#!/usr/bin/env python3
"""THE EDGE OF WHAT YOU HOLD, STANDING ON THE GROUND IT CLAIMS.

Every ring in this game was a torus lying flat at one height, which is only the
truth on a billiard table. Drawn around a village on rolling country, half of
it floats a metre over a rise and the other half is buried in the next one --
and a boundary you cannot trust the look of is worse than none drawn at all,
because the player believes it.

    "Let's make the influence rings rise/lower to emanate from the terrain.
     They should appear like a ring of smoldering fire, or hints of radiant
     beams (evil/good respectively)."

So it is a curtain of quads planted on the ground all the way round. Which
introduces the one cost that could quietly eat a frame: every corner of that
ribbon is a QUESTION PUT TO THE TERRAIN, and terrain reads are the most
expensive thing this game does -- the meter has a line for them, and they have
peaked over nine thousand in a frame before now.

Five claims:

  IT IS BUILT FROM THE GROUND. Sampled per corner, not set to one height.

  AND ONLY WHEN IT MUST BE. A village never moves, so its ring is asked once.
  The creature's follows a walking animal, and is rebuilt on distance rather
  than on every frame.

  ONE RING FOR BOTH. The creature's and the village's are the same object, so
  "this ground is yours" has one vocabulary and one place to change it.

  IT BURNS OR IT SHINES, by what the god has become.

  AND IT KEEPS ITS OWN TIME. A village ring is recoloured when the population
  changes, which is every few minutes; one that only guttered when it was
  recoloured would sit dead still around every town in the world.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RING = (ROOT / "scripts/miracles/ground_ring.gd").read_text()
REACH = (ROOT / "scripts/miracles/reach_ring.gd").read_text()
TOWN = (ROOT / "scripts/world/village.gd").read_text()
CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()


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


fail = []
SEGMENTS = int(number(RING, "SEGMENTS") or 0)
MOVED = number(RING, "MOVED")
SHARE = number(RING, "MOVED_SHARE")
WALK = number(CREATURE, "WALK_SPEED")

# -- BUILT FROM THE GROUND ---------------------------------------------------
raising = body_of(RING, "_raise")
samples = any("world.surface_at(" in r for r in raising)
per_corner = any("for i in SEGMENTS" in r for r in raising)
stands = any("+ STANDS" in r for r in raising)
fades = [r for r in raising if "1.0, 1.0, 1.0, 0.0" in r]
print("THE RIBBON IS %s, and its top %s."
      % ("planted on the terrain corner by corner" if samples and per_corner
         else "SET TO ONE HEIGHT",
         "fades out" if fades else "IS A WALL"))
if not samples or not per_corner:
    fail.append("the ring is not sampled against the ground around its own "
                "circle, so it is a flat hoop again — floating over the rise "
                "and buried in the dip, which is a boundary the player cannot "
                "trust the look of")
if not stands or not fades:
    fail.append("the ribbon does not stand up from the ground and fade out at "
                "the top, so it reads as a wall around the town rather than as "
                "the ground giving something off")

# -- AND ONLY WHEN IT MUST BE ------------------------------------------------
standing = body_of(RING, "stand_on")
lazy = any("_built_at.distance_to(centre)" in r for r in standing)
print()
print("WHAT THE GROUND IS ASKED, per ring:")
print("   %-34s %s" % ("corners in one rebuild", SEGMENTS))
if lazy and MOVED and WALK:
    for what, radius in [("a whelp's ring (14m)", 14.0), ("a giant's (40m)", 40.0),
                         ("a small town's (28m)", 28.0)]:
        stir = max(MOVED, radius * SHARE)
        # A creature walking flat out re-asks every `stir` metres.
        per_sec = WALK / stir * SEGMENTS
        print("   %-34s every %.1fm walked -> %.0f reads a second at a full walk"
              % (what, stir, per_sec))
    still = 0
    print("   %-34s %d (a village never moves)" % ("a town standing still", still))
if not lazy:
    fail.append("the ribbon is rebuilt without asking whether anything moved, "
                "so a ring around a walking creature puts %d questions to the "
                "terrain every frame — and terrain reads are the most "
                "expensive thing this game does" % SEGMENTS)
if SEGMENTS > 128:
    fail.append("%d corners a ring is more terrain reads than a smooth circle "
                "is worth" % SEGMENTS)

# -- ONE RING FOR BOTH -------------------------------------------------------
shared = "GroundRing" in code(REACH) and "GroundRing" in code(TOWN)
old_hoops = []
for name, text in [("the creature's", REACH), ("a village's", TOWN)]:
    if "TorusMesh.new()" in code(text):
        old_hoops.append(name)
print()
print("THE CREATURE'S RING AND A VILLAGE'S ARE %s."
      % ("the same object" if shared and not old_hoops else "TWO DIFFERENT THINGS"))
if not shared or old_hoops:
    fail.append("%s ring is still a torus of its own, so 'this ground is "
                "yours' is said two different ways and only one of them was "
                "fixed" % (old_hoops[0] if old_hoops else "one"))

# -- IT BURNS OR IT SHINES ---------------------------------------------------
tinting = body_of(RING, "tint")
both_ways = any("_burn_plate()" in r and "_shine_plate()" in r for r in tinting)
by_align = any("align <" in r for r in tinting)
plates = body_of(RING, "_plate")
ragged = any("ragged" in r for r in plates)
print("IT %s by what the god has become."
      % ("burns or shines" if both_ways and by_align and ragged
         else "LOOKS THE SAME WHATEVER THE GOD HAS BECOME"))
if not both_ways or not by_align:
    fail.append("the ring does not choose between embers and beams on the "
                "god's alignment, which was the whole of what it is meant to "
                "say from across a valley")
if not ragged:
    fail.append("both looks are drawn from the same plate, so smouldering and "
                "shining are the same picture in two colours")

# -- AND IT KEEPS ITS OWN TIME -----------------------------------------------
ticks = body_of(RING, "_process")
runs = any("uv1_offset" in r for r in ticks)
gutters = any("_burn(" in r for r in ticks)
asks_caller = "drift(" in code(REACH) or "drift(" in code(TOWN)
print("IT %s."
      % ("keeps its own time" if runs and gutters and not asks_caller
         else "WAITS TO BE TOLD TO MOVE"))
if not runs or not gutters:
    fail.append("the ring does not run its own fire — a village's is "
                "recoloured when the population changes, so one that moves "
                "only when it is recoloured sits dead still around every town "
                "in the world and flickers once when somebody is born")
if asks_caller:
    fail.append("something still calls drift() from outside, so the ring both "
                "keeps its own time and is told the time, and whichever ring "
                "has two callers runs at double speed")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: one ring for both, planted on the ground, asked only when it "
      "moves, burning or shining on its own clock.")
