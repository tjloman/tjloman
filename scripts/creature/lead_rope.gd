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
const TUG_EVERY := 1.4
## ...and how far the hand must have moved for a tug to be worth sending. Below
## this the creature is already going where you want and being told again only
## interrupts it.
const TUG_IF_MOVED := 2.5

## HOW LONG THE ROPE IS. Tied to something, this is the slack the creature has
## to move in; held in the hand it is how far you may wander before it is pulled
## taut and the beast is obliged to follow.
const ROPE_LENGTH := 22.0

## WHAT TRUST BUYS. Below REFUSES_UNDER a tug is ignored outright as often as
## not; at HEEDS_ABOVE every one lands. Between them it is a chance, so a
## half-trusted creature is not broken, it is unreliable — which is a thing a
## player can feel and do something about.
const REFUSES_UNDER := 25.0
const HEEDS_ABOVE := 90.0

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
## Where the hand end is. Written by DivineHand every frame it is carried; a
## dropped rope keeps the last one, which is where it lies on the ground.
var hand_at := Vector3.INF
## True while the player is carrying it.
var in_hand := false

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
	var anchor := _from()
	if not anchor.is_finite():
		return
	_draw_between(anchor, creature.global_position + Vector3.UP * creature.scale.y)
	_next_tug -= delta
	if _next_tug <= 0.0:
		_next_tug = TUG_EVERY
		_tug(anchor)


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
func _tug(anchor: Vector3) -> void:
	var gap := creature.global_position.distance_to(anchor)
	if tied_to != null and gap <= ROPE_LENGTH:
		return                      # inside its slack: let it be
	if _told_at.is_finite() and _told_at.distance_to(anchor) < TUG_IF_MOVED \
			and gap <= ROPE_LENGTH:
		return                      # already going where you want it
	if not heeds():
		# It felt the rope and did not come. Said out loud, because a creature
		# that ignores you silently is indistinguishable from a bug.
		creature.express("stubborn", 1.5)
		return
	_told_at = anchor
	creature.leash_to(anchor)


## DOES IT COME WHEN THE ROPE MOVES? Below REFUSES_UNDER it mostly does not;
## above HEEDS_ABOVE it always does; between, it is a chance that rises with
## what it thinks of you. An exiled creature refuses everything, which
## CreatureLead already says and this must not contradict.
func heeds() -> bool:
	if creature == null or not is_instance_valid(creature) or creature.exiled:
		return false
	var mind := clampf((creature.trust - REFUSES_UNDER)
		/ maxf(HEEDS_ABOVE - REFUSES_UNDER, 0.001), 0.0, 1.0)
	return randf() <= mind


## TIE THE FAR END ROUND THIS. Null unties it and leaves the rope in the hand.
func tie(what: Node3D) -> void:
	tied_to = what
	_told_at = Vector3.INF
	_next_tug = 0.0


## DRAWN AS A SAGGING LINE. Straight when it is taut, bellied when there is rope
## to spare — which is the only readout the player needs and the only one they
## will ever look at.
func _draw_between(a: Vector3, b: Vector3) -> void:
	var span := a.distance_to(b)
	var slack := clampf(1.0 - span / maxf(ROPE_LENGTH, 0.001), 0.0, 1.0)
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
