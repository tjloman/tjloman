#!/usr/bin/env python3
"""HOW LONG A GOD MAY WORK OFF THEIR OWN GROUND.

A hard edge was the wrong shape. Strips of no-man's-land run between every pair
of towns, and a god who simply cannot act in them is fencing with the map
rather than with the world. So the edge is soft, and what makes it soft is a
leash: an allowance of time outside, spent faster the further out you go.

TWO WAYS THIS GOES WRONG AND NEITHER LOOKS LIKE A BUG.

  TOO SHORT and it is a wall with a noise attached. A player who crosses the
  ring, hears a tone and is refused two seconds later has not been given a
  leash; they have been given the same refusal with extra steps.

  TOO LONG and the circles stop meaning anything. If a middling empire can
  stand a hundred metres out for half a minute, there is no reason ever to
  convert a village or walk the creature anywhere.

AND THE BEAST IS NOT A WELL. Its circle used to refill the leash whole, which
made the animal a walking refuelling station: walk it to the far edge of the
world, stand in its ring, and your reach out there was as complete as in the
middle of your own capital. Nothing about the map mattered after that, because
the map could be brought to you. It HOLDS now -- being inside any circle stops
the drain, so a full leash stays full while you follow the beast -- and it gives
back one per cent, which is a grip and not a refill.

And one way it goes wrong that IS invisible: the leash is not the prayer pool.
They are deliberately independent -- the leash is worth what your prayer power
COULD be, so converts and shrines widen it, but spending one must never touch
the other. A single stray `try_spend` in the wrong place would make every trip
out of your country quietly cost you the storm you were saving, and the only
symptom would be a reservoir that seemed to leak.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REACH = (ROOT / "scripts/miracles/miracle_reach.gd").read_text()
RING = (ROOT / "scripts/miracles/reach_ring.gd").read_text()
STATE = (ROOT / "scripts/game_state.gd").read_text()
TOWN = (ROOT / "scripts/world/village.gd").read_text()


def const(name, text, where):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9]+\.?[0-9]*)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


PER_METRE = const("PER_METRE", REACH, "miracle_reach.gd")
REFILLS_IN = const("REFILLS_IN", REACH, "miracle_reach.gd")
PITCH_FULL = const("PITCH_FULL", RING, "reach_ring.gd")
PITCH_SPENT = const("PITCH_SPENT", RING, "reach_ring.gd")
SOUNDS_BELOW = const("SOUNDS_BELOW", RING, "reach_ring.gd")
PER_VILLAGE = const("PRAYER_PER_VILLAGE", TOWN, "village.gd")

# GameState.set_max_prayer_power, as Village._update_influence calls it.
BASE = 100.0


def leash(villages, belief):
    return BASE + belief * 2.0 + villages * PER_VILLAGE


def seconds(full, metres):
    return full / (metres * PER_METRE)


REIGNS = [
    ("the first morning", 1, 25.0),
    ("two towns, devout", 2, 80.0),
    ("a small dominion", 5, 90.0),
    ("an empire", 12, 100.0),
]
OUT = [5.0, 15.0, 40.0, 100.0]

fail = []

print("HOW LONG YOU MAY STAND OUT THERE, in seconds, by how far past the edge:")
print("   %-22s %8s  %s" % ("reign", "leash",
                            "  ".join("%5.0fm" % m for m in OUT)))
for label, villages, belief in REIGNS:
    full = leash(villages, belief)
    print("   %-22s %8.0f  %s"
          % (label, full, "  ".join("%5.1f" % seconds(full, m) for m in OUT)))

first = leash(1, 25.0)
empire = leash(12, 100.0)

# -- A LEASH, NOT A WALL ----------------------------------------------------
# Just over the edge, on the first morning: long enough to get somewhere and
# back. Under a few seconds and the feature is a refusal with a tone on it.
near_first = seconds(first, 5.0)
print()
print("ON THE FIRST MORNING, five metres past the edge, you have %.0f seconds."
      % near_first)
if near_first < 15.0:
    fail.append("a new god gets %.1fs five metres off their own ground: that is "
                "a wall with a noise attached, not a leash" % near_first)

# -- A LEASH, NOT A LICENCE -------------------------------------------------
far_empire = seconds(empire, 100.0)
print("AT THE HEIGHT OF AN EMPIRE, a hundred metres out, you have %.0f seconds."
      % far_empire)
if far_empire > 45.0:
    fail.append("an empire gets %.0fs a hundred metres from anywhere it holds: "
                "there is no longer any reason to convert a village or walk the "
                "creature anywhere" % far_empire)

# -- IT COMES BACK ----------------------------------------------------------
print()
print("IT REFILLS WHOLE IN %.0f SECONDS INSIDE, whatever was left of it."
      % REFILLS_IN)
if REFILLS_IN <= 0.0 or REFILLS_IN > 20.0:
    fail.append("the leash refills in %.0fs: a trip out of your country becomes "
                "a thing you have to plan a rest around" % REFILLS_IN)

# -- THE BEAST HOLDS, AND THE TOWN REFILLS -----------------------------------
#
# Both halves are load-bearing and they fail in opposite directions. A creature
# that refills makes the map irrelevant; a creature that does not HOLD makes
# following it pointless, because the leash would run down while you stood in
# its ring.
CIRCLES = REACH[REACH.index("static func circles("):]
CIRCLES = CIRCLES[:CIRCLES.index("\n\nstatic func")]
beast_block = CIRCLES[CIRCLES.index("beast_reach(beast)"):]
beast_fills = re.search(r'"fills": ([\w.]+)', beast_block)
town_block = CIRCLES[:CIRCLES.index("beast_reach(beast)")]
town_fills = re.search(r'"fills": ([\w.]+)', town_block)
holds_at = const("HOLDS_AT", REACH, "MiracleReach")
wagon = const("REFILLS_TO", (ROOT / "scripts/world/caravan.gd").read_text(), "Caravan")
if abs(float(holds_at) - float(wagon)) > 1e-9:
    fail.append("MiracleReach.HOLDS_AT (%s) and Caravan.REFILLS_TO (%s) have "
                "drifted apart — they are the same idea written twice because "
                "a constant may not reach across these two classes, and a "
                "number written twice drifts unless something holds it"
                % (holds_at, wagon))
paying = REACH[REACH.index("static func pay_out("):]
paying = paying[:paying.index("\n\nstatic func")] if "\n\nstatic func" in paying else paying
stops_drain = "if over > 0.0:" in paying and "return" in paying

print()
print("STANDING IN A CIRCLE:")
print("   %-22s refills to %s" % ("a faithful town", town_fills.group(1) if town_fills else "?"))
print("   %-22s refills to %s (%.0f%% of a leash)"
      % ("your creature", beast_fills.group(1) if beast_fills else "?",
         float(holds_at) * 100 if holds_at else -1))
if beast_fills is None or beast_fills.group(1) == "1.0":
    fail.append("the creature's circle refills the leash whole, so the beast is "
                "a walking refuelling station and the map stops mattering — "
                "walk it to the edge of the world and your reach there is as "
                "complete as in your own capital")
if town_fills is None or town_fills.group(1) != "1.0":
    fail.append("a faithful town no longer refills the leash whole, which "
                "leaves nowhere at all to be made whole again")
if not stops_drain:
    fail.append("being inside a circle no longer stops the leash paying out, so "
                "the creature HOLDS nothing and following it across the country "
                "is no better than walking out there alone")

# What that means for the trip the request describes: leave a city full, follow
# the beast, arrive with what you left with -- and come back to it spent, and
# leave it spent.
full_leash = leash(6, 70.0)
print("   leaving a city at 100% and following the beast: still 100% on "
      "arrival (nothing drains inside a circle)")
print("   arriving spent and sitting in its ring: tops up to %.0f%% and stops."
      % (float(holds_at) * 100 if holds_at else -1))
if holds_at and float(holds_at) > 0.25:
    fail.append("the beast tops the leash up to %.0f%%, which is most of a "
                "refill wearing a smaller number — it was meant to be a grip, "
                "not a well" % (float(holds_at) * 100))

# -- AND IT IS NOT THE PRAYER POOL ------------------------------------------
# The one that would never be noticed. Everything that moves the meter lives in
# miracle_reach.gd, so nothing in there may touch the reservoir.
print()
spends = [w for w in ("try_spend", "add_prayer_power", "prayer_power -=",
                      "prayer_power +=", "prayer_power =") if w in REACH]
print("THE LEASH AND THE RESERVOIR: miracle_reach.gd %s the prayer pool."
      % ("TOUCHES" if spends else "never touches"))
if spends:
    fail.append("miracle_reach.gd touches the prayer pool (%s). The leash is "
                "worth what your prayer COULD be and must never spend it -- "
                "otherwise every trip out of your country quietly costs you the "
                "storm you were saving, and the only symptom is a reservoir "
                "that seems to leak" % ", ".join(spends))

# -- AND YOU CAN HEAR IT ----------------------------------------------------
# -- AND IT IS A WARNING, NOT FURNITURE -------------------------------------
# The first version started the moment you crossed the edge and held for as
# long as you stayed out. On a long leash that is a drone running under a whole
# expedition, and a sound that is always there is a sound nobody hears.
print()
print("THE TONE IS SILENT until %.0f%% of the leash is gone, and stops at"
      % ((1.0 - SOUNDS_BELOW) * 100.0))
print("   nothing left. How long it actually sounds for:")
for label, villages, belief in REIGNS[:1] + REIGNS[2:3]:
    full = leash(villages, belief)
    row = "  ".join("%5.1f" % (seconds(full, m) * SOUNDS_BELOW) for m in OUT)
    print("   %-22s %8s  %s" % (label, "", row))
if not 0.0 < SOUNDS_BELOW < 1.0:
    fail.append("SOUNDS_BELOW is %.2f: at 1 it is the constant hum this "
                "replaced, and at 0 it never sounds at all" % SOUNDS_BELOW)
# The pitch has to be spread over the AUDIBLE part, or the fall a player hears
# is the bottom half of the range rather than the whole of it.
# THE LINE THAT DIVIDES, not "does the name appear in the function". It appears
# twice — once to decide whether to sound at all — so looking for the name let
# the very change this forbids pass. That is the second time in two days a
# check here has been written loose enough that it could not fail.
tone_fn = RING[RING.index("func _sound_the_leash"):]
tone_fn = tone_fn[:tone_fn.index("\n\n\n")] if "\n\n\n" in tone_fn else tone_fn
if "share / maxf(SOUNDS_BELOW" not in tone_fn:
    fail.append("the pitch is not divided through SOUNDS_BELOW, so the tone "
                "only ever uses the part of its range below halfway — the fall "
                "anybody actually hears is half the octave it was tuned for")

ratio = PITCH_FULL / max(PITCH_SPENT, 0.001)
print("THE TONE falls from %.2f to %.2f -- a ratio of %.2f, which is %.1f"
      % (PITCH_FULL, PITCH_SPENT, ratio, 12.0 * math.log2(ratio)))
print("   semitones, or just over an octave.")
if ratio < 1.4:
    fail.append("the tone moves by a ratio of only %.2f between a full leash "
                "and a spent one: nobody will hear the difference, and the "
                "tone is the only warning there is" % ratio)

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: a leash, not a wall and not a licence, and you can hear it running.")
