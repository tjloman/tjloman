#!/usr/bin/env python3
"""A VILLAGER'S DAY, AND A TOWN THAT STOPS TO THINK.

"At 292 villagers, dozens of them are sleeping in the streets mid-day, even
with excess housing." And: "Everyone started standing still at one point."

THE DAY. A sleeper woke the moment energy reached a hundred — ten seconds into
a two-minute night — and a rested adult may potter about after dark, so the
town worked through the night, woke nobody at dawn because nobody was asleep,
and at half a point a second a labourer was under the nap line by mid-
afternoon. Now the night is slept through (a hungry sleeper still gets up), a
nap by day ends once rested and not everybody on the same frame, and a day's
work costs about a day's energy.

THE STANDING STILL. A villager whose plan has run out stands where it is
until the Spool gives it a turn to think, and the Spool gave four a physics
tick on LOW: a hundred and twenty a second, three and a half seconds for the
four hundred and thirty in the line in a screenshot. Four was the count when
one decision could cost six hundred milliseconds; now the floor stays and
turns go on being granted while the frame's thinking is under a time budget.

Arithmetic on a model of the day and the line. Not a playtest.
"""
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAN = (ROOT / "scripts/villager/villager.gd").read_text()
NEEDS = (ROOT / "scripts/villager/villager_needs.gd").read_text()
STATE = (ROOT / "scripts/game_state.gd").read_text()
SPOOL = (ROOT / "scripts/spool.gd").read_text()
QUALITY = (ROOT / "scripts/quality.gd").read_text()


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


def const(text, name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s" % name)
    return float(m.group(1))


DAY = const(STATE, "DAY_SECONDS")
WAKE_RATE = const(MAN, "WAKE_RATE")
m = re.search(r"who\.energy - \(([0-9.]+) if working else ([0-9.]+)\)", NEEDS)
WORK_DRAIN, IDLE_DRAIN = float(m.group(1)), float(m.group(2))


def night(t):
    f = (t / DAY) % 1.0
    return f < 0.20 or f >= 0.86


def live(new, days=6, seed=1):
    """One working adult. Seconds asleep by day and by night."""
    rng = random.Random(seed)
    dt = 0.1
    t, energy, asleep = DAY * 0.25, 100.0, False
    day_asleep = night_asleep = day_total = night_total = 0.0
    drain = WORK_DRAIN if new else 0.5
    while t < DAY * (days + 0.25):
        if asleep:
            energy = min(energy + 8.0 * dt, 100.0)
            if new:
                if not night(t) and energy > 60.0 and rng.random() < dt * WAKE_RATE:
                    asleep = False
            elif energy >= 100.0 or (energy > 60.0 and not night(t)):
                asleep = False
        else:
            energy = max(energy - drain * dt, 0.0)
            if energy < 20.0 or (night(t) and energy < 85.0):
                asleep = True
        if night(t):
            night_total += dt
            night_asleep += dt if asleep else 0.0
        else:
            day_total += dt
            day_asleep += dt if asleep else 0.0
        t += dt
    return day_asleep / day_total, night_asleep / night_total


def source(fail):
    phys = body(MAN, "_physics_process")
    m = re.search(r"State\.SLEEPING:\n(.*?)\n\t\tState\.", phys, re.S)
    arm = m.group(1) if m else ""
    if "energy >= 100.0" in arm:
        fail.append("a sleeper still gets up at night the moment energy is full")
    if "not GameState.is_night() and energy > 60.0 and randf() < delta * WAKE_RATE" not in arm:
        fail.append("waking by day is not rested-and-staggered")
    if "hunger > 80.0" not in arm:
        fail.append("a hungry sleeper no longer gets up to eat")
    turn = body(SPOOL, "turn_to_think")
    if "if _thinking < Quality.think_usec():" not in turn or "budget = MOST_A_FRAME" not in turn:
        fail.append("the Spool grants a fixed count a frame however cheap thinking is")
    if "Spool.thought(Time.get_ticks_usec() - began)" not in phys:
        fail.append("villagers never tell the Spool what their thinking cost")


def line(fail):
    waiting = 430
    floor = int(re.search(r"func decisions\(\) -> int:\s*\n\s*return \[(\d+)", QUALITY).group(1))
    usec = int(re.search(r"func think_usec\(\) -> int:\s*\n\s*return \[(\d+)", QUALITY).group(1))
    most = int(const(SPOOL, "MOST_A_FRAME"))
    print()
    print("THE LINE: %d waiting, 30 physics ticks a second, LOW tier:" % waiting)
    print("  %-26s %8s" % ("a decision costs", "cleared in"))
    for cost in (0.05, 0.1, 0.25, 0.5, 1.0):
        per = max(floor, min(most, int(usec / (cost * 1000.0)) + 1))
        print("  %-26s %7.1fs   (%d a tick; before: %d, %.1fs)"
              % ("%.2f ms" % cost, waiting / (per * 30.0), per, floor, waiting / (floor * 30.0)))
    typical = max(floor, min(most, int(usec / 250.0) + 1))
    if waiting / (typical * 30.0) > 1.5:
        fail.append("at a quarter of a millisecond a decision the line still takes "
                    "%.1fs to clear" % (waiting / (typical * 30.0)))


def main():
    fail = []
    source(fail)
    print("A WORKING ADULT, six days (day %.0fs):" % DAY)
    for what, new in (("before", False), ("after", True)):
        d, n = live(new)
        print("  %-7s asleep %3.0f%% of the day, %3.0f%% of the night" % (what, 100 * d, 100 * n))
    d, n = live(True)
    if d > 0.05:
        fail.append("a worker still sleeps %.0f%% of the daylight" % (100 * d))
    if n < 0.8:
        fail.append("a worker sleeps only %.0f%% of the night" % (100 * n))
    line(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
