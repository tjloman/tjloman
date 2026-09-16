#!/usr/bin/env python3
"""CAN A NEW VILLAGE FEED THE PEOPLE IT WAS FOUNDED WITH, ONCE?

THIS IS NOT ABOUT STARVATION. Hunger climbs as it always has, a famine kills
as it always has, and a town that runs its larder dry buries people -- that is
the game. This is about the first five minutes, where a villager can die
without the mechanic ever having been given a chance to be fair to them.

The founding larder was fourteen units of food. That number was written when a
village was twelve people. A village is fifty now. So the first eleven to get
hungry ate, the granary was bare before the rest were even hungry, and
`_plan_eating` handed those thirty-odd `false` -- no ground food, empty store,
forage only if a bush happened to be near. They went to work instead and died
of it. They never had a chance to run to the store. The store was empty before
they set off.

And they all set off at once, which made it worse: every villager began at
exactly 30 hunger climbing at a quarter a second, so all fifty wanted a meal
at exactly the same second. One stampede, one granary, and whoever lost the
race found nothing.

So: one meal each in the larder, and a spread of starting hungers so they
arrive in a trickle. Both are read off the shipped files here, along with how
long the fields take to overtake them.
"""
import math
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


TOWN = "scripts/world/village.gd"
FARM = "scripts/world/farm.gd"
FOOD = "scripts/world/food_item.gd"
STORE = "scripts/world/food_store.gd"

SOULS = int(const("STARTING_SOULS", TOWN))
MEALS = const("FOUNDING_MEALS", TOWN)
LEAST = const("DAWN_HUNGER_LEAST", TOWN)
MOST = const("DAWN_HUNGER_MOST", TOWN)
NUTRITION = const("NUTRITION", FOOD)
YIELD = const("HARVEST_YIELD", FARM)
GROW = const("BASE_GROWTH_PER_SEC", FARM) + const("TEND_BONUS_PER_SEC", FARM)

HUNGER_PER_SEC = 0.25       # VillagerNeeds.live, a working adult
EATS_AT = 60.0              # Villager._choose
ADULT_SHARE = 0.72          # the rest are children, who are never hungry

meal = math.ceil(EATS_AT / NUTRITION)
adults = int(SOULS * ADULT_SHARE)
larder = SOULS * MEALS
ripen = (0.8 - 0.05) / GROW

fail = []

print("A VILLAGE IS FOUNDED with %d souls, about %d of them adults who eat."
      % (SOULS, adults))
print("The larder holds %.0f units and a meal is %d, so it feeds %d of them"
      % (larder, meal, larder // meal))
print("   once -- %s" % ("everybody, with %d meals spare"
                         % (larder // meal - adults) if larder // meal >= adults
                         else "NOT EVERYBODY"))
if larder // meal < adults:
    fail.append("the founding larder feeds %d of %d adults once. The rest reach "
                "for a granary that is already bare, get nothing out of "
                "`_plan_eating`, and go to work and die of it -- without the "
                "starvation mechanic ever having been fair to them"
                % (larder // meal, adults))

first = (EATS_AT - MOST) / HUNGER_PER_SEC
last = (EATS_AT - LEAST) / HUNGER_PER_SEC
print()
print("THEY GET HUNGRY between %.0fs and %.0fs in -- a %.0f-second trickle,"
      % (first, last, last - first))
print("   not a stampede. (Starting hunger is spread %.0f to %.0f.)" % (LEAST, MOST))
if MOST - LEAST < 10.0:
    fail.append("starting hunger spans only %.0f points, so the whole village "
                "wants a meal within %.0f seconds of each other: one stampede "
                "at one granary, and whoever loses the race finds it empty"
                % (MOST - LEAST, (MOST - LEAST) / HUNGER_PER_SEC))
if MOST >= EATS_AT:
    fail.append("a villager may be founded at %.0f hunger and goes looking at "
                "%.0f: some of them are hungry before the world has finished "
                "loading" % (MOST, EATS_AT))

# AND THE FIELDS HAVE TO OVERTAKE IT. The larder is a bridge, not an income.
per_sec = adults * meal / (EATS_AT / HUNGER_PER_SEC)
farm_per_sec = YIELD / max(ripen, 40.0)      # one tended field, one round trip
print()
print("THE TOWN EATS %.2f units a second. One tended field brings in %.2f,"
      % (per_sec, farm_per_sec))
print("   so the larder bridges %.0f seconds on its own." % (larder / max(per_sec, 0.01)))
if larder / max(per_sec, 0.01) < 120.0:
    fail.append("the founding larder lasts %.0f seconds. The first field takes "
                "%.0f to ripen and somebody has to walk to it: this is not a "
                "bridge, it is a countdown"
                % (larder / max(per_sec, 0.01), ripen))

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: everybody founded can reach the store and eat once, in a trickle.")
