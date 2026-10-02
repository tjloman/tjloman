#!/usr/bin/env python3
"""THINK SLOWER THAN YOU MOVE.

Every villager ran its whole life on every physics tick — needs, hazards,
timers, the watchdog, the label, the state machine — two ticks a frame on a
slow device. A villager near the camera now thinks every BRAIN_TICKS ticks,
staggered, with the time between folded into delta; in between, only the feet
move (VillagerFeet.coast), on the heading the last thought chose, and a
villager standing still does nothing at all.

THE TRAP is walking twice. The thinking tick's delta is everything since the
last thought, and the feet already carried them through all but the last tick
of it — so the walk on a thinking tick takes only what was not coasted. Get
that wrong and everybody walks at up to three times their speed. This models a
walker both ways and holds the pace equal, the arrival short of overshoot, and
the statements that make both true.

Arithmetic on a model. Not a playtest.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAN = (ROOT / "scripts/villager/villager.gd").read_text()
FEET = (ROOT / "scripts/villager/villager_feet.gd").read_text()
GRIEF = (ROOT / "scripts/villager/villager_grief.gd").read_text()


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


TICKS = int(const(MAN, "BRAIN_TICKS"))
ARRIVE = const(MAN, "ARRIVE_DIST")
HZ = 30.0
DT = 1.0 / HZ


def walk(goal, speed, every, subtract=True):
    """A villager walking at `speed` toward a point `goal` metres off.
    Returns (seconds to arrive, closest it came past the goal, thoughts)."""
    x = 0.0
    owed = coasted = 0.0
    left = every
    velocity = 0.0
    thoughts = 0
    t = 0.0
    passed = 0.0
    while t < 120.0:
        t += DT
        owed += DT
        left -= 1
        if left > 0:
            if velocity and goal - x >= ARRIVE:          # coast
                x += velocity * DT
                coasted += DT
            elif velocity:
                velocity = 0.0
        else:
            left = every
            delta, owed = owed, 0.0
            thoughts += 1
            if goal - x < ARRIVE:
                return t, passed, thoughts
            walked = max(delta - coasted, 0.0) if subtract else delta
            coasted = 0.0
            velocity = speed
            x += speed * walked
        passed = max(passed, x - goal)
    return t, passed, thoughts


def source(fail):
    phys = body(MAN, "_physics_process")
    gate = phys.find("_brain_left -= 1")
    if gate < 0 or "VillagerFeet.coast(self, delta)" not in phys:
        fail.append("the villager thinks on every tick again")
    if not re.search(r"_brain_left = BRAIN_TICKS if _sim_scale <= 1\.0 else 1", phys):
        fail.append("a far villager, already on a slow clock, would think slower still")
    if phys.find("_brain_left -= 1") > phys.find("_choose()"):
        fail.append("the decision is taken before the thinking gate")
    walkf = body(FEET, "walk")
    if "var walked := maxf(delta - who._coasted, 0.0)" not in walkf \
            or "step_by(who, dir * speed * walked)" not in walkf:
        fail.append("a thinking tick walks the coasted ground again")
    coast = body(FEET, "coast")
    if "not who._coast_to.is_finite()" not in coast:
        fail.append("a thrown villager coasts on the velocity of the throw")
    if "_coast_to = Vector3.INF" not in phys:
        fail.append("nothing clears the coast between walks")
    grief = body(GRIEF, "mourn")
    if "get_physics_frames()" in grief or 'get_meta(&"horror_in"' not in grief:
        fail.append("the mourners' look-up is a tick count again — a multiple of "
                    "BRAIN_TICKS never lands on some of them")


def model(fail):
    print("A walker at 3 m/s to a point 30 m off, %d physics ticks a second:" % HZ)
    every_tick = walk(30.0, 3.0, 1)
    now = walk(30.0, 3.0, TICKS)
    doubled = walk(30.0, 3.0, TICKS, subtract=False)
    for label, r in (("every tick (before)", every_tick), ("every %d ticks" % TICKS, now),
                     ("every %d, walking twice" % TICKS, doubled)):
        print("   %-24s arrives in %5.2fs, %3d thoughts" % (label, r[0], r[2]))
    if abs(now[0] - every_tick[0]) > TICKS * DT + 1e-6:
        fail.append("the pace changed: %.2fs against %.2fs" % (now[0], every_tick[0]))
    if now[1] > 0.0:
        fail.append("a walker coasts %.2fm past where it was going" % now[1])
    if doubled[0] > every_tick[0] * 0.8:
        fail.append("the double-walk trap does not show in the model — it proves nothing")
    print("   thoughts a second near the camera: %d before, %d now; a standing villager "
          "costs nothing between them" % (HZ, HZ / TICKS))


def main():
    fail = []
    source(fail)
    model(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
