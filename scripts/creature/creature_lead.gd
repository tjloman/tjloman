class_name CreatureLead
extends RefCounted
## THE LEAD — the one thing you can say to your creature directly.
##
## Everything else in this game is indirect. You praise a deed, you scold a
## deed, you show it something and hope; the creature's mind does the rest and
## nothing you do is a command. The lead is the exception, and it is the whole
## of the player's vocabulary for "not that — THIS".
##
## It ties to two kinds of thing, and the second is the one that teaches:
##
##   A SPOT. Go there and wait. Post it somewhere and leave it.
##   A THING. Go to that and PICK IT UP. Which means "fetch that" is a sentence
##   you can say with the same gesture as "go there" — point the lead at a
##   sheep instead of at the grass beside it. The lead comes off in the act,
##   because you asked for a thing to be fetched and it has been.
##
## The creature is on a stake until you have learned this (CreatureStake), and
## that is the bargain: you are given a beast you cannot lose, and you get it
## loose the moment you hold the tool that replaces the rope.
##
## Lifted out of Creature — which lives permanently on its line limit — once
## tying the lead to a thing made it more than a destination.

## How near it has to get to a thing before it takes it up, plus a share of its
## own size: a beast fifteen metres across does not have to stand on a sheep.
const TAKES_AT := 2.2
const TAKES_PER_SIZE := 0.6
## And how near a SPOT counts as arrived. Loose on purpose — a creature told to
## go over there and standing three metres off has done as it was asked.
const ARRIVED := 3.0
## How often it looks up from waiting.
const LOOK_EVERY := 3.0


## ORDER IT TO A SPOT (the hand's ground point). It drops what it is doing.
static func to_spot(who: Creature, pos: Vector3) -> void:
	# A creature that has walked away from you does not come when called. This
	# is the one command it will refuse, and it refuses it until amends are made.
	if who.exiled:
		GameState.announce("Your creature looks at your hand, and does not come.")
		who.express("sad", 2.0)
		return
	# A ROPE IS STILL A ROPE. Pointing past it sends the creature as near as it
	# can get rather than having it strain at the end for the rest of the day.
	who.leash_target = CreatureStake.nearest_within(who.get_tree(), pos)
	who.release_carried()
	who.state = Creature.State.LEASHED
	who.express("curious")
	who.attention = minf(who.attention + 25.0, 100.0)


## TIE IT TO A THING. It goes and fetches it.
static func to_thing(who: Creature, what: Node3D) -> void:
	if what == null or not is_instance_valid(what):
		return
	to_spot(who, what.global_position)
	if who.is_leashed():
		who.leash_thing = what
		GameState.announce("Your creature is sent after %s."
			% CreatureLook.carriable_word(what))


static func release(who: Creature) -> void:
	who.leash_thing = null
	if who.leash_target == Vector3.INF:
		return
	who.leash_target = Vector3.INF
	if who.state == Creature.State.LEASHED:
		who._decide()


## WALK TO WHERE IT WAS SENT. If that was a spot it waits there, drifting a
## little, until you let it go — so you can post it somewhere and leave. If it
## was a thing, it picks the thing up and the lead comes off.
static func walk(who: Creature, delta: float) -> void:
	if who.leash_target == Vector3.INF:
		who._decide()
		return
	# A LEAD TIED TO SOMETHING FOLLOWS IT. A sheep that wanders off while the
	# creature is on its way is still the sheep it was sent for.
	var prize := who.leash_thing
	if prize != null:
		if not is_instance_valid(prize) or prize.is_queued_for_deletion():
			who.leash_thing = null
			prize = null
		else:
			who.leash_target = CreatureStake.nearest_within(
				who.get_tree(), prize.global_position)
	if prize != null:
		var reach := TAKES_AT + who.scale.x * TAKES_PER_SIZE
		if who.global_position.distance_to(prize.global_position) < reach:
			who.leash_thing = null
			who.leash_target = Vector3.INF
			who.take_up(prize)
			return
	if who.global_position.distance_to(who.leash_target) > ARRIVED:
		who._move_toward(who.leash_target, who._run_speed() * 0.9, delta)
		return
	who._apply_gravity_only(delta)
	who._action_time -= delta
	if who._action_time <= 0.0:
		who._action_time = LOOK_EVERY
		# Waiting where it was told, but still watching the world go by.
		CreatureWatching.observe(who)
