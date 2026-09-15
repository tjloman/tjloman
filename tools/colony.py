#!/usr/bin/env python3
"""FOUNDING A TOWN: what the wagon costs, what it carries, and what it becomes.

Villages could only ever appear where the world generator put one. A Caravan is
the player's own verb for founding -- pick the wagon up, carry it, put it down
-- and because a town's influence ring is now the ground a god can work on
(MiracleReach), founding one is also the only way to EXTEND YOUR REACH
permanently. Which quietly makes these numbers load-bearing in a second way
nobody would think to check.

The one that matters most: SETTLING MUST NEVER SHRINK YOUR REACH. A wagon on
the road holds a circle of its own, and the town it unpacks into holds a circle
sized by its population. If a wagon carries too few people, the moment it
settles the circle gets SMALLER -- the player watches ground they could cast on
disappear as a reward for founding a town, and nothing anywhere says why.

Every number below is read off the shipped files.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def const(name, relpath):
    text = (ROOT / relpath).read_text()
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9]+\.?[0-9]*)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, relpath))
    return float(m.group(1))


CART = "scripts/world/caravan.gd"
TOWN = "scripts/world/village.gd"

SOULS_SENT = int(const("SOULS_SENT", CART))
SOULS_MOST = int(const("SOULS_MOST", CART))
LUMBER_SENT = int(const("LUMBER_SENT", CART))
STONE_SENT = int(const("STONE_SENT", CART))
FOOD_SENT = int(const("FOOD_SENT", CART))
HEAD_PER_BONUS = int(const("HEAD_PER_BONUS", CART))
SOULS_PER_BONUS = int(const("SOULS_PER_BONUS", CART))
BONUS_MOST = int(const("BONUS_MOST", CART))
HEAD_MOST = int(const("HEAD_MOST", CART))
LUMBER_PER_BONUS = int(const("LUMBER_PER_BONUS", CART))
CART_REACH = const("REACH", CART)
CLEAR_OF_TOWNS = const("CLEAR_OF_TOWNS", CART)

MIN_INFLUENCE = const("MIN_INFLUENCE", TOWN)
MAX_INFLUENCE = const("MAX_INFLUENCE", TOWN)
STARTING_SOULS = int(const("STARTING_SOULS", TOWN))
FOUNDING_HOUSED = const("FOUNDING_HOUSED", TOWN)

# House.SPECS, for what the timber in the cart actually buys.
HUT_LUMBER, HUT_STONE, HUT_BEDS = 5, 3, 3


def ring(pop):
    return max(MIN_INFLUENCE, min(10.0 + pop * 1.8, MAX_INFLUENCE))


def packed(head):
    """Caravan.pack, transcribed: what a town with `head` in its books sends."""
    bonus = min(head // HEAD_PER_BONUS, BONUS_MOST)
    return {
        "souls": min(SOULS_SENT + bonus * SOULS_PER_BONUS, SOULS_MOST),
        "lumber": LUMBER_SENT + bonus * LUMBER_PER_BONUS,
        "stone": STONE_SENT,
        "head": min(bonus, HEAD_MOST),
    }


fail = []

print("WHAT A TOWN SENDS, by the stock in its books:")
print("   %-8s %-7s %-8s %-6s %s" % ("head", "souls", "timber", "drove", "the colony's ring"))
for head in (0, 12, 24, 48, 84, 150):
    cart = packed(head)
    print("   %-8d %-7d %-8d %-6d %.0fm"
          % (head, cart["souls"], cart["lumber"], cart["head"], ring(cart["souls"])))

bare = packed(0)
best = packed(10 ** 6)
print()
print("A WAGON ON THE ROAD holds %.0fm. The poorest colony it can become holds"
      % CART_REACH)
print("   %.0fm, and the best %.0fm." % (ring(bare["souls"]), ring(best["souls"])))

# -- SETTLING MUST NEVER SHRINK YOUR REACH ----------------------------------
if ring(bare["souls"]) < CART_REACH:
    fail.append("the poorest wagon becomes a %.0fm town but was a %.0fm wagon: "
                "founding a colony would SHRINK the ground you can cast on"
                % (ring(bare["souls"]), CART_REACH))

# -- A COLONY IS A HAMLET, NOT A CITY ---------------------------------------
# It has to be visibly smaller than a town the world generator laid down, or
# founding is simply better than conquering and nobody converts anyone again.
heathen = STARTING_SOULS * 2 // 3
print()
print("THE RICHEST COLONY starts with %d souls, against %d for a village the"
      % (best["souls"], heathen))
print("   world laid down and %d at home." % STARTING_SOULS)
if best["souls"] >= heathen:
    fail.append("the richest colony starts with %d souls against a generated "
                "village's %d: founding beats converting and nobody will ever "
                "convert anything again" % (best["souls"], heathen))

# -- NEVER FOUNDED INSIDE SOMEBODY ELSE'S RING ------------------------------
print()
print("A COLONY KEEPS %.0fm CLEAR of any town, against the %.0fm ring of the"
      % (CLEAR_OF_TOWNS, MAX_INFLUENCE))
print("   largest village there can be.")
if CLEAR_OF_TOWNS < MAX_INFLUENCE + 15.0:
    fail.append("a colony may be founded %.0fm from a town whose ring is "
                "%.0fm: the two would overlap on the day it was founded"
                % (CLEAR_OF_TOWNS, MAX_INFLUENCE))

# -- IT ARRIVES ABLE TO BUILD -----------------------------------------------
# The founding houses are free, and they bed FOUNDING_HOUSED of the party. The
# timber in the cart has to roof the rest, or the colony is born homeless and
# starts packing wagons of its own on the day it is founded.
for label, cart in (("the poorest", bare), ("the richest", best)):
    rough = cart["souls"] - int(cart["souls"] * FOUNDING_HOUSED)
    huts = -(-rough // HUT_BEDS)  # ceiling
    need_l, need_s = huts * HUT_LUMBER, huts * HUT_STONE
    print()
    print("%s colony beds %d of %d at founding; %d sleep rough, which is %d hut%s"
          % (label.capitalize(), cart["souls"] - rough, cart["souls"], rough,
             huts, "" if huts == 1 else "s"))
    print("   -- %d timber and %d stone against the %d and %d in the cart."
          % (need_l, need_s, cart["lumber"], cart["stone"]))
    if cart["lumber"] < need_l or cart["stone"] < need_s:
        fail.append("%s colony arrives %d timber and %d stone short of roofing "
                    "the people it brought: it is born homeless and starts "
                    "packing wagons of its own"
                    % (label, max(0, need_l - cart["lumber"]),
                       max(0, need_s - cart["stone"])))

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: founding widens your reach, stays a hamlet, and arrives able to build.")
