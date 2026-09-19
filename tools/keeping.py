#!/usr/bin/env python3
"""WHAT HE KEEPS.

Forgetting used to run to zero, once a second, forever. Every value in the
mind drifted toward nothing at a fixed rate whatever its history, so a thing
learned four hundred times and a thing learned once were both on their way out
at the same speed. A creature could not accumulate anything; it could only be
recently reminded. And because it was charged by the CLOCK rather than by
living, an hour of standing still cost exactly what an hour of hard work did,
and a night left running cost everything.

    "Retention floors, just like how it's limited from shrinking to 1. There's
     no forgetting a concept once it has been learned... there's no point to
     having to relearn things at a rate slower than it forgets things.
     Retention is key to growth and progression."

Three claims, and the third is the one that would be easiest to let rot:

  A FLOOR UNDER EVERYTHING. Each value fades toward what its own history has
  earned -- the deepest it ever reached, times what repetition made of it --
  and never past that. One store left fading to zero is one concept the
  creature still has to relearn forever.

  CHARGED BY LIVING. Forgetting is spent at a decision and in sleep, never on
  a wall clock, like every other slow number in this game.

  AND FORGETTING IS SLOWER THAN LEARNING, in every single store. This is the
  claim that cannot be eyeballed: the rates live in four files, they are named
  differently in each, and a pair that inverts does not crash anything -- it
  just quietly makes that kind of knowledge unobtainable.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEEPING = (ROOT / "scripts/creature/creature_keeping.gd").read_text()
MIND = (ROOT / "scripts/creature/creature_mind.gd").read_text()
BELIEFS = (ROOT / "scripts/creature/creature_beliefs.gd").read_text()
BONDS = (ROOT / "scripts/creature/creature_bonds.gd").read_text()
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

# -- FORGETTING IS SLOWER THAN LEARNING --------------------------------------
#
# Every store that fades, beside the rate the same store learns at. A store
# missing from this table is a store nobody is holding to the rule, so the
# count is checked against the fades that actually exist in the files.
PAIRS = [
    ("what it thinks of a deed", MIND, "FORGET", MIND, "LR"),
    ("what circumstances mean", BELIEFS, "WEIGHT_FADE", BELIEFS, "WEIGHT_LR"),
    ("what the world is like", BELIEFS, "LORE_FADE", BELIEFS, "LORE_LR"),
    ("how a place feels", BELIEFS, "PLACE_FADE", BELIEFS, "PLACE_LR"),
    ("the order it does things in", BELIEFS, "RITE_FADE", BELIEFS, "RITUAL_LR"),
    ("what it thinks of a person", BONDS, "FADE", BONDS, "REGARD_LR"),
]
print("FORGETTING AGAINST LEARNING, store by store:")
for what, ftext, fname, ltext, lname in PAIRS:
    forgets, learns = number(ftext, fname), number(ltext, lname)
    if forgets is None or learns is None:
        fail.append("the rates for %s (%s / %s) are gone, so nothing holds "
                    "that store to forgetting slower than it learns"
                    % (what, fname, lname))
        continue
    ratio = learns / forgets if forgets else 0.0
    print("   %-28s learns %.3f, forgets %.4f  — learning is %3.0fx faster"
          % (what, learns, forgets, ratio))
    if forgets >= learns:
        fail.append("%s forgets (%.4f) at least as fast as it learns (%.4f), "
                    "so the creature spends its life relearning it and never "
                    "gets to anything new" % (what, forgets, learns))

# Any store fading straight to zero has no floor under it at all.
loose = []
for name, text in [("the mind", MIND), ("its beliefs", BELIEFS),
                   ("its people", BONDS)]:
    for row in body_of(text, "fade") + body_of(text, "decay"):
        if "move_toward(" in row and "0.0," in row:
            loose.append((name, row.strip()))
print()
print("EVERY STORE FADES TOWARD %s."
      % ("what it has earned" if not loose else "ZERO, SOMEWHERE"))
for name, row in loose:
    print("   %-12s %s" % (name, row))
    fail.append("%s still fades something to zero (%s), so that concept has "
                "to be learned again from nothing every time it goes quiet"
                % (name, row))

# -- CHARGED BY LIVING -------------------------------------------------------
per_second = [r for r in code(CREATURE).split("\n")
              if "mind.decay(" in r or "_decay_tick" in r]
at_a_choice = any("decay(PER_CHOICE)" in r for r in body_of(MIND, "choose"))
print()
print("FORGETTING IS CHARGED %s."
      % ("by deciding, not by the clock" if not per_second and at_a_choice
         else "ON A WALL CLOCK"))
if per_second:
    fail.append("the creature still spends forgetting on a timer (%s), which "
                "is what made an hour of standing still cost the same as an "
                "hour of living" % per_second[0].strip())
if not at_a_choice:
    fail.append("nothing charges forgetting at a decision any more, so either "
                "it never happens or something else is paying for it")

# -- WHAT A FLOOR IS WORTH ---------------------------------------------------
most = number(KEEPING, "KEPT_MOST")
half = number(KEEPING, "HALF_KEPT")
if most is None or half is None:
    fail.append("CreatureKeeping's floor constants are gone")
else:
    kept = lambda n: most * n / (n + half)
    print()
    print("WHAT REPETITION MAKES PERMANENT:")
    print("   learned  " + "".join("%7d" % n for n in (1, 3, 12, 30, 50, 100, 400)))
    print("   kept     " + "".join("%6.0f%%" % (kept(n) * 100)
                                   for n in (1, 3, 12, 30, 50, 100, 400)))
    # A NIGHT OF NOT USING IT. The creature decides about once every fifteen
    # seconds (see tools/deeds.py), so a fourteen-hour night is some 3,400
    # decisions -- which used to be 50,400 seconds of decay and is now this.
    forget = number(MIND, "FORGET") * number(MIND, "PER_CHOICE")
    print()
    print("A VALUE AT ITS FULL 4.00, THEN A NIGHT OF NEVER COMING UP AGAIN:")
    for times in (1, 12, 50, 400):
        value, floor_at = 4.0, 4.0 * kept(times)
        for _ in range(3400):
            value = max(value - forget, floor_at)
        print("   learned %3d times -> %.2f left of 4.00 (%d%%)"
              % (times, value, round(value / 4.0 * 100)))
        if times >= 50 and value < 1.0:
            fail.append("something learned %d times is down to %.2f of 4.00 "
                        "after one night of not coming up, which is the "
                        "overnight wipe again wearing a floor" % (times, value))
    once = 4.0
    for _ in range(3400):
        once = max(once - forget, 4.0 * kept(1))
    print("   — and a thing done once is gone, which is the other half of it.")
    if once > 1.0:
        fail.append("a thing done exactly once survives a night at %.2f of "
                    "4.00, so nothing is ever forgotten and the creature's "
                    "mind only ever fills up" % once)

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: every store fades toward what it earned, at a rate its own "
      "learning outruns, and only ever while he is living.")
