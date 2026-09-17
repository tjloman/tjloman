#!/usr/bin/env python3
"""A SLOW DEVICE MUST NOT MAKE ITSELF SLOWER, AND SOMEBODY MUST BE ABLE TO SEE WHY.

A phone reported 133.1ms a frame -- seven and a half pictures a second -- and
there was no way to tell from here which half of the machine was spending it.
Everything after that question is guessing, and guessing is how a week goes into
making the fast half faster.

So two things ship together and this file guards both.

THE INSTRUMENT. FrameMeter prints the split: what GDScript cost, what was left
over for the driver and the fragment pass, and -- the number this was built for
-- how many physics ticks went into one drawn picture. It has to be openable on
a phone, which is the only machine whose frame time anybody needs to look at,
and F7 is not a key a phone has.

THE HOLE. Godot runs physics on a fixed clock: every drawn frame it works out
how many ticks it owes and runs them all, up to `max_physics_steps_per_frame`.
At the engine defaults -- sixty a second, ceiling of eight -- a frame of 133ms
owes eight, and runs eight: every villager, every animal, every rigid body,
simulated eight times for one picture. Which makes the frame longer, which owes
more ticks. It is not a slope, it is a hole, and the arithmetic below says how
deep.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
QUALITY = (ROOT / "scripts/quality.gd").read_text()
METER = (ROOT / "scripts/ui/frame_meter.gd").read_text()
HUD = (ROOT / "scripts/ui/hud.gd").read_text()
MAIN = (ROOT / "scripts/main.gd").read_text()


def code(text):
    """Source with its comments taken out. A note about a thing is not it."""
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


def number(text, name):
    found = re.search(r"^const %s := ([-\d.]+)" % name, text, re.M)
    return float(found.group(1)) if found else None


fail = []

hz = number(QUALITY, "PHYSICS_HZ_HANDHELD")
most = number(QUALITY, "STEPS_MOST_HANDHELD")
desk_hz = number(QUALITY, "PHYSICS_HZ_DESK")
desk_most = number(QUALITY, "STEPS_MOST_DESK")
if None in (hz, most, desk_hz, desk_most):
    print("BROKEN: the fixed clock is not set anywhere in Quality")
    sys.exit(1)


def steps(frame_ms, rate, ceiling):
    """What Godot runs: the ticks owed since the last frame, up to the ceiling."""
    return min(math.floor(frame_ms / (1000.0 / rate)) or 1, ceiling)


# -- THE HOLE, MEASURED ------------------------------------------------------
print("HOW MANY TIMES THE WHOLE WORLD IS SIMULATED FOR ONE PICTURE:")
print("   %-12s %-22s %-22s" % ("frame", "60 Hz, ceiling 8", "%d Hz, ceiling %d"
                                % (hz, most)))
for ms in (16.7, 33.3, 50.0, 66.7, 100.0, 133.1, 200.0):
    was = steps(ms, 60, 8)
    now = steps(ms, hz, most)
    print("   %-12s %-22s %-22s%s"
          % ("%.1f ms" % ms,
             "x%d%s" % (was, "  PINNED" if was >= 8 else ""),
             "x%d%s" % (now, "  pinned" if now >= most else ""),
             "   <- the phone" if abs(ms - 133.1) < 0.1 else ""))
if most >= 8:
    fail.append("the step ceiling on a handheld is still %d, so a phone that "
                "falls behind simulates the world eight times for one picture "
                "and every extra millisecond buys it more work" % most)
if hz >= 60:
    fail.append("a handheld still runs %d physics ticks a second — nothing in "
                "this game needs sixty, and the hand was taken off the physics "
                "tick long ago precisely so it would not wait for one" % hz)

# WHAT IT IS WORTH, as a share of the physics work in a pinned frame. The split
# between the fixed work and the per-step work is exactly what nobody knows yet
# -- which is why the meter ships alongside this -- so it is shown for a range
# of splits rather than asserted at one.
print()
print("WHAT THAT IS WORTH at the phone's 133.1ms, by how much of it is physics.")
print("(The split is the thing nobody knows yet. That is what the meter is for.)")
print("   %-16s %-14s %-14s %s" % ("physics share", "one step", "new frame", "fps"))
best = 0.0
for share in (0.3, 0.5, 0.7):
    fixed = 133.1 * (1.0 - share)
    per_step = 133.1 * share / 8.0
    # Settle the loop: the frame decides the steps which decide the frame.
    frame = 133.1
    for _ in range(40):
        frame = fixed + steps(frame, hz, most) * per_step
    best = max(best, 1000.0 / frame)
    print("   %-16s %-14s %-14s %.1f"
          % ("%d%%" % (share * 100), "%.1f ms" % per_step,
             "%.0f ms" % frame, 1000.0 / frame))
print()
print("   ...so the clock alone is worth roughly %.1fx. Reaching 25 fps from"
      % (best / 7.5))
print("   7.5 needs 3.3x, so this is a piece of it and not the whole.")

# -- THE INSTRUMENT ----------------------------------------------------------
print()
says = {
    "the script/draw split": "TIME_PROCESS",
    "the physics time": "TIME_PHYSICS_PROCESS",
    "the draw calls": "RENDER_TOTAL_DRAW_CALLS_IN_FRAME",
    "when they are pinned": "max_physics_steps_per_frame",
}
print("THE METER REPORTS:")
for what, needle in says.items():
    there = needle in code(METER)
    print("   %-24s %s" % (what, "yes" if there else "NO"))
    if not there:
        fail.append("the frame meter does not report %s, which is one of the "
                    "things it exists to answer" % what)

# THE STEPS ARE COUNTED IN _physics_process, and counted means INCREMENTED.
# `_ticks` appearing in this file says nothing — it is declared once and zeroed
# once whether or not anything ever adds to it, so looking for the NAME is a
# check that cannot fail. Look for the statement.
ticked = any(re.search(r"_ticks (\+=|= _ticks \+)", r)
             for r in body_of(METER, "_physics_process"))
print("   %-24s %s" % ("the steps a frame", "yes" if ticked else "NO"))
if not ticked:
    fail.append("nothing in the meter's _physics_process counts a tick, so the "
                "steps-a-frame figure — the number it was built for — is zero "
                "for ever and reads as a healthy device")

# AND IT OPENS ON A PHONE. F7 is not a key a phone has, and a phone is the only
# machine whose frame time anybody needs to look at.
by_key = "toggle_frames" in code(MAIN) and "toggle_frames" in code(HUD)
by_hand = any("_frames_button" in r and "pressed.connect" in r
              for r in code(HUD).split("\n"))
print()
print("IT OPENS: %s%s" % ("by key" if by_key else "NOT BY KEY",
                          ", and by a button" if by_hand else ", AND BY NOTHING ELSE"))
if not by_key:
    fail.append("the frame meter has no key bound to it")
if not by_hand:
    fail.append("the frame meter can only be opened with a keyboard — which is "
                "the one thing the device it was built to measure does not have")

# AND IT COSTS ALMOST NOTHING TO LEAVE OPEN. A readout rewritten every frame is
# string formatting and a Label relayout inside the frame it is measuring.
every = number(METER, "EVERY")
rewrites = any("_next" in r for r in body_of(METER, "_process"))
print("IT REWRITES every %.1fs%s" % (every or 0.0,
                                     "" if rewrites else " — NO, EVERY FRAME"))
if not every or every < 0.15 or not rewrites:
    fail.append("the meter rewrites its readout every frame, so it is string "
                "formatting and a label relayout inside the frame it claims to "
                "be measuring")

# The counting must NOT be behind the visibility check, or the averages are
# wrong for the first half-second after it is opened — which is the half-second
# somebody holding a phone actually reads.
counts = body_of(METER, "_process")
hidden = next((i for i, r in enumerate(counts) if "if not visible:" in r), None)
tallied = next((i for i, r in enumerate(counts) if "_steps_seen = " in r), None)
print("IT COUNTS %s it is open."
      % ("whether or not" if hidden is not None and tallied is not None
         and tallied < hidden else "ONLY WHILE"))
if hidden is None or tallied is None or tallied > hidden:
    fail.append("the meter only counts while it is open, so every number in it "
                "is wrong for the first moments after it is opened — which is "
                "when somebody holding a phone reads it")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: the clock cannot run away, and the frame can be read on the device.")
