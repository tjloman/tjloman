#!/usr/bin/env python3
"""EVERYTHING STANDS ON THE GROUND IT IS PUT ON.

    "Buildings are spawning below ground! Can we fix our town generator?"

It was not the town generator. `find_build_spot` picks dry, gently sloped
ground and puts the building's NODE exactly on it, which is right. What sank
was the model hung off that node: a custom house, store, school, workshop, bush
or rock is authored by somebody else, with its pivot wherever they left it, and
a model pivoted at its middle hangs half of itself below the node it is
attached to. The village is then correctly placed and visibly buried.

The game already knew this and already had the answer. When herds began drawing
animals whose feet floated, ModelBank.footing was written -- the measured
distance from a model's pivot to the bottom of its own bounding box -- and
Animal was taught to lift by it. One caller. Every other model in the game went
on being hung from whatever pivot it came with, including every building in
every town.

  IT IS SCALE-FREE, which is why one number does for a sapling and a
  full-grown tree. A child's local offset is scaled by its parent exactly as
  the model's own extents are, so lifting by the footing in local units puts
  the bottom on the node at any scale. No multiplication, and none wanted.

  AND IT IS HARMLESS WHERE IT IS NOT NEEDED. A model authored with its pivot
  already at its base measures a footing of zero and does not move. So the rule
  is simply: every model the bank hands out is lifted by its own footing, and
  a site that does not is a site waiting for somebody to re-export an asset
  with a different pivot.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "scripts"

## The one model in the game that stands on nothing. Excused by name and with
## a reason, because "it looked wrong when I tried it" is not a rule anybody
## can check a year from now.
EXCUSED = {
    "scripts/player/divine_hand.gd": "the hand hovers at the cursor and stands "
                                     "on no ground at all; lifting it by its "
                                     "own height would move it away from the "
                                     "thing it is pointing at",
}

fail = []
sites, lifted = [], []
for path in sorted(SRC.glob("**/*.gd")):
    short = str(path.relative_to(ROOT))
    rows = path.read_text().split("\n")
    for i, row in enumerate(rows):
        bare = row.split("#")[0]
        made = re.search(r"ModelBank\.instantiate(_any)?\(", bare)
        if not made:
            continue
        # The lift is within a few lines of the instantiation, inside the same
        # `if custom != null:` — read the block rather than the whole file, or
        # one site with a lift would excuse every other site in the file.
        block = "\n".join(rows[i:i + 12])
        has = "ModelBank.footing" in block
        sites.append((short, i + 1, bool(made.group(1)), has, short in EXCUSED))
        if has:
            lifted.append(short)

print("EVERY MODEL THE BANK HANDS OUT, and whether it is stood on its footing:")
for short, line, anyish, has, excused in sites:
    print("   %-40s %-5s %s" % ("%s:%d" % (short, line),
                                "any" if anyish else "one",
                                "lifted" if has else
                                ("excused: " + EXCUSED[short]) if excused
                                else "<-- HANGS FROM ITS PIVOT"))
    if excused and has:
        fail.append("%s:%d lifts a model that stands on nothing — %s"
                    % (short, line, EXCUSED[short]))
    if not has and not excused:
        fail.append("%s:%d hangs its model from whatever pivot the asset was "
                    "authored with — a pivot at the middle buries half of it, "
                    "which is a village that looks badly placed and is not"
                    % (short, line))
print("   %d sites, %d lifted, %d excused."
      % (len(sites), len(lifted), len(EXCUSED)))
if len(sites) < 8:
    fail.append("only %d model sites were found, which is fewer than this game "
                "has — the search has stopped matching and a check that finds "
                "nothing passes" % len(sites))

# -- THE ONE THAT KNOWS HOW, AND WHAT IT MEASURES ----------------------------
bank = (ROOT / "scripts/model_bank.gd").read_text()
measures = "return -bounds(model_name).position.y" in bank
for_any = "func footing_any(" in bank
print()
print("THE FOOTING IS %s, and there is %s."
      % ("measured off the model's own box" if measures
         else "A NUMBER SOMEBODY CHOSE",
         "one for a model asked for by several names" if for_any
         else "NO ANSWER FOR instantiate_any"))
if not measures:
    fail.append("ModelBank.footing no longer measures the model's own bounding "
                "box — a hand-picked lift is right for exactly the asset it "
                "was picked for and wrong for the next one")
if not for_any:
    fail.append("there is no footing_any, so a tree that asked for tree_pine "
                "and settled for tree is lifted by the footing of a model it "
                "did not get")

# -- AND NOBODY MULTIPLIES IT BY A SCALE -------------------------------------
#
# The tempting mistake: a scaled parent LOOKS like it needs the footing scaled
# too. It does not — a child's local offset is scaled by the parent exactly as
# the model's extents are — and multiplying lifts a full-grown tree metres into
# the air.
scaled = []
for path in sorted(SRC.glob("**/*.gd")):
    for i, row in enumerate(path.read_text().split("\n"), 1):
        bare = row.split("#")[0]
        if "ModelBank.footing" in bare and re.search(r"footing\w*\([^)]*\)\s*\*", bare):
            scaled.append("%s:%d" % (path.relative_to(ROOT), i))
print("THE LIFT IS %s."
      % ("taken in local units, unscaled" if not scaled
         else "MULTIPLIED BY A SCALE SOMEWHERE"))
for where in scaled:
    fail.append("%s multiplies the footing by something — a child's local "
                "offset is already scaled by its parent, so this lifts a "
                "full-grown model clear of the ground" % where)

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: %d of %d models stand on their own footing, measured rather "
      "than chosen, nothing scales it twice, and the one that stands on "
      "nothing is named." % (len(lifted), len(sites)))
