#!/usr/bin/env python3
"""THE CREATURE'S ROUTE SEARCH, AND HOW OFTEN IT HAS TO SEARCH.

The meter's slowest-call line caught the creature at 11.8ms (GUARD) and 13.6ms
(COMMUNE), and put it at the top of the bill in a town. Both are walking
states, and walking a long way means NavField.route: an A* over 6m cells, up
to 380 expanded.

1. THE FRONTIER. It was a sorted Array of [priority, cell] pairs — pop_front()
   shifted every entry behind the front, and every push allocated a pair and
   inserted it mid-array, shifting the rest. Now a binary heap in two packed
   arrays. This runs both on random ground and checks they find routes of the
   SAME cost (ties may break differently; no route is ever worse), and counts
   the element moves each makes.

2. THE PATROL. On GUARD the creature walked to random points on a ring round
   the village, usually further apart than CreatureSteering.DIRECT, so every
   post was a search. It now hops round the ring inside DIRECT: no search.

3. THE AUDIENCE. COMMUNE counted who was watching — a walk of every villager —
   on every tick. Now twice a second.

Arithmetic on a model of the search. Not a frame capture.
"""
import heapq
import math
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAV = (ROOT / "scripts/nav_field.gd").read_text()
CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()
STEER = (ROOT / "scripts/creature/creature_steering.gd").read_text()
LEISURE = (ROOT / "scripts/creature/creature_leisure.gd").read_text()


def bare(text):
    out = []
    for line in text.splitlines():
        stripped = line.split("#")[0].rstrip()
        if stripped:
            out.append(stripped)
    return "\n".join(out)


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def const(text, name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s" % name)
    return float(m.group(1))


BUDGET = int(const(NAV, "ROUTE_BUDGET"))
DIRECT = const(STEER, "DIRECT")
NEIGHBOURS = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]


def octile(a, b):
    dx, dz = abs(a[0] - b[0]), abs(a[1] - b[1])
    return (max(dx, dz) + (math.sqrt(2) - 1) * min(dx, dz)) * 6.0


def search(ground, start, goal, heap):
    """A* as NavField.route runs it; returns (cost or None, element moves)."""
    best = {start: 0.0}
    moves = 0
    if heap:
        open_ = [(octile(start, goal), start)]
    else:
        open_ = [[octile(start, goal), start]]
    expanded = 0
    while open_ and expanded < BUDGET:
        if heap:
            _, here = heapq.heappop(open_)
            moves += int(math.log2(len(open_) + 1)) + 1
        else:
            here = open_.pop(0)[1]
            moves += len(open_)                  # every entry behind the front
        if here == goal:
            return best[here], moves
        expanded += 1
        for dx, dz in NEIGHBOURS:
            there = (here[0] + dx, here[1] + dz)
            toll = ground(there)
            if toll < 0:
                continue
            cost = best[here] + 6.0 * (math.sqrt(2) if dx and dz else 1.0) + toll
            if there in best and cost >= best[there]:
                continue
            best[there] = cost
            pri = cost + octile(there, goal)
            if heap:
                heapq.heappush(open_, (pri, there))
                moves += 2
            else:
                lo, hi = 0, len(open_)
                while lo < hi:
                    mid = (lo + hi) // 2
                    if open_[mid][0] < pri:
                        lo = mid + 1
                    else:
                        hi = mid
                open_.insert(lo, [pri, there])
                moves += len(open_) - lo + 1     # the shift, and a new pair
    return None, moves


def source(fail):
    route = body(NAV, "route")
    if "open.pop_front()" in route or "_enqueue(" in route:
        fail.append("the route search keeps a sorted list again")
    if "_heap_pop(open_cost, open_cell)" not in route or "_heap_push(open_cost, open_cell" not in route:
        fail.append("the route search does not use the heap")
    guard = body(CREATURE, "_pick_guard_waypoint")
    if "CreatureSteering.DIRECT - 1.0" not in guard or "randf() * TAU" in guard:
        fail.append("the guard patrol crosses the ring, planning a route at every post")
    commune = body(LEISURE, "commune")
    if "CreatureEyes.audience(" in commune or "_audience_of(who, delta)" not in commune:
        fail.append("communing counts every villager every tick again")


def model(fail):
    rng = random.Random(9)
    worse = found = 0
    was = now = 0
    for trial in range(300):
        seed = rng.random()
        walls = set()
        wrng = random.Random(seed)
        for _ in range(140):
            walls.add((wrng.randint(-25, 25), wrng.randint(-25, 25)))
        hills = {}

        def ground(cell):
            if cell in walls:
                return -1.0
            if cell not in hills:
                hills[cell] = random.Random(hash((seed, cell))).random() * 3.0
            return hills[cell]
        start = (0, 0)
        goal = (rng.randint(-20, 20), rng.randint(-20, 20))
        walls.discard(start)
        walls.discard(goal)
        a, ma = search(ground, start, goal, heap=False)
        b, mb = search(ground, start, goal, heap=True)
        was += ma
        now += mb
        if a is not None and b is not None:
            found += 1
            if b > a + 1e-6:
                worse += 1
    print("300 searches on random ground, budget %d cells:" % BUDGET)
    print("   found by both: %d; worse route with the heap: %d" % (found, worse))
    print("   element moves: %d with the sorted list, %d with the heap (%.0fx)"
          % (was, now, was / max(now, 1)))
    if worse:
        fail.append("the heap found a costlier route %d times" % worse)
    if now * 3 > was:
        fail.append("the heap saves less than two thirds of the work")
    radius = 40.0
    hop = 2.0 * radius * math.sin(math.asin(min((DIRECT - 1.0) / (2.0 * radius), 1.0)))
    print()
    print("GUARD: a %.0fm patrol ring, hop %.1fm against the %.0fm direct range."
          % (radius, hop, DIRECT))
    if hop >= DIRECT:
        fail.append("a guard hop is %.1fm, past the direct range: it plans a route" % hop)


def main():
    fail = []
    source(fail)
    model(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
