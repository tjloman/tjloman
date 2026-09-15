#!/usr/bin/env python3
"""THE FISHING DOCK: can it be built, can it be found, and is it worth it?

A harbour is the first building in the game that cannot be raised wherever the
town likes. It wants REAL WATER beside it -- a body you could row a boat round,
not the wet patch at the end of the lane -- which means a flood fill over the
shoreline (Waters), and a flood fill is the kind of thing that fails silently.

Two ways it fails silently, and this holds both:

  THE FLOOD NEVER REACHES ITS OWN TARGET. Waters.surface_from walks a lattice
  and stops at ENOUGH square metres, with PROBES_MOST as a hard ceiling so it
  can never walk the open sea. If ENOUGH needs more cells than the ceiling
  allows, the early exit is UNREACHABLE: every flood runs to the ceiling, comes
  back short, and no village anywhere in an endless world ever builds a dock.
  Nothing errors. The trade simply is not in the game.

  THE SHORE SEARCH COSTS TOO MUCH. It rings outward from the town, and the
  probe count goes up with the square of the reach. It runs on the world
  generator's path when a village is sited, so it is worth knowing the number.

And the economics, because the whole point of a harbour is that it is EXPENSIVE
-- it is what makes a coastal village a different kind of town rather than a
village with a nice view.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WATERS = (ROOT / "scripts/world/waters.gd").read_text()
SHOP = (ROOT / "scripts/world/workshop.gd").read_text()


def const(name, text, where):
    m = re.search(r"^const %s\s*:?=\s*([0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


def trades():
    """Every TRADES row, as {name: {lumber, stone, employs, makes, wants}}."""
    block = SHOP[SHOP.index("const TRADES := {"):]
    block = block[:block.index("\n}\n")]
    out = {}
    for row in re.finditer(
            r'^\t"(\w+)": \{(.*?)^\t\},', block, re.M | re.S):
        name, body = row.group(1), row.group(2)
        spec = {}
        for key in ("employs", "lumber", "stone"):
            m = re.search(r'"%s": (\d+)' % key, body)
            spec[key] = int(m.group(1)) if m else 0
        m = re.search(r'"wants": ([0-9.]+) / ([0-9.]+)', body)
        spec["wants"] = float(m.group(1)) / float(m.group(2)) if m else 0.0
        for key in ("takes", "makes"):
            inner = re.search(r'"%s": \{(.*?)\}' % key, body).group(1)
            spec[key] = {k: int(v) for k, v in
                         re.findall(r'"(plant|meat)": (\d+)', inner)}
        out[name] = spec
    return out


STEP = const("STEP", WATERS, "waters.gd")
ENOUGH = const("ENOUGH", WATERS, "waters.gd")
PROBES_MOST = const("PROBES_MOST", WATERS, "waters.gd")
SHORE_WITHIN = const("SHORE_WITHIN", WATERS, "waters.gd")

MILLS = const("DOCK_WANTS_MILLS", SHOP, "workshop.gd")
BOAT_LUMBER = const("BOAT_LUMBER", SHOP, "workshop.gd")
BOATS_MOST = const("BOATS_MOST", SHOP, "workshop.gd")
SHIFT = const("SHIFT", SHOP, "workshop.gd")

TRADES = trades()
fail = []

if "dock" not in TRADES:
    sys.exit("BROKEN: there is no dock in Workshop.TRADES")
DOCK = TRADES["dock"]

# -- CAN THE FLOOD EVER SUCCEED? --------------------------------------------
need_cells = math.ceil(ENOUGH / (STEP * STEP))
print("THE FLOOD walks a %.0fm lattice and wants %.0f square metres, which is"
      % (STEP, ENOUGH))
print("   %d wet cells. Its hard ceiling is %d probes." % (need_cells, PROBES_MOST))
if need_cells > PROBES_MOST:
    fail.append("the flood needs %d wet cells and is capped at %d probes: the "
                "early exit is unreachable and NO VILLAGE ANYWHERE can ever "
                "build a dock" % (need_cells, PROBES_MOST))
else:
    print("   Headroom: %d probes of shoreline and blind alleys." % (PROBES_MOST - need_cells))
# A lattice fill wastes probes on dry cells at the water's edge, so wanting
# nearly the whole budget in WET ones is the same failure arriving slowly.
if need_cells > PROBES_MOST * 0.6:
    fail.append("the flood wants %d of its %d probes to come back WET: a lake "
                "with any shoreline at all will exhaust the ceiling before it "
                "reaches the target" % (need_cells, PROBES_MOST))

# -- WHAT THE SHORE SEARCH COSTS --------------------------------------------
probes = 0
ring = 20.0
rings = 0
while ring <= SHORE_WITHIN:
    probes += max(8, int(ring / 3.0))
    rings += 1
    ring += STEP * 2.0
print()
print("THE SHORE SEARCH walks %d rings out to %.0fm -- %d probes on an inland"
      % (rings, SHORE_WITHIN, probes))
print("   town, where every one of them comes back dry and costs nothing more.")
if probes > 600:
    fail.append("the shore search is %d probes before it gives up, and it runs "
                "on the world generator's path when a village is sited" % probes)

# -- IS IT THE BIGGEST TIMBER INVESTMENT IN THE GAME? -----------------------
fleet = BOAT_LUMBER * min(BOATS_MOST, DOCK["employs"])
total = DOCK["lumber"] + fleet
print()
print("A HARBOUR COSTS %d timber and %d stone, and its %d boats another %d --"
      % (DOCK["lumber"], DOCK["stone"], min(BOATS_MOST, DOCK["employs"]), fleet))
print("   %d timber all told. The next dearest building in the game:" % total)
others = sorted(((s["lumber"], n) for n, s in TRADES.items() if n != "dock"),
                reverse=True)
for lumber, name in others[:3]:
    print("      %-8s %d timber" % (name, lumber))
if DOCK["lumber"] <= others[0][0]:
    fail.append("a dock costs %d timber against the %s's %d: it is not the "
                "bigger investment it is supposed to be"
                % (DOCK["lumber"], others[0][1], others[0][0]))

# -- AND IS IT WORTH IT? ----------------------------------------------------
# Fishing is the one trade that makes food out of nothing but labour. If it is
# not clearly the best food per pair of hands, nobody pays thirty timber and
# two mills to reach it and the whole building is decoration.
print()
print("WHAT A SHIFT IS WORTH, per worker, in food a minute -- NET, which is the")
print("only honest way to read it: a mill hands back six and swallows four.")
best_other = 0.0


def net(spec):
    return sum(spec["makes"].values()) - sum(spec["takes"].values())


for name in sorted(TRADES):
    spec = TRADES[name]
    if net(spec) == 0 and not spec["makes"]:
        continue
    rate = net(spec) * 60.0 / SHIFT
    print("   %-8s %5.1f  (+%d -%d a shift, %d posts)"
          % (name, rate, sum(spec["makes"].values()),
             sum(spec["takes"].values()), spec["employs"]))
    if name != "dock":
        best_other = max(best_other, rate)
dock_rate = net(DOCK) * 60.0 / SHIFT
print("   Fishing is the only one of them that takes NOTHING: no seed corn, no")
print("   herd, no field to water. That is what the thirty timber buys.")
if dock_rate < best_other * 0.8:
    fail.append("a dock makes %.1f food a minute a worker against the best "
                "other trade's %.1f, and costs %d timber and %d mills to reach: "
                "nobody will ever build one"
                % (dock_rate, best_other, total, MILLS))

print()
print("AND IT WANTS %d MILLS standing first, so a harbour is only ever raised"
      % MILLS)
print("   by a town that has already solved its grain.")
if MILLS < 1:
    fail.append("a dock asks for %d mills: the prerequisite is not there" % MILLS)

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: the flood can succeed, the search is cheap, and a harbour is dear "
      "and worth it.")
