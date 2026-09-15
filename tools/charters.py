#!/usr/bin/env python3
"""A HUNDRED THOUSAND WAYS TO RUN A VILLAGE, and the hundred and twenty-eight
that work.

THE PROBLEM THIS SOLVES IS NOT A BALANCE PROBLEM. A village is founded with
fifty souls, none of whom has a job, so on the first frame all fifty ask the
board what the town needs -- and the board's answer is the same for all fifty
because none of them has acted yet. They sort it out eventually, badly, by
taking jobs and dropping them, and a town of two hundred does it two hundred
times over while the player watches.

The decision engine is not for this. It is there so a village RESPONDS -- to a
wolf, to a fire, to the creature, to a hand reaching down. Deriving the ordinary
running of a town from first principles, fifty times, every time anybody finishes
a task, is work nobody asked it to do.

So the ordinary running of a town is decided HERE, once, offline, and shipped.
A village rolls one of these at founding and deals it out; the live logic keeps
running from there and handles everything that actually happens.

HOW THEY ARE SCORED. Each candidate is a share of the town's adults per job. It
is run through a coarse but honest model of the village economy for twenty
minutes of game time -- every rate below is read off the shipped scripts, and
the ones that are estimates say so -- and judged on two things:

  SUCCESS: is the town fed, housed and growing at the end of it?
  STABILITY: did it get there WITHOUT a famine, and without the larder
             swinging wildly? A mix that starves for two minutes and then
             recovers is not a mix to found a village on.

Run with --write to regenerate data/village_charters.json. Run bare to verify
the shipped file still matches what this model would produce.
"""
import argparse
import json
import pathlib
import random
import re
import statistics
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "data/village_charters.json"

CANDIDATES = 100_000
KEEP = 128
SEED = 20260714


def const(name, relpath, default=None):
    text = (ROOT / relpath).read_text()
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9]+\.?[0-9]*)" % name, text, re.M)
    if not m:
        if default is not None:
            return default
        sys.exit("could not read %s off %s" % (name, relpath))
    return float(m.group(1))


# ---------------------------------------------------------------- the game's
VILLAGER = "scripts/villager/villager.gd"
FARM = "scripts/world/farm.gd"
HOUSE = "scripts/world/house.gd"
JOBS = "scripts/world/village_jobs.gd"
VILLAGE = "scripts/world/village.gd"
ROCK = "scripts/world/rock_deposit.gd"
FOOD = "scripts/world/food_item.gd"

NUTRITION = const("NUTRITION", FOOD)
WALK_SPEED = const("WALK_SPEED", VILLAGER)
HARVEST_YIELD = const("HARVEST_YIELD", FARM)
GROW_BASE = const("BASE_GROWTH_PER_SEC", FARM)
GROW_TEND = const("TEND_BONUS_PER_SEC", FARM)
BUILD_RATE = const("BUILD_RATE", HOUSE)
STONE_PER_HARVEST = const("STONE_PER_HARVEST", ROCK)
SOULS_PER_GATHERER = const("SOULS_PER_GATHERER", JOBS)
STARTING_SOULS = int(const("STARTING_SOULS", VILLAGE))
FOUNDING_HOUSED = const("FOUNDING_HOUSED", VILLAGE)
FARMS_MOST = int(const("FARMS_MOST", VILLAGE))

# Hunger climbs at 0.25/s for a working adult (VillagerNeeds.tick) and a meal
# is taken at 60, costing ceil(60/NUTRITION) units. Children are never hungry
# at all, which is a rule and not a balance number -- see the same file.
HUNGER_PER_SEC = 0.25
EATS_AT = 60.0
MEAL_UNITS = -(-int(EATS_AT) // int(NUTRITION))
# How fast a fed, housed town grows, per soul per second.
#
# DELIBERATELY FASTER THAN THE GAME'S, and this is the number that makes the
# whole search work. Village paces births through `conception_chance` and a
# cooldown; modelled as a slow exponential, every viable mix simply rode the
# same curve and scored identically -- a hundred thousand candidates and a
# hundred and twenty-eight-way tie, which is not a ranking, it is a coin toss
# with extra steps.
#
# Set high, the town is ALWAYS pressed against its roofs, so the population is
# whatever the materials economy can house and the ranking becomes a real
# question: too many gatherers and nobody farms, too many farmers and there are
# no roofs to grow into. That is the trade a founding charter is actually
# making, and it is invisible until births stop being the limit.
BIRTH_PER_SEC = 0.01

# -------------------------------------------------------- honest estimates --
# Everything above is read off the game. Everything here is a guess about
# WALKING, which the scripts do not state as a number because it depends on
# where things are. They are all round-trip times in seconds at WALK_SPEED, and
# they are the weakest part of this model; they are written together so that
# anybody retuning them can see them all at once.
TRIP = {
    "farm": 40.0,      # out to the field, tend to harvest, haul the grain back
    "hunt": 75.0,      # find a beast, run it down, carry the meat home
    "chop": 70.0,      # out past the ring to a tree, fell it, haul the timber
    "quarry": 70.0,
    "tame": 60.0,
}
# A tended field ripens in (0.8 - 0.05) / (base + tend) seconds; a farmer is at
# it for that, so a farm shift is the longer of the two.
RIPEN = (0.8 - 0.05) / (GROW_BASE + GROW_TEND)
# A middling tree, off the Fibonacci ladder in wild_tree.gd.
LUMBER_PER_TREE = 12.0
# A middling beast, off Animal.SPECIES -- sheep 2, pig 3, ox 4, hen 1.
MEAT_PER_BEAST = 2.5

# The jobs a FOUNDING village can actually offer. Workshops do not exist yet,
# so "work" is not on this list; nor is anything that needs a school, a nest or
# a war. This is the board on day one, and it is short on purpose.
FOUNDING_JOBS = ["farm", "hunt", "chop", "quarry", "build", "build_farm",
                 "tame", "rest"]


def room(job, souls, farms=1.0):
    """VillageJobs.room_for, transcribed. Two hands to a field, one gatherer per
    twelve souls, and a fixed ceiling on the rest."""
    if job == "farm":
        return max(int(farms) * 2, 1)
    if job in ("chop", "quarry"):
        return max(int(souls / SOULS_PER_GATHERER), 1)
    caps = {"build": 3, "build_farm": 2, "hunt": 4, "tame": 2}
    return caps.get(job, 10 ** 6)   # rest is uncapped


def run(mix, souls, seconds=900.0, step=4.0):
    """A coarse village, twenty minutes of it. Returns (fed, housed, stability)."""
    adults = int(souls * 0.72)          # the rest are children, who do not work
    food = 14.0 + 8.0                   # FoodStore's founding plant + the gift
    lumber, stone = 6.0, 3.0
    beds = souls * FOUNDING_HOUSED
    farms = 1.0
    larder = []
    lived = []
    starved = 0.0
    t = 0.0
    hands = {}
    turn = 0
    while t < seconds:
        # THE HANDS ARE RE-DEALT AS THE TOWN GROWS, which is the difference
        # between a model that ranks and one that does not. Dealt once at
        # founding, every mix that filled the room caps at thirty-six adults
        # produced exactly the same town forever after -- the caps became a
        # ceiling every good candidate reached, and the top hundred and
        # twenty-eight tied to the decimal. A village re-tallies; so does this.
        #
        # And the caps themselves move: `room_for` gives chop and quarry one
        # hand per twelve souls, so a town that grows earns more woodcutters.
        # That is what makes the SHARES matter rather than just the order --
        # thirty per cent on a field with twenty places is ten people wasted.
        if turn % 10 == 0:
            hands = {j: min(int(round(mix.get(j, 0.0) * adults)),
                            room(j, souls, farms)) for j in FOUNDING_JOBS}
        turn += 1
        # EATING. Every adult takes MEAL_UNITS every (EATS_AT / rate) seconds.
        eat = adults * MEAL_UNITS * step / (EATS_AT / HUNGER_PER_SEC)
        food -= eat
        if food < 0.0:
            starved += -food * step
            food = 0.0
        # FARMING. A field is worked by up to two, and a second pair does not
        # ripen it twice as fast -- the field's clock is the limit.
        working_fields = min(farms, hands["farm"] / 2.0)
        food += working_fields * HARVEST_YIELD * step / max(RIPEN, TRIP["farm"])
        # HUNTING.
        food += hands["hunt"] * MEAT_PER_BEAST * step / TRIP["hunt"]
        # And a tamer's beasts, which feed the town slowly and forever.
        food += hands["tame"] * 0.5 * step / TRIP["tame"]
        # TIMBER AND STONE.
        lumber += hands["chop"] * LUMBER_PER_TREE * step / TRIP["chop"]
        stone += hands["quarry"] * STONE_PER_HARVEST * step / TRIP["quarry"]
        # BUILDING. A hut is 5 timber, 3 stone, 45 effort, and sleeps 3.
        if hands["build"] > 0 and lumber >= 5.0 and stone >= 3.0:
            made = hands["build"] * BUILD_RATE * step / 45.0
            can_pay = min(lumber / 5.0, stone / 3.0)
            made = min(made, can_pay)
            lumber -= made * 5.0
            stone -= made * 3.0
            beds += made * 3.0
        # NEW FIELDS, which is what makes a town able to grow at all.
        if hands["build_farm"] > 0 and lumber >= 4.0 and farms < FARMS_MOST:
            broken = hands["build_farm"] * step / 90.0
            broken = min(broken, lumber / 4.0, FARMS_MOST - farms)
            lumber -= broken * 4.0
            farms += broken
        # BIRTHS, bounded by BEDS and by the larder, exactly as Village bounds
        # them (`at_capacity`). Beds are what bind: this game's fields are
        # enormously productive -- one farmer on one tended field is 0.85 food
        # a second against thirty-six adults eating 0.3 -- so food is not the
        # constraint at founding and a model that scored on it ranked nothing.
        # What separates one town from another is how fast it gets roofs up.
        if food > adults * 0.5 and souls < beds + 8:
            souls += souls * BIRTH_PER_SEC * step
            adults = int(souls * 0.72)
        larder.append(food)
        lived.append(souls)
        t += step
    fed = food / max(adults, 1)
    housed = beds / max(souls, 1)
    # STABILITY is the swing of the larder over the second half, once the town
    # has settled -- a mix that oscillates is a mix where people keep changing
    # their minds, which is the thing this whole exercise exists to stop.
    tail = larder[len(larder) // 2:]
    swing = statistics.pstdev(tail) / max(statistics.mean(tail), 1.0)
    # AND THE TOWN IS SCORED OVER ITS WHOLE LIFE, not at the end of it. The
    # mean population rewards getting big EARLY and staying big, which is what
    # a founding charter is actually for; a final count rewards dawdling
    # equally with racing.
    return fed, housed, swing, starved, statistics.mean(lived)


def score(mix, souls):
    fed, housed, swing, starved, lived = run(mix, souls)
    if starved > 0.0:
        return -1e9 + -starved        # a famine is disqualifying, and ranked
    if fed < 1.0:
        return -1e6 + fed             # not starving, but living hand to mouth
    # HOW BIG THE TOWN WAS, ON AVERAGE, ALL RUN -- and a penalty for a larder
    # that swings. Nothing else: food and housing have already had their say in
    # what the population could reach.
    return lived - swing * 25.0


def roll(rng):
    """One candidate: a share per job, summing to one."""
    weights = {j: rng.random() ** 2 for j in FOUNDING_JOBS}
    weights["rest"] = rng.random() * 2.0   # leisure is a real answer
    total = sum(weights.values())
    return {j: w / total for j, w in weights.items()}


def name_for(mix):
    """What this town is, in a word: whatever it puts most of itself into."""
    working = {j: v for j, v in mix.items() if j != "rest"}
    chief = max(working, key=working.get)
    return {"farm": "tillage", "hunt": "the chase", "chop": "timber",
            "quarry": "stone", "build": "raising", "build_farm": "breaking",
            "tame": "husbandry"}.get(chief, "tillage")


def best(verbose=True):
    rng = random.Random(SEED)
    scored = []
    for _ in range(CANDIDATES):
        mix = roll(rng)
        scored.append((score(mix, STARTING_SOULS), mix))
    scored.sort(key=lambda row: row[0], reverse=True)
    top = scored[:KEEP]
    if verbose:
        print("%d candidates, top %d kept. Best %.1f, worst kept %.1f, "
              "median of all %.1f."
              % (CANDIDATES, KEEP, top[0][0], top[-1][0],
                 scored[len(scored) // 2][0]))
    # IS THIS A RANKING AT ALL?
    #
    # Twice while this was being written every one of the top hundred and
    # twenty-eight scored EXACTLY the same, because the model had a ceiling in
    # it and every decent mix reached it. A hundred-thousand-candidate search
    # that returns a hundred-and-twenty-eight-way tie has not chosen anything;
    # it has handed back the first hundred and twenty-eight rows that cleared a
    # bar, in the order the random number generator happened to make them, and
    # it looks exactly like a search that worked.
    if abs(top[0][0] - top[-1][0]) < 0.01:
        sys.exit("BROKEN: all %d kept charters score %.2f. The model has a "
                 "ceiling every good mix reaches, so this is not a ranking -- "
                 "it is the order the generator made them in." % (KEEP, top[0][0]))
    return top


def as_file(top):
    rows = []
    for points, mix in top:
        rows.append({
            "name": name_for(mix),
            "score": round(points, 2),
            "mix": {j: round(v, 4) for j, v in sorted(mix.items())},
        })
    return {
        "note": "GENERATED BY tools/charters.py -- do not edit by hand. "
                "Each row is a share of a founding village's adults per job. "
                "See VillageCharter, which deals one of these out at founding "
                "so that fifty people do not each derive the same answer from "
                "first principles on the same frame.",
        "candidates": CANDIDATES,
        "kept": KEEP,
        "seed": SEED,
        "jobs": FOUNDING_JOBS,
        "charters": rows,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true",
                    help="regenerate data/village_charters.json")
    args = ap.parse_args()

    top = best()
    made = as_file(top)

    print()
    print("THE FIVE BEST TOWNS, as shares of the adults:")
    head = [j for j in FOUNDING_JOBS]
    print("   %-10s %6s  %s" % ("name", "score",
                                "  ".join("%-6s" % j[:6] for j in head)))
    for row in made["charters"][:5]:
        print("   %-10s %6.1f  %s" % (row["name"], row["score"],
              "  ".join("%-6.2f" % row["mix"][j] for j in head)))

    kinds = {}
    for row in made["charters"]:
        kinds[row["name"]] = kinds.get(row["name"], 0) + 1
    print()
    print("WHAT KIND OF TOWNS SURVIVED the cut:")
    for kind, n in sorted(kinds.items(), key=lambda kv: -kv[1]):
        print("   %-12s %3d" % (kind, n))

    if args.write:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(made, indent=1) + "\n")
        print()
        print("wrote %s (%d charters)" % (OUT.relative_to(ROOT), len(made["charters"])))
        return

    # WILL THE EXPORT ACTUALLY CARRY THE FILE?
    #
    # Every preset exports "all_resources", and a .json is not a resource in
    # Godot 4 -- nothing imports it, so nothing includes it unless the preset's
    # include_filter says so. It works perfectly in the editor and is simply
    # absent on the device, which is a failure this project has already had
    # once and did not enjoy. VillageCharter falls back to one baked-in row, so
    # the symptom is not a crash: it is every village in the exported game
    # being founded identically and nobody ever knowing why.
    presets = ROOT / "export_presets.cfg"
    if presets.exists():
        text = presets.read_text()
        want = text.count("export_filter=")
        have = text.count('include_filter="*.json"')
        print()
        print("EXPORT: %d of %d presets carry *.json." % (have, want))
        if have < want:
            sys.exit("BROKEN: %d export preset(s) do not include *.json. The "
                     "charters are in the editor and absent on the device, and "
                     "the fallback makes every village identical in silence."
                     % (want - have))

    if not OUT.exists():
        sys.exit("BROKEN: %s does not exist -- run with --write"
                 % OUT.relative_to(ROOT))
    shipped = json.loads(OUT.read_text())
    print()
    if shipped.get("charters") != made["charters"]:
        sys.exit("BROKEN: %s is not what this model produces any more. Some "
                 "constant it reads off the game has moved -- run with --write "
                 "and look at what changed." % OUT.relative_to(ROOT))
    print("OK: the shipped charters are what this model produces.")


main()
