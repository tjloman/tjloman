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
    "get_tree", "get_node", "get_node_or_null", "find_children",
    "is_inside_tree", "set_meta",
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
# `CreatureBody.NOURISHMENT` — a CONSTANT read off a class, with no call
# brackets after it. The call checks above all end in `(`, so a renamed or
# deleted constant sailed through every one of them: `main.gd` went on
# referring to a NOURISHMENT that the digestion rework had removed, and the
# game would not load. Reading a member is exactly as breakable as calling one.
static_member_re = re.compile(r"(?<![\w.$\"])([A-Z]\w+)\s*\.\s*(\w+)\b(?!\s*\()")
# Double-quoted text, stripped before that regex runs so a class name inside a
# string is not mistaken for a real reference.
quoted_re = re.compile(r'"[^"]*"')
# A bare `_helper(` — a call on self, with nothing in front of it to say so.
own_call_re = re.compile(r"(?<![\w.$\"])(_\w+)\s*\(")

# A whole function signature, so the declared type of each parameter is known.
signature_re = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)", re.M)
# A whole dotted path before a call: `mind.judge(`, `wronged.mind.judge(`,
# `creature.mind.beliefs.creed(`. Resolved left to right, one member at a time,
# which is what it takes to catch a bad argument two levels down.
member_call_re = re.compile(r"(?<![\w.$\"])([a-z_]\w*(?:\s*\.\s*\w+)+)\s*\(")
# `var thing := SomeClass.new()` and `var thing: SomeClass`, at column 0 --
# these are the CLASS MEMBERS, which is what a dotted chain walks through.
typed_var_re = re.compile(r"^var\s+(\w+)\s*:?=?\s*([A-Z]\w+)\.new\(\)", re.M)
typed_decl_re = re.compile(r"^var\s+(\w+)\s*:\s*([A-Z]\w+)", re.M)
# The same, at ANY indent, so locals declared inside a function are resolved
# too. Leaving this out is why `wronged.mind.judge(0.8, ...)` in a smoke test
# sailed past the checker and stopped the game compiling.
local_var_re = re.compile(r"^\s*var\s+(\w+)\s*:?=?\s*([A-Z]\w+)\.new\(\)", re.M)
local_decl_re = re.compile(r"^\s*var\s+(\w+)\s*:\s*([A-Z]\w+)", re.M)

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
    MEMBER_TYPES.clear()
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
            here = dict(typed_var_re.findall(src))
            here.update(dict(typed_decl_re.findall(src)))
            MEMBER_TYPES[m.group(1)] = here
    return classes


# (class, method) -> [(param name, declared type or None)]. Filled by collect().
SIGNATURES = {}
# class -> {member name -> class}, so a dotted call chain can be followed.
MEMBER_TYPES = {}


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
        # call to, which is what makes argument checking possible at all. Locals
        # count, so a smoke test's `var wronged := Creature.new()` resolves too.
        #
        # A name declared as two different classes anywhere in the file is
        # AMBIGUOUS -- two functions may each have their own `var v` -- so it is
        # dropped rather than guessed at. Silence beats a false alarm.
        typed = {}
        ambiguous = set()
        for rx in (local_var_re, local_decl_re):
            for word, kind in rx.findall(src):
                if word in typed and typed[word] != kind:
                    ambiguous.add(word)
                typed[word] = kind
        for word in ambiguous:
            typed.pop(word, None)
        for lineno, line in enumerate(src.split("\n"), 1):
            if line.lstrip().startswith("#"):
                continue
            for rx in (cast_call_re, static_call_re):
                for cls, method in rx.findall(line):
                    if cls not in classes or method in BUILTIN:
                        continue
                    if method not in members_of(cls, classes):
                        problems.append((path, lineno, cls, method, line.strip()))
            # The same question for a member READ rather than a call.
            for cls, name in static_member_re.findall(quoted_re.sub('""', line)):
                if cls not in classes or name in BUILTIN:
                    continue
                if name not in members_of(cls, classes):
                    problems.append((path, lineno, cls, name, line.strip()))
            # ARGUMENTS. Only for calls whose class is known: a static call
            # (`CreatureEthos.kindness(...)`) or a call on a member declared
            # with a project type (`mind.judge(...)`).
            for m in static_call_re.finditer(line) or []:
                _flag_args(problems, path, lineno, line, classes,
                           m.group(1), m.group(2), line[m.end():])
            for m in member_call_re.finditer(line):
                chain = [p.strip() for p in m.group(1).split(".")]
                cls = _walk_chain(chain, typed, classes)
                if cls:
                    _flag_args(problems, path, lineno, line, classes,
                               cls, chain[-1], line[m.end():])
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


def _walk_chain(chain, local_types, classes):
    """Follow `a.b.c.method` to the class `method` is actually called on.

    `a` comes from a typed declaration in this file; every step after that from
    the declared member types of the class before it. Returns None the moment a
    link cannot be resolved, so anything uncertain is simply not checked.
    """
    cls = local_types.get(chain[0])
    for step in chain[1:-1]:
        if cls is None:
            return None
        cls = MEMBER_TYPES.get(cls, {}).get(step)
    return cls


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


def check_untyped_array_results(files):
    """Find a typed array assigned the result of filter()/map()/slice().

    These return a PLAIN `Array`, whatever they were called on, so

        _clouds = _clouds.filter(func(c): return is_instance_valid(c))

    where `_clouds` is an `Array[StormCloud]` fails at RUNTIME with "Trying to
    assign an array of type Array to a variable of type Array[StormCloud]" --
    and only on the frame that line first runs, which in practice meant a
    miracle that had shipped and could not be cast.

    gdparse does not catch it, and nor does the editor: the type error is
    raised when the assignment executes. So it is caught here, by remembering
    which names were declared as typed arrays.
    """
    problems = []
    typed_array = re.compile(r"^\s*var\s+(\w+)\s*:\s*Array\[")
    loose = re.compile(r"^\s*(\w+)\s*=\s*.*\.(filter|map|slice)\s*\(")
    for path in files:
        typed = set()
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
        for line in lines:
            m = typed_array.match(line)
            if m:
                typed.add(m.group(1))
        for lineno, line in enumerate(lines, 1):
            m = loose.match(line)
            if m and m.group(1) in typed:
                problems.append((path, lineno, m.group(1), m.group(2), line.strip()))
    return problems


# Container methods GDScript declares as returning Variant, even when called on
# a TYPED array. Inferring a variable's type from one of these gives Variant.
VARIANT_RETURNS = ("pop_back", "pop_front", "pop_at", "front", "back",
                   "pick_random", "get")


def check_inferred_variant(files):
    """Find `var x := <container>.pop_back()` and friends.

    This project builds with untyped declarations treated as errors, so

        var gone := _lights.pop_back()

    fails to COMPILE with "The variable type is being inferred from a Variant
    value" -- and it takes the whole dependency chain down with it, so one
    line in one file stops main.gd loading. gdparse does not catch it, because
    it does no type inference at all.

    Only flagged when the call is the WHOLE right-hand side: wrapping it, as
    `float(ep.get("worth", 0.0))` does throughout, is exactly the fix and must
    not be reported.
    """
    problems = []
    inferred = re.compile(
        r"^\s*var\s+\w+\s*:=\s*[\w\.\[\]\"']+\.(%s)\([^()]*\)\s*(?:#.*)?$"
        % "|".join(VARIANT_RETURNS))
    for path in files:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                m = inferred.match(line.rstrip())
                if m:
                    problems.append((path, lineno, m.group(1), line.strip()))
    return problems


## THE SAME BUILD ERROR, ARRIVING A THIRD WAY.
##
## `check_inferred_variant` above catches `var x := thing.pop_back()`. It does
## not catch this, which shipped twice in one commit:
##
##     for step in [Vector2i(1, 0), Vector2i(-1, 0)]:
##         var next := cell + step        # step is Variant, so next is Variant
##
## An untyped array literal has element type Variant, so the loop variable is a
## Variant, so anything inferred from it is a Variant — and this project builds
## that as an ERROR that takes every dependent script down with it. `gdparse`
## does not catch it and `gdlint` does not either; only Godot does, at load.
##
## The fix is always the same and always trivial: name the element type on the
## `for`, as `for step: Vector2i in [...]`.
def check_untyped_loop_vars(files):
    loop = re.compile(r"^(\s*)for\s+(\w+)\s+in\s+\[")
    typed = re.compile(r"^\s*for\s+\w+\s*:")
    infer = re.compile(r"^(\s*)var\s+(\w+)\s*:=\s*(.+?)\s*(?:#.*)?$")
    problems = []
    for path in files:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        open_loops = []          # (indent of the `for`, loop variable name)
        for lineno, line in enumerate(lines, 1):
            if not line.strip() or line.strip().startswith("#"):
                continue
            indent = len(line) - len(line.lstrip())
            open_loops = [(d, n) for d, n in open_loops if indent > d]
            m = loop.match(line)
            if m and not typed.match(line):
                open_loops.append((len(m.group(1)), m.group(2)))
                continue
            m = infer.match(line)
            if not m or not open_loops:
                continue
            bare = _outside_calls(m.group(3))
            for _d, name in open_loops:
                if re.search(r"\b%s\b" % re.escape(name), bare):
                    problems.append((path, lineno, name, line.strip()))
                    break
    return problems


## What is left of an expression once every call and constructor argument list
## is taken out of it — which is precisely where a Variant does NOT leak.
##
## This distinction is the whole rule. `var cell := center + Vector2i(dx, dz)`
## is FINE however Variant `dx` is, because `Vector2i(...)` is a Vector2i
## whatever you feed it, and so is `Util.sphere(0.12, ..., 0.18 * side)`. It is
## only when the loop variable is out in the open — `var next := cell + step` —
## that the inferred type becomes Variant and the build stops. Without this the
## rule fired on six lines that have compiled happily for months.
def _outside_calls(expr):
    while True:
        stripped = re.sub(r"\([^()]*\)", "()", expr)
        if stripped == expr:
            return expr
        expr = stripped


# Members of Godot's own node classes that scripts here plausibly name a local
# or a parameter after. Godot warns on the shadow but the build does not fail,
# so it reaches the player as noise — and worse, a later edit that MEANT the
# node's own property silently gets the local instead.
#
# Curated rather than exhaustive: this is the set of names a person actually
# reaches for. `show`, `basis` and `scale` have each shipped.
BASE_MEMBERS = {
    "Object": {"free", "name"},
    "Node": {"name", "owner", "process_mode", "scene_file_path", "multiplayer"},
    "CanvasItem": {"visible", "modulate", "self_modulate", "material", "show",
                   "hide", "z_index", "top_level", "draw", "light_mask"},
    "Node2D": {"position", "rotation", "scale", "skew", "transform",
               "global_position", "global_rotation"},
    "Control": {"position", "size", "scale", "rotation", "pivot_offset", "theme",
                "tooltip_text", "focus_mode", "mouse_filter", "anchor_left",
                "custom_minimum_size", "clip_contents"},
    # `show` and `hide` are on Node3D as well as CanvasItem — leaving them off
    # here is why the first run of this rule missed the `show` parameter that
    # actually shipped.
    "Node3D": {"position", "rotation", "scale", "basis", "transform", "visible",
               "global_position", "global_transform", "global_rotation",
               "quaternion", "top_level", "show", "hide"},
    "CollisionObject3D": {"collision_layer", "collision_mask", "input_ray_pickable"},
    "PhysicsBody3D": {"axis_lock_linear_x"},
    "RigidBody3D": {"mass", "freeze", "linear_velocity", "angular_velocity",
                    "gravity_scale", "physics_material_override", "inertia"},
    "CharacterBody3D": {"velocity", "motion_mode", "up_direction", "floor_snap_length"},
    "GeometryInstance3D": {"transparency", "cast_shadow", "material_override"},
    "MeshInstance3D": {"mesh", "skeleton", "skin"},
    "Light3D": {"light_color", "light_energy", "shadow_enabled", "light_specular"},
    "Camera3D": {"far", "near", "fov", "projection"},
    "CanvasLayer": {"layer", "offset", "follow_viewport_enabled"},
}

# What each base pulls in from above it.
INHERITS = {
    "Node": ["Object"],
    "CanvasItem": ["Node", "Object"],
    "Node2D": ["CanvasItem", "Node", "Object"],
    "Control": ["CanvasItem", "Node", "Object"],
    "CanvasLayer": ["Node", "Object"],
    "Node3D": ["Node", "Object"],
    "GeometryInstance3D": ["Node3D", "Node", "Object"],
    "MeshInstance3D": ["GeometryInstance3D", "Node3D", "Node", "Object"],
    "Light3D": ["Node3D", "Node", "Object"],
    "OmniLight3D": ["Light3D", "Node3D", "Node", "Object"],
    "SpotLight3D": ["Light3D", "Node3D", "Node", "Object"],
    "Camera3D": ["Node3D", "Node", "Object"],
    "CollisionObject3D": ["Node3D", "Node", "Object"],
    "PhysicsBody3D": ["CollisionObject3D", "Node3D", "Node", "Object"],
    "RigidBody3D": ["PhysicsBody3D", "CollisionObject3D", "Node3D", "Node", "Object"],
    "CharacterBody3D": ["PhysicsBody3D", "CollisionObject3D", "Node3D", "Node", "Object"],
    "StaticBody3D": ["PhysicsBody3D", "CollisionObject3D", "Node3D", "Node", "Object"],
    "Area3D": ["CollisionObject3D", "Node3D", "Node", "Object"],
}


def _inherited_members(base):
    names = set(BASE_MEMBERS.get(base, ()))
    for parent in INHERITS.get(base, []):
        names |= set(BASE_MEMBERS.get(parent, ()))
    return names


def check_shadowed_members(files):
    """Find locals and parameters named after a property of the node's base.

    A script that `extends Node3D` and declares `var scale` shadows the node's
    own scale. Godot warns; the project still runs; and the next person to
    write `scale.y = 2` in that function silently sets a float they meant to
    read. Three of these have shipped.

    Only names the base class ACTUALLY has are flagged, resolved through the
    file's own `extends` — a plain RefCounted helper may call a local `name`
    all it likes.
    """
    problems = []
    var_line = re.compile(r"^(\s+)var\s+(\w+)")
    func_line = re.compile(r"^(?:static\s+)?func\s+\w+\(([^)]*)")
    for path in files:
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        m = re.search(r"^extends\s+(\w+)", src, re.M)
        if not m:
            continue
        members = _inherited_members(m.group(1))
        if not members:
            continue
        for lineno, line in enumerate(src.splitlines(), 1):
            hit = var_line.match(line)
            if hit and hit.group(2) in members:
                problems.append((path, lineno, hit.group(2), m.group(1), line.strip()))
                continue
            sig = func_line.match(line)
            if sig:
                for part in sig.group(1).split(","):
                    arg = part.strip().split(":")[0].split("=")[0].strip()
                    if arg in members:
                        problems.append((path, lineno, arg, m.group(1), line.strip()))
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
    shadowed_members = check_shadowed_members(files)
    for path, lineno, nm, base, line in shadowed_members:
        print("%s:%d: '%s' shadows a property of the base class %s — Godot warns, and "
              "a later edit meaning the node's own '%s' would silently get this "
              "instead\n    %s" % (path, lineno, nm, base, nm, line))
    loose_arrays = check_untyped_array_results(files)
    for path, lineno, name, call, line in loose_arrays:
        print("%s:%d: %s() returns a plain Array, and '%s' is a TYPED array — this "
              "fails at runtime on the frame it first runs. Build the new array with "
              "a loop instead.\n    %s" % (path, lineno, call, name, line))
    variants = check_inferred_variant(files)
    for path, lineno, call, line in variants:
        print("%s:%d: %s() is declared as returning Variant, so ':=' infers a "
              "Variant here — this project builds that as an ERROR and it stops "
              "every dependent script loading. Declare the type, or wrap the "
              "call.\n    %s" % (path, lineno, call, line))
    loop_vars = check_untyped_loop_vars(files)
    for path, lineno, name, line in loop_vars:
        print("%s:%d: '%s' comes from an UNTYPED array literal, so it is a "
              "Variant and ':=' infers a Variant here — Godot builds that as an "
              "error that stops every dependent script loading. Name the element "
              "type: `for %s: <Type> in [...]`.\n    %s"
              % (path, lineno, name, name, line))
    total = len(problems) + len(escapes) + len(formats) + len(shadowed) \
        + len(loose_arrays) + len(variants) + len(shadowed_members) \
        + len(loop_vars)
    print("checked %d classes across %d files — %d problem(s)"
          % (len(classes), len(files), total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
