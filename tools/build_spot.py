#!/usr/bin/env python3
"""THE 640ms VILLAGER: ONE DECISION TO BUILD.

The meter's new slowest-call line caught it: "slowest ever: Villager 640.3 ms
(WANDER)", and in another frame one villager call of 82.6ms alongside 10,938
land reads, 10,847 of them the villagers'. One villager, one decision, ten
thousand questions of the land.

Village.find_build_spot sweeps rings out from the totem, 24 bearings a ring,
and asked the LAND about every spot — slope (3 reads), a 5x5 dry footprint
(25), a dry line home (6), the settled height — BEFORE asking whether a house
already stood there. A grown town has every inner ring built over, so it paid
some forty reads a spot to be told each one was taken.

Now the town's own buildings are asked first (distances only), and the sweep
starts at the ring the last building of that size went on. This grows a town
by the real algorithm on flat dry ground and counts the land reads each new
building costs, before and after. Arithmetic, not a frame capture.
"""
import math
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VILLAGE = (ROOT / "scripts/world/village.gd").read_text()


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


def const(name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, VILLAGE, re.M)
    if not m:
        sys.exit("could not read %s" % name)
    return float(m.group(1))


NEAREST = const("BUILD_NEAREST")
BAND = const("BUILD_BAND")
ANGLES = int(const("BUILD_ANGLES"))
APART = const("ROOM_ROUND_A_HOUSE") + 3.0      # a house's own width, near enough
READS_A_SPOT = 3 + 25 + 6 + 4                  # slope, footprint, line home, settle
MOST_INFLUENCE = 80.0


def grow(new, buildings=220, seed=3):
    rng = random.Random(seed)
    placed = []
    full_to = None
    costs = []
    for n in range(buildings):
        reach = max(min(10.0 + n * 1.2 * 1.8, MOST_INFLUENCE) * 0.8, 12.0)
        band = max(NEAREST, full_to) if (new and full_to) else NEAREST
        turn = rng.random() * math.tau
        reads = 0
        found = None
        while band <= reach and found is None:
            best, best_room = None, -1.0
            for step in range(ANGLES):
                a = turn + math.tau * step / ANGLES
                p = (math.cos(a) * band, math.sin(a) * band)
                blocked = any(math.dist(p, q) < APART for q in placed)
                if new and blocked:
                    continue
                reads += READS_A_SPOT
                if blocked:
                    continue
                room = min((math.dist(p, q) for q in placed), default=99.0)
                if room > best_room:
                    best, best_room = p, room
            if best is not None:
                found = best
                full_to = band
            else:
                band += BAND
        if found is None:
            break
        placed.append(found)
        costs.append(reads)
    return costs


def source(fail):
    spot = body(VILLAGE, "find_build_spot")
    blocked = spot.find("_spot_blocked(pos, own_room)")
    land = spot.find("slope_at(")
    if blocked < 0 or land < 0 or blocked > land:
        fail.append("find_build_spot asks the land before asking whether the spot is taken")
    if "_full_to.get(own_room" not in spot or "_full_to[own_room] = [band, GameState.clock]" not in spot:
        fail.append("find_build_spot starts every sweep at the innermost ring again")
    if "_full_to.clear()" not in body(VILLAGE, "on_house_destroyed"):
        fail.append("a house coming down does not reopen the inner rings")
    farm = body(VILLAGE, "_farm_position")
    loop = farm[farm.find("for i in 24:"):]
    if loop.find("_spot_clear(") < 0 or loop.find("_spot_clear(") > loop.find("_grounded("):
        fail.append("_farm_position grounds (and spirals for dry land) before asking if taken")


def founding(fail):
    """A TOWN OVER THE HORIZON IS FOUNDED A FEW AT A TIME.

    The one two-second hang left came when the camera was dragged across the
    land, on the frame "Scouts speak of a village called Thornbury" — thirty-odd
    people and up to twenty-four houses, four hundred nodes, in one frame."""
    ready = body(VILLAGE, "_found")
    if not re.search(r"if is_player_home or founding > 0:[\s\S]*?else:\s*\n\s*_found_in_stages\(\)", ready):
        fail.append("a village found over the horizon is raised whole in one frame again")
    staged = body(VILLAGE, "_found_in_stages")
    if "process_mode = Node.PROCESS_MODE_DISABLED" not in staged \
            or not staged.rstrip().endswith("process_mode = was"):
        fail.append("a half-founded town is left running before it has a charter")
    if staged.count("await get_tree().process_frame") < 2:
        fail.append("the founders or the houses are no longer spread over frames")
    if "_open_for_business()" not in staged:
        fail.append("a staged town is never dealt its charter")
    if "FOUNDERS_A_FRAME" not in staged:
        fail.append("the founders a frame are not bounded")
    # AND IT IS BILLED TO ITSELF. Founding runs in _ready (a deferred add) and
    # in a coroutine resuming each frame — nobody's _process — so without its
    # own clock it was charged to whatever ran last, usually the physics row.
    for step in ("_ready", "_spawn_founder", "_raise_founding_house", "_open_for_business"):
        text = body(VILLAGE, step)
        if 'Ledger.swap(&"Village:founding")' not in text or "Ledger.resume(clock)" not in text:
            fail.append("%s runs without its own clock: the meter bills it to whoever "
                        "ran before" % step)
    per = int(const("FOUNDERS_A_FRAME"))
    print("A town over the horizon: %d founders a frame, then one house a frame." % per)


def main():
    fail = []
    source(fail)
    founding(fail)
    before, after = grow(False), grow(True)
    print("A town grown one building at a time on flat dry ground:")
    print("  %-22s %10s %10s" % ("", "before", "after"))
    for label, lo, hi in (("buildings 1-50", 0, 50), ("buildings 51-150", 50, 150),
                          ("buildings 151+", 150, len(before))):
        b = before[lo:hi] or [0]
        a = after[lo:hi] or [0]
        print("  %-22s %10.0f %10.0f   land reads, worst %d -> %d"
              % (label, sum(b) / len(b), sum(a) / len(a), max(b), max(a)))
    worst_b, worst_a = max(before), max(after)
    if worst_a * 5 > worst_b:
        fail.append("the worst placement still reads the land %d times (was %d)"
                    % (worst_a, worst_b))
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
