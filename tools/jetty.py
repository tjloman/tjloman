#!/usr/bin/env python3
"""DOES A JETTY ACTUALLY END UP OVER WATER, AND DO THE BOATS?

Every dock and every boat in a whole test run was on dry land, and nothing in
this toolbox could say so, because every one of these tools reads CONSTANTS and
this was a failure of GEOMETRY. The numbers were all reasonable. They were
applied to the wrong axis.

Two faults, and the second is the one worth a tool:

  THE SIGN. `_ready` turns a dock so its +Z runs out to sea; `_tie_up` read -Z.
  So every mooring was probed INLAND, found no water, fell through to a
  fallback and put the boat on the lawn behind the jetty. A one-character
  disagreement between two functions forty lines apart, in a file that compiles
  perfectly and runs without a single error.

  THE WALK-BACK. The finder stepped inland from a wet probe until it hit dry
  ground and called that a harbour -- which is a spot NEAR water, and near
  water is what every building in a lakeside village already is. On a shallow
  shore it landed metres inland and the deck ran out over grass.

So this builds a shoreline in Python, runs the shipped arithmetic over it, and
asks where things actually land. Four shores: a straight coast, a gentle curve,
a narrow bay, and a diagonal. For each, the dock's root must be DRY, every
plank past JETTY_WET_FROM must be WET, and all three moorings must be WET.

It is a model, not the game -- the real `is_underwater` also knows about ponds,
scars and whether the sea reaches a hollow. What it shares with the game is the
arithmetic, which is where the bug was.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WATERS = (ROOT / "scripts/world/waters.gd").read_text()
SHOP = (ROOT / "scripts/world/workshop.gd").read_text()


def const(name, text=WATERS, where="waters.gd"):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9]+\.?[0-9]*)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


JETTY_TO = const("JETTY_TO")
JETTY_WET_FROM = const("JETTY_WET_FROM")
SHORE_FOOTING = const("SHORE_FOOTING")
WATERLINE_STEP = const("WATERLINE_STEP")
DECK_STEP = const("DECK_STEP")
SHORE_WITHIN = const("SHORE_WITHIN")
STEP = const("STEP")
BOATS_MOST = const("BOATS_MOST", SHOP, "workshop.gd")

# ------------------------------------------------------------------ shores --
# Water is everything with z above the shoreline. A town sits at the origin.
SHORES = {
    "a straight coast": lambda x: 40.0,
    "a gentle curve": lambda x: 40.0 + 0.004 * x * x,
    "a narrow bay": lambda x: 40.0 - 25.0 * math.exp(-(x / 18.0) ** 2),
    "a diagonal": lambda x: 40.0 + 0.6 * x,
}


def wet(shore, x, z):
    return z > shore(x)


# ------------------------------------------------------- the shipped maths --
def waterline(shore, wx, wz, ox, oz):
    """Waters._waterline, transcribed."""
    dx = wx - ox * (JETTY_TO + SHORE_FOOTING * 2.0)
    dz = wz - oz * (JETTY_TO + SHORE_FOOTING * 2.0)
    if wet(shore, dx, dz):
        return None
    while math.hypot(wx - dx, wz - dz) > WATERLINE_STEP:
        mx, mz = (wx + dx) * 0.5, (wz + dz) * 0.5
        if wet(shore, mx, mz):
            wx, wz = mx, mz
        else:
            dx, dz = mx, mz
    return wx, wz


def deck_is_over_water(shore, rx, rz, ox, oz):
    """Waters._deck_is_over_water, transcribed."""
    along = JETTY_WET_FROM
    while along <= JETTY_TO:
        if not wet(shore, rx + ox * along, rz + oz * along):
            return False
        along += DECK_STEP
    return True


def dock_spot(shore, px, pz, angle):
    """Waters._dock_spot, transcribed (minus the body-size flood)."""
    if not wet(shore, px, pz):
        return None
    ox, oz = math.cos(angle), math.sin(angle)
    edge = waterline(shore, px, pz, ox, oz)
    if edge is None:
        return None
    rx = edge[0] - ox * SHORE_FOOTING
    rz = edge[1] - oz * SHORE_FOOTING
    if wet(shore, rx, rz):
        return None
    if not deck_is_over_water(shore, rx, rz, ox, oz):
        return None
    return rx, rz, angle


def look_for_a_shore(shore):
    """Waters._look_for_a_shore, transcribed, from a town at the origin."""
    ring = 20.0
    while ring <= SHORE_WITHIN:
        steps = max(8, int(ring / 3.0))
        for i in range(steps):
            angle = math.tau * i / steps
            px, pz = math.cos(angle) * ring, math.sin(angle) * ring
            found = dock_spot(shore, px, pz, angle)
            if found:
                return found
        ring += STEP * 2.0
    return None


def moorings(shore, rx, rz, angle):
    """Workshop._tie_up, transcribed. +Z is seaward, so `out` IS the bearing."""
    ox, oz = math.cos(angle), math.sin(angle)
    bx, bz = oz, -ox
    out = []
    for n in range(int(BOATS_MOST)):
        along = (n - (BOATS_MOST - 1) * 0.5) * 2.4
        tie = None
        for reach in (JETTY_TO + 1.5, JETTY_TO + 4.0, JETTY_TO + 7.0,
                      JETTY_TO + 11.0):
            tx = rx + ox * reach + bx * along
            tz = rz + oz * reach + bz * along
            if wet(shore, tx, tz):
                tie = (tx, tz)
                break
        out.append(tie)
    return out


fail = []

# -- THE SIGN, read off the source ------------------------------------------
# The fault that put every boat in the game on a lawn. `_ready` puts +Z out to
# sea; anything measuring seaward must agree with it.
tie_body = SHOP[SHOP.index("func _tie_up("):]
# TO THE END OF THE FUNCTION, by indentation. Slicing to the next blank run ran
# past it and swallowed the neighbour's `return Vector3.INF`, so the fallback
# check below could never fail -- a checker that cannot fail is worse than no
# checker, because it is also a claim.
lines = []
for row in tie_body.split("\n")[1:]:
    if row and not row.startswith(("\t", " ")):
        break
    lines.append(row)
tie_body = "\n".join(lines)
print("THE SEAWARD AXIS:")
turns_z = "atan2(cos(out_to_sea), sin(out_to_sea))" in SHOP
print("   _ready puts %s out to sea." % ("+Z" if turns_z else "SOMETHING ELSE"))
ties_minus = "-global_transform.basis.z" in tie_body
print("   _tie_up measures along %s." % ("-Z" if ties_minus else "+Z"))
if not turns_z or ties_minus:
    fail.append("_ready and _tie_up disagree about which way the sea is. Every "
                "mooring is probed inland, finds no water, and the boat ends up "
                "on the lawn behind the jetty — which is exactly what happened")
# ITS LAST STATEMENT, and not merely "does INF appear anywhere in it". The
# first version of this check looked for the string, and `_tie_up` opens with a
# null guard that also returns INF -- so restoring the very fallback this
# exists to forbid did not fail it. A checker that cannot fail is worse than no
# checker, because it is also a claim.
last = [row.strip() for row in tie_body.split("\n") if row.strip()][-1]
print("   _tie_up, having found no water, %s." % (
    "gives up" if last == "return Vector3.INF" else "puts the boat SOMEWHERE"))
if last != "return Vector3.INF":
    fail.append("_tie_up ends with `%s` rather than giving up. A mooring that "
                "cannot be found is a boat that should not be launched; putting "
                "it somewhere anyway is how a bug becomes a feature nobody can "
                "see the edge of" % last)

# -- AND THE GEOMETRY, run over real shorelines -----------------------------
print()
print("WHERE A HARBOUR LANDS, on %d shores:" % len(SHORES))
print("   %-18s %-22s %s" % ("shore", "root (dry?)", "deck / moorings"))
for name, shore in SHORES.items():
    found = look_for_a_shore(shore)
    if found is None:
        print("   %-18s no harbour found" % name)
        fail.append("no harbour can be placed on %s at all — a shoreline that "
                    "obvious must be able to carry a jetty" % name)
        continue
    rx, rz, angle = found
    dry = not wet(shore, rx, rz)
    deck = deck_is_over_water(shore, rx, rz, math.cos(angle), math.sin(angle))
    ties = moorings(shore, rx, rz, angle)
    afloat = sum(1 for t in ties if t is not None)
    print("   %-18s (%6.1f,%6.1f) %-6s  deck %s, %d/%d boats afloat"
          % (name, rx, rz, "dry" if dry else "WET!",
             "over water" if deck else "ON GRASS", afloat, len(ties)))
    if not dry:
        fail.append("the dock's root is underwater on %s: the net rack, which "
                    "is the one part of a harbour that belongs on land, is in "
                    "the lake" % name)
    if not deck:
        fail.append("the jetty runs out over GRASS on %s" % name)
    if afloat < len(ties):
        fail.append("%d of %d boats have no mooring on water on %s"
                    % (len(ties) - afloat, len(ties), name))

# -- AND THE DOOR ASKS THE GROUND ------------------------------------------
#
# Everything above proves the FINDER is right. It has been right for a while,
# and the dock has still been built on grass three times — because the last
# check before a jetty goes up compared the spot against what `harbour_for`
# said, and passed whenever the two agreed. Two functions agreeing is not
# evidence: a stale memory, or a pond a rain miracle made and that has since
# drained, puts the same wrong answer on both sides.
TOWN = (ROOT / "scripts/world/village.gd").read_text()


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


asks_ground = any("can_carry_a_jetty(" in r for r in body_of(SHOP, "may_stand"))
print()
print("THE RULE FOR WHERE A JETTY MAY STAND asks %s."
      % ("the ground" if asks_ground else "ANOTHER FUNCTION, AND NOTHING ELSE"))
if not asks_ground:
    fail.append("Workshop.may_stand does not walk the deck against the world — "
                "it compares the spot against what the finder said, which "
                "agrees with itself when the finder is wrong, and that is how a "
                "jetty gets built in a meadow")

# AND THE WALK IS THE SAME ONE. A second implementation of "is the deck wet"
# is a second opinion, and the two would drift.
shared = any("_deck_is_over_water(" in r
             for r in body_of(WATERS, "can_carry_a_jetty"))
print("   ...with %s walk the finder uses."
      % ("the same" if shared else "A SECOND, SEPARATE"))
if not shared:
    fail.append("can_carry_a_jetty does not use the finder's own deck walk, so "
                "the door and the search hold two opinions about what counts as "
                "over water, and they will drift")

# AND EVERY WAY IN ASKS IT. This is the one that matters, and the one that was
# missed for three fixes running: a villager raises a workshop through
# `spawn_workshop_at`, and a village restored from a save or a map deals its
# trades back out directly. Only the first was ever guarded, which is exactly
# why destroying the bad dock and letting the town rebuild it put it on water.
ways = []
for path in sorted((ROOT / "scripts").rglob("*.gd")):
    rows_here = code(path.read_text()).split("\n")
    for n, row in enumerate(rows_here):
        if "Workshop.create(" not in row:
            continue
        near = "\n".join(rows_here[max(0, n - 25):n + 3])
        ways.append((path.name, n + 1, "may_stand(" in near))
# AND A RESTORE BRINGS A TOWN UP TO ITS SAVED COUNT rather than adding that
# many on top of what is already there. A village is GENERATED with its own
# workshops and then has its save laid over it, so a save saying "one barn"
# meets a town that already has one — and the ceiling then refused it and
# warned, four times a load, about barns that were standing right there. With
# the duplicates gone, a refusal means a building the town genuinely cannot
# have back, which is worth saying.
restore = body_of(TOWN, "_rebuild")
tops_up = any("how_many(" in r for r in restore)
print()
print("A SAVE RESTORE raises %s."
      % ("what is missing" if tops_up else "ITS WHOLE SAVED COUNT AGAIN"))
if not tops_up:
    fail.append("the save restore raises its full saved count on top of "
                "whatever the town was generated with, so every duplicate is "
                "refused by the ceiling and warned about — a log full of "
                "buildings that are standing right there")

print()
print("WAYS A WORKSHOP GETS RAISED: %d" % len(ways))
for name, line, guarded in ways:
    print("   %-22s line %-6d %s"
          % (name, line, "asks may_stand" if guarded else "ASKS NOTHING"))
    if not guarded:
        fail.append("%s:%d raises a workshop without asking Workshop.may_stand "
                    "— a second way in, unguarded, which is how a dock ends up "
                    "in a meadow while the guarded way puts it on the water"
                    % (name, line))
if len(ways) < 2:
    fail.append("only %d way(s) to raise a workshop were found; the reader has "
                "stopped matching how they are written" % len(ways))

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: the root is ashore, the deck is over water, the boats float, and the "
      "door asks the ground.")
