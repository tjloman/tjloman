#!/usr/bin/env python3
"""THE TURNING SIGIL IS A SHORTCUT THROUGH THE DRAWING, NEVER THROUGH THE PRICE.

The fourth bend was deliberately unspoken for a long time -- a real, reliable
shape with nothing bound to it, kept empty rather than filled with a noun the
grammar did not need. What the grammar needed turns out not to be a noun: it is
Black & White's R key. The hand is busy, the thing you want is the thing you
just did, and redrawing five strokes to get it is five strokes of not watching.

A repeat is the one rune whose meaning is HISTORY rather than a thing in the
world, and that makes two ways for it to go quietly wrong:

  IT BECOMES FREE. `cast_runes` takes the prayer, checks the cap and checks
  that you know every rune involved. A repeat that skipped any of that would be
  a way to cast a tempest for nothing, for ever, by drawing one stroke -- and
  it would look like a convenience.

  IT BECOMES A LOOPHOLE. The repeat must be the RUNES you drew, put back
  through the same door. Remembering the finished reading instead would let a
  working survive its own conditions: cast while you held five villages, said
  again after losing four.

And the sigil has to still be a sigil. It is stored as a gesture (`bend_left`)
and read as a rune (`again`), and the two names have to keep pointing at each
other or the stroke lands on the slate as nothing.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BOOK = (ROOT / "scripts/miracles/spellbook.gd").read_text()
MANAGER = (ROOT / "scripts/miracles/miracle_manager.gd").read_text()
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()


def code(text):
    """Source with its comments taken out. A note about a thing is not it."""
    return "\n".join(r.split("#")[0].rstrip() for r in text.split("\n")
                     if r.split("#")[0].strip())


def body_of(text, name):
    src = code(text)
    head = "func %s(" % name
    if head not in src:
        return ""
    out = []
    for row in src[src.index(head):].split("\n")[1:]:
        if row and not row.startswith(("\t", " ")):
            break
        out.append(row)
    return "\n".join(out)


fail = []

# -- THE SIGIL STILL POINTS AT A RUNE ---------------------------------------
shape = re.search(r'^const UNSPOKEN := "(\w+)"', BOOK, re.M)
rune = re.search(r'^const AGAIN := "(\w+)"', BOOK, re.M)
mapped = re.search(r'"(\w+)": "again"', BOOK)
print("THE SIGIL: %s is drawn as %s and read as %s."
      % (rune.group(1) if rune else "?", shape.group(1) if shape else "?",
         '"%s"' % mapped.group(1) if mapped else "NOTHING"))
if not (shape and rune and mapped and mapped.group(1) == shape.group(1)):
    fail.append("the turning sigil's shape and its rune do not point at each "
                "other, so the stroke lands on the slate as nothing")

# -- AND THE HAND LETS IT THROUGH -------------------------------------------
# It used to be intercepted before it could ever become a rune, with a hint
# saying it had no working bound to it. It has one now.
refused = "gesture == Spellbook.UNSPOKEN" in code(HAND)
print("THE HAND %s it reach the slate." % ("REFUSES to let" if refused else "lets"))
if refused:
    fail.append("DivineHand still intercepts the turning sigil before it can "
                "become a rune, so nothing downstream will ever see it")

# -- IT GOES BACK THROUGH THE SAME DOOR -------------------------------------
cast = body_of(MANAGER, "cast_runes")
head = cast[:cast.index("var reading")] if "var reading" in cast else cast
takes_runes = "_said_before()" in head or "_said" in head
print()
print("A REPEAT %s before the drawing is interpreted."
      % ("replaces the runes" if takes_runes else "IS NOT HANDLED"))
if not takes_runes:
    fail.append("cast_runes does not turn a repeat back into runes before it "
                "interprets the drawing, so the sigil means nothing")

# Everything after that point must still run: the price, the cap, the rudiments.
tail = cast[cast.index("var reading"):] if "var reading" in cast else ""
for what, needle, why in [
        ("the rudiments", "known_runes()", "a repeat could cast a rune you have "
         "since forgotten how to draw"),
        ("the cap", "max_prayer_power", "a repeat could hold a working your "
         "flock is too small for"),
        ("the price", "try_spend", "a repeat would be FREE -- one stroke, a "
         "tempest, for ever")]:
    ok = needle in tail
    print("   %-16s %s" % (what, "checked" if ok else "SKIPPED"))
    if not ok:
        fail.append("a repeat skips %s: %s" % (what, why))

# -- AND IT IS RUNES THAT ARE REMEMBERED, NOT A READING ---------------------
remembers = re.search(r"_said = (\w+)", code(MANAGER))
print()
print("WHAT IS REMEMBERED: %s." % (remembers.group(1) if remembers else "NOTHING"))
if not remembers:
    fail.append("nothing is remembered, so there is never anything to repeat")
elif remembers.group(1) != "runes":
    fail.append("a finished reading is remembered rather than the runes, so a "
                "working could outlive its own conditions — cast while you held "
                "five villages, repeated after losing four")

# -- A WORD ON ITS OWN ------------------------------------------------------
print()
mixes = "runes.has(AGAIN)" in code(BOOK)
print("MIXED WITH ANYTHING ELSE it %s."
      % ("means nothing" if mixes else "IS SILENTLY DROPPED"))
if not mixes:
    fail.append("Spellbook.interpret does not refuse a drawing containing the "
                "turning sigil, so `again + water` quietly casts rain")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: a shortcut through the drawing, and through nothing else.")
