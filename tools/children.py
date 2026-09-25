#!/usr/bin/env python3
"""NO CHILD IS HARMED IN THIS GAME, AND TRYING GETS YOU NOTHING.

Somebody will get bored and try to murder the children. The only thing that
keeps that from being a game is there being NO PAYOFF: not a punishment (which
is a payoff of its own to the player hunting for one), not a refusal (which is a
puzzle), but the dullest possible answer. Any harm that reaches a child — fire,
a stone, a fireball, a quake, a wolf, water, the creature, hunger — turns at the
door into this: they walk home, go inside, and stay in until the next morning.
Only a run of it — the same child harmed day after day with no clear day between
— sends them to family elsewhere for good. No announcement, no scream, no body, no mourners, no
karma, nothing for the creature to learn, nothing for the village to witness.

A RULE LIKE THIS FAILS BY LEAKING, not by being wrong, so this checks every door
harm comes through by its STATEMENTS:

  * each door asks ChildSafety.spared BEFORE any consequence — the belief, the
    karma, the grief, the announcement is itself the payoff;
  * the slow harms (drowning, starving) are turned at their START, or there is
    ten seconds of a child drowning to watch before the door is reached;
  * the creature is never OFFERED a child, never takes one up, and never eats
    one, each shut separately so no future path gets through one gap;
  * the leaving itself says and does nothing, which is checked by looking for
    every kind of thing that would count as saying or doing something;
  * and nothing anywhere frees a villager except the two doors that ask.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def read(rel):
    return (ROOT / rel).read_text()


def bare(text):
    out = []
    for line in text.splitlines():
        if line.split("#")[0].rstrip():
            out.append(line.split("#")[0].rstrip())
    return "\n".join(out)


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        return None
    rest = text[m.end():]
    rest = rest[rest.index("\n") + 1:]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


V = read("scripts/villager/villager.gd")
SAFE = read("scripts/villager/child_safety.gd")
NEEDS = read("scripts/villager/villager_needs.gd")
MAUL = read("scripts/villager/mauling.gd")
BLOW = read("scripts/world/blow.gd")
FIRE = read("scripts/miracles/fireball.gd")
CREATURE = read("scripts/creature/creature.gd")
EYES = read("scripts/creature/creature_eyes.gd")
WORDS = read("scripts/villager/villager_words.gd")


def first_statement(fail, where, name, needle, why):
    b = body(where, name)
    if b is None:
        fail.append("could not find %s — if it moved, nothing is guarding it" % name)
        return
    first = b.strip().splitlines()[0].strip() if b.strip() else ""
    if needle not in first:
        fail.append("%s does not ask first — its first statement is `%s`. %s"
                    % (name, first, why))
    else:
        print("  %-28s asks before anything else ......... yes" % name)


def before(fail, text, guard, then, what):
    g, t = text.find(guard), text.find(then)
    if g < 0:
        fail.append("%s: the child is never asked about" % what)
    elif t >= 0 and g > t:
        fail.append("%s: the child is asked about only AFTER `%s` — which is "
                    "the payoff" % (what, then))
    else:
        print("  %-28s turned before `%s` ... yes" % (what, then.split("(")[0][:14]))


def doors(fail):
    print("EVERY DOOR HARM COMES THROUGH")
    spared = "ChildSafety.spared(self)"
    first_statement(fail, V, "take_damage", spared,
                    "The god's mark and the belief come next, and are a payoff.")
    first_statement(fail, V, "ignite", spared, "A burning child is a spectacle.")
    first_statement(fail, V, "enter_dying", spared,
                    "Dying ANNOUNCES itself.")
    first_statement(fail, V, "die", spared,
                    "Death brings mourning, karma, grief and a lesson.")
    hazards = body(V, "_tick_hazards") or ""
    before(fail, hazards, "ChildSafety.spared(self)", "health -= HAZARD_RATE",
           "drowning")
    before(fail, bare(NEEDS), "ChildSafety.spared(who)", "who.health -= 2.0",
           "starving")
    before(fail, bare(NEEDS), "ChildSafety.spared(who)", "GameState.announce",
           "starving, announced")
    before(fail, body(MAUL, "seize") or "", "ChildSafety.spared(prey)",
           "feud.seize", "a wolf's jaws")
    before(fail, body(BLOW, "lands") or "", "ChildSafety.spared(soul)",
           "soul.take_damage", "a thrown thing")
    before(fail, bare(FIRE), "ChildSafety.spared(villager)",
           "shift_alignment(KARMA_PER_KILL)", "a fireball's core")


def creature(fail):
    print()
    print("THE CREATURE")
    around = body(CREATURE, "_things_around") or ""
    if "ChildSafety.is_child(node)" not in around:
        fail.append("the creature is OFFERED children among the things it "
                    "could smash, hurl or eat — whether it ever does is learned, "
                    "and nothing should be learned about this")
    else:
        print("  it is never offered a child ................... yes")
    first_statement(fail, CREATURE, "_pick_up_thing", "ChildSafety.is_child(node)",
                    "Every road to carrying — a catch, a gift, a chase — ends here.")
    first_statement(fail, EYES, "devour", "ChildSafety.spared(victim)",
                    "The last door. It is shut too.")


def silence(fail):
    print()
    print("THE LEAVING SAYS AND DOES NOTHING")
    loud = ("GameState.announce", "GameState.hint", "hive.witness", "mourn(",
            "shift_alignment", "SoundBank", "Corpse.new", "witness_horror",
            "change_belief", "judge(", "express(")
    for name in ("spared", "take_shelter", "resume", "_set_off", "shelter_for",
                 "leave_step", "_go_in", "hide_step", "_come_out"):
        b = body(SAFE, name)
        if b is None:
            fail.append("ChildSafety.%s is missing" % name)
            continue
        said = [w for w in loud if w in b]
        if said:
            fail.append("ChildSafety.%s does %s — the whole design is that "
                        "nothing happens" % (name, ", ".join(said)))
    print("  no word, no sound, no body, no karma, no lesson  checked")
    over = body(WORDS, "status_text") or ""
    if 'Villager.State.LEAVING, Villager.State.HIDDEN: return ""' not in over:
        fail.append("something is written over the head of a child going home, "
                    "or where one is hiding")
    else:
        print("  and nothing floats over their head ............ yes")
    arm = (body(V, "_physics_process") or "").split("State.LEAVING:")[-1][:200]
    if "ChildSafety.leave_step(self, delta)" not in arm or "queue_free()" not in arm:
        fail.append("a leaving child never walks anywhere, or never goes in")
    if "shelter_for(" in (body(SAFE, "leave_step") or ""):
        fail.append("the walk home looks for a roof every frame — every house in "
                    "the world, per leaving child, per physics tick")
    if "ChildSafety.resume(self)" not in (body(V, "_choose") or ""):
        fail.append("a child lifted out of harm's way and set down forgets they "
                    "were leaving")
    else:
        print("  set down again, they carry on home ............ yes")


def const(text, name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s" % name)
    return float(m.group(1))


class Child:
    """ChildSafety.take_shelter's run, mirrored: how bad has it been?"""

    def __init__(self):
        self.hid_on = -99
        self.hidings = 0
        self.gone = False

    def harmed(self, today, leaves_after):
        run = self.hidings if today - self.hid_on <= 1 else 0
        run += 1
        self.hidings = run
        self.hid_on = today
        if run >= leaves_after:
            self.gone = True


def a_day_indoors(fail):
    print()
    print("A DAY INDOORS, NOT A TOWN EMPTIED")
    leaves = int(const(SAFE, "LEAVES_AFTER"))
    morning = const(SAFE, "MORNING")
    print("  harmed, they come out at the next first light (%.2f of a day)" % morning)
    print("  harmed %d days running, with no clear day between, they are gone" % leaves)

    # "I just watched a village go 32 people to 17 for one lightning bolt."
    kids = [Child() for _ in range(15)]
    for k in kids:
        k.harmed(0, leaves)
    back = sum(1 for k in kids if not k.gone)
    print("  one lightning bolt over fifteen children: %d come back out next day" % back)
    if back != len(kids):
        fail.append("one bad moment still removes children for good — %d of %d "
                    "gone. 'We don't just zero out villages from one or two "
                    "negligent acts of recklessness.'" % (len(kids) - back, len(kids)))
    twice = Child()
    twice.harmed(0, leaves)
    twice.harmed(1, leaves)
    if twice.gone:
        fail.append("two careless days running send a child away for good")
    spaced = Child()
    for day in range(0, 12, 2):
        spaced.harmed(day, leaves)
    print("  harmed every other day for a fortnight: %s"
          % ("gone" if spaced.gone else "still at home — a clear day forgives"))
    if spaced.gone:
        fail.append("a clear day between does not clear the run")
    run = Child()
    for day in range(leaves):
        run.harmed(day, leaves)
    print("  harmed %d days in a row: %s" % (leaves, "gone" if run.gone else "still here"))
    if not run.gone:
        fail.append("no amount of harm ever sends a child away — then the god "
                    "who does it every day is only inconveniencing them")

    take = body(SAFE, "take_shelter") or ""
    if "today - last <= 1" not in take or "run >= LEAVES_AFTER" not in take:
        fail.append("take_shelter no longer counts a run the way this models it "
                    "— the simulation above is checking a rule the game lost")
    step = body(SAFE, "leave_step") or ""
    if 'get_meta("for_good", false)' not in step:
        fail.append("the walk home ends the body without asking whether this "
                    "was the time it was for good")
    hide = body(SAFE, "hide_step") or ""
    if "today <= int(" not in hide or "day_fraction() < MORNING" not in hide:
        fail.append("a hidden child comes out before the next morning")
    go_in = body(SAFE, "_go_in") or ""
    if "visible = false" not in go_in or "collision_layer = 0" not in go_in:
        fail.append("a child indoors can still be seen, hovered or hit")
    else:
        print("  indoors, nothing can see, hover or reach them .. yes")
    if "if sheltering and state not in" not in (body(V, "_physics_process") or ""):
        fail.append("anything that writes a villager's state from outside — a "
                    "scare, a festival, a muster — walks an invisible child out "
                    "of their house and into a field")
    else:
        print("  and nothing else can walk them out of it ....... yes")


def frees(fail):
    print()
    print("NOTHING ELSE MAKES A VILLAGER VANISH")
    # BY TYPE, NOT BY NAME. `child` is also what every UI file calls a scene
    # node; what matters is whatever was declared a Villager in that file.
    found = []
    for path in sorted(ROOT.glob("scripts/**/*.gd")):
        text = bare(path.read_text())
        names = set(re.findall(r"\b(\w+)\s*:=\s*[^\n]*\bas Villager\b", text))
        names |= set(re.findall(r"\b(\w+)\s*:\s*Villager\b", text))
        for name in names:
            if re.search(r"\b%s\.queue_free\(\)" % re.escape(name), text):
                found.append("%s:%s" % (path.relative_to(ROOT), name))
    allowed = {"scripts/creature/creature_eyes.gd:victim"}
    stray = [f for f in found if f not in allowed]
    if stray:
        fail.append("a villager is freed somewhere that does not ask about "
                    "children first: %s" % ", ".join(stray))
    else:
        print("  only the two doors that ask ................... yes")


def main():
    fail = []
    doors(fail)
    creature(fail)
    silence(fail)
    a_day_indoors(fail)
    frees(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
