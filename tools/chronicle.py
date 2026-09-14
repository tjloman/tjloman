#!/usr/bin/env python3
"""Does the record still span the whole reign after a long session?

Chronicle keeps 600 samples and, when the ring fills, THROWS AWAY EVERY OTHER
ONE and doubles the interval.  The obvious alternative -- drop the oldest, keep
the newest 600 -- is a ring buffer, and a ring buffer is wrong for this: it
silently amputates the beginning of the reign, so a player six hours in opens
the population chart and sees the last two hours with no way to tell that the
first four ever happened.

This transcribes the shipped rule out of scripts/world/chronicle.gd and reports,
for real session lengths, how much of the run the chart actually covers and at
what resolution.  --broken runs the ring-buffer version instead, so the checker
can be seen to fail on the thing it is meant to catch.
"""
import argparse
import pathlib
import re
import sys

SRC = pathlib.Path(__file__).resolve().parent.parent / "scripts/world/chronicle.gd"
GAME = pathlib.Path(__file__).resolve().parent.parent / "scripts/game_state.gd"


def read_const(path, name, default=None):
    """Pull a numeric const off a .gd file rather than duplicating it here."""
    text = path.read_text()
    m = re.search(r"^const %s(?:\s*:\s*\w+)?\s*:=\s*([0-9.]+)" % name, text, re.M)
    if not m:
        if default is not None:
            return default
        sys.exit("could not read %s from %s" % (name, path.name))
    return float(m.group(1))


KEEP = int(read_const(SRC, "KEEP"))
DAY = read_const(GAME, "DAY_SECONDS")
LIFE_DAYS = read_const(GAME, "LIFE_DAYS")
# FIRST_EVERY is derived from DAY_SECONDS in the source; read the divisor.
m = re.search(r"const FIRST_EVERY := GameState\.DAY_SECONDS / ([0-9.]+)", SRC.read_text())
FIRST_EVERY = DAY / float(m.group(1)) if m else DAY / 8.0


def run(seconds, broken=False):
    """Returns (samples held, interval now, earliest sample's time)."""
    rows = []
    every = FIRST_EVERY
    t = 0.0
    # Stepping a frame at a time for twenty hours is four million iterations for
    # nothing: the clock is deterministic, so walk sample to sample instead.
    while t <= seconds:
        rows.append(t)
        if len(rows) > KEEP:
            if broken:
                rows = rows[1:]            # the ring buffer: oldest falls off
            else:
                rows = rows[::2]           # the shipped rule: halve resolution
                every *= 2.0
        t += every
    return rows, every


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--broken", action="store_true",
                    help="use drop-oldest instead of the shipped rule")
    args = ap.parse_args()

    print("KEEP = %d samples, first interval = %.0fs, a game day = %.0fs,"
          % (KEEP, FIRST_EVERY, DAY))
    print("a villager's life = %.0f days. All read off the source.\n" % LIFE_DAYS)
    print("%-10s %8s %10s %12s %10s" %
          ("SESSION", "SAMPLES", "INTERVAL", "COVERS", "OLDEST"))

    bad = 0
    for hours in (0.5, 1, 2, 4, 8, 20):
        seconds = hours * 3600.0
        rows, every = run(seconds, args.broken)
        covered = (seconds - rows[0]) / seconds
        note = ""
        # THE PROMISE: the chart always starts at the start of the reign. One
        # sample's slack, because the newest sample lands a fraction late.
        if rows[0] > every:
            note = "  <-- the first %.0f min of the reign are GONE" % (rows[0] / 60.0)
            bad += 1
        print("%-9.1fh %8d %9.0fs %11.0f%% %9.0fm%s"
              % (hours, len(rows), every, covered * 100.0, rows[0] / 60.0, note))

    print("\nCOVERS is how much of the session the chart can draw. It must be"
          "\n100% at every length: the record loses RESOLUTION as a run gets"
          "\nlong, never the beginning of it.")
    if bad:
        print("\nFAIL: %d session length(s) had lost the start of the reign." % bad)
        return 1
    print("\nOK: every session length still spans the whole reign.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
