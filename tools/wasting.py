#!/usr/bin/env python3
"""HOW MUCH OF A MORNING CAN BE TAKEN BACK IN AN AFTERNOON.

Wasting is the visible price of cruelty: a creature taken past bearing does not
merely stop growing, it comes off, and a player is meant to be able to see from
across the valley what they have made. That is worth keeping.

What it was ALSO doing is taking the afternoon's work back while the player was
busy somewhere else. At its worst it sheds 0.45 of a stature-step a second --
twenty-seven a minute, sixteen hundred an hour -- and a young creature has only
a few thousand steps to its name. An hour of errands and an empty belly and the
morning was gone.

    "With all the running and things the creature does, it's hard to get him
     above size 1. I feel like shrinking needs a limiter per session, so he
     can't shrink more than a certain percent in a single play session -- no
     matter what happens."

So there is a floor, and this file is what says it holds. Four claims:

  ONE DOOR. Stature is lost in exactly one place. A cap on a door only caps
  anything if it is the only door, so the check is that nothing else anywhere
  in the scripts assigns `stature` downward.

  THE FLOOR IS TAKEN OFF THE HIGH-WATER MARK, not off what the creature was
  when the game opened. Grow for an hour and the floor comes up with you, so an
  hour's work cannot be taken back to where it started.

  NOTHING OF IT IS SAVED. A fresh allowance each sitting is the whole idea; a
  saved one would be a lifetime cap on wasting and would quietly retire the
  mechanism instead of pacing it.

  AND THE BOOKS MATCH THE BEAST. Shrinking used to write `stature` and never
  touch the scale, so a wasted creature was the same size on the grass until
  the next mouthful of food happened to put the two back in step.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WELFARE = (ROOT / "scripts/creature/creature_welfare.gd").read_text()
CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()


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
share = number(WELFARE, "MOST_LOST_IN_A_SITTING")
rate = number(WELFARE, "SHRINK_RATE")
shrink_at = number(WELFARE, "SHRINK_AT")
waste = body_of(WELFARE, "waste")
grow = body_of(CREATURE, "_grow_by")

# -- ONE DOOR ----------------------------------------------------------------
#
# Every line in the scripts that moves `stature` anywhere but up. `_grow_by` is
# the door; a second assignment somewhere else is a hole in the floor, however
# innocent it looks. Two are allowed and both are about loading rather than
# living: creature_record putting a saved creature back at the size it was, and
# the `growth` property's setter, which is the same thing for saves written
# before stature existed.
def property_rows(text, name):
    """The rows of a `var x:` property block -- its getter and setter."""
    src = text.split("\n")
    for i, row in enumerate(src):
        if row.startswith("var %s:" % name):
            out = []
            for later in src[i + 1:]:
                if later and not later.startswith(("\t", " ")):
                    break
                out.append(later.split("#")[0].strip())
            return [r for r in out if r]
    return []


setter = property_rows(CREATURE, "growth")
doors = []
for path in sorted(ROOT.glob("scripts/**/*.gd")):
    for n, row in enumerate(path.read_text().split("\n"), 1):
        bare = row.split("#")[0]
        if not re.search(r"(^|[^._\w])stature\s*(=|-=)", bare):
            continue
        if "+=" in bare or "minf(stature +" in bare or "+ gained" in bare:
            continue                        # growing, or a smoke test that grows
        if path.name == "creature_record.gd":
            continue                        # loading a save, not losing size
        doors.append(("%s:%d" % (path.relative_to(ROOT), n), bare.strip()))
print("WHERE STATURE CAN GO DOWN:")
allowed = [r.strip() for r in grow] + setter
for where, row in doors:
    print("   %-38s %-46s %s"
          % (where, row, "the door" if row in allowed else "<-- ANOTHER DOOR"))
if not grow:
    fail.append("Creature._grow_by is gone, so there is no door to cap")
for where, row in doors:
    if row not in allowed:
        fail.append("stature is written at %s, outside _grow_by, so the "
                    "per-sitting floor caps one of several doors and caps "
                    "nothing" % where)

# A creature's `growth` can be assigned instead, which goes through that setter
# and lands wherever it likes. Loading a save is the only caller there may be.
# (Farms have a `growth` of their own and it is a different thing entirely.)
for path in sorted(ROOT.glob("scripts/**/*.gd")):
    for n, row in enumerate(path.read_text().split("\n"), 1):
        bare = row.split("#")[0]
        found = re.search(r"(\w+)\.growth\s*=[^=]", bare)
        if not found or found.group(1) in ["field", "farm", "crop"]:
            continue
        if path.name == "creature_record.gd":
            continue
        fail.append("%s:%d assigns a creature's `growth` outright, which sets "
                    "stature through the property setter and walks straight "
                    "past the sitting's floor" % (path.relative_to(ROOT), n))

# -- THE FLOOR, AND WHAT IT IS MEASURED FROM ---------------------------------
marks = any("_high_water = maxf" in r for r in waste)
off_mark = any("_high_water * (1.0 - MOST_LOST_IN_A_SITTING)" in r for r in waste)
caps = any("minf(wasting()" in r for r in waste)
print()
print("THE ALLOWANCE IS MEASURED FROM %s."
      % ("the biggest it has been this sitting" if marks and off_mark
         else "SOMETHING THAT IS NOT A HIGH-WATER MARK"))
if not marks or not off_mark:
    fail.append("the floor is not taken off the largest stature seen this "
                "sitting, so an hour of growing can still be taken back to "
                "wherever the creature started the day")
if not caps:
    fail.append("waste() does not hold this tick's loss down to what is left "
                "above the floor, so the floor is a number nothing reads")

# -- NOTHING OF IT IS SAVED --------------------------------------------------
saved = any("_high_water" in r for r in
            body_of(WELFARE, "to_dict") + body_of(WELFARE, "from_dict"))
print("THE MARK IS %s." % ("forgotten when the game closes" if not saved
                           else "WRITTEN TO THE SAVE FILE"))
if saved:
    fail.append("the high-water mark is saved, which turns a per-sitting "
                "allowance into a lifetime one and retires wasting altogether")

# -- THE BOOKS MATCH THE BEAST -----------------------------------------------
redraws = any("_apply_stature()" in r for r in grow)
print("A SHRUNK CREATURE %s."
      % ("is redrawn at its new size" if redraws
         else "IS STILL DRAWN AT ITS OLD SIZE"))
if not redraws:
    fail.append("_grow_by does not re-apply the scale, so wasting moves the "
                "number and leaves the creature exactly as big as it was")

# -- WHAT A BAD DAY COSTS ----------------------------------------------------
#
# The worst case the game can produce, run minute by minute: standing pinned at
# -1 (starved, spent and beaten, the state the old bug parked every creature
# in), against a creature of the size the report is about.
def sitting(start, hours, share, rate, shrink_at, capped):
    """Stature left after `hours` of the worst treatment in the game."""
    stature, mark = float(start), float(start)
    step = 1.0                                  # a second at a time
    for _ in range(int(hours * 3600 / step)):
        mark = max(mark, stature)
        per_second = (shrink_at + 1.0) / (1.0 + shrink_at) * rate
        least = max(mark * (1.0 - share), 1.0) if capped else 1.0
        stature = max(stature - per_second * step, least)
    return stature


def size(stature):
    """What a player actually sees: size goes as the square root of stature."""
    return (stature / 65535.0) ** 0.5


if None in (share, rate, shrink_at):
    fail.append("MOST_LOST_IN_A_SITTING, SHRINK_RATE or SHRINK_AT is gone")
else:
    print()
    print("A CREATURE AT STATURE 4000 (about a quarter grown), TORTURED:")
    print("   %-9s %-22s %s" % ("", "before", "with the floor"))
    for hours in [1, 3, 8]:
        was = sitting(4000, hours, share, rate, shrink_at, False)
        now = sitting(4000, hours, share, rate, shrink_at, True)
        print("   %-9s %6.0f  (%3d%% of size)   %6.0f  (%3d%% of size)"
              % ("%d hour%s" % (hours, "" if hours == 1 else "s"),
                 was, round(size(was) / size(4000) * 100),
                 now, round(size(now) / size(4000) * 100)))
    worst = sitting(4000, 8, share, rate, shrink_at, True)
    print("   a whole day of it costs %d%% of its size, and no more, however "
          "long it goes on." % round(100 - size(worst) / size(4000) * 100))
    # Over weeks, though, it must still take a creature apart -- the cap is on
    # the sitting, not on the mechanism.
    stature, days = 4000.0, 0
    while stature > 400.0 and days < 400:
        stature = sitting(stature, 3, share, rate, shrink_at, True)
        days += 1
    print("   kept up at three hours a sitting, it is a tenth of its stature "
          "after %d sittings -- so cruelty still tells." % days)
    if days > 60:
        fail.append("wasting no longer takes a creature apart in any playable "
                    "number of sittings (%d), so the cap has retired the "
                    "mechanism instead of pacing it" % days)
    if share is not None and share >= 0.5:
        fail.append("half a creature or more can still come off in one "
                    "sitting, which is the thing that was asked about")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: a sitting can cost a creature %d%% of its stature and no more, "
      "and the beast on the grass is the size the books say."
      % round((share or 0) * 100))
