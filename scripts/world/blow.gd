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
## RAISED WHEN THE THROWS WERE SLOWED. Damage is mass times speed, so cutting
## the ceiling from 55 to 38 quietly took a third off every blow in the game —
## a stone went from twelve throws to seventeen to fell a house without anybody
## deciding it should. This is the knob that puts it back: what a throw is
## WORTH is a separate question from how fast it flies, and slowing the flight
## to make it watchable should not also make it feeble.
const PER_MOMENTUM := 1.45

## Under this a thing in flight has stopped flying — used for settling and for
## skipping, where a speed is the right question and always was.
const MATTERS_ABOVE := 7.0

## And under THIS a landing is a thing being set down rather than a blow — AND
## IT IS MOMENTUM,
## not speed.
##
## It was a speed alone, seven metres a second, which says that a pebble flicked
## quickly is a blow and a boulder walked slowly into a wall is not. That is
## backwards, and it is most of "I was smacking houses with stones and it wasn't
## doing anything": a heavy thing is hard to get moving and does not need to be
## moving fast, which is the entire reason anybody picks up a heavy thing.
##
## Mass times speed, so the bar is the same bar the damage is reckoned from
## (see PER_MOMENTUM). Fifteen stone weighs 7.6 and clears it at under two
## metres a second; a single cut block weighs 2.0 and needs seven, which is
## about a throw; and a joint of meat set down gently is still a thing being
## set down.
const MOMENTUM_MATTERS := 14.0

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

## SKIPPING ------------------------------------------------------------------
##
## WATER IS NOT A COLLIDER. A chunk's water is one MeshInstance3D quad with
## nothing behind it, which is right — a lake you can walk into wants no
## physics body — and it means a thrown stone passed straight through the
## surface and landed on the seabed with a thump. There was no such thing as
## hitting water at all.
##
## So the one thing already watching a thrown body every frame does it: a Blow
## knows where the stone was last frame and where it is now, which is all a
## skip needs. Cross the surface going down, shallow enough and fast enough,
## and it comes back off it.
##
## THE ANGLE IS THE WHOLE GAME, exactly as it is on a real pond. Lob a rock in
## and it sinks; send it out flat and it walks. SKIP_ANGLE is measured off the
## water, so a smaller number is a stricter throw.
const SKIP_ANGLE := deg_to_rad(22.0)
const SKIP_ABOVE := 7.0
## What a skip keeps: most of its forward run, and rather MORE than all of its
## bounce — which looks like a mistake and is the thing that makes skipping
## work at all.
##
## Water LIFTS a stone that hits it flat; that is the whole mechanism, and it
## is why a skipping stone rises between hops instead of settling. At a bounce
## of 0.45, correct for a rock hitting a rock, a pebble managed six skips over
## a total run of THREE METRES — technically a skip, invisible at any camera
## distance anybody plays at.
##
## And it is what ENDS the run, with no counter and no cutoff. The upward part
## grows each hop while the forward part shrinks, so the angle steepens by
## itself until it passes SKIP_ANGLE and the stone goes in. Which is exactly
## how it ends on a real pond: the last skip is always the steep one.
const SKIP_CARRY := 0.86
const SKIP_BOUNCE := 1.15
## And how heavy a thing can be and still skip. A pebble walks; a boulder is a
## splash — which is funny once, and is why teaching a creature to skip a
## BOULDER is a thing worth watching rather than a thing that works.
const SKIP_HEFT := 6.0

## How many times it has come off the water. Kept so the landing can say, and
## so a creature watching has something to be impressed by.
var skips := 0

var _by_god := true
var _was := 0.0
var _left := FLIGHT_MOST
## Where it was last frame, so a surface crossing can be spotted between two
## positions rather than guessed at from one.
var _last_at := Vector3.INF


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
	Ledger.open(&"Blow")
	var thing := get_parent() as RigidBody3D
	if thing == null or not is_instance_valid(thing):
		queue_free()
		return
	_left -= delta
	if _skipped(thing):
		_was = thing.linear_velocity.length()
		_last_at = thing.global_position
		return
	_last_at = thing.global_position
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


## DID IT COME OFF THE WATER? True on the frame it did, which is also a frame
## on which nothing else should happen to it — it has not landed, it has
## bounced, and reading its speed as an impact would end the throw.
func _skipped(thing: RigidBody3D) -> bool:
	if is_inf(_last_at.x) or thing.mass > SKIP_HEFT:
		return false
	var at := thing.global_position
	var down := thing.linear_velocity
	if down.y >= 0.0:
		return false
	var world := thing.get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return false
	var top := world.water_level_at(at.x, at.z)
	# -INF is dry ground: there is no water here to come off.
	if is_inf(top) or _last_at.y <= top or at.y > top:
		return false
	var speed := down.length()
	if speed < SKIP_ABOVE:
		return false
	# THE ANGLE OFF THE WATER, not off the vertical. A stone falling steeply
	# has a big number here and goes in.
	var flat := Vector2(down.x, down.z).length()
	if flat < 0.01 or atan2(-down.y, flat) > SKIP_ANGLE:
		return false
	skips += 1
	thing.linear_velocity = Vector3(
		down.x * SKIP_CARRY, -down.y * SKIP_BOUNCE, down.z * SKIP_CARRY)
	thing.global_position = Vector3(at.x, top + 0.05, at.z)
	SoundBank.play_at("whisper", at, -4.0, 0.3, 1.4 + float(skips) * 0.12)
	return true


## IT CAME DOWN HERE, THIS FAST, WEIGHING THIS MUCH. The one door in, so a
## tree that flies on its own arithmetic and a stone that flies on Godot's
## arrive at the same consequences.
static func lands(thing: Node3D, at: Vector3, speed: float, mass: float,
		by_god: bool) -> void:
	var heft := maxf(mass, 0.2)
	if speed * heft < MOMENTUM_MATTERS:
		return
	var force := speed * heft * PER_MOMENTUM
	var tree := thing.get_tree()
	if tree == null:
		return
	var wrecked := 0
	var hurt := 0.0
	for b in tree.get_nodes_in_group(Affords.BURNABLE):
		var built := b as Node3D
		if not is_instance_valid(built) or built == thing:
			continue
		# TO THE WALL, NOT TO THE MIDDLE. See Util.within: a longhouse's corner
		# is 3.67m from its origin and this reached 2.4m, so every building
		# bigger than a hut was simply immune to being hit.
		if not Util.within(built, at, SPLASH):
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
