#!/usr/bin/env python3
"""THE LEAD IS A THING YOU HOLD, NOT A SENTENCE YOU SAY.

It used to be a command. Press a key and the creature was told, once, to go
somewhere — and then the telling was over and there was nothing in the world to
show for it. That is a command line with a button on it, and it is why the most
important tool in the game did not feel like a tool: nothing to hold, nothing to
pull against, and no way to say "not there, HERE" except by saying the whole
sentence again.

Now one end of it is in your hand. What this file guards is the handful of ways
that goes quietly wrong.

  TWO DOORS. The key and the on-screen button were two separate copies of the
  lead's behaviour. A rewrite of one leaves the other doing the old thing on the
  machine where it matters most — which is exactly how a dock came to be built
  on grass by one path while the other put it on the water.

  TWO ROPES. A creature has one lead. Picking it up twice while one is already
  tied somewhere leaves two of them in the world, both tugging, and the beast is
  pulled between them.

  A ROPE THAT IS NOT A ROPE. If the tug fires every frame the creature never
  finishes a stride; if trust does not gate it, the bond you have spent the
  whole game building buys nothing at the one moment it should be worth most.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ROPE = (ROOT / "scripts/creature/lead_rope.gd").read_text()
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()
MAIN = (ROOT / "scripts/main.gd").read_text()
TOUCH = (ROOT / "scripts/ui/touch_controls.gd").read_text()


def code(text):
    """Source with its comments taken out. A note about a thing is not it."""
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


fail = []

# -- ONE DOOR ----------------------------------------------------------------
takes = body_of(MAIN, "_take_the_lead")
button = body_of(TOUCH, "_on_leash_pressed")
one_door = bool(takes) and any("leash_creature" in r for r in button) \
    and not any("leash_to" in r for r in button)
print("THE BUTTON AND THE KEY go through %s."
      % ("one door" if one_door else "TWO SEPARATE COPIES"))
if not takes:
    fail.append("Main._take_the_lead does not exist, so there is no one place "
                "the lead is picked up")
if not one_door:
    fail.append("the on-screen button does not fire the same action the key "
                "does — it keeps its own copy of what the lead means, and a "
                "phone is the machine where that copy is the one that runs")

# -- ONE ROPE ----------------------------------------------------------------
reuses = any("_rope_on(" in r for r in takes)
print("PICKING IT UP TWICE %s."
      % ("finds the rope already there" if reuses else "MAKES A SECOND ROPE"))
if not reuses:
    fail.append("taking up the lead does not look for the rope the creature "
                "already has, so a second one is made every time and the beast "
                "is tugged by both")

# -- IT IS A ROPE, NOT A VOLLEY OF ORDERS ------------------------------------
every = number(ROPE, "TUG_EVERY")
moved = number(ROPE, "TUG_IF_MOVED")
length = number(ROPE, "ROPE_LENGTH")
ticking = body_of(ROPE, "_process")
paced = any("_next_tug" in r for r in ticking)
print()
print("THE ROPE TUGS every %.1fs, and only once the hand has moved %.1fm."
      % (every or 0.0, moved or 0.0))
if not paced or not every:
    fail.append("the rope re-orders the creature every frame — a beast told "
                "again sixty times a second never finishes a stride, and what "
                "you would be holding is a stutter, not a lead")
if every and every > 4.0:
    fail.append("a tug every %.0f seconds is not a lead, it is a telegram — "
                "the hand moves and nothing happens for most of a walk" % every)
if not moved:
    fail.append("the rope tugs whether or not the hand has gone anywhere, so "
                "standing still re-orders the creature for ever")

# -- AND TRUST IS WHAT MAKES IT WORK -----------------------------------------
heeding = body_of(ROPE, "heeds")
reads_trust = any("trust" in r for r in heeding)
refuses_exile = any("exiled" in r for r in heeding)
under = number(ROPE, "REFUSES_UNDER")
above = number(ROPE, "HEEDS_ABOVE")
print("IT COMES WHEN THE ROPE MOVES: %s."
      % ("as much as it trusts you" if reads_trust else "ALWAYS, WHATEVER IT THINKS"))
if not reads_trust:
    fail.append("the rope does not read the creature's trust, so the bond you "
                "have spent the whole game building buys nothing at the one "
                "moment it should be worth the most")
if not refuses_exile:
    fail.append("the rope does not check `exiled` — CreatureLead refuses a "
                "creature that has walked away from you, and a rope that hauls "
                "it back anyway contradicts that to the player's face")
if under is not None and above is not None:
    print("   %-10s %-12s %s" % ("trust", "comes", ""))
    for t in (0.0, 25.0, 55.0, 80.0, 100.0):
        odds = max(0.0, min(1.0, (t - under) / max(above - under, 0.001)))
        print("   %-10.0f %-12s %s" % (t, "%d%%" % (odds * 100.0),
                                       "<- a new creature" if t == 55.0 else ""))
    if above <= under:
        fail.append("the trust band is inverted or empty, so the chance of "
                    "being obeyed is not a chance at all")

# -- A HAND WITH A ROPE IN IT IS DOING ONE THING -----------------------------
press = body_of(HAND, "_on_pointer_button")
guarded = False
for i, row in enumerate(press):
    if "has_lead()" in row:
        guarded = any(r.strip() == "return" for r in press[i:i + 8])
print()
print("A HAND HOLDING THE LEAD %s."
      % ("does not also grab" if guarded else "STILL GRABS AND PANS"))
if not guarded:
    fail.append("the press handler does not hand the pointer to the lead — so "
                "tying the rope, grabbing a villager and dragging the camera "
                "are all the same gesture and none of them is reliable")

ties = body_of(HAND, "_tick_tying")
lets_go = any("tie(null)" in r or "tie(onto)" in r for r in ties)
print("   a hold %s it off, and a hold on bare earth unties it."
      % ("ties" if lets_go else "DOES NOTHING"))
if not lets_go:
    fail.append("holding the pointer down does not tie the rope, which is the "
                "whole of how slack is set")

# -- THE FORGIVING PICK, which is what makes tying it to a villager possible --
sweep = body_of(HAND, "_nearly_under")
after_ray = False
hover = body_of(HAND, "_update_hover")
for i, row in enumerate(hover):
    if "_nearly_under(" in row:
        after_ray = any("hover_target == null" in r for r in hover[max(0, i - 3):i + 1])
print()
print("THE HAND %s for a thing when the ray finds only earth."
      % ("looks around" if sweep and after_ray else "DOES NOT LOOK"))
if not sweep:
    fail.append("there is no forgiving pick, so taking hold of a villager is "
                "hitting a capsule half a metre wide with an infinitely thin "
                "ray, on a touchscreen")
if sweep and not after_ray:
    fail.append("the forgiving sweep runs even when the ray hit something — it "
                "must only be a fallback, or pointing AT a thing stops meaning "
                "what it says")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: one rope, one door, paced tugs, and trust decides.")
