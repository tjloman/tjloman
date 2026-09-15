#!/usr/bin/env python3
"""WHAT A THROWN THING IS WORTH WHERE IT LANDS.

Until Blow existed a stone hurled through the wall of a house did nothing at
all: the sling, the aftertouch, the arc and the momentum read off a finger all
landed on a world that did not care. This is the arithmetic that fixed it,
checked against the thing it is meant to feel like.

Two questions, and they pull against each other. Throwing things at a town has
to be a REAL way to wreck it, or the mechanic is a toy. And it has to be a SLOW
one, or a god with a quarry never needs a miracle and the whole spellbook is
decoration. So: a house should be a dozen-ish good hits with an ordinary stone
and a couple with a hurled oak, and one stone should hurt a man badly without
reliably killing him outright.

Every number is read off the source.
"""
import argparse
import ast
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BLOW = (ROOT / "scripts/world/blow.gd").read_text()
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()
TREE = (ROOT / "scripts/world/wild_tree.gd").read_text()


def const(text, name, where="blow.gd"):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


PER_MOMENTUM = const(BLOW, "PER_MOMENTUM")
MATTERS_ABOVE = const(BLOW, "MATTERS_ABOVE")
TO_FLESH = const(BLOW, "TO_FLESH")
KARMA_PER_HURT = const(BLOW, "KARMA_PER_HURT")
KARMA_PER_WRECK = const(BLOW, "KARMA_PER_WRECK")
TOP_SPEED = const(HAND, "MAX_THROW_SPEED", "divine_hand.gd")
NEEDS = (ROOT / "scripts/villager/villager_needs.gd").read_text()
FIRE_DEATH = const(NEEDS, "DEATH_BY_FIRE", "villager_needs.gd")
PLAIN_DEATH = const(NEEDS, "DEATH_UNLOOKED_FOR", "villager_needs.gd")
TIMBER = ast.literal_eval(
    re.search(r"const TIMBER: Array\[int\] = (\[[^\]]*\])", TREE).group(1))

# What a village raises, and what it is worth in full. Read off each building
# rather than listed here, so a change to a building's toughness shows up in
# this table without anybody remembering to come and edit it.
#
# THE GROUP NAME COMES OUT OF Affords, not out of a string in this file. It was
# a string in this file, and the day the six burnable buildings moved from
# `add_to_group("burnable")` to `add_to_group(Affords.BURNABLE)` this tool
# quietly found no buildings at all and died on the next line. A second copy of
# a vocabulary is a vocabulary that drifts, which is the whole reason
# scripts/affords.gd exists.
AFFORDS = (ROOT / "scripts/affords.gd").read_text()
BURNABLE = re.search(r'^const BURNABLE := "(\w+)"', AFFORDS, re.M).group(1)
TARGETS = []
for path in sorted((ROOT / "scripts/world").glob("*.gd")):
    src = path.read_text()
    m = re.search(r"^const MOST_HEALTH := ([0-9.]+)", src, re.M)
    joined = ("add_to_group(Affords.BURNABLE)" in src
              or ('add_to_group("%s")' % BURNABLE) in src)
    if m and joined:
        TARGETS.append((path.stem, float(m.group(1))))
if not TARGETS:
    sys.exit("no burnable buildings found — has the Affords vocabulary moved?")
TARGETS.append(("a villager", 100.0))

# A load of stone weighs what its count says — see ResourceItem.refresh_bundle,
# which is the thing that turns a boulder into a siege weapon rather than a
# large-looking pebble.
RES = (ROOT / "scripts/world/resource_item.gd").read_text()
HEFT_BARE = const(RES, "HEFT_BARE", "resource_item.gd")
HEFT_EACH = const(RES, "HEFT_EACH", "resource_item.gd")
MOST_IN_A_BUNDLE = const(RES, "MOST_IN_A_BUNDLE", "resource_item.gd")
PRISED = const((ROOT / "scripts/world/rock_deposit.gd").read_text(),
               "STONE_PER_BOULDER", "rock_deposit.gd")


def heft(count):
    return HEFT_BARE + max(count - 1.0, 0.0) * HEFT_EACH


# The things a hand can pick up and hurl, and what they weigh.
THROWN = [("a loaf or a fish", 1.0), ("one stone or a log", heft(1)),
          ("a corpse", 4.0),
          ("a boulder, %d stone" % PRISED, heft(PRISED)),
          ("an armful, %d stone" % MOST_IN_A_BUNDLE, heft(MOST_IN_A_BUNDLE))]
# A tree's mass is its timber, per WildTree._land.
for size in (1, 5, 10):
    THROWN.append(("a tree, size %d" % size, 2.0 + float(TIMBER[size - 1]) * 0.12))


def blow(mass, speed):
    return speed * max(mass, 0.2) * PER_MOMENTUM


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--speed", type=float, default=TOP_SPEED * 0.55,
                    help="throw speed; the default is a solid flick, not a record")
    args = ap.parse_args()
    speed = args.speed

    print("read off the source: PER_MOMENTUM %.2f, TO_FLESH %.2f, "
          "a throw counts above %.0f m/s, the hand caps at %.0f m/s\n"
          % (PER_MOMENTUM, TO_FLESH, MATTERS_ABOVE, TOP_SPEED))
    print("HITS TO DESTROY, thrown at %.0f m/s\n" % speed)

    names = [n for n, _ in TARGETS]
    print("%-18s %s" % ("", "".join("%>13s".replace(">", "") % n[:12] for n in names)))
    bad = []
    for what, mass in THROWN:
        row = ""
        for name, most in TARGETS:
            share = TO_FLESH if name == "a villager" else (1.0 - TO_FLESH)
            per = blow(mass, speed) * share
            hits = most / per if per > 0 else 9e9
            row += "%13s" % ("%.0f" % hits if hits >= 1 else "1")
        print("%-18s %s" % (what, row))

    # THE TWO THINGS THIS HAS TO FEEL LIKE.
    stone = blow(2.0, speed)
    house = next(m for n, m in TARGETS if n == "house")
    to_house = house / (stone * (1.0 - TO_FLESH))
    to_man = 100.0 / (stone * TO_FLESH)
    print("\nA STONE AT A HOUSE: %.0f hits." % to_house)
    if not 6.0 <= to_house <= 24.0:
        bad.append("a stone takes %.0f hits to bring a house down — wanted 6..24"
                   % to_house)
    print("A STONE AT A MAN:   %.1f hits." % to_man)
    if to_man < 1.0:
        bad.append("one stone kills a man outright (%.1f hits); a thrown rock "
                   "should hurt badly and not be an execution" % to_man)
    if to_man > 6.0:
        bad.append("a man shrugs off %.0f stones; that is not a blow" % to_man)

    oak = blow(2.0 + float(TIMBER[9]) * 0.12, speed)
    print("A FULL-GROWN TREE AT A HOUSE: %.1f hits."
          % (house / (oak * (1.0 - TO_FLESH))))
    rock = blow(heft(PRISED), speed)
    to_house_by_rock = house / (rock * (1.0 - TO_FLESH))
    print("A BOULDER AT A HOUSE: %.1f hits." % to_house_by_rock)
    # METHODICALLY. A boulder has to be a real siege weapon and still take
    # several goes: one-shotting a house makes the vein a delete button, and
    # ten makes it a chore nobody will do twice.
    if not 2.0 <= to_house_by_rock <= 5.0:
        bad.append("a boulder takes %.1f throws to fell a house — wanted 2..5, "
                   "which is methodical rather than either a delete button or "
                   "a chore" % to_house_by_rock)

    # WHAT IT COSTS, against the scale already in VillagerNeeds. Charged on the
    # damage actually LANDED, which for a building is the share that was not
    # spent on the people in it.
    per_stone = stone * (1.0 - TO_FLESH) * KARMA_PER_HURT
    whole_house = per_stone * to_house + KARMA_PER_WRECK
    print("\nWHAT IT COSTS. A stone landing on a house: %.2f alignment."
          "\nPulling the whole house down, all %.0f throws of it: %.1f."
          "\nFor scale, VillagerNeeds charges %.1f for a death by fire and "
          "%.1f for one\nnobody caused — and a death this throw causes is "
          "charged AGAIN on top of\nthe above, which is how a rock that takes "
          "a roof off is one price and a\nrock that takes a roof off and "
          "kills the family under it is two."
          % (per_stone, to_house, whole_house, FIRE_DEATH, PLAIN_DEATH))

    # PELTING A WALL IS VANDALISM; PULLING THE HOUSE DOWN IS THE DEED. If most
    # of the cost sits in the chipping rather than the wrecking, a god is being
    # judged for throwing rather than for what the throwing did.
    if abs(per_stone * to_house) > abs(KARMA_PER_WRECK):
        bad.append("more of the cost of a house is in the chipping (%.1f) than "
                   "in the wrecking (%.1f)" % (per_stone * to_house, KARMA_PER_WRECK))
    if abs(whole_house) < abs(FIRE_DEATH):
        bad.append("pulling a family's house down (%.1f) costs less than one "
                   "death by fire (%.1f)" % (whole_house, FIRE_DEATH))
    if abs(whole_house) > abs(FIRE_DEATH) * 8.0:
        bad.append("pulling one house down (%.1f) costs more than eight deaths "
                   "by fire; that is not a scale, it is a wall" % whole_house)

    if bad:
        print("\nFAIL:")
        for line in bad:
            print("  " + line)
        return 1
    print("\nOK: a town can be wrecked by hand, and slowly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
