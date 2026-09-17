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

# -- TWO PULLS, NOT ONE SPEED ------------------------------------------------
#
# A rope has two things it can do and they are different sentences. A STRONG
# tug is the player asserting — a double tap, tying off — and it must land the
# instant it is asked, because a deliberate pull answered a second and a half
# later is one the player has already decided did not work. A WEAK tug is the
# rope having MOVED, which is not an order and must not be answered like one.
hauling = body_of(ROPE, "haul")
now = any("Pull.STRONG" in r for r in hauling) \
    and any("_next_tug" in r for r in hauling)
beat = any("Pull.WEAK" in r for r in body_of(ROPE, "_process"))
print()
print("A DELIBERATE PULL is answered %s."
      % ("on the spot" if now else "ON THE NEXT BEAT — WHICH IS THE COMPLAINT"))
print("THE AMBIENT ONE is %s."
      % ("weak, on the beat" if beat else "THE SAME HAUL, ON A TIMER"))
if not now:
    fail.append("there is no immediate pull — everything waits for the tug "
                "interval, so the answer to a double tap is up to %.1fs late and "
                "the rope feels dead in the hand" % (number(ROPE, "TUG_EVERY") or 0))
if not beat:
    fail.append("the periodic tug is not the weak one, so walking about hauls "
                "the creature every beat — a hand on the scruff of the neck "
                "rather than a lead")

# AND A WEAK TUG MUST NOT MAKE IT DROP WHAT IT IS CARRYING.
LEADC2 = (ROOT / "scripts/creature/creature_lead.gd").read_text()
drops_in_spot = any("release_carried()" in r for r in body_of(LEADC2, "to_spot"))
drops_in_nudge = any("release_carried()" in r for r in body_of(LEADC2, "nudge_to"))
drops_to_fetch = any("release_carried()" in r for r in body_of(LEADC2, "to_thing"))
print("BEING LED %s what it is carrying."
      % ("keeps" if not drops_in_spot and not drops_in_nudge else "MAKES IT DROP"))
if drops_in_nudge or drops_in_spot:
    fail.append("a tug makes the creature set down what it is carrying — on a "
                "timer that is every %.1f seconds, so a creature on the lead can "
                "never carry anything across a village, which is most of what "
                "leading one is for" % (number(ROPE, "TUG_EVERY") or 0))
if not drops_to_fetch:
    fail.append("being sent to FETCH something does not free the creature's "
                "hands first, so it arrives at the thing still holding the last "
                "one")

# -- AND TRUST IS WHAT MAKES IT WORK -----------------------------------------
heeding = body_of(ROPE, "heeds")
reads_trust = any("trust" in r for r in heeding)
refuses_exile = any("exiled" in r for r in heeding)
under = number(ROPE, "WEAK_REFUSES")
above = number(ROPE, "WEAK_HEEDS")
s_under = number(ROPE, "STRONG_REFUSES")
s_above = number(ROPE, "STRONG_HEEDS")
graded = any("pull ==" in r for r in heeding)
print()
print("IT ANSWERS: %s."
      % ("on a different band for each pull" if graded and reads_trust
         else "THE SAME WAY WHATEVER YOU DID"))
if not graded:
    fail.append("both pulls are judged on one trust band, so yanking the rope "
                "is worth no more than walking — and a yank that is ignored "
                "reads as broken rather than as wilful")
if not reads_trust:
    fail.append("the rope does not read the creature's trust, so the bond you "
                "have spent the whole game building buys nothing at the one "
                "moment it should be worth the most")
if not refuses_exile:
    fail.append("the rope does not check `exiled` — CreatureLead refuses a "
                "creature that has walked away from you, and a rope that hauls "
                "it back anyway contradicts that to the player's face")
if None not in (under, above, s_under, s_above):
    print("   %-8s %-12s %-12s" % ("trust", "a yank", "the rope moving"))
    for t in (0.0, 20.0, 55.0, 80.0, 100.0):
        weak = max(0.0, min(1.0, (t - under) / max(above - under, 0.001)))
        strong = max(0.0, min(1.0, (t - s_under) / max(s_above - s_under, 0.001)))
        print("   %-8.0f %-12s %-12s %s"
              % (t, "%d%%" % (strong * 100.0), "%d%%" % (weak * 100.0),
                 "<- a new creature" if t == 55.0 else ""))
    if above <= under or s_above <= s_under:
        fail.append("a trust band is inverted or empty, so the chance of being "
                    "obeyed is not a chance at all")
    # A YANK MUST BEAT THE AMBIENT FOLLOW AT EVERY TRUST THERE IS, or the two
    # pulls are not two things.
    for t in (10.0, 30.0, 55.0, 75.0):
        weak = max(0.0, min(1.0, (t - under) / max(above - under, 0.001)))
        strong = max(0.0, min(1.0, (t - s_under) / max(s_above - s_under, 0.001)))
        if strong <= weak:
            fail.append("at trust %.0f a deliberate yank is no more likely to "
                        "land than the rope merely moving, so the strong pull "
                        "buys the player nothing" % t)
            break

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

# -- THE ROPE IS A HAND FULL -------------------------------------------------
HUD = (ROOT / "scripts/ui/hud.gd").read_text()
LEADC = (ROOT / "scripts/creature/creature_lead.gd").read_text()

casting = body_of(HAND, "_open_casting")
barred = False
for i, row in enumerate(casting):
    if "has_lead()" in row and "is_tied()" in row:
        barred = any(r.strip() == "return" for r in casting[i:i + 6])
print()
print("A LOOSE ROPE IN YOUR HAND %s casting."
      % ("bars" if barred else "DOES NOT BAR"))
if not barred:
    fail.append("a god may draw runes with the lead loose in one hand — which "
                "is a hand that is full, and the tie-it-off move exists "
                "precisely to get it back")

# AND ONLY THE BUTTON PUTS IT DOWN. Anything else and a tool you hold for
# minutes at a time can be dropped by accident, which is how you stop trusting
# it.
drops = []
for path in sorted((ROOT / "scripts").rglob("*.gd")):
    for n, row in enumerate(code(path.read_text()).split("\n")):
        # The DEFINITION is not a place it is put down; it is where it is
        # defined. Looking for the NAME rather than the CALL is the mistake this
        # codebase keeps making, and it made it again here.
        if "let_go_of_lead()" in row and not row.lstrip().startswith("func "):
            drops.append("%s:%d" % (path.name, n + 1))
print("IT IS PUT DOWN in %d place(s): %s" % (len(drops), ", ".join(drops)))
if len(drops) != 1:
    fail.append("the lead is put down in %d places — it must come off only the "
                "way it went on, or it can be dropped by accident in the middle "
                "of shepherding" % len(drops))

# AND THE ORDER OUTLIVES THE ROPE.
remembers = re.search(r"^var last_order", ROPE, re.M) is not None \
    and any("last_order = " in r for r in body_of(ROPE, "_tug"))
print("THE ORDER %s being put down."
      % ("outlives" if remembers else "IS FORGOTTEN ON"))
if not remembers:
    fail.append("the rope does not remember what it last told the creature, so "
                "putting it down unposts a beast you deliberately posted")

# -- IT IS AWAKE ON THE ROPE -------------------------------------------------
walking = body_of(LEADC, "walk")
watches = next((i for i, r in enumerate(walking) if "CreatureWatching.observe" in r),
               None)
moves = next((i for i, r in enumerate(walking) if "_move_toward(" in r), None)
print()
print("WHILE BEING LED it %s."
      % ("watches the world go by" if watches is not None and moves is not None
         and watches < moves else "SEES NOTHING UNTIL IT ARRIVES"))
if watches is None:
    fail.append("a creature on the lead never observes anything, so the one "
                "tool for showing it the world teaches it nothing")
elif moves is not None and watches > moves:
    fail.append("a creature on the lead only observes once it has ARRIVED — so "
                "being walked the length of a village teaches it nothing, which "
                "is most of what leading one is for")

# -- AND THE PANEL CLOSES, AND TAKES ITS POINTER WITH IT ---------------------
shut = body_of(HUD, "shut_the_stone")
redraws = any("queue_redraw()" in r for r in shut)
hides = any("visible = false" in r for r in shut)
# HIDING IT WHILE BUILDING IT IS NOT CLOSING IT. A panel is born hidden and
# there is no pointer drawn yet to leave behind; what matters is every hide that
# happens while the thing is on screen.
def _inside(text, line_no):
    """The function a given line sits in."""
    here = "(top level)"
    for n, row in enumerate(text.split("\n")):
        found = re.match(r"^(?:static\s+)?func (\w+)\(", row)
        if found:
            here = found.group(1)
        if n + 1 >= line_no:
            return here
    return here


closers = 0
for _n, _row in enumerate(HUD.split("\n")):
    if "_stone_panel.visible = false" not in _row:
        continue
    _where = _inside(HUD, _n + 1)
    if _where != "shut_the_stone" and not _where.startswith("_build"):
        closers += 1
print()
print("CLOSING THE PANEL %s its pointer."
      % ("redraws away" if redraws and hides else "LEAVES"))
if not (redraws and hides):
    fail.append("shutting the info panel does not ask its pointer to repaint — "
                "a Control only repaints when told, so the last triangle it drew "
                "stays over the world for the rest of the session")
# ANY of them, not "more than one". A single runtime hide outside the closer is
# the whole bug: that is precisely what `_tick_stone` used to do, and it left
# the triangle painted over the world every single time the panel timed out.
if closers > 0:
    fail.append("%d place(s) hide the info panel at runtime without going "
                "through the one closer, and every one of them leaves the "
                "pointer painted over the world" % closers)

tapped = body_of(HAND, "_tapped_twice")
closes = any("shut_the_stone()" in r for r in tapped)
print("A DOUBLE TAP %s an open panel." % ("closes" if closes else "DOES NOT CLOSE"))
if not closes:
    fail.append("nothing closes an info panel but walking away from it")

# AND WITH THE ROPE IN HAND IT IS THE STRONG TUG. The user's words: "Strong Tug,
# which is the multi-tapping and attaching". A double tap that only turned the
# creature's head would be a look, not a pull.
yanks = any("haul(" in r for r in tapped)
print("   ...and with the rope in hand it %s."
      % ("hauls" if yanks else "ONLY TURNS ITS HEAD"))
if not yanks:
    fail.append("a double tap with the lead in hand does not pull the rope — "
                "the multi-tap IS the strong tug, and without the haul it is a "
                "glance the creature may do nothing about")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: one rope, one door, paced tugs, trust decides, and what opens shuts.")
