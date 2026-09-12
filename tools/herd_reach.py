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
import re
import sys

MANAGER = "scripts/miracles/miracle_manager.gd"
THROWN = "scripts/miracles/fireball.gd"

# How a function says "I am doing something to loose animals"...
LIVE = ('get_nodes_in_group("animals")', "ignite_animals_near",
        "frighten_animals_near")
# ...and how it says "and to the mass as well".
MASS = ('get_nodes_in_group("herds")', "bolt_from(", "scorched(", "doused(")


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
    return any(reaches(c, bodies, needles, seen)
               for c in set(re.findall(r"(?<![\w.])(\w+)\(", body)) if c != name)


def survey():
    bodies = functions(open(MANAGER, encoding="utf-8").read())
    for k, v in functions(open(THROWN, encoding="utf-8").read()).items():
        bodies.setdefault("thrown_" + k, v)
    rows = []
    for name in sorted(bodies):
        if not name.startswith("_cast_"):
            continue
        rows.append((name[len("_cast_"):],
                     reaches(name, bodies, LIVE), reaches(name, bodies, MASS)))
    rows.append(("fireball/fireblast",
                 reaches("thrown__go_off", bodies, LIVE),
                 reaches("thrown__go_off", bodies, MASS)))
    return rows


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
    return 0


if __name__ == "__main__":
    code = main()
    sys.exit(code if "--check" in sys.argv else 0)
