class_name Blow
extends Node
## WHAT A THROWN THING DOES WHEN IT ARRIVES.
##
## It did nothing. A stone hurled through the wall of a house passed through
## the world without consequence — no damage to the house, no harm to anybody
## standing in it, no karma. Only three things could hurt a building at all: a
## fireball's core, an earthquake, and the creature deliberately smashing one.
## The whole throwing mechanic — the sling, the aftertouch, the arc, the
## momentum read off a finger — landed on nothing.
##
## THE COST IS PAID AT THE LANDING, NOT EVERY FRAME. Nothing here monitors
## contacts, and no thrown object carries a physics callback: a Blow is a NODE
## that a throw hangs on its own projectile and that frees itself the moment
## the flight ends. A world of resting rocks costs exactly nothing, which is
## the arrangement that makes "collision only after a throw" true rather than
## aspirational.
##
## THREE FAMILIES OF THROWABLE and every one of them already had a landing to
## hook:
##
##   RIGID BODIES — stone, lumber, food, a corpse — get one of these hung on
##   them at release. It watches for the speed to fall off a cliff, which is
##   what an impact IS, and fires with the speed it had the instant before.
##
##   A TREE flies on its own arithmetic and calls `_land` with its own impact
##   speed. See WildTree.
##
##   A PERSON OR A BEAST lands in their own FALLING state and already takes
##   their own fall damage. They are not handled here, on purpose: what a
##   thrown villager does to a wall is a smaller question than what the wall
##   does to them, and that half already works.

## WHAT A BLOW IS WORTH, in damage per unit of momentum. A two-kilo stone at
## twenty metres a second comes to about forty — a tenth of a house, a fifth of
## a field, and rather more than a villager can stand. Tuned so that throwing
## things at a town is a real way to wreck it and a slow one: a house is a
## dozen good hits, which is the difference between vandalism and a miracle.
const PER_MOMENTUM := 1.0

## Under this it is a thing being set down, not a blow.
const MATTERS_ABOVE := 7.0

## How far the shock reaches from where it came down. Small: this is an impact,
## not an explosion, and a rock through one wall should not shake the street.
const SPLASH := 2.4

## HOW MUCH OF A BUILDING'S BLOW GOES TO THE PEOPLE IN IT, and how much of a
## person's to the building. A stone through a wall mostly hits the wall.
const TO_FLESH := 0.45

## WHAT IT COSTS YOU, and NEARLY ALL OF IT IS AT THE OUTCOME.
##
## Chipping a wall is vandalism and is charged like vandalism; bringing the
## house down is the deed and carries the weight. The first draft had it the
## other way round — a fifth of a point per landed stone, which came to half a
## death-by-fire for one thrown rock and more than a burnt village for pulling
## down a single roof. Pelting a wall is not that.
##
## Set against the scale already in VillagerNeeds: a death by fire is -2.5 and
## a death nobody caused is -0.5, so a wrecked home at -8 is the worst single
## thing in that table, which is about right for taking a family's house away.
## And the death a throw causes is charged AGAIN on top, by `mourn` — which is
## how a rock that takes a roof off is one price and a rock that takes a roof
## off and kills the people under it is two.
const KARMA_PER_HURT := -0.004
const KARMA_PER_WRECK := -8.0

## AND WHAT YOUR CREATURE'S THROWS COST YOU. Less than your own, because it is
## not your hand — and not nothing, because a beast that hurls rocks at houses
## learned it from somebody and you are the only teacher it has. See
## CreatureMind.witness_god_deed, which is the channel it learned through.
const YOURS_WHEN_IT_THREW := 0.35

## How fast the speed has to fall in one physics step to be an impact rather
## than air resistance, and how long a Blow waits before giving up on a throw
## that never really landed.
const STOPPED_BY := 0.45
const FLIGHT_MOST := 12.0

var _by_god := true
var _was := 0.0
var _left := FLIGHT_MOST


## HANG ONE ON A THROW. `by_god` is false when the creature threw it — see
## YOURS_WHEN_IT_THREW. Does nothing for a body that cannot be thrown hard
## enough to matter, so a dropped apple costs no node.
static func ride(thing: Node3D, by_god: bool) -> void:
	if not is_instance_valid(thing) or not thing is RigidBody3D:
		return
	# One per flight. Catching a thing and hurling it again should not stack
	# two watchers that both fire on the same landing.
	var old := thing.get_node_or_null("blow")
	if old != null:
		old.queue_free()
	var blow := Blow.new()
	blow.name = "blow"
	blow._by_god = by_god
	thing.add_child(blow)


func _physics_process(delta: float) -> void:
	var thing := get_parent() as RigidBody3D
	if thing == null or not is_instance_valid(thing):
		queue_free()
		return
	_left -= delta
	var now := thing.linear_velocity.length()
	# THE SPEED THE INSTANT BEFORE is the one that matters: by the time a
	# collision has been resolved the projectile is already slow, and reading it
	# then values every blow at nothing.
	if _was > MATTERS_ABOVE and now < _was * STOPPED_BY:
		lands(thing, thing.global_position, _was, thing.mass, _by_god)
		queue_free()
		return
	if _left <= 0.0 or (thing.sleeping and _was < MATTERS_ABOVE):
		queue_free()
		return
	_was = now


## IT CAME DOWN HERE, THIS FAST, WEIGHING THIS MUCH. The one door in, so a
## tree that flies on its own arithmetic and a stone that flies on Godot's
## arrive at the same consequences.
static func lands(thing: Node3D, at: Vector3, speed: float, mass: float,
		by_god: bool) -> void:
	if speed < MATTERS_ABOVE:
		return
	var force := speed * maxf(mass, 0.2) * PER_MOMENTUM
	var tree := thing.get_tree()
	if tree == null:
		return
	var wrecked := 0
	var hurt := 0.0
	for b in tree.get_nodes_in_group("burnable"):
		var built := b as Node3D
		if not is_instance_valid(built) or built == thing:
			continue
		if built.global_position.distance_to(at) > SPLASH:
			continue
		if not built.has_method("damage"):
			continue
		var landed := force * (1.0 - TO_FLESH)
		built.call("damage", landed)
		# WHAT WAS ACTUALLY DONE, not what was thrown. This counted the whole
		# force while the villager branch below counted only the share that
		# reached them, so the same blow was charged at two different rates
		# depending on what it hit.
		hurt += landed
		if not is_instance_valid(built) or built.is_queued_for_deletion():
			wrecked += 1
	for v in tree.get_nodes_in_group("villagers"):
		var soul := v as Villager
		if soul == null or not is_instance_valid(soul) or soul == thing:
			continue
		if soul.global_position.distance_to(at) > SPLASH:
			continue
		# `by_god` is passed through as the damage's own flag, which is what
		# lets VillagerNeeds tell a stoning from a wolf when it comes to
		# reckoning the death — see Villager.take_damage.
		soul.take_damage(force * TO_FLESH, by_god)
		hurt += force * TO_FLESH
	if hurt <= 0.0:
		return
	_reckon(hurt, wrecked, by_god)


## WHAT IT COST. A share when the creature threw it, because a beast that
## hurls rocks at houses had a teacher.
static func _reckon(hurt: float, wrecked: int, by_god: bool) -> void:
	var owed := hurt * KARMA_PER_HURT + float(wrecked) * KARMA_PER_WRECK
	if not by_god:
		owed *= YOURS_WHEN_IT_THREW
	if owed != 0.0:
		GameState.shift_alignment(owed)
