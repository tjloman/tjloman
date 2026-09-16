#!/usr/bin/env python3
"""THE SKY SIGIL IS A NUMBER, AND A NUMBER HAS TO BE PAID FOR.

Every other rune in the book is a thing in the world -- water, fire, fury, the
ground. `sky` alone still is one: a flock of birds. Put it with anything else
and it stops being a noun and becomes a COUNT, because that is what a sky full
of something means. Three fires and a fury is one great exploding gout; three
fires, a fury and a sky is a volley of them, which is Dragon's Claws.

A rune that means "more of it" is the one rune that can quietly break the
economy, and there are four ways for it to do that:

  IT BECOMES FREE. If `_cost_of` never reads the count, one extra stroke makes
  seven fireballs for the price of one, for ever. The sigil is a shortcut
  through the DRAWING -- which is the thing a god has too little of in the
  middle of a fight -- and through nothing else.

  IT BECOMES UNBOUNDED. A count that is not clamped where it is written is a
  count that is clamped nowhere, and a caught volley builds up.

  IT FANS TWICE. The mark has to be SPENT at the throw. A ball caught out of
  the air and hurled back carries a mark; if the first one keeps its own, one
  drawing seeds a volley every time anything lands.

  IT FANS WHEN NOTHING WAS THROWN. Setting a working down gently is not a
  volley, and a hand that opened over the town square must not birth six more.

And the OTHER half of the same request: three sizes of fireball. `_make_orb`
handed the potency to every orb in the game except the fireball, which built
itself from `kind` alone -- so three fires cost two and a half times one fire
and threw exactly the same ball. That line is checked here by the STATEMENT
that assigns it, not by the word `potency` appearing somewhere nearby.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BOOK = (ROOT / "scripts/miracles/spellbook.gd").read_text()
MANAGER = (ROOT / "scripts/miracles/miracle_manager.gd").read_text()
BALL = (ROOT / "scripts/miracles/fireball.gd").read_text()
FAN = (ROOT / "scripts/miracles/volley.gd").read_text()
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()


def code(text):
    """Source with its comments taken out. A note about a thing is not it."""
    return "\n".join(r.split("#")[0].rstrip() for r in text.split("\n")
                     if r.split("#")[0].strip())


def body_of(text, name):
    """The rows of one function, comments already gone."""
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


def under(rows, guard, needle):
    """True when `needle` is written INSIDE the block opened by `guard`.

    Not "both appear in this function" -- that is the unfalsifiable shape this
    codebase keeps relearning. The guard's own indent is measured, and the
    needle has to come after it and still be deeper than it.
    """
    depth = None
    for row in rows:
        bare = row.strip()
        if not bare:
            continue
        indent = len(row) - len(row.lstrip("\t"))
        if depth is not None and indent <= depth:
            depth = None
        if depth is not None and needle in row:
            return True
        if guard in row:
            depth = indent
    return False


def number(text, name):
    found = re.search(r"^const %s := ([-\d.]+)" % name, text, re.M)
    return float(found.group(1)) if found else None


## As wide as the fan may ever open. Past a quarter turn the ends of a volley
## are thrown sideways rather than at anything.
FAN_CEILING = 90.0

fail = []

# The three sizes of fire, read once: the fan needs them to check its spacing
# and the ladder needs them to check its rungs.
hefts = [(float(a), float(b)) for a, b in
         re.findall(r'\{"from": ([\d.]+), "grows": ([\d.]+)', BALL)]
ball_r = float(re.search(r"shape\.radius = ([\d.]+) \* grew", BALL).group(1))

# -- ONE SKY IS A BIRD; A SKY AND ANYTHING ELSE IS A COUNT -------------------
rows = body_of(BOOK, "interpret")
# THE ROW THAT OPENS THE COUNT, read as the condition it is rather than as the
# word `skies` turning up somewhere in the function.
opens = next((r.strip() for r in rows if r.strip().startswith("if skies")), "")
counts = bool(opens) and under(rows, opens, 'many["volley"]')
print("A DRAWING WITH SKY IN IT %s."
      % ("is read as a count of what is left"
         if counts else "IS NOT READ AS A COUNT AT ALL"))
if not counts:
    fail.append("Spellbook.interpret does not turn a sky into a count, so the "
                "sigil is a bird and Dragon's Claws is one fireball")
# AND THE BRANCH HAS TO REFUSE A DRAWING THAT IS ALL SKY. Stripping the skies
# out of `sky` leaves nothing to be three of: the flock would simply vanish.
alone = re.search(r'"sky": "(\w+)"', BOOK)
lone_ok = "skies > 0" in opens and "skies < runes.size()" in opens
print("A SKY ON ITS OWN is still %s." % (alone.group(1) if alone else "NOTHING"))
if not alone:
    fail.append("`sky` has no meaning of its own left, so one stroke of it "
                "casts nothing")
if not lone_ok:
    fail.append("the count branch is guarded by `%s`, which does not require "
                "that something other than sky was drawn — so a lone sky is "
                "stripped to an empty drawing and the flock is gone"
                % (opens or "nothing"))

at_one = number(BOOK, "VOLLEY_AT_ONE")
per = number(BOOK, "VOLLEY_PER_EXTRA")
most = number(BOOK, "VOLLEY_MOST")
each = number(BOOK, "VOLLEY_EACH")
if None in (at_one, per, most, each):
    print("BROKEN: the volley constants are not all in the spellbook")
    sys.exit(1)

print()
print("HOW MANY, by skies drawn:")
for skies in range(1, 6):
    print("   %d sky%-4s %d projectile(s)"
          % (skies, "" if skies == 1 else "s",
             min(at_one + (skies - 1) * per, most)))

# -- AND IT IS PAID FOR, PER PROJECTILE -------------------------------------
priced = body_of(MANAGER, "_cost_of")
# THE STATEMENT, not the word. `volley` appearing in a comment, in a variable
# that is never used, or in a line that reads it and throws it away are all
# things that look like a price and are not one.
charges = any(re.search(r"price \*?= .*VOLLEY_EACH", r) for r in priced)
print()
print("THE PRICE %s with the count." % ("rises" if charges else "DOES NOT MOVE"))
if not charges:
    fail.append("_cost_of never multiplies the price by the count, so one "
                "extra stroke makes seven fireballs for the price of one")
else:
    print("   each past the first costs %.0f%% of full price" % (each * 100.0))
    print("   %-14s %-10s %s" % ("projectiles", "price", "per projectile"))
    last = 0.0
    for many in sorted({int(min(at_one + (s - 1) * per, most))
                        for s in range(1, 6)} | {1}):
        mult = 1.0 + (many - 1) * each
        print("   %-14d x%-9.2f x%.2f" % (many, mult, mult / many))
        if mult <= last:
            fail.append("a volley of %d costs no more than a smaller one" % many)
        if many > 1 and mult >= many:
            fail.append("a volley of %d costs at least %d separate casts, so "
                        "the sigil is a tax rather than a shortcut" % (many, many))
        if many > 1 and mult <= 1.0:
            fail.append("a volley of %d costs no more than a single cast" % many)
        last = mult

# The price has to be taken BEFORE the working is conjured, or the check above
# is a number nobody spends.
cast = body_of(MANAGER, "cast_runes")
spent = next((i for i, r in enumerate(cast) if "try_spend" in r), None)
made = next((i for i, r in enumerate(cast) if "_conjure_reading" in r), None)
print("   the prayer is taken %s the volley is conjured"
      % ("before" if spent is not None and made is not None and spent < made
         else "AFTER, OR NOT AT ALL,"))
if spent is None or made is None or spent > made:
    fail.append("cast_runes conjures the working before it takes the prayer")

# -- THE COUNT IS CLAMPED WHERE IT IS WRITTEN -------------------------------
marking = body_of(FAN, "mark")
clamped = any("clampi(" in r and "VOLLEY_MOST" in r for r in marking)
print()
print("THE COUNT IS %s." % ("clamped where it is written"
                            if clamped else "UNBOUNDED"))
if not clamped:
    fail.append("Volley.mark does not clamp, so a caught volley grows without "
                "limit and seven becomes seventy")
# And nothing writes the mark behind its back.
loose = []
for name, text in [("fireball.gd", BALL), ("miracle_manager.gd", MANAGER),
                   ("divine_hand.gd", HAND)]:
    if re.search(r'set_meta\(\s*(Volley\.MARK|"volley")', code(text)):
        loose.append(name)
print("   written directly by: %s" % (", ".join(loose) if loose else "nobody"))
if loose:
    fail.append("%s writes the volley mark directly instead of through "
                "Volley.mark, so it goes round the clamp" % ", ".join(loose))

# -- IT FANS ONCE, AND ONLY ON A THROW --------------------------------------
fanning = body_of(FAN, "fan")
spends = next((i for i, r in enumerate(fanning)
               if re.search(r"set_meta\(MARK, 1\)", r)), None)
loops = next((i for i, r in enumerate(fanning) if "for i in range(1, many)" in r),
             None)
print()
print("THE MARK IS %s." % ("spent before the fan opens"
                           if spends is not None and loops is not None
                           and spends < loops else "NOT SPENT"))
if spends is None or loops is None or spends > loops:
    fail.append("Volley.fan does not spend the mark before it fans, so one "
                "drawing seeds a volley every time anything is thrown again")
if loops is None:
    fail.append("Volley.fan does not make exactly one fewer twin than the "
                "count, so the volley is the wrong size")

# HOW WIDE THE WALL IS, off the shipped fan. A god throwing forty metres wants
# to know whether a volley of seven is a line abreast or a circle around them.
spread = number(FAN, "SPREAD_DEG")
widest = number(FAN, "SPREAD_MOST")
print()
print("THE FAN, at a forty-metre throw:")
for many in sorted({int(min(at_one + (s - 1) * per, most)) for s in range(1, 6)}):
    step_deg = min(spread, widest / float(many - 1))
    arc = step_deg * (many - 1)
    edge = 2.0 * 40.0 * math.sin(math.radians(arc / 2.0))
    print("   %d abreast   %.1f° apart  ·  %.0f° of arc  ·  %.0fm wall  ·  "
          "%.0fm between neighbours" % (many, step_deg, arc, edge, edge / (many - 1)))
    if edge / (many - 1) < ball_r * 2.0 * hefts[-1][1]:
        fail.append("a volley of %d lands closer together than the fire is "
                    "wide, so it is one smear rather than a wall" % many)
if not spread or spread <= 0.0 or not widest or widest > FAN_CEILING:
    fail.append("the fan opens %s degrees: past a quarter turn the outer "
                "projectiles are thrown sideways rather than at anything, and "
                "the volley is a ring round the player"
                % (("%.0f" % widest) if widest else "no"))

# AND THEY ARE BORN CLEAR OF ONE ANOTHER. Two spheres spawned overlapping shove
# each other apart at whatever speed the solver picks, which reads as the volley
# going off in the player's face. The greatest fire is nearly twice the width of
# the smallest, so this is asked of every rung.
apart = number(FAN, "APART")
least = number(FAN, "APART_LEAST")
print("   born apart:", end=" ")
for i, (_frm, grows) in enumerate(hefts):
    wide = ball_r * grows
    gap = max(least, wide * apart)
    print("rung %d %.2fm across in a %.2fm gap%s"
          % (i, wide * 2.0, gap, ";" if i < len(hefts) - 1 else ""), end=" ")
    if gap <= wide * 2.0:
        fail.append("a volley of rung %d is born overlapping — %.2fm of ball "
                    "in a %.2fm gap — so it shoves itself apart in the "
                    "player's face" % (i, wide * 2.0, gap))
print()

released = body_of(HAND, "_release_body")
# ONE CALL, AND IT IS INSIDE THE THROW. Both halves matter: a fan moved out of
# the branch and a SECOND fan added beside it break the same rule, and only
# counting them catches the second.
opens_hand = sum(r.count("Volley.fan") for r in released)
only_thrown = opens_hand == 1 and under(released, "if not gentle:", "Volley.fan")
print("IT FANS %s." % ("only on a real throw" if only_thrown
                       else "WHENEVER THE HAND OPENS"))
if not only_thrown:
    fail.append("DivineHand fans the volley %d time(s), not once inside the "
                "`not gentle` branch — so setting a working down gently births "
                "six more of it" % opens_hand)

# -- THREE SIZES OF FIRE, AND THE DRAWING SAYS WHICH ------------------------
step = number(BOOK, "REPEAT_RUNG") or 0.0
print()
print("SIZES OF FIRE: %d" % len(hefts))
if len(hefts) < 3:
    fail.append("there are fewer than three sizes of fire, and the player "
                "asked for three")
if any(hefts[i][1] <= hefts[i - 1][1] for i in range(1, len(hefts))):
    fail.append("a larger rung of fire does not grow the ball, so two of the "
                "sizes are the same size")

# The potency the spellbook actually produces for one, two and three fires,
# against the rungs the fireball actually reads.
reach = float(re.search(r'"fireball": \{\s*"reach": ([\d.]+)', BALL).group(1))
hurt = float(re.search(r'"fireball": \{[^}]*"hurt": ([\d.]+)', BALL).group(1))
lands = []
for fires in (1, 2, 3):
    potency = 1.0 + (fires - 1) * step
    which = max(i for i, (frm, _g) in enumerate(hefts) if potency >= frm)
    grows = hefts[which][1]
    lands.append(which)
    print("   %d fire%-3s potency %.2f  ->  rung %d  ·  reach %.1fm  hurt %.0f"
          % (fires, "" if fires == 1 else "s", potency, which,
             reach * grows, hurt * grows))
if len(set(lands)) < 3:
    fail.append("one, two and three fires do not land on three different "
                "sizes: the ladder is %s, so a drawing costing two and a half "
                "times as much throws the same ball" % lands)

# AND THE BALL ACTUALLY READS ITS RUNG. A size table nothing consults is a
# comment: `grew` has to come off the potency, and every number that makes a
# fire dangerous has to come off `grew`.
readying = body_of(BALL, "_ready")
sized = any(re.match(r"\s*grew = ", r) and ("HEFTS" in r or "rung()" in r)
            for r in readying)
burst = body_of(BALL, "_go_off")
raw = [k for k in ("reach", "kill", "hurt", "house")
       if not any('heft("%s")' % k in r for r in burst)]
print("   the ball's size %s the rung it landed on."
      % ("comes off" if sized else "IS FIXED AND IGNORES"))
if not sized:
    fail.append("Fireball never reads its own rung, so the size table is a "
                "comment and every fire is the same fire")
if raw:
    fail.append("the burst reads %s straight off the KINDS row rather than "
                "through `heft`, so a greater fire is no more dangerous than a "
                "gout" % ", ".join(raw))

# AND THE POTENCY ACTUALLY REACHES THE BALL. This is the statement that did not
# exist: the fireball branch of _make_orb read `kind` and nothing else.
orbed = body_of(MANAGER, "_make_orb")
carried = under(orbed, "Fireball.KINDS.has(miracle)",
                re.sub(r"\s+", "", "ball.potency = potency"))
carried = carried or under(orbed, "Fireball.KINDS.has(miracle)", "ball.potency =")
print("   the drawing's potency %s the ball."
      % ("reaches" if carried else "IS DROPPED ON THE FLOOR BEFORE IT REACHES"))
if not carried:
    fail.append("_make_orb builds a fireball without giving it the potency, so "
                "every fire is the same size whatever it cost")

# -- FIRE CATCHES FIRE, AND ONLY FIRE ---------------------------------------
catching = body_of(BALL, "_try_catch")
in_hand = any("held_body as Fireball" in r for r in catching)
closing = any("linear_velocity.dot(" in r for r in catching)
process = body_of(BALL, "_physics_process")
armed = under(process, "if _armed:", "_try_catch()")
frozen = next((i for i, r in enumerate(process) if "if freeze:" in r), None)
tried = next((i for i, r in enumerate(process) if "_try_catch()" in r), None)
print()
print("TO CATCH ONE you must %s."
      % ("already be holding fire" if in_hand else "DO NOTHING AT ALL"))
print("   and it must be %s you."
      % ("coming at" if closing else "ANYWHERE NEAR — INCLUDING ROLLING AWAY FROM"))
print("   a ball in the grip %s."
      % ("cannot catch" if frozen is not None and tried is not None
         and frozen < tried else "CAN CATCH"))
if not in_hand:
    fail.append("a fireball is caught without holding one, so an empty hand "
                "cannot be hit by fire at all")
if not closing:
    fail.append("the catch does not ask whether the ball is closing, so the "
                "hand swallows its own spent throws rolling past")
if not armed:
    fail.append("the catch is asked outside the armed branch, so a ball that "
                "was never thrown can be caught")
if frozen is None or tried is None or frozen > tried:
    fail.append("a frozen ball is asked to catch, so a ball in the grip eats "
                "the one beside it")

# -- AND THE DRAWING THE PLAYER ACTUALLY ASKED FOR --------------------------
#
# `/ / / Z ^`: three flames, a Z and a peak. Walked here off the shipped
# constants rather than asserted, because the whole point of a grammar is that
# nobody wrote this combination down anywhere -- it has to FALL OUT.
RECIPES = BOOK[BOOK.index("const RECIPES"):BOOK.index("const COMBO_MULTIPLIER")]
recipes = dict(re.findall(r'"([a-z+_]+)": "(\w+)"', RECIPES))
gestures = dict(re.findall(r'"(\w+)": "(\w+)"',
                           BOOK[BOOK.index("const RUNE_OF"):BOOK.index("const AGAIN")]))
claws = ["dline", "dline", "dline", "zed", "bend_up"]
drawn = [gestures.get(g, "?") for g in claws]
skies = drawn.count("sky")
rest = [r for r in drawn if r != "sky"]
distinct = sorted(set(rest))
named = recipes.get("+".join(sorted(rest))) or recipes.get("+".join(distinct))
potency = 1.0 + (len(rest) - len(distinct)) * step
many = int(min(at_one + (skies - 1) * per, most))
print()
print("DRAGON'S CLAWS  ·  / / / Z ^")
print("   reads as     %s" % " + ".join(drawn))
print("   which is     %s at potency %.2f, %d of them"
      % (named or "NO NAMED WORKING", potency, many))
if named:
    grows = hefts[max(i for i, (frm, _g) in enumerate(hefts) if potency >= frm)][1]
    span = float(re.search(r'"fireblast": \{\s*"reach": ([\d.]+)', BALL).group(1))
    price = float(re.search(r'"%s": \{"cost": ([\d.]+)' % named, MANAGER).group(1))
    one = price * (1.0 + (potency - 1.0) * 0.7)
    print("   each one      %.1fm across" % (span * grows))
    print("   and it costs  %.0f prayer (%.0f for one of them, %.0f for a "
          "plain %s)" % (one * (1.0 + (many - 1) * each), one, price, named))
# AND THE GRAMMAR HAS TO ACTUALLY DO THIS. The walk above models rule 3 in
# Python; without the STATEMENT that implements it, the model is a wish.
keyed = any(re.search(r"named :?= key_for\(distinct\)", r) for r in rows)
harder = keyed and under(rows, "if RECIPES.has(named):", "REPEAT_RUNG")
print("   a name said harder %s."
      % ("climbs the same ladder one rune does"
         if harder else "IS NOT A RULE THE SPELLBOOK HAS"))
if not harder:
    fail.append("Spellbook.interpret has no rule for a NAMED combination drawn "
                "with repeats, so `fire fire fire fury` blends into odds and "
                "ends instead of becoming the greatest blast")
if named != "fireblast":
    fail.append("`/ / / Z ^` does not read as a fireblast — it reads as %s — "
                "so the drawing the player asked for is not the drawing they "
                "get" % (named or "a blend of odds and ends"))
elif max(i for i, (frm, _g) in enumerate(hefts) if potency >= frm) != len(hefts) - 1:
    fail.append("`/ / / Z ^` does not reach the largest size of fire, so three "
                "flames buys the same blast two flames does")
elif many < at_one:
    fail.append("`/ / / Z ^` throws fewer than %d, so the sky in it bought "
                "nothing" % at_one)

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: the sky is a count, the count is paid for, and fire comes in three "
      "sizes.")
