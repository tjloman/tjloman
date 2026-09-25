#!/usr/bin/env python3
"""HOW LONG A TREE BURNS, AND HOW FAST A WOOD GOES.

A tree burned for nine seconds. That is a flash: long enough to be a mechanic
for clearing forest, far too short to be a THING -- you cannot carry a burning
tree anywhere, cannot javelin one across a valley and watch it arrive, cannot
use one as a torch. And a blazing pine turning end over end is the best picture
this game has in it.

But burn time and spread pull hard against each other. A tree that burns five
times as long gets five times as many chances to light its neighbours, so
lengthening the burn without touching the odds turns every woodland into a
firestorm that takes the whole map. The interesting fire is the one that CREEPS:
it should walk through a stand over a minute or two, not flash across it, and it
should still stop at a gap.

This reports both from the numbers in wild_tree.gd: how long one tree lasts, how
long before it takes its neighbour, and how long a stand of trees burns through.
"""
import argparse
import math
import pathlib
import random
import re
import sys

SRC = pathlib.Path(__file__).resolve().parent.parent / "scripts/world/wild_tree.gd"
TEXT = SRC.read_text()


def const(name):
    m = re.search(r"^const %s\s*:?=\s*([0-9.]+)" % name, TEXT, re.M)
    if not m:
        sys.exit("could not read %s off wild_tree.gd" % name)
    return float(m.group(1))


# A TREE BURNS FOR WHAT IT IS WORTH, in seconds — the running Fibonacci sum in
# TIMBER, which this game already reckons a tree's value in. BURN_SECONDS is
# only the middle of that range and is what the spread is reasoned about.
import ast
TIMBER = ast.literal_eval(
    re.search(r"const TIMBER: Array\[int\] = (\[[^\]]*\])", TEXT).group(1))
BURN = const("BURN_SECONDS")
SPREAD_RADIUS = const("SPREAD_RADIUS")
SPREAD_CHANCE = const("SPREAD_CHANCE")
# The fire tick used to be a bare literal in `_burn`. It is a named function
# now, because the seconds of heat a burning tree hands the stone beside it are
# paid in exactly these units — see RockDeposit.warm and tools/forge.py — and a
# beat written twice is a beat that drifts. Read off the function.
TICK = float(re.search(r"func _fire_beat_length\(\) -> float:\s*\n\s*return ([0-9.]+)",
                       TEXT).group(1))


def stand(trees, spacing, seed):
    """A row of trees `spacing` apart, lit at one end. Returns (took, burnt)."""
    rng = random.Random(seed)
    alight = {0: BURN * rng.uniform(0.8, 1.2)}
    ash = set()
    t = 0.0
    first_catch = None
    while alight and t < 900.0:
        t += TICK
        for i in list(alight):
            alight[i] -= TICK
            for j in range(trees):
                if j in alight or j in ash:
                    continue
                if abs(j - i) * spacing > SPREAD_RADIUS:
                    continue
                if rng.random() < SPREAD_CHANCE:
                    alight[j] = BURN * rng.uniform(0.8, 1.2)
                    if first_catch is None:
                        first_catch = t
            if alight[i] <= 0.0:
                del alight[i]
                ash.add(i)
    return t, len(ash), first_catch


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trees", type=int, default=12)
    ap.add_argument("--spacing", type=float, default=4.0)
    args = ap.parse_args()

    print("read off wild_tree.gd: a tree burns %.0fs, rolls every %.1fs at %.2f "
          "per\nneighbour within %.0fm.\n" % (BURN, TICK, SPREAD_CHANCE,
                                              SPREAD_RADIUS))
    runs = [stand(args.trees, args.spacing, s) for s in range(24)]
    took = sum(r[0] for r in runs) / len(runs)
    burnt = sum(r[1] for r in runs) / len(runs)
    caught = [r[2] for r in runs if r[2] is not None]
    first = sum(caught) / len(caught) if caught else None

    print("A TREE BURNS FOR WHAT IT IS WORTH, in seconds:")
    print("   " + "  ".join("%d:%ds" % (i + 1, v)
                            for i, v in enumerate(TIMBER)))
    print("\nONE MIDDLING TREE burns for %.0fs." % BURN)
    print("IT TAKES ITS NEIGHBOUR after %s."
          % ("%.1fs" % first if first else "never"))
    print("A STAND of %d trees %.0fm apart: %.0f of them gone in %.0fs."
          % (args.trees, args.spacing, burnt, took))

    bad = []
    # LONG ENOUGH TO BE A THING. You have to be able to pick one up, carry it,
    # and throw it somewhere while it is still alight.
    # A FULL-GROWN TREE HAS TO BE WORTH CARRYING. That is the whole ask: long
    # enough to pick up, walk somewhere with, and throw while still alight.
    if TIMBER[-1] < 90:
        bad.append("the biggest tree burns %ds — not long enough to carry one "
                   "anywhere, which is most of what a burning tree is for"
                   % TIMBER[-1])
    if TIMBER[0] > 3:
        bad.append("a sapling burns %ds; the small end of the curve is supposed "
                   "to be almost nothing" % TIMBER[0])
    if BURN < 25.0:
        bad.append("a tree burns %.0fs — too short to carry one anywhere, "
                   "which is most of what a burning tree is for" % BURN)
    # AND IT HAS TO CREEP, NOT FLASH. A fire that takes its neighbour within a
    # second or two is an explosion with extra steps.
    if first is not None and first < 3.0:
        bad.append("fire takes the next tree in %.1fs; a wood should burn "
                   "through, not go up" % first)
    if first is None:
        bad.append("fire never reaches the next tree at all")
    # ...and it still has to finish. A blaze nobody can outlast is not a tool.
    if took > 420.0:
        bad.append("a stand of %d takes %.0fs to burn out — a fire the player "
                   "cannot outwait is weather, not a tool" % (args.trees, took))

    # AND A GAP STILL STOPS IT. Contained-by-default is the whole reason fire
    # is usable as a tool rather than as a thing that happens to you, and it is
    # the first casualty of anybody raising SPREAD_RADIUS to "make fire better".
    wide = args.spacing if args.spacing > SPREAD_RADIUS else SPREAD_RADIUS + 2.0
    across = [stand(args.trees, wide, s)[1] for s in range(8)]
    if max(across) > 1:
        bad.append("fire crossed a %.0fm gap against a %.0fm reach and took %d "
                   "trees; a blaze that leaps gaps is weather"
                   % (wide, SPREAD_RADIUS, max(across)))

    print("\nA burning tree has to last long enough to be CARRIED and thrown,"
          "\nand a wood has to burn THROUGH rather than go up. Those two pull"
          "\nagainst each other: every extra second of burn is another roll"
          "\nagainst every neighbour.")
    if bad:
        print("\nFAIL:")
        for line in bad:
            print("  " + line)
        return 1
    print("\nOK: a tree burns long enough to carry, and a wood creeps.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
