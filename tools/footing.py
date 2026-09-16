#!/usr/bin/env python3
"""A BUILDING MUST STAND ON THE GROUND THAT IS DRAWN, NOT ON THE NOISE.

`WorldGen.height_at` is a continuous function -- four octaves of noise, a detail
layer, and whatever scars have been cut into it -- and it is exact at any point
you care to ask about. The terrain the player can SEE is not that function. It
is a grid of samples taken off it, CHUNK_SIZE/chunk_cells apart, with two flat
triangles stretched over every cell (Chunk._build_terrain, which hands the same
grid to the collision heightmap so that what you see and what you walk on cannot
disagree).

Between those samples the drawn ground is a PLANE THROUGH THREE CORNERS. In a
hollow -- where the land curves up away from the middle of a cell -- that plane
sits above the true surface, by an amount this file works out from the shipped
noise parameters rather than guessing at.

So a building settled at `height_at` in a hollow is settled underneath the
hillside it is standing on. That is what happened to the schoolhouse: the town
raised it, it sank into the green, and the children gave up and walked back to
the totem.

The fix is not a fudge factor and this file exists to keep it from becoming one.
The drawn ground is piecewise linear between grid corners, so its highest point
over any footprint is EXACTLY the highest of the corners that footprint covers.
Sample those and no part of a building can be under the ground, on any terrain,
ever. Which means two things have to stay true: the sweep must sample GRID
CORNERS (a sample taken anywhere else is the same bug wearing a new function),
and it must use the step the chunks actually mesh at.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FOOT = (ROOT / "scripts/world/footing.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()
STANDS = {
    "edubba.gd": "scripts/world/edubba.gd",
    "workshop.gd": "scripts/world/workshop.gd",
    "house.gd": "scripts/world/house.gd",
}


def code(text):
    """Source with its comments taken out. A note about a thing is not it."""
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


fail = []

# -- THE SWEEP SAMPLES GRID CORNERS, AND NOTHING ELSE -----------------------
#
# The whole correctness argument is "the drawn ground is linear between grid
# corners, so its maximum over a footprint is the maximum of the corners it
# covers". A sweep that sampled the FOOTPRINT's corners instead would be the
# original bug with a new function wrapped round it, and would look right.
sweep = body_of(FOOT, "under")
asks = [r.strip() for r in sweep if "height_at(" in r]
on_grid = all(re.search(r"height_at\(\s*float\(gx\) \* step,\s*float\(gz\) \* step\s*\)",
                        r) for r in asks) and asks
print("THE SWEEP ASKS: %s" % (asks[0] if asks else "NOTHING"))
print("   ...which is %s." % ("the grid the land is meshed on"
                              if on_grid else "NOT ON THE GRID AT ALL"))
if not asks:
    fail.append("Footing.under never asks the world for a height, so every "
                "building settles at whatever it was given")
elif not on_grid:
    fail.append("Footing.under samples somewhere other than the terrain grid "
                "corners — which is the original bug in a new function: the "
                "drawn ground between corners is a plane and no sample off the "
                "grid bounds it")

# AND AT THE STEP THE CHUNKS MESH AT. Two files deciding separately how wide a
# terrain cell is would agree today and drift in a month.
mine = [r.strip() for r in body_of(FOOT, "under") if "var step :=" in r]
theirs = [r.strip() for r in body_of(CHUNK, "_build_terrain") if "var step :=" in r]
same = bool(mine) and bool(theirs) \
    and mine[0].split(":=")[1].replace("float(maxi(world.chunk_cells, 1))", "cells") \
    .replace(" ", "") == theirs[0].split(":=")[1].replace(" ", "")
print()
print("THE STEP:  footing  %s" % (mine[0] if mine else "(none)"))
print("           chunk    %s" % (theirs[0] if theirs else "(none)"))
if not same:
    fail.append("the footing and the chunk work out the width of a terrain "
                "cell differently, so a building is settled against a grid the "
                "land is not meshed on")

# -- HOW WRONG IT WAS, off the shipped noise --------------------------------
#
# A linear chord across a step `h` of a wave of amplitude A and wavelength L
# misses the crest by A(1 - cos(pi*h/L)). Summed over the octaves, that is how
# far ABOVE the true surface the drawn ground can sit in a hollow -- which is
# exactly how deep a building settled against the noise could be buried.
size = number(WORLD, "CHUNK_SIZE")
cells = float(re.search(r"var chunk_cells := (\d+)", WORLD).group(1))
step = size / cells
freq = float(re.search(r"_height_noise\.frequency = ([\d.]+)", WORLD).group(1))
octaves = int(re.search(r"_height_noise\.fractal_octaves = (\d+)", WORLD).group(1))
detail_f = float(re.search(r"_detail_noise\.frequency = ([\d.]+)", WORLD).group(1))
detail_a = float(re.search(r"_detail_noise\.get_noise_2d\(x, z\) \* ([\d.]+)",
                           WORLD).group(1))
amps = dict(re.findall(r'"(\w+)":\n\t\t\tamp = ([\d.]+)', WORLD)) or {}
for name, val in re.findall(r'"(\w+)":\n(?:\t*#[^\n]*\n)*\t*\t\tamp = ([\d.]+)', WORLD):
    amps[name] = val
amps.setdefault("grass", re.search(r"var amp := ([\d.]+)", WORLD).group(1))


def miss(amp_total, wavelength):
    return amp_total * (1.0 - math.cos(math.pi * step / wavelength))


shares = [0.5 ** k for k in range(octaves)]
shares = [s / sum(shares) for s in shares]
print()
print("THE TERRAIN GRID is %.1fm across (CHUNK_SIZE %.0f / %d cells)." % (step, size, cells))
print("HOW FAR THE DRAWN GROUND CAN SIT ABOVE THE NOISE, per biome:")
worst = 0.0
for biome in sorted(amps, key=lambda b: -float(amps[b])):
    amp = float(amps[biome])
    off = sum(miss(amp * shares[k], 1.0 / (freq * (2 ** k))) for k in range(octaves))
    off += miss(detail_a, 1.0 / detail_f)
    worst = max(worst, off)
    print("   %-14s amp %-5.0f  ->  up to %.2fm of a building buried" % (biome, amp, off))
# Reported, and NOT asserted. "The error is big enough to be worth fixing" is a
# claim about my own arithmetic rather than about the code, and a check that can
# only fail when somebody flattens the whole world is a check that never fails —
# which this codebase has learned the hard way is worse than no check, because
# it is also a claim. The settle above is correct whatever this number says.
print("   (%s is where the schoolhouse was found, with %.2fm of it underground)"
      % ("grass", sum(miss(float(amps["grass"]) * shares[k], 1.0 / (freq * (2 ** k)))
                      for k in range(octaves)) + miss(detail_a, 1.0 / detail_f)))

# -- AND EVERYTHING THAT STANDS ON THE GROUND SITS DOWN ON IT ---------------
print()
print("WHAT SETTLES ITSELF:")
for name, path in STANDS.items():
    text = (ROOT / path).read_text()
    ready = body_of(text, "_ready")
    sits = any("Footing.settle(" in r for r in ready)
    print("   %-14s %s" % (name, "settles in _ready" if sits else "DOES NOT SETTLE"))
    if not sits:
        fail.append("%s never sits down on the drawn ground, so it is placed at "
                    "whatever height the noise said and sinks into any hollow "
                    "it is raised in" % name)

# THE DOCK IS THE ONE EXCEPTION, and it has to stay one: its deck stands at the
# waterline with most of its footprint over open water, and the highest ground
# under that footprint is the beach it is getting away from.
shop = body_of(FOOT, "settle")  # touched below only for the shape of the check
ready = body_of((ROOT / "scripts/world/workshop.gd").read_text(), "_ready")
guard = next((i for i, r in enumerate(ready) if 'trade == "dock"' in r), None)
sits = next((i for i, r in enumerate(ready) if "Footing.settle(" in r), None)
bails = any(r.strip() == "return" for r in ready[guard:sits]) \
    if guard is not None and sits is not None and guard < sits else False
print("   %-14s %s" % ("(the dock)",
                       "excused, before the settle"
                       if bails else "SETTLED LIKE THE REST"))
if not bails:
    fail.append("the dock is settled onto the highest ground under its deck — "
                "which is the beach it is built to reach out from, so the "
                "jetty is lifted out of the water it exists to stand in")

# A THING MEASURES ITS OWN FOOTPRINT, rather than being told one. A table of
# footprints kept anywhere but on the buildings drifts from the meshes and
# nothing says so — the same bargain Util.within makes with a blow's reach.
own = body_of(FOOT, "settle")
asked = any("footprint_of(" in r for r in own)
turned = any("get_euler()" in r for r in body_of(FOOT, "footprint_of"))
print()
print("A BUILDING'S FOOTPRINT is %s, and %s."
      % ("read off its own collision shape" if asked else "GUESSED FROM OUTSIDE",
         "turned with it" if turned else "USED UNTURNED"))
if not asked:
    fail.append("Footing.settle does not measure the thing it is settling, so "
                "the size a building is and the height it stands at are two "
                "opinions that will drift")
if not turned:
    fail.append("a footprint measured in local space is used in world space — a "
                "village is rotated and everything in it with it, so that is "
                "the wrong rectangle for every town but one")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: buildings stand on the ground that is drawn.")
