class_name LeadRope
extends Node3D
## A ROPE WITH TWO ENDS, AND ONE OF THEM IS IN YOUR HAND.
##
## THE LEAD USED TO BE A SENTENCE. You pressed a key and the creature was told,
## once, to go to a spot — and then the telling was over and there was nothing
## in the world to show for it. That is a command line with a button on it, and
## it is why the most important tool in the game did not feel like a tool: there
## was nothing to hold, nothing to pull against, and no way to say "not there,
## HERE" except by saying the whole sentence again.
##
## So the lead is a thing now. Tap Lead and one end of it is in your hand. The
## other is on the creature. Walk, and it walks: the rope TUGS — every
## TUG_EVERY seconds the beast is told again where your hand is — which is the
## difference between an order and a lead. Nothing is instant and nothing is
## silent; you can see the line between you, and it goes slack when it is being
## obeyed and straightens when it is not.
##
## AND IT TIES OFF. Hold your finger on anything and the far end goes round it:
## a fence post, a tree, a villager. What a tied rope buys is SLACK — the
## creature is bound to that thing within the rope's length and may do as it
## likes inside it, which is the whole of shepherding and none of it is a
## command. Tie it to a villager and the beast follows that villager about.
##
## AND A TAP ON BARE EARTH IS STILL "GO THERE", because sometimes you do just
## want to point.
##
## AND A TIED ROPE IS OUT OF YOUR HANDS. Tying the far end round something is
## the end of the holding: the rope stays where you put it and works away on its
## own, and the world goes back to being the world — drag to look about, tap to
## do whatever a tap does.
##
## It has to be this way round because THE LANDSCAPE IS ALSO THE CAMERA. While
## the rope owns every touch there is no looking around at all, and a tap on the
## ground means "untie and come here" — so posting the creature by a tree and
## then looking at anything else was impossible, and the rope kept picking
## itself back up by surprise. Press Lead to take it up again; that is the only
## way back into your hand, and it is the one gesture nobody makes by accident.
##
## TRUST IS THE WHOLE OF WHETHER IT WORKS. A creature that does not trust you
## drags, ignores a tug it does not fancy, and slips the rope altogether if you
## have treated it badly enough. One that trusts you completely comes the
## instant the line moves. That is not a difficulty setting — it is the reason
## to be worth trusting, and it is the one place in this game where the bond you
## have built is a thing you can feel in your hand.

## HOW OFTEN THE ROPE SAYS ANYTHING. A held lead re-aims the creature this often
## rather than every frame: a beast re-ordered sixty times a second is a beast
## that never finishes a stride, and one re-ordered every ten seconds is not on
## a lead at all, it is being telegrammed. At this it reads as being led.
## THE TWO PULLS. A rope has two things it can do and they are not the same
## thing at two speeds — they are different sentences.
##
## A STRONG TUG is the player asserting: a double tap, or tying the rope off.
## It happens THE INSTANT it is asked, never on the next beat, because the whole
## of what makes a lead feel like a lead is that a deliberate pull is answered
## now. It turns the beast, takes its whole attention, and interrupts whatever
## it was doing.
##
## A WEAK TUG is the rope having MOVED: you walked, or you let out slack. That
## is not an order and must not be answered like one. It re-aims the creature
## and changes nothing else — what it is carrying stays carried, what it was
## doing goes on — and it gets a glance rather than the beast's whole mind.
##
## Every tug used to be the strong one, on a timer. A haul every second and a
## half is not a lead, it is a hand on the scruff of the neck, and it made the
## creature drop whatever it was carrying every time the timer came round.
enum Pull { WEAK, STRONG }

const TUG_EVERY := 1.4
## ...and how far the hand must have moved for a tug to be worth sending. Below
## this the creature is already going where you want and being told again only
## interrupts it.
const TUG_IF_MOVED := 2.5

## HOW LONG THE ROPE IS. Tied to something, this is the slack the creature has
## to move in; held in the hand it is how far you may wander before it is pulled
## taut and the beast is obliged to follow.
const ROPE_LENGTH := 22.0

## WHAT TRUST BUYS, and it buys different things for the two pulls.
##
## A YANK GETS THROUGH TO ALMOST ANYTHING. You have hold of the rope and you
## have pulled it; a creature that ignored that would not read as wilful, it
## would read as broken. So a strong tug asks little and lands nearly always.
##
## THE AMBIENT FOLLOW IS WHERE TRUST LIVES. Whether a beast comes along because
## the rope moved — without being told, without being hauled — is exactly the
## question "does it trust you", and at low trust the answer is mostly no. Which
## gives the rope a shape over a whole game: early on you lead by yanking, and
## as it comes to trust you it simply follows, and you notice you stopped
## yanking. That is the tool teaching the player what the bond is for.
const STRONG_REFUSES := 5.0
const STRONG_HEEDS := 60.0
const WEAK_REFUSES := 35.0
const WEAK_HEEDS := 95.0

## How thick the rope draws, and how far it sags at full slack.
const CORD_THICK := 0.09
const SAG := 1.6
## How many segments the drawn line has. A rope is a curve and four straight
## pieces is enough of one at the distance this is ever seen from.
const LINKS := 6

## WHOSE ROPE THIS IS. Set before it enters the tree.
var creature: Creature = null
## What the far end is tied to, or null while it is loose in your hand.
var tied_to: Node3D = null
## WHAT YOU LAST TOLD IT, kept after the rope is put down.
##
## "If you dismiss the leash and creature, the creature remembers what you
## ordered it to do." A lead that forgets the moment you let go of it is a lead
## you have to hold for ever, and the whole point of tying one off is to walk
## away — so the order outlives the rope, and picking the rope up again picks up
## where you left off rather than starting from nothing.
var last_order := Vector3.INF
## Where the hand end is. Written by DivineHand every frame it is carried; a
## dropped rope keeps the last one, which is where it lies on the ground.
var hand_at := Vector3.INF
## True while the player is carrying it.
var in_hand := false
## HOW LONG THE ROPE IS RIGHT NOW. A var and not the constant, because the
## player is going to set it — pinch the rope at its middle and pull — and
## LENGTHENING IT IS A WEAK TUG: the slack changes, the creature notices, and
## nothing is ordered. See `set_length`.
var length := ROPE_LENGTH

var _links: Array[MeshInstance3D] = []
var _next_tug := 0.0
var _told_at := Vector3.INF


func _ready() -> void:
	name = "LeadRope"
	add_to_group("lead_rope")
	top_level = true
	for i in LINKS:
		var link := Util.box(Vector3(CORD_THICK, CORD_THICK, 1.0),
			Color(0.62, 0.53, 0.38))
		add_child(link)
		_links.append(link)


## THE HAND END, WHEREVER IT IS. A rope in the hand follows the hand; a rope
## tied to a thing follows the thing; a rope on the ground stays put.
func _from() -> Vector3:
	if tied_to != null and is_instance_valid(tied_to):
		return tied_to.global_position + Vector3.UP * 0.6
	return hand_at


func _process(delta: float) -> void:
	if creature == null or not is_instance_valid(creature):
		queue_free()
		return
	# PUT DOWN AND TIED TO NOTHING IS A ROPE ON THE GROUND, AND IT GOES.
	#
	# Letting go took the rope out of the HAND and left the node in the world,
	# and `_from` falls back to `hand_at` — the last place your hand was — so a
	# dropped rope went on drawing itself and went on hauling the creature to
	# a spot you had already walked away from, for ever. From the player's side
	# that is a lead you cannot put down: the button says you did, and the rope
	# is still there, still pulling.
	#
	# And it took the nest with it. A hand holding the lead does not read the
	# stone (it does not grab anything), so a lead that could not be put down
	# meant the nest could not be read either — until the game was restarted
	# and the node died with the scene. Two symptoms, one line.
	#
	# A TIED rope is different and stays: that is the posted creature, and
	# walking away from it is the whole point of tying off.
	if not in_hand and not is_tied():
		queue_free()
		return
	var anchor := _from()
	if not anchor.is_finite():
		return
	_draw_between(anchor, creature.global_position + Vector3.UP * creature.scale.y)
	_next_tug -= delta
	if _next_tug <= 0.0:
		_next_tug = TUG_EVERY
		_tug(anchor, Pull.WEAK)


## THE ROPE PULLS. What that means depends on which end is fixed.
##
## In the hand it means COME HERE: the creature is re-aimed wherever the hand
## now is, but only once the hand has actually gone somewhere — see
## TUG_IF_MOVED, without which walking on the spot would re-order the beast
## every second and a half for ever and it would never take a full stride.
##
## Tied to something it means STAY NEAR THAT: nothing is said at all while the
## creature is inside the rope's length, which is the slack, and that is the
## point of tying it off rather than holding it.
func _tug(anchor: Vector3, pull: Pull) -> void:
	var gap := creature.global_position.distance_to(anchor)
	if pull == Pull.WEAK:
		# A WEAK TUG IS ONLY EVER THE ROPE MOVING, so it says nothing at all
		# while there is nothing new to say. A strong one is the player
		# asserting and is never talked out of it.
		if tied_to != null and gap <= length:
			return                  # inside its slack: let it be
		if _told_at.is_finite() and _told_at.distance_to(anchor) < TUG_IF_MOVED \
				and gap <= length:
			return                  # already going where you want it
	if not heeds(pull):
		# It felt the rope and did not come. Said out loud, because a creature
		# that ignores you silently is indistinguishable from a bug.
		creature.express("stubborn", 1.5)
		return
	_told_at = anchor
	last_order = anchor
	if pull == Pull.STRONG:
		CreatureLead.to_spot(creature, anchor)
	else:
		CreatureLead.nudge_to(creature, anchor)


## PULL IT NOW. The door for everything the player does ON PURPOSE — a double
## tap, tying the rope off — and the whole of why it is a separate door is that
## it does not wait for the beat. A deliberate pull answered a second and a half
## later is a deliberate pull the player has already decided did not work.
func haul(toward: Vector3) -> void:
	if creature == null or not is_instance_valid(creature):
		return
	_next_tug = TUG_EVERY           # the ambient beat restarts from here
	_tug(toward, Pull.STRONG)


## DOES IT ANSWER THIS PULL? A chance that rises with what it thinks of you,
## on a different band for each of the two pulls — see the note by
## STRONG_REFUSES. An exiled creature refuses everything, which CreatureLead
## already says and this must not contradict.
func heeds(pull: Pull) -> bool:
	if creature == null or not is_instance_valid(creature) or creature.exiled:
		return false
	var floor_at := STRONG_REFUSES if pull == Pull.STRONG else WEAK_REFUSES
	var sure_at := STRONG_HEEDS if pull == Pull.STRONG else WEAK_HEEDS
	var mind := clampf((creature.trust - floor_at)
		/ maxf(sure_at - floor_at, 0.001), 0.0, 1.0)
	return randf() <= mind


## TIE THE FAR END ROUND THIS. Null unties it and leaves the rope in the hand.
##
## A STRONG TUG, because tying off is the player asserting: the anchor has moved
## and the creature should find that out now rather than on the next beat.
func tie(what: Node3D) -> void:
	tied_to = what
	_told_at = Vector3.INF
	# AND TYING IT OFF PUTS IT DOWN. See the note at the head of this file: the
	# hand is only in lead mode while the rope is IN it, so this one line is
	# what hands the landscape back to the camera the moment the creature is
	# posted. Untying — `tie(null)` — is the same sentence backwards and puts
	# the end back in your hand, which is what a tap on bare earth means.
	in_hand = what == null
	haul(_from())


## TAKE IT BACK UP. The far end comes off whatever it was round and the rope is
## in your hand again, at `at`.
##
## Nothing is hauled. Picking a rope up is not an order — it is you getting hold
## of it — and the creature finds out where your hand is on the next beat like
## it always does. A pick-up that yanked would make the Lead button unusable for
## the one thing it is now for: getting a posted creature back under your hand
## without disturbing what it is doing.
func take_up(at: Vector3) -> void:
	tied_to = null
	in_hand = true
	hand_at = at
	_told_at = Vector3.INF


## THE ROPE THIS CREATURE HAS, if any — in your hand or tied off somewhere on
## the far side of the valley. A beast has ONE lead, and everything that asks
## about it asks here: the key, both buttons and the hand cannot come to
## different conclusions about a thing there is only one of.
static func on(who: Creature, tree: SceneTree) -> LeadRope:
	if who == null or tree == null:
		return null
	for r in tree.get_nodes_in_group("lead_rope"):
		var rope := r as LeadRope
		if rope != null and is_instance_valid(rope) and rope.creature == who:
			return rope
	return null


## LET OUT OR TAKE IN ROPE. A WEAK tug — the slack changed and the beast may
## notice, but nobody ordered it anywhere. This is the door the pinch gesture
## will come through when it is built.
func set_length(metres: float) -> void:
	length = maxf(metres, 1.0)
	_tug(_from(), Pull.WEAK)


## IS IT TIED TO SOMETHING? What the casting gate asks — see DivineHand: a rope
## loose in your hand is a hand that is full, and a hand that is full cannot
## draw. Tie it off and both of yours are free again.
func is_tied() -> bool:
	return tied_to != null and is_instance_valid(tied_to)


## DRAWN AS A SAGGING LINE. Straight when it is taut, bellied when there is rope
## to spare — which is the only readout the player needs and the only one they
## will ever look at.
func _draw_between(a: Vector3, b: Vector3) -> void:
	var span := a.distance_to(b)
	var slack := clampf(1.0 - span / maxf(length, 0.001), 0.0, 1.0)
	for i in _links.size():
		var t0 := float(i) / float(_links.size())
		var t1 := float(i + 1) / float(_links.size())
		var p0 := a.lerp(b, t0) + Vector3.DOWN * _belly(t0, slack)
		var p1 := a.lerp(b, t1) + Vector3.DOWN * _belly(t1, slack)
		var link := _links[i]
		link.global_position = (p0 + p1) * 0.5
		var along := p1 - p0
		if along.length() > 0.001:
			# A ROPE MAY HANG STRAIGHT DOWN — the creature below a hand held
			# over a cliff — and `look_at` along the up axis is an error Godot
			# reports every frame for as long as it lasts.
			var facing := along.normalized()
			var up := Vector3.UP if absf(facing.dot(Vector3.UP)) < 0.99 \
				else Vector3.FORWARD
			link.look_at(link.global_position + facing, up)
		link.scale = Vector3(1.0, 1.0, maxf(along.length(), 0.01))


## How far the rope hangs at this point along it. A parabola, which is close
## enough to a catenary that nobody has ever been able to tell.
func _belly(t: float, slack: float) -> float:
	return SAG * slack * (1.0 - (2.0 * t - 1.0) * (2.0 * t - 1.0))
