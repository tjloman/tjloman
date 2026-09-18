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

## WHAT A PULL IS WORTH IN ATTENTION. A hauled rope has the beast's whole mind;
## a rope that merely moved gets a glance. See `to_spot` and `nudge_to`, which
## are the strong door and the weak one.
const STRONG_HEED := 25.0
const GLANCE := 8.0

## TIED UP AND MADE TO WATCH — the disciplinary measure and the teaching aid,
## and they are the same act.
##
## A creature on a tied rope cannot walk off. So when you let go of the lead and
## then work a miracle, or hurl a tree, or set somebody down gently in front of
## it, that is not a thing the beast MAY happen to notice — it is a thing it is
## being SHOWN. Its head goes round, its attention is pinned, and it can do
## nothing about any of it.
##
## This is what tying the rope off is FOR, and it is the answer to the oldest
## complaint about teaching by example in this game: that the one creature you
## most need to show something to is the one that keeps wandering off to look at
## a sheep. Holding the lead is steering. Tying it is teaching.
##
## What it buys is the HOW and not the WHY. Being made to watch a thing done
## teaches technique twice as fast and gets past the point where a creature has
## stopped taking its cues from you at all — but what it comes to WANT is still
## settled by what it thinks of you, because you cannot make anything admire you
## by tying it to a post. See CreatureMind.witness_god_deed.
const HELD_HEED := 2.0
## And it notices you from further off while it is tied, because there is
## nothing else to notice.
const HELD_REACH := 1.6
## How long its head is held on what you just did. Longer than the head's own
## HOLD_LOOK: it is not choosing to look.
const HELD_LOOK := 3.2


## IS IT TIED UP? Not "is it on a lead" — a rope in your hand is a rope it can
## be led by, and it may still put its back to you. This is the far end being
## round SOMETHING, which is the state it cannot leave.
static func tied_up(who: Creature) -> bool:
	if who == null or not is_instance_valid(who) or not who.is_inside_tree():
		return false
	var rope := LeadRope.on(who, who.get_tree())
	return rope != null and rope.is_tied()


## HOW MUCH HARDER A LESSON LANDS RIGHT NOW: one while it is loose, and
## HELD_HEED while it is tied up in front of what you are doing.
static func heed(who: Creature) -> float:
	return HELD_HEED if tied_up(who) else 1.0


## AND HOW MUCH FURTHER IT SEES YOU, for the same reason.
static func reach_gain(who: Creature) -> float:
	return HELD_REACH if tied_up(who) else 1.0


## COULD IT SEE THAT? Its ordinary sight, widened by what it has been attending
## to and by its own size — a big creature's eye is higher up — and widened
## again while it is tied.
##
## Lifted out of Creature.witness_god, which is where the numbers were: the file
## lives permanently on its line limit, and this is the lead's rule now.
static func in_sight(who: Creature, where: Vector3) -> bool:
	if who == null or not is_instance_valid(who):
		return false
	var reach := (24.0 + who.attention * 0.3 + who.scale.x * 1.5) * reach_gain(who)
	return who.global_position.distance_to(where) <= reach


## AND IT LOOKS AT IT. A creature that cannot walk away from what you are doing
## should not be able to look away from it either: the head goes to the spot and
## is held there, rather than drifting back to your hand or a passing sheep the
## moment the head next picks a subject.
##
## Loose, this is nothing at all. A free creature notices what it notices, and
## that is the whole difference between showing something to a beast and merely
## doing it near one.
static func made_to_watch(who: Creature, where: Vector3) -> void:
	if not tied_up(who):
		return
	if where.distance_to(who.global_position) > CreatureHead.STARTLE_WITHIN:
		return
	CreatureHead.startled(who, where)
	who.head.look_here(where, HELD_LOOK)


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
	who.state = Creature.State.LEASHED
	who.express("curious")
	who.attention = minf(who.attention + STRONG_HEED, 100.0)


## TIE IT TO A THING. It goes and fetches it.
static func to_thing(who: Creature, what: Node3D) -> void:
	if what == null or not is_instance_valid(what):
		return
	# HANDS FREE, because this one ends in picking something up — which is the
	# ONLY reason a lead ever makes a creature set down what it is carrying.
	# `to_spot` used to do it for every order, which meant the periodic tug of a
	# held rope made the beast drop its load every second and a half, for ever:
	# a creature on the lead could not carry anything across a village, which is
	# most of what you would want to lead one for.
	who.release_carried()
	to_spot(who, what.global_position)
	if who.is_leashed():
		who.leash_thing = what
		GameState.announce("Your creature is sent after %s."
			% CreatureLook.carriable_word(what))


## NUDGE IT — THE WEAK DOOR.
##
## The difference between the two is the whole of how a lead feels. `to_spot` is
## a HAUL: the beast turns, drops what it was doing and comes, and the player
## meant it. This is the rope merely having MOVED — you walked, or you let out
## some slack — and a rope moving is not an order. It re-aims the creature and
## changes nothing else: what it is carrying stays carried, what it was
## expressing goes on being expressed, and it gets a glance rather than its
## whole attention.
##
## Without this every tug was a haul, and a haul every second and a half is not
## a lead. It is a hand on the scruff of the neck.
static func nudge_to(who: Creature, pos: Vector3) -> void:
	if who.exiled:
		return
	who.leash_target = CreatureStake.nearest_within(who.get_tree(), pos)
	if who.state != Creature.State.LEASHED:
		who.state = Creature.State.LEASHED
	who.attention = minf(who.attention + GLANCE, 100.0)


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
	# IT IS AWAKE ON THE ROPE, AND THAT IS THE POINT OF THE ROPE.
	#
	# The look-round used to happen only once it had ARRIVED and was standing
	# about — so a creature led the length of a village saw none of it, and the
	# one tool a player has for showing their beast the world taught it nothing
	# on the way. Being walked past a thing is how an animal learns what a thing
	# is. So it observes on its own clock whether it is walking or waiting, and
	# everything CreatureWatching does — moods, what it makes of what it sees,
	# what it decides it wants to try — goes on happening while you lead it.
	who._action_time -= delta
	if who._action_time <= 0.0:
		who._action_time = LOOK_EVERY
		CreatureWatching.observe(who)
	if who.global_position.distance_to(who.leash_target) > ARRIVED:
		who._move_toward(who.leash_target, who._run_speed() * 0.9, delta)
		return
	who._apply_gravity_only(delta)
