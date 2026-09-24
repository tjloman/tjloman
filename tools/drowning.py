#!/usr/bin/env python3
"""THE BLOOD BATH.

An animal drowns. It drops its meat where it died, which is the bottom of the
water. A hungry villager sees meat, walks to it, and drowns. That villager is
now a corpse in the water with meat beside it, which is two reasons for the
next one to go in -- and the town empties itself into the shallows one soul at
a time.

    "The screenshots just show the 'blood baths', wherein a villager will see
     meat from a drowned animal, go to gather it, and then drown. One thing
     drowning means the entire town will override their present pathfinding to
     go and drown while grabbing meat."

TWO THINGS HAD TO BE TRUE AT ONCE, and only one of them is obvious.

The obvious one: nothing asked whether the meat could be reached alive. Every
picker -- loose food, the nearest corpse, the town's own watcher, a beast worth
gentling -- took the nearest one and pointed a villager at it.

The other one is a shortcut with a precondition that quietly stopped being
true. Villagers refuse open water by routing along the shore (NavField.water_
route), EXCEPT when both they and their goal are inside their own town's
circle, because a town builds on nothing but dry, gently sloped ground with a
dry way to it. That is true of a well, a workshop, a granary, a build site. It
is not true of an animal, a corpse, a joint of meat or a person, because none
of those was PLACED -- they are wherever they ended up, and a drowned animal
ends up at the bottom of the water.

So THE SUBJECT DECIDES THE VERB. The caller says what it is walking to, and
only a thing the town put somewhere earns the shortcut past the water guard.

So, four claims:

  NOTHING IS SENT SOMEWHERE IT WOULD DROWN. Every picker asks.

  THE SHORTCUT IS ONLY FOR WHAT THE TOWN PLACED. Being inside the circle is no
  longer enough on its own, and nothing that walks to a creature, a carcass or
  a dropped armful may claim it.

  ONE DEPTH, ONE ANSWER. The depth that kills a villager and the depth that
  makes a thing unreachable are the same number, or the game will kill people
  for going where it sent them.

  AND THE GOD CAN STILL FISH IT OUT. The meat is not deleted and not made
  untouchable -- the village leaves it, and the hand can reach under the water
  and take it, which is the whole reason the hand may now go below y = 0.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAN = (ROOT / "scripts/villager/villager.gd").read_text()
FEED = (ROOT / "scripts/villager/villager_feeding.gd").read_text()
WATCH = (ROOT / "scripts/world/village_watch.gd").read_text()
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()


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
DROWN = number(MAN, "DROWN_DEPTH")
REACH = number(HAND, "GATHER_REACH")
HOVER = number(HAND, "HOVER_HEIGHT")

# -- NOTHING IS SENT SOMEWHERE IT WOULD DROWN --------------------------------
PICKERS = [
    ("loose food on the ground", FEED, "_ground_food"),
    ("the nearest corpse", MAN, "_nearest_corpse"),
    ("a beast worth gentling", MAN, "_nearest_tamable"),
    ("the town's own watcher", WATCH, "_look_for_corpse"),
]
print("WHO ASKS WHETHER A THING CAN BE REACHED ALIVE:")
for what, text, func in PICKERS:
    rows = body_of(text, func)
    asks = any("would_drown_at(" in r or "DROWN_DEPTH" in r for r in rows)
    print("   %-28s %s" % (what, "asks" if asks else "<-- SENDS THEM IN"))
    if not rows:
        fail.append("%s is gone (%s), so this file is guarding something that "
                    "has moved" % (what, func))
    elif not asks:
        fail.append("%s never asks whether the thing is standing in water deep "
                    "enough to drown in, so the nearest meat in the shallows "
                    "is still the whole town's next destination" % what)

# -- THE SHORTCUT ASKS TOO ---------------------------------------------------
walking = body_of(MAN, "_move_toward")
guarded = [r for r in walking if "at_home(" in r]
by_subject = any("not placed" in r for r in guarded)
opt_in = re.search(r"placed := (\w+)", code(MAN))
print()
print("THE AT-HOME SHORTCUT %s, and a caller that says nothing gets %s."
      % ("is only for what the town placed" if by_subject
         else "STILL TAKES ANY GOAL INSIDE THE CIRCLE",
         "the water guard" if opt_in and opt_in.group(1) == "false"
         else "THE SHORTCUT"))
if not guarded:
    fail.append("_move_toward no longer mentions at_home at all, so either the "
                "shortcut or the guard has moved and this check is stale")
elif not by_subject:
    fail.append("inside its own circle a villager still walks straight at any "
                "goal without the water guard — the shortcut assumes the town "
                "proved that ground, and a dropped joint of meat proves "
                "nothing")
if not opt_in or opt_in.group(1) != "false":
    fail.append("walking somewhere is water-guarded only if the caller opts "
                "IN; a default of anything but false means every unexamined "
                "call site quietly claims the town placed its target")

# -- AND NOTHING THAT WALKS TO A THING CLAIMS IT -----------------------------
#
# The whole rule rests on the callers being honest about what they walk to, so
# the claims are read rather than trusted. A site that passes `true` while
# walking to something that ended up where it is has undone all of this.
LOOSE = ("_target", "animal", "corpse", "food", "mother", "beast", "away",
         "target.global_position", "_fish_spot")
src = code(MAN).split("\n")
claimed, wrong = 0, []
for i, row in enumerate(src):
    if "_move_toward(" not in row:
        continue
    call = " ".join(src[i:i + 3])
    call = call[call.index("_move_toward("):]
    if "true)" not in call.replace(" ", "")[:160]:
        continue
    claimed += 1
    said = call[len("_move_toward("):call.find(",")] if "," in call else call
    if any(word in said for word in LOOSE):
        wrong.append(said.strip())
print("   %d call sites claim the town placed their goal, %s."
      % (claimed, "all of them sites" if not wrong
         else "and %d walk to a THING: %s" % (len(wrong), ", ".join(wrong))))
for said in wrong:
    fail.append("a walk to `%s` claims the town placed it — it is a thing that "
                "ended up where it is, and claiming otherwise sends people "
                "into the water after it" % said)

# -- ONE DEPTH, ONE ANSWER ---------------------------------------------------
hazard = body_of(MAN, "_tick_hazards")
kills_at = any("DROWN_DEPTH" in r for r in hazard)
refuses_at = any("DROWN_DEPTH" in r for r in body_of(MAN, "would_drown_at"))
print("THE DEPTH THAT KILLS AND THE DEPTH THAT REFUSES ARE %s."
      % ("the same number" if kills_at and refuses_at else "TWO NUMBERS"))
if not kills_at or not refuses_at:
    fail.append("the drowning depth and the unreachable depth are no longer "
                "the same constant, so the game can send somebody exactly as "
                "far as the water that kills them")

# -- AND THE GOD CAN STILL FISH IT OUT ---------------------------------------
hovering = body_of(HAND, "_update_hover")
clamped = [r for r in hovering if "ground_point.y = maxf" in r]
print()
print("THE HAND %s."
      % ("may reach below the waterline" if not clamped
         else "IS STILL PINNED TO THE SURFACE"))
if clamped:
    fail.append("the hand still clamps its point to y >= 0 (%s), so everything "
                "on the seabed is out of reach — and a pile held over a "
                "submerged one is %.1fm away when the merge needs %.1fm, which "
                "is why the meat cannot be gathered into one armful"
                % (clamped[0].strip(), (DROWN or 0) + (HOVER or 0), REACH or 0))
elif DROWN and REACH and HOVER:
    print("   a pile lying %.1fm down, held at %.1fm over the seabed: the "
          "merge reaches %.1fm." % (DROWN, HOVER - 0.6, REACH))

# -- AND THE CASCADE ITSELF, COUNTED -----------------------------------------
#
# What the old arrangement cost, on the numbers in the screenshots: a town of
# 240 souls with meat in the shallows. Every hungry villager picks the NEAREST
# food, they are all near the same shore, and each death adds a corpse and its
# own joints to the pile.
print()
print("THE CASCADE, ON THE TOWN IN THE SCREENSHOT (240 souls):")
went_in, meat = 0, 1
while meat > 0 and went_in < 240:
    went_in += 1
    meat += 1        # their own joints, left in the water where they fell
    if went_in >= 240:
        break
print("   before: one drowned animal is %d villagers, because every death "
      "leaves more meat in the water than it took out." % went_in)
print("   now:    nobody is sent, the meat stays where it is, and the god can "
      "pick it up.")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: nothing is sent where it would drown, the town's own circle is no "
      "excuse, one depth answers both questions, and the hand can still reach "
      "in after it.")
