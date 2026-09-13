#!/usr/bin/env python3
"""EVERY MIRACLE THAT TOUCHES SOMETHING ALIVE MUST REACH THE HERD MASS.

A herd is the unit of simulation, and only a couple of dozen head anywhere in
the world are ever real `Animal` nodes. So a miracle written the obvious way —
walk the "animals" group, do something to what is close — reaches a handful of
a two-hundred-strong herd and misses the rest, and there is nothing on screen
to say so. It looks like it worked.

That bug shipped in nearly every miracle in the game at once, and each was
found by hand, one at a time: fire, lightning, the thunderclap, the twister,
molten rock, and — worse, because they are the mercies — the rain and the
healing shower, which could not put out a fire in a herd they had just been
used to save it from.

It is not a bug any test would catch, because nothing crashes and no number
comes out wrong. So it is asserted structurally instead: if a cast function
reaches the "animals" group, it must also, somewhere down its own call chain,
reach a Herd.

Run with --check to fail the build on a regression.
"""
import os
import re
import sys

MANAGER = "scripts/miracles/miracle_manager.gd"
# The miracles that do their work from a file of their own. Each needs listing
# HERE as well, or the survey reads it as a miracle that touches nothing alive —
# a false clean, which is the one outcome this check must never produce. The
# entry is (file, the function the effect lands in, the name to print).
ELSEWHERE = [
    ("scripts/miracles/fireball.gd", "_go_off", "fireball/fireblast"),
    ("scripts/miracles/eye_volcano.gd", "_land", "eye_volcano"),
    ("scripts/miracles/storm_shroud.gd", "_tick_work", "storm_shroud"),
    ("scripts/miracles/mercy_shroud.gd", "_tick_work", "healing_shroud"),
]

# How a function says "I am doing something to loose animals". The bare
# `"animals"` catches the group named inside a list literal — `for group in
# ["pickable", "animals", "villagers"]` — which is how the gust reads it, and
# how this check missed the gust entirely on its first run.
LIVE = ('"animals"', "ignite_animals_near", "frighten_animals_near")
# ...and how it says "and to the mass as well".
MASS = ('get_nodes_in_group("herds")', "bolt_from(", "scorched(", "doused(",
        "calmed(")


def functions(text):
    """name -> body, for every top-level func in a GDScript file."""
    out, name, buf = {}, None, []
    for line in text.split("\n"):
        head = re.match(r"^(?:static )?func (\w+)\(", line)
        if head:
            if name:
                out[name] = "\n".join(buf)
            name, buf = head.group(1), [line]
        elif name is not None:
            if line and not line[0].isspace() and not line.startswith(")"):
                out[name] = "\n".join(buf)
                name, buf = None, []
            else:
                buf.append(line)
    if name:
        out[name] = "\n".join(buf)
    return out


def reaches(name, bodies, needles, seen=None):
    """Does this function, or anything it calls, contain one of these?"""
    seen = seen or set()
    if name in seen or name not in bodies:
        return False
    seen.add(name)
    body = bodies[name]
    if any(n in body for n in needles):
        return True
    # A QUALIFIED CALL IS STILL A CALL. This used to refuse to look at anything
    # with a dot in front of it, which meant a miracle living in its own file
    # and routing its burning through `MiracleManager.ignite_animals_near` read
    # as touching the loose animals and missing the mass — the exact false
    # report this whole check exists to prevent, produced by the check itself.
    # Only names that are actually functions here are ever followed, so opening
    # this up costs nothing.
    return any(reaches(c, bodies, needles, seen)
               for c in set(re.findall(r"\b(\w+)\(", body)) if c != name)


def survey():
    bodies = functions(open(MANAGER, encoding="utf-8").read())
    extra = []
    for i, (path, entry, label) in enumerate(ELSEWHERE):
        tag = "away%d_" % i
        for k, v in functions(open(path, encoding="utf-8").read()).items():
            bodies.setdefault(tag + k, v)
        extra.append((label, tag + entry))
    rows = []
    for name in sorted(bodies):
        if not name.startswith("_cast_"):
            continue
        # A cast that only hands the effect to one of the files above is judged
        # by THAT file's row, not by its own empty one.
        if name[len("_cast_"):] in [label for label, _ in extra]:
            continue
        rows.append((name[len("_cast_"):],
                     reaches(name, bodies, LIVE), reaches(name, bodies, MASS)))
    for label, entry in extra:
        rows.append((label, reaches(entry, bodies, LIVE),
                     reaches(entry, bodies, MASS)))
    return rows


def promotable():
    """EVERY KIND OF HERD MUST HAVE A BEAST IT CAN BECOME.

    A herd draws as a MultiMesh and only PROMOTES the few heads somebody is
    near — and promotion is `Animal.create(species)`. A species that can be
    scattered or rolled as a herd but has no entry in Animal.SPECIES is
    therefore a mass you can see, walk up to, put your hand on, and never
    touch: no collider, nothing to pick up, nothing to hunt. It is the exact
    shape of "you cannot interact with that herd", and the only thing standing
    between the two tables is somebody remembering.
    """
    herd = open("scripts/animals/herd.gd").read()
    chunk = open("scripts/world/chunk.gd").read()
    animal = open("scripts/animals/animal.gd").read()
    social = herd[herd.index("const SOCIAL := {"):]
    social = set(re.findall(r'^\t"(\w+)":', social[:social.index("\n}\n")], re.M))
    scattered = set(re.findall(r'"(\w+)": 0\.\d+', chunk))
    spec = animal[animal.index("const SPECIES"):]
    have = set(re.findall(r'^\t"(\w+)": \{', spec, re.M))
    return sorted((social | scattered) - have), len(social | scattered)


def main():
    rows = survey()
    broken = [n for n, live, mass in rows if live and not mass]
    print("%-20s %-9s %s" % ("miracle", "the loose", "the herd's mass"))
    print("-" * 50)
    for name, live, mass in rows:
        if not live and not mass:
            continue
        print("%-20s %-9s %s" % (name, "yes" if live else "—",
                                 "yes" if mass else "MISSES IT"))
    quiet = [n for n, live, mass in rows if not live and not mass]
    print("\nTouch nothing alive (by design — they are gifts, weather or ground):")
    print("  " + ", ".join(quiet))
    if broken:
        print("\n%d miracle(s) reach loose animals and miss the herd mass: %s"
              % (len(broken), ", ".join(broken)))
        return 1
    print("\nEvery miracle that touches something alive reaches the mass too.")
    orphans, total = promotable()
    if orphans:
        print("\n%d herd species have no Animal to promote into, so nothing in "
              "them can ever be touched: %s" % (len(orphans), ", ".join(orphans)))
        return 1
    print("All %d herd species have a beast they can become." % total)
    return 0


if __name__ == "__main__":
    code = main()
    sys.exit(code if "--check" in sys.argv else 0)
