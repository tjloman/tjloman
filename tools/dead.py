#!/usr/bin/env python3
"""WHAT IS LEFT WHEN A THING DIES — AND WHAT IS NOT.

TWO SEPARATE JOBS, AND THE SECOND ONE IS THE IMPORTANT ONE.

THERE IS NO SUCH THING AS A CHILD'S BODY IN THIS GAME. A corpse here is an
OBJECT, and every object like it is PICKABLE — which means carried off, hurled
at a wall, set alight, eaten by a creature and butchered by a village on the
cannibal diet. Those are not things to do to a dead child, so the object does
not exist: Villager.die raises no Corpse at all for anyone under ADULT_AGE. The
grief, the oath, the announcement and what the death teaches the creature all
still happen. This file fails the build the day that guard is removed, moved, or
quietly turned into something weaker, and it checks the STATEMENT rather than
the presence of the word somewhere in the file.

AND AN ANIMAL LEAVES A BODY. It used to leave three chops in the grass where a
bison had been standing. Now there is a carcass carrying the weight of the beast
it was, reckoned off the torso the animal was drawn with — so the numbers here
are not invented, they were already in Animal.SPECIES.

Two claims worth arithmetic:

  1. A CHICKEN IS NOT A WEAPON AND A BISON IS. Thrown at a house, one should not
     register as a blow at all (Blow.MOMENTUM_MATTERS) and the other should take
     better than a third of it off in one go.

  2. NO VILLAGE IS A MOUTHFUL POORER. The joints a beast used to drop still
     arrive — they arrive after the body has had its three quarters of a minute
     to be a body. If that ever stops being true, every wolf kill and every
     fireballed herd quietly stops feeding anybody.

Every number is read off the source.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CARCASS = (ROOT / "scripts/world/carcass.gd").read_text()
ANIMAL = (ROOT / "scripts/animals/animal.gd").read_text()
VILLAGER = (ROOT / "scripts/villager/villager.gd").read_text()
BLOW = (ROOT / "scripts/world/blow.gd").read_text()
HOUSE = (ROOT / "scripts/world/house.gd").read_text()
BODY = (ROOT / "scripts/creature/creature_body.gd").read_text()

ORDINARY_THROW = 20.0


def bare(text):
    out = []
    for line in text.splitlines():
        if line.split("#")[0].rstrip():
            out.append(line.split("#")[0].rstrip())
    return "\n".join(out)


def body_of(text, name):
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


HEFT_BARE = const(CARCASS, "HEFT_BARE", "carcass.gd")
HEFT_PER_CUBIC = const(CARCASS, "HEFT_PER_CUBIC", "carcass.gd")
LIES_FOR = const(CARCASS, "LIES_FOR", "carcass.gd")
BURNS_FOR = const(CARCASS, "BURNS_FOR", "carcass.gd")
PER_MOMENTUM = const(BLOW, "PER_MOMENTUM", "blow.gd")
TO_FLESH = const(BLOW, "TO_FLESH", "blow.gd")
MOMENTUM_MATTERS = const(BLOW, "MOMENTUM_MATTERS", "blow.gd")
MOST_HEALTH = const(HOUSE, "MOST_HEALTH", "house.gd")
ADULT_AGE = const(VILLAGER, "ADULT_AGE", "villager.gd")

SPECIES = {}
_blk = ANIMAL[ANIMAL.index("const SPECIES := {"):]
_blk = _blk[:_blk.index("\n}\n")]
for name, x, y, z, meat in re.findall(
        r'"([a-z_]+)": \{"body": Vector3\(([\d.]+), ([\d.]+), ([\d.]+)\).*?"meat": (\d+)',
        _blk, re.S):
    SPECIES[name] = (float(x) * float(y) * float(z), int(meat))


def heft(volume):
    return HEFT_BARE + volume * HEFT_PER_CUBIC


def to_house(volume, speed):
    m = heft(volume)
    if speed * m < MOMENTUM_MATTERS:
        return 0.0
    return speed * m * PER_MOMENTUM * (1.0 - TO_FLESH)


def bodies(fail):
    print("WHAT A BODY WEIGHS, off the torso the beast was drawn with")
    print("  %-10s %7s %7s %7s   %s" % ("beast", "m3", "weighs", "joints", "thrown at a house"))
    for name in ("frog", "chicken", "wolf", "sheep", "deer", "bear", "ox", "bison"):
        if name not in SPECIES:
            continue
        vol, meat = SPECIES[name]
        hit = to_house(vol, ORDINARY_THROW)
        said = "nothing at all" if hit <= 0.0 else "%.0f of %.0f (%.0f%%)" % (
            hit, MOST_HEALTH, hit / MOST_HEALTH * 100.0)
        print("  %-10s %7.3f %7.1f %7d   %s" % (name, vol, heft(vol), meat, said))
    if to_house(SPECIES["chicken"][0], ORDINARY_THROW) > 0.0:
        fail.append("a thrown chicken damages a house — it is under Blow's "
                    "momentum floor for a reason")
    bison = to_house(SPECIES["bison"][0], ORDINARY_THROW)
    if bison < MOST_HEALTH / 3.0:
        fail.append("a bison thrown at a house does %.0f%% of it. 'A bison "
                    "doesn't strike a house without consequences.'"
                    % (bison / MOST_HEALTH * 100.0))


def no_child_body(fail):
    print()
    print("THERE IS NO SUCH THING AS A CHILD'S BODY")
    raised = []
    for path in sorted(ROOT.glob("scripts/**/*.gd")):
        for i, line in enumerate(bare(path.read_text()).splitlines(), 1):
            if "Corpse.new()" in line:
                raised.append((path.relative_to(ROOT), i, line))
    print("  a Corpse is raised in exactly %d place%s"
          % (len(raised), "" if len(raised) == 1 else "s"))
    if len(raised) != 1:
        fail.append("a Corpse is raised in %d places; the guard below covers "
                    "one of them, so the others are unguarded" % len(raised))
        return
    # THE STATEMENT, NOT THE NAME. `is_adult()` appearing somewhere in the file
    # proves nothing — the raising has to sit INSIDE it.
    die = body_of(VILLAGER, "die").splitlines()
    at = [i for i, ln in enumerate(die) if "Corpse.new()" in ln]
    if not at:
        fail.append("the Corpse is no longer raised in Villager.die, so this "
                    "check is looking at the wrong function and is proving "
                    "nothing about anything")
        return
    line = die[at[0]]
    depth = len(line) - len(line.lstrip("\t"))
    guard = ""
    for ln in reversed(die[:at[0]]):
        if ln.strip() and len(ln) - len(ln.lstrip("\t")) < depth:
            guard = ln.strip()
            break
    print("  it is raised under: %s" % (guard or "(nothing)"))
    if guard != "if is_adult():":
        fail.append("the body of a dead villager is raised under `%s` rather "
                    "than `if is_adult():`. Every object like it is PICKABLE — "
                    "carried off, thrown, burnt, eaten, butchered — and there "
                    "is no version of this game in which those happen to a "
                    "dead child." % (guard or "nothing at all"))
    else:
        print("  nobody under %d leaves one ...................... confirmed"
              % int(ADULT_AGE))


def not_a_mouthful_poorer(fail):
    print()
    print("NO VILLAGE IS A MOUTHFUL POORER")
    die = body_of(ANIMAL, "die")
    if "Carcass.new()" not in die:
        fail.append("an animal no longer leaves a body")
    elif "if drop_meat and meat > 0:" not in die:
        fail.append("an animal leaves a body even when something has already "
                    "taken it — a hunter carrying the kill home, a creature "
                    "swallowing it")
    else:
        print("  a beast that dies in the field leaves a body .... yes")
    if "FoodItem.new()" in die:
        fail.append("an animal still scatters loose joints as well as leaving "
                    "a body, so every kill now feeds a village twice")
    apart = body_of(CARCASS, "_fall_apart")
    if "for i in meat:" not in apart or "FoodItem.new()" not in apart:
        fail.append("an abandoned body no longer becomes the meat it was "
                    "worth. Every wolf kill and every fireballed herd in the "
                    "world just stopped feeding anybody")
    else:
        print("  and in %.0fs of being ignored it is that meat ... yes" % LIES_FOR)
    if "_charred" not in apart:
        fail.append("a burnt body still feeds people")
    else:
        print("  unless it was burnt, which ruins it ............. yes")
    if "_charred" not in body_of(CARCASS, "butcher"):
        fail.append("butchering a burnt body still yields meat")


def source(fail):
    print()
    print("WHAT THE SOURCE ACTUALLY DOES")
    proc = body_of(CARCASS, "_process")
    if "freeze or not sleeping" not in proc:
        fail.append("a body being carried or thrown is counting down to falling "
                    "apart — it should be asked of the physics server whether "
                    "anybody is playing with it")
    else:
        print("  being played with is not being abandoned ....... yes")
    burn = body_of(CARCASS, "_burn")
    if "BURNS_FOR * 0.5" not in burn:
        # Charring on the first lick of flame means a lit body can never be
        # saved, and rain douses anything BURNABLE it falls on.
        fail.append("a body chars the instant it catches, so there is no window "
                    "in which pulling it out of the fire (or rain) saves it")
    else:
        print("  there are %.0fs to save a lit body .............. yes" % (BURNS_FOR * 0.5))
    if "add_to_group(Affords.BURNABLE)" not in bare(CARCASS):
        fail.append("a body cannot burn at all")
    if "thing is Carcass" not in bare(BODY):
        fail.append("CreatureBody.burden does not weigh a body, so a fledgling "
                    "can shoulder a bison")
    else:
        print("  a whelp cannot shoulder a bison ................ yes")
    if "func butcher" not in CARCASS:
        fail.append("nothing can cut a body up")


def main():
    fail = []
    bodies(fail)
    no_child_body(fail)
    not_a_mouthful_poorer(fail)
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
