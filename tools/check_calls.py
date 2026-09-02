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
# A bare `_helper(` — a call on self, with nothing in front of it to say so.
own_call_re = re.compile(r"(?<![\w.$\"])(_\w+)\s*\(")

# A whole function signature, so the declared type of each parameter is known.
signature_re = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)", re.M)
# `thing.method(` where `thing` is a lower-case identifier -- a typed member, so
# its class can be resolved from `var thing := SomeClass.new()` in the same file.
member_call_re = re.compile(r"(?<![\w.$\"])([a-z_]\w*)\s*\.\s*(\w+)\s*\(")
# `var thing := SomeClass.new()` and `var thing: SomeClass`
typed_var_re = re.compile(r"^var\s+(\w+)\s*:?=?\s*([A-Z]\w+)\.new\(\)", re.M)
typed_decl_re = re.compile(r"^var\s+(\w+)\s*:\s*([A-Z]\w+)", re.M)

# What a literal argument obviously IS. Anything not obvious is left alone.
LITERAL_FLOAT = re.compile(r"^-?\d+\.\d+$")
LITERAL_INT = re.compile(r"^-?\d+$")
LITERAL_STRING = re.compile(r'^(?:"[^"]*"|\'[^\']*\')$')
LITERAL_BOOL = re.compile(r"^(?:true|false)$")
LITERAL_DICT = re.compile(r"^\{.*\}$")
LITERAL_ARRAY = re.compile(r"^\[.*\]$")


def literal_type(text):
    """The type of an argument, when it is unmistakable. None otherwise."""
    text = text.strip()
    if LITERAL_FLOAT.match(text):
        return "float"
    if LITERAL_INT.match(text):
        return "int"
    if LITERAL_STRING.match(text):
        return "String"
    if LITERAL_BOOL.match(text):
        return "bool"
    if LITERAL_DICT.match(text):
        return "Dictionary"
    if LITERAL_ARRAY.match(text):
        return "Array"
    return None


# Types a literal may legitimately be handed to.
COMPATIBLE = {
    "float": {"float", "Variant"},
    "int": {"int", "float", "Variant"},
    "String": {"String", "StringName", "Variant"},
    "bool": {"bool", "Variant"},
    "Dictionary": {"Dictionary", "Variant"},
    "Array": {"Array", "Variant"},
}


def parse_params(raw):
    """[(name, declared type or None)] for one parameter list."""
    params = []
    depth = 0
    current = ""
    for ch in raw + ",":
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            piece = current.strip()
            current = ""
            if not piece:
                continue
            head = piece.split("=")[0].strip()
            if ":" in head:
                name, kind = head.split(":", 1)
                params.append((name.strip(), kind.strip()))
            else:
                # `name := default` -- the type is whatever the default is.
                default = piece.split("=", 1)[1].strip() if "=" in piece else ""
                params.append((head.rstrip(":"), literal_type(default)))
            continue
        current += ch
    return params


def split_args(raw):
    """Top-level arguments of one call, ignoring nested brackets and strings.

    An empty list for `foo()` -- not one empty argument, which would make every
    no-argument call in the project look like it was passed something.
    """
    if raw.lstrip().startswith(")"):
        return []
    args = []
    depth = 0
    quote = ""
    current = ""
    for ch in raw:
        if quote:
            current += ch
            if ch == quote:
                quote = ""
            continue
        if ch in "\"'":
            quote = ch
            current += ch
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                args.append(current)
                return args
            depth -= 1
        if ch == "," and depth == 0:
            args.append(current)
            current = ""
            continue
        current += ch
    args.append(current)
    return args

# Godot calls these on us; we never declare all of them.
ENGINE_VIRTUALS = {
    "_ready", "_init", "_process", "_physics_process", "_input", "_draw",
    "_unhandled_input", "_unhandled_key_input", "_gui_input", "_notification",
    "_enter_tree", "_exit_tree", "_to_string", "_get", "_set",
    "_get_property_list", "_integrate_forces", "_get_configuration_warnings",
}


def collect(root):
    """class name -> (members, base class name)."""
    classes = {}
    SIGNATURES.clear()
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
            for fname, raw in signature_re.findall(src):
                SIGNATURES[(m.group(1), fname)] = parse_params(raw)
    return classes


# (class, method) -> [(param name, declared type or None)]. Filled by collect().
SIGNATURES = {}


def signature_of(cls, method, classes, seen=None):
    """A method's parameters, following the chain of project base classes."""
    seen = seen or set()
    if cls in seen or cls not in classes:
        return None
    seen.add(cls)
    if (cls, method) in SIGNATURES:
        return SIGNATURES[(cls, method)]
    return signature_of(classes[cls][1], method, classes, seen)


def check_arguments(cls, method, raw_args, classes):
    """Does this call hand an obviously-wrong literal to a typed parameter?

    Narrow on purpose: only unmistakable literals against explicitly declared
    types. That is enough, because the bug this exists for is CHANGING A
    SIGNATURE and missing a call site -- `judge(-0.20)` where the first
    parameter has become `verb: String`. gdparse does not type-check and gdlint
    does not either, so nine of those once reached the player at once.
    """
    params = signature_of(cls, method, classes)
    if params is None:
        return None
    args = split_args(raw_args)
    if len(args) > len(params):
        return "%s.%s() takes %d argument(s), given %d" % (
            cls, method, len(params), len(args))
    for i, arg in enumerate(args):
        got = literal_type(arg)
        wanted = params[i][1]
        if got is None or not wanted:
            continue
        if wanted not in COMPATIBLE.get(got, {wanted}):
            return "%s.%s() argument %d (%s) is declared %s, given a %s" % (
                cls, method, i + 1, params[i][0], wanted, got)
    return None


def members_of(cls, classes, seen=None):
    """Members of a class plus everything it inherits from a project class."""
    seen = seen or set()
    if cls in seen or cls not in classes:
        return set()
    seen.add(cls)
    members, base = classes[cls]
    return members | members_of(base, classes, seen)


def own_members(path, src, classes):
    """Everything a script may call on itself: what it declares, plus whatever
    it inherits from a project class it extends."""
    members = set()
    for rx in (func_re, var_re, const_re, signal_re, enum_re):
        members |= set(rx.findall(src))
    base = extends_re.search(src)
    if base:
        members |= members_of(base.group(1), classes)
    return members


def check(paths, classes):
    problems = []
    for path in paths:
        src = open(path, encoding="utf-8").read()
        mine = own_members(path, src, classes)
        # `var mind := CreatureMind.new()` tells us what `mind.judge(...)` is a
        # call to, which is what makes argument checking possible at all.
        typed = dict(typed_var_re.findall(src))
        typed.update(dict(typed_decl_re.findall(src)))
        for lineno, line in enumerate(src.split("\n"), 1):
            if line.lstrip().startswith("#"):
                continue
            for rx in (cast_call_re, static_call_re):
                for cls, method in rx.findall(line):
                    if cls not in classes or method in BUILTIN:
                        continue
                    if method not in members_of(cls, classes):
                        problems.append((path, lineno, cls, method, line.strip()))
            # ARGUMENTS. Only for calls whose class is known: a static call
            # (`CreatureEthos.kindness(...)`) or a call on a member declared
            # with a project type (`mind.judge(...)`).
            for m in static_call_re.finditer(line) or []:
                _flag_args(problems, path, lineno, line, classes,
                           m.group(1), m.group(2), line[m.end():])
            for m in member_call_re.finditer(line):
                cls = typed.get(m.group(1))
                if cls:
                    _flag_args(problems, path, lineno, line, classes,
                               cls, m.group(2), line[m.end():])
            # A call on SELF to a private helper that is not there. This is the
            # bug that keeps reaching the player: delete or rename a `_helper`
            # and every call to it still parses, still lints, and still fails
            # the moment the line runs. Restricted to underscore names because
            # those are ours by convention -- an unprefixed bare call could be
            # any of hundreds of engine methods we do not enumerate.
            for method in own_call_re.findall(line):
                if method in ENGINE_VIRTUALS or method in mine or method in BUILTIN:
                    continue
                if ("func " + method) in src:
                    continue
                problems.append((path, lineno, "self", method, line.strip()))
    return problems


def _flag_args(problems, path, lineno, line, classes, cls, method, rest):
    if cls not in classes or method in BUILTIN:
        return
    # Only when the whole argument list is on this one line; a call wrapped
    # across lines is left alone rather than guessed at.
    if ")" not in rest:
        return
    complaint = check_arguments(cls, method, rest, classes)
    if complaint:
        problems.append((path, lineno, complaint, "", line.strip()))


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


def check_format_precedence(files):
    """Find `"a" + "b" % [args]` — a crash that gdparse and gdlint both pass.

    `%` binds tighter than `+` in GDScript, so a format string split across
    lines with `+` formats ONLY THE LAST PIECE, and every placeholder in the
    earlier pieces goes unfilled. Godot then raises "not all arguments
    converted during string formatting" the moment that line runs. It has
    already cost this project two crashes, and it is invisible to both the
    parser and the linter because the code is perfectly valid.

    The fix is always the same: wrap the whole concatenation in parentheses.
    """
    problems = []
    # A continuation line that starts with `+ "` and ends with a `%` format.
    joined = re.compile(r'^\s*\+\s*"')
    formatted = re.compile(r'"\s*%\s*[\[(]')
    for path in files:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                if line.lstrip().startswith("#"):
                    continue
                if joined.match(line) and formatted.search(line):
                    problems.append((path, lineno, line.strip()))
    return problems


def check_shadowed_vars(files):
    """Find `var x` declared twice where the first is still in scope.

    GDScript rejects it outright ("There is already a variable named x declared
    in this scope"), and gdparse does not, so it takes the whole class down at
    load time. It happens when a long function grows a second helper variable
    with an obvious name -- `quiet`, `folk` -- and it has cost this project two
    failed launches.

    Scope is tracked by indentation, which is all GDScript has: any line at a
    shallower indent than a declaration ends the block that declaration lived
    in, so two sibling `for` loops may each have their own `var up` and only a
    genuine redeclaration is reported.
    """
    problems = []
    var_line = re.compile(r"^(\s*)var\s+(\w+)")
    func_line = re.compile(r"^(?:static\s+)?func\s")
    for path in files:
        live = []      # [(indent, name, lineno)] still in scope, outermost first
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                if func_line.match(line):
                    live = []                      # a new function is a new scope
                    continue
                bare = line.rstrip()
                if not bare.strip() or bare.lstrip().startswith("#"):
                    continue
                indent = len(bare[:len(bare) - len(bare.lstrip())].expandtabs(4))
                # Anything at this indent has closed every deeper block.
                live = [e for e in live if e[0] <= indent]
                m = var_line.match(line)
                if not m or indent == 0:
                    continue                       # indent 0 is a class member
                name = m.group(2)
                clash = next((e for e in live if e[1] == name), None)
                if clash:
                    problems.append((path, lineno, name, clash[2], line.strip()))
                else:
                    live.append((indent, name, lineno))
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
        what = ("%s has no member '%s'" % (cls, method)) if method else cls
        print("%s:%d: %s\n    %s" % (path, lineno, what, line))
    escapes = check_escapes(files)
    for path, lineno, seq, line in escapes:
        print("%s:%d: invalid string escape '%s' (Godot rejects it; gdparse does not)"
              "\n    %s" % (path, lineno, seq, line))
    shadowed = check_shadowed_vars(files)
    for path, lineno, name, first, line in shadowed:
        print("%s:%d: '%s' is already declared in this scope (line %d) — Godot "
              "rejects this at load time\n    %s" % (path, lineno, name, first, line))
    formats = check_format_precedence(files)
    for path, lineno, line in formats:
        print("%s:%d: '%%' binds tighter than '+', so only the LAST piece of this "
              "string is formatted — wrap the whole concatenation in parentheses"
              "\n    %s" % (path, lineno, line))
    total = len(problems) + len(escapes) + len(formats) + len(shadowed)
    print("checked %d classes across %d files — %d problem(s)"
          % (len(classes), len(files), total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
