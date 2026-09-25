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
## HOW MANY TIMES RUNNING a child can be sent indoors before they stop coming
## back out. Three: a mistake is one, a bad week is two, and a god who harms the
## same child on three days with no clear day between is not being careless.
const LEAVES_AFTER := 3
## When the morning is, as a fraction of the day — first light. See
## GameState.day_fraction.
const MORNING := 0.25


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
## Any harm that reaches a child — fire, a thrown stone, a fireball, lightning, a
## wolf, the water, the creature, hunger — is turned at the door. They get up,
## walk home, go inside, and STAY INSIDE until the next morning. No
## announcement, no scream, no body, no mourners, no karma, nothing for the
## creature to learn, nothing written over their head. The street is simply
## empty of children for the rest of the day.
##
## THAT IS AIMED AT A PERSON, NOT AT A VILLAGER. Somebody will get bored and try
## to murder the children, and the only thing that keeps that from being a game
## is there being NO PAYOFF: not a punishment (a payoff of its own to the player
## looking for one), not a refusal (a puzzle), but the dullest answer there is.
##
## AND IT IS NOT MEANT TO EMPTY A TOWN. The first draft sent every child it
## touched away for good, and one lightning bolt took a village from thirty-two
## to seventeen: every child ran home and was gone. A reckless god loses the
## town's children for a DAY, which is a cost the village feels — no school, no
## play in the square, a quiet evening. Only a child harmed day after day, with
## no clear day between, stops coming back out and goes to family elsewhere.
## That is what "really bad" means here, and it takes a campaign, not a mistake.
##
## Returns true when the harm was turned. Every door asks this FIRST, before any
## of its own consequences, or the consequences are the payoff.
static func spared(soul: Villager) -> bool:
	if not is_child(soul):
		return false
	take_shelter(soul)
	return true


static func take_shelter(child: Villager) -> void:
	if child.sheltering:
		return
	child.sheltering = true
	# HOW BAD HAS IT BEEN? A day indoors, a day out and unharmed, clears it: a
	# run of hidings only counts while the harm comes back before a whole day
	# has passed without it.
	var today := GameState.day_number()
	var last := int(child.get_meta("hid_on", -99))
	var run := int(child.get_meta("hidings", 0)) if today - last <= 1 else 0
	run += 1
	child.set_meta("hidings", run)
	child.set_meta("hid_on", today)
	child.set_meta("for_good", run >= LEAVES_AFTER)
	child.extinguish()
	child.health = maxf(child.health, 1.0)
	Mauling.free_of(child)
	_set_off(child)
	# In a hand, or in the air: they set off once they are on their feet — see
	# Villager._choose, which hands a sheltering child straight back to `resume`.
	if child.state == Villager.State.HELD or child.state == Villager.State.FALLING:
		return
	resume(child)


## BACK TO WHATEVER SHELTERING THEY WERE DOING — walking, or already indoors.
## Asked by Villager._choose whenever a sheltering child would otherwise pick a
## new job, which is exactly when they have just been set down again.
static func resume(child: Villager) -> void:
	child._dismount()
	child._decision_due = false
	child.state = Villager.State.HIDDEN if child.has_meta("hidden_in") \
		else Villager.State.LEAVING


## O(N) BY DESIGN: once per child, when harm turns them and when a house they
## were hiding in is gone — never on the tick. The walk reads the answer stored
## here; see `leave_step`.
## WHERE THEY GO IN. Their own home first — that is where a child runs — then
## the nearest roof in their village, then the school, then anybody's.
static func shelter_for(child: Villager) -> Node3D:
	if child.home != null and is_instance_valid(child.home) \
			and not child.home.under_construction:
		return child.home
	var town := child.village
	if town != null and is_instance_valid(town):
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
		if town.edubba != null and is_instance_valid(town.edubba):
			return town.edubba
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


static func _set_off(child: Villager) -> void:
	child.set_meta("leaving_to", shelter_for(child))
	child.set_meta("leaving_left", GIVES_UP_AFTER)


## ONE STEP OF THE WALK HOME. True only when a child is GONE FOR GOOD — the
## villager's own arm then ends the body (Villager, State.LEAVING). Arriving to
## hide is not that: they go in, and this hands them to State.HIDDEN.
##
## The house may burn down on the way, and the walk may be blocked for good.
## Neither keeps them in the street: they go in wherever they got to.
static func leave_step(child: Villager, delta: float) -> bool:
	var left := float(child.get_meta("leaving_left", 0.0)) - delta
	child.set_meta("leaving_left", left)
	# UNTYPED UNTIL PROVED ALIVE. Putting a freed house into a typed variable is
	# the error, before any check below could catch it.
	var kept: Variant = child.get_meta("leaving_to") if child.has_meta("leaving_to") else null
	var there := left <= 0.0 or kept == null or not is_instance_valid(kept)
	if not there:
		var shelter := kept as Node3D
		# `placed`: a building is on proved ground, so the walk asks no water
		# question of it — see Villager._move_toward.
		there = child._move_toward(shelter.global_position,
			Villager.WALK_SPEED * WALKS_HOME, delta, Villager.ARRIVE_DIST, true)
	if not there:
		return false
	Mauling.free_of(child)
	child._dismount()
	if bool(child.get_meta("for_good", false)):
		return true
	_go_in(child, kept)
	return false


## INDOORS. Out of sight and out of reach: nothing is drawn, nothing collides,
## nothing can hover or hurt them. The house they are in is remembered so that
## if it burns they come out and find another.
static func _go_in(child: Villager, house: Variant) -> void:
	child.set_meta("hidden_in", house)
	child.set_meta("was_layer", child.collision_layer)
	child.set_meta("was_mask", child.collision_mask)
	child.collision_layer = 0
	child.collision_mask = 0
	child.visible = false
	child.velocity = Vector3.ZERO
	child.state = Villager.State.HIDDEN


## A NIGHT AT HOME. They come out at the first dawn after the day it happened —
## fed and rested, because they have been home with their family. If the house
## is gone from around them, they come out now and find another.
## True when they are out and should take up the day — the villager's own arm
## then asks for a plan.
static func hide_step(child: Villager) -> bool:
	var house: Variant = child.get_meta("hidden_in")
	if house == null or not is_instance_valid(house):
		_come_out(child)
		child.sheltering = false
		take_shelter(child)     # somewhere else, and it counts: that was bad
		return false
	var today := GameState.day_number()
	if today <= int(child.get_meta("hid_on", today)) \
			or GameState.day_fraction() < MORNING:
		return false
	_come_out(child)
	child.hunger = minf(child.hunger, 25.0)
	child.energy = maxf(child.energy, 90.0)
	child.sheltering = false
	return true


static func _come_out(child: Villager) -> void:
	child.remove_meta("hidden_in")
	child.collision_layer = int(child.get_meta("was_layer", 1))
	child.collision_mask = int(child.get_meta("was_mask", 1))
	child.visible = true
