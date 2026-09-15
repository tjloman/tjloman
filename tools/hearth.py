#!/usr/bin/env python3
"""HOW LONG YOU HAVE TO HOLD THE FIRE AGAINST A THING.

A ball of fire has always been a thing you hold -- conjured into the grip,
carried around, thrown -- and for all that time it was inert in the hand. It
burns now, at what it is near, and that turns the cheapest miracle in the
spellbook into a tool: a furnace on a hearth you can put wherever you need it.

Which makes ONE number load-bearing in a way it was not before. Heat goes in at
HEARTH_HEAT every HEARTH_EVERY seconds while Kindling.COOLING runs the whole
time in between, so the rate that matters is the DIFFERENCE, and if that ever
goes negative then holding a fireball against a wall COOLS THE WALL -- silently,
with every constant still looking sensible, exactly the way HEAT_FROM_NEXT_DOOR
once quietly stopped fire crossing a lane.

So: the dwell ladder, off the shipped numbers, and a floor and a ceiling on it.
A timber house should be a few seconds of deliberate holding. The nest should be
a commitment. Neither should be instant, because a hearth that lights on contact
is not a hearth, it is a match.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def const(name, relpath):
    text = (ROOT / relpath).read_text()
    m = re.search(r"^const %s\s*:?=\s*([0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, relpath))
    return float(m.group(1))


BALL = "scripts/miracles/fireball.gd"
KIND = "scripts/world/kindling.gd"

HEAT = const("HEARTH_HEAT", BALL)
EVERY = const("HEARTH_EVERY", BALL)
REACH = const("HEARTH_REACH", BALL)
COOLING = const("COOLING", KIND)
SPREAD_REACH = const("SPREAD_REACH", KIND)
BLAZE = const("HEAT_OF_A_BLAZE", KIND)

# What a village raises, and what it is made of. The same reading kindle.py
# takes, kept short here: this tool is about the dwell, not the materials.
MADE_OF = [
    ("a field of dry crops", "TINDER"),
    ("a house", "TIMBER"),
    ("a workshop", "TIMBER"),
    ("a granary", "STORES"),
    ("the school", "STONE"),
    ("the creature's nest", "MENHIR"),
]

gross = HEAT / EVERY
net = gross - COOLING

print("A HELD BALL gives %.0f heat a second (%.0f every %.2fs); a warmed thing"
      % (gross, HEAT, EVERY))
print("   sheds %.0f a second. The rate that counts is %.0f." % (COOLING, net))
print("   One fireball core, for scale, is %.0f heat delivered at once." % BLAZE)
print()

fail = []
if net <= 0.0:
    fail.append("a held ball delivers %.0f/s against %.0f/s of cooling: holding "
                "fire against a wall now COOLS THE WALL" % (gross, COOLING))
    net = float("nan")

print("HOLD IT AGAINST... until it catches:")
dwells = {}
for label, stuff in MADE_OF:
    temper = const("TEMPER_" + stuff, KIND)
    seconds = temper / net if net > 0 else float("inf")
    dwells[stuff] = seconds
    print("   %-22s %5.1fs   (%s, %.0f)" % (label, seconds, stuff.lower(), temper))

print()
print("AND THE REACH is %.1fm -- an arm, against the %.0fm a burning building"
      % (REACH, SPREAD_REACH))
print("   reaches over to its neighbour.")

if net > 0:
    # A HEARTH, NOT A MATCH. Contact-lighting would make the held ball strictly
    # better than throwing it, and there would be no reason to ever let go.
    if dwells["TIMBER"] < 2.0:
        fail.append("a timber house catches in %.1fs of holding -- that is a "
                    "match, not a hearth" % dwells["TIMBER"])
    # ...AND NOT A CHORE EITHER.
    if dwells["TIMBER"] > 8.0:
        fail.append("a timber house takes %.1fs of standing still to light: "
                    "nobody will ever do this twice" % dwells["TIMBER"])
    # The nest is the stoutest thing in the game and should be a siege you can
    # actually commit to, rather than one you give up on.
    if dwells["MENHIR"] > 40.0:
        fail.append("the nest takes %.0fs of unbroken holding -- past the point "
                    "where a player believes it is working" % dwells["MENHIR"])

# An arm's reach, not a neighbourhood. At spread range, standing in a village
# square with a ball in hand would warm the whole square at once.
if REACH >= SPREAD_REACH:
    fail.append("the hearth reaches %.1fm, as far as a burning building reaches "
                "its neighbour: holding one in a square warms the square"
                % REACH)

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: a hearth is a dwell, not a touch, and the nest is a siege you finish.")
