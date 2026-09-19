#!/usr/bin/env python3
"""WHO HE HAS BEEN, AS AGAINST WHAT HE DID LAST.

Character was a running impression: one number an axis, moved 5% by each deed.
That is a memory of about twenty deeds, and twenty deeds is five minutes. A
creature could haul grain all afternoon and be indistinguishable by teatime
from one that never had, and a creature that ate somebody at noon was innocent
again by supper -- not forgiven, INNOCENT, because the only trace a deed left
was a number the next deed moved.

    "Ethos's memory needs drastically expanded... 20 deeds is 5 minutes of
     gameplay. Let's catalogue the deeds episodically, and we can assign each
     memory a value within FF... That's 256 memory values, nearly 13 times the
     capacity... and for the creature to have moral depth."

So this file guards the record that replaced it. Six claims:

  TWO HUNDRED AND FIFTY-SIX DEEDS, each weighing 00..FF, in a ring -- an hour
  of conduct kept deed by deed rather than boiled down.

  IT TAPERS. The newest deed counts for all of itself and the oldest for a
  quarter, so nothing drops off a cliff.

  WHAT FALLS OUT PAINTS. The 257th deed pushes the 1st out, and on the way out
  it lays its meaning permanently onto the canvas -- which is the only way
  anything reaches the canvas at all.

  AND IT IS HEARD. A forgotten deed becomes a conviction in words, because a
  character the player cannot read is a number wearing a costume.

  DILUTED, NEVER SCRUBBED. Good years thin a bad one and never take it out:
  the deepest marks of a life are kept whole and tint the reading forever.

  AND THE RATIO IS THE POINT. Four rescues and one killing must not read the
  same as one rescue and four killings. That is the whole of what a record is
  for, and an average cannot do it -- which this file measures rather than
  asserts.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEEDS = (ROOT / "scripts/creature/creature_deeds.gd").read_text()
ETHOS = (ROOT / "scripts/creature/creature_ethos.gd").read_text()
BELIEFS = (ROOT / "scripts/creature/creature_beliefs.gd").read_text()


SUBJECT = dict(re.findall(r'"(\w+)": "([^"]+)"',
              BELIEFS[BELIEFS.index("const PLAIN_SUBJECT := {"):].split("}")[0]))


def code(text):
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


MOST = int(number(DEEDS, "MOST") or 0)
TAIL = number(DEEDS, "TAIL")
TAPER = number(DEEDS, "TAPER")
PAINT = number(DEEDS, "PAINT")
RING_SHARE = number(DEEDS, "RING_SHARE")
GRAVITY = number(DEEDS, "GRAVITY")
VOICE = number(DEEDS, "VOICE")
REMEMBERED = number(DEEDS, "REMEMBERED")
MARKS = int(number(DEEDS, "MARKS") or 0)
WORTH_MARKING = number(DEEDS, "WORTH_MARKING")
STEP = number(BELIEFS, "CONVICTION_STEP")
CAP = number(BELIEFS, "CONVICTION_CAP")
CONFIDENT = number(BELIEFS, "CONFIDENT")

# The meanings, read out of the GDScript so this cannot drift from the game.
MEANING = {}
block = ETHOS[ETHOS.index("const MEANING := {"):]
block = block[:block.index("\n}")]
for row in block.split("\n"):
    row = row.split("#")[0].strip()
    found = re.match(r'"(\w+)": \{(.*)\},?$', row)
    if not found:
        continue
    MEANING[found.group(1)] = {
        k: float(v) for k, v in re.findall(r'"(\w+)": ([-\d.]+)', found.group(2))}
GOOD = {k: float(v) for k, v in
        re.findall(r'"(\w+)": ([\d.]+)', ETHOS[ETHOS.index("const GOOD := {"):][:120])}
AXES = re.findall(r'"(\w+)"',
                  ETHOS[ETHOS.index("const AXES"):][:200])


class Record:
    """The GDScript ring, in Python, one for one with CreatureDeeds."""

    def __init__(self):
        self.ring = []            # newest last: (verb, force 0..255)
        self.canvas = {a: 0.0 for a in AXES}
        self.scars, self.graces = [], []
        self.rules = {}

    def add(self, verb, weight=1.0, way=1.0):
        if len(self.ring) >= MOST:
            self._forget(self.ring.pop(0))
        self.ring.append((verb, round(weight * 255), way))

    def _forget(self, slot):
        verb, force, way = slot
        w = force / 255.0 * TAIL
        worst = his = 0.0
        for a, amount in MEANING.get(verb, {}).items():
            amount *= w * way
            self.canvas[a] = max(-1.2, min(1.2, self.canvas[a] + amount * PAINT))
            worst += amount * GOOD.get(a, 0.0)
            his += amount * MEANING[verb][a]
        his = his >= 0
        if abs(worst) >= WORTH_MARKING * PAINT:
            into = self.scars if worst < 0 else self.graces
            into.append({"verb": verb, "weight": worst, "his": his})
            into.sort(key=lambda m: -abs(m["weight"]))
            del into[MARKS:]
        # The game's key, exactly: a conviction names what the deed is done TO,
        # and it is "right" when the deed was his own and "wrong" when he was
        # pushed the other way. Looking up the sign of the deed's MORALITY here
        # instead is how the first draft of this file managed to test for a
        # rule the game never writes, and pass.
        if worst:
            rule = "%s|%s>%s" % (verb, SUBJECT.get(verb, "things"),
                                 "right" if his else "wrong")
            self.rules[rule] = min(self.rules.get(rule, 0.0) + STEP * abs(worst), CAP)

    def _ring(self, axis):
        if not self.ring:
            return 0.0
        total = spread = 0.0
        for age, (verb, force, way) in enumerate(reversed(self.ring)):
            w = force / 255.0 * (1.0 - (age / MOST) ** TAPER * (1.0 - TAIL))
            m = MEANING.get(verb, {}).get(axis, 0.0) * way
            say = abs(m) ** GRAVITY
            total += (1 if m >= 0 else -1) * say * w
            spread += (say + VOICE) * w
        return total / spread if spread else 0.0

    def _marked(self, axis):
        out = 0.0
        for mark in (self.scars + self.graces):
            profile = MEANING.get(mark["verb"], {})
            if axis in profile:
                out += profile[axis] * (1 if mark.get("his", True) else -1)
        return max(-1.0, min(1.0, out / (MARKS * 2)))

    def standing(self, axis):
        return max(-1.2, min(1.2, self._ring(axis) * RING_SHARE
                   + self.canvas[axis] * (1 - RING_SHARE)
                   + self._marked(axis) * REMEMBERED))

    def alignment(self):
        return max(-1.0, min(1.0, sum(self.standing(a) * w
                                      for a, w in GOOD.items()) * 1.4))


class Impression:
    """What it used to be: one number an axis, nudged DEED_FORCE a deed."""

    def __init__(self, force=0.05, drift=0.35):
        self.axis = {a: 0.0 for a in AXES}
        self.force, self.drift = force, drift

    def add(self, verb, weight=1.0):
        profile = MEANING.get(verb, {})
        f = self.force * weight / 0.05 * 0.05
        for a in AXES:
            rate = f if a in profile else f * self.drift
            self.axis[a] += (profile.get(a, 0.0) - self.axis[a]) * rate

    def standing(self, axis):
        return self.axis[axis]

    def alignment(self):
        return max(-1.0, min(1.0, sum(self.axis[a] * w
                                      for a, w in GOOD.items()) * 1.4))


fail = []
print("READ OUT OF THE GAME: %d verbs, %d axes, ring of %d, taper to %.0f%%."
      % (len(MEANING), len(AXES), MOST, TAIL * 100))

# -- THE RATIO IS THE POINT --------------------------------------------------
print()
print("FOUR RESCUES AND ONE KILLING, AGAINST ONE RESCUE AND FOUR KILLINGS")
print("   (each with a hundred ordinary deeds around it, as a life has)")
for label, saves, kills in [("mostly good", 4, 1), ("mostly awful", 1, 4)]:
    for who, model in [("record", Record()), ("the old impression", Impression())]:
        for i in range(100):
            model.add("gather" if i % 2 else "tend", 0.25)
        for _ in range(saves):
            model.add("rescue", 1.0)
        for _ in range(kills):
            model.add("eat_kin", 1.0)
        print("   %-13s %-20s mercy %+.2f   alignment %+.2f"
              % (label, who, model.standing("mercy"), model.alignment()))
        if who == "record":
            globals()["_last_" + label.split()[1]] = model.alignment()
gap = _last_good - _last_awful
print("   the record tells them apart by %.2f of alignment." % gap)
if gap < 0.25:
    fail.append("four rescues and one killing still read almost the same as one "
                "rescue and four killings (%.2f apart), which is the whole of "
                "what a record was for" % gap)

# -- AN AFTERNOON'S WORK, AND WHETHER IT SURVIVES TEATIME --------------------
print()
print("AN AFTERNOON HAULING GRAIN (120 deeds), THEN TWENTY MINUTES IDLE (80)")
for who, model in [("record", Record()), ("the old impression", Impression())]:
    for _ in range(120):
        model.add("gather", 0.25)
    worked = model.standing("bounty")
    for _ in range(80):
        model.add("wander", 0.25)
    print("   %-20s bounty after the work %+.2f -> after the idling %+.2f"
          % (who, worked, model.standing("bounty")))
    if who == "record":
        kept = model.standing("bounty") / worked if worked else 0.0
print("   the record keeps %d%% of the afternoon; five minutes of walking about "
      "no longer erases it." % round(kept * 100))
if kept < 0.4:
    fail.append("an afternoon's work is %d%% gone after twenty minutes of "
                "idling, which is the five-minute memory again" % round(100 - kept * 100))

# -- WHAT FALLS OUT PAINTS, AND IS HEARD -------------------------------------
print()
print("A MAN-EATER, DEED BY DEED (%d deeds fill the record, then it paints)" % MOST)
who = Record()
said_at = 0
for n in range(1, MOST * 4 + 1):
    who.add("eat_kin", 1.0) if n % 25 == 0 else who.add("wander", 0.25)
    strongest = who.rules.get("eat_kin|%s>right" % SUBJECT.get("eat_kin"), 0.0)
    if said_at == 0 and strongest >= CONFIDENT:
        said_at = n
    if n in (MOST, MOST * 2, MOST * 3, MOST * 4):
        print("   after %4d deeds: canvas mercy %+.2f   scars %d   "
              "conviction %.2f" % (n, who.canvas["mercy"], len(who.scars), strongest))
painted = who.canvas["mercy"] < -0.001
print("   \"is sure that eating people is the right thing to do\" is said at "
      "deed %d." % said_at)
if not painted:
    fail.append("nothing reaches the canvas as deeds fall out of the record, so "
                "a life longer than an hour leaves no permanent trace at all")
if said_at == 0:
    fail.append("no forgotten deed ever becomes a conviction the player can "
                "read, so the canvas moves the creature without ever saying so")

# -- DILUTED, NEVER SCRUBBED -------------------------------------------------
print()
print("ONE KILLING, THEN A THOUSAND KINDNESSES")
saint = Record()
for _ in range(MOST):
    saint.add("tend", 0.25)
sinner = Record()
sinner.add("eat_kin", 1.0)
for _ in range(MOST):
    sinner.add("tend", 0.25)
for n in (200, 500, 1000):
    for _ in range((n - len(sinner.ring)) if n == 200 else (n - 200 if n == 500 else 500)):
        sinner.add("tend", 0.25)
        saint.add("tend", 0.25)
    print("   after %4d kindnesses: the one who ate a man reads mercy %+.3f, "
          "the one who never did %+.3f" % (n, sinner.standing("mercy"),
                                           saint.standing("mercy")))
apart = saint.standing("mercy") - sinner.standing("mercy")
print("   a thousand good deeds later he is still %.3f short of clean, and "
      "always will be." % apart)
if apart <= 0.0:
    fail.append("a creature that ate somebody reads exactly as merciful as one "
                "that never did, once enough good deeds are piled on — the "
                "fault has been scrubbed rather than diluted")

# -- AND THE CODE SAYS SO ----------------------------------------------------
print()
forgets = body_of(DEEDS, "add")
paints = body_of(DEEDS, "_forget")
one_door = any("_forget(head)" in r for r in forgets)
canvas_only = any("canvas[a] = clampf" in r for r in paints)
# Loading a save writes the canvas too, and must: those two are excluded by
# NAME rather than by counting, so a third writer appearing anywhere else in
# the file is still caught.
living = code(DEEDS)
for skip in ("from_dict", "inherit"):
    for row in body_of(DEEDS, skip):
        living = living.replace(row, "")
elsewhere = [r for r in living.split("\n")
             if re.search(r"canvas\[[^\]]+\] *=", r) and "clampf" in r]
speaks = any("beliefs.conviction" in r for r in paints)
print("THE CANVAS IS REACHED %s."
      % ("only by forgetting" if canvas_only and len(elsewhere) == 1
         else "BY SOMETHING OTHER THAN FORGETTING"))
print("A FORGOTTEN DEED %s."
      % ("is said out loud" if speaks else "MOVES HIM IN SILENCE"))
if not one_door:
    fail.append("adding a deed no longer pushes the oldest one out through "
                "_forget, so the record fills up and the canvas never gets "
                "painted at all")
if not canvas_only or len(elsewhere) != 1:
    fail.append("the canvas is written in %d places; it may only ever be "
                "reached by a deed falling out of memory" % len(elsewhere))
if not speaks:
    fail.append("a deed falling out of memory no longer becomes a conviction, "
                "so the canvas is a number with no voice")

# -- THE NUMBER THAT IS WRITTEN TWICE ----------------------------------------
#
# CreatureEthos and CreatureDeeds name each other, which Godot resolves at
# runtime and refuses inside a constant -- so the ceiling is written out in
# both files instead of read from one. A number written twice is a number that
# drifts, unless something holds it.
limit = number(ETHOS, "AXIS_LIMIT")
if limit != number(DEEDS, "CANVAS_LIMIT"):
    fail.append("CreatureEthos.AXIS_LIMIT (%s) and CreatureDeeds.CANVAS_LIMIT "
                "(%s) have drifted apart, so the reading is clamped to one "
                "ceiling and the canvas to another"
                % (limit, number(DEEDS, "CANVAS_LIMIT")))

# -- AND THE CODE SAYS IT THE WAY THE MODEL ABOVE ASSUMES ---------------------
#
# Everything above this line is a MODEL of the record, and a model agrees with
# itself no matter what the game does. Put the mark-sign bug back into the
# GDScript -- a scar reading its direction off the sign of its own worth, so
# that a man-eater's worst deed made him read MORE merciful -- and every
# simulation above still passed. These read the statements instead.
reading = body_of(DEEDS, "_ring")
weighs = any("pow(absf(m), GRAVITY)" in r for r in reading)
crowds = any("+ VOICE" in r for r in reading)
marked = body_of(DEEDS, "_marked")
by_deed = any('mark.get("his"' in r or 'mark["his"]' in r for r in marked)
by_worth = any("signf" in r and "weight" in r for r in marked)
print("A MOMENTOUS DEED %s in the reading."
      % ("outweighs a routine one" if weighs and crowds
         else "COUNTS THE SAME AS A ROUTINE ONE"))
print("A SCAR CUTS %s."
      % ("the way the deed did" if by_deed and not by_worth
         else "WHICHEVER WAY ITS ARITHMETIC HAPPENS TO LAND"))
if not weighs or not crowds:
    fail.append("_ring no longer weighs a deed by what it meant (GRAVITY) and "
                "against the room it takes up (VOICE), so the reading is the "
                "plain average that could not tell four killings from one")
if by_worth or not by_deed:
    fail.append("_marked takes a scar's direction from the sign of its worth "
                "rather than from whether the deed was his own — a cruel deed "
                "and a cruel worth are both negative, so they cancel and his "
                "worst moment makes him read BETTER")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: %d deeds of record, a canvas only forgetting can reach, and a "
      "fault that dilutes without ever washing out." % MOST)
