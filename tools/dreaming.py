#!/usr/bin/env python3
"""A NIGHT'S SLEEP, AND WHAT IT SETS.

Sleep was a place energy came back. He lay down, a number went up, he got up,
and nothing about the day he had just had was any different for his having
slept on it -- while the one thing in his mind that ran on a clock was
FORGETTING. Sleep was precisely the least useful thing he could do.

    "Sleeping should sort of save a dream file within the creature's mind. It
     remembers its favorite things, or what made it scared... new places it
     went to that day, and how the world was."

Four claims, and the last two are the ones that quietly rot:

  A NIGHT REHEARSES THE DAY, and how much of it sets is how well he has been
  kept -- a creature that sleeps like a stone holds most of its day and one
  that sleeps thin holds almost none of it.

  REHEARSAL DEEPENS AND DOES NOT MOVE. Consolidation may make what he thinks
  harder to lose; it may not change what he thinks. A sleep that could edit a
  value would be a way of arguing with a creature while it is unconscious.

  THE NIGHT IS IN THE GAME'S OWN TIME. A day here is 320 seconds and a night's
  sleep about ten of them. Written at a plausible twelve seconds a memory --
  which is what this file was first written at -- a cherished creature would
  have rehearsed nothing on any night of its life, and every simulation of the
  design would still have passed.

  AND EIGHT NIGHTS ARE KEPT, in words, where the player can read them.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DREAMS = (ROOT / "scripts/creature/creature_dreams.gd").read_text()
MIND = (ROOT / "scripts/creature/creature_mind.gd").read_text()
LEISURE = (ROOT / "scripts/creature/creature_leisure.gd").read_text()
WELFARE = (ROOT / "scripts/creature/creature_welfare.gd").read_text()
NEST = (ROOT / "scripts/world/creature_nest.gd").read_text()
CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()


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


def number(text, name):
    found = re.search(r"^const %s := ([-\d.]+)" % name, text, re.M)
    return float(found.group(1)) if found else None


fail = []
EVERY = number(DREAMS, "REHEARSE_EVERY")
MOST = int(number(DREAMS, "MOST_A_NIGHT") or 0)
THIN = number(DREAMS, "THIN_SETS")
KEEPS = int(number(DREAMS, "KEEPS") or 0)

# The night, read out of the game rather than assumed: when he lies down, how
# fast he recovers, and what he wakes at.
sleeping = "\n".join(body_of(LEISURE, "sleep"))
gain = re.search(r"\((\d+\.?\d*) \+ (\d+\.?\d*) \* depth\)", sleeping)
wakes = re.search(r"lerpf\((\d+\.?\d*), (\d+\.?\d*), depth\)", sleeping)
lies_at = re.search(r"if energy < (\d+\.?\d*):", "\n".join(body_of(CREATURE, "_perceive")))
deepest = re.search(r"0\.08, 1\.0", "\n".join(body_of(WELFARE, "sleep_depth")))
if not (gain and wakes and lies_at):
    fail.append("the sleep loop no longer says when he lies down, how fast he "
                "rests or what he wakes at, so nothing here knows how long a "
                "night is")
else:
    flat, per_depth = float(gain.group(1)), float(gain.group(2))
    thin_wake, deep_wake = float(wakes.group(1)), float(wakes.group(2))
    down_at = float(lies_at.group(1))

    def night(depth):
        """Seconds asleep, and how many memories that sets, at this depth."""
        energy, slept, held = down_at - 5.0, 0.0, 0
        target = thin_wake + (deep_wake - thin_wake) * depth
        while energy <= target and slept < 600.0:
            slept += 1.0 / 60.0
            energy += (flat + per_depth * depth) / 60.0
            pace = EVERY / (THIN + (1.0 - THIN) * depth)
            if held < MOST and slept >= pace * (held + 1):
                held += 1
        return slept, held

    print("A NIGHT, IN THE GAME'S OWN TIME (a day is %d seconds long):"
          % 320)
    print("   %-22s %8s %10s" % ("", "asleep", "memories set"))
    rows = {}
    for label, depth in [("cherished (deep)", 1.0), ("getting by", 0.5),
                         ("wretched (thin)", 0.08)]:
        slept, held = night(depth)
        rows[label] = held
        print("   %-22s %6.1fs %8d" % (label, slept, held))
    deep, thin = rows["cherished (deep)"], rows["wretched (thin)"]
    print("   a cherished creature sets %s what a tormented one does."
          % ("%.0f times" % (deep / thin) if thin else "everything and"))
    if deep < MOST / 2:
        fail.append("even sleeping like a stone sets only %d of a possible %d "
                    "memories a night — the rehearsal interval is written in "
                    "wall-clock time, not in the game's" % (deep, MOST))
    if thin >= deep:
        fail.append("a creature that sleeps thin sets as much as one that "
                    "sleeps deeply (%d against %d), so how it has been kept no "
                    "longer decides what its nights are worth" % (thin, deep))
    if deep < 1 or thin < 1:
        fail.append("a night sets no memories at all at one of these depths, "
                    "so sleeping is once again the least useful thing he does")

# The floor under the worst sleep has to be in the CODE, not only in the model
# above: a model that divides by its own constant agrees with itself whatever
# the game does.
# And the depth has to come from how he has been KEPT. Hard-coding it to 1.0
# left every simulation in this file passing -- the model takes depth as an
# argument, so it cannot tell whether the game asks anybody for it.
drifting = body_of(DREAMS, "drift")
if not any("welfare.sleep_depth()" in r for r in drifting):
    fail.append("drift no longer reads welfare.sleep_depth(), so every creature "
                "rehearses the same amount however it has been treated and the "
                "whole claim that cruelty costs memory is decoration")
if THIN is None or not any("THIN_SETS" in r for r in drifting):
    fail.append("drift no longer paces rehearsal against a floor for the worst "
                "sleep, so a tormented creature sets nothing at all and can be "
                "put beyond the reach of teaching by a week of neglect")

# -- REHEARSAL DEEPENS AND DOES NOT MOVE -------------------------------------
going_over = body_of(MIND, "consolidate")
deepens = any("CreatureKeeping.learned" in r for r in going_over)
moves = [r for r in going_over if re.search(r"q\[[^\]]+\] *=", r)]
print()
print("GOING OVER A MEMORY %s."
      % ("holds it without moving it" if deepens and not moves
         else "CHANGES WHAT HE THINKS"))
if not deepens:
    fail.append("consolidate no longer deepens anything, so a night's sleep "
                "sets nothing and the dream is a diary of a thing that did "
                "not happen")
if moves:
    fail.append("consolidate writes a value (%s) — sleeping may make what he "
                "thinks harder to lose, never change it, or a long night is a "
                "way of arguing with an unconscious creature" % moves[0].strip())

# -- THE NIGHT IS SPENT, AND KEPT --------------------------------------------
waking = body_of(DREAMS, "wake")
spends = any("decay(" in r for r in waking)
trims = any("pop_front()" in r for r in waking)
told = bool(body_of(DREAMS, "told"))
on_the_wall = "dreams.told(" in code(NEST)
print("WAKING %s, KEEPS %d NIGHTS, AND %s."
      % ("spends the night's forgetting" if spends else "FORGETS NOTHING",
         KEEPS, "the wall reads them" if on_the_wall and told
         else "NOBODY CAN READ THEM"))
if not spends:
    fail.append("waking spends none of the night's forgetting, so with the "
                "wall clock gone the only thing that thins anything is "
                "deciding — and a creature that never decides never forgets")
if not trims or KEEPS != 8:
    fail.append("the dream file is not held to eight nights (keeps %d, trims "
                "%s), so it grows for the length of a reign" % (KEEPS, trims))
if not (told and on_the_wall):
    fail.append("the nights are not readable on the nest wall, which is the "
                "whole of what a dream file is FOR")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: a night rehearses the day in the game's own time, sets what he "
      "has been kept well enough to keep, and is legible on his own wall.")
