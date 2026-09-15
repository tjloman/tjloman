#!/usr/bin/env python3
"""HOW MANY FIREBALLS DOES IT TAKE, AND CAN A FIRE STILL CROSS A LANE?

Nothing used to CATCH fire; things were SET on fire. `Kindling.light` was called
and the thing was burning -- first touch, every time, whether it was a stack of
thatch or a stone granary. One fireball lit a street, and what a building was
made of meant nothing at all.

Heat accumulates and bleeds away now, so a material has a temper: one core on a
house is a scorch mark that cools off, three in quick succession is a house on
fire, and the nest wants a sustained bombardment. The two numbers that decides
are COOLING and the TEMPER_ table, and they pull hard against each other --
cool too fast and a fire can never spread, too slow and stone lights from one
stray lick.

So this reports both ends: what it costs the player to light a thing on purpose,
and whether a burning building can still take its neighbour with it. Every
number is read off scripts/world/kindling.gd.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
KIND = (ROOT / "scripts/world/kindling.gd").read_text()


def const(name, text=KIND, where="kindling.gd"):
    m = re.search(r"^const %s\s*:?=\s*([0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


BLAZE = const("HEAT_OF_A_BLAZE")
COOLING = const("COOLING")
NEXT_DOOR = const("HEAT_FROM_NEXT_DOOR")
SPREAD_EVERY = const("SPREAD_EVERY")
SPREAD_ODDS = const("SPREAD_ODDS")
BURN_SECONDS = const("BURN_SECONDS")
TEMPERS = {n: const("TEMPER_" + n) for n in
           ("TINDER", "TIMBER", "STORES", "STONE", "MENHIR")}

# What each thing a village raises is made of, read off the building itself so
# this table cannot drift from the game.
MADE_OF = {}
for path in sorted((ROOT / "scripts/world").glob("*.gd")):
    m = re.search(r"kindling\.temper = Kindling\.TEMPER_(\w+)", path.read_text())
    if m:
        MADE_OF[path.stem] = m.group(1)


def cores_to_light(temper, every):
    """Fireballs at `every` seconds apart before it catches, or None."""
    heat = 0.0
    for n in range(1, 41):
        heat += BLAZE
        if heat >= temper:
            return n
        heat = max(heat - COOLING * every, 0.0)
    return None


def catches_from_next_door(temper):
    """Does a neighbour burning for its whole life get this alight?"""
    heat = 0.0
    t = 0.0
    while t < BURN_SECONDS:
        t += SPREAD_EVERY
        # The roll is per reach; on average SPREAD_ODDS of them land.
        heat += NEXT_DOOR * SPREAD_ODDS
        if heat >= temper:
            return round(t)
        heat = max(heat - COOLING * SPREAD_EVERY, 0.0)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--every", type=float, default=3.0,
                    help="seconds between thrown fireballs")
    args = ap.parse_args()

    print("read off kindling.gd: a core is %.0f heat, things shed %.0f a second,"
          "\na neighbour gives %.0f every %.0fs at odds %.2f, and a fire lasts "
          "%.0fs.\n" % (BLAZE, COOLING, NEXT_DOOR, SPREAD_EVERY, SPREAD_ODDS,
                        BURN_SECONDS))
    print("%-18s %-10s %8s %14s" %
          ("", "MADE OF", "CORES", "FROM NEXT DOOR"))
    bad = []
    for thing in sorted(MADE_OF):
        made = MADE_OF[thing]
        temper = TEMPERS[made]
        cores = cores_to_light(temper, args.every)
        spread = catches_from_next_door(temper)
        print("%-18s %-10s %8s %14s"
              % (thing, made.lower(),
                 cores if cores else "NEVER",
                 ("%ds" % spread) if spread else "never"))
        if cores is None:
            bad.append("%s can never be lit by fireballs at %.0fs apart"
                       % (thing, args.every))

    house = TEMPERS["TIMBER"]
    n = cores_to_light(house, args.every)
    print("\nA HOUSE TAKES %s CORES." % n)
    # SEVERAL, which is the whole point: one was the bug.
    if n is None or not 2 <= n <= 5:
        bad.append("a house takes %s fireballs — wanted 2..5, since one was the "
                   "thing being fixed and six is a chore" % n)
    # ...AND A FIRE HAS TO BE ABLE TO CROSS A LANE, or a burning village is a
    # burning building with an audience.
    if catches_from_next_door(house) is None:
        bad.append("a burning house cannot set the house next door alight in "
                   "its whole life; fire no longer spreads at all")
    if catches_from_next_door(TEMPERS["MENHIR"]) is not None:
        bad.append("the nest catches from a neighbour burning nearby; a rock "
                   "with a fire in it should want a sustained bombardment")

    print("\nCORES is how many fireball cores, %.0fs apart, before it catches."
          "\nFROM NEXT DOOR is how long a building burning within reach takes"
          "\nto set it going — 'never' means that material shrugs off a"
          "\nneighbour, which is what stone is supposed to do." % args.every)
    if bad:
        print("\nFAIL:")
        for line in bad:
            print("  " + line)
        return 1
    print("\nOK: several cores to light a house, and fire still crosses a lane.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
