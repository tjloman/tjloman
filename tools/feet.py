#!/usr/bin/env python3
"""VILLAGERS WALK WITHOUT THE PHYSICS ENGINE.

The bill in a big town was the villagers: 35-90ms a frame, 1,100-odd calls,
each of which asked the solver to slide a capsule across the heightmap
(`move_and_slide`) on every physics tick — standing still included. They
collide with nothing but the ground: they pass through each other and through
buildings, and steer round trees and water themselves. So a step is now the
step: across, and onto the ground as drawn (VillagerFeet.step_by).

What this holds in place:

  1. THE ONLY move_and_slide LEFT IN A VILLAGER IS THE FALL. A thrown or
     dropped villager is still a physics body, landing on the heightmap.
  2. A WALL STILL STOPS YOU. Ground rising faster than MOST_CLIMB a metre is
     refused, which is what kept people out of crater walls and off bluffs
     when the solver did it (a CharacterBody's floor gives out at 45 degrees).
  3. STANDING IS FREE. A villager who has not moved is not set on the ground
     again until GROUND_RECHECK has passed — the solver was asked every tick.
  4. NO LAND READS: footing is the chunk's own drawn grid.

Arithmetic on the source and a town. Not a frame capture.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAN = (ROOT / "scripts/villager/villager.gd").read_text()
FEET = (ROOT / "scripts/villager/villager_feet.gd").read_text()
FIRE = (ROOT / "scripts/miracles/fireball.gd").read_text()


def bare(text):
    out = []
    for line in text.splitlines():
        stripped = line.split("#")[0].rstrip()
        if stripped:
            out.append(stripped)
    return "\n".join(out)


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def const(text, name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s" % name)
    return float(m.group(1))


CLIMB = const(FEET, "MOST_CLIMB")
RECHECK = const(FEET, "GROUND_RECHECK")


def source(fail):
    code = bare(MAN)
    slides = code.count("move_and_slide()")
    phys = body(MAN, "_physics_process")
    m = re.search(r"\n\t\tState\.FALLING:\n(.*?)\n\t\tState\.", phys, re.S)
    falling = m.group(1) if m else ""
    if slides != 1 or "move_and_slide()" not in falling:
        fail.append("villager.gd calls move_and_slide %d times; the fall should be the "
                    "only one" % slides)
    if "move_and_slide" in bare(FEET):
        fail.append("VillagerFeet hands walking back to the solver")
    if "VillagerFeet.walk(" not in body(MAN, "_move_toward") \
            or "VillagerFeet.stand(" not in body(MAN, "_apply_gravity_only"):
        fail.append("the villager's movers no longer go through VillagerFeet")
    step = body(FEET, "step_by")
    if not re.search(r"if ground - here\.y > run \* MOST_CLIMB", step):
        fail.append("a step no longer refuses ground too steep to climb")
    if "drawn_height_at(" not in step or re.search(r"(?<!drawn_)height_at\(", step):
        fail.append("a step does not stand on the drawn ground")
    stand = body(FEET, "stand")
    if "_reseat_in <= 0.0" not in stand or "!= who._placed_xz" not in stand:
        fail.append("a standing villager is set on the ground every tick again")


def model(fail):
    # The crater a fireball leaves: its steepest wall, against the climb limit.
    depth = const(FIRE, "DIG_FLOOR")
    radius = const(FIRE, "GOUGE_RADIUS")
    wall = depth * (math.pi / 2.0) / radius     # steepest slope of cos(t*pi)/2+1/2
    print("A fireball's crater wall rises %.2f a metre; a villager climbs %.2f." % (wall, CLIMB))
    if wall >= CLIMB:
        fail.append("a villager cannot walk out of a single fireball crater")
    souls, steps = 550, 2.0
    before = souls * steps
    standing = 0.6                               # working, praying, sleeping, waiting
    after_settles = souls * (1 - standing) * steps + souls * standing * steps / (RECHECK * 30.0)
    print("A town of %d at %.0f physics steps a frame:" % (souls, steps))
    print("   before: %4.0f move_and_slide calls a frame (every villager, every step)" % before)
    print("   after:  %4.0f, and %.0f drawn-ground lookups (walkers each step, the "
          "standing once in %.1fs)" % (0, after_settles, RECHECK))


def main():
    fail = []
    source(fail)
    model(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
