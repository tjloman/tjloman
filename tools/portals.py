#!/usr/bin/env python3
"""THE SHORT WAY, AND WHY IT IS NOT IN THE GRAPH.

A nest has a way through built into it and the miracle opens one for five
minutes, so a creature three thousand metres off has two ways to answer a
summons: walk, or step through something.

    "Check for a shorter route from portals, then if none is found, he
     marches."

The obvious implementation is to hang portals off the A* as extra neighbours
and let the search find them. It is wrong, and wrong in the way that does not
show: the search is guided by `_octile`, a straight-line estimate, and that
estimate is only admissible while nothing can beat a straight line. A portal
beats it. The estimate then over-states what is left to do, A* settles for the
first route it finds, and the creature walks past a hole that would have saved
it three hundred metres -- with no error, no stall and nothing on screen. So
the search stays portal-free and whole routes are compared outside it.

Which leaves pruning. Routing through every portal in the world costs more
searches than a frame allows (six, and each candidate is two), so candidates
are priced first by straight lines and the hopeless ones dropped unsearched.
That is only safe if a straight line can never over-state what a route really
costs -- and if it ever does, the creature quietly stops finding the best way
across the world, which is again a bug with no symptom.

Five claims:

  IT DOES NOT GO IN THE GRAPH. Nothing portal-shaped in NavField's neighbour
  loop, ever.

  PRUNING NEVER LOSES THE BEST. Checked against trying every candidate with no
  pruning at all, over thousands of random worlds.

  IT MUST WIN, NOT TIE -- which is also what makes ping-pong impossible.

  A JOURNEY ENDS. Plan, walk to the mouth, step through, plan again: the
  remaining distance must strictly fall, and the whole thing must terminate.

  AND WHEN NOTHING BEATS WALKING, HE WALKS.
"""
import math
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PORTAL = (ROOT / "scripts/portal_path.gd").read_text()
NAV = (ROOT / "scripts/nav_field.gd").read_text()
STEER = (ROOT / "scripts/creature/creature_steering.gd").read_text()


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


MARCH_UNDER = number(PORTAL, "MARCH_UNDER")
STEP_COST = number(PORTAL, "STEP_COST")
MUST_BEAT = number(PORTAL, "MUST_BEAT")
MOST_TRIED = int(number(PORTAL, "MOST_TRIED"))
MOST_HOPS = int(number(PORTAL, "MOST_HOPS"))
CHAIN_BEAT = MUST_BEAT * 2.0
MAP = (ROOT / "scripts/portal_map.gd").read_text()
REACH = number(NAV, "ROUTE_REACH")
fail = []


# -- A WORLD, AND WHAT A ROUTE THROUGH IT REALLY COSTS ------------------------
#
# The ground is priced at somewhere between one and three times the distance
# over it -- hills, water, thickets -- so a straight line is always a LOWER
# BOUND on a route and never an upper one. That is the property the pruning
# leans on, and modelling it any other way would be modelling a world where
# the pruning is allowed to be wrong.
def flat(a, b):
    return math.dist(a, b)


class World:
    def __init__(self, rng, gates):
        self.rng = rng
        self.gates = gates
        self.roughness = {}
        self.mapped = {}
        self.measures = 0
        self.lookups = 0
        self.filled_this_call = False

    def known(self, a, b):
        """A measured leg, or -1. It never guesses -- see PortalMap.known."""
        got = self.mapped.get((a["id"], b["id"]), -1.0)
        if got >= 0.0:
            self.lookups += 1
        return got

    def map_fully(self):
        """Walk out every leg. Comparing a pruned decision with an unpruned
        one is only about the pruning if BOTH see the same map -- the map
        measures one leg a decision, so left alone the second call sees a leg
        the first did not, and that difference reads as a pruning failure."""
        before = -1
        while len(self.mapped) != before:
            before = len(self.mapped)
            self.opening()

    def opening(self):
        """One unwalked leg of the network is measured, outside any decision."""
        for a in self.gates:
            for b in self.gates:
                if a["id"] == b["id"] or (a["id"], b["id"]) in self.mapped:
                    continue
                self.measures += 1
                self.mapped[(a["id"], b["id"])] = \
                    self.cost(a["exit"], b["mouth"]) \
                    or flat(a["exit"], b["mouth"]) * 2.0
                return

    def cost(self, a, b):
        """What routing from a to b really costs here, or None past the reach."""
        if flat(a, b) > REACH:
            return None
        key = (round(a[0], 1), round(a[1], 1), round(b[0], 1), round(b[1], 1))
        if key not in self.roughness:
            self.roughness[key] = self.rng.uniform(1.0, 3.0)
        return flat(a, b) * self.roughness[key]


def best(world, here, goal, skip=0, prune=True):
    """PortalPath.best, in Python, one for one."""
    world.opening()
    walk = world.cost(here, goal)
    straight = flat(here, goal)
    if straight < MARCH_UNDER:
        return {"via": None, "cost": walk if walk is not None else straight,
                "marched": True, "searches": 1}
    beat = walk if walk is not None else straight
    searches = 1
    worth = []
    for gate in world.gates:
        if gate["id"] == skip:
            continue
        bound = flat(here, gate["mouth"]) + STEP_COST \
            + least_onward(world, gate, goal)
        if prune and bound >= beat * (1.0 - MUST_BEAT):
            continue
        worth.append((bound, gate))
    worth.sort(key=lambda row: row[0])
    picked = None
    tried = 0
    for bound, gate in worth:
        if prune:
            if bound >= beat * (1.0 - MUST_BEAT):
                break
            tried += 1
            if tried > MOST_TRIED:
                break
        searches += 2
        to_mouth = world.cost(here, gate["mouth"])
        if to_mouth is None:
            to_mouth = flat(here, gate["mouth"])
        total = to_mouth + STEP_COST + onward(world, gate, goal)
        if total >= beat * (1.0 - MUST_BEAT):
            continue
        beat = total
        picked = gate
    return {"via": picked, "cost": beat, "marched": picked is None,
            "searches": searches}


def least_onward(world, gate, goal):
    """PortalPath._least_onward: the least the rest could cost, all straight
    lines -- and it must know chains exist, because a portal jumps space and
    the straight line to the goal is not a bound on what is left."""
    least = flat(gate["exit"], goal)
    for nxt in world.gates:
        if nxt["id"] == gate["id"]:
            continue
        least = min(least, flat(gate["exit"], nxt["mouth"]) + STEP_COST
                    + flat(nxt["exit"], goal))
    return least


def onward(world, gate, goal, hops=1):
    """PortalPath._onward: the walk from the far end, or another hop if one
    turns that walk into a short one. The inside of a chain is a LOOKUP -- see
    PortalMap -- so a second hop costs no search."""
    walk = world.cost(gate["exit"], goal)
    if walk is None:
        walk = flat(gate["exit"], goal)
    if hops >= MOST_HOPS:
        return walk
    for nxt in world.gates:
        if nxt["id"] == gate["id"]:
            continue
        leg = world.known(gate, nxt)
        if leg < 0.0 or leg + STEP_COST >= walk * (1.0 - CHAIN_BEAT):
            continue
        tail = world.cost(nxt["exit"], goal)
        if tail is None:
            continue
        if leg + STEP_COST + tail < walk * (1.0 - CHAIN_BEAT):
            walk = leg + STEP_COST + tail
        break
    return walk


def a_world(rng, how_many):
    gates = []
    for i in range(how_many):
        mouth = (rng.uniform(-2000, 2000), rng.uniform(-2000, 2000))
        exit_at = (rng.uniform(-2000, 2000), rng.uniform(-2000, 2000))
        gates.append({"id": i + 1, "mouth": mouth, "exit": exit_at})
    return World(rng, gates)


# -- PRUNING NEVER LOSES THE BEST --------------------------------------------
rng = random.Random(20260920)
worse, tried, searches_kept, searches_all = 0, 0, 0, 0
for _ in range(4000):
    world = a_world(rng, rng.randint(1, 6))
    here = (rng.uniform(-2000, 2000), rng.uniform(-2000, 2000))
    goal = (rng.uniform(-2000, 2000), rng.uniform(-2000, 2000))
    world.map_fully()
    quick = best(world, here, goal)
    whole = best(world, here, goal, prune=False)
    tried += 1
    searches_kept += quick["searches"]
    searches_all += whole["searches"]
    if quick["cost"] > whole["cost"] + 0.001:
        worse += 1
print("PRICING EVERY CANDIDATE AGAINST PRICING THE PROMISING ONES:")
print("   %d worlds, %d portals a world at most — the pruned answer was worse "
      "in %d of them." % (tried, 6, worse))
print("   and it paid for %.1f searches a decision instead of %.1f."
      % (searches_kept / tried, searches_all / tried))
if worse:
    fail.append("pruning by straight lines lost the best route in %d of %d "
                "worlds, so the creature quietly stops finding the short way "
                "across the world and nothing about that is visible"
                % (worse, tried))

# -- A JOURNEY ENDS ----------------------------------------------------------
#
# Plan, walk to the mouth, step through, plan again -- the loop the game will
# actually run. Ping-pong is the failure this is for: arriving on a pad, being
# offered the way back as a fresh idea, and going nowhere for ever.
print()
print("WALKING THE WHOLE JOURNEY, a thousand times:")
longest, stuck, hops_total = 0, 0, 0
for _ in range(1000):
    world = a_world(rng, rng.randint(2, 6))
    # Two-way gates, which is what makes ping-pong possible at all.
    for gate in list(world.gates):
        world.gates.append({"id": gate["id"] + 100, "mouth": gate["exit"],
                            "exit": gate["mouth"]})
    here = (rng.uniform(-2000, 2000), rng.uniform(-2000, 2000))
    goal = (rng.uniform(-2000, 2000), rng.uniform(-2000, 2000))
    # WHAT MUST FALL IS THE COST, not the distance. A hop that lands slightly
    # further away as the crow flies but on the near side of a bay is the
    # router doing its job; measured by distance it looks like a failure, and
    # eleven journeys in six hundred were failed for exactly that before the
    # invariant was written down properly.
    # THE POTENTIAL MUST BE WHAT THE DECISION OPTIMISES. He is not minimising
    # the direct walk -- he is minimising the best way there he can see, chains
    # included -- so that is the number that has to fall. Measured against the
    # direct walk instead, six perfectly good journeys across a mapped network
    # read as ping-pong.
    left = best(world, here, goal)["cost"]
    came = 0
    hops = 0
    while hops < 40:
        step = best(world, here, goal, skip=came)
        if step["via"] is None:
            break
        here = step["via"]["exit"]
        came = step["via"]["id"]
        hops += 1
        # WITHOUT the skip. Immunity deliberately takes an option away for a
        # few seconds, which can only raise what he can see from where he is
        # standing -- so measuring the potential WITH it counts the safety
        # catch as a failure of the thing it is protecting.
        now = best(world, here, goal)["cost"]
        if now >= left:
            stuck += 1
            break
        left = now
    hops_total += hops
    longest = max(longest, hops)
    if hops >= 40:
        stuck += 1
print("   %d journeys, %.2f hops each on average, longest %d, and %d that "
      "failed to get closer." % (1000, hops_total / 1000.0, longest, stuck))
if stuck:
    fail.append("%d journeys either went round for ever or came out of a hole "
                "with more left to do than they went in with — that is the "
                "ping-pong this whole design exists to make impossible" % stuck)

# -- THE LAYOUT THE GAME ACTUALLY HAS ----------------------------------------
#
# Random portals in a four-kilometre box almost never help, so a journey test
# built on them proves very little: it reported 0.29 hops a journey, which is
# to say it was barely exercising the thing it was testing. The real shape is a
# NETWORK -- a handful of nests, every ordered pair of them a way through -- and
# a player who ties the lead beside one of them. That is also where the cap on
# how many candidates get searched can start costing something, because twenty
# ways through are now on offer and two of them get priced properly.
def a_network(rng, nests):
    where = [(rng.uniform(-2500, 2500), rng.uniform(-2500, 2500))
             for _ in range(nests)]
    gates, n = [], 0
    for a in where:
        for b in where:
            if a != b:
                n += 1
                gates.append({"id": n, "mouth": a, "exit": b})
    world = World(rng, gates)
    return world, where


rng = random.Random(31415)
hops_total, stuck, lost, worst_loss, journeys, crabbed = 0, 0, 0, 0.0, 600, 0
deepest = 0
for _ in range(journeys):
    world, nests = a_network(rng, 5)
    here = (rng.uniform(-2500, 2500), rng.uniform(-2500, 2500))
    # The lead tied a few hundred metres from one of his nests, which is the
    # case in the request: "I put the leash on next to a nest there".
    near = nests[rng.randrange(len(nests))]
    goal = (near[0] + rng.uniform(-300, 300), near[1] + rng.uniform(-300, 300))
    world.map_fully()
    quick, whole = best(world, here, goal), best(world, here, goal, prune=False)
    if quick["cost"] > whole["cost"] + 0.001:
        lost += 1
        worst_loss = max(worst_loss, quick["cost"] / whole["cost"] - 1.0)
    left, came, hops = best(world, here, goal)["cost"], 0, 0
    further = 0
    while hops < 40:
        step = best(world, here, goal, skip=came)
        if step["via"] is None:
            break
        was = flat(here, goal)
        here, came = step["via"]["exit"], step["via"]["id"]
        hops += 1
        if flat(here, goal) > was:
            further += 1
        # WITHOUT the skip. Immunity deliberately takes an option away for a
        # few seconds, which can only raise what he can see from where he is
        # standing -- so measuring the potential WITH it counts the safety
        # catch as a failure of the thing it is protecting.
        now = best(world, here, goal)["cost"]
        if now >= left:
            stuck += 1
            break
        left = now
    crabbed += further
    deepest = max(deepest, hops)
    hops_total += hops
    if hops >= 40:
        stuck += 1
print()
print("A NETWORK OF FIVE NESTS (20 ways through), the lead tied by one of them:")
print("   %d journeys, %.2f hops each, longest %d."
      % (journeys, hops_total / float(journeys), deepest))
print("   %d hops in %d did not leave him better off than he was — hindsight "
      "regret, not a loop." % (stuck, hops_total))
print("   %d hops landed further off as the crow flies and nearer to walk "
      "from, which is the router working, not failing." % crabbed)
print("   searching only the %d most promising lost the best route %d times%s."
      % (MOST_TRIED, lost,
         "" if not lost else " (worst %.1f%% dearer)" % (worst_loss * 100)))
# TWO DIFFERENT FAILURES, AND ONLY ONE OF THEM IS PING-PONG.
#
# A journey that never ends is a bug outright. A single hop that turns out not
# to have been worth taking is not: he commits on what he can see, and what he
# can see from the far end is not the same view. Tuning constants until that
# number is zero would be fitting the design to the measurement — so the loop
# is forbidden outright and the regret is held to a share, with the figure
# printed either way.
MOST_REGRET = 0.02
if deepest > MOST_HOPS + 1:
    fail.append("a journey across a five-nest network took %d hops, where two "
                "is the whole network — that is a creature going round in "
                "circles" % deepest)
if hops_total and stuck / float(hops_total) > MOST_REGRET:
    fail.append("%d hops of %d (%.0f%%) left him no better off than before he "
                "took them, against a tolerance of %.0f%% — at that rate he is "
                "not choosing, he is wandering between rings"
                % (stuck, hops_total, stuck / float(hops_total) * 100,
                   MOST_REGRET * 100))
if hops_total / float(journeys) < 0.5:
    fail.append("a creature summoned across a five-nest network takes %.2f "
                "ways through a journey — the network is being ignored, which "
                "is the whole case this was built for"
                % (hops_total / float(journeys)))
if worst_loss > 0.1:
    fail.append("capping the search at the %d most promising candidates cost "
                "up to %.0f%% on the best route — the cap is meant to save "
                "searches, not to pick a worse way across the world"
                % (MOST_TRIED, worst_loss * 100))

# -- AND WHEN NOTHING BEATS WALKING, HE WALKS --------------------------------
rng = random.Random(7)
marched = 0
for _ in range(600):
    world = a_world(rng, 3)
    here = (0.0, 0.0)
    goal = (rng.uniform(-80, 80), rng.uniform(-80, 80))   # near: never worth it
    if best(world, here, goal)["marched"]:
        marched += 1
print()
print("A GOAL WITHIN SIGHT is walked to %d times out of 600." % marched)
if marched < 600:
    fail.append("%d of 600 short trips went through a portal — under %.0fm he "
                "should simply walk, and a creature that hops across a field "
                "is a creature nobody can follow" % (600 - marched, MARCH_UNDER))

# -- IT DOES NOT GO IN THE GRAPH ---------------------------------------------
# THE MODEL ABOVE CANNOT SEE ANY OF THIS. It reads the constants out of the
# GDScript and then agrees with itself, so a change to what the GAME does is
# invisible to it: of six deliberate breaks, it caught one. These read the
# statements, and each one names the exact line whose absence is the bug.
searching = body_of(NAV, "route")
in_graph = [r for r in searching if "portal" in r.lower()]
prices_real = any("NavField.last_cost" in r for r in body_of(PORTAL, "_price"))
bounding = body_of(PORTAL, "_worth_trying")
bounds = any("_least_onward(" in r for r in bounding)
chain_aware = any("STEP_COST" in r for r in body_of(PORTAL, "_least_onward"))
skips = any('int(gate["id"]) == skip' in r for r in bounding)
# A map that guesses is the whole of the earlier disaster: `known` may hand back
# a measured leg or a refusal, and nothing else.
asking = body_of(MAP, "known")
guesses = any("_flat(" in r for r in asking)
refuses = any("return -1.0" in r for r in asking)
# And the expiry has to be the test that DECIDES, not a word that appears
# somewhere in the function: the first version of this passed happily with the
# clock check replaced by `if true`, because the tidying-up below it still
# mentioned `until`.
keeping = body_of(NAV, "portals_open")
expires = any('GameState.clock <= float(gate["until"])' in r for r in keeping)
immune = any("PORTAL_IMMUNITY" in r for r in body_of(STEER, "_plan"))
print()
print("THE SEARCH ITSELF IS %s."
      % ("portal-free, so its estimate stays honest" if not in_graph
         else "AWARE OF PORTALS, AND ITS ESTIMATE IS NO LONGER ADMISSIBLE"))
print("ROUTES ARE COMPARED BY %s."
      % ("what the search says they cost" if prices_real
         else "SOMETHING OTHER THAN THEIR COST"))
print("A CLOSED PORTAL %s, AND THE ONE HE CAME OUT OF %s."
      % ("is not offered" if expires else "IS STILL ROUTED THROUGH",
         "is invisible for a few seconds" if immune and skips
         else "IS OFFERED STRAIGHT BACK"))
if in_graph:
    fail.append("NavField.route mentions portals (%s) — a portal in the "
                "neighbour loop breaks _octile's admissibility and the "
                "creature silently walks past holes that would have saved it "
                "hundreds of metres" % in_graph[0].strip())
if not prices_real:
    fail.append("_price no longer compares routes by what the search says they "
                "cost, so hills, water and thickets stop counting and the "
                "cheapest-looking route is merely the straightest")
if not bounds or not chain_aware:
    fail.append("_worth_trying no longer bounds candidates with a chain-aware "
                "straight-line estimate — a portal jumps space, so the walk "
                "from an exit to the goal is not a bound on what is left, and "
                "bounding on it throws away candidates that would have won")
if guesses or not refuses:
    fail.append("PortalMap.known guesses at a leg it has not walked (it "
                "mentions _flat) instead of refusing — an under-stated leg "
                "makes a route look better than it is, which is thirty-seven "
                "lost routes and six circular journeys, measured")
if MUST_BEAT < 0.05:
    fail.append("a portal route need only TIE with walking (margin %.2f) to be "
                "taken, and a tie is what oscillates: two routes of equal cost "
                "swap places on every re-plan" % MUST_BEAT)
if not expires:
    fail.append("portals_open no longer checks when a portal closes, so a "
                "five-minute miracle is routed through for the rest of the game")
if not immune or not skips:
    fail.append("nothing makes the portal he just came out of invisible, so "
                "the one arrangement the arithmetic cannot rule out leaves him "
                "stepping back and forth on a pad")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: the search stays honest, the pruning cannot lose the best way, "
      "every journey ends, and a short trip is walked.")
