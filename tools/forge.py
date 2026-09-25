#!/usr/bin/env python3
"""THE FURNACE IS NOT A BUILDING.

There is no furnace object, no recipe and no build menu. A hole in the ground
is a fireball crater; rocks roll into it because rocks roll; trees lie on top
because a thrown tree lies where it stops; and a burning tree resting against a
stone puts heat into the stone. Everything above already existed. The only new
thing is that stone now HOLDS heat — and that a stone which has taken enough of
it catches fire itself, which is what closes the loop.

HEAT IS MEASURED IN SECONDS, and that one decision is the whole mechanic. A
rock soaks a second a second and sheds a second a second, so five seconds in a
flame is five seconds of glow. It is full when it has taken as many seconds as
it has stone — 143 for a megalith — and a full rock burns for exactly that long,
because burning IS the shedding.

Four claims worth arithmetic rather than assertion:

  1. ONE FLAME FILLS A ROCK IN AS MANY SECONDS AS IT HAS STONE. Not roughly:
     the fire reports in beats and the rock sheds continuously, and if the two
     were not held to each other a rock beside a bonfire would cool.

  2. A LONE ROCK BURNS OUT. It has to, or the world fills up with eternal
     fires nobody lit on purpose.

  3. TWO ROCKS IN REACH OF EACH OTHER DO NOT. That is the design, stated:
     "putting a handful of rocks into a pit, then starting them afire with a
     couple large trees means the rocks will actively reignite one another
     continuously looping the fire. That is how it should be."

  4. RAIN SHORTENS A BURN AND NEVER ENDS ONE. Only water the rock is IN does
     that.

Every number is read off the source.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ROCK = (ROOT / "scripts/world/rock_deposit.gd").read_text()
TREE = (ROOT / "scripts/world/wild_tree.gd").read_text()
FIRE = (ROOT / "scripts/miracles/fireball.gd").read_text()
MIRACLES = (ROOT / "scripts/miracles/miracle_manager.gd").read_text()

DT = 1.0 / 60.0


def bare(text):
    out = []
    for line in text.splitlines():
        stripped = line.split("#")[0].rstrip()
        if stripped:
            out.append(stripped)
    return "\n".join(out)


def body(text, name):
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


WORTH = [int(v) for v in re.search(
    r"^const WORTH: Array\[int\] = \[([0-9,\s]+)\]", ROCK, re.M).group(1).split(",")]
NAMES = re.findall(r'"([a-z]+)"', re.search(
    r"^const NAMES.*?=\s*\[(.*?)\]", ROCK, re.M | re.S).group(1))

HOLDS_PER_STONE = const(ROCK, "HOLDS_PER_STONE", "rock_deposit.gd")
GLOWS_ABOVE = const(ROCK, "GLOWS_ABOVE", "rock_deposit.gd")
COOLS = const(ROCK, "COOLS", "rock_deposit.gd")
RAIN_COOLS = const(ROCK, "RAIN_COOLS", "rock_deposit.gd")
SOAKS = const(ROCK, "SOAKS", "rock_deposit.gd")
STAYS_WARMED = const(ROCK, "STAYS_WARMED", "rock_deposit.gd")
FIRE_BEAT = const(ROCK, "FIRE_BEAT", "rock_deposit.gd")
FIREBALL_SECONDS = const(ROCK, "FIREBALL_SECONDS", "rock_deposit.gd")


class Stone:
    """RockDeposit's heat, mirrored — `warm`, `_process` and `_burn_around`."""

    def __init__(self, rung):
        self.rung = rung
        self.heat = 0.0
        self.ablaze = False
        self.warmed = 0.0
        self.beat = 0.0
        self.raining = False

    def holds(self):
        return WORTH[self.rung] * HOLDS_PER_STONE

    def warm(self, seconds):
        self.heat = min(self.heat + seconds, self.holds())
        self.warmed = STAYS_WARMED
        if not self.ablaze and self.heat >= self.holds():
            self.ablaze = True
            self.beat = 0.0

    def tick(self, dt):
        """Returns the seconds of heat it hands out this step."""
        if self.heat <= 0.0:
            return 0.0
        if self.warmed > 0.0:
            self.warmed -= dt
        else:
            self.heat -= (COOLS + (RAIN_COOLS if self.raining else 0.0)) * dt
        if self.heat <= 0.0:
            self.heat = 0.0
            self.ablaze = False
            return 0.0
        if not self.ablaze:
            return 0.0
        self.beat -= dt
        if self.beat > 0.0:
            return 0.0
        self.beat = FIRE_BEAT
        return SOAKS * FIRE_BEAT


def pit(rocks, flames, flame_life, run_for):
    """A hole with `rocks` stones in it and `flames` trees burning on top.

    Every stone is within reach of every other, which is what a pit means.
    Returns (seconds until the first catches, seconds still alight at the end).
    """
    stones = [Stone(r) for r in rocks]
    caught = None
    t = 0.0
    beat = 0.0
    while t < run_for:
        if t < flame_life:
            beat -= DT
            if beat <= 0.0:
                beat = FIRE_BEAT
                for s in stones:
                    s.warm(SOAKS * FIRE_BEAT * flames)
        given = [s.tick(DT) for s in stones]
        for i, out in enumerate(given):
            if out <= 0.0:
                continue
            for j, s in enumerate(stones):
                if i != j:
                    s.warm(out)
        if caught is None and any(s.ablaze for s in stones):
            caught = t
        t += DT
    return caught, sum(1 for s in stones if s.ablaze)


def heating(fail):
    print("HOW LONG A FLAME HAS TO REST AGAINST A STONE")
    print("  %-10s %6s %9s %9s %9s %10s" % (
        "rung", "stone", "1 flame", "2 flames", "3 flames", "burns for"))
    for rung, worth in enumerate(WORTH):
        caught, _ = pit([rung], 1, 10000.0, WORTH[rung] * 1.6 + 5.0)
        if caught is None:
            fail.append("a %s never catches, however long a flame rests on it"
                        % NAMES[rung])
            continue
        two, _ = pit([rung], 2, 10000.0, WORTH[rung] * 1.6 + 5.0)
        three, _ = pit([rung], 3, 10000.0, WORTH[rung] * 1.6 + 5.0)
        print("  %-10s %6d %8.0fs %8.0fs %8.0fs %9.0fs" % (
            NAMES[rung], worth, caught, two, three, worth))
        # One flame, one second a second: it fills in as many seconds as it has
        # stone, give or take the beat the fire reports on.
        if abs(caught - worth) > FIRE_BEAT * 2.0 + 0.1:
            fail.append("a %s takes %.1fs to catch off one flame and is worth "
                        "%d stone — heat is measured in seconds and those two "
                        "numbers are the same number" % (NAMES[rung], caught, worth))


def lonely(fail):
    print()
    print("A ROCK ON ITS OWN GOES OUT")
    rung = len(WORTH) - 1
    worth = WORTH[rung]
    # Lit by flames that then die, and nothing else near it.
    stone = Stone(rung)
    stone.warm(worth)
    t = 0.0
    while stone.ablaze and t < worth * 4.0:
        stone.tick(DT)
        t += DT
    print("  a %s burns for %.0fs alone, then it is a rock again" % (NAMES[rung], t))
    # The latch: a stone does not start shedding until STAYS_WARMED after the
    # last thing that warmed it, so its burn is that much longer than its worth.
    if abs(t - worth) > STAYS_WARMED + 0.5:
        fail.append("a lone %s burns for %.0fs rather than the %d seconds it "
                    "holds" % (NAMES[rung], t, worth))
    # And in the rain it is shorter, but it is still a fire.
    wet = Stone(rung)
    wet.warm(worth)
    wet.raining = True
    t = 0.0
    while wet.ablaze and t < worth * 4.0:
        wet.raining = True
        wet.tick(DT)
        t += DT
    print("  in rain, %.0fs — shorter, and still a fire the whole way down" % t)
    if t >= worth:
        fail.append("rain does not shorten a burning stone at all")
    if t <= 0.5:
        fail.append("rain puts a burning stone out — only water it is IN does "
                    "that, and that is the point of heating one in the first place")


def the_pit(fail):
    print()
    print("A PIT OF THEM KEEPS ITSELF GOING")
    worth = WORTH[3]
    run = worth * 20.0
    for n in (1, 2, 5):
        caught, still = pit([3] * n, 2, worth, run)
        print("  %d %s%s lit by two trees: %d still burning after %.0fs"
              % (n, NAMES[3], "" if n == 1 else "s", still, run))
        if n == 1 and still:
            fail.append("one stone alone is still burning after twenty times "
                        "its own worth — nothing was feeding it")
        if n > 1 and not still:
            fail.append("%d stones in reach of each other went out. The pit is "
                        "the whole design: a rock that has caught is itself a "
                        "flame, so they reignite one another" % n)
    print("  — the trees are ash after %.0fs; the stones are not" % worth)


def brushing(fail):
    """A rock that passes through a flame must come out cold."""
    print()
    print("A ROCK THAT BRUSHES A FLAME")
    one = Stone(len(WORTH) - 1)
    one.warm(SOAKS * FIRE_BEAT)          # the least a fire can ever hand over
    print("  one beat of fire is %.1fs of heat; it shows above %.1fs"
          % (one.heat, GLOWS_ABOVE))
    if one.heat >= GLOWS_ABOVE:
        fail.append("a single beat of fire — the least a rock can be handed, "
                    "and what a stone dragged through a blaze gets — is enough "
                    "to make it glow")
    five = Stone(len(WORTH) - 1)
    for _ in range(int(5.0 / FIRE_BEAT)):
        five.warm(SOAKS * FIRE_BEAT)
    print("  five seconds against one gives %.1fs of heat, so %.1fs of orange"
          % (five.heat, five.heat - GLOWS_ABOVE))


def breaking(fail):
    print()
    print("SPLITTING ONE WHILE IT IS ALIGHT")
    top = len(WORTH) - 1
    hot = Stone(top)
    hot.warm(hot.holds())
    halves = [Stone(top - 1), Stone(top - 1)]
    for h in halves:
        h.warm(hot.heat)
    print("  a burning %s (%ds of heat) splits into two %ss, both alight "
          "with %ds each" % (NAMES[top], hot.heat, NAMES[top - 1], halves[0].heat))
    if not all(h.ablaze for h in halves):
        fail.append("splitting a burning rock gives pieces that are not alight")


def source(fail):
    print()
    print("WHAT THE SOURCE ACTUALLY DOES")

    warm = body(ROCK, "warm")
    if "_warmed = STAYS_WARMED" not in warm:
        # Without this a fire handing over 0.6s every 0.6s exactly cancels the
        # shedding and nothing in the world ever gets hot.
        fail.append("warming a rock no longer stops it shedding, so a stone "
                    "beside a bonfire cools at exactly the rate it heats")
    else:
        print("  a stone being warmed is not also cooling ....... yes")

    proc = body(ROCK, "_process")
    if "_drowned()" not in proc:
        fail.append("water no longer puts a burning stone out — it is the only "
                    "thing that can")
    else:
        print("  water it is IN puts it out ..................... yes")
    if "set_process(false)" not in proc or "set_process(false)" not in body(ROCK, "_ready"):
        fail.append("a cold rock is running _process — a hillside of two "
                    "hundred of them is supposed to cost nothing")
    else:
        print("  a cold rock runs no code ....................... yes")

    around = body(ROCK, "_burn_around")
    if "RockDeposit.warm_near(" not in around:
        fail.append("a burning rock no longer warms the rocks beside it, which "
                    "is the loop the whole pit rests on")
    else:
        print("  stone warms stone .............................. yes")

    burn = body(TREE, "_burn")
    if "RockDeposit.warm_near(" not in burn:
        fail.append("a burning tree no longer heats the stone under it — that "
                    "is the furnace")
    elif burn.count("_fire_beat_length()") < 2:
        # The beat it ticks on and the seconds it pays have to be one number.
        fail.append("the tree's fire beat and the seconds it pays the stone "
                    "are written separately, so they can drift apart and heat "
                    "rocks at a rate nobody chose")
    else:
        print("  a burning tree heats what it rests on ........... yes")

    if "RockDeposit.warm_near(" not in bare(FIRE):
        fail.append("a fireball no longer heats stone")
    else:
        print("  a fireball puts %2.0fs into a stone ............... yes"
              % FIREBALL_SECONDS)

    # Rain must reach a stone in the loop that calls `rain` on what it finds,
    # and NOT in any of the loops below that call `extinguish` — those are the
    # ones that put fires out, and a burning stone is not meant to be one of
    # the things they reach.
    rain = body(MIRACLES, "rain_upon").splitlines()
    at = [i for i, ln in enumerate(rain) if "rock_deposits" in ln]
    if len(at) != 1:
        fail.append("rain mentions rock_deposits %d times; it should reach a "
                    "hot stone exactly once, to shorten it" % len(at))
    else:
        near = "\n".join(rain[at[0]:at[0] + 6])
        if 'call("rain"' not in near:
            fail.append("rain no longer WARMS-DOWN a hot stone; whatever loop "
                        "it is in now, it is not the one that calls `rain`")
        elif "extinguish" in near:
            fail.append("rain douses a burning stone. It must only shorten one "
                        "— reaching fire is supposed to be worth something")
        else:
            print("  rain shortens a burn, never ends one ............ yes")

    if "half.warm(heat)" not in body(ROCK, "split"):
        fail.append("splitting a burning rock gives cold halves")
    else:
        print("  the halves come apart still burning ............. yes")


def main():
    fail = []
    heating(fail)
    lonely(fail)
    the_pit(fail)
    brushing(fail)
    breaking(fail)
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
