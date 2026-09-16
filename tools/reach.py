#!/usr/bin/env python3
"""How much of the world a god may actually work in, measured.

MiracleReach put a rule on the game that had never been there: you may only
WORK on ground you hold. That is the right rule and it is also the kind of rule
that quietly makes a game unplayable -- if the circles are too small the first
heathen village can never be converted, and the run is dead with no error
message anywhere.

So this walks the numbers that are actually shipped, out of the actual files,
and asserts four things.

  * THE BEAST IS THE BRIDGE. Casting at the creature's own feet must always
    work, at every age, awake or asleep. It is the only reach that travels, and
    if it can ever be zero the player can be stranded.

  * THE FIRST CONVERSION IS POSSIBLE. Rival villages are founded at least
    VILLAGE_MIN_CELL_DIST chunks out, which is further than any circle you
    start with. The route has to be "walk the animal there", and the circle it
    carries has to cover enough of a town to be worth casting into.

  * THE RING YOU SEE IS THE RING THAT WORKS -- GRACE stays a hair.

  * AND THE GATE IS ON REACHING OUT, NOT ON WHERE IT LANDS. This one is here
    because the first version got it backwards, and the bug was not a crash: a
    working hurled across a valley came back "beyond your reach by 88 metres",
    so the best thing in the game read as a punishment for throwing well.

    The circle bounds where you may STAND AND ACT -- casting AND grabbing, since
    a god who cannot call down a fire on the far mountain but can pull its trees
    up by the roots has not been limited at all. What is already in your hand
    goes wherever you throw it, and goes off where it lands.

Run it after touching any of: MiracleReach's constants, Village.MIN/MAX_INFLUENCE,
Village.STARTING_SOULS, or WorldGen's village spacing.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def consts(relpath):
    """Every `const NAME := <number>` in a script, as {name: float}."""
    text = (ROOT / relpath).read_text()
    found = {}
    for name, value in re.findall(
            r"^const ([A-Z_][A-Z0-9_]*)\s*:=\s*(-?[0-9]+\.?[0-9]*)\s*(?:#.*)?$",
            text, re.M):
        found[name] = float(value)
    return found


REACH = consts("scripts/miracles/miracle_reach.gd")
TOWN = consts("scripts/world/village.gd")
WORLD = consts("scripts/world/world_gen.gd")

WHELP = REACH["AT_A_WHELP"]
GIANT = REACH["AT_A_GIANT"]
ASLEEP = REACH["WHILE_ASLEEP"]
GRACE = REACH["GRACE"]
MIN_TOWN = TOWN["MIN_INFLUENCE"]
MAX_TOWN = TOWN["MAX_INFLUENCE"]
SOULS = int(TOWN["STARTING_SOULS"])
CHUNK = WORLD["CHUNK_SIZE"]
RIVALS_FROM = int(WORLD["VILLAGE_MIN_CELL_DIST"])


def town_reach(pop):
    """Village._update_influence, transcribed."""
    return max(MIN_TOWN, min(10.0 + pop * 1.8, MAX_TOWN))


def beast_reach(growth, asleep=False):
    """MiracleReach.beast_reach, transcribed."""
    span = WHELP + (GIANT - WHELP) * max(0.0, min(growth, 1.0))
    return span * ASLEEP if asleep else span


def chunks(radius):
    return math.pi * radius * radius / (CHUNK * CHUNK)


fail = []

print("WHAT THE CREATURE CARRIES, by age:")
row = []
for g in (0.0, 0.25, 0.5, 0.75, 1.0):
    row.append("%3d%%:%4.0fm" % (g * 100, beast_reach(g)))
print("   " + "  ".join(row))
print("   asleep, grown: %.0fm" % beast_reach(1.0, asleep=True))

print()
print("WHAT A TOWN HOLDS, by souls:")
row = []
for pop in (10, 25, SOULS, 100):
    row.append("%3d:%4.0fm" % (pop, town_reach(pop)))
print("   " + "  ".join(row))

home = town_reach(SOULS)
print()
print("AT THE FIRST DAWN you hold %.0fm at home and %.0fm around a whelp"
      % (home, beast_reach(0.0)))
print("   -- about %.1f chunks of world, out of an endless one." % chunks(home))

rivals_at = RIVALS_FROM * CHUNK
print()
print("THE NEAREST RIVAL is at least %.0fm off, and your home circle ends at"
      % rivals_at)
print("   %.0fm. The gap is %.0fm of ground you must WALK THE ANIMAL across."
      % (home, rivals_at - home))

# -- THE BEAST IS THE BRIDGE ------------------------------------------------
# A miracle at the creature's own feet is distance zero, so it passes for any
# positive span. What must never happen is a span that rounds to nothing.
worst = beast_reach(0.0, asleep=True)
if worst <= 1.0:
    fail.append("a creature carries only %.2fm at its worst -- a god whose "
                "only reach is a sleeping whelp is stranded" % worst)

# -- THE FIRST CONVERSION IS POSSIBLE ---------------------------------------
# Stand the beast in the middle of a rival town and the circle it carries has
# to cover a real part of that town, or casting into it converts nobody.
rival_pop = SOULS * 2 // 3
rival = town_reach(rival_pop)
covered = min(1.0, (beast_reach(1.0) ** 2) / (rival ** 2))
print()
print("A RIVAL TOWN of %d souls spreads %.0fm. A grown beast standing in the"
      % (rival_pop, rival))
print("   middle of it holds %.0fm -- %.0f%% of its ground." % (beast_reach(1.0),
                                                               covered * 100))
if covered < 0.25:
    fail.append("a grown creature covers only %.0f%% of a rival town it is "
                "standing in the middle of" % (covered * 100))

# -- THE RING YOU SEE IS THE RING THAT WORKS --------------------------------
# GRACE is slack against rounding, not a second rule. On the smallest circle
# in the game it must still be invisible.
slop = GRACE / min(MIN_TOWN, beast_reach(0.0, asleep=True))
print()
print("GRACE is %.1fm -- %.0f%% of the smallest circle in the game."
      % (GRACE, slop * 100))
if slop > 0.15:
    fail.append("GRACE is %.0f%% of the smallest circle: the ring drawn on the "
                "grass and the ring that works have visibly parted company"
                % (slop * 100))

# -- THE GATE IS ON THE DRAWING, NOT THE LANDING -----------------------------
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()
BOOK = (ROOT / "scripts/miracles/miracle_manager.gd").read_text()
BALL = (ROOT / "scripts/miracles/fireball.gd").read_text()


def body_of(text, name):
    """One function's body, by indentation."""
    head = "func %s(" % name
    if head not in text:
        return ""
    rest = text[text.index(head):]
    out = []
    for line in rest.split("\n")[1:]:
        if line and not line.startswith(("\t", " ")):
            break
        out.append(line)
    return "\n".join(out)


print()
print("WHERE THE RULE IS ENFORCED:")
for where, text, name, must in [
        ("divine_hand.gd", HAND, "_open_casting", True),
        ("divine_hand.gd", HAND, "_on_grab", True),
        ("miracle_manager.gd", BOOK, "cast_runes", True),
        ("miracle_manager.gd", BOOK, "resolve", False),
        ("fireball.gd", BALL, "_go_off", False),
        ("fireball.gd", BALL, "_hearth", False)]:
    body = body_of(text, name)
    asks = "MiracleReach.reaches" in body
    want = "asks" if must else "does not ask"
    print("   %-20s %-14s %s" % (where, name, "asks" if asks else "does not ask"))
    if must and not asks:
        fail.append("%s.%s does not consult MiracleReach: there is a door into "
                    "reaching out that skips the rule entirely" % (where, name))
    if not must and asks:
        fail.append("%s.%s gates on the reach. That is the LANDING, not the "
                    "drawing -- it is the mistake that made every long throw "
                    "come back \"beyond your reach by 88 metres\"" % (where, name))

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: the beast is always a bridge, and a rival town is reachable on foot.")
