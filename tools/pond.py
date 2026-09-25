#!/usr/bin/env python3
"""DOES A DELUGE FILL THE PIT YOU DUG?

"Deluge should be filling this crater I made with a couple dozen fireblasts."
It did not, and for a reason that had nothing to do with the rain: the old
test found the ONE fireball scar nearest the storm, and asked whether there
was a rim at four fifths of that scar's radius. Two dozen fireballs are not
one crater. They are a handful of scars grown into each other (see
TerrainScars.deposit), and the lip of any one of them sits INSIDE the big pit,
on ground lower than the floor the test started from — so it said "drains".

WorldGen.measure_basin now floods outward from the lowest ground the way water
does, always taking the lowest next cell, and the level it must rise to before
it gets out is the spill level. This file:

  1. digs pits the way the game does — 24 fireballs round an aim point, each
     one POURED (merging into a nearby scar and growing it) and stopped at the
     dig floor — into rolling ground at several slopes, and counts how often
     the old test and the new one hold water. The new one must hold far more.
  2. checks the pool it makes is honest: no point in the disc that is below
     the water is outside the pit (the flat disc hanging over the far side of
     a lip is exactly the thing a pond must not do), and the surface sits
     under the rim.
  3. keeps a single clean crater working at least as well as it did.
  4. counts the ground samples one measurement costs, the cost of a cast.
  5. reads the statements: dug ground goes through measure_basin, and the
     town guard still stands in front of EVERY flood — a Deluge does not
     drown a village either (the user's rule: "it shouldn't be flooding
     inside the town").

Numbers are read off the source. This is arithmetic on a model of the ground,
not a playtest.
"""
import math
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MM = (ROOT / "scripts/miracles/miracle_manager.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()
SCARS = (ROOT / "scripts/world/terrain_scars.gd").read_text()
FIRE = (ROOT / "scripts/miracles/fireball.gd").read_text()


def bare(text):
    """Statements only. A comment that says the right thing is not a fix."""
    out = []
    for line in text.splitlines():
        stripped = line.split("#")[0].rstrip()
        if stripped and not stripped.lstrip().startswith("##"):
            out.append(stripped)
    return "\n".join(out)


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def const(text, name, where):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


def default(text, func, arg, where):
    m = re.search(r"func %s\([^)]*%s\s*:?=\s*(-?[0-9.]+)" % (func, arg), text)
    if not m:
        sys.exit("could not read %s's %s off %s" % (func, arg, where))
    return float(m.group(1))


GOUGE_RADIUS = const(FIRE, "GOUGE_RADIUS", "fireball.gd")
GOUGE_DEPTH = const(FIRE, "GOUGE_DEPTH", "fireball.gd")
DIG_FLOOR = const(FIRE, "DIG_FLOOR", "fireball.gd")
MERGE_WITHIN = const(SCARS, "MERGE_WITHIN", "terrain_scars.gd")
BUCKET = const(SCARS, "BUCKET", "terrain_scars.gd")
FREEBOARD = const(MM, "FREEBOARD", "miracle_manager.gd")
DUG_WITHIN = const(MM, "DUG_WITHIN", "miracle_manager.gd")
MOST = default(WORLD, "measure_basin", "most", "world_gen.gd")
STEP = default(WORLD, "measure_basin", "step", "world_gen.gd")
HOLLOW_WITHIN = default(SCARS, "hollow_near", "within", "terrain_scars.gd")

## The old test, as it was before this change: one scar's lip, and the pool at
## nine tenths of that scar.
OLD_LIP_OF = 0.82
## How far under the surface ground must be before it counts as hanging water.
EDGE = 0.05
DELUGE = 3.6
FIREBALLS = 24


class Ground:
    """Rolling seeded ground plus crater scars, poured the way the game pours."""

    def __init__(self, rng, slope):
        a = rng.uniform(0, math.tau)
        self.sx, self.sz = math.cos(a) * slope, math.sin(a) * slope
        self.waves = [(rng.uniform(0.15, 0.6), rng.uniform(9, 30), rng.uniform(0, math.tau),
                       rng.uniform(0, math.tau)) for _ in range(3)]
        self.scars = []

    def seeded(self, x, z):
        h = self.sx * x + self.sz * z
        for amp, wave, px, pz in self.waves:
            h += amp * math.sin(x / wave + px) * math.cos(z / wave + pz)
        return h

    def offset(self, x, z):
        total = 0.0
        for s in self.scars:
            d2 = (x - s["x"]) ** 2 + (z - s["z"]) ** 2
            r = s["radius"]
            if d2 >= r * r:
                continue
            t = math.sqrt(d2) / r
            bowl = math.cos(t * math.pi) * 0.5 + 0.5
            lip = math.sin(min(max((t - 0.55) / 0.45, 0.0), 1.0) * math.pi) * 0.35
            total += s["amount"] * (bowl - lip)
        return total

    def height(self, x, z):
        return self.seeded(x, z) + self.offset(x, z)

    def pour(self, x, z, radius, amount):
        """TerrainScars.deposit: grow a scar near enough, or cut a new one."""
        for s in self.scars:
            gap = math.hypot(s["x"] - x, s["z"] - z)
            if gap > max(s["radius"], radius) * MERGE_WITHIN:
                continue
            had = abs(s["amount"])
            pull = min(max(abs(amount) / max(had + abs(amount), 0.001), 0.0), 0.5)
            s["x"] += (x - s["x"]) * pull
            s["z"] += (z - s["z"]) * pull
            s["amount"] += amount
            s["radius"] = min(max(max(s["radius"], radius) + gap * 0.35, 1.0), BUCKET)
            return
        self.scars.append({"x": x, "z": z, "radius": max(radius, 1.0), "amount": amount})

    def fireball(self, x, z):
        depth = min(GOUGE_DEPTH, max(0.0, DIG_FLOOR + self.offset(x, z)))
        self.pour(x, z, GOUGE_RADIUS, -depth)

    def hollow_near(self, x, z, within):
        best, closest = None, within
        for s in self.scars:
            if s["amount"] >= 0.0:
                continue
            d = math.hypot(s["x"] - x, s["z"] - z)
            if d < closest:
                best, closest = s, d
        return best


def old_flood(g, x, z):
    """The test as it stood: (level, pool) or None."""
    s = g.hollow_near(x, z, HOLLOW_WITHIN)
    if s is None:
        return None
    cx, cz = s["x"], s["z"]
    reach = s["radius"] * OLD_LIP_OF
    floor_y = g.height(cx, cz)
    lowest = math.inf
    for i in range(12):
        a = math.tau * i / 12
        h = g.height(cx + math.cos(a) * reach, cz + math.sin(a) * reach)
        if h <= floor_y + 0.3:
            return None
        lowest = min(lowest, h)
    if lowest - floor_y < 0.8:
        return None
    return True


def measure_basin(g, nx, nz, count):
    """WorldGen.measure_basin, line for line."""
    low, floor_y = (nx, nz), g.height(nx, nz)
    for gz in range(-8, 9):
        for gx in range(-8, 9):
            p = (nx + gx, nz + gz)
            dug = g.offset(*p)
            count[0] += 1
            if dug >= 0.0:
                continue
            h = g.seeded(*p) + dug
            if h < floor_y:
                floor_y, low = h, p
    import heapq
    heights, reached, undug = {}, {(0, 0)}, set()
    heap = [(floor_y, (0, 0))]
    rim = floor_y
    while heap:
        h, cell = heapq.heappop(heap)
        if math.hypot(*cell) * STEP >= MOST or (h < rim and cell in undug):
            heapq.heappush(heap, (h, cell))
            break
        rim = max(rim, h)
        heights[cell] = h
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nxt = (cell[0] + d[0], cell[1] + d[1])
            if nxt in reached:
                continue
            reached.add(nxt)
            ax, az = low[0] + nxt[0] * STEP, low[1] + nxt[1] * STEP
            dug = g.offset(ax, az)
            count[0] += 1
            if dug == 0.0:
                undug.add(nxt)
            heapq.heappush(heap, (g.seeded(ax, az) + dug, nxt))
    if rim - floor_y <= 0.3:
        return None
    wet = [c for c, h in heights.items() if h < rim]
    mx = sum(c[0] for c in wet) / max(len(wet), 1)
    mz = sum(c[1] for c in wet) / max(len(wet), 1)
    widest = max(math.hypot(c[0] - mx, c[1] - mz) for c in wet)
    radius = (widest + 1.0) * STEP
    reach = math.ceil(radius / STEP)
    mid = (round(mx), round(mz))
    for gz in range(-reach, reach + 1):
        for gx in range(-reach, reach + 1):
            cell = (mid[0] + gx, mid[1] + gz)
            if cell in heights:
                continue
            off = math.hypot(cell[0] - mx, cell[1] - mz) * STEP
            if off >= radius:
                continue
            count[0] += 1
            if g.height(low[0] + cell[0] * STEP, low[1] + cell[1] * STEP) < rim:
                radius = off - STEP * 0.5
    return {"x": low[0] + mx * STEP, "z": low[1] + mz * STEP, "floor": floor_y, "rim": rim,
            "radius": max(radius, STEP), "wet": wet, "low": low}


def new_flood(g, x, z, count):
    b = measure_basin(g, x, z, count)
    if b is None or b["rim"] - b["floor"] < 0.8:
        return None
    level = b["floor"] + (b["rim"] - FREEBOARD - b["floor"]) * min(max(DELUGE / 3.6, 0.35), 0.92)
    if level <= b["floor"] + 0.25:
        return None
    b["level"] = level
    return b


def overhang(g, b):
    """Points in the disc that are below the water but not in the pit.

    Sampled on a half-step grid; a point counts as IN the pit when it is
    within a step of a cell the flood filled. The seam at the very edge of the
    pit is a step wide by construction and is not what this is looking for —
    this is looking for the disc lying out over ground past the lip. Nor is
    ground within EDGE of the surface, which is the gap between two samples a
    metre apart and invisible under a disc 8cm thick."""
    wet = {(b["low"][0] + c[0] * STEP, b["low"][1] + c[1] * STEP) for c in b["wet"]}
    r = b["radius"]
    bad = 0
    n = int(r / (STEP * 0.5)) + 1
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            x = b["x"] + i * STEP * 0.5
            z = b["z"] + j * STEP * 0.5
            if (x - b["x"]) ** 2 + (z - b["z"]) ** 2 >= r * r:
                continue
            if g.height(x, z) >= b["level"] - EDGE:
                continue
            near = any(abs(x - wx) <= STEP * 1.5 and abs(z - wz) <= STEP * 1.5 for wx, wz in wet)
            if not near:
                bad += 1
    return bad


def dig_pit(rng, slope):
    g = Ground(rng, slope)
    ax, az = rng.uniform(-50, 50), rng.uniform(-50, 50)
    for _ in range(FIREBALLS):
        a, d = rng.uniform(0, math.tau), rng.uniform(0, 6.0) ** 1.0
        g.fireball(ax + math.cos(a) * d, az + math.sin(a) * d)
    return g, ax, az


def dig_one(rng, slope):
    g = Ground(rng, slope)
    ax, az = rng.uniform(-50, 50), rng.uniform(-50, 50)
    for _ in range(4):                   # one crater, dug to its floor
        g.fireball(ax, az)
    return g, ax, az


def trial(fail, name, digger, slopes, runs, want_new, beat_old):
    print("\n%s (%d per slope)" % (name, runs))
    print("  %-6s %9s %9s %10s %9s %10s" % ("slope", "old fills", "new fills", "worst cost",
                                              "overhang", "depth"))
    for slope in slopes:
        rng = random.Random(int(slope * 1000) + len(name))
        old = new = 0
        worst_cost = 0
        overhung = 0
        depths = []
        for _ in range(runs):
            g, x, z = digger(rng, slope)
            # The storm lands somewhere on the pit, not bang in its middle.
            cx, cz = x + rng.uniform(-3, 3), z + rng.uniform(-3, 3)
            if g.hollow_near(cx, cz, DUG_WITHIN) is None:
                fail.append("%s: a dug pit was not found within DUG_WITHIN of the aim" % name)
                continue
            if old_flood(g, cx, cz):
                old += 1
            count = [0]
            b = new_flood(g, cx, cz, count)
            worst_cost = max(worst_cost, count[0])
            if b is not None:
                new += 1
                depths.append(b["level"] - b["floor"])
                if b["level"] >= b["rim"]:
                    fail.append("%s: pond surface at or over its rim" % name)
                if overhang(g, b):
                    overhung += 1
        depth = "%.2fm" % (sum(depths) / len(depths)) if depths else "-"
        print("  %-6.2f %6d/%-3d %6d/%-3d %10d %9d %10s" % (slope, old, runs, new, runs, worst_cost,
                                                        overhung, depth))
        if slope <= 0.03 and new < runs * want_new:
            fail.append("%s at slope %.2f: the new test fills %d of %d" % (name, slope, new, runs))
        if beat_old and slope <= 0.03 and new <= old:
            fail.append("%s at slope %.2f: no better than the old test (%d vs %d)"
                        % (name, slope, new, old))
        if not beat_old and new < old:
            fail.append("%s at slope %.2f: WORSE than the old test (%d vs %d)"
                        % (name, slope, new, old))
        if overhung:
            fail.append("%s at slope %.2f: %d ponds hang out over ground past the lip"
                        % (name, slope, overhung))
        if worst_cost > 3000:
            fail.append("%s: one measurement took %d ground samples" % (name, worst_cost))


def source(fail):
    flood = body(MM, "_maybe_flood")
    dug = body(MM, "_flood_dug")
    if "_flood_dug(" not in flood or "hollow_near(here, DUG_WITHIN)" not in flood:
        fail.append("_maybe_flood does not send dug ground to _flood_dug")
    if "measure_basin(" not in dug:
        fail.append("_flood_dug does not measure the pit with measure_basin")
    # THE TOWN GUARD, in front of every flood. Checked by position: the guard
    # must come before the flood call in each path.
    for name, text in (("_maybe_flood", flood), ("_flood_dug", dug)):
        guard = text.find("_settled_near(")
        pour = text.find("world.flood(")
        if guard < 0 or pour < 0 or guard > pour:
            fail.append("%s can flood without asking whether a town is there" % name)
    if "_settled_near(middle, pool)" not in dug:
        fail.append("_flood_dug asks about the pit's middle only, not the whole disc")
    if "spread" not in body(MM, "_settled_near"):
        fail.append("_settled_near ignores how far the water spreads")
    # No way round it for any storm.
    rain = body(MM, "_cast_rain")
    if not re.search(r"_maybe_flood\(pos, potency\)", rain):
        fail.append("_cast_rain no longer floods the ordinary way")
    if re.search(r"_cast_rain\([^)]*,[^)]*,", bare(MM)):
        fail.append("a _cast_rain call passes an extra flag — nothing may bypass the town guard")
    basin = body(WORLD, "measure_basin")
    if not re.search(r"offset_at\(p\.x, p\.y\)\s*\n\s*if dug >= 0\.0:\s*\n\s*continue", basin):
        fail.append("measure_basin's floor can be natural ground outside the pit")
    if "undug.has(cell)" not in basin:
        fail.append("measure_basin only stops at the search edge: flat ground costs thousands")
    if not re.search(r"if heights\.has\(cell\):\s*\n\s*continue[\s\S]*?< rim:\s*\n\s*radius = off", basin):
        fail.append("measure_basin's disc is not kept off low ground past the rim")


def main():
    fail = []
    print("From the source: fireball gouge %.2fm x %.1fm, floor %.1fm, merge within %.2f;"
          % (GOUGE_DEPTH, GOUGE_RADIUS, DIG_FLOOR, MERGE_WITHIN))
    print("measure_basin most %.0fm step %.1fm; dug scar within %.0fm; freeboard %.1fm"
          % (MOST, STEP, DUG_WITHIN, FREEBOARD))
    slopes = [0.0, 0.01, 0.02, 0.03, 0.05, 0.08]
    trial(fail, "A pit from %d fireballs" % FIREBALLS, dig_pit, slopes, 60, 0.8, True)
    trial(fail, "One clean crater", dig_one, slopes, 60, 0.8, False)
    source(fail)
    print()
    if fail:
        for f in sorted(set(fail)):
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
