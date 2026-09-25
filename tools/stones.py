#!/usr/bin/env python3
"""WHAT A ROCK IS, NOW THAT IT IS A ROCK.

A rock used to stop being one the moment you touched it: the hand `prise`d a
bundle of resource out of it and the rock itself vanished, so there was no
carrying a stone about, no dropping one on a roof, and "I was smacking houses
with stones and it wasn't doing anything" was the honest outcome — what you
were throwing was a crate worth fifteen.

Now the hand lifts the rock, and the rock climbs the same ladder a tree does:
WildTree.TIMBER, the running sum of the Fibonacci sequence, one to a hundred
and forty-three. Three claims here are worth arithmetic rather than assertion.

  1. THE LADDER IS THE TREE'S LADDER. It has to be written out twice (Godot
     refuses a constant that depends on another class's constant when the two
     can reach each other), so the day the two disagree is the day this fails.

  2. BREAKING A ROCK IS A GAIN, AND IT IS BOUNDED. Two of rung n-1 are worth
     more than one of rung n, everywhere above the bottom of the ladder — which
     is what makes cracking stones the one way to end up with more stone than
     the map was made with. It must not be unbounded, and it is not: the total
     you can get out of one rock by pulverising it is printed, with what it
     costs in taps.

  3. A HUT-SIZED ROCK HITS LIKE ONE. "Throwing a 143 stone rock into a hut
     should deal more than half the hut's damage in a single throw" — and
     stop short of being a one-shot at an ordinary throw, or a god with one
     boulder never needs a miracle again.

Every number is read off the source.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ROCK = (ROOT / "scripts/world/rock_deposit.gd").read_text()
TREE = (ROOT / "scripts/world/wild_tree.gd").read_text()
BLOW = (ROOT / "scripts/world/blow.gd").read_text()
HOUSE = (ROOT / "scripts/world/house.gd").read_text()
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()
WATCH = (ROOT / "scripts/world/village_watch.gd").read_text()
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()
VILLAGE = (ROOT / "scripts/world/village.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()
BODY = (ROOT / "scripts/creature/creature_body.gd").read_text()

## A THROW A PERSON ACTUALLY MAKES, against the ceiling the hand allows. The
## ceiling is a perfect flick; this is a throw.
ORDINARY_THROW = 20.0


def bare(text):
    """Statements only. A comment that says the right thing is not a fix."""
    out = []
    for line in text.splitlines():
        stripped = line.split("#")[0].rstrip()
        if stripped:
            out.append(stripped)
    return "\n".join(out)


def body(text, name):
    """One function's statements, up to the next top-level `func`."""
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def const(text, name, where):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


def int_list(text, name, where):
    m = re.search(r"^const %s.*?=\s*\[([0-9,\s]+)\]" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return [int(v) for v in m.group(1).split(",")]


WORTH = int_list(ROCK, "WORTH", "rock_deposit.gd")
TIMBER = int_list(TREE, "TIMBER", "wild_tree.gd")
NAMES = re.search(r'^const NAMES.*?=\s*\[(.*?)\]', ROCK, re.M | re.S).group(1)
NAMES = re.findall(r'"([a-z]+)"', NAMES)

GIRTH = const(ROCK, "GIRTH", "rock_deposit.gd")
HEFT_BARE = const(ROCK, "HEFT_BARE", "rock_deposit.gd")
HEFT_PER_STONE = const(ROCK, "HEFT_PER_STONE", "rock_deposit.gd")
CRACKS_PER_RUNG = const(ROCK, "CRACKS_PER_RUNG", "rock_deposit.gd")
TOTAL_STONE = const(ROCK, "TOTAL_STONE", "rock_deposit.gd")

PER_MOMENTUM = const(BLOW, "PER_MOMENTUM", "blow.gd")
TO_FLESH = const(BLOW, "TO_FLESH", "blow.gd")
MOMENTUM_MATTERS = const(BLOW, "MOMENTUM_MATTERS", "blow.gd")
MOST_HEALTH = const(HOUSE, "MOST_HEALTH", "house.gd")
MAX_THROW = const(HAND, "MAX_THROW_SPEED", "divine_hand.gd")

HUT_WIDE = float(re.search(r'Size\.HUT:\s*\{[^}]*"width":\s*([0-9.]+)',
                           HOUSE, re.S).group(1)) if re.search(
    r'Size\.HUT:\s*\{[^}]*"width":\s*([0-9.]+)', HOUSE, re.S) else 2.0


def heft(worth):
    return HEFT_BARE + worth * HEFT_PER_STONE


def across(worth):
    return 2.0 * GIRTH * worth ** (1.0 / 3.0)


def to_building(worth, speed):
    """What one landing takes off a house. See Blow.lands."""
    m = heft(worth)
    if speed * m < MOMENTUM_MATTERS:
        return 0.0
    return speed * m * PER_MOMENTUM * (1.0 - TO_FLESH)


def pulverise(rung):
    """Most stone obtainable out of one rock, and the cracks it costs.

    Breaking gives two of the rung below. Whether to break again is a choice
    per piece, so the best total is the best of (keep it) and (break it).
    """
    if rung == 0:
        return WORTH[0], 0
    keep = WORTH[rung]
    lower, lower_cost = pulverise(rung - 1)
    broken = 2 * lower
    cost = rung * int(CRACKS_PER_RUNG) + 2 * lower_cost
    if broken > keep:
        return broken, cost
    return keep, 0


def ladder(fail):
    print("THE LADDER OF STONE — a rock is worth everything it has been")
    print("  %-10s %6s %8s %7s %9s %9s" % (
        "rung", "stone", "across", "weighs", "a throw", "throws/house"))
    last = -1.0
    for i, worth in enumerate(WORTH):
        hit = to_building(worth, ORDINARY_THROW)
        throws = MOST_HEALTH / hit if hit > 0 else float("inf")
        print("  %-10s %6d %7.2fm %7.1f %9.0f %9.1f" % (
            NAMES[i] if i < len(NAMES) else "?", worth, across(worth),
            heft(worth), hit, throws))
        if hit <= last:
            fail.append("a %s hits no harder than the rung below it — the "
                        "ladder has stopped meaning anything" % NAMES[i])
        last = hit
    print("  %-10s %6d %7.2fm %7s %9s %9s" % (
        "outcrop", int(TOTAL_STONE), across(TOTAL_STONE), "--", "--", "--"))
    print("      (an outcrop is the hill: quarried, never lifted, never thrown)")


def biggest(fail):
    top = WORTH[-1]
    print()
    print("THE BIGGEST ROCK IN THE WORLD, against a hut")
    print("  a hut is %.1fm wide; the top of the ladder is %.2fm across"
          % (HUT_WIDE, across(top)))
    ordinary = to_building(top, ORDINARY_THROW)
    perfect = to_building(top, MAX_THROW)
    print("  at an ordinary throw (%.0f m/s): %.0f of a house's %.0f — %.0f%%"
          % (ORDINARY_THROW, ordinary, MOST_HEALTH, ordinary / MOST_HEALTH * 100.0))
    print("  at the hand's ceiling (%.0f m/s): %.0f — %.0f%%"
          % (MAX_THROW, perfect, perfect / MOST_HEALTH * 100.0))
    if across(top) < HUT_WIDE * 0.75 or across(top) > HUT_WIDE * 1.75:
        fail.append("the biggest rock is %.2fm across against a %.1fm hut — "
                    "it is meant to be roughly the size of one"
                    % (across(top), HUT_WIDE))
    if ordinary <= MOST_HEALTH * 0.5:
        fail.append("a %d-stone rock at an ordinary throw does %.0f%% of a "
                    "house — the whole point of the top of the ladder is that "
                    "it does more than half in one throw"
                    % (top, ordinary / MOST_HEALTH * 100.0))
    if ordinary >= MOST_HEALTH:
        fail.append("a %d-stone rock flattens a house in ONE ordinary throw — "
                    "a god with one boulder never needs a miracle again"
                    % top)
    smallest = to_building(WORTH[0], MAX_THROW)
    throws = MOST_HEALTH / smallest if smallest > 0 else float("inf")
    print("  a %s thrown perfectly still needs %.0f throws to fell that house"
          % (NAMES[0], throws))
    if throws < 4.0:
        fail.append("a %s fells a house in %.0f throws — the bottom of the "
                    "ladder has stopped being the bottom" % (NAMES[0], throws))


def breaking(fail):
    print()
    print("BREAKING ONE OPEN — two of the rung below, and what that is worth")
    print("  %-10s %6s %8s %8s   %s" % (
        "rung", "stone", "halved", "cracks", "gain"))
    for i in range(1, len(WORTH)):
        halves = 2 * WORTH[i - 1]
        gain = halves - WORTH[i]
        note = "+%d" % gain if gain > 0 else ("break even" if gain == 0 else "A LOSS")
        print("  %-10s %6d %8d %8d   %s" % (
            NAMES[i] if i < len(NAMES) else "?", WORTH[i], halves,
            i * int(CRACKS_PER_RUNG), note))
        if halves < WORTH[i]:
            fail.append("breaking a %s LOSES stone — cracking rocks is "
                        "supposed to be the one way to make more of it"
                        % NAMES[i])
    most, cost = pulverise(len(WORTH) - 1)
    print()
    print("  a %s pulverised all the way down yields %d stone, at %d cracks"
          % (NAMES[-1], most, cost))
    print("  — %.1fx its face value, and that is the ceiling: there is no "
          "third rock" % (most / float(WORTH[-1])))
    if most <= WORTH[-1]:
        fail.append("pulverising the biggest rock gains nothing at all")
    if cost < 100:
        fail.append("the whole ladder comes apart in %d taps — it is supposed "
                    "to be paid for with the player's own time" % cost)


def where(fail):
    """WHICH ROCKS TURN UP WHERE, read off the scatter tables."""
    town = int_list(CHUNK, "TOWN_SPREAD", "chunk.gd")
    open_country = int_list(CHUNK, "STONE_SPREAD", "chunk.gd")
    shingle = int_list(CHUNK, "SHINGLE", "chunk.gd")
    great = int_list(CHUNK, "GREAT_STONES", "chunk.gd")
    vein = eval(re.search(r"^const VEIN_CHANCE := (.+)$", CHUNK, re.M).group(1))
    odds = const(CHUNK, "GREAT_STONE_CHANCE", "chunk.gd")
    hills = const(CHUNK, "GREAT_STONE_IN_HILLS", "chunk.gd")
    chunk_m = const(WORLD, "CHUNK_SIZE", "world_gen.gd")

    print()
    print("WHICH ROCKS TURN UP WHERE")
    for label, spread in (("a town", town), ("open country", open_country),
                          ("the waterline", shingle)):
        top = max(spread)
        big = sum(1 for r in spread if r >= 4) / float(len(spread))
        print("  %-14s rungs %d..%d (%s at most, %d stone) — %.0f%% worth carrying"
              % (label, min(spread), top, NAMES[top], WORTH[top], big * 100.0))
    print("  %-14s %d%% of wild rocks, and one per village outright"
          % ("outcrops", round(vein * 100.0)))
    print("  %-14s rungs %s, one roll a chunk" % ("great stones",
          " and ".join(NAMES[r] for r in great)))

    print()
    print("HOW FAR YOU WALK TO FIND A GREAT STONE")
    for label, p in (("ordinary country", odds), ("the rocky hills", hills)):
        per = 1.0 / p
        side = (per * chunk_m * chunk_m) ** 0.5
        print("  %-18s one in %.0f chunks — about a %.0fm square of it"
              % (label, per, side))

    if max(town) > 3:
        fail.append("town ground can grow a %s — a town would have built the "
                    "square round anything that big" % NAMES[max(town)])
    if max(open_country) >= min(great):
        fail.append("open country scatters a %s, which is supposed to be a "
                    "thing you go and FIND, not a thing in every third meadow"
                    % NAMES[max(open_country)])
    if max(open_country) < 4:
        fail.append("nothing above a %s spawns in open country — 'I haven't "
                    "found any megalith, indeed nothing as large as a boulder'"
                    % NAMES[max(open_country)])
    if sorted(great) != [len(WORTH) - 2, len(WORTH) - 1]:
        fail.append("the great stones are not the top two rungs of the ladder")
    if max(shingle) > 2:
        fail.append("shingle is rolled stone — it does not run to a %s"
                    % NAMES[max(shingle)])


def source(fail):
    print()
    print("WHAT THE SOURCE ACTUALLY DOES")

    if WORTH != TIMBER:
        fail.append("RockDeposit.WORTH and WildTree.TIMBER have drifted apart: "
                    "%s vs %s. They are one ladder written twice because Godot "
                    "will not let one be the other." % (WORTH, TIMBER))
    else:
        print("  a rock is worth what a tree is worth ............ yes")

    # The tree hands Blow `2.0 + timber() * 0.12`; a rock must weigh the same
    # per unit of worth, or the two ladders describe different worlds.
    m = re.search(r"([0-9.]+)\s*\+\s*float\(timber\(\)\)\s*\*\s*([0-9.]+)",
                  bare(TREE))
    if m is None:
        fail.append("could not find the tree's own weight line in wild_tree.gd "
                    "— if it moved, nothing is holding a rock's weight to it")
    elif (float(m.group(1)), float(m.group(2))) != (HEFT_BARE, HEFT_PER_STONE):
        fail.append("a rock weighs %.2f + %.2f/stone and a tree weighs "
                    "%.2f + %.2f/timber off the same ladder"
                    % (HEFT_BARE, HEFT_PER_STONE,
                       float(m.group(1)), float(m.group(2))))
    else:
        print("  a rock weighs what a tree of that worth weighs ... yes")

    rock = bare(ROCK)
    if "add_to_group(Affords.QUARRIED if vein else Affords.PICKABLE)" not in rock:
        fail.append("a rock is no longer EITHER lifted or quarried — being "
                    "both, with QUARRIED tested first, is exactly why every "
                    "rock in the world turned into resource when touched")
    else:
        print("  a rock is lifted OR quarried, never both ........ yes")

    if "func _banked" not in rock or "store.add_stone(worth())" not in rock:
        fail.append("a rock no longer turns into stores at a storehouse — "
                    "which is the only place it is supposed to stop being a rock")
    else:
        print("  a storehouse is where it becomes stone .......... yes")

    # IN THE DOUBLE TAP'S OWN BODY, not merely somewhere in the file. A dead
    # function that still says `crack()` is exactly the check that cannot fail:
    # cutting the call site left this passing.
    if "_cracked_a_rock()" not in body(HAND, "_tapped_twice"):
        fail.append("the double tap no longer reaches the rock-cracking rung")
    elif "rock.crack()" not in body(HAND, "_cracked_a_rock"):
        fail.append("the rock-cracking rung no longer cracks anything")
    else:
        print("  a double tap cracks it ......................... yes")

    if "if not rock.vein:" not in bare(WATCH):
        fail.append("quarriers are walking out to chip three stone off pebbles "
                    "again — a village works the hill, not the field")
    else:
        print("  quarriers work outcrops, not field stones ....... yes")

    burden = body(BODY, "burden")
    ready = body(VILLAGE, "_ready")
    quarry = body(VILLAGE, "_raise_quarry")
    if ready.count("_raise_quarry()") != 1:
        fail.append("a village raises its own rock %d times — it is meant to be "
                    "exactly one" % ready.count("_raise_quarry()"))
    elif "quarry.vein = true" not in quarry:
        fail.append("a village's own rock is not an outcrop, so it can be "
                    "picked up and carried off")
    else:
        print("  every village is given exactly one outcrop ..... yes")

    ground = body(WORLD, "village_ground")
    if "_is_village_cell(" not in ground or 'get_nodes_in_group("village")' not in ground:
        # A chunk scatters its stones before the village on that cell exists, so
        # the live-village test alone seeds every town site with megaliths.
        fail.append("WorldGen.village_ground no longer asks BOTH the seed and "
                    "the live villages, so town ground is decided by whichever "
                    "of the two happens to have run first")
    else:
        print("  town ground is known before the town is ........ yes")

    if "thing is RockDeposit" not in burden:
        fail.append("CreatureBody.burden no longer weighs a rock, so a "
                    "fledgling can shoulder a megalith")
    elif "return 0.0" not in burden.split("liftable_whole()")[-1].split("return float(stone")[0]:
        # An outcrop that weighs INF reads as "too heavy to lift" and stops the
        # creature working a vein at all — it does not lift one, it breaks a
        # piece off. See CreatureThrowing._collect.
        fail.append("an outcrop no longer weighs nothing, so no creature can "
                    "work a vein: can_lift refuses it before it ever gets there")
    else:
        print("  a fledgling cannot lift a megalith .............. yes")
        print("  a beast can still break a piece off the hill .... yes")

    # THE MOONWALK. A rock rests on layer 1 with the hills; the creature
    # collides with layer 1; so a rock carried on layer 1 is a wall that walks
    # with whoever holds it, and a small beast that caught a megalith was
    # shoved backwards out of its own arms, every frame, for fifty metres.
    if "collision_layer = 0" not in body(ROCK, "pick_up"):
        fail.append("a carried rock stays on the ground layer, so whoever holds "
                    "it is shoved out of it every frame — the moonwalk")
    elif 'set_deferred("collision_layer", 1)' not in body(ROCK, "_on_sleep_changed"):
        fail.append("a rock that has been carried never goes back on the ground "
                    "layer, so it is a ghost everybody walks through")
    else:
        print("  a carried rock is off the ground layer .......... yes")
    CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()
    THROWING = (ROOT / "scripts/creature/creature_throwing.gd").read_text()
    # `pick_up` has to be ASKED, rigid body or not. It was an `elif` after the
    # freeze in all three lifters, so no rigid body's pick_up ever ran — which
    # is also why a fishing boat went on sailing in the god's hand.
    for who, where, fn in (("the hand", HAND, "_on_grab"),
                           ("the creature", CREATURE, "_pick_up_thing"),
                           ("a gathering creature", THROWING, "_collect")):
        seen = body(where, fn)
        if not seen:
            fail.append("could not read %s's %s — if it moved, this is not "
                        "checking anything" % (who, fn))
        elif re.search(r"elif \w+\.has_method\(\"pick_up\"\)", seen):
            fail.append("%s only tells a thing it has been picked up when it "
                        "is NOT a rigid body — no rock, and no boat, ever hears "
                        "it" % who)
    print("  every lifter tells a rigid body it is lifted .... yes")
    if "can_lift(thrown)" not in body(CREATURE, "_try_catch_throw"):
        fail.append("a whelp can catch a megalith")
    else:
        print("  a whelp does not catch a hut ................... yes")

    if len(NAMES) != len(WORTH):
        fail.append("%d rungs and %d names" % (len(WORTH), len(NAMES)))


def main():
    fail = []
    ladder(fail)
    biggest(fail)
    breaking(fail)
    where(fail)
    source(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
