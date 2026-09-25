class_name CreatureOffer
extends RefCounted
## WHAT IS IN YOUR HAND, AND WHETHER IT IS GOING TO TAKE IT.
##
## THE HOLE THIS FILLS. The creature knew two things about your hand: where it
## was (near enough to be worth watching) and what had recently left it
## (`last_thrown`, for the catch). It did not know what was IN it. So the only
## way to give it anything was to carry the thing to within three metres, bring
## the pointer to a complete stop for longer than THROW_ACTIVE_WINDOW, and let
## go — and any release still in motion read as a throw instead, which a young
## creature catches about one time in eight and otherwise watches sail past.
## Everything else landed on the grass, where nothing picked it up.
##
## Which is to say: HANDING IT SOMETHING WAS A TRICK YOU HAD TO KNOW, and the
## only place in the game where the creature was a passive target rather than a
## thing with its own reach. That is exactly backwards. It is a beast with
## claws and an interest in you. If you hold food out to it, it should take it.
##
## SO IT TAKES. Hold something still within its reach and it takes the thing
## out of your hand — no release, no timing, no stroke to get wrong. Hold it
## further off and, if it is minding you, it walks over and takes it from
## there. The rope is respected the whole way: an offer made beyond the tether
## is walked to as far as the tether allows and no further (see CreatureStake),
## which is the case the stake was written for — a staked creature is supposed
## to be able to be fed.
##
## WHY IT MUST BE HELD STILL. Without that, dragging a boulder across the map
## past a sleeping creature would have it snatched out of your hand in passing.
## A third of a second of a steady hand is the difference between carrying
## something and offering it, and it is a distinction every player already
## makes without being told.

## Reach, from the creature's middle, plus its own size — a whelp takes what is
## under its nose, a giant takes what is under yours.
const REACH := 2.4
## How far off an offer is worth crossing the ground for.
const NOTICE := 12.0
## Seconds the hand must hold roughly still before it reads as an offer at all,
## and how fast it may still be travelling and count as held.
##
## A SPEED, NOT A DISTANCE. Measured against the previous frame, a distance
## threshold is meaningless — 1.2 metres of travel in a sixtieth of a second is
## seventy metres a second, so a hand being hauled across the map at any
## plausible pace would have read as perfectly still. Two and a half metres a
## second is a slow deliberate drag; a hand that has come to rest sits far
## below it (the idle bob is under a fifth of a metre a second).
const STEADY := 0.3
const DRIFT := 2.5
## How long it will keep walking toward a hand that keeps moving away before it
## decides you are not really offering, and how long it then wants nothing to
## do with crossing the ground for you. Without the second number the first one
## does nothing: giving up clears the offer, the very next frame sees a fresh
## one and starts the walk again from zero, and a player could lead a creature
## across the map forever by holding a chicken in front of it. Well inside
## Creature.STUCK_SECONDS, so the stuck-state watchdog never gets there first.
const PATIENCE := 7.0
const SHY := 5.0
## WHAT A STEADY OFFER IS WORTH IN ATTENTION, a second.
##
## This was a GATE, and the gate could not be opened. Attention only rises when
## your hand is within about seven metres and decays at 0.6 a second, so a
## creature twelve metres off has none, cannot get any without you closing the
## distance yourself, and would therefore never come — which is the whole
## behaviour, refusing to happen for want of the thing it was supposed to
## create. An offer held out to it IS the attention-getter. It earns.
const NOTICED := 9.0

## Seconds the hand has been steady, seconds spent walking to this offer, and
## seconds left of not wanting to walk to another one.
var _steady := 0.0
var _walked := 0.0
var _shy := 0.0
var _was := Vector3.INF
## The thing being offered, held only so `walk` can tell that you put it down
## or swapped it for something else.
var _want: Node3D = null


## Every frame, from the creature's own tick. Costs one null check on a world
## where nothing is being held, which is nearly all of them.
func consider(who: Creature, delta: float) -> void:
	_shy = maxf(_shy - delta, 0.0)
	var hand := who.divine_hand
	if hand == null or not is_instance_valid(hand):
		_forget(who)
		return
	var item := hand.held_body
	if item == null or not is_instance_valid(item) or item == who \
			or item.is_queued_for_deletion() or not _free(who):
		_forget(who)
		return

	var at := hand.global_position
	if _was == Vector3.INF or at.distance_to(_was) > DRIFT * maxf(delta, 0.001):
		_steady = 0.0
	else:
		_steady += delta
	_was = at
	if _steady < STEADY:
		return

	var gap := who.global_position.distance_to(at)
	if gap <= REACH + who.scale.x:
		_take(who, hand, item)
		return
	if gap > NOTICE or _shy > 0.0:
		_forget(who)
		return
	# HOLDING SOMETHING OUT TO IT IS HOW YOU GET ITS ATTENTION, not something
	# you need its attention for. See NOTICED.
	who.attention = minf(who.attention + NOTICED * delta, 100.0)
	# THE WALKING CLOCK BELONGS TO THE OFFER, NOT TO THE STATE. A stuck-state
	# watchdog or a fright can bounce it out of TAKE and back in again, and if
	# `_walked` restarted on every re-entry PATIENCE would never be reached.
	if _want != item:
		_walked = 0.0
		_want = item
	if who.state != Creature.State.TAKE:
		who.state = Creature.State.TAKE
		who.head.subject = item      # and it keeps its eyes on the thing


## State.TAKE: crossing the ground to what you are holding out. The offer is
## re-checked from scratch every frame in `tick`, so all this has to do is
## walk and know when to stop.
func walk(who: Creature, delta: float) -> void:
	var hand := who.divine_hand
	if hand == null or not is_instance_valid(hand) or _want == null \
			or not is_instance_valid(_want) or hand.held_body != _want:
		_forget(who)
		who._decide()
		return
	_walked += delta
	if _walked > PATIENCE:
		_shy = SHY
		_forget(who)
		who._decide()
		return
	# NOT ONE STEP PAST THE ROPE. An offer made outside the tether is walked to
	# as far as the tether goes, and the creature stands there wanting it —
	# which is a true and readable thing for it to be doing, and far better
	# than straining at a rope or ignoring you.
	var to := CreatureStake.nearest_within(
		who.get_tree(), hand.global_position)
	who._move_toward(to, who._run_speed() * 0.75, delta)


## Nothing is on offer any more — you put the thing down, swapped it, walked
## off with it, or the creature stopped being in a state to want it. `tick`
## re-asks all of that from scratch every frame, so this is only ever the
## answer to a question that has already been decided above it.
func _forget(who_given: Variant) -> void:
	# Untyped until proved alive: a freed object handed to a typed parameter
	# is the error, raised before any check below could run. Gone is null.
	var who: Creature = (who_given as Creature) if is_instance_valid(who_given) else null
	_steady = 0.0
	_walked = 0.0
	_was = Vector3.INF
	_want = null
	if who != null and is_instance_valid(who) and who.state == Creature.State.TAKE:
		who.state = Creature.State.IDLE
		who._action_time = 0.4


## OUT OF YOUR HAND AND INTO ITS CLAWS. `give_to` is what unwinds the hand's
## side of it — the sling, the rope, the busy flag — and `receive_gift` is the
## same innate acceptance a set-down hand-off has always used, so what the
## creature then DOES with the thing is decided in exactly one place.
func _take(who: Creature, hand: DivineHand, item: Node3D) -> void:
	var came := _walked > 0.0
	_forget(who)
	if not hand.give_to(who):
		return
	who.head.subject = item
	# SAID ONLY WHEN IT CROSSED GROUND FOR IT. Taking something out of a hand
	# that is already at its face is the ordinary way to feed it and wants no
	# narration — `receive_gift` already shows it in the beast's own face. A
	# creature that walked over and took the thing is doing something the
	# player has not seen before and may not know it can do.
	if came:
		GameState.announce("Your creature comes over and takes it out of your hand.")


## It will not take anything while it is asleep, cowed, mid-miracle, weighing
## something up, or already holding something — and CARRYING is in that list
## twice over, because a creature that swaps what it is holding every time your
## hand comes near is a creature you cannot use.
static func _free(who: Creature) -> bool:
	if who.is_laden():
		return false
	return not (who.state in [
		Creature.State.SLEEPING, Creature.State.SULK, Creature.State.FLEE,
		Creature.State.WEIGHING, Creature.State.CAST, Creature.State.DEPART,
		Creature.State.SHUN, Creature.State.CARRYING, Creature.State.JUGGLE,
	])
