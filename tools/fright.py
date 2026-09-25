#!/usr/bin/env python3
"""HOW LONG DOES A FRIGHT LAST?

"Villagers, after witnessing something bad, remain in !!! fleeing in terror
status indefinitely. And they often stand still while fleeing in terror.
Literally several minutes of standing there, a day passes, and they go
hungry. At some point, they need to feel safe."

Three things made it, and none of them alone would have:

  1. THE LATCH. When a plan ends a villager asks the Spool for a turn to
     think, and stands still until it comes (see Spool: "the asker must
     stop"). In a town of six hundred at twelve frames a second that wait was
     seven seconds. A flee that timed out went into that wait STILL IN FLEE,
     so they stood under "!!!" for all of it.
  2. SCARE UNDER THE LATCH. A scare landing during the wait set FLEE but left
     the latch on, and the latch freezes a villager whatever their state says:
     "fleeing in terror" without moving a step.
  3. NOTHING EVER STEADIED THEM. A burning town calls Firefight.clear_the_way
     on every spread beat, Kindling.SPREAD_EVERY seconds, for everybody within
     FLEE_REACH who cannot beat the fire — children, elders, the pregnant. So
     for as long as the town burned they were scared again every few seconds,
     and never got to a plan long enough to eat.

This models one of them through a town fire, before and after, and reads the
statements that make the difference. Arithmetic on a model, not a playtest.
"""
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VILLAGER = (ROOT / "scripts/villager/villager.gd").read_text()
KINDLING = (ROOT / "scripts/world/kindling.gd").read_text()
FIREFIGHT = (ROOT / "scripts/villager/firefight.gd").read_text()


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


def const(text, name, where):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


SPREAD_EVERY = const(KINDLING, "SPREAD_EVERY", "kindling.gd")
FLEE_REACH = const(FIREFIGHT, "FLEE_REACH", "firefight.gd")
FRIGHT = const(VILLAGER, "FRIGHT_SECONDS", "villager.gd")
STEADY_FOR = const(VILLAGER, "STEADY_FOR", "villager.gd")
TOO_CLOSE = const(VILLAGER, "TOO_CLOSE", "villager.gd")
OLD_FRIGHT = 4.0

## THE TOWN IN THE SCREENSHOT: 343 in the line, 4 thinking a frame, 12 fps.
WAIT = 343 / (4 * 12.0)
## A fire spreading through the town for five minutes.
FIRE_FOR = 300.0
DT = 0.05


def live(new, seed):
    """One non-beater through a town fire. Seconds: (in FLEE, frozen in FLEE,
    with a plan of their own)."""
    rng = random.Random(seed)
    t = 0.0
    state = "work"
    timer = 0.0
    latched = False
    turn_at = 0.0
    steady_until = -1e9
    next_scare = rng.uniform(0, SPREAD_EVERY)
    fleeing = frozen = free = 0.0
    while t < FIRE_FOR:
        if t >= next_scare:
            next_scare += SPREAD_EVERY
            # Mostly out at the edge of the reach; now and then close by.
            dist = rng.uniform(2.0, FLEE_REACH)
            if new:
                if not (t < steady_until and dist > TOO_CLOSE):
                    state, timer, latched = "flee", FRIGHT, False
                    steady_until = t + FRIGHT + STEADY_FOR
            else:
                state, timer = "flee", OLD_FRIGHT
        if latched:
            if t >= turn_at:
                latched = False
                state = "work"          # _choose: a plan of their own
        elif state == "flee":
            timer -= DT
            if timer <= 0.0:
                latched, turn_at = True, t + WAIT
                if new:
                    state = "wander"
        if state == "flee":
            fleeing += DT
            if latched:
                frozen += DT
        elif not latched:
            free += DT
        t += DT
    return fleeing, frozen, free


def model(fail):
    print("A town fire for %.0fs; spread beat every %.0fs; reach %.0fm; decision wait %.1fs"
          % (FIRE_FOR, SPREAD_EVERY, FLEE_REACH, WAIT))
    print("  %-7s %12s %14s %16s" % ("", "under !!!", "frozen in !!!", "own plans"))
    rows = {}
    for new in (False, True):
        runs = [live(new, s) for s in range(200)]
        avg = [sum(r[i] for r in runs) / len(runs) for i in range(3)]
        rows[new] = avg
        print("  %-7s %11.0f%% %13.0f%% %15.0f%%" % ("after" if new else "before",
              *[100 * a / FIRE_FOR for a in avg]))
    before, after = rows[False], rows[True]
    if after[1] > 0.0:
        fail.append("somebody still stands frozen under !!!")
    if after[0] > FIRE_FOR * 0.25:
        fail.append("a fire keeps them in terror %.0f%% of the time" % (100 * after[0] / FIRE_FOR))
    if after[2] < FIRE_FOR * 0.5:
        fail.append("under half the fire left for plans of their own (meals among them)")
    if after[2] <= before[2]:
        fail.append("no more time for their own plans than before")


def source(fail):
    scare = body(VILLAGER, "scare")
    if "_decision_due = false" not in scare:
        fail.append("scare() leaves the latch on: they 'flee' standing still")
    if not re.search(r"if GameState\.clock < _steady_until \\\s*\n\s*and global_position"
                     r"\.distance_to\(from_pos\) > TOO_CLOSE:\s*\n\s*return", scare):
        fail.append("scare() never lets them feel safe")
    if "_steady_until = GameState.clock + FRIGHT_SECONDS + STEADY_FOR" not in scare:
        fail.append("scare() does not start the steadied window")
    if scare.find("happiness = maxf(happiness - 10.0") > scare.find("_steady_until"):
        fail.append("a steadied villager's fright costs them nothing at all")
    phys = body(VILLAGER, "_physics_process")
    m = re.search(r"State\.FLEE:\n(.*?)\n\t\tState\.", phys, re.S)
    if not m:
        fail.append("could not find the FLEE arm")
        return
    arm = m.group(1)
    if not re.search(r"if _action_time <= 0\.0:\s*\n\s*state = State\.WANDER[\s\S]*?_rethink\(\)", arm):
        fail.append("a fright that has run out waits for its next plan still in FLEE")


def main():
    fail = []
    model(fail)
    source(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
