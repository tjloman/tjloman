#!/usr/bin/env python3
"""WHY BUILDINGS WERE SPAWNING BELOW GROUND, AND WHAT PUTS THEM BACK.

A house was seated at the height the terrain noise gives. The terrain that is
DRAWN is flat triangles between grid corners, so the two disagree — a little in
gentle country on a fine grid, and a great deal everywhere else:

  * the far ring is cut at six or eight cells to a forty-eight metre chunk, so
    six- and eight-metre cells;
  * `seeded_height_at` picks its amplitude from the biome AT THAT POINT, so the
    analytic surface has step changes in it that one flat triangle spans;
  * and Elsmere's founding houses are raised in Main._ready, before a single
    chunk has streamed, so there was no drawn ground to seat them on at all and
    nothing ever went back to check.

The fix has two halves and this checks both. Buildings are seated against the
chunk's own height grid (WorldGen.settle_height -> Chunk.highest_over), and
they are RE-seated whenever the ground under them is cut (reseat_over).

Two claims are worth arithmetic rather than assertion:

  1. `highest_over` is EXACT. It enumerates the four footprint corners and
     every grid vertex inside the footprint, and claims that is the maximum of
     the drawn surface over the whole square. That is true because the surface
     is flat within each triangle — but "true because" is not "true", so it is
     brute-forced against a dense sweep.
  2. The difference is worth having. On a field with a biome-style step in it,
     seating on the analytic height buries a building by metres.

Every number is read off the source.
"""
import math
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()
QUALITY = (ROOT / "scripts/quality.gd").read_text()
METER = (ROOT / "scripts/ui/frame_meter.gd").read_text()

SEATERS = {
    "house": "scripts/world/house.gd",
    "workshop": "scripts/world/workshop.gd",
    "food_store": "scripts/world/food_store.gd",
    "edubba": "scripts/world/edubba.gd",
}


def bare(text):
    """The statements only. A comment that says the right thing is not a fix."""
    out = []
    for line in text.splitlines():
        stripped = line.split("#")[0].rstrip()
        if stripped:
            out.append(stripped)
    return "\n".join(out)


def const(text, name, where):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


def body(text, name):
    """One function's statements, up to the next top-level `func`."""
    m = re.search(r"^func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


WORLD_BARE = bare(WORLD)
CHUNK_BARE = bare(CHUNK)

CHUNK_SIZE = const(WORLD, "CHUNK_SIZE", "world_gen.gd")


def tiers(text, name):
    m = re.search(r"^func %s\(\).*?\n\treturn \[([0-9,\s]+)\]" % name, text, re.M | re.S)
    if not m:
        sys.exit("could not read Quality.%s" % name)
    return [int(v) for v in m.group(1).split(",")]


FAR_CELLS = tiers(QUALITY, "far_cells")
CHUNK_CELLS = tiers(QUALITY, "chunk_cells")


# ---------------------------------------------------------------- the surface

def drawn(grid, cells, wx, wz):
    """Chunk.drawn_height, mirrored: the two triangles `_cut_mesh` emits."""
    step = CHUNK_SIZE / cells
    wide = cells + 1
    u = wx / step
    v = wz / step
    cx = min(max(int(u // 1), 0), cells - 1)
    cz = min(max(int(v // 1), 0), cells - 1)
    fu = min(max(u - cx, 0.0), 1.0)
    fv = min(max(v - cz, 0.0), 1.0)
    h0 = grid[cz * wide + cx]
    h1 = grid[cz * wide + cx + 1]
    h2 = grid[(cz + 1) * wide + cx + 1]
    h3 = grid[(cz + 1) * wide + cx]
    if fu >= fv:
        return h0 + (h1 - h0) * fu + (h2 - h1) * fv
    return h0 + (h2 - h3) * fu + (h3 - h0) * fv


def edge_high(grid, cells, a, b, fixed, along_x, step):
    """Chunk._edge_high, mirrored."""
    def at(t):
        return drawn(grid, cells, t if along_x else fixed,
                     fixed if along_x else t)
    best = max(at(a), at(b))
    for base in (0.0, fixed):
        first = int(math.ceil((a - base) / step))
        last = int(math.floor((b - base) / step))
        for k in range(first, last + 1):
            best = max(best, at(base + k * step))
    return best


def highest_over(grid, cells, wx, wz, half):
    """Chunk.highest_over, mirrored: edges (with their bends) plus vertices."""
    step = CHUNK_SIZE / cells
    wide = cells + 1
    best = edge_high(grid, cells, wx - half, wx + half, wz - half, True, step)
    best = max(best, edge_high(grid, cells, wx - half, wx + half, wz + half, True, step))
    best = max(best, edge_high(grid, cells, wz - half, wz + half, wx - half, False, step))
    best = max(best, edge_high(grid, cells, wz - half, wz + half, wx + half, False, step))
    lo_x = int(math.ceil((wx - half) / step))
    hi_x = int(math.floor((wx + half) / step))
    lo_z = int(math.ceil((wz - half) / step))
    hi_z = int(math.floor((wz + half) / step))
    for gz in range(max(lo_z, 0), min(hi_z, wide - 1) + 1):
        for gx in range(max(lo_x, 0), min(hi_x, wide - 1) + 1):
            best = max(best, grid[gz * wide + gx])
    return best


def brute(grid, cells, wx, wz, half, steps=101):
    best = -1e30
    for i in range(steps):
        for j in range(steps):
            x = wx - half + 2.0 * half * i / (steps - 1)
            z = wz - half + 2.0 * half * j / (steps - 1)
            best = max(best, drawn(grid, cells, x, z))
    return best


def land(cells, rng, step_cliff=0.0):
    """A height grid with rolling country and, optionally, a biome-style step."""
    wide = cells + 1
    span = CHUNK_SIZE / cells
    grid = []
    for z in range(wide):
        for x in range(wide):
            wx = x * span
            wz = z * span
            h = 2.2 + 3.0 * math.sin(wx / 9.0) + 2.0 * math.cos(wz / 7.0)
            h += rng.uniform(-0.4, 0.4)
            if step_cliff and wx > CHUNK_SIZE * 0.5:
                h += step_cliff
            grid.append(h)
    return grid


# ---------------------------------------------------------------- the checks

def check_exactness(fail):
    rng = random.Random(20260924)
    worst = 0.0
    for cells in sorted(set(FAR_CELLS + CHUNK_CELLS)):
        grid = land(cells, rng)
        for _ in range(60):
            half = rng.uniform(0.8, 3.4)
            wx = rng.uniform(half, CHUNK_SIZE - half)
            wz = rng.uniform(half, CHUNK_SIZE - half)
            mine = highest_over(grid, cells, wx, wz, half)
            ref = brute(grid, cells, wx, wz, half)
            worst = max(worst, ref - mine)
    print("HOW MUCH OF A FOOTPRINT `highest_over` CAN MISS")
    print("  worst a dense sweep beat the enumeration by: %.6f m" % worst)
    if worst > 1e-6:
        fail.append("highest_over is not exact: missed %.4f m" % worst)
    return worst


def check_worth_it(fail):
    """What seating on the noise costs where the drawn surface is above it."""
    rng = random.Random(7)
    print()
    print("HOW FAR A BUILDING IS BURIED IF IT IS SEATED ON THE NOISE")
    worst_plain = 0.0
    worst_cliff = 0.0
    for cells, cliff, label in (
            (int(CHUNK_CELLS[2]), 0.0, "fine grid, rolling country"),
            (int(FAR_CELLS[0]), 0.0, "far ring, rolling country"),
            (int(CHUNK_CELLS[2]), 6.0, "fine grid, across a biome step")):
        grid = land(cells, rng, cliff)
        worst = 0.0
        for _ in range(3000):
            half = 3.18            # a longhouse on its foundation
            wx = rng.uniform(half, CHUNK_SIZE - half)
            wz = rng.uniform(half, CHUNK_SIZE - half)
            # Seated the old way: the highest of five ANALYTIC samples, which
            # here is the height grid read at the corners of the footprint.
            seated = max(drawn(grid, cells, wx + dx, wz + dz)
                         for dx, dz in ((0, 0), (half, half), (-half, half),
                                        (half, -half), (-half, -half)))
            worst = max(worst, highest_over(grid, cells, wx, wz, half) - seated)
        print("  %-34s worst %.2f m under" % (label, worst))
        if cliff:
            worst_cliff = worst
        else:
            worst_plain = max(worst_plain, worst)
    if worst_cliff < 0.5:
        fail.append("a step in the land no longer buries a five-sample seating "
                    "— the model has stopped modelling the bug")
    return worst_plain, worst_cliff


def check_source(fail):
    print()
    print("WHAT THE SOURCE ACTUALLY DOES")

    settle = body(WORLD, "settle_height")
    if "chunk_at(" not in settle or "highest_over(" not in settle:
        fail.append("WorldGen.settle_height no longer asks the chunk for the "
                    "ground it actually drew")
    else:
        print("  settle_height asks the chunk it stands on ....... yes")

    dh = body(WORLD, "drawn_height_at")
    if "chunk_at(" not in dh or "is_nan(" not in dh:
        fail.append("WorldGen.drawn_height_at no longer prefers the drawn mesh")
    else:
        print("  drawn_height_at prefers the drawn mesh .......... yes")

    # The fallback is walked hundreds of thousands of times while a village is
    # founded, and it is a guess at a mesh that is not there. One read.
    if dh.count("height_at(") - dh.count("drawn_height_at(") != 1:
        fail.append("WorldGen.drawn_height_at's no-chunk fallback costs more "
                    "than one read of the seed — it is a guess, not an answer, "
                    "and reseat_over is what makes it right")
    else:
        print("  the no-chunk fallback costs one read ............ yes")

    reseat = body(WORLD, "reseat_over")
    if "seat_half" not in reseat or "settle_height(" not in reseat:
        fail.append("WorldGen.reseat_over no longer re-settles by footprint")
    else:
        print("  reseat_over re-settles by footprint ............. yes")

    built = body(CHUNK, "_build_terrain")
    if "world.reseat_over(cell)" not in built:
        fail.append("cutting a chunk no longer re-seats what stands on it — "
                    "which is the half of the fix that reaches Elsmere")
    else:
        print("  cutting ground re-seats what stands on it ....... yes")

    spawn = body(WORLD, "_spawn_chunk")
    filed = spawn.find("_chunks[cell] = chunk")
    raised = spawn.find("add_child(chunk)")
    if filed < 0 or raised < 0 or filed > raised:
        fail.append("a chunk is filed after it is raised, so its own first cut "
                    "cannot find it and re-seats nothing")
    else:
        print("  a chunk is filed before it is raised ............ yes")

    # The interpolation has to split the quad the way the mesh does, or the
    # height read back is off by the whole diagonal on half of every cell.
    if "for idx in [0, 1, 2, 0, 2, 3]" not in CHUNK_BARE:
        fail.append("_cut_mesh no longer splits on the 0-2 diagonal, so "
                    "Chunk.drawn_height is interpolating the wrong triangles")
    else:
        print("  drawn_height splits the quad as the mesh does ... yes")

    if re.search(r"\bworld\.height_at\(", CHUNK_BARE):
        fail.append("something in chunk.gd still places scenery on the "
                    "analytic surface instead of the drawn one")
    else:
        print("  nothing in a chunk stands on the noise .......... yes")

    if "WorldGen.SEATED" not in bare(METER) or "seat_half" not in bare(METER):
        fail.append("the frame meter no longer measures seating the way the "
                    "seater seats, so its readout can agree with a bug")
    else:
        print("  the meter measures what the seater measured ..... yes")

    for name, path in SEATERS.items():
        text = bare((ROOT / path).read_text())
        joins = "add_to_group(WorldGen.SEATED)" in text
        halfs = 'set_meta("seat_half"' in text
        if not joins or not halfs:
            fail.append("%s %s" % (name, "never joins the seated group"
                                   if not joins else "joins it with no footprint"))
        else:
            print("  %-14s seats itself, with a footprint ... yes" % name)


def main():
    fail = []
    check_exactness(fail)
    check_worth_it(fail)
    check_source(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
