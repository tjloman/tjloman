#!/usr/bin/env python3
"""IS EVERY SYSTEM ACTUALLY TALKING TO THE OTHERS?

A thing can be written, parse, lint, pass every type check and still be wired to
nothing. That failure is invisible: no error, no crash, no wrong number — the
feature simply never happens, and you find out by playing for an hour and
noticing an absence. This project has shipped three of them (a hive feeling
nothing ever sent, a charge readout nothing ever drew, a signal nothing emitted).

So this asks four structural questions across every script:

  DEAD ENDS      a public method nobody calls
  ORPHAN SIGNALS declared but never emitted, or emitted but never connected
  ONE-WAY GROUPS added to but never read, or read but never added to
  DEAD METADATA  set_meta with a key nothing ever reads (and the reverse)

None of these is automatically a bug — an interface can be for the player's
hand, a group can be a marker — so this REPORTS rather than fails. Read it after
building something and check the new names are not in it.
"""
import os, re, sys

SKIP_METHODS = {
    # Godot's own entry points and virtuals: the engine calls them.
    "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_init", "_enter_tree", "_exit_tree", "_draw", "_notification",
    "_get_configuration_warnings", "_to_string", "_gui_input",
}


def scripts(root="scripts"):
    for dp, _d, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith(".gd"):
                yield os.path.join(dp, f)


def main():
    src = {p: open(p, encoding="utf-8").read() for p in scripts()}
    everything = "\n".join(src.values())
    # Strip comments so a name mentioned only in prose does not count as a use.
    code = "\n".join(
        line.split("#", 1)[0] for line in everything.split("\n")
        if not line.lstrip().startswith("#"))

    declared, signals, emitted, connected = {}, {}, set(), set()
    joins, reads, meta_set, meta_get = {}, set(), {}, set()
    for p, text in src.items():
        body = "\n".join(l.split("#", 1)[0] for l in text.split("\n")
                         if not l.lstrip().startswith("#"))
        for m in re.finditer(r"^(?:static\s+)?func\s+([a-z]\w*)\s*\(", text, re.M):
            declared.setdefault(m.group(1), []).append(p)
        for m in re.finditer(r"^signal\s+(\w+)", text, re.M):
            signals.setdefault(m.group(1), []).append(p)
        emitted.update(re.findall(r"(\w+)\.emit\s*\(", body))
        connected.update(re.findall(r"(\w+)\.connect\s*\(", body))
        for m in re.finditer(r'add_to_group\("(\w+)"\)', body):
            joins.setdefault(m.group(1), []).append(p)
        reads.update(re.findall(r'get_nodes_in_group\("(\w+)"\)', body))
        reads.update(re.findall(r'get_first_node_in_group\("(\w+)"\)', body))
        reads.update(re.findall(r'is_in_group\("(\w+)"\)', body))
        for m in re.finditer(r'set_meta\("(\w+)"', body):
            meta_set.setdefault(m.group(1), []).append(p)
        meta_get.update(re.findall(r'(?:get_meta|has_meta|remove_meta)\("(\w+)"', body))

    def uses(name):
        # A call made by NAME — `body.call("in_flight_push", dv)`,
        # `has_method("drop")`, `connect("x", ...)` — is a real call, and the
        # reflection door is exactly how this project talks to things it
        # deliberately does not have a type for (the thrown flyers, mostly).
        # Counting only dotted calls reported every one of them as dead.
        return len(re.findall(r"(?<![\w.])%s\s*\(" % re.escape(name), code)) \
             + len(re.findall(r"\.%s\s*\(" % re.escape(name), code)) \
             + len(re.findall(r'"%s"' % re.escape(name), code))

    print("DEAD ENDS — a public method nothing calls")
    dead = []
    for name, where in sorted(declared.items()):
        if name in SKIP_METHODS or name.startswith("_"):
            continue
        # One hit is the declaration itself.
        if uses(name) <= len(where):
            dead.append((name, where[0]))
    for name, p in dead:
        print("    %-28s %s" % (name, p))
    if not dead:
        print("    (none)")

    print("\nORPHAN SIGNALS")
    orphans = []
    for name, where in sorted(signals.items()):
        if name not in emitted:
            orphans.append(("declared, never emitted", name, where[0]))
        elif name not in connected:
            orphans.append(("emitted, nothing listens", name, where[0]))
    for why, name, p in orphans:
        print("    %-28s %-26s %s" % (name, why, p))
    if not orphans:
        print("    (none)")

    print("\nONE-WAY GROUPS")
    ways = []
    for name, where in sorted(joins.items()):
        if name not in reads:
            ways.append(("joined, never looked up", name, where[0]))
    for name in sorted(reads - set(joins)):
        ways.append(("looked up, nobody joins", name, "-"))
    for why, name, p in ways:
        print("    %-20s %-26s %s" % (name, why, p))
    if not ways:
        print("    (none)")

    print("\nDEAD METADATA")
    metas = []
    for name, where in sorted(meta_set.items()):
        if name not in meta_get:
            metas.append(("written, never read", name, where[0]))
    for name in sorted(meta_get - set(meta_set)):
        metas.append(("read, never written", name, "-"))
    for why, name, p in metas:
        print("    %-20s %-24s %s" % (name, why, p))
    if not metas:
        print("    (none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
