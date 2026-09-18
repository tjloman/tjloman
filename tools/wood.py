#!/usr/bin/env python3
"""HOW FAR OUT THE TREES ARE REAL.

A chunk inside `load_radius` is a place: collision to walk on, water to drown
in, animals, villages, and real trees. Past it a chunk is scenery — one painted
quad a tree, the whole chunk's worth in a single MultiMesh. The quads stand
exactly where the trunks would, off the same seeded stand and the same analytic
ground, so nothing MOVES when one becomes the other. But a quad is a quad, and
the line where the wood turns real is the most visible seam left in the world.

So on the tier that can hold it the trunks reach one ring further than the
place does. What that buys is the seam pushed from about 150 metres out to
about 190. What it costs is the trunks: thirty-two chunks' worth of WildTree
nodes, each one a body in every `get_nodes_in_group("trees")` scan in the game,
which is exactly what the billboards exist to avoid.

The ring is cheap to describe and easy to get wrong in four ways, which is what
this file is for.

  IT MUST NOT REACH PAST THE UNLOAD RING. Beyond that a chunk is stripped of
  everything living on it, so a wood ring further out would plant trunks on a
  cell one frame and strip them the next, for ever.

  THE WOOD IS NOT DRAWN TWICE. A wooded chunk holds real trees AND is still
  `terrain_only`, which is the state every billboard path tests for.

  A FELLED WOOD STAYS FELLED. The stand is remembered as it actually STOOD, not
  as the seed described it, on the way in and on the way out.

  AND THE STREAM STAYS IN STEP. The far ring replays the chunk's own scatter
  RNG to decide where its billboards go. Skip the draw that plants the wood and
  every tree in the biome moves as you walk up to it.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
QUAL = (ROOT / "scripts/quality.gd").read_text()
GEN = (ROOT / "scripts/world/world_gen.gd").read_text()
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()


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


def tiers(text, name):
    found = re.search(r"func %s\(\) -> int:\s*\n\s*return \[([^\]]*)\]" % name, text)
    return [int(v) for v in found.group(1).split(",")] if found else None


fail = []
load = tiers(QUAL, "load_radius")
unload = tiers(QUAL, "unload_radius")
beyond = tiers(QUAL, "wood_beyond")
TIER = ["LOW", "MEDIUM", "HIGH"]

print("%-8s %-6s %-6s %-6s %s" % ("tier", "place", "wood", "unload", "real trees"))
if None in (load, unload, beyond):
    fail.append("one of load_radius, unload_radius or wood_beyond is gone, so "
                "there is no telling how far the wood reaches")
else:
    for i, name in enumerate(TIER):
        wood = min(load[i] + beyond[i], unload[i])
        near = (load[i] * 2 + 1) ** 2
        wooded = (wood * 2 + 1) ** 2
        print("   %-5s %-6d %-6d %-6d %d chunks (%+d over the place)"
              % (name, load[i], wood, unload[i], wooded, wooded - near))
        if load[i] + beyond[i] > unload[i]:
            fail.append("on %s the wood ring reaches past the unload ring, so "
                        "every cell in the band is planted and stripped on "
                        "alternate frames for as long as the player stands "
                        "there" % name)

# -- THE BOUND IS IN THE CODE, NOT ONLY IN THE TABLE ABOVE -------------------
ready = body_of(GEN, "_ready")
bounded = any("wood_radius" in r and "mini(" in r and "unload_radius" in r
              for r in ready)
print()
print("THE RING IS %s."
      % ("held inside the unload ring" if bounded else "FREE TO REACH PAST IT"))
if not bounded:
    fail.append("nothing clamps the wood ring to the unload ring — the table "
                "above is only true of the numbers that happen to be there now")

# -- THE WOOD IS NOT DRAWN TWICE ---------------------------------------------
boards = body_of(CHUNK, "retally_boards")
guarded = False
for i, row in enumerate(boards):
    if "wooded" in row:
        guarded = any(r.strip() == "return" for r in boards[i:i + 3])
        break
print("A WOODED CHUNK %s."
      % ("draws its trees and not its quads" if guarded else "DRAWS BOTH"))
if not guarded:
    fail.append("the billboard pass does not ask whether the trees are already "
                "standing, so a felled tree, a burn, a crater or a coarsening "
                "out there draws the whole wood a second time on top of itself")

# -- A FELLED WOOD STAYS FELLED ----------------------------------------------
planting = body_of(CHUNK, "plant_the_wood")
boarding = body_of(CHUNK, "board_the_wood")
in_remembers = any("_stand_known" in r for r in planting)
out_remembers = any("_standing_stand()" in r for r in boarding)
print("WHAT WAS CUT DOWN stays down: %s on the way in, %s on the way out."
      % ("yes" if in_remembers else "NO", "yes" if out_remembers else "NO"))
if not in_remembers:
    fail.append("planting the wood ring asks the SEED what grows there, so a "
                "wood you logged from inside the near ring stands back up the "
                "moment you step out of it")
if not out_remembers:
    fail.append("boarding the wood back up reads the seed rather than the trees "
                "that are actually left, so an axe or a fireball that reached "
                "out there is forgotten the moment you walk away")

# -- AND THE SCATTER STREAM STAYS IN STEP ------------------------------------
#
# `_scatter` draws the stand whether or not it plants it, because the far ring
# replays the same RNG in the same order to place its billboards.
scatter = body_of(CHUNK, "_scatter")
draws = next((i for i, r in enumerate(scatter) if "_tree_stand(rng)" in r), None)
plants = next((i for i, r in enumerate(scatter) if "_plant_stand(" in r), None)
gate = next((i for i, r in enumerate(scatter) if "if plant_wood" in r), None)
# The draw has to happen OUTSIDE the gate, which means before it. Writing this
# as three separate booleans and then failing on two of them is how the first
# version of this check passed the exact mutation it was written for.
in_step = (draws is not None and gate is not None and plants is not None
           and draws < gate < plants)
print("THE SCATTER %s."
      % ("draws the stand whether or not it plants it" if in_step
         else "SKIPS THE DRAW WHEN IT SKIPS THE PLANTING"))
if not in_step:
    fail.append("the stand is drawn only when it is planted — and the far ring "
                "replays this stream in this order to place its billboards, so "
                "every tree in the biome walks across the ground as you walk up "
                "to it")

# -- AND A CHUNK ARRIVING WITH TREES ON IT DOES NOT GET A SECOND SET ---------
# EVERY scatter in there, not "the word appears somewhere in the function":
# `flesh_out` has two of them, one on each side of a re-cut, and asking whether
# the flag is mentioned passed happily with one of them still unconditional.
flesh = body_of(CHUNK, "flesh_out")
scatters = [r for r in flesh if "_scatter(" in r]
keeps = bool(scatters) and all("had_wood" in r for r in scatters)
print("A CHUNK PROMOTED FROM THE WOOD RING %s (%d scatter%s)."
      % ("keeps the trees it has" if keeps else "IS GIVEN A SECOND WOOD",
         len(scatters), "" if len(scatters) == 1 else "s"))
if not keeps:
    fail.append("a chunk that already had its trunks is scattered again when it "
                "becomes a place, so the wood doubles and everything felled out "
                "there stands back up")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: the trunks reach as far as the tier can hold, once each, and stay felled.")
