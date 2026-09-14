#!/usr/bin/env python3
"""Nothing in the simulation may measure an interval against the wall clock.

The temple pauses the game. Until it existed the tree was only ever paused on
the opening screen -- before there was a creature to get anything wrong about --
so every "how long since..." in the codebase was written against
Time.get_ticks_msec(), which does not stop for a pause.

Ten quiet minutes spent reading a chart then read as ten minutes of the
creature's life: CreatureMind.shape paces character-forming by elapsed time and
would take a full-strength lesson off the very next deed, and CreatureBonds
ranks who it remembers by when it last saw them, so everyone it knew would age
out of the ledger at once.

GameState.clock advances in _process and therefore stops when the tree does.
This fails the build on any SIMULATION code that stores or compares a wall-clock
timestamp instead.

Some wall-clock use is correct, and there are exactly two ways to say so:

  * a cosmetic phase -- sin(Time.get_ticks_msec() / 60.0) for a flicker or a
    wobble. The node it animates is paused anyway, so it freezes with the world;
    all this does is pick where the wobble resumes. Recognised automatically.
  * a file that is not timing the SIMULATION at all -- the hand timing the
    player's finger to read a throw, an aim arc throttling its own redraw, the
    autosave measuring real elapsed minutes. Such a file must say so at the top:

        ## WALL CLOCK BY DESIGN: <why>

    which is the whole exemption mechanism. It is a line in the file rather
    than a list in here on purpose: the reason belongs next to the code, and
    writing one down is the point of being made to ask.

NOTE THE HAZARD THAT DECIDES THIS. It is NOT true that GameState.clock is
always the safer choice. DivineHand reads throw velocity as distance over
elapsed time between finger samples; with a frozen clock a stroke spanning a
pause has two samples a hand's width apart and zero seconds between them, and
`_stroke_is_throw` would find the hand "still moving" and hurl a rock the
player merely set down. On the wall clock that same gap reads as ten minutes,
which is a resting hand -- which is correct. Timing human input against the
world's clock is a bug in the other direction.

Run with --list to see every wall-clock use and how it was classified.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "scripts"

WALL = "Time.get_ticks_msec()"
PRAGMA = "## WALL CLOCK BY DESIGN:"
# A wall-clock reading fed straight into a trig phase is decoration.
COSMETIC = re.compile(r"(sin|cos)\s*\(\s*(float\()?\s*Time\.get_ticks_msec")


def judge(line):
    """Returns 'cosmetic', 'interval' or None for one line of GDScript."""
    if WALL not in line:
        return None
    bare = line.split("#")[0]
    if WALL not in bare:
        return None                      # only mentioned in a comment
    if COSMETIC.search(bare):
        return "cosmetic"
    return "interval"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true",
                    help="print every wall-clock use, allowed ones included")
    args = ap.parse_args()

    bad = []
    seen = 0
    for path in sorted(ROOT.rglob("*.gd")):
        text = path.read_text()
        excused = ""
        for line in text.splitlines():
            if line.startswith(PRAGMA):
                excused = line[len(PRAGMA):].strip()
                break
        for n, line in enumerate(text.splitlines(), 1):
            verdict = judge(line)
            if verdict is None:
                continue
            seen += 1
            where = "%s:%d" % (path.relative_to(ROOT.parent), n)
            if excused:
                if args.list:
                    print("  excused  %s  %s\n             (%s)"
                          % (where, line.strip(), excused))
                continue
            if verdict == "cosmetic":
                if args.list:
                    print("  cosmetic %s  %s" % (where, line.strip()))
                continue
            bad.append((where, line.strip()))

    if bad:
        print("Interval measured against the WALL CLOCK, which does not stop "
              "for a pause.\nUse GameState.clock:\n")
        for where, line in bad:
            print("  %s\n      %s" % (where, line))
        print("\n%d wall-clock use(s) in all; %d of them measure simulation time."
              "\nIf a file genuinely is not timing the simulation, say so at the"
              "\ntop of it:  %s <why>" % (seen, len(bad), PRAGMA))
        return 1
    print("checked %d wall-clock use(s) — every interval is on GameState.clock."
          % seen)
    return 0


if __name__ == "__main__":
    sys.exit(main())
