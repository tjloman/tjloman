#!/usr/bin/env python3
"""WHO ASKS THE LAND, AND HOW OFTEN.

A screenshot: "10,717 land reads (peak 32,034)", with villagers costing
0.216ms apiece where they usually cost a twentieth of that. A land read is
`WorldGen.seeded_height_at` — five noise samples and a biome lookup in
GDScript, the most expensive question in the game — and every villager was
asking it on every physics tick for two things that almost never change:

  * AM I STANDING IN DEEP WATER?  `water_level_at` + `height_at`, every tick.
  * AM I BELOW THE GROUND?        `height_at`, every tick, even standing on
                                  the collision, which IS the drawn ground.

Now dry ground is asked twice a second (every tick only while they are in the
water), and nobody the physics has on the floor asks at all. The meter now
prints which classes did the asking, so the next screenshot says where the
rest of the reads come from instead of leaving it to a guess.

Arithmetic on the source and the screenshot's town. Not a frame capture.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAN = (ROOT / "scripts/villager/villager.gd").read_text()
BEAST = (ROOT / "scripts/animals/animal.gd").read_text()
WADING = (ROOT / "scripts/villager/wading.gd").read_text()
LEDGER = (ROOT / "scripts/ledger.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()
METER = (ROOT / "scripts/ui/frame_meter.gd").read_text()
QUALITY = (ROOT / "scripts/quality.gd").read_text()


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


def source(fail):
    for who, text in (("villager", MAN), ("beast", BEAST)):
        stick = body(text, "_stick_to_ground")
        floor = stick.find("if is_on_floor():")
        read = stick.find("height_at(")
        if floor < 0 or read < 0 or floor > read:
            fail.append("a %s on the floor still reads the land to find the floor" % who)
    if "Wading.drown(self" not in body(MAN, "_tick_hazards"):
        fail.append("the hazard tick no longer goes through Wading.drown")
    drown = body(WADING, "drown")
    if not re.search(r"if who\._water_check <= 0\.0 or who\._water_surface > -INF:", drown):
        fail.append("Wading.drown reads the land every tick again (or stops watching "
                    "somebody already in the water)")
    if "Ledger.land_read()" not in body(WORLD, "seeded_height_at"):
        fail.append("land reads are no longer charged to a class")
    if "Ledger.land_rows()" not in METER:
        fail.append("the meter no longer says who read the land")
    if "_asked_page = _asked" not in body(LEDGER, "turn_the_page"):
        fail.append("the per-class reads are never turned over with the page")
    m = re.search(r"func sight_radius\(\) -> int:\s*\n\s*return \[(\d+)", QUALITY)
    far = re.search(r"func camera_far\(\) -> float:\s*\n\s*return \[([0-9.]+)", QUALITY)
    if m and far:
        need = -(-float(far.group(1)) // 48.0)
        if int(m.group(1)) < need:
            fail.append("LOW holds %s rings of land and the camera sees %s m — the "
                        "edge would show" % (m.group(1), far.group(1)))


def model(fail):
    every = const(WADING, "WATER_EVERY")
    hz, souls, steps = 30.0, 436, 1.4
    before = souls * steps * (2 + 1)                 # water + depth, and the floor
    after = souls * steps * (2 / (every * hz))       # water, twice a second
    print("The screenshot's town: %d souls, %.1f physics steps a frame." % (souls, steps))
    print("  villager land reads a frame, hazards and footing:")
    print("    before  %6.0f   (three a villager a tick)" % before)
    print("    after   %6.0f   (dry ground asked every %.1fs; the floor never)"
          % (after, every))
    print("  of the 10,717 in the screenshot, the rest is somebody else's —")
    print("  the meter now prints whose.")
    if after * 10 > before:
        fail.append("the footing and drowning reads are not cut tenfold")


def shared(fail):
    """SHARED LAND READS: "when the villager reads the terrain, the other
    villagers who are near enough don't make their own read — for x seconds."

    The seeded land never changes, so a read is snapped to a half-metre grid
    and kept for everybody for SHARED_FOR seconds. Two claims to hold:

      1. THE DRAWN LAND DOES NOT MOVE. Every chunk corner, on every tier, near
         and far, must already lie on the grid — or the ground would be cut
         from snapped heights and shift under everything standing on it.
      2. IT IS ACTUALLY SHARED. A town of three hundred milling in a sixty-metre
         square asks the same few thousand points over and over."""
    per = const(WORLD, "SHARED_PER_METRE")
    keep = const(WORLD, "SHARED_FOR")
    seeded = body(WORLD, "seeded_height_at")
    if "_shared_heights.get(key)" not in seeded or "_shared_heights[key] = made" not in seeded:
        fail.append("seeded_height_at no longer shares what it reads")
    if "_shared_heights.clear()" not in body(WORLD, "_process"):
        fail.append("the shared reads are kept forever — they must be dropped every "
                    "SHARED_FOR seconds")
    cells = [int(v) for v in re.search(r"func chunk_cells\(\) -> int:\s*\n\s*return \[([^\]]+)\]",
                                       QUALITY).group(1).split(",")]
    far = [int(v) for v in re.search(r"func far_cells\(\) -> int:\s*\n\s*return \[([^\]]+)\]",
                                     QUALITY).group(1).split(",")]
    size = const(WORLD, "CHUNK_SIZE")
    for n in cells + far:
        step = size / n
        if abs(step * per - round(step * per)) > 1e-9:
            fail.append("a chunk cut %d to a side puts corners %.4f m apart, off the "
                        "shared grid — the drawn land would move" % (n, step))
    import random
    rng = random.Random(4)
    asked = hits = 0
    known = {}
    t = 0.0
    people = [(rng.uniform(-30, 30), rng.uniform(-30, 30)) for _ in range(300)]
    for tick in range(30 * 20):
        t += 1.0 / 30.0
        if t > keep:
            t = 0.0
            known.clear()
        for i, (x, z) in enumerate(people):
            x += rng.uniform(-0.1, 0.1)
            z += rng.uniform(-0.1, 0.1)
            people[i] = (x, z)
            if rng.random() < 1.0 / 15.0:          # a water check, twice a second
                key = (round(x * per), round(z * per))
                asked += 1
                if key in known:
                    hits += 1
                else:
                    known[key] = True
    print()
    print("SHARED READS: 300 people milling in 60m for 20s, a %.2fm grid kept %.0fs:"
          % (1.0 / per, keep))
    print("   %d asked, %d answered from the grid (%.0f%%)"
          % (asked, hits, 100.0 * hits / max(asked, 1)))
    if hits * 2 < asked:
        fail.append("under half of a crowded town's land reads are shared")


def main():
    fail = []
    source(fail)
    model(fail)
    shared(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
