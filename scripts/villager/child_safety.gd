class_name ChildSafety
extends RefCounted
## THERE IS NO THROWING OF CHILDREN IN THIS GAME.
##
## Not "it costs a lot of karma". Not "the villagers will hate you for it".
## It does not happen, the way a rule of the world does not happen, and this
## file is the whole of that rule so that there is exactly one place to read
## it and exactly one place it could ever be weakened from.
##
## A game about a god with a hand over a village is going to be picked up and
## shaken by people looking for the worst thing in it, and the worst thing in
## it should not be available. That is not squeamishness — it is that the
## cruelty this game is actually ABOUT is the interesting kind: neglect,
## favouritism, famine you caused by not looking, a creature you taught to eat
## people. None of that needs this, and this would drown all of it.
##
## SO THE WORLD PUSHES BACK, rather than a message box telling you not to:
##
##   REACHING FOR A CHILD WITH AN EVIL HAND GETS YOU THE PARENT. They put
##   themselves in your grip in the child's place, which is the oldest and
##   most legible thing a parent does, and reads as the world defending itself
##   rather than as the game refusing an input.
##
##   AND THEY WILL NOT BE SHAKEN OFF. Try to hurl the parent aside and go back
##   for the child and they wrestle to stay in your hand. The hand is occupied
##   for exactly as long as you keep trying, which costs you the thing you
##   actually wanted — your hand — and nothing else.
##
##   A CHILD IN HAND IS SET DOWN, NEVER THROWN. Every path that lets go with
##   any speed sets them on their feet instead, the player's hand and the
##   creature's alike.
##
## A GOOD HAND MAY LIFT A CHILD, and must be able to: carrying one out of a
## burning street is a rescue, and lifting one out of the water is the ONLY
## way to save them from drowning. A rule that made children untouchable would
## take that away and make good play poorer, which is the opposite of the
## point. So the gate is on cruelty, not on children.

## Under this alignment the hand is not trusted with a child. Nought is the
## neutral god; the check is deliberately the same one that decides whether
## lifting a dying villager cradles them back to life (DivineHand._on_grab), so
## a hand that can save is a hand that can carry.
const TRUSTED_AT := 0.0

## How far a parent will come from to take a child's place. A village's own
## business: beyond this nobody saw it happen.
const STEPS_IN_FROM := 26.0

## What `throw_answer` says. "" is an ordinary throw.
const SET_DOWN := "set_down"
const HELD_FAST := "held_fast"

## Faster than a stroll, slower than a run. They are not fleeing anything; they
## are going somewhere, and they know the way.
const WALKS_HOME := 1.3
## And the most the walk is allowed to take, in seconds. A child stuck against
## water or a cliff is not left pacing it for ever.
const GIVES_UP_AFTER := 40.0


## Is this a child? The one definition, so nothing anywhere has its own idea.
static func is_child(thing: Node3D) -> bool:
	var soul := thing as Villager
	return soul != null and is_instance_valid(soul) and not soul.is_adult()


## WHAT ACTUALLY ENDS UP IN YOUR HAND when you reach for something.
##
## Ordinarily the thing you reached for. Reach for a child with an evil hand
## and it is whoever loves them: their mother if she is alive and near, and
## otherwise the nearest grown villager, because an orphan is not less
## defended than anybody else and a village looks after its own.
##
## If nobody is near enough to step in, the child is simply not lifted — the
## hand closes on nothing. That is the right failure: a child alone in an
## empty field with a monstrous god over them is a moment the game should
## refuse rather than resolve.
static func in_your_hand(reached_for: Node3D) -> Node3D:
	if not is_child(reached_for):
		return reached_for
	if GameState.alignment >= TRUSTED_AT:
		return reached_for            # a hand that can save may carry
	var child := reached_for as Villager
	var guard := _who_loves(child)
	if guard == null:
		return null
	guard.set_meta("shielding", child)
	GameState.announce("%s puts themselves in your hand." % guard.villager_name)
	return guard


## WHO COMES. The mother first — she is the one the world models — and then
## whoever else is grown and close by.
static func _who_loves(child: Villager) -> Villager:
	var here := child.global_position
	var mum := child.mother
	if mum != null and is_instance_valid(mum) and not mum.is_dying() \
			and mum.global_position.distance_to(here) < STEPS_IN_FROM:
		return mum
	var best: Villager = null
	var best_gap := STEPS_IN_FROM
	for v in child.get_tree().get_nodes_in_group("villagers"):
		var soul := v as Villager
		if soul == null or not is_instance_valid(soul) or soul == child:
			continue
		if not soul.is_adult() or soul.is_dying():
			continue
		var gap := soul.global_position.distance_to(here)
		if gap < best_gap:
			best_gap = gap
			best = soul
	return best


## CAN THIS BE THROWN, and if not, what happens instead?
##
## Returns "" for anything that may be thrown, SET_DOWN for a child — who goes
## on their feet wherever the hand happens to be — and HELD_FAST for somebody
## standing in a child's place, who simply does not let go.
static func throw_answer(thing: Node3D) -> String:
	if is_child(thing):
		return SET_DOWN
	if is_instance_valid(thing) and thing.has_meta("shielding"):
		var child: Variant = thing.get_meta("shielding")
		# They stop wrestling once there is nobody left to wrestle for.
		if is_instance_valid(child) and child is Villager:
			return HELD_FAST
		thing.remove_meta("shielding")
	return ""


## They are on the ground and it is over. Called wherever a grip ends, so a
## guardian set down properly goes back to being an ordinary villager who can
## be picked up and thrown like anybody else.
static func let_go(thing: Node3D) -> void:
	if is_instance_valid(thing) and thing.has_meta("shielding"):
		thing.remove_meta("shielding")


## AND THERE IS NO HURTING THEM EITHER — AND NOTHING TO SEE IF YOU TRY.
##
## Any harm that reaches a child — fire, a thrown stone, a fireball, a quake, a
## wolf, the water, the creature, hunger — is turned at the door into this: they
## get up and walk to the school, or the nearest house, go inside, and are gone.
## They have gone to live with family somewhere else. No announcement, no
## scream, no body, no mourners, no karma, nothing learned by the creature,
## nothing for the village to witness.
##
## THAT IS THE DESIGN AND IT IS AIMED AT A PERSON, NOT AT A VILLAGER. Somebody
## is going to get bored and try to murder the children in this game, and the
## only thing that stops that being a game is there being NO PAYOFF — not a
## punishment, which is a payoff of its own to the kind of player looking for
## one, and not a refusal, which is a puzzle to be solved. A child who simply
## leaves is the dullest possible answer. It is not meaningless: the village is
## one child smaller, and a god who keeps doing it will find the school empty.
## But there is nothing in it to enjoy.
##
## Returns true when the harm was turned. Every door asks this FIRST, before any
## of its own consequences, or the consequences are the payoff.
static func spared(soul: Villager) -> bool:
	if not is_child(soul):
		return false
	send_away(soul)
	return true


static func send_away(child: Villager) -> void:
	if child.leaving:
		return
	child.leaving = true
	_set_off(child)
	child.extinguish()
	child.health = maxf(child.health, 1.0)
	Mauling.free_of(child)
	# In a hand, or in the air: they set off once they are on their feet — see
	# Villager._choose, which sends a leaving child straight back to it.
	if child.state == Villager.State.HELD or child.state == Villager.State.FALLING:
		return
	child._dismount()
	child._decision_due = false
	child.state = Villager.State.LEAVING
	_set_off(child)


## O(N) BY DESIGN: once per child, at the moment harm turns them, and never
## again — send_away returns at `if child.leaving` before it can be asked twice.
## The walk itself reads the answer it stored; see `leave_step`.
## WHERE THEY GO IN. The school first — it is where a child goes when things are
## wrong — then the nearest roof in their own village, then anybody's.
static func shelter_for(child: Villager) -> Node3D:
	var town := child.village
	if town != null and is_instance_valid(town):
		if town.edubba != null and is_instance_valid(town.edubba):
			return town.edubba
		var best: Node3D = null
		var best_d := INF
		for h in town.houses:
			if not is_instance_valid(h) or h.under_construction:
				continue
			var d := child.global_position.distance_to(h.global_position)
			if d < best_d:
				best_d = d
				best = h
		if best != null:
			return best
	var near: Node3D = null
	var near_d := INF
	for h in child.get_tree().get_nodes_in_group("houses"):
		var house := h as Node3D
		if not is_instance_valid(house):
			continue
		var gap := child.global_position.distance_to(house.global_position)
		if gap < near_d:
			near_d = gap
			near = house
	return near


## WHERE, DECIDED ONCE. Asked when harm turns them, never per frame: finding the
## nearest roof walks every house in the world, and a leaving child is on the
## physics tick. (Asked twice is harmless — a lifted child sets off again.)
static func _set_off(child: Villager) -> void:
	child.set_meta("leaving_to", shelter_for(child))
	child.set_meta("leaving_left", GIVES_UP_AFTER)


## One step of the walk. True when they are gone — inside, or simply away — and
## the villager's own arm ends the body; see Villager, State.LEAVING.
##
## The house they were walking to may burn down on the way, and the walk may be
## blocked for good. Neither keeps them here: they have gone anyway.
static func leave_step(child: Villager, delta: float) -> bool:
	var left := float(child.get_meta("leaving_left", 0.0)) - delta
	child.set_meta("leaving_left", left)
	# UNTYPED UNTIL PROVED ALIVE. The house may have burnt down on the way, and
	# putting a freed object into a typed variable is the error, before any
	# check below could catch it.
	var kept: Variant = child.get_meta("leaving_to") if child.has_meta("leaving_to") else null
	if left <= 0.0 or kept == null or not is_instance_valid(kept):
		_let_go(child)
		return true
	var shelter := kept as Node3D
	# `placed`: a building is set on proved ground, so the walk asks no water
	# question of it — see Villager._move_toward.
	if child._move_toward(shelter.global_position, Villager.WALK_SPEED * WALKS_HOME,
			delta, Villager.ARRIVE_DIST, true):
		_let_go(child)
		return true
	return false


static func _let_go(child: Villager) -> void:
	Mauling.free_of(child)
	child._dismount()
