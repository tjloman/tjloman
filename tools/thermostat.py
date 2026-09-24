#!/usr/bin/env python3
"""WHEN TO BELIEVE THE FRAMES.

The world turns itself down when the device is struggling, which is right, and
it did it on the strength of a running average of frame times, which is where
it kept being wrong. Something happens OUTSIDE the game — an editor spewing
four thousand errors into its own log, a compile, the OS indexing something, a
window losing focus — the frames go to pieces for a few seconds, the average
crosses a line, and the world dims. Turning the graphics down would not have
bought back a millisecond of it, and the player is left with a worse-looking
game and no idea why.

    "Sometimes something happens in the background, and changing quality
     wouldn't have fixed it one bit."

So three things have to be true before anything is turned down, and each rules
out a different way of being fooled:

  A STALL IS NOT A SLOW DEVICE. A frame far out of line with those around it is
  something BLOCKING, not something rendering. Measured against the running
  average rather than a fixed ceiling, so a genuinely slow machine -- where
  every frame is slow and none is out of line -- gets no protection from it at
  all. That is the property worth testing, because a filter that also hides a
  real problem is worse than no filter.

  IT HAS TO BE MOST OF THE FRAMES. Twenty dreadful frames in a quiet minute
  lift a mean over the line while fifty-nine in sixty were fine.

  AND THE LAST ONE HAD TO HAVE HELPED. If the world was turned down and the
  frame did not improve, the trouble is not in anything the tier controls.

Each is simulated below against the session it exists for, and against the
session it must NOT interfere with.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
Q = (ROOT / "scripts/quality.gd").read_text()


def number(name):
    found = re.search(r"^const %s := ([-\d.]+)" % name, Q, re.M)
    return float(found.group(1)) if found else None


C = {n: number(n) for n in ["FRAME_WARM", "FRAME_HOT", "FRAME_COOL", "HEAT_HOLD",
                            "COOL_HOLD", "FRAME_BLEND", "SPIKE", "STALL_OVER",
                            "MOSTLY", "SHARE_BLEND", "HELPED_BY", "STUBBORN_HOLD"]}
fail = []
missing = [n for n, v in C.items() if v is None]
if missing:
    print("FAIL: Quality has lost %s" % ", ".join(missing))
    sys.exit(1)

EASY, WARM, HOT = 0, 1, 2


class Thermostat:
    """Quality._process, in Python, one for one."""

    def __init__(self, resist=True):
        self.frame = 0.016
        self.over = 0.0
        self.pressure = 0.0
        self.heat = EASY
        self.dropped_at = 0.0
        self.stalls = 0
        self.drops = 0
        self.resist = resist

    def tick(self, real):
        if self.resist and real > C["STALL_OVER"] and real > self.frame * C["SPIKE"]:
            self.stalls += 1
            return
        self.frame += (real - self.frame) * C["FRAME_BLEND"]
        self.over += ((1.0 if real > C["FRAME_WARM"] else 0.0) - self.over) \
            * C["SHARE_BLEND"]
        want = self.heat
        if self.frame > C["FRAME_HOT"]:
            want = HOT
        elif self.frame > C["FRAME_WARM"]:
            want = max(self.heat, WARM)
        elif self.frame < C["FRAME_COOL"]:
            want = max(self.heat - 1, EASY)
        if want == self.heat:
            self.pressure = 0.0
            return
        if self.resist and want > self.heat and self.over < C["MOSTLY"]:
            self.pressure = 0.0
            return
        self.pressure += real
        hold = C["COOL_HOLD"]
        if want > self.heat:
            helped = (not self.resist) or self.dropped_at <= 0.0 \
                or self.frame < self.dropped_at * (1.0 - C["HELPED_BY"])
            hold = C["HEAT_HOLD"] if helped else C["HEAT_HOLD"] * C["STUBBORN_HOLD"]
        if self.pressure < hold:
            return
        self.pressure = 0.0
        if want > self.heat:
            self.dropped_at = self.frame
            self.drops += 1
        else:
            self.dropped_at = 0.0
        self.heat = want


def run(frames, resist=True):
    t = Thermostat(resist)
    for f in frames:
        t.tick(f)
    return t


GOOD, SLOW, STALL = 0.0166, 0.040, 0.30

# -- THE SESSION THIS EXISTS FOR ---------------------------------------------
#
# Four minutes of a perfectly healthy sixty frames a second, with two seconds
# of something else entirely in the middle of it -- the editor's error storm.
quiet = [GOOD] * (60 * 120) + [STALL] * 120 + [GOOD] * (60 * 120)
was, now = run(quiet, resist=False), run(quiet)
print("A HEALTHY SESSION WITH A TWO-SECOND STALL IN IT:")
print("   before: the world was turned down %d time(s)" % was.drops)
print("   now:    %d, with %d frames set aside as stalls"
      % (now.drops, now.stalls))
if now.drops:
    fail.append("a healthy session with one background stall in it still turns "
                "the world down %d time(s) — which is the whole complaint: "
                "nothing about the graphics was ever going to fix it" % now.drops)

# -- AND THE SESSION IT MUST NOT INTERFERE WITH ------------------------------
#
# A machine that genuinely cannot keep up: every frame slow, none of them out
# of line with the others. Nothing here should be filtered.
sinking = [SLOW] * (60 * 60)
sunk = run(sinking)
print()
print("A DEVICE THAT GENUINELY CANNOT KEEP UP (every frame %.0fms):"
      % (SLOW * 1000))
# IN REAL SECONDS. Counting the ticks and dividing by sixty is the frame rate
# this session does NOT have — at forty milliseconds a frame it is twenty-five.
when = -1.0
probe = Thermostat()
clock = 0.0
for f in sinking:
    probe.tick(f)
    clock += f
    if probe.drops and when < 0.0:
        when = clock
print("   turned down after %.0fs of real time, %d frames set aside as stalls"
      % (when, sunk.stalls))
if not sunk.drops:
    fail.append("a device where every single frame is 40ms is never turned "
                "down — the resistance is protecting the wrong thing, which is "
                "worse than having none")
if sunk.stalls:
    fail.append("%d frames of a steadily slow device were set aside as stalls; "
                "the stall test is measured against the running average for "
                "exactly this reason and is catching real slowness" % sunk.stalls)

# -- AND A LEVER THAT IS NOT WORKING -----------------------------------------
#
# THE SCENARIO HAS TO BE ABLE TO STEP TWICE, and the first one written could
# not: forty-millisecond frames are already past HOT, so the thermostat goes
# from EASY to HOT in a single step and there is no second step for a longer
# hold to delay. It printed a number and proved nothing.
#
# So: frames that are middling-bad (over WARM, under HOT) until the world is
# turned down once, and then WORSE rather than better — the shape of a device
# whose trouble is not in anything the tier controls.
MIDDLING, WORSE = 0.026, 0.037


def stubborn_session(resist):
    t = Thermostat(resist)
    steps, clock = [], 0.0
    for i in range(60 * 600):
        # It gets worse the moment the first step down fails to help, which is
        # what makes the second step look justified on a mean alone.
        t.tick(MIDDLING if t.drops == 0 else WORSE)
        clock += MIDDLING if t.drops == 0 else WORSE
        if len(steps) < t.drops:
            steps.append(clock)
    return steps


was, now = stubborn_session(False), stubborn_session(True)
print()
print("MIDDLING FRAMES, TURNED DOWN, AND WORSE AFTERWARDS:")
for what, steps in (("before", was), ("now", now)):
    if len(steps) > 1:
        print("   %-7s first step at %.0fs, second %.0fs later"
              % (what, steps[0], steps[1] - steps[0]))
    elif steps:
        print("   %-7s one step at %.0fs, and no second one" % (what, steps[0]))
    else:
        print("   %-7s never stepped down" % what)
if len(now) < 2 or len(was) < 2:
    fail.append("the session meant to exercise a second step down does not "
                "produce one (%d steps before, %d now), so the longer hold is "
                "a rule nothing here tests" % (len(was), len(now)))
else:
    before_gap, after_gap = was[1] - was[0], now[1] - now[0]
    if after_gap < before_gap * 2.0:
        fail.append("the second step came %.0fs after the first, against "
                    "%.0fs without the resistance — a downgrade that bought "
                    "nothing is supposed to make the next one wait and it is "
                    "barely waiting" % (after_gap, before_gap))

# -- AND THE GAME SAYS IT THE WAY THIS FILE ASSUMES --------------------------
#
# Everything above is a MODEL of the thermostat built from its constants, and a
# model agrees with itself however the game is written: the stall filter was
# deleted outright, then made an absolute ceiling, then the majority gate was
# turned off, and all three simulations went on passing. These read the code.
def code(text):
    return "\n".join(r.split("#")[0].rstrip() for r in text.split("\n")
                      if r.split("#")[0].strip())


def body_of(text, name):
    src = code(text)
    head = "func %s(" % name
    if head not in src:
        return []
    out = []
    for row in src[src.index(head):].split("\n")[1:]:
        if row and not row.startswith(("\t", " ")):
            break
        out.append(row)
    return out


thinking = body_of(Q, "_process")
filters = [r for r in thinking if "_stalls += 1" in r]
against_mean = any("_frame * SPIKE" in r for r in thinking)
majority = any("_over < MOSTLY" in r for r in thinking)
remembers = any("_dropped_at" in r for r in thinking)
print()
print("IN THE CODE: stall filter %s, measured against %s, majority gate %s."
      % ("present" if filters else "GONE",
         "the running average" if against_mean else "A FIXED CEILING",
         "present" if majority else "GONE"))
if not filters:
    fail.append("nothing sets a stall aside any more, so a two-second freeze "
                "from outside the game goes straight into the average that "
                "decides how the world looks")
if not against_mean:
    fail.append("the stall test is not measured against the running average — "
                "a fixed ceiling throws out the frames of a genuinely slow "
                "device as well, which is the failure that is WORSE than the "
                "one being fixed, because it hides a real problem")
if not majority:
    fail.append("the majority gate is gone, so a mean lifted by a burst is "
                "once again enough to turn the world down")
if not remembers:
    fail.append("the thermostat no longer remembers what the frame was when it "
                "last turned the world down, so it cannot tell whether doing "
                "so helped")

# -- AND IT SAYS WHAT IT IGNORED ---------------------------------------------
meter = (ROOT / "scripts/ui/frame_meter.gd").read_text()
tells = "stalls_ignored()" in meter and "share_over()" in meter
print()
print("THE METER %s what the thermostat threw out."
      % ("prints" if tells else "DOES NOT SAY"))
if not tells:
    fail.append("nothing reports how many frames were set aside or what share "
                "were over the line — a thermostat that quietly ignores things "
                "has to say how often, or the next person wondering why the "
                "world did not ease off has nothing to read")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: a stall is ignored, a genuinely slow device is not, and a lever "
      "that bought nothing is not pulled again in a hurry.")
