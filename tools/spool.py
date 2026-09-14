#!/usr/bin/env python3
"""DOES THE SPOOL ACTUALLY BOUND THE FRAME, AND DOES ANYBODY STARVE?

The spool trades one quantity for another: the frame stops growing with the
population and the WAIT starts growing instead. That is only a good trade if
two things hold, and neither is obvious from reading the code.

    THE FRAME IS BOUNDED. No frame ever takes more decisions than
    Quality.decisions() allows, including the moment a whole town re-decides
    at once — a wolf over the hill, a job filling, a miracle landing. That is
    the spike the spool exists for, and it is the one a phase-based scheduler
    cannot touch, because the trigger is simultaneous by nature.

    NOBODY STARVES. Askers arrive in Godot's tree order, which never changes,
    so a naive first-come-first-served would serve the same villagers forever.
    The line is what stops that: an entry is servable only while it sits within
    `budget` live places of the front, so the order they happen to ask in
    cannot decide anything.

This replays the real queue — the same walk-the-front-of-the-line rule as
Spool.turn_to_think — against the shipped budget, for towns of a size the game
actually reaches, and reports the worst frame and the worst wait.

Usage:
    python3 tools/spool.py            towns of 50 / 200 / 500 / 2000
    python3 tools/spool.py --check    exit 1 if a frame overspends or anybody
                                      waits longer than PATIENCE
"""

import random
import re
import sys

TOWNS = [50, 200, 500, 2000]
SECONDS = 60.0
TICK = 1.0 / 60.0
## How long a villager may stand about waiting for a thought before it stops
## reading as thinking and starts reading as broken. Four seconds is roughly
## the longest pause a person watching a crowd will read as deliberate.
PATIENCE = 4.0
## How often a villager wants a decision, in seconds — the life of one plan.
## Villager._choose sets _action_time in the 3-18s range depending on the job;
## this is the busy end of it, so the figures below are pessimistic.
PLAN_LIFE = (3.0, 9.0)
## And the storms: everybody in town re-decides at once. A wolf, a filled job,
## a miracle. This is the case no stride can spread.
STORMS_A_MINUTE = 4


def budget_per_tier():
    q = open("scripts/quality.gd", encoding="utf-8").read()
    m = re.search(r"func decisions\(\) -> int:\s*\n\s*return \[([\d,\s]+)\]"
                  r"\[effective_tier", q)
    return [int(v) for v in m.group(1).split(",")]


def run(many, budget, seed=1):
    """One town, frame by frame, under the real queue rule."""
    rng = random.Random(seed)
    # Each villager: when its current plan runs out.
    due_at = [rng.uniform(*PLAN_LIFE) for _ in range(many)]
    asking = {}            # id -> the frame it first asked
    line = []              # ids, arrival order — the spool's own `_line`
    waiting = set()
    frames = int(SECONDS / TICK)
    # Storms are kept out of the last few seconds. One fired on the final
    # frame leaves a queue that never had time to drain, and reading that as
    # starvation is measuring the clock rather than the spool.
    settle = int(PATIENCE * 2.0 / TICK)
    storms = sorted(rng.sample(range(max(frames - settle, 1)), STORMS_A_MINUTE))
    worst_frame, waits, worst_wait = 0, [], 0
    for f in range(frames):
        now = f * TICK
        # Plans running out, and the storms that end everybody's at once.
        ends = [i for i in range(many) if due_at[i] <= now]
        if storms and f == storms[0]:
            storms.pop(0)
            ends = list(range(many))
        for i in ends:
            if i not in waiting:
                waiting.add(i)
                line.append(i)
                asking[i] = f
            due_at[i] = float("inf")     # no new plan until it is served

        # THE RULE, exactly as Spool.turn_to_think walks it: askers come in
        # tree order, and only the front `budget` LIVE places may be served.
        spent = 0
        head = 0
        live = 0
        while head < len(line) and live < budget and spent < budget:
            who = line[head]
            if who not in waiting:
                head += 1
                continue
            waiting.discard(who)
            spent += 1
            live += 1
            head += 1
            wait = (f - asking[who]) * TICK
            waits.append(wait)
            worst_wait = max(worst_wait, wait)
            due_at[who] = now + rng.uniform(*PLAN_LIFE)
        line = line[head:]
        worst_frame = max(worst_frame, spent)

    # THE STARVATION TEST, and it is a separate question from saturation. Stop
    # making demands and keep turning the crank: if the queue empties, every
    # entry reached the front, which is the property tree order threatens. A
    # town that simply wants more thinking than the frame can buy is SLOW, and
    # slow is the trade; a town where somebody never gets served is BROKEN.
    drain = 0
    while waiting and drain < many * 4:
        head, live, spent = 0, 0, 0
        while head < len(line) and live < budget and spent < budget:
            who = line[head]
            head += 1
            if who not in waiting:
                continue
            waiting.discard(who)
            spent += 1
            live += 1
            waits.append((frames + drain - asking[who]) * TICK)
        line = line[head:]
        drain += 1
    waits.sort()
    return dict(worst_frame=worst_frame, worst_wait=worst_wait,
                mean=sum(waits) / max(len(waits), 1),
                p99=waits[int(len(waits) * 0.99)] if waits else 0.0,
                served=len(waits), left=len(waiting))


def main():
    tiers = budget_per_tier()
    print("Quality.decisions() = %s, read off the source.\n" % tiers)
    print("%-8s %7s %8s %12s %9s %9s %9s %8s"
          % ("TIER", "BUDGET", "SOULS", "WORST FRAME", "MEAN WAIT", "p99 WAIT",
             "WORST", "STRANDED"))
    bad = False
    for tier, label in enumerate(["LOW", "MEDIUM", "HIGH"]):
        budget = tiers[tier]
        for many in TOWNS:
            r = run(many, budget)
            over = r["worst_frame"] > budget
            late = r["worst_wait"] > PATIENCE
            bad = bad or over or r["left"] > 0
            print("%-8s %7d %8d %12d %8.2fs %8.2fs %8.2fs %8d%s"
                  % (label, budget, many, r["worst_frame"], r["mean"],
                     r["p99"], r["worst_wait"], r["left"],
                     "  OVER" if over else ("  slow, and slow is the trade"
                                            if late else "")))
    print("\nWORST FRAME must never exceed BUDGET — that is the whole promise."
          "\nWORST WAIT is the longest anybody stood about with a plan run out,"
          "\n  across a minute containing %d town-wide storms (everybody"
          " re-deciding\n  on one frame, which is what a wolf or a filled job"
          " actually does).\nSTRANDED is anyone the queue never reached once"
          " demand stopped, and must be\n  zero: askers arrive in a fixed tree"
          " order, so a line served by arrival alone\n  would serve the same"
          " people forever. A town wanting more thinking than the\n  frame can"
          " buy is SLOW, which is the trade; one where somebody is never"
          "\n  served at all is broken." % STORMS_A_MINUTE)
    if "--check" in sys.argv:
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
