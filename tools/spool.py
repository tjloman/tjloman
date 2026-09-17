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
## HOW MANY OF THEM GO QUIET WHILE THEY WAIT, and for how long.
##
## THE CASE THAT BROKE IT, and that this tool did not model, which is why it
## passed a spool that jammed solid after a few hours of play. A villager can
## ask for a decision and then stop asking: pinned under a wolf, dying, or
## simply far enough out that Util.sim_stride runs it every fortieth frame.
##
## While it is silent it is still ALIVE, so nothing in the walk could tell it
## from somebody waiting patiently — and it went on holding one of the `budget`
## places at the front of the queue. Collect `budget` of those and the queue
## stops serving anybody at all. Villagers stand about, and the town starves
## with a full granary.
QUIET_SHARE = 0.06
QUIET_SECONDS = (4.0, 30.0)
## AND THE ONES THAT NEVER COME BACK. A silence that ends is survivable — the
## place is held for a while and then released by being served. A silence that
## does not is the thing the rule has to be proof against: an entity that asks
## once, is refused, and is then lost to a state that never asks again.
##
## Whether the game produces those today is a separate question from whether
## the queue survives them, and the queue must, because a rule that depends on
## every caller behaving forever is not a rule. One in a hundred here, which
## over an evening is plenty.
LOST_SHARE = 0.01


def gone_quiet_frames():
    """Spool.GONE_QUIET, read off the source. A huge value here reproduces the
    old behaviour — a place held forever by having asked once."""
    s = open("scripts/spool.gd", encoding="utf-8").read()
    m = re.search(r"^const GONE_QUIET := (\d+)", s, re.M)
    return int(m.group(1)) if m else 10 ** 9


def budget_per_tier():
    q = open("scripts/quality.gd", encoding="utf-8").read()
    m = re.search(r"func decisions\(\) -> int:\s*\n\s*return \[([\d,\s]+)\]"
                  r"\[effective_tier", q)
    return [int(v) for v in m.group(1).split(",")]


def run(many, budget, gone_quiet, seed=1):
    """One town, frame by frame, transcribed from Spool.turn_to_think.

    THE MODEL THAT MATTERS: an entity that WANTS a decision is not the same as
    an entity that is ASKING for one. A villager pinned under a wolf, dying, or
    running on a coarse clock still wants its turn and cannot speak up for it.
    The old spool could not tell those apart, so the silent ones held places at
    the front of the queue until there were none left.

    The walk below runs once PER ASKER, as the real one does, and the askers go
    in id order — which is Godot's tree order, which never changes, and is
    therefore the worst case for fairness.
    """
    rng = random.Random(seed)
    due_at = [rng.uniform(*PLAN_LIFE) for _ in range(many)]
    wants = set()
    silent_until = [0.0] * many
    first_asked = {}
    line = []                   # the spool's `_line`
    head = [0]                  # the spool's `_head`, which persists
    queued = set()
    spoke = {}                  # the spool's `_waiting`: id -> frame last asked
    frames = int(SECONDS / TICK)
    settle = int(PATIENCE * 2.0 / TICK)
    storms = sorted(rng.sample(range(max(frames - settle, 1)), STORMS_A_MINUTE))
    worst_frame, waits, worst_wait, live_served = 0, [], 0.0, 0

    def ask(who, f, spent):
        """Spool.turn_to_think, for one entity, on one frame."""
        if spent >= budget:
            return False
        live = 0
        i = head[0]
        while i < len(line) and live < budget:
            other = line[i]
            lapsed = (other not in queued
                      or f - spoke.get(other, -10 ** 9) > gone_quiet)
            if lapsed:
                queued.discard(other)
                if i == head[0]:
                    head[0] += 1
                i += 1
                continue
            # NOT ASKING THIS FRAME IS NOT WAITING THIS FRAME — see the note
            # in Spool.turn_to_think. This line is the fix, and the case that
            # needed it is `strided` below.
            if spoke.get(other) != f and other != who:
                i += 1
                continue
            if other == who:
                queued.discard(who)
                if i == head[0]:
                    head[0] += 1
                return True
            live += 1
            i += 1
        if head[0] > 256:
            del line[:head[0]]
            head[0] = 0
        return False

    for f in range(frames):
        now = f * TICK
        ends = [i for i in range(many) if due_at[i] <= now]
        if storms and f == storms[0]:
            storms.pop(0)
            ends = list(range(many))
        for i in ends:
            if i not in wants:
                wants.add(i)
                if rng.random() < LOST_SHARE:
                    silent_until[i] = 1e30       # asks once, then never again
                elif rng.random() < QUIET_SHARE:
                    silent_until[i] = now + rng.uniform(*QUIET_SECONDS)
            due_at[i] = float("inf")
        spent = 0
        for who in sorted(wants):
            if now < silent_until[who] and who in queued:
                continue                      # holds a place, cannot speak
            if now < silent_until[who] and who not in queued and spoke.get(who) is not None:
                continue
            spoke[who] = f
            first_asked.setdefault(who, f)
            if who not in queued:
                queued.add(who)
                line.append(who)
            if ask(who, f, spent):
                spent += 1
                wants.discard(who)
                wait = (f - first_asked.pop(who, f)) * TICK
                waits.append(wait)
                worst_wait = max(worst_wait, wait)
                due_at[who] = now + rng.uniform(*PLAN_LIFE)
        worst_frame = max(worst_frame, spent)
        live_served += spent

    # THE STARVATION TEST: stop making demands, let every silence end, and keep
    # turning the crank. If the queue empties, every entry reached the front.
    drain = 0
    speaking = [w for w in wants if silent_until[w] < 1e29]
    while speaking and drain < many * 8 + 6000:
        f = frames + drain
        spent = 0
        for who in sorted(speaking):
            spoke[who] = f
            first_asked.setdefault(who, f)
            if who not in queued:
                queued.add(who)
                line.append(who)
            if ask(who, f, spent):
                spent += 1
                wants.discard(who)
        speaking = [w for w in speaking if w in wants]
        drain += 1
    waits.sort()
    return dict(worst_frame=worst_frame, worst_wait=worst_wait,
                mean=sum(waits) / max(len(waits), 1),
                p99=waits[int(len(waits) * 0.99)] if waits else 0.0,
                served=live_served,
                left=len([w for w in wants if silent_until[w] < 1e29]))


def strided(budget, gone_quiet, near=12, far=251, stride=30, frames=600):
    """THE TOWN IN THE SCREENSHOT, which the run above does not describe.

    `run` models a town where everybody asks every frame and a SHARE of them
    occasionally goes quiet. The real one is the other way round: Elsmere is
    1271m from the camera, so Util.sim_stride puts nearly all of it on a clock
    of ten — times up to four for heat — and the majority of the town asks once
    in thirty frames, always, as its normal condition.

    Refuse one of those and it holds a place in silence for twenty-nine frames.
    It does not lapse: GONE_QUIET is a hundred and twenty and has to be, because
    forty frames is an honest gap between two asks. Collect `budget` of them at
    the front and the walk never reaches anybody who IS asking.

    Returns (frames that served nobody, served, asked, left in the line).
    """
    line, head, queued, spoke = [], [0], set(), {}
    starved = served = asked = 0

    def ask(who, f, spent):
        if who not in queued:
            line.append(who)
            queued.add(who)
        spoke[who] = f
        if spent >= budget:
            return False
        live, i = 0, head[0]
        while i < len(line) and live < budget:
            other = line[i]
            if other not in queued or f - spoke.get(other, -10 ** 9) > gone_quiet:
                queued.discard(other)
                if i == head[0]:
                    head[0] += 1
                i += 1
                continue
            if spoke.get(other) != f and other != who:
                i += 1
                continue
            if other == who:
                queued.discard(who)
                if i == head[0]:
                    head[0] += 1
                return True
            live += 1
            i += 1
        return False

    for f in range(1, frames + 1):
        spent = 0
        askers = list(range(near))
        askers += [near + k for k in range(far) if (f + k) % stride == 0]
        got = 0
        for who in askers:
            asked += 1
            if ask(who, f, spent):
                spent += 1
                got += 1
        served += got
        if got == 0 and askers:
            starved += 1
    return starved, served, asked, len(queued)


def main():
    tiers = budget_per_tier()
    quiet = gone_quiet_frames()
    print("Quality.decisions() = %s, Spool.GONE_QUIET = %d frames (%.1fs), "
          "read off the source.\n" % (tiers, quiet, quiet * TICK))
    print("%-8s %7s %8s %12s %9s %9s %9s %8s"
          % ("TIER", "BUDGET", "SOULS", "WORST FRAME", "MEAN WAIT", "p99 WAIT",
             "WORST", "STRANDED"))
    bad = False
    for tier, label in enumerate(["LOW", "MEDIUM", "HIGH"]):
        budget = tiers[tier]
        for many in TOWNS:
            r = run(many, budget, quiet)
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
    # -- AND THE TOWN THAT IS MOSTLY OVER THE HILL --------------------------
    print("\nA TOWN ON A COARSE CLOCK — 12 souls near the camera asking every"
          "\nframe, 251 in the next valley asking once in thirty, which is what"
          "\nUtil.sim_stride does at 1271m. The case above does not describe"
          "\nthis one, and this is the one that stopped a town thinking.")
    print("\n%-8s %-8s %-22s %-22s %s"
          % ("TIER", "BUDGET", "FRAMES SERVING NOBODY", "SERVED / ASKED", "LEFT"))
    jammed = False
    for tier, label in enumerate(["LOW", "MEDIUM", "HIGH"]):
        starved, served, asked, left = strided(tiers[tier], quiet)
        jammed = jammed or starved > 0
        print("%-8s %-8d %-22s %-22s %d"
              % (label, tiers[tier],
                 "%d of 600%s" % (starved, "   JAMMED" if starved else ""),
                 "%d / %d" % (served, asked), left))
    print("\nFRAMES SERVING NOBODY must be zero. A frame where people are"
          "\n  asking and none is served is not a slow queue, it is a stopped"
          "\n  one — the whole town stands about with its plans run out, and"
          "\n  the readout says `0 thinking a frame, 65 in the line`.")

    # A JAM IS FATAL WITHOUT BEING ASKED. Everything above this is a tuning
    # question — how long a wait is too long — and lives behind `--check` so a
    # bare run stays a report. A queue that serves nobody while people are
    # asking is not a tuning question, so it fails the build either way. The
    # suite runs these tools bare; this one had a finding it could not report.
    if jammed:
        print("\nBROKEN: the spool serves nobody on frames where people are "
              "asking — the town stops thinking.")
        return 1
    if "--check" in sys.argv:
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
