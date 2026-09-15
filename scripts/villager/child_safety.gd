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
