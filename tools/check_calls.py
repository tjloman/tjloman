#!/usr/bin/env python3
"""Catch calls to methods that do not exist on the target class.

gdparse only checks syntax and gdlint only checks style, so a call like
`(v as Villager).hurt_by(...)` sails through both and then crashes at runtime
the moment that code path is hit. This walks every `class_name` script,
collects the methods (and properties) each one declares, then flags calls made
through an explicit class reference that no such member exists for.

    python3 tools/check_calls.py            # whole project
    python3 tools/check_calls.py scripts/x  # one file or directory

Deliberately conservative: it only reports calls it can attribute to a class
with confidence, so a clean run is meaningful and a hit is nearly always real.
"""

import os
import re
import sys

# Members every Node/Object already has that scripts legitimately call.
BUILTIN = {
    "queue_free", "free", "is_queued_for_deletion", "get_instance_id",
    "add_child", "remove_child", "get_parent", "get_children", "get_child",
    "get_tree", "get_node", "find_children", "is_inside_tree", "set_meta",
    "get_meta", "has_meta", "remove_meta", "add_to_group", "is_in_group",
    "remove_from_group", "connect", "disconnect", "emit_signal", "call",
    "call_deferred", "has_method", "get", "set", "duplicate", "to_local",
    "to_global", "look_at", "rotate_y", "global_rotate", "translate",
    "get_class", "is_class", "set_process", "set_physics_process",
    "move_and_slide", "is_on_floor", "is_on_wall", "get_world_3d",
    "get_viewport", "add_theme_font_size_override", "propagate_call",
    "surface_get_material", "get_surface_override_material", "instantiate",
    "get_overlapping_bodies", "get_overlapping_areas", "set_deferred",
    "new",  # every class has its constructor
    "add_theme_color_override", "add_theme_stylebox_override",
    "add_theme_constant_override", "set_anchors_preset", "reparent",
    "set_anchors_and_offsets_preset", "find_blend_shape_by_name",
    "set_blend_shape_value", "set_instance_shader_parameter",
}

decl_re = re.compile(r"^class_name\s+(\w+)", re.M)
func_re = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(", re.M)
var_re = re.compile(r"^var\s+(\w+)", re.M)
const_re = re.compile(r"^const\s+(\w+)", re.M)
signal_re = re.compile(r"^signal\s+(\w+)", re.M)
enum_re = re.compile(r"^enum\s+(\w+)", re.M)
extends_re = re.compile(r"^extends\s+(\w+)", re.M)

# `(x as Villager).foo(` and `Weapon.foo(`
cast_call_re = re.compile(r"\bas\s+(\w+)\s*\)\s*\.\s*(\w+)\s*\(")
static_call_re = re.compile(r"(?<![\w.])([A-Z]\w+)\s*\.\s*(\w+)\s*\(")


def collect(root):
    """class name -> (members, base class name)."""
    classes = {}
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(dirpath, name)
            src = open(path, encoding="utf-8").read()
            m = decl_re.search(src)
            if not m:
                continue
            members = set()
            for rx in (func_re, var_re, const_re, signal_re, enum_re):
                members |= set(rx.findall(src))
            base = extends_re.search(src)
            classes[m.group(1)] = (members, base.group(1) if base else None)
    return classes


def members_of(cls, classes, seen=None):
    """Members of a class plus everything it inherits from a project class."""
    seen = seen or set()
    if cls in seen or cls not in classes:
        return set()
    seen.add(cls)
    members, base = classes[cls]
    return members | members_of(base, classes, seen)


def check(paths, classes):
    problems = []
    for path in paths:
        src = open(path, encoding="utf-8").read()
        for lineno, line in enumerate(src.split("\n"), 1):
            if line.lstrip().startswith("#"):
                continue
            for rx in (cast_call_re, static_call_re):
                for cls, method in rx.findall(line):
                    if cls not in classes or method in BUILTIN:
                        continue
                    if method not in members_of(cls, classes):
                        problems.append((path, lineno, cls, method, line.strip()))
    return problems


# Escapes GDScript actually understands. Anything else after a backslash in a
# string literal is a parse error in Godot -- and gdparse does NOT catch it, so
# a stray "\" in help text takes the whole class down at load time with an
# error that names only the line, not the character.
VALID_ESCAPES = set('abfnrtv"\'\\uUxU0123456789\n')


def check_escapes(files):
    """Find invalid string escapes: the one class of syntax error gdparse misses."""
    problems = []
    for path in files:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                stripped = line.lstrip()
                # Comments and doc comments are not string literals.
                if stripped.startswith("#"):
                    continue
                # A backslash at end of line is GDScript's line continuation.
                body = line.rstrip("\n")
                i = 0
                while True:
                    i = body.find("\\", i)
                    if i < 0 or i == len(body) - 1:
                        break
                    nxt = body[i + 1]
                    if nxt not in VALID_ESCAPES:
                        problems.append((path, lineno, "\\" + nxt, line.strip()))
                    i += 2
    return problems


def main():
    root = "scripts"
    targets = sys.argv[1:] or [root]
    classes = collect(root)
    files = []
    for t in targets:
        if os.path.isfile(t):
            files.append(t)
        else:
            for dirpath, _d, names in os.walk(t):
                files += [os.path.join(dirpath, n) for n in names if n.endswith(".gd")]
    problems = check(files, classes)
    for path, lineno, cls, method, line in problems:
        print("%s:%d: %s has no member '%s'\n    %s" % (path, lineno, cls, method, line))
    escapes = check_escapes(files)
    for path, lineno, seq, line in escapes:
        print("%s:%d: invalid string escape '%s' (Godot rejects it; gdparse does not)"
              "\n    %s" % (path, lineno, seq, line))
    total = len(problems) + len(escapes)
    print("checked %d classes across %d files — %d problem(s)"
          % (len(classes), len(files), total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
