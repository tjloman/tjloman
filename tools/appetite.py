#!/usr/bin/env python3
"""WHO EATS THE DEAD, AND WHEN.

A town of three hundred with a glut in the storehouse knelt down round one
dead man. The line a villager went to a body BEFORE the granary sat at
morality 30, above where the card starts saying "decent" (20), so every
coarse soul and some decent ones chose the body first, and with the body
being eaten nobody mourned.

The rule now, by the word on the card:

  saintly, decent, coarse   a body only starving, and only when there is
                            nothing on the ground, in the store or on a bush
  wicked                    a body when the store has nothing they may eat,
                            before foraging; never in front of a mourner
  monstrous                 a body before the store, mourners or not

and everybody short of monstrous weeps over the dead.

This reads VillagerFeeding.plan in source order — each place to eat and the
guard on it — and runs it over every morality and hunger against every larder.
Arithmetic on the source. Not a playtest.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FEED = (ROOT / "scripts/villager/villager_feeding.gd").read_text()
WORDS = (ROOT / "scripts/villager/villager_words.gd").read_text()
MAN = (ROOT / "scripts/villager/villager.gd").read_text()


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


def const(text, name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s" % name)
    return float(m.group(1))


WICKED = const(FEED, "WICKED")
MONSTROUS = const(FEED, "MONSTROUS")
STARVING = const(MAN, "STARVING_HUNGER")
NAMES = {"WICKED": WICKED, "MONSTROUS": MONSTROUS}


def steps():
    """plan() as an ordered list of (place, morality ceiling or None)."""
    out = []
    lines = body(FEED, "plan").splitlines()
    for i, ln in enumerate(lines):
        if "_ground_food(who)" in ln:
            out.append(("ground", None))
        elif "store.has(type)" in ln:
            out.append(("store", None))
        elif "VillagerSearch.forage(who)" in ln:
            out.append(("bush", None))
        elif "return _go_to(who, body)" in ln:
            guard = lines[i - 1].strip()
            m = re.fullmatch(r"if body != null and who\.morality < (\w+):", guard)
            if m and m.group(1) in NAMES:
                out.append(("body", NAMES[m.group(1)]))
            elif guard == "if body != null:":
                out.append(("body", None))
            else:
                sys.exit("cannot read the guard on a body: `%s`" % guard)
    return out


def word(m):
    if m > 60:
        return "saintly"
    if m > 20:
        return "decent"
    if m >= WICKED:
        return "coarse"
    if m >= MONSTROUS:
        return "wicked"
    return "monstrous"


def choose(plan, morality, hunger, have):
    """What a villager eats, given which places have food."""
    flesh = morality < WICKED or hunger > STARVING          # will_eat_flesh
    for place, ceiling in plan:
        if place == "body":
            if flesh and "body" in have and (ceiling is None or morality < ceiling):
                return "body"
        elif place in have:
            return place
    return None


def source(fail):
    flesh = body(FEED, "will_eat_flesh")
    if not re.search(r"who\.morality < WICKED or who\.hunger > Villager\.STARVING_HUNGER", flesh):
        fail.append("will_eat_flesh is not the wicked line or starving: `%s`" % flesh.strip())
    if "VillagerFeeding.WICKED" not in body(WORDS, "morality_word"):
        fail.append("the word 'wicked' and the line a soul eats a body are two numbers")
    if WICKED > -20.0 + 1e-9 or WICKED <= MONSTROUS:
        fail.append("WICKED is %.0f: it must sit below every coarse soul and above "
                    "the monstrous" % WICKED)
    pick = body(MAN, "_pick_job")
    if "VillagerFeeding.will_mourn(self)" not in pick:
        fail.append("the job board no longer asks will_mourn before offering grief")


def model(fail):
    plan = steps()
    print("plan(), in order: " + ", ".join(
        p if c is None else "%s(<%.0f)" % (p, c) for p, c in plan))
    larders = (("a full store", {"store", "bush", "body"}),
               ("a bare store, berries out", {"bush", "body"}),
               ("nothing but the body", {"body"}))
    print("%-10s %-7s %-26s %-26s %s" % ("", "hunger", *[n for n, _ in larders]))
    for m in (80, 25, 0, -19, -21, -59, -61, -90):
        for hunger in (70, 95):
            got = [choose(plan, m, hunger, have) or "-" for _, have in larders]
            print("%-10s %-7d %-26s %-26s %s" % ("%s %d" % (word(m), m), hunger, *got))
    for m in range(-100, 101):
        w = word(m)
        for hunger in (61, 80, 89, 91, 100):
            full = choose(plan, m, hunger, {"store", "bush", "body"})
            bare_store = choose(plan, m, hunger, {"bush", "body"})
            if w != "monstrous" and full == "body":
                fail.append("a %s soul (%d) eats a body with a full storehouse" % (w, m))
            if w in ("saintly", "decent", "coarse") and bare_store == "body":
                fail.append("a %s soul (%d) eats a body with berries on the bushes" % (w, m))
            if w == "monstrous" and full != "body":
                fail.append("a monstrous soul (%d) walks past a body to the store" % m)
            if hunger > STARVING and choose(plan, m, hunger, {"body"}) != "body":
                fail.append("a starving %s soul (%d) with nothing else starves "
                            "beside a body" % (w, m))


def main():
    fail = []
    source(fail)
    model(fail)
    print()
    if fail:
        for f in sorted(set(fail))[:20]:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
