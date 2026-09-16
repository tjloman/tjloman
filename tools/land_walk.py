#!/usr/bin/env python3
"""WALK ACROSS THE WORLD AND WATCH WHAT THE STREAMER OWES.

The far ring is cut coarse now, which means chunks change resolution as the
player moves: fine when you arrive, coarse again behind you. Both directions
cost a mesh cut, and a mesh cut is (cells+1)^2 calls to `height_at`, each of
which is about five noise samples plus a walk of the scars. So the question
this asks is not "how many triangles" — tri_budget answers that — but

    CAN THE STREAMER EVER OWE MORE IN ONE FRAME THAN IT IS ALLOWED TO PAY?

Crossing a single chunk boundary strips a whole ROW at once: nine chunks at
unload_radius 4. Nine re-cuts on one frame is a hitch of precisely the kind the
far ring exists to remove, which is why coarsening is owed rather than done, and
paid off at COARSEN_PER_FRAME like everything else in WorldGen.

This walks a player across the world at a chosen speed, runs the real streaming
rules frame by frame off the shipped constants, and reports the worst frame and
the steady state. Every number below is read out of scripts/, never typed here.

Usage:
    python3 tools/land_walk.py              a walk at each speed, each tier
    python3 tools/land_walk.py --check      exit 1 if any frame overspends, or
                                            the wake of fine chunks grows
"""

import re
import sys

SPEEDS = [("a walk", 4.5), ("a horse", 9.0), ("flung by AIR", 26.0)]
SECONDS = 240.0
TICK = 1.0 / 60.0


def shipped():
    """The constants, read off the source rather than copied into this file."""
    q = open("scripts/quality.gd", encoding="utf-8").read()
    w = open("scripts/world/world_gen.gd", encoding="utf-8").read()

    def tiers(name):
        m = re.search(r"func %s\(\) -> \w+:\s*\n\s*return \[([\d.,\s]+)\]"
                      r"\[effective_tier" % name, q)
        return [int(float(v)) for v in m.group(1).split(",")]

    def const(name, src):
        return int(re.search(r"const %s := (\d+)" % name, src).group(1))

    return dict(chunk_cells=tiers("chunk_cells"), far_cells=tiers("far_cells"),
                load=tiers("load_radius"), unload=tiers("unload_radius"),
                sight=tiers("sight_radius"),
                chunk_size=float(re.search(r"const CHUNK_SIZE := ([\d.]+)", w).group(1)),
                # ONE OF EACH, WHICH IS WHAT A BUDGET LEAVES.
                #
                # These were counts -- one near chunk, two far ones, one
                # coarsening a frame -- and they are a millisecond budget now
                # (WorldGen.WORLD_MILLIS), because a count is a guess that every
                # chunk costs the same and they do not come close.
                #
                # A budget always does at least one thing and then stops when it
                # is over, so the WORST FRAME is one cut of the dearest kind,
                # and that is the number this tool exists to report. The fill
                # times below are therefore a pessimistic bound: the real
                # streamer does more per frame whenever the chunks are cheap.
                per_frame=1, shells=1, coarsen=1)


def samples(cells):
    """What one cut costs, in calls to height_at."""
    return (cells + 1) ** 2


def walk(k, tier, speed):
    """One traversal, frame by frame, under the real rules."""
    near, unload, sight = k["load"][tier], k["unload"][tier], k["sight"][tier]
    fine, coarse = k["chunk_cells"][tier], k["far_cells"][tier]
    size = k["chunk_size"]

    # cell -> cells it is currently cut at. Absent means not built.
    built = {}
    worst = dict(cost=0, at=0.0, what="")
    most_fine = 0
    cuts = 0
    frames = int(SECONDS / TICK)
    for f in range(frames):
        x = speed * f * TICK
        cx = int(x // size)
        spent = 0          # height samples charged to this frame

        # _fill_near: one chunk a frame, built whole or promoted.
        made = 0
        for dz in range(-near, near + 1):
            for dx in range(-near, near + 1):
                c = (cx + dx, dz)
                if built.get(c) == fine:
                    continue
                built[c] = fine
                spent += samples(fine)
                cuts += 1
                made += 1
                if made >= k["per_frame"]:
                    break
            if made >= k["per_frame"]:
                break

        if made < k["per_frame"]:
            # _fill_sight: coarse ground, two shells a frame.
            shells = 0
            for ring in range(near + 1, sight + 1):
                for d in range(-ring, ring + 1):
                    for c in [(cx + d, -ring), (cx + d, ring),
                              (cx - ring, d), (cx + ring, d)]:
                        if c in built:
                            continue
                        built[c] = coarse
                        spent += samples(coarse)
                        cuts += 1
                        shells += 1
                        if shells >= k["shells"]:
                            break
                    if shells >= k["shells"]:
                        break
                if shells >= k["shells"]:
                    break

            # _shed: free what is past sight, coarsen one that is owed.
            owed = 0
            paid = 0
            for c in list(built):
                out = max(abs(c[0] - cx), abs(c[1]))
                if out > sight:
                    del built[c]
                    continue
                if out > unload and built[c] != coarse:
                    owed += 1
                    if paid < k["coarsen"]:
                        built[c] = coarse
                        spent += samples(coarse)
                        cuts += 1
                        paid += 1
            most_fine = max(most_fine, owed)

        if spent > worst["cost"]:
            worst = dict(cost=spent, at=f * TICK,
                         what="%d samples" % spent)

    standing = sum(1 for c in built
                   if built[c] == fine and max(abs(c[0] - cx), abs(c[1])) > unload)
    tris = sum(2 * built[c] * built[c] + (8 * built[c] if built[c] == coarse else 0)
               for c in built)
    return dict(worst=worst, cuts=cuts, backlog=most_fine,
                stranded=standing, tris=tris, chunks=len(built))


def main():
    k = shipped()
    budget = k["per_frame"] * samples(k["chunk_cells"][2])
    world = open("scripts/world/world_gen.gd", encoding="utf-8").read()
    millis = float(re.search(r"const WORLD_MILLIS := ([\d.]+)", world).group(1))
    print("Read off the source: near %s cells, far %s, rings load %s / unload %s"
          " / sight %s.\nThe streamer has %.1fms of each frame and always does at"
          " least one cut, so the\nworst frame is ONE cut of the dearest kind --"
          " which is what is measured below.\n"
          % (k["chunk_cells"], k["far_cells"], k["load"], k["unload"],
             k["sight"], millis))
    print("%-8s %-14s %10s %10s %9s %9s %11s"
          % ("TIER", "SPEED", "WORST FRAME", "BUDGET", "CUTS", "BACKLOG",
             "STRANDED"))
    bad = False
    for tier, label in enumerate(["LOW", "MEDIUM", "HIGH"]):
        cap = k["per_frame"] * samples(k["chunk_cells"][tier])
        for name, speed in SPEEDS:
            r = walk(k, tier, speed)
            over = r["worst"]["cost"] > cap
            bad = bad or over or r["stranded"] > 0
            print("%-8s %-14s %10s %10s %9d %9d %11d%s"
                  % (label, name, "{:,}".format(r["worst"]["cost"]),
                     "{:,}".format(cap), r["cuts"], r["backlog"],
                     r["stranded"], "  OVER" if over else ""))
    print("\nWORST FRAME is height samples charged to the heaviest single frame"
          " of a %.0f-second\n  traversal; BUDGET is what one near-chunk cut"
          " costs, which is the rate this\n  file's streaming was already"
          " written to. BACKLOG is the most chunks ever owed a\n  coarsening at"
          " once — the row a boundary crossing strips. STRANDED is how many"
          "\n  chunks are still cut fine behind the player at the end, which"
          " must be zero:\n  a wake of full-resolution ground gives back"
          " everything the far ring is for." % SECONDS)
    if "--check" in sys.argv:
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
