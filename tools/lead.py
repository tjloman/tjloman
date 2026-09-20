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

  AND A ROPE NO LONGER THAN A ROPE. The rope drew itself between its two ends
  whatever the gap, and the gap has no natural limit: the hand is wherever the
  camera looks, so holding the lead and scrolling across the valley put three
  kilometres between the ends and drew six five-hundred-metre cylinders through
  the world every frame. Nothing about that is visible as a bug in the code --
  the sag is capped, the link count is fixed, every number in sight is small --
  and on screen it is the shearing that has been chased for weeks. It matters
  twice over now, because a creature summoned through a portal IS three
  thousand metres away, right up until it is standing at the post.

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

# -- AND THERE IS ALWAYS A WAY OFF IT ----------------------------------------
#
# A lead that is up narrows the whole game to one tool: a hand holding it does
# not read the stone, does not grab and does not cast. So the way out cannot be
# a key, because a phone has none — and it cannot be only the Lead button
# either, which toggles the rope in your HAND rather than taking it off the
# beast. It goes on the screen that is about the creature.
HUD2 = (ROOT / "scripts/ui/hud.gd").read_text()
on_screen = "_unlead_button" in code(HUD2) \
    and any("take_the_lead_off(" in r for r in body_of(HUD2, "_on_unlead_pressed"))
clickable = any("MOUSE_FILTER_STOP" in r for r in body_of(HUD2, "_build_unlead_button"))
# AND IT IS OFFERED WHENEVER THERE IS A ROPE, not only while one is in your
# hand. The case this button exists for is the rope you have LOST TRACK OF —
# and a rope you have lost track of is a rope that is tied to something, which
# is exactly the state `has_lead` is false in. Gating the one way out on the
# hand takes it away in the only case that needed it.
panel = "\n".join(body_of(HUD2, "_update_creature_panel"))
offered = ""
if "_unlead_button.visible" in panel:
    offered = panel[panel.index("_unlead_button.visible"):][:200]
asks_for_a_rope = "LeadRope.on(" in offered and "has_lead()" not in offered
print()
print("THE LEAD COMES OFF from the creature screen: %s%s"
      % ("yes" if on_screen else "NO",
         "" if clickable else ", BUT THE BUTTON CANNOT BE CLICKED"))
if not on_screen:
    fail.append("there is no way to take the lead off but a key and the Lead "
                "button — and a lead that is up stops the hand reading, "
                "grabbing and casting, so a player who loses track of the rope "
                "has no way back")
if not clickable:
    fail.append("the unlead button is inside a panel that is made click-through "
                "after it is built, so the one way out of the lead cannot be "
                "pressed")
print("   ...and it is offered %s."
      % ("whenever the creature has a rope at all" if asks_for_a_rope
         else "ONLY WHILE THE ROPE IS IN YOUR HAND"))
if not asks_for_a_rope:
    fail.append("the way off the lead is only shown while the rope is in your "
                "hand — but the case it exists for is the rope you have lost "
                "track of, and a lost rope is a TIED one, which is the one "
                "state the hand is empty in")

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
# -- A ROPE NO LONGER THAN A ROPE -------------------------------------------
#
# The check is on the DRAWN span, not on the gap: the two ends may be any
# distance apart -- that is what a summons is -- and what may not happen is a
# link being drawn across it.
drawing = body_of(ROPE, "_draw_between")
capped = any("span > length" in r for r in drawing)
short = any("normalized() * length" in r for r in drawing)
walks = [r for r in drawing if "lerp(b," in r]
print()
print("THE DRAWN ROPE IS %s."
      % ("never longer than the rope" if capped and short and not walks
         else "AS LONG AS THE GAP HAPPENS TO BE"))
LENGTH = number(ROPE, "ROPE_LENGTH")
LINKS = number(ROPE, "LINKS")
if LENGTH and LINKS:
    print("   ends 2m apart: %.2fm a link.  Ends 3km apart: %.2fm a link "
          "(it was %.0fm)." % (2.0 / LINKS, LENGTH / LINKS, 3000.0 / LINKS))
if not capped or not short:
    fail.append("the rope still draws itself across whatever gap there is, so "
                "a hand scrolled across the valley stretches six links over "
                "kilometres and the camera ends up inside their bounding "
                "boxes")
if walks:
    fail.append("a link is still laid along the full gap (%s) rather than "
                "along the capped end, so the cap is a number nothing uses"
                % walks[0].strip())

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

# -- A ROPE YOU PUT DOWN IS PUT DOWN -----------------------------------------
#
# Letting go took the rope out of the HAND and left the node in the world, and
# `_from` falls back to `hand_at` — the last place your hand was — so a dropped
# rope went on drawing itself and went on hauling the creature to a spot the
# player had already walked away from. From their side that is a lead that
# cannot be put down: the button says you did, and the rope is still pulling.
#
# And it took the nest with it, because a hand holding the lead does not read
# the stone — so a lead that could not be put down meant the stone could not be
# read either, until the game was restarted.
ticking = body_of(ROPE, "_process")
lets_go = False
for i, row in enumerate(ticking):
    if "in_hand" in row and "is_tied()" in row:
        lets_go = any("queue_free()" in r for r in ticking[i:i + 4])
print()
print("A ROPE PUT DOWN AND TIED TO NOTHING %s."
      % ("goes" if lets_go else "GOES ON PULLING FROM WHERE YOUR HAND WAS"))
if not lets_go:
    fail.append("a rope that is neither held nor tied stays in the world and "
                "goes on tugging toward the last place the hand was — the lead "
                "cannot be put down, and while it is up the nest cannot be read")

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

# -- A TIED ROPE IS OUT OF YOUR HANDS ----------------------------------------
#
# THE LANDSCAPE IS ALSO THE CAMERA. While the rope owns every touch you cannot
# look round the world at all, and a tap on the ground means "untie and come
# here" — so tying the creature to a tree and then looking at anything else was
# impossible. The player's words: "once the leash is TIED to something on the
# landscape, I want to be able to drag the camera around like normal. I don't
# want touching the landscape to mean picking up the leash again."
#
# So tying it off PUTS IT DOWN, and what makes that true is not the name of a
# function. It is that `tie` decides `in_hand` from whether it was given
# anything to tie to, and that `has_lead` — the gate every input path in the
# hand asks before it does anything — reads `in_hand`. Either half alone is
# worth nothing, so both are checked.
tying = body_of(ROPE, "tie")
puts_down = any(re.search(r"\bin_hand\s*=", r) and "what" in r for r in tying)
reads_hand = any("in_hand" in r for r in body_of(HAND, "has_lead"))
print()
print("TYING THE ROPE OFF %s."
      % ("puts it down, and the landscape is the camera's again" if puts_down
         else "KEEPS HOLD OF THE LANDSCAPE"))
if not puts_down:
    fail.append("tying the rope off does not take it out of your hand, so the "
                "hand goes on owning every touch: the camera cannot be dragged "
                "and a tap on the ground unties the rope and hauls the creature "
                "to it, for as long as the beast is posted anywhere")
if not reads_hand:
    fail.append("`has_lead` does not read `in_hand`, so whether the rope is in "
                "your hand has nothing to do with whether the hand behaves as "
                "though it is")

# AND TAKING IT UP TAKES IT OFF THE POST. Tied AND held is the same bug from
# the other side: it is the state in which a tap on bare earth meant "untie and
# haul", which is not what a tap on the landscape should ever mean while the
# creature is tied up somewhere.
taking = body_of(ROPE, "take_up")
comes_off = any("tied_to = null" in r for r in taking) \
    and any(re.search(r"\bin_hand\s*=\s*true", r) for r in taking)
picks_up = any("take_up(" in r for r in body_of(HAND, "hold_lead"))
print("TAKING IT BACK UP %s."
      % ("takes it off the post" if comes_off and picks_up
         else "LEAVES IT TIED AND IN YOUR HAND AT ONCE"))
if not comes_off:
    fail.append("there is no door that takes the far end off whatever it is "
                "round and puts it back in your hand, so the only way to hold "
                "a tied rope again is the one that also hauls the creature")
if not picks_up:
    fail.append("taking up the lead does not untie it, so a rope can be tied to "
                "a tree and in your hand at the same time — which is the state "
                "where a tap on the landscape unties it by surprise")

# -- AND YOUR HAND EMPTIES WHEN YOU TAKE IT UP -------------------------------
#
# A hand with the lead in it does not grab, and the release path returns early
# for the lead — so taking up the rope while carrying something left that thing
# glued to the hand with NO way to let go of it: the sling's rope and aim arc
# drawn over it for the rest of the session, and `hands_busy` stuck true, which
# costs the far half of the world a simulation stride for as long as it lasts.
taking_up = body_of(HAND, "hold_lead")
frees = any("_release_body(" in r for r in taking_up) \
    and any("held_body = null" in r for r in taking_up) \
    and any("_stow_sling()" in r for r in taking_up)
print()
print("TAKING UP THE LEAD %s."
      % ("sets down what the hand was holding" if frees
         else "LEAVES IT GLUED TO A HAND THAT CANNOT LET GO"))
if not frees:
    fail.append("taking up the lead does not set down what the hand was "
                "carrying — and the release path returns early while the lead "
                "is up, so that thing can never be let go of, its sling stays "
                "drawn over the world, and hands_busy never clears")

# -- AND TYING IT OFF IS THE TEACHING AID ------------------------------------
#
# The player's words: "Letting go of it, and casting miracles or throwing things
# is like pulling the creature aside so it is FORCED to see what it is you want
# it to see. This is the disciplinary measure and teaching aid rolled into one."
#
# So a tied creature does not merely fail to wander off — it is SHOWN things.
# Its head goes round and is held there, and the lesson goes in harder. The
# whole mechanic rests on four statements, and any one of them missing leaves
# the other three doing nothing worth having.
LEADC3 = (ROOT / "scripts/creature/creature_lead.gd").read_text()
HEADC = (ROOT / "scripts/creature/creature_head.gd").read_text()
MIND = (ROOT / "scripts/creature/creature_mind.gd").read_text()

shown = body_of(LEADC3, "made_to_watch")
only_tied = False
for i, row in enumerate(shown):
    if "tied_up(" in row:
        only_tied = any(r.strip() == "return" for r in shown[i:i + 3])
aims = any("look_here(" in r for r in shown)
print()
print("A TIED CREATURE %s what you do in front of it."
      % ("is made to watch" if only_tied and aims else "MAY LOOK OR MAY NOT"))
if not aims:
    fail.append("nothing turns the tied creature's head to what you just did, "
                "so tying it off buys the player nothing they could see")
if not only_tied:
    fail.append("being made to watch is not gated on being TIED, so either a "
                "loose creature is pinned to your every move or the gate is "
                "somewhere it cannot be read")

# AND THE HEAD IS HELD. Without the hold `_pick` has it back on your hand or a
# passing sheep within HOLD_LOOK, and being shown a thing is exactly the part
# where you do not get to look away.
held = any("_choose_in" in r for r in body_of(HEADC, "look_here"))
print("   ...and its head %s." % ("is held there" if held else "DRIFTS STRAIGHT BACK"))
if not held:
    fail.append("the head can be pointed at what you did but not HELD there, "
                "so it picks a new subject within HOLD_LOOK and the creature "
                "looks away from the thing it is tied in front of")

# AND EVERY DEED GOES THROUGH IT: what your hands do, and what your miracles do.
by_hand = any("made_to_watch(" in r for r in body_of(HAND, "_show_creature"))
MIRACLES = (ROOT / "scripts/miracles/miracle_manager.gd").read_text()
# `resolve` is where a miracle actually happens — the one door every working
# goes through, whether it was drawn, thrown as an orb, or cast by the creature.
by_miracle = any("made_to_watch(" in r for r in body_of(MIRACLES, "resolve"))
print("   ...for your hands: %s, for your miracles: %s."
      % ("yes" if by_hand else "NO", "yes" if by_miracle else "NO"))
if not by_hand:
    fail.append("a thrown or gently set-down thing does not reach the tied "
                "creature, so half of what you can show it is not shown")
if not by_miracle:
    fail.append("a miracle worked in front of a tied creature does not make it "
                "watch, which is the example the mechanic exists for")

# AND WHAT IT BUYS IS THE HOW, NOT THE WHY. This is the design claim, and it is
# worth a check because it is the one that would be quietly convenient to break:
# a `heed` on the reward would let a player MANUFACTURE a creature's devotion by
# tying it to a post, and nothing else in this codebase works that way.
learning = body_of(MIND, "witness_god_deed")
wants = next((r for r in learning if "teach(" in r), "")
can = next((r for r in learning if "watch_technique(" in r), "")
floor = next((r for r in learning if "FAITH_FLOOR" in r or "faith <" in r), "")
honest = "heed" not in wants and "heed" in can and "heed" in floor
print("BEING MADE TO WATCH teaches %s."
      % ("the how, and never the why" if honest else "WHATEVER IS CONVENIENT"))
if "heed" not in can:
    fail.append("being made to watch does not teach technique any faster, so "
                "the whole mechanic is a head turning and nothing else")
if "heed" in wants:
    fail.append("being made to watch moves what the creature WANTS — so a "
                "player can manufacture devotion by tying a beast to a post, "
                "which is not how anything else in this game works")
if "heed" not in floor:
    fail.append("the trust floor is not passable by being made to watch, so "
                "tying up the one creature that has stopped listening to you "
                "teaches it nothing — which is the case the mechanic is for")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: one rope, one door, paced tugs, trust decides, and what opens shuts.")
