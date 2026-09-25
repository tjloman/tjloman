#!/usr/bin/env python3
"""THE CHEAP QUESTION FIRST.

Every "find me the nearest tree / rock / beast / body / meal" asks two things of
each candidate: is it in reach, and could I get to it without drowning. The
first is a subtraction. The second is two or three reads of the terrain noise.
Every sweep asked the dear one FIRST — so a woodcutter choosing a tree asked
the water about all two hundred and twenty trees in the loaded world, including
the ones half a kilometre off, and then threw four fifths of them away on
distance. A frame in a busy town read the land 10,711 times against 91 in the
next, and the villager row was 79 ms against 6.

Asking the cheap question first returns EXACTLY the same answer — both are
filters, and the order of two filters does not change what passes both — for a
fraction of the reads. This checks every sweep by its statements, and models
what it saves.
"""
import math
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = ["scripts/world/village_watch.gd", "scripts/villager/villager_search.gd",
         "scripts/villager/villager_feeding.gd"]
WATER = re.compile(r"(_unreachable\(|would_drown_at\()")

## What one water question costs, in reads of the noise: `water_level_at` and
## `height_at` are each a seeded height at least.
READS_PER_ASK = 2


def bare(text):
    return [l.split("#")[0].rstrip() for l in text.splitlines()]


def sweeps(fail):
    print("EVERY SWEEP ASKS THE DISTANCE FIRST")
    seen = 0
    for rel in FILES:
        lines = bare((ROOT / rel).read_text())
        for i, line in enumerate(lines):
            if not WATER.search(line) or "func " in line:
                continue
            # The loop this sits in: walk up to its `for`.
            j = i
            while j > 0 and not lines[j].lstrip().startswith("for "):
                j -= 1
            loop = "\n".join(lines[j:i + 1])
            if "distance_to(" not in loop:
                fail.append("%s:%d asks about the water before it has measured "
                            "the distance" % (rel, i + 1))
            seen += 1
    print("  %d water questions, every one after its distance ... %s"
          % (seen, "yes" if not fail else "NO"))
    if seen < 10:
        fail.append("only %d sweeps found — if they moved, this is not "
                    "checking them" % seen)


def model():
    """One woodcutter choosing a tree, each way, in reads."""
    rng = random.Random(7)
    trees = 220
    loaded = 25 * 48.0 * 48.0            # the near ring
    side = math.sqrt(loaded)
    reach = 60.0                         # influence_radius * 2.5 in a big town
    here = (side / 2.0, side / 2.0)
    first = 0
    last = 0
    for _ in range(trees):
        x, y = rng.uniform(0, side), rng.uniform(0, side)
        d = math.hypot(x - here[0], y - here[1])
        first += READS_PER_ASK
        if d < reach:
            last += READS_PER_ASK
    print()
    print("ONE WOODCUTTER CHOOSING ONE TREE, OF %d" % trees)
    print("  water first: %4d reads" % first)
    print("  water last:  %4d reads   (%.0f%% fewer)" % (last, 100.0 * (1 - last / first)))
    return first, last


def main():
    fail = []
    sweeps(fail)
    first, last = model()
    if last * 2 > first:
        fail.append("asking the cheap question first saves less than half — the "
                    "model has stopped modelling the problem")
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
