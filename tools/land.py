#!/usr/bin/env python3
"""HOW HARD THE LAND IS ASKED.

`seeded_height_at` is the most expensive thing in this game: five noise samples
and a walk of every scar in range, in GDScript. Everything asks it — routing,
drowning, placement, meshing, grazing — and the biggest single asker by far is
the shore route, which a body near water runs on EVERY physics tick.

    Animal   112.4 ms   116 calls   0.969 each

A sheep at 0.969ms a frame is not a complicated sheep, it is a sheep standing
at a lake edge asking the land the same hundred questions thirty times a second.
A villager beside it costs 0.020ms, and the difference is not what they think
about: it is that a villager inside its own town skips the terrain probe
entirely (VillagerLook.at_home) and a sheep has no town.

What this file guards is the four properties that keep the bill down, and it
prints what one body costs under each of them so the number can be argued with.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAV = (ROOT / "scripts/nav_field.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()


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
step = body_of(NAV, "_bad_step")
route = body_of(NAV, "water_route")
worst = body_of(NAV, "_least_bad")

# -- THE GROUND UNDER THE BODY IS ONE PLACE ----------------------------------
#
# It cannot have moved between the headings of a sweep, and there are fourteen
# of those. Read inside the step test, that is twenty-eight reads of one point.
takes_here = any("here: float" in r for r in step)
reads_here = any("height_at(pos.x, pos.z)" in r for r in step)
sweep_once = any("here: float" in r for r in worst) \
    and not any("height_at(pos.x, pos.z)" in r for r in worst)
print("THE GROUND UNDERFOOT is read %s."
      % ("once per route" if takes_here and not reads_here and sweep_once
         else "ONCE PER HEADING, OF THE SAME POINT"))
if reads_here or not takes_here:
    fail.append("the step test reads the ground under the body itself, so a "
                "fourteen-heading sweep reads one unmoving point fourteen times")
if not sweep_once:
    fail.append("the last-resort sweep reads the ground under the body once per "
                "heading — sixteen reads of a point the body is standing on")

# -- AND THE ANSWER IS KEPT ---------------------------------------------------
remembers = any("route_at" in r for r in route)
by_place = any("distance_to(asked)" in r or "probe * REPROBE" in r for r in route)
by_heading = any("REMEMBERS_WHILE" in r for r in route)
reprobe = number(NAV, "REPROBE")
print("THE ANSWER IS %s."
      % ("kept while it is still an answer" if remembers and by_place and by_heading
         else "THROWN AWAY AND ASKED AGAIN NEXT FRAME"))
if not remembers:
    fail.append("the shore route is recomputed from scratch every physics tick, "
                "so a body that has moved four centimetres asks the land the "
                "same hundred questions again")
if remembers and not by_place:
    fail.append("the remembered route is not bounded by how far the body has "
                "MOVED, so a beast can walk the whole way to the water on an "
                "answer about where it used to be")
if remembers and not by_heading:
    fail.append("the remembered route is not bounded by where the body now "
                "WANTS to go, so a turn that avoided water on the old heading "
                "is applied to a new one it knows nothing about")
if reprobe is not None and reprobe >= 1.0:
    fail.append("the body may walk a whole probe-length on one answer, so it "
                "can step clean past the only warning it gets")

# -- AND THE LAND SAYS HOW OFTEN IT WAS ASKED --------------------------------
counted = "static var reads" in WORLD \
    and any("reads += 1" in r for r in body_of(WORLD, "seeded_height_at"))
free = any("Ledger.on" in r for r in body_of(WORLD, "seeded_height_at"))
METER = (ROOT / "scripts/ui/frame_meter.gd").read_text()
shown = "WorldGen.reads" in code(METER)
print("AND THE METER %s how many there were."
      % ("says" if counted and shown else "CANNOT SAY"))
if not counted or not shown:
    fail.append("nothing counts the terrain reads, so the next argument about "
                "where a frame went ends where the last one did — in a guess")
if counted and not free:
    fail.append("the counter runs whether or not anybody is reading the meter, "
                "on the hottest function in the game")

# -- WHAT ONE BODY COSTS -----------------------------------------------------
#
# Counting `seeded_height_at`, which is what the meter now counts too.
#   is_underwater  -> 1     (written out to reuse the seeded height)
#   height_at      -> 1
#   _depth_at      -> 2     (water_level_at + height_at)
SWEEP = len(re.search(r"var mags := \[([^\]]*)\]", NAV).group(1).split(",")) * 2
DRY = int(number(NAV, "DRY_SWEEP") or 16)
PROBE = 1.7          # the default a beast passes
SPEED = 3.0          # a sheep's walk
TICKS = 30.0

per_step = 2                      # is_underwater ahead + the ground there
clear = 1 + per_step              # the ground underfoot, once, plus one step
shore = 1 + SWEEP * per_step
boxed = shore + DRY * 3           # _depth_at + the ground there, per heading
every = (PROBE * (reprobe or 1.0)) / SPEED * TICKS   # frames one answer lasts
print()
print("ONE BEAST, walking at %.0f m/s on a %.0f Hz clock, asks the land:" % (SPEED, TICKS))
for name, cost in [("on open ground", clear), ("at a shoreline", shore),
                   ("boxed in by water", boxed)]:
    print("   %-18s %3d reads when it asks, every %.1f frames -> %5.1f a frame"
          % (name, cost, every, cost / every))
print("   ...against %d, %d and %d a frame before, which is where the sheep went."
      % (4, 4 * SWEEP, 4 * SWEEP + 4 * DRY))

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: the land is asked once, the answer is kept, and the bill is counted.")
