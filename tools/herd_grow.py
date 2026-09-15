#!/usr/bin/env python3
"""DOES THE WILD COUNTRY FILL UP?

A herd's `capacity()` is a ceiling on ONE HERD, worked from what it was founded
at and what forage it can reach. Nothing was a ceiling on a PLACE. Two herds
standing in the same meadow each grew to their own full size and the meadow
carried twice what either of them thought it could; three bands, three times.

And shedding a stray made that worse in a way nobody would guess from reading
it. `_shed_strays` founds a band out of whatever drifted too far, and it used to
hand that band the parent's `_born_head` -- copied from `_calve_off`, where it
is right, because a party of eight setting out for new country deserves the
country's worth or it starves on the day it is born. For a stray it meant every
accidental outlier founded a herd that bred up to the size of the one it left.
An evening of that is a countryside of forty-head herds that were each one
wandering deer.

This walks an evening of seasons and reports where the head count and the herd
count end up. Every number is read off scripts/animals/herd.gd.
"""
import argparse
import math
import pathlib
import re
import sys

SRC = pathlib.Path(__file__).resolve().parent.parent / "scripts/animals/herd.gd"
TEXT = SRC.read_text()


def const(name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, TEXT, re.M)
    if not m:
        sys.exit("could not read %s off herd.gd" % name)
    return float(m.group(1))


BREED = const("BREED")
SEASON = const("SEASON")
KIN_MOST = int(const("KIN_MOST"))
HEAD_NEAR_MOST = int(const("HEAD_NEAR_MOST"))
CARRY_BARE = const("CARRY_BARE")
CARRY_MOST = const("CARRY_MOST")
TAG_WORTH_IT = int(const("TAG_WORTH_IT"))
WATCH_EVERY = const("WATCH_EVERY")

# How rich the meadow is, as the forage multiplier a grazing herd would see.
# Middling: not a bare hillside, not a berry farm.
MULT = min(max(CARRY_BARE + 6 * 0.08, 0.2), CARRY_MOST)


class Band:
    def __init__(self, head, born):
        self.head = head
        self.born = born

    def ceiling(self):
        return max(self.born * MULT, 1.0)


def evening(hours, stray_inherits, place_cap, rng, meadow=1):
    """Returns (head, bands, tags) after `hours` of seasons.

    `meadow` is how many bands are already standing in this one piece of
    country — which is the case the place ceiling exists for, and which
    nothing else in the game bounds.
    """
    bands = [Band(24, 24) for _ in range(meadow)]
    seasons = int(hours * 3600.0 / SEASON)
    # Strays shed on the look-about clock, not the season clock.
    sheds_per_season = SEASON / WATCH_EVERY
    for _ in range(seasons):
        here = sum(b.head for b in bands)
        for b in list(bands):
            room = 1.0 - b.head / max(b.ceiling(), 1.0)
            change = BREED * b.head * room
            whole = int(change)
            if rng.random() < abs(change - whole):
                whole += 1 if change > 0 else -1
            # THE PLACE IS FULL, whoever is standing in it.
            if place_cap and whole > 0 and here >= HEAD_NEAR_MOST:
                whole = 0
            b.head = max(b.head + whole, 0)
            if b.head <= 0:
                bands.remove(b)
        # A stray drifts off now and then and founds its own band.
        if bands and rng.random() < 0.02 * sheds_per_season:
            parent = max(bands, key=lambda b: b.head)
            if parent.head > 1:
                parent.head -= 1
                bands.append(Band(1, parent.born if stray_inherits else 1))
        # ...and a band small enough to be a stray walks into the next herd it
        # meets, which is what _consider_company does with it.
        for b in list(bands):
            if b.head < TAG_WORTH_IT and len(bands) > 1 and rng.random() < 0.25:
                bands.remove(b)
                max(bands, key=lambda o: o.head).head += b.head
    head = sum(b.head for b in bands)
    tags = sum(1 for b in bands if b.head >= TAG_WORTH_IT)
    return head, len(bands), tags


def main():
    import random
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=4.0)
    args = ap.parse_args()

    print("read off herd.gd: BREED %.2f, a season is %.0fs, HEAD_NEAR_MOST %d,"
          "\na tag needs %d head. One meadow, founded with 24.\n"
          % (BREED, SEASON, HEAD_NEAR_MOST, TAG_WORTH_IT))
    print("%-34s %8s %8s %8s" % ("", "HEAD", "BANDS", "TAGS"))

    rows = [
        ("ONE band of deer in a meadow", 1, None),
        ("  as it shipped", 1, (True, False)),
        ("  stray founded on its own size", 1, (False, False)),
        ("  ...and a ceiling on the place", 1, (False, True)),
        ("FOUR bands sharing one meadow", 4, None),
        ("  each to its own full size", 4, (False, False)),
        ("  ...and a ceiling on the place", 4, (False, True)),
    ]
    bad = []
    for label, meadow, how in rows:
        if how is None:
            print("%-34s" % label)
            continue
        inherits, cap = how
        runs = [evening(args.hours, inherits, cap, random.Random(s), meadow)
                for s in range(9)]
        head = sum(r[0] for r in runs) // len(runs)
        bands = sum(r[1] for r in runs) / len(runs)
        tags = sum(r[2] for r in runs) / len(runs)
        note = ""
        if cap and head > HEAD_NEAR_MOST * 1.35:
            note = "  <-- over the ceiling"
            bad.append("%s: %d head in one meadow against a ceiling of %d"
                       % (label.strip(), head, HEAD_NEAR_MOST))
        # ...and the ceiling has to actually be doing something, or it is a
        # constant nobody is enforcing and this table is reassuring for nothing.
        if not cap and meadow > 1 and head <= HEAD_NEAR_MOST:
            bad.append("the uncapped four-band meadow only reached %d head, so "
                       "the ceiling of %d was never tested"
                       % (head, HEAD_NEAR_MOST))
        print("%-34s %8d %8.1f %8.1f%s" % (label, head, bands, tags, note))

    print("\nHEAD is every animal of one kind in one meadow after %.0f hours."
          "\nBANDS is how many herd nodes that is, and TAGS how many of them"
          "\nfloat a number over themselves — a herd of one is an animal you"
          "\ncan see, and a countryside of \"1 deer\" labels says nothing."
          % args.hours)
    if bad:
        print("\nFAIL:")
        for line in bad:
            print("  " + line)
        return 1
    print("\nOK: the meadow fills and then stops.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
