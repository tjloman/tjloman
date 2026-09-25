#!/usr/bin/env python3
"""NO CHILD IS HARMED IN THIS GAME, AND TRYING GETS YOU NOTHING.

Somebody will get bored and try to murder the children. The only thing that
keeps that from being a game is there being NO PAYOFF: not a punishment (which
is a payoff of its own to the player hunting for one), not a refusal (which is a
puzzle), but the dullest possible answer. Any harm that reaches a child — fire,
a stone, a fireball, a quake, a wolf, water, the creature, hunger — turns at the
door into this: they walk to the school or the nearest roof, go inside, and are
gone to family elsewhere. No announcement, no scream, no body, no mourners, no
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
    for name in ("spared", "send_away", "_set_off", "shelter_for", "leave_step", "_let_go"):
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
    if 'Villager.State.LEAVING: return ""' not in over:
        fail.append("something is written over a leaving child's head")
    else:
        print("  and nothing floats over their head ............ yes")
    arm = (body(V, "_physics_process") or "").split("State.LEAVING:")[-1][:200]
    if "ChildSafety.leave_step(self, delta)" not in arm or "queue_free()" not in arm:
        fail.append("a leaving child never walks anywhere, or never goes in")
    if "shelter_for(" in (body(SAFE, "leave_step") or ""):
        fail.append("the walk home looks for a roof every frame — every house in "
                    "the world, per leaving child, per physics tick")
    if "state = State.LEAVING" not in (body(V, "_choose") or ""):
        fail.append("a child lifted out of harm's way and set down forgets they "
                    "were leaving")
    else:
        print("  set down again, they carry on home ............ yes")


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
