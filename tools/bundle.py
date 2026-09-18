#!/usr/bin/env python3
"""WHAT ONE HAND CAN CARRY HOME.

A player culls a herd. The grass is covered in joints of three different
animals, in piles of whatever each beast dropped. They pick one up, hold it
over the next, and nothing happens -- because the piles were only allowed to
merge when the meat came off the same SPECIES, and because a pile that was
already full refused the merge outright instead of taking what would fit. So a
hunt was three trips, or four, or six, and every one of them was carrying
rather than deciding.

    "I had several piles -- mutton x12, bison chuck x24 -- but I couldn't
     combine them to take all of it home at once, which is important to me."

What this file guards is the four rules that came out of that, and the one that
was there before them and must survive intact.

  ANY MEAT JOINS ANY MEAT, and the pile is called mystery meat once there is
  more than one animal in it.

  AS MUCH AS WILL FIT. A full pile takes nothing, but a pile with room takes
  what the room allows and leaves the rest -- a flat refusal is what stopped
  two half-piles ever becoming one.

  A SHEAF IS NOT A JOINT. Grain and meat stay apart.

  AND NOTHING IS LAUNDERED. Human flesh used to be kept out of an honest pile
  by refusing the merge. It TAINTS it now, which is more permissive and exactly
  as honest: every villager who would have refused the joint refuses the whole
  stack, and the player is told the moment it happens. If that ever becomes a
  quiet merge instead, a god can feed a village its own people by accident.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FOOD = (ROOT / "scripts/world/food_item.gd").read_text()
STORE = (ROOT / "scripts/world/food_store.gd").read_text()


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


def refuses(body, needle, within=3):
    """True when a row mentioning `needle` leads to a `return false` just below.

    GDScript writes a guard over two lines, and looking for both halves on ONE
    row is how a check like this comes to pass against the very code it was
    written to catch. Asked for the exact `absorb` this file exists because of,
    every one-row version of these tests said the code was already fixed.
    """
    for i, row in enumerate(body):
        if needle in row:
            for later in body[i:i + within]:
                if later.strip() == "return false":
                    return True
    return False


def number(text, name):
    found = re.search(r"^const %s := ([-\d.]+)" % name, text, re.M)
    return float(found.group(1)) if found else None


fail = []
taking = body_of(FOOD, "absorb")
most = number(FOOD, "MOST_IN_A_BUNDLE")

# -- ONE HAND, ONE TRIP ------------------------------------------------------
#
# The hunt that started this: three animals' worth of meat on the grass, in the
# piles the game actually left it in.
PILES = [12, 24]
## And a proper slaughter, for scale: twenty head at four joints apiece. This
## one is REPORTED and not required — a cap is a cap, and eighty joints in one
## fist would not be a bundle, it would be a granary on a string.
HERD = [4] * 20
print("THE PILES IN THE REPORT: %s -- %d joints on the grass."
      % (" + ".join(str(p) for p in PILES), sum(PILES)))


def trips(piles, cap, partial, mixes):
    """How many times the player walks home, under a given set of rules."""
    left = sorted(piles, reverse=True)
    walks = 0
    while left:
        # Pick one up, then draw in whatever it is allowed to take.
        hand = left.pop(0)
        again = True
        while again:
            again = False
            for i, pile in enumerate(left):
                if not mixes:
                    continue        # a different animal: never joins
                room = cap - hand
                if room <= 0:
                    break
                if not partial and pile > room:
                    continue        # refused outright
                take = min(pile, room)
                hand += take
                if take >= pile:
                    left.pop(i)
                else:
                    left[i] = pile - take
                again = True
                break
        walks += 1
    return walks


was = trips(PILES, 24, False, False)
now = trips(PILES, int(most or 0), True, True)
print("   the old rules took it home in %d trips; these take %d." % (was, now))
print("   a twenty-head cull (%d joints) takes %d."
      % (sum(HERD), trips(HERD, int(most or 0), True, True)))
if most is None:
    fail.append("FoodItem.MOST_IN_A_BUNDLE is gone, so there is no cap at all")
elif now > 1:
    fail.append("the hunt in the report still takes %d trips to carry home, "
                "which is the whole of what was asked for" % now)

# -- ANY MEAT JOINS ANY MEAT -------------------------------------------------
by_name = refuses(taking, "meat_name")
renames = any("MYSTERY" in r for r in taking)
print()
print("TWO ANIMALS IN ONE PILE: %s."
      % ("mystery meat" if renames and not by_name else "STILL TWO PILES"))
if by_name:
    fail.append("meat is still refused for coming off a different animal, so a "
                "hunt is still one trip per species")
if not renames:
    fail.append("a pile of two different animals keeps the name of whichever "
                "joint was picked up first, which is a lie about what is in it")

# -- AS MUCH AS WILL FIT -----------------------------------------------------
whole_or_nothing = refuses(taking, "count + other.count")
partial = any("mini(other.count" in r for r in taking) \
    and any("other.count -=" in r for r in taking)
print("A PILE WITH ROOM %s."
      % ("takes what fits" if partial and not whole_or_nothing
         else "TAKES ALL OF IT OR NONE OF IT"))
if whole_or_nothing or not partial:
    fail.append("a merge is all-or-nothing, so a pile with room for eight "
                "refuses a pile of nine and two half-piles stay two piles")

# -- A SHEAF IS NOT A JOINT --------------------------------------------------
apart = refuses(taking, "food_type")
print("GRAIN AND MEAT %s." % ("stay apart" if apart else "GO IN TOGETHER"))
if not apart:
    fail.append("grain and meat merge into one bundle — they are wanted for "
                "different things and a granary full of mutton is a different "
                "game")

# -- AND NOTHING IS LAUNDERED ------------------------------------------------
#
# The rule that was already there, in its new form. It is checked hardest,
# because the new form is the PERMISSIVE one: the old one could only fail
# closed, and this one can fail open.
blocked = refuses(taking, "is_human_meat")
taints = any(re.search(r"is_human_meat\s*=\s*true", r) for r in taking)
tells = any("hint(" in r or "announce(" in r for r in taking)
print("A JOINT OF SOMEBODY %s."
      % ("taints the whole pile, out loud" if taints and tells
         else "IS LAUNDERED INTO IT"))
if not taints:
    if blocked:
        fail.append("human flesh is kept out by refusing the merge — which is "
                    "honest, but it also refuses every innocent merge, and "
                    "this file exists because that refusal was the problem")
    else:
        fail.append("human flesh goes quietly into a pile of mutton: the whole "
                    "stack is then eaten by people who would have refused it, "
                    "and the god who did it never finds out")
if taints and not tells:
    fail.append("a pile is tainted without the player being told, so the first "
                "they know of it is a village that will not eat")

# -- AND THE STORE OBEYS THE SAME CAP ----------------------------------------
topping = body_of(STORE, "top_up")
capped = any("MOST_IN_A_BUNDLE" in r for r in topping)
print("DRAWING STOCK OUT of a store %s."
      % ("stops at a handful" if capped else "GROWS THE BUNDLE FOR EVER"))
if not capped:
    fail.append("pulling food out of a store never asks what will fit, so the "
                "cap is a rule that applies only to the piles on the grass")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: a hunt goes home in one lift, and nobody eats anybody by accident.")
