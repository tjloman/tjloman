#!/usr/bin/env python3
"""THE HAND ON THE CREATURE: hold to call it, stroke to praise, slap to scold.

On a phone the creature was the hardest thing in the game to reach, and a
thumb could not reliably pick anything up either. Both came down to the hand
not looking at what was under a finger until a tick after it landed.

What holds the fix in place:

  1. A PRESS ASKS WHAT IS UNDER IT, before anything reads the answer. A thumb
     lands rather than glides, and its press arrives before the next physics
     tick: every grab was reading where the finger last lifted from.
  2. A HOLD ON THE CREATURE CALLS IT (Audience.HOLD), and a press on it that
     moves first is still the land.
  3. IT STAYS FOR YOU. HEED let go of the creature the next tick; it holds now
     while `greeting_eye` is set — in both places that let it go.
  4. STROKE AND SLAP ARE PRAISE AND SCOLD — the same two acts P and L are, so
     nothing is taught twice by two roads.
  5. A SLEEPING CREATURE IS NOT WOKEN by the hand (see tools/rest.py).
  6. THE GREETING IS READ, NOT ROLLED: no dice in it, so what it says is what
     is true of it.
  7. And with GODOT set, tools/live/audience_live.gd does all of it with real
     input events in a real engine.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()
AUDIENCE = (ROOT / "scripts/player/audience.gd").read_text()
CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()
GREETING = (ROOT / "scripts/creature/creature_greeting.gd").read_text()


def bare(text):
    return [ln.split("#")[0].rstrip() for ln in text.splitlines()
            if ln.split("#")[0].strip() and not ln.strip().startswith("##")]


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func |^## ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def source(fail):
    press = body(HAND, "_on_pointer_button")
    asked = next((i for i, ln in enumerate(press) if "_update_hover(event.position)" in ln), None)
    used = next((i for i, ln in enumerate(press) if "hover_target" in ln), None)
    print("  a press asks what is under it %s" % (
        "first" if asked is not None and (used is None or asked < used) else "TOO LATE, OR NEVER"))
    if asked is None or (used is not None and used < asked):
        fail.append("a press reads the hover before asking what is under the finger: "
                    "a thumb lands, and grabs what was under where it last lifted")
    if not any("_greeting = (hover_target as Creature)" in ln for ln in press):
        fail.append("a press on the creature does not start calling it")
    calling = body(HAND, "_tick_greeting")
    if not any("Audience.HOLD" in ln for ln in calling) \
            or not any("audience.open(" in ln for ln in calling):
        fail.append("holding the hand on the creature never opens an audience")
    moved = body(HAND, "_on_pointer_motion")
    if not any("OPEN_SLOP" in ln for ln in moved[:12]) or not any("_on_grab()" in ln for ln in moved[:14]):
        fail.append("a press on the creature that moves is no longer the land")
    heed = body(CREATURE, "_process_heed")
    heat = body(CREATURE, "_tick_heat")
    held = any("not held" in ln and "_decide" not in ln for ln in heed) \
        and any("greeting_eye == Vector3.INF" in ln for ln in heat)
    print("  it %s while you are with it" % ("stays" if held else "WANDERS OFF"))
    if not held:
        fail.append("HEED lets the creature go while an audience holds it")
    stroke = body(AUDIENCE, "_stroke")
    slap = body(AUDIENCE, "_slap")
    if not any("who.praise()" in ln for ln in stroke) or not any("who.scold()" in ln for ln in slap):
        fail.append("a stroke or a slap teaches by its own road instead of praise and scold")
    refuse = body(AUDIENCE, "refusal")
    if not any("SLEEPING" in ln for ln in refuse):
        fail.append("the hand wakes a sleeping creature to talk to it")
    dice = [ln.strip() for ln in bare(GREETING) if re.search(r"\brand[fi]?\w*\(|\bpick_random\(", ln)]
    print("  the greeting rolls %d dice" % len(dice))
    if dice:
        fail.append("the greeting is rolled, not read: %s" % dice[0])


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "tools/live/audience_live.gd"], capture_output=True, text=True,
                         timeout=400)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  in Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0 else "FAILING"))
    if ran.returncode != 0:
        fail.append("in Godot:\n" + "\n".join(ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("THE HAND ON THE CREATURE")
    source(fail)
    live(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
