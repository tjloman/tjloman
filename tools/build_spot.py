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
SEARCH = (ROOT / "scripts/world/build_search.gd").read_text()
SCARS = (ROOT / "scripts/world/terrain_scars.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()


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


def const(name, text=VILLAGE):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
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
    spot = body(SEARCH, "_look")
    blocked = spot.find("_village._spot_blocked(pos, own_room)")
    land = spot.find("_village._ground_for_building(")
    if blocked < 0 or land < 0 or blocked > land:
        fail.append("the build search asks the land before asking whether the spot is taken")
    if re.search(r"(slope_at|footprint_dry|line_dry|settle_height)\(", spot):
        fail.append("the build search reads the land itself instead of asking the "
                    "village what it already knows")
    if "snappedf(pos.x, Village.GROUND_CELL)" not in spot \
            or "snappedf(pos.z, Village.GROUND_CELL)" not in spot \
            or spot.find("snappedf(pos.z") > blocked:
        fail.append("build spots are not snapped to the ground grid, so no search "
                    "ever stands where the last one did and nothing is reused")
    ground = body(VILLAGE, "_ground_for_building")
    for need, why in (("world.land_edition()", "a crater or a flood would leave the "
                       "town building on what the land USED to say"),
                      ("_ground_known.clear()", "a changed land is never forgotten"),
                      ("_ground_known.get(key)", "nothing is asked of the memory"),
                      ("_ground_known[key] = settled", "nothing is kept"),
                      ("slope_at(", "steep ground is not refused"),
                      ("footprint_dry(", "a wet footprint is not refused"),
                      ("line_dry(", "a spot across a lake is not refused"),
                      ("settle_height(", "nothing settles on the ground")):
        if need not in ground:
            fail.append("_ground_for_building: %s" % why)
    # EVERY WAY THE LAND CHANGES moves the edition: a scar laid, reshaped or
    # loaded, and a pond raised, spread or loaded (all of which are shown).
    for text, fn in ((SCARS, "add"), (SCARS, "reshape"), (SCARS, "from_save"),
                     (WORLD, "_show_pond")):
        if not re.search(r"(edition|_pond_edition) \+= 1", body(text, fn)):
            fail.append("%s changes the land without moving its edition, so the "
                        "town goes on building on what the land used to say" % fn)
    if "scars.edition + _pond_edition" not in body(WORLD, "land_edition"):
        fail.append("WorldGen.land_edition does not follow the scars and the ponds")
    if "_spot_blocked" in ground or "houses" in ground:
        fail.append("the land memory keeps who has built where — that changes "
                    "without the land changing")
    find = body(VILLAGE, "find_build_spot")
    if "_build_search(" not in find or "_searched(" not in find:
        fail.append("find_build_spot no longer goes through BuildSearch")
    if "_full_to.get(own_room" not in body(VILLAGE, "_build_search"):
        fail.append("find_build_spot starts every sweep at the innermost ring again")
    # A FAILED SEARCH IS REMEMBERED TOO: unconditionally, at the band it stopped
    # on, which is past the reach — so the next one is over at once.
    kept = body(VILLAGE, "_searched").strip().splitlines()
    if len(kept) < 2 or kept[1].strip() != "_full_to[search.own_room] = [search.band, GameState.clock]":
        fail.append("a search that found nothing is not remembered, so every villager "
                    "deciding to build in a full town sweeps every ring again")
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
    # EVERY SEARCH FOR GROUND IN A STAGED FOUNDING IS SLICED: nothing in it asks
    # for a spot to the end, and every search it opens is run a slice a frame.
    # Anything a founding raises later goes through here or fails this.
    if "find_build_spot(" in staged or "_raise_quarry(" in staged \
            or "_build_starting_houses(" in staged:
        fail.append("a staged founding looks for ground in one go")
    opened = staged.count("_build_search(")
    if opened == 0 or opened != staged.count("await _search_slowly("):
        fail.append("a staged founding opens %d searches and slices %d of them"
                    % (opened, staged.count("await _search_slowly(")))
    slow = body(VILLAGE, "_search_slowly")
    if "search.run(FOUNDING_SLICE_USEC)" not in slow or "await get_tree().process_frame" not in slow \
            or 'Ledger.swap(&"Village:founding")' not in slow:
        fail.append("_search_slowly does not run a budgeted slice a frame on the founding clock")
    run = body(SEARCH, "run")
    loop = run[run.find("while not done:"):]
    if loop.find("_look(") < 0 or loop.find("budget_usec > 0 and Time.get_ticks_usec() - began") \
            < loop.find("_look("):
        fail.append("BuildSearch.run does not check its budget after every spot")
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
    for step in ("_ready", "_spawn_founder", "_raise_founding_house", "_open_for_business",
                 "_search_slowly"):
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
    # THE FROZEN FRAME: the last founding house of a town with no room left,
    # which sweeps every ring out to the reach. 3.6s and 15,063 land reads on
    # the meter is what one read costs on that machine.
    reach = max(min(10.0 + 50 * 1.8, MOST_INFLUENCE) * 0.8, 12.0)
    rings = int((reach - NEAREST) / BAND) + 1
    sweep = rings * ANGLES * READS_A_SPOT
    per_read = 3637.6e3 / 15063
    budget = const("FOUNDING_SLICE_USEC")
    spot_us = READS_A_SPOT * per_read
    print("A town of 50 with no room: %d rings x %d spots, up to %d land reads."
          % (rings, ANGLES, sweep))
    print("  at %.0fus a read: %.1fs in one frame before; now a slice of %.0fms "
          "plus at most one spot (%.0fms) a frame, over %d frames,"
          % (per_read, sweep * per_read / 1e6, budget / 1e3, spot_us / 1e3,
             math.ceil(sweep * per_read / (budget + spot_us))))
    print("  and the next search that size in that town is over before it starts.")
    # AND WHAT THE LAND SAID IS KEPT: snapped to the ground grid, a later search
    # stands on the spots an earlier one asked about.
    cell = const("GROUND_CELL")
    turns = int(const("TURNS", SEARCH))
    if "randi() % TURNS" not in body(SEARCH, "_init"):
        fail.append("a sweep is turned by any amount, so no two searches share a spot")
    rng = random.Random(9)
    known = set()
    costs = []
    for n in range(12):
        turn = math.tau * rng.randrange(turns) / (ANGLES * turns)
        fresh = 0
        for ring in range(rings):
            r = NEAREST + ring * BAND
            for step in range(ANGLES):
                a = turn + math.tau * step / ANGLES
                key = (round(math.cos(a) * r / cell), round(math.sin(a) * r / cell))
                if key not in known:
                    known.add(key)
                    fresh += 1
        costs.append(fresh * READS_A_SPOT)
    print("  twelve full sweeps of that town, land reads for spots new to it:")
    print("    %s" % ", ".join(str(c) for c in costs))
    print("  (every sweep after the %d turns have all been used reads nothing)" % turns)
    if costs[-1] > 0 or sum(1 for c in costs if c) > turns:
        fail.append("a later sweep of the same town still reads the land again")
    if (budget + spot_us) / 1e3 > 33.0:
        fail.append("a founding slice can still take more than a 30 Hz frame")
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
