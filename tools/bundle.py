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

  AND NOTHING OF A PERSON IS EVER STOCK. This one is not about carrying at all
  and it is the reason the file is longer than it looks.

  Human meat is not a worse kind of meat. It is a different thing with a
  different life: it never joins a pile, it never goes to a store, it is never
  carried home, and it is eaten where it lies by people who have run out of
  other options or out of decency, down on their hands and knees, the way an
  animal feeds. Every one of those is a separate statement and every one of
  them can be undone by a single innocent-looking line somewhere else.

  It was shipped the other way for one commit — let the flesh into the pile and
  let it TAINT what it went into, on the grounds that nothing was laundered by
  it. Nothing was. It was still wrong: a pile it can be mixed into is a pile
  that gets carried, banked and served at a hearth, and the eating of it stops
  being the separate wretched thing it is.

  And the door that mattered was never the merge. A butcher turned a corpse
  into two abstract units of `meat` and walked them to the granary, where they
  became ordinary stock and were handed out to the whole village. That shipped,
  and no rule about bundles touched it.

  AND A BODY IS NOT A MEAL THAT RUNS OUT. Eating from a corpse takes nothing
  off it: one villager fills their belly and the body is still lying in the
  grass, so the next one who has run out of options comes and does the same,
  and a third joins them. Nobody waits their turn and nobody is served, because
  nothing is being handed out. That is what lets three of them be down over the
  same person at once, and it is the whole of why it reads the way it does.
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
print("A JOINT OF SOMEBODY %s."
      % ("stays out of an honest pile" if blocked else "GOES IN WITH THE MUTTON"))
if not blocked:
    fail.append("human flesh can be merged into a pile of mutton — and a pile "
                "it can be mixed into is a pile that gets carried, banked and "
                "served at a hearth, whether or not the mixing itself is "
                "honest about what went in")

# AND THE BUTCHER LEAVES IT WHERE IT LAY.
#
# This is the door that actually mattered, and no rule about bundles touched
# it: `_begin_haul("meat", 2, "butcher")` turned a corpse into two abstract
# units of stock and walked them to the granary.
VILL = (ROOT / "scripts/villager/villager.gd").read_text()
cutting = []
src = code(VILL)
if "State.BUTCHERING:" in src:
    cutting = src[src.index("State.BUTCHERING:"):].split("\n")[:16]
hauls_it = any("_begin_haul" in r for r in cutting)
drops_it = any("joints_of_a_person" in r for r in cutting)
print("A BUTCHERED BODY %s."
      % ("leaves joints on the grass" if drops_it and not hauls_it
         else "IS WALKED TO THE GRANARY AS STOCK"))
if hauls_it or not drops_it:
    fail.append("butchering a corpse banks abstract meat in the store, where "
                "it becomes ordinary stock and is served to the whole village "
                "— which is the laundering, at a larger scale than any bundle "
                "and through a door no bundle rule watches")

# AND ONE DOOR MAKES IT, so that everything true of human meat is true in one
# place and nothing else is ever flagged this way by accident.
FOODC = code(FOOD)
doors = [r for r in FOODC.split("\n") if re.search(r"is_human_meat\s*=\s*true", r)]
print("IT IS MADE in %d place(s)." % len(doors))
if len(doors) != 1:
    fail.append("human meat is flagged in %d places — there is no one door, so "
                "the next thing that makes some will have its own opinion about "
                "what that means" % len(doors))

# AND THE STORE REFUSES IT AT THE DOOR, both ways in: a joint left on the
# platform, and a bundle held over it to be topped up.
intake = code(STORE)
at_the_door = "is_human_meat" in intake.split("func top_up")[0]
print("THE STOREHOUSE %s."
      % ("will not take it" if at_the_door else "BANKS IT LIKE ANY OTHER MEAT"))
if not at_the_door:
    fail.append("a joint of somebody left on the storehouse platform is banked "
                "as meat_food, which is what a village hands out at a hearth to "
                "anybody who is hungry")

# AND THEY EAT IT ON THE GROUND. No rig has a clip for this, so the body is put
# there the way sleep does it — dropped and pitched forward — and, crucially,
# STOOD BACK UP afterwards. A pose that puts a body on the ground and never
# lifts it has shipped in this codebase before.
LOOK = (ROOT / "scripts/villager/villager_look.gd").read_text()
down = body_of(LOOK, "gone_to_carrion")
up = body_of(LOOK, "stand_up")
kneels = any("_pitch_body(" in r for r in down) and any("sit_down(true)" in r for r in down)
rises = any("_pitch_body(0.0)" in r for r in up) and any("sit_down(false)" in r for r in up)
# The FIRST `State.EATING:` is the state machine's. The later ones are the
# status line and the word over their head, and looking at those instead is how
# a check comes to report on a match arm that does nothing.
stands = any("stand_up(" in r
             for r in code(VILL).split("State.EATING:")[1].split("\n")[:6])
print("A PERSON EATING A PERSON %s%s."
      % ("goes down on all fours" if kneels else "EATS STANDING UP, LIKE DINNER",
         "" if rises and stands else ", AND NEVER GETS UP AGAIN"))
if not kneels:
    fail.append("eating a person looks exactly like eating a meal — the one "
                "meal in the game that is not a meal")
if kneels and not (rises and stands):
    fail.append("nothing stands the eater back up, so a villager who ate on "
                "their knees spends the rest of their life face down in the "
                "grass — this file has shipped that bug once already, for sleep")

# -- AND THE STORE OBEYS THE SAME CAP ----------------------------------------
topping = body_of(STORE, "top_up")
capped = any("MOST_IN_A_BUNDLE" in r for r in topping)
if not any("is_human_meat" in r for r in topping):
    fail.append("a bundle held over a store is topped up without asking what is "
                "in it, so a joint of somebody grows into a stack of stock")
print("DRAWING STOCK OUT of a store %s."
      % ("stops at a handful" if capped else "GROWS THE BUNDLE FOR EVER"))
if not capped:
    fail.append("pulling food out of a store never asks what will fit, so the "
                "cap is a rule that applies only to the piles on the grass")

# -- AND A BODY IS NOT USED UP -----------------------------------------------
FEED = (ROOT / "scripts/villager/villager_feeding.gd").read_text()
eating = body_of(FEED, "meal")
on_a_body = []
for i, row in enumerate(eating):
    if "feeding_on" in row and "if" in row:
        on_a_body = eating[i:i + 5]
        break
uses_it_up = any("queue_free" in r for r in on_a_body)
fills = any("hunger = " in r for r in on_a_body)
print()
print("EATING FROM A BODY %s."
      % ("fills them and leaves it lying there" if fills and not uses_it_up
         else "GETS RID OF THE BODY"))
if not fills:
    fail.append("feeding from a corpse does nothing for the hunger that drove "
                "somebody to it")
if uses_it_up:
    fail.append("the body is consumed by the first person to reach it — so the "
                "second one who has run out of options finds nothing, and the "
                "thing never reads as what it is")

# AND NOBODY WAITS THEIR TURN. There is no claim on a corpse and there must not
# be: the moment one villager can reserve it, it becomes a queue, and a queue is
# the opposite of several people descending on the same body.
finding = body_of(FEED, "_a_body") + body_of(
    (ROOT / "scripts/villager/villager.gd").read_text(), "_nearest_corpse")
claimed = any(w in r for r in finding
              for w in ["set_meta", "has_meta", "taken", "claimed", "busy", "reserved"])
print("SEVERAL MAY DESCEND on the same one: %s." % ("yes" if not claimed else "NO"))
if claimed:
    fail.append("a corpse is claimed or reserved by whoever gets there first, "
                "which turns it into a queue — nothing is being handed out, so "
                "there is nothing to wait for")

# AND THEY LOOK LIKE IT WHILE THEY DO. The pose has to know about the body as
# well as about a joint, or the darkest thing in the game is a man standing up
# straight having his dinner.
seen = body_of((ROOT / "scripts/villager/villager_look.gd").read_text(),
               "eating_a_person")
print("AND IT SHOWS: %s." % ("yes" if any("feeding_on" in r for r in seen) else "NO"))
if not any("feeding_on" in r for r in seen):
    fail.append("the pose asks only about a carried joint, so somebody down "
                "over a corpse eats it standing up like dinner")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: a hunt goes home in one lift, and nobody eats anybody by accident.")
