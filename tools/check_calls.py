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
    "get_child_count", "get_index", "get_groups", "is_ancestor_of", "reparent",
    "set_process_unhandled_input", "set_process_input", "set_process_internal",
    "move_and_slide", "is_on_floor", "is_on_wall", "get_world_3d",
    "get_viewport", "add_theme_font_size_override", "propagate_call",
    "surface_get_material", "get_surface_override_material", "instantiate",
    "get_overlapping_bodies", "get_overlapping_areas", "set_deferred",
    "new",  # every class has its constructor
    "add_theme_color_override", "add_theme_stylebox_override",
    "add_theme_constant_override", "set_anchors_preset", "reparent",
    "set_anchors_and_offsets_preset", "find_blend_shape_by_name",
    "set_blend_shape_value", "set_instance_shader_parameter",
    # Viewport's own. get_texture is how anything looks at what a SubViewport
    # drew — see Temple, which hangs the temple room on a TextureRect.
    "get_texture", "get_visible_rect", "set_input_as_handled",
    "get_node_count_in_group", "get_first_node_in_group", "get_nodes_in_group",
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
static_func_re = re.compile(r"^static\s+func\s+(\w+)\s*\(", re.M)
# `SomeClass.method(` — a call made THROUGH a class name rather than an object.
through_class_re = re.compile(r"(?<![\w.])([A-Z]\w*)\.(\w+)\s*\(")
# `SomeClass.field` with no call after it — reaching an instance VARIABLE
# through a class name, which fails for exactly the same reason.
through_class_var_re = re.compile(r"(?<![\w.])([A-Z]\w*)\.(\w+)\s*(?!\s*\()")
# A call with nothing before it: this script calling its own method.
bare_call_re = re.compile(r"(?<![\w.$])([a-z_]\w*)\s*\(")
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
# A TYPED FUNCTION PARAMETER. `static func lounge(who: Creature, delta: float)`
# says what `who` is just as plainly as a `var` does — and this whole project
# is written that way: CreatureLeisure, CreatureThrowing, CreatureWatching,
# Militia and Sling all take `who` and reach into it. Without this, NONE of
# those calls were ever checked against the class they were calling on, which
# is how `who._audience(20.0)` survived `_audience` being moved out of Creature
# and took every dependent script down at load.
param_type_re = re.compile(r"(?<![\w.])(\w+)\s*:\s*([A-Z]\w+)")

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
            OWN_FUNCS[m.group(1)] = set(func_re.findall(src))
            for fname in static_func_re.findall(src):
                STATICS.add((m.group(1), fname))
            OWN_VARS[m.group(1)] = set(var_re.findall(src))
            here = dict(typed_var_re.findall(src))
            here.update(dict(typed_decl_re.findall(src)))
            MEMBER_TYPES[m.group(1)] = here
    return classes


# (class, method) -> [(param name, declared type or None)]. Filled by collect().
SIGNATURES = {}
# (class, method) pairs declared `static func`. Filled by collect().
STATICS = set()
# Every func a class declares, static or not. Filled by collect().
OWN_FUNCS = {}
# Every INSTANCE var a class declares (static vars and consts excluded — those
# are reachable through the class name and always were). Filled by collect().
OWN_VARS = {}
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
        own = decl_re.search(src)
        mine_class = own.group(1) if own else None
        # `var mind := CreatureMind.new()` tells us what `mind.judge(...)` is a
        # call to, which is what makes argument checking possible at all. Locals
        # count, so a smoke test's `var wronged := Creature.new()` resolves too.
        #
        # A name declared as two different classes anywhere in the file is
        # AMBIGUOUS -- two functions may each have their own `var v` -- so it is
        # dropped rather than guessed at. Silence beats a false alarm.
        # EVERY TYPE A NAME IS EVER GIVEN IN THIS FILE, engine types included.
        # The engine ones are never USED to resolve a call — this project knows
        # nothing about Array's members — but they must still count toward
        # AMBIGUITY, or a file with `tree: SceneTree` in one function and
        # `tree: WildTree` in another quietly resolves every `tree.` in it to
        # whichever of the two happened to be a project class.
        bindings = {}
        for rx in (local_var_re, local_decl_re):
            for word, kind in rx.findall(src):
                bindings.setdefault(word, set()).add(kind)
        for _fname, raw in signature_re.findall(src):
            for word, kind in param_type_re.findall(raw):
                bindings.setdefault(word, set()).add(kind)
        typed = {}
        ambiguous = set()
        for word, kinds in bindings.items():
            if len(kinds) != 1:
                ambiguous.add(word)
                continue
            typed[word] = list(kinds)[0]
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
            # AND A CALL THE SCRIPT MAKES ON ITSELF. `_move_toward(a, b, c, d)`
            # inside the class that declares `_move_toward(a, b, c)` was never
            # argument-checked at all: the class was only ever "known" for a
            # dotted call, so the one kind of call a file makes most of the time
            # was the one kind nobody looked at. Godot rejects it at parse time,
            # and it is exactly the mistake of copying a line from a sibling
            # class whose version of the method takes one more parameter.
            if mine_class:
                for m in bare_call_re.finditer(line):
                    if (mine_class, m.group(1)) not in SIGNATURES:
                        continue
                    _flag_args(problems, path, lineno, line, classes,
                               mine_class, m.group(1), line[m.end():])
            for m in member_call_re.finditer(line):
                chain = [p.strip() for p in m.group(1).split(".")]
                cls = _walk_chain(chain, typed, classes)
                # DOES THE METHOD EVEN EXIST? This asked only about ARGUMENTS.
                # So `who._audience(20.0)`, on a `who: Creature` parameter,
                # went on being checked for argument count long after
                # `_audience` had been moved out of Creature entirely — and the
                # one kind of call this project makes most (a helper class
                # reaching into the `who` it was handed) was the one kind
                # nobody ever asked the first question about.
                # `cls in classes` matters: _walk_chain happily hands back
                # engine types too (`var _runes: Array`), and this project has
                # no idea what Array's members are.
                if cls in classes and chain[-1] not in BUILTIN \
                        and chain[-1] not in members_of(cls, classes):
                    problems.append((path, lineno, cls, chain[-1], line.strip()))
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


# GLOBAL FUNCTIONS OF @GlobalScope that read like ordinary nouns, and so get
# used as variable names without anyone noticing. Godot warns rather than
# errors, which means the warning scrolls past in a wall of engine output and
# nobody sees it -- `load`, `wrap` and `range` all shipped in this project that
# way. Deliberately NOT the whole of @GlobalScope: a name nobody would ever
# reach for is a name nobody will accidentally shadow, and every entry here is
# one more chance of a false positive.
SHADOWABLE = {
    "abs", "acos", "asin", "atan", "ceil", "char", "clamp", "cos", "ease",
    "error_string", "exp", "floor", "fmod", "hash", "instance_from_id",
    "inverse_lerp", "is_instance_valid", "len", "lerp", "load", "log", "max",
    "min", "move_toward", "nearest_po2", "ord", "pingpong", "posmod", "pow",
    "print", "printerr", "push_error", "push_warning", "randf", "randi",
    "randomize", "range", "remap", "rotate_toward", "round", "seed", "sign",
    "sin", "smoothstep", "snapped", "sqrt", "str", "str_to_var", "tan",
    "type_convert", "typeof", "var_to_str", "weakref", "wrap",
}
var_decl_re = re.compile(r"^\s*(?:@\w+\s+)*var\s+(\w+)", re.M)


def check_shadowed_globals(files):
    """A variable or parameter named after a built-in global function.

    Godot only WARNS about this, so it never stops a build and never gets
    fixed -- and the day someone inside that scope wants the real `load()` or
    `wrap()`, they get the local instead, silently.
    """
    out = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        for lineno, line in enumerate(src.split("\n"), 1):
            bare = line.split("#")[0]
            if not bare.strip():
                continue
            for name in var_decl_re.findall(bare):
                if name in SHADOWABLE:
                    out.append((path, lineno, name, "variable", line.strip()))
            for _fname, raw in signature_re.findall(bare + "\n"):
                for pname, _kind in parse_params(raw):
                    if pname in SHADOWABLE:
                        out.append((path, lineno, pname, "parameter", line.strip()))
    return out


# WORDS THAT ARE NOT NAMES. Keywords, the lowercase built-in types, and the
# handful of literals — everything a line can contain that looks like an
# identifier but never has to be declared anywhere.
NOT_A_NAME = {
    "if", "elif", "else", "for", "in", "while", "return", "var", "const",
    "func", "static", "extends", "class_name", "class", "match", "when",
    "break", "continue", "pass", "and", "or", "not", "is", "as", "self",
    "true", "false", "null", "await", "signal", "enum", "super", "assert",
    "breakpoint", "void", "int", "float", "bool", "yield", "set", "get",
    "master", "puppet", "remote", "sync", "trait", "namespace", "_",
}

# `foo` — a bare lowercase name, with nothing in front of it to give it an
# owner. The lookbehind rules out `a.foo`, `$foo`, `@foo` and a name already
# inside a word; the lookahead rules out `foo(`, which is a CALL and is the
# business of check() above rather than of this rule.
bare_name_re = re.compile(r"(?<![\w.$@])([a-z_]\w*)\b(?!\s*\()")
# Everything that DECLARES a name inside a function body.
local_decl_names = re.compile(r"(?:^|\s)(?:var|for)\s+(\w+)")
# An inline lambda brings its own parameters into the lines that follow it.
lambda_params_re = re.compile(r"\bfunc\s*\(([^)]*)\)")
# Class-level declarations, annotations and all: `@onready var x`, `var y`,
# `const Z`, `signal s`, `enum E`, `func f`.
class_decl_re = re.compile(
    r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?"
    r"(?:var|const|signal|enum)\s+(\w+)", re.M)
strings_re = re.compile(r'"[^"]*"|\'[^\']*\'')


def _func_bodies(src):
    """Every function in a file as (line number, whole signature, body lines).

    The signature is joined across continuation lines: a `func` whose
    parameters wrap onto a second line still declares them, and reading only
    the first line would report every one of the rest as undeclared.
    """
    lines = src.split("\n")
    heads = [i for i, ln in enumerate(lines)
             if re.match(r"^(?:static\s+)?func\s+\w+\s*\(", ln)]
    out = []
    for n, start in enumerate(heads):
        sig = lines[start]
        after = start
        while sig.count("(") > sig.count(")") and after + 1 < len(lines):
            after += 1
            sig += " " + lines[after].strip()
        stop = heads[n + 1] if n + 1 < len(heads) else len(lines)
        # A function ends at the next top-level declaration, whichever comes
        # first: the next `func`, or anything else at column zero.
        for i in range(after + 1, stop):
            ln = lines[i]
            if ln and not ln[0].isspace() and not ln.startswith(")"):
                stop = i
                break
        out.append((start + 1, sig, lines[after + 1:stop], after + 1))
    return out


def check_undeclared_names(files):
    """A bare name inside a function that nothing in scope declares.

    This is the rule that would have caught the two worst load failures this
    project has had, both of them the same mistake: code LIFTED OUT of a node
    class into a static helper, where `energy` and `_cheer_time` and `rotation`
    no longer mean anything because there is no longer a `self` holding them.
    `gdparse` accepts every one of those — they are perfectly good syntax —
    and the game simply does not load.

    It runs where the scope is CLOSED and can therefore be known exactly:

      * every `static func` anywhere, which can see only its parameters, its
        own locals, and the class's constants and static members; and
      * every function in a class extending RefCounted or Object, whose
        inherited surface is small enough to write down.

    Instance methods of Node subclasses are left alone, because checking those
    means knowing the whole Godot node API and a rule that cries wolf is a rule
    that gets switched off.

    Only LOWERCASE names are considered. A capitalised bare name is a class, an
    autoload or a global enum, and this file has no business guessing at those.
    Calls are left to check() — this rule is about names that are merely READ.
    """
    # The whole of RefCounted and Object worth naming, plus what @GlobalScope
    # offers as a bare word rather than as a call.
    inherited = {
        "free", "get_instance_id", "get_script", "get_class", "is_class",
        "notification", "to_string", "property_list_changed",
    }
    problems = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        base = extends_re.search(src)
        closed_class = base is not None and base.group(1) in ("RefCounted", "Object")
        members = set(class_decl_re.findall(src)) | set(func_re.findall(src))
        members |= inherited
        # A class extending a Godot node has an inherited surface this file
        # cannot know, so bare names there are normally left alone. PRIVATE
        # names are the exception and they are safe to judge anywhere: a
        # leading underscore is this project's own, never something inherited.
        # `_fire` and `_tutorial_button` both shipped as parse errors in a
        # CanvasLayer, where the closed-scope rule below could not look.
        for lineno, header, body, body_at in _func_bodies(src):
            is_static = header.lstrip().startswith("static ")
            # THE FRAME TIME, ORPHANED. This one runs in EVERY function of
            # every class, closed scope or not, because `delta` is not a
            # property of anything in Godot: a function using it that was not
            # handed it is always a mistake, and it is the exact mistake that
            # happens when a block of a `_process` is moved somewhere else.
            # Three blocks of this project's villager state machine were
            # pasted into three `match state:` blocks that return strings, and
            # fifty-four lines of `delta` came with them.
            if "delta" not in header:
                for offset, ln in enumerate(body):
                    bare = strings_re.sub('""', ln.split("#")[0])
                    if re.search(r"(?<![\w.$@])delta\b", bare):
                        problems.append((path, body_at + offset, "delta",
                                         header.split(")")[0].strip() + ")",
                                         ln.strip()))
            scope = set(members)
            inner = header[header.index("(") + 1:header.rindex(")")] \
                if ")" in header else ""
            for pname, _kind in parse_params(inner):
                scope.add(pname)
            clean_body = [strings_re.sub('""', ln.split("#")[0]) for ln in body]
            for ln in clean_body:
                scope |= set(local_decl_names.findall(ln))
                for raw in lambda_params_re.findall(ln):
                    for pname, _k in parse_params(raw):
                        scope.add(pname)
            for offset, ln in enumerate(clean_body):
                stripped = ln.strip()
                if not stripped or stripped.startswith("##"):
                    continue
                for name in bare_name_re.findall(ln):
                    if name in NOT_A_NAME or name in scope:
                        continue
                    if name in SHADOWABLE:
                        continue          # a global used as a bare reference
                    if not (closed_class or is_static) \
                            and not name.startswith("_"):
                        continue          # inherited surface: not ours to judge
                    problems.append((path, body_at + offset, name,
                                     header.split(")")[0].strip() + ")",
                                     body[offset].strip()))
    return problems


# `var beast: Animal = row["agent"]` followed a line or two later by
# `is_instance_valid(beast)`.
typed_then_guarded = re.compile(r"^\s*var\s+(\w+)\s*:\s*([A-Z]\w+)\s*=")


def check_late_validity_guards(files):
    """A typed assignment from a handle that the next lines then check is alive.

    The guard is too late. Assigning an ALREADY-FREED object to a TYPED
    variable is an error in Godot in its own right — it is raised by the
    assignment, before any is_instance_valid() below it can run — so the very
    check that says "this handle may be dead" proves the line above it can
    throw.

    This took the game down in a live session: a herd keeps a handle on each
    beast it has promoted to a real body, those bodies are freed by everything
    from a wolf to a chunk unloading, and `var agent: Animal = m["agent"]` was
    the first line of the loop that tidied them up.

    The fix is always the same shape: read it untyped, ask whether it is still
    there, and only then give it a type.
    """
    problems = []
    for path in files:
        lines = open(path, encoding="utf-8").read().split("\n")
        for i, line in enumerate(lines):
            hit = typed_then_guarded.match(line.split("#")[0])
            if not hit:
                continue
            name = hit.group(1)
            guard = re.compile(r"is_instance_valid\(\s*%s\s*\)" % re.escape(name))
            for ahead in lines[i + 1:i + 5]:
                if guard.search(ahead):
                    problems.append((path, i + 1, name, hit.group(2), line.strip()))
                    break
    return problems


# `who.thirst` — a member READ or WRITTEN on a variable whose class is known.
# Not followed by "(", because calls are already checked by check() above.
dotted_member_re = re.compile(r"(?<![\w.$@\"])([a-z_]\w*)\s*\.\s*(\w+)\b(?!\s*\()")


def check_phantom_members(files, classes):
    """A property read or written on a typed variable whose class has no such thing.

    `check()` above follows dotted CALLS — `who.mind.judge(...)` — and
    `static_member_re` catches a constant read off a class name. Between them
    sat the commonest mistake of all and nothing looked at it: an ordinary
    property on an ordinary variable, `who.thirst = ...`, where the class has
    never had a thirst. GDScript compiles it happily and raises only on the
    frame it finally runs, which for a deed the creature does now and then
    means minutes into a session.

    Only the FIRST hop is judged — `who.heart.stir(...)` asks whether Creature
    has a `heart` and stops there — and only for variables whose class this
    project declares. Godot's own properties are allowed through BASE_MEMBERS,
    which is the same table check_shadowed_members uses; a base class missing
    from it shows up as noise here rather than silence, which is the right way
    round.
    """
    problems = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        for lineno, header, body, body_at in _func_bodies(src):
            known = {}
            inner = header[header.index("(") + 1:header.rindex(")")] \
                if ")" in header else ""
            for pname, ptype in parse_params(inner):
                if ptype in classes:
                    known[pname] = ptype
            clean = [strings_re.sub('""', ln.split("#")[0]) for ln in body]
            for ln in clean:
                for rx in (local_var_re, local_decl_re):
                    for name, kind in rx.findall(ln + "\n"):
                        if kind in classes:
                            known[name] = kind
            if not known:
                continue
            for offset, ln in enumerate(clean):
                if ln.strip().startswith("#"):
                    continue
                for name, member in dict.fromkeys(dotted_member_re.findall(ln)):
                    if name not in known:
                        continue
                    cls = known[name]
                    have = members_of(cls, classes)
                    base = classes.get(cls, (set(), None))[1]
                    while base is not None:
                        have |= _inherited_members(base)
                        base = classes.get(base, (set(), None))[1] \
                            if base in classes else None
                    have |= _inherited_members(classes.get(cls, (set(), None))[1])
                    if member not in have and member not in BUILTIN:
                        problems.append((path, body_at + offset, name, cls,
                                         member, body[offset].strip()))
    return problems


def check_untyped_array_consts(files):
    """An array constant that does not say what it holds.

    `const LESSONS := ["circle", ...]` is an array of VARIANTS, so LESSONS[i]
    has no type — and `var next := LESSONS[i]` therefore has nothing to infer
    from. This project builds that as an error, and the error stops every
    dependent script loading: one untyped constant in a schoolhouse took the
    whole village down with it.

    The line that trips it can be written years after the constant, in another
    file, by somebody who never looks at the constant at all. So it is the
    CONSTANT that is asked to say what it holds — there is no cost to it, and
    it closes the whole family rather than the one line that happened to find
    it. Seventeen of these were in the project when this rule was written, and
    every one of them was one `:=` away from the same failure.
    """
    problems = []
    bare = re.compile(r"^const\s+(\w+)\s*:=\s*\[")
    for path in files:
        for lineno, line in enumerate(
                open(path, encoding="utf-8").read().split("\n"), 1):
            hit = bare.match(line)
            if hit:
                problems.append((path, lineno, hit.group(1), line.strip()))
    return problems


def check_twice_declared(files):
    """The same function defined twice in one class.

    Godot does not merge them and does not take the last one: it refuses to
    parse the CLASS, and then every class that names it fails to resolve, and
    the error you are shown is about some innocent file three steps downstream.
    Today it was `seat_of` written twice into Edubba, and what the engine
    reported was that Village could not resolve a type.

    gdparse accepts it happily — two functions of the same name are perfectly
    good syntax — so nothing in this project's own checks saw it either.
    """
    problems = []
    for path in files:
        seen = {}
        lines = open(path, encoding="utf-8").read().split("\n")
        for lineno, line in enumerate(lines, 1):
            hit = re.match(r"^(?:static\s+)?func\s+(\w+)\s*\(", line)
            if not hit:
                continue
            name = hit.group(1)
            if name in seen:
                problems.append((path, lineno, name, seen[name], line.strip()))
            else:
                seen[name] = lineno
    return problems


def check_shadowed_class_vars(files):
    """A LOCAL WITH THE SAME NAME AS ONE OF THE CLASS'S OWN VARIABLES.

    Godot warns (SHADOWED_VARIABLE) and carries on, which is the worst of both:
    the code runs, the local wins inside that function, and every later reader
    believes they are looking at the member. Adding `var head` to Creature
    silently shadowed it inside the body-building block that had been using a
    local `head` for a year.

    The sibling checks cover a redeclaration in the SAME scope and a name that
    collides with an inherited engine property; this is the third door.
    """
    out = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        own = set(re.findall(r"^var\s+(\w+)", src, re.M))
        if not own:
            continue
        for i, line in enumerate(src.split("\n"), 1):
            if not line.startswith((" ", "\t")):
                continue
            m = re.match(r"^[ \t]+var\s+(\w+)", line.split("#", 1)[0])
            if m and m.group(1) in own:
                out.append((path, i, m.group(1), line.strip()))
    return out


def check_confusable_locals(files):
    """A LOCAL DECLARED INSIDE A BLOCK when the SAME name is declared later in
    an enclosing one. Godot calls it CONFUSABLE_LOCAL_DECLARATION and warns,
    because a reader of the inner block cannot tell which they are looking at
    without scrolling past the end of it."""
    out = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        for fname, body, start in _func_spans(src):
            seen = {}
            for off, line in enumerate(body.split("\n")):
                bare = line.split("#", 1)[0]
                m = re.match(r"^([ \t]*)var\s+(\w+)", bare)
                if not m:
                    continue
                depth, name = len(m.group(1).expandtabs(4)), m.group(2)
                if name in seen and depth < seen[name][0]:
                    # This one encloses an earlier, deeper declaration.
                    out.append((path, start + seen[name][1], name, fname,
                                start + off, line.strip()))
                seen[name] = (depth, off)
    return out


def _func_spans(src):
    """(name, body, first line number) for every top-level func."""
    out, name, buf, start = [], None, [], 0
    for i, line in enumerate(src.split("\n"), 1):
        h = re.match(r"^(?:static\s+)?func\s+(\w+)\s*\(", line)
        if h:
            if name:
                out.append((name, "\n".join(buf), start))
            name, buf, start = h.group(1), [], i
        elif name is not None:
            if line and not line[0].isspace() and not line.startswith(")"):
                out.append((name, "\n".join(buf), start))
                name, buf = None, []
            else:
                buf.append(line)
    if name:
        out.append((name, "\n".join(buf), start))
    return out


def autoloads(path="project.godot"):
    """The singletons Godot installs as global names -> the STATIC methods each
    one's script declares.

    A call through one of these is an ordinary instance call and perfectly
    legal, with exactly one exception: a method that IS static, reached through
    the instance, which Godot warns about from the other direction."""
    found, inside = {}, False
    try:
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line.startswith("["):
                inside = line == "[autoload]"
                continue
            if inside and "=" in line:
                nm = line.split("=", 1)[0].strip()
                # An autoload script has no `class_name` — the global name IS
                # its only name — so its statics are read straight out of the
                # file the autoload points at.
                rel = line.split("=", 1)[1].strip().strip('"').lstrip("*")
                rel = rel.replace("res://", "")
                try:
                    found[nm] = set(static_func_re.findall(
                        open(rel, encoding="utf-8").read()))
                except OSError:
                    found[nm] = set()
    except OSError:
        pass
    return found


def check_static_calls(files, singletons):
    """AN INSTANCE METHOD CALLED THROUGH ITS CLASS NAME.

    `MiracleManager.resolve(...)` is a STATIC call. Godot refuses it for a
    method that is not static, and refuses it at PARSE time — so one line of it
    takes every script that depends on that class down with it, and the error
    names the caller rather than the mistake.

    It is an easy line to write and a very easy one to believe: a class with a
    manager-ish name reads exactly like an autoload, and the six autoloads in
    this project ARE called that way, legally, everywhere. Three new miracles
    were written against a MiracleManager that is not one, in one afternoon,
    and none of the other checks here had anything to say about it.
    """
    out = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        for i, line in enumerate(src.split("\n"), 1):
            code = line.split("#", 1)[0]
            for cls, method in through_class_re.findall(code):
                # THE MIRROR CASE. An autoload is an INSTANCE, so reaching a
                # STATIC method through it is the same mistake the other way up,
                # and Godot warns about that one too.
                if cls in singletons:
                    if method in singletons[cls]:
                        out.append((path, i, cls, method, "static", line.strip()))
                    continue
                if cls not in OWN_FUNCS:
                    continue
                if method not in OWN_FUNCS[cls] or (cls, method) in STATICS:
                    continue
                out.append((path, i, cls, method, "method", line.strip()))
            # And the same mistake made against a FIELD rather than a method.
            # `MiracleManager.divine_hand` was in the very same log, and it
            # fails the same way and for the same reason.
            for cls, field in through_class_var_re.findall(code):
                if cls in singletons or cls not in OWN_VARS:
                    continue
                if field not in OWN_VARS[cls]:
                    continue
                if re.search(r"\b%s\.%s\s*\(" % (cls, field), code):
                    continue        # already reported above as a call
                out.append((path, i, cls, field, "field", line.strip()))
    return out


def check_sim_clock(files):
    """A SCHEDULER CLOCK STAMPED ONLY ON THE FRAMES IT TICKS COARSELY.

    Scheduler.turn() hands back `now - last_ran` and the caller multiplies BOTH
    its delta and its velocity scale by that number. So `last_ran` has to mean
    "the frame this thing last ran", and it only means that if it is written on
    every frame the thing runs — including the fast ones, where the stride is 1
    and Scheduler is never consulted at all.

    Written inside the `if stride > 1:` branch, it means something else
    entirely: "the frame it was last far away". A villager that spent ten
    minutes near the camera had a `last_ran` ten minutes stale, and the first
    frame its stride rose above 1 — the camera panning off, the heat band
    moving, a full hand — it was charged thirty-six thousand frames at once and
    covered nine hundred metres between two frames, through everything in the
    way. Every villager and beast in the town did it together.

    The rule is structural and cheap to check: the assignment must sit at an
    indent no deeper than the `var stride` that decides the branch.
    """
    out = []
    for path in files:
        src = open(path, encoding="utf-8").read()
        if "Scheduler.turn(" not in src:
            continue
        lines = src.split("\n")
        for i, line in enumerate(lines):
            if "Scheduler.turn(" not in line.split("#", 1)[0]:
                continue
            call_indent = len(line) - len(line.lstrip("\t"))
            # Walk on to the end of the enclosing function looking for a stamp
            # written at a SHALLOWER indent than the branch the call sits in.
            stamped = False
            for after in lines[i + 1:]:
                code = after.split("#", 1)[0]
                if code.strip() and not code.startswith("\t"):
                    break                      # left the function
                if "Scheduler.now()" not in code:
                    continue
                if len(code) - len(code.lstrip("\t")) < call_indent:
                    stamped = True
                    break
            if not stamped:
                out.append((path, i + 1, line.strip()))
    return out


def check_typed_has(files):
    """A TYPED ARRAY'S `has` VALIDATES ITS ARGUMENT, AND RAISES.

    `Array[MultiMeshInstance3D].has(some_staticbody)` does not answer false. It
    throws — "Attempted to use 'has' an object of type 'StaticBody3D' into a
    TypedArray, which does not inherit from 'MultiMeshInstance3D'" — and keeps
    throwing, once per offending element, every time the line runs.

    Which makes "is this thing of mine in my list?" an unsafe question to ask of
    a mixed bag. The bag that shipped this was `get_children()`: a chunk walking
    its children to free them, asking a typed array of billboards whether each
    one was a billboard. Every tree standing on that chunk raised.

    Guard with `is` first — `node is T and list.has(node)` short-circuits before
    `has` ever sees the wrong type. Same family as the `filter()` trap in
    Util.prune: a typed array is not a list, it is a list that CHECKS.
    """
    node_source = re.compile(
        r"^for\s+(\w+)\s+in\s+.*\b(get_children|find_children|"
        r"get_nodes_in_group)\(")
    typed = re.compile(r"^\s*var\s+(\w+)\s*:\s*Array\[")
    asked = re.compile(r"\b([\w.]+)\.(has|erase|find|rfind|count)\(\s*(\w+)\s*\)")
    out = []
    for path in files:
        lines = open(path, encoding="utf-8").read().split("\n")
        names = set()
        for line in lines:
            m = typed.match(line)
            if m:
                names.add(m.group(1))
        if not names:
            continue
        loop_var, loop_indent = None, 0
        for i, line in enumerate(lines, 1):
            code = line.split("#", 1)[0]
            bare = code.strip()
            indent = len(code) - len(code.lstrip("\t"))
            if loop_var is not None and bare != "" and indent <= loop_indent:
                loop_var = None
            m = node_source.match(bare)
            if m:
                loop_var, loop_indent = m.group(1), indent
                continue
            if loop_var is None:
                continue
            for hit in asked.finditer(code):
                if hit.group(3) != loop_var or hit.group(1) not in names:
                    continue
                # `x is T and list.has(x)` is the fix, and is left alone.
                if re.search(r"\b%s\s+is\s+\w+" % re.escape(loop_var), code):
                    continue
                out.append((path, i, hit.group(1), hit.group(2), loop_var,
                            bare))
    return out


def check_shadowed_own(files):
    """A parameter or local named after one of the class's OWN variables.

    check_shadowed_members catches names inherited from the base node. This
    catches the other half: a script that declares `var style` and then writes
    `static func crown(style: String)`. Godot raises SHADOWED_VARIABLE at every
    load, for the life of the line, and in a NON-static function the parameter
    quietly wins over the member — which is how a function comes to read an
    argument it was never passed.

    METHOD NAMES COUNT TOO, and the first version of this rule did not know it:
    `var lux := 0.0` inside a class that has a `lux()` method is the same
    warning, and LightMeter shipped with one because nothing was watching.
    """
    own_decl = re.compile(r"^(?:var|const)\s+(\w+)|^(?:static )?func (\w+)\(")
    sig = re.compile(r"^(?:static\s+)?func\s+\w+\((.*)$")
    local = re.compile(r"^\t+var\s+(\w+)")
    out = []
    for path in files:
        lines = open(path, encoding="utf-8").read().split("\n")
        own = set()
        for line in lines:
            m = own_decl.match(line)
            if m:
                own.add(m.group(1) or m.group(2))
        if not own:
            continue
        for i, line in enumerate(lines, 1):
            code = line.split("#", 1)[0]
            m = sig.match(code)
            if m:
                mine = re.match(r"^(?:static )?func (\w+)\(", code)
                if mine is not None and mine.group(1) in own:
                    own_here = mine.group(1)
                else:
                    own_here = ""
                for arg in split_top(m.group(1).split(")")[0]):
                    name = arg.split(":")[0].split("=")[0].strip()
                    if name in own and name != own_here:
                        out.append((path, i, name, "parameter", code.strip()))
                continue
            m = local.match(code)
            if m and m.group(1) in own:
                out.append((path, i, m.group(1), "local", code.strip()))
    return out


def split_top(text):
    """Comma split that ignores commas inside brackets."""
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return out


def check_int_division(files):
    """WHOLE-NUMBER DIVISION THAT NOBODY SAID WAS DELIBERATE.

    `TALL / 2` where TALL is an int const is an INTEGER division, and Godot
    warns about every one of them at every load, forever. The warning is right
    to exist — it cannot tell a deliberate floor from somebody who forgot that
    two ints do not make a float — but a warning nobody can silence is a
    warning nobody reads, and this project has now shipped three separate
    batches of them: Edubba's class seating, VillageJobs' hands per job, and
    SkyCover's horizon row.

    The fix is never to change the arithmetic. It is to SAY SO: an
    `@warning_ignore("integer_division")` on the line above, and a comment
    saying why the floor is what was wanted. Then the log is empty and the next
    person knows the remainder was thrown away on purpose.

    Only divisions where BOTH sides are known integers are flagged — an int
    const over a literal, or over another int const. Anything involving a
    float, a variable or a call is left alone, because this cannot know.

    ...WITH ONE EXCEPTION, ADDED AFTER IT MISSED ONE. `.size()` and
    `.get_child_count()` return an int and nothing else, always, so
    `sorted.size() / 2` is an integer division as surely as any const is — and
    it is the commonest shape of all, because halving a collection is what
    people do to find a middle. The original rule only knew about named int
    constants and let Chronicle._middle straight through into the log.
    """
    out = []
    # Calls whose return type is int, whatever the receiver.
    WHOLE = r"(?:\.size\(\)|\.get_child_count\(\))"
    for path in files:
        lines = open(path, encoding="utf-8").read().split("\n")
        ints = set()
        for line in lines:
            m = re.match(r"^const (\w+)(?:\s*:\s*int)?\s*:?=\s*-?\d+\s*(?:#.*)?$", line)
            if m:
                ints.add(m.group(1))
        named = "|".join(re.escape(n) for n in ints)
        # `(?![\d.])` and not `\b`: a word boundary sits happily between the 2
        # and the dot of `2.0`, so the first pass flagged `size() / 2.0` —
        # which is a FLOAT divide and perfectly correct. A checker that cries
        # about correct code gets switched off.
        tests = [re.compile(r"\w+%s\s*/\s*\d+(?![\d.])" % WHOLE)]
        if ints:
            tests.append(re.compile(
                r"\b(?:%s)\s*/\s*(?:\d+(?![\d.])|(?:%s)\b)" % (named, named)))
        for i, line in enumerate(lines):
            code = line.split("#", 1)[0]
            hit = None
            for test in tests:
                hit = test.search(code)
                if hit is not None:
                    break
            if hit is None:
                continue
            above = lines[i - 1] if i > 0 else ""
            if "integer_division" in above:
                continue
            out.append((path, i + 1, hit.group(0), code.strip()))
    return out


# WHAT A VILLAGE RAISES. Anything a town builds and stands behind belongs here,
# and adding a new kind of building means adding a line — there is no way to
# derive this list that does not also sweep up the pens, the totem and half the
# helper classes, and a survey that quietly misses a building is worse than no
# survey, because "the mill would not burn" is exactly the bug it exists to
# prevent and it went unnoticed for months.
VILLAGE_RAISES = {
    "house.gd": "a house",
    "workshop.gd": "a mill, tannery, smithy or barn",
    "food_store.gd": "the granary",
    "edubba.gd": "the school",
    "farm.gd": "a field",
    "creature_nest.gd": "the nest",
}
# What being burnable actually commits a building to. `ignite` without `damage`
# is a building that catches and never falls; `damage` without `full_health` is
# a building every blow treats as a hut.
BURNABLE_OWES = ("ignite", "extinguish", "damage", "full_health", "burn_down")


# EVERY PLACE IN THE GAME THAT LETS GO OF SOMETHING WITH SPEED. Each one has
# to ask ChildSafety first, and a new one added without asking is how the rule
# quietly stops being a rule.
LETS_GO = {
    "divine_hand.gd": "the player's own hand",
    "creature_throwing.gd": "everything the creature hurls",
}


def check_children(files):
    """NO PATH LETS GO OF A CHILD WITH ANY SPEED.

    There is no throwing of children in this game -- not "it costs a lot of
    karma", not "the villagers will hate you", it does not happen. The rule
    lives in one file, ChildSafety, precisely so there is one place to read it
    and one place it could ever be weakened from.

    But a rule enforced at the call sites is only as good as the call sites, and
    the two of them are a thousand lines apart in files that are edited for
    entirely unrelated reasons. So: anything that throws asks first, and this
    fails the build if one of them stops asking. That includes deleting the
    check to fix something else and meaning to put it back.
    """
    out = []
    for path in files:
        name = os.path.basename(path)
        if name not in LETS_GO:
            continue
        src = open(path, encoding="utf-8").read()
        if "ChildSafety.throw_answer(" not in src:
            out.append((path, "%s is %s and never asks ChildSafety.throw_answer"
                        % (name, LETS_GO[name])))
    # And the rule itself has to still be a rule.
    guard = [p for p in files if os.path.basename(p) == "child_safety.gd"]
    if not guard:
        out.append(("scripts/villager/child_safety.gd",
                    "ChildSafety is gone entirely"))
    else:
        src = open(guard[0], encoding="utf-8").read()
        for owed in ("is_child", "in_your_hand", "throw_answer", "let_go"):
            if re.search(r"^static func %s\(" % owed, src, re.M) is None:
                out.append((guard[0], "ChildSafety has lost `%s`" % owed))
    return out


def check_burnable(files):
    """EVERYTHING A VILLAGE RAISES CAN BE BURNED DOWN, AND KNOWS WHAT IT IS WORTH.

    A building is the thing that protects the villager, so every one of them
    has to be destructible -- and every one has to say how tough it is, or a
    blow scaled as a share of a building's health silently treats a granary as
    a hut.

    Two ways to fail. A village-built thing that never joined "burnable" is
    invisible to the sweep that sets a street alight AND to the fire spreading
    from the barn next door: the farm was in exactly that state, so a fire
    walked round a wheat field. And a thing in "burnable" that is missing one of
    the five methods above is a building that catches fire and then cannot do
    anything about it.
    """
    out = []
    for path in files:
        name = os.path.basename(path)
        src = open(path, encoding="utf-8").read()
        burns = 'add_to_group("burnable")' in src
        if name in VILLAGE_RAISES and not burns:
            out.append((path, 0, "%s is %s and never joins \"burnable\", so no "
                        "fire can reach it and none can spread to it"
                        % (name, VILLAGE_RAISES[name])))
            continue
        if not burns:
            continue
        for owed in BURNABLE_OWES:
            if re.search(r"^func %s\(" % owed, src, re.M) is None:
                out.append((path, 0, "%s is burnable but has no `%s`"
                            % (name, owed)))
    return out


def check_tree_worth(files):
    """A TREE'S SIZE BANKED AS A TREE'S WORTH.

    `WildTree.lumber` is how BIG it is, one to ten. `WildTree.timber()` is what
    felling it yields -- the running Fibonacci sum of every size it has been, so
    a nine is worth eighty-eight and a ten is worth a hundred and forty-three.
    The whole point of that curve is that a wood becomes something a village
    lets stand and comes back to, and cutting saplings stops being worth the
    walk.

    Three of the four ways a tree can be harvested were banking the SIZE. A
    woodcutter called `fell()`, which returns `timber()`, and got 88; the same
    giant carried to the storehouse in the god's own hand paid 9, and hurled
    hard enough to burst it paid 3. Nobody noticed for as long as the game has
    had Fibonacci timber, because each path looked perfectly reasonable on its
    own line.

    So: nothing may pass `lumber` to `add_lumber`. Quoted text is stripped
    first, because `spec["lumber"]` is a build cost and has nothing to do with
    a tree.
    """
    out = []
    quoted = re.compile(r'"[^"]*"|\'[^\']*\'')
    bare = re.compile(r"\blumber\b")
    for path in files:
        for i, line in enumerate(open(path, encoding="utf-8").read().split("\n")):
            code = line.split("#", 1)[0]
            at = code.find("add_lumber(")
            if at < 0:
                continue
            # The argument text, to the matching close paren.
            depth, arg = 0, []
            for ch in code[at + len("add_lumber("):]:
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    if depth == 0:
                        break
                    depth -= 1
                arg.append(ch)
            if bare.search(quoted.sub("", "".join(arg))):
                out.append((path, i + 1, code.strip()))
    return out


def check_sentinel_passed(files):
    """A "NOWHERE YET" SENTINEL HANDED TO SOMETHING THAT WILL BUILD THERE.

    `Vector3.INF` is this codebase's "no spot has been chosen". It is a real
    Vector3, so nothing refuses it: pass one to a spawner and a field is raised
    at infinity, the ground sampling under it comes back NaN, `generate_normals`
    cannot normalize, and the renderer reports a non-finite transform once a
    frame for the rest of the session. That is not a hypothetical number — it
    was three hundred and seventy-nine thousand lines of debugger.

    The shape: a member that is assigned `Vector3.INF` somewhere in the file,
    then passed as an argument to a call on another object, in a function that
    never checks it. The check can be `is_finite()` or a comparison against the
    sentinel; either satisfies this.

    Assignments are not guards. `foo(_spot)` followed by `_spot = Vector3.INF`
    is exactly the bug — the reset lands after the horse has left.
    """
    # Every function anywhere that takes a Vector3 and refuses a non-finite
    # one. Collected across the whole project first, because the guard and the
    # call are nearly always in different files.
    guarded_takers = set()
    for path in files:
        src = open(path, encoding="utf-8").read().split("\n")
        here, body = "", []
        for line in src + ["func _end_():"]:
            m = re.match(r"^(?:static )?func (\w+)\(.*Vector3", line)
            if m or re.match(r"^(?:static )?func ", line):
                if here and any("is_finite" in b for b in body[:12]):
                    guarded_takers.add(here)
                here = m.group(1) if m else ""
                body = []
                continue
            if here:
                body.append(line)

    out = []
    for path in files:
        lines = open(path, encoding="utf-8").read().split("\n")
        marked = set()
        for line in lines:
            m = re.match(r"^\s*(?:var\s+)?(_?\w+)\s*:?=\s*Vector3\.INF\s*$", line)
            if m:
                marked.add(m.group(1))
        if not marked:
            continue
        # Walk function by function: a guard anywhere in the same function
        # counts, since a state machine's arms share one.
        start, func = 0, ""
        bounds = []
        for i, line in enumerate(lines):
            if re.match(r"^(?:static )?func (\w+)", line):
                if func:
                    bounds.append((func, start, i))
                func = re.match(r"^(?:static )?func (\w+)", line).group(1)
                start = i
        if func:
            bounds.append((func, start, len(lines)))
        for _name, lo, hi in bounds:
            body = lines[lo:hi]
            for name in marked:
                guarded = any(
                    re.search(r"\b%s\b" % re.escape(name), b)
                    and ("is_finite" in b or "Vector3.INF" in b.split("=")[0]
                         or re.search(r"%s\s*[!=]=\s*Vector3\.INF" % re.escape(name), b))
                    for b in body)
                if guarded:
                    continue
                for j, b in enumerate(body):
                    code = b.split("#", 1)[0]
                    hit = re.search(r"\w+\.(\w+)\([^)]*\b%s\b" % re.escape(name), code)
                    if hit is None:
                        continue
                    # A GUARD IN THE CALLEE COUNTS, and is the better place for
                    # it: the sentinel is shared, so one refusal at the thing
                    # being built covers every caller that will ever pass one.
                    if hit.group(1) in guarded_takers:
                        continue
                    out.append((path, lo + j + 1, name, code.strip()))
    return out


def check_stand_first(files):
    """THE WOOD MUST BE DRAWN FROM THE CHUNK'S RNG BEFORE ANYTHING ELSE IS.

    Chunk._tree_stand decides where a chunk's trees go, off `world.chunk_rng`.
    Two callers ask it: `_scatter`, which plants real trees, and
    `retally_boards` on a chunk out in the far ring, which has no trees at all
    and paints billboards where they WOULD be. The two agree only because both
    ask at the same point in the same deterministic stream — the very start of
    it.

    Put one more `rng` draw above `_tree_stand(rng)` in `_scatter` and they
    silently disagree: the far ring paints a wood in one place, and walking up
    to it plants the wood somewhere else. Nothing errors. You watch the trees
    move as you approach them, which is the exact thing an impostor exists not
    to do.

    So: in `_scatter`, the first line after the RNG is made that touches it has
    to be the `_tree_stand` call.
    """
    out = []
    for path in files:
        if not path.endswith("chunk.gd"):
            continue
        inside, armed = False, False
        for i, line in enumerate(open(path, encoding="utf-8"), 1):
            code = line.split("#", 1)[0]
            if re.match(r"^func _scatter\(", code):
                inside = True
                continue
            if inside and re.match(r"^func ", code):
                break
            if not inside:
                continue
            if "world.chunk_rng(" in code:
                armed = True
                continue
            if armed and re.search(r"\brng\b", code):
                if "_tree_stand(rng)" not in code:
                    out.append((path, i, line.strip()))
                armed = False
    return out


def check_null_as_alive(files):
    """`x != null` USED AS A TEST FOR "THERE IS A LIVE OBJECT HERE".

    It is not one. A Variant holding a FREED object does not behave like a live
    one under `!=`, so `x != null and not is_instance_valid(x)` — which reads
    exactly like "there is something here and it is dead" — never reports a
    dead thing at all. Whatever follows then works on the corpse, and if it
    casts it, Godot takes the game down with "Trying to cast a freed object".

    That is not hypothetical: Creature._enact guarded its target this way, and a
    choice can sit in CreatureIntent for seconds before it is enacted. Drop what
    it was aimed at in that window and the next praise crashed the game.

    `typeof(x) == TYPE_OBJECT` is the question that survives: a Variant's TYPE
    does not change when the object it held is freed, so it separates "somebody
    put a thing here" from "this was always null", and is_instance_valid then
    says which sort of thing it is.

    The OTHER order — `x != null and is_instance_valid(x)` — is safe and is left
    alone: a freed object failing the first test reaches the right answer.
    """
    dead = re.compile(r"(\b[\w.]+)\s*!=\s*null\s+and\s+not\s+is_instance_valid\(\s*([\w.]+)\s*\)")
    out = []
    for path in files:
        lines = open(path, encoding="utf-8").read().split("\n")
        held, start = "", 0
        for i, line in enumerate(lines, 1):
            code = line.split("#", 1)[0].rstrip()
            # A continuation is joined onto the line it started on, so the site
            # is reported where a reader will find it rather than N lines early.
            if held == "":
                start = i
            if code.endswith("\\"):
                held += code[:-1] + " "
                continue
            stmt = held + code
            held = ""
            m = dead.search(stmt)
            if m and m.group(1) == m.group(2):
                out.append((path, start, m.group(1), stmt.strip()))
    return out


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
    shadowed_globals = check_shadowed_globals(files)
    for path, lineno, name, kind, line in shadowed_globals:
        print("%s:%d: the %s '%s' has the same name as the built-in function "
              "%s() — Godot warns and carries on, so this never gets fixed, and "
              "the real %s() is unreachable from inside this scope"
              "\n    %s" % (path, lineno, kind, name, name, name, line))
    through = check_static_calls(files, autoloads())
    for path, lineno, cls, name, kind, line in through:
        if kind == "static":
            print("%s:%d: %s.%s() is a STATIC function reached through the "
                  "autoload INSTANCE — Godot warns and asks for it to be called "
                  "on the type. Either drop `static` or call it on the script."
                  "\n    %s" % (path, lineno, cls, name, line))
            continue
        shown = name + "()" if kind == "method" else name
        print("%s:%d: %s.%s is an INSTANCE %s reached through the class name — %s "
              "is not an autoload. Godot rejects this at parse time and takes every "
              "dependent script with it. Get the object first."
              "\n    %s" % (path, lineno, cls, shown, kind, cls, line))
    class_shadows = check_shadowed_class_vars(files)
    for path, lineno, name, line in class_shadows:
        print("%s:%d: the local '%s' has the same name as a variable of this "
              "class — Godot warns and carries on, so the local quietly wins "
              "inside this function and every later reader believes they are "
              "looking at the member\n    %s" % (path, lineno, name, line))
    confusable = check_confusable_locals(files)
    for path, lineno, name, fn, outer, line in confusable:
        print("%s:%d: '%s' is declared again at line %d, in a block that "
              "ENCLOSES this one — Godot calls that confusable and warns, "
              "because a reader of %s() cannot tell them apart\n    %s"
              % (path, lineno, name, outer, fn, line))
    undeclared = check_undeclared_names(files)
    for path, lineno, name, where, line in undeclared:
        print("%s:%d: '%s' is not declared in the scope of %s — nothing in this "
              "function, its parameters, or its class provides it. gdparse "
              "accepts this; Godot refuses to load the script."
              "\n    %s" % (path, lineno, name, where, line))
    loose_consts = check_untyped_array_consts(files)
    for path, lineno, name, line in loose_consts:
        print("%s:%d: the array constant '%s' does not say what it holds, so "
              "reading an element of it gives a Variant and ':=' has nothing to "
              "infer from — an error this project builds as fatal, in whatever "
              "file eventually indexes it. Name the element type."
              "\n    %s" % (path, lineno, name, line))
    twice = check_twice_declared(files)
    for path, lineno, name, first, line in twice:
        print("%s:%d: '%s' is already defined at line %d. Godot refuses to parse "
              "the whole CLASS for this, and reports it as a failure in some "
              "other file that merely names the class."
              "\n    %s" % (path, lineno, name, first, line))
    phantoms = check_phantom_members(files, classes)
    for path, lineno, name, cls, member, line in phantoms:
        print("%s:%d: %s is a %s, and %s has no '%s'. GDScript accepts this and "
              "raises only on the frame the line finally runs."
              "\n    %s" % (path, lineno, name, cls, cls, member, line))
    late_guards = check_late_validity_guards(files)
    for path, lineno, name, kind, line in late_guards:
        print("%s:%d: '%s' is typed as %s here and only checked with "
              "is_instance_valid() below — but assigning an already-freed "
              "object to a TYPED variable is itself the error, raised before "
              "that check can run. Read it untyped, guard it, then type it."
              "\n    %s" % (path, lineno, name, kind, line))
    alive = check_null_as_alive(files)
    for path, lineno, name, line in alive:
        print("%s:%d: `%s != null` does not mean '%s is a live object' — a FREED "
              "one does not compare like a live one, so this branch never fires "
              "and whatever follows works on a corpse (a cast of it is a crash). "
              "Ask `typeof(%s) == TYPE_OBJECT` instead."
              "\n    %s" % (path, lineno, name, name, name, line))
    int_div = check_int_division(files)
    for path, lineno, expr, line in int_div:
        print("%s:%d: `%s` divides two whole numbers, so the remainder is "
              "thrown away — and Godot says so at every load, forever. If that "
              "is what was wanted, say it: `@warning_ignore(\"integer_division\")` "
              "on the line above, and a comment saying why the floor is right."
              "\n    %s" % (path, lineno, expr, line))
    kids = check_children(files)
    for path, why in kids:
        print("%s: %s. There is no throwing of children in this game and the "
              "rule is enforced at every place that lets go — see "
              "scripts/villager/child_safety.gd." % (path, why))
    burnable = check_burnable(files)
    for path, _lineno, why in burnable:
        print("%s: %s. Everything a village raises must be destructible and must "
              "say what it is worth in full — see tools/check_calls.py, "
              "VILLAGE_RAISES." % (path, why))
    worth = check_tree_worth(files)
    for path, lineno, line in worth:
        print("%s:%d: this banks a tree's SIZE as its WORTH. `lumber` is how big "
              "it is (1..10); `timber()` is what felling it yields — the running "
              "Fibonacci sum of every size it has been, so a nine is 88 and a "
              "ten is 143. Call `timber()`."
              "\n    %s" % (path, lineno, line))
    sentinels = check_sentinel_passed(files)
    for path, lineno, name, line in sentinels:
        print("%s:%d: `%s` is assigned Vector3.INF somewhere in this file — the "
              "'no spot yet' sentinel — and is handed to something here without "
              "this function ever checking it. A thing built at infinity puts "
              "NaN through the ground, the normals and the renderer's "
              "transform, once a frame, forever. Guard it with `is_finite()`; "
              "resetting it AFTER the call is what caused this."
              "\n    %s" % (path, lineno, name, line))
    typed_has = check_typed_has(files)
    for path, lineno, arr, verb, var, line in typed_has:
        print("%s:%d: `%s` is a TYPED array, so `%s(%s)` does not answer false "
              "for an element of the wrong class — it RAISES, once per element, "
              "every time this runs. `%s` comes straight out of the scene tree "
              "and is a mixed bag. Guard it: `%s is <Type> and %s.%s(%s)`."
              "\n    %s" % (path, lineno, arr, verb, var, var, var, arr, verb,
                            var, line))
    shadowed_own = check_shadowed_own(files)
    for path, lineno, name, kind, line in shadowed_own:
        print("%s:%d: the %s '%s' is named after this class's own variable, "
              "which Godot warns about at every load — and in a non-static "
              "function the %s silently wins over the member. Rename it."
              "\n    %s" % (path, lineno, kind, name, kind, line))
    stand = check_stand_first(files)
    for path, lineno, line in stand:
        print("%s:%d: this draws from the chunk's RNG before `_tree_stand(rng)` "
              "does. The far ring replays that same stream to decide where a "
              "chunk's billboard trees stand, so one extra draw ahead of it "
              "puts the painted wood and the real wood in different places — "
              "and you watch the trees move as you walk up to them. Ask for "
              "the stand first."
              "\n    %s" % (path, lineno, line))
    sim_clocks = check_sim_clock(files)
    for path, lineno, line in sim_clocks:
        print("%s:%d: nothing writes `_sim_last = Scheduler.now()` outside this "
              "branch, so the clock only advances on the frames this entity runs "
              "COARSELY. Scheduler.turn() then charges it every frame since it "
              "was last far from the camera — multiplied into delta AND into the "
              "velocity scale — and it teleports. Stamp it on every frame it runs."
              "\n    %s" % (path, lineno, line))
    loop_vars = check_untyped_loop_vars(files)
    for path, lineno, name, line in loop_vars:
        print("%s:%d: '%s' comes from an UNTYPED array literal, so it is a "
              "Variant and ':=' infers a Variant here — Godot builds that as an "
              "error that stops every dependent script loading. Name the element "
              "type: `for %s: <Type> in [...]`.\n    %s"
              % (path, lineno, name, name, line))
    total = len(problems) + len(escapes) + len(formats) + len(shadowed) \
        + len(loose_arrays) + len(variants) + len(shadowed_members) \
        + len(loop_vars) + len(shadowed_globals) + len(undeclared) + len(late_guards) + len(phantoms) + len(twice) + len(loose_consts) + len(through) \
        + len(class_shadows) + len(confusable) + len(sim_clocks) + len(alive) \
        + len(stand) + len(typed_has) + len(shadowed_own) + len(sentinels) \
        + len(int_div) + len(worth) + len(burnable) + len(kids)
    print("checked %d classes across %d files — %d problem(s)"
          % (len(classes), len(files), total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
