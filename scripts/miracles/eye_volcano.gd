class_name EyeVolcano
extends Node3D
## THE LASER-GUIDED VOLCANO EYES, and the first working in the game that takes
## FIVE runes.
##
##   |  /  V  )  Z      force + fire + earth + ward + fury
##
## Read it and it says itself. Earth and fire is molten rock; fury is violence
## done to it, and those three together are already the volcano. What the last
## two add is the aiming: `force` is the rune of a bolt driven straight, and
## `ward` is the rune of a thing held OVER something — held on it, kept on it.
## Molten rock, meant, driven in a line, and held on what you pointed it at.
##
## WHAT IT ACTUALLY IS: six miniature volcanoes, three blobs apiece, fired one
## eye at a time. Not a beam. Six shots, and you steer every one of them —
## which is the whole difference between a weapon and a hose. Point the hand
## somewhere and the next eye that fires goes there; move it between shots and
## you can walk six small burning mountains across a valley in ten seconds.
##
## The creature is the one it comes out of, and it learns from that. A beast
## whose god keeps handing it the earth's fire becomes something, and what it
## becomes is not a surprise to anybody.

## SIX SHOTS, THREE BLOBS EACH, alternating eyes. These three numbers are the
## whole of what the miracle IS; everything else below is how it looks.
const BLASTS := 6
const BLOBS := 3
## How long between shots. Long enough to move the hand and mean it — a player
## who cannot re-aim between blasts has not been given six shots, they have
## been given one wide one.
const BLAST_EVERY := 1.6
## And how long it waits, holding its fire, when the hand is not on the world.
## The shots keep: pointing away is how you STOP it, not how you waste it.
const PATIENCE := 20.0

## How far the eyes can throw, and how near the miracle must land to find the
## creature at all.
const REACH := 70.0
const GRANTED_WITHIN := 60.0

## ONE MINIATURE VOLCANO. The blobs come down scattered about the aim, and each
## pours its own small dome of rock — three overlapping domes read as a little
## cone, which is what a volcano looks like from far enough away.
const SCATTER := 2.6
const RISE := 0.3
const POUR_REACH := 2.4
const BURN_REACH := 4.6
const HURT := 30.0
## How long a blob is in the air, and how high it arcs on the way.
const FLIGHT := 0.75
const LIFT := 7.0
## Colour of the eyes while this is in them, and how bright they flare to shoot.
const EMBER := Color(1.0, 0.45, 0.12)
const FLARE := Color(1.0, 0.92, 0.55)

## WHERE THE EYES ARE, in the procedural creature's own body: head at 2.1, eyes
## a little above and in front of it, a hand's width to each side. Multiplied by
## the creature's scale, so a beast the size of a tower fires from the height of
## one. A custom model is fired from the same place — close enough, and far
## better than nothing coming out at all.
const EYE_UP := 2.25
const EYE_OUT := 0.6
const EYE_SIDE := 0.18

## What holding this does to the creature, per shot fired.
const LESSON := -1.1


var creature: Creature = null
var left := BLASTS

var _until_next := BLAST_EVERY
var _patience := PATIENCE
var _side := 0            # which eye fires next: 0 left, 1 right
var _glow: Array[OmniLight3D] = []


## GRANT IT. A second casting reloads rather than stacking a second pair of
## eyes on the same head.
static func grant(who: Creature) -> EyeVolcano:
	var held := holding(who)
	if held != null:
		held.left = BLASTS
		held._patience = PATIENCE
		return held
	var eyes := EyeVolcano.new()
	eyes.creature = who
	who.add_child(eyes)
	return eyes


static func holding(who: Creature) -> EyeVolcano:
	for child in who.get_children():
		if child is EyeVolcano:
			return child as EyeVolcano
	return null


func _ready() -> void:
	for side in 2:
		var lamp := OmniLight3D.new()
		lamp.light_color = EMBER
		lamp.light_energy = 1.6
		lamp.omni_range = 5.0
		lamp.shadow_enabled = false
		add_child(lamp)
		_glow.append(lamp)


func _physics_process(delta: float) -> void:
	if creature == null or not is_instance_valid(creature) or left <= 0:
		queue_free()
		return
	_sit_the_glow_on_the_eyes()
	var aim := _where_you_are_pointing()
	if aim == Vector3.INF:
		# HOLDING FIRE. Nothing is spent; the loaded eyes simply wait, and the
		# creature stands there with them lit, which is its own warning.
		_patience -= delta
		if _patience <= 0.0:
			GameState.announce("The fire goes out of your creature's eyes, unspent.")
			queue_free()
		return
	_patience = PATIENCE
	creature._face(aim)
	_until_next -= delta
	if _until_next > 0.0:
		return
	_until_next = BLAST_EVERY
	_fire(aim)


## WHERE THE GOD IS POINTING. The hand's own ground point, clipped to what the
## eyes can actually throw — beyond their reach they fire as far down that line
## as they can, which reads as a creature straining rather than a miracle
## silently refusing.
func _where_you_are_pointing() -> Vector3:
	var hand := MiracleManager.divine_hand
	if hand == null or not is_instance_valid(hand):
		return Vector3.INF
	var spot: Vector3 = hand.ground_point
	if spot == Vector3.ZERO:
		return Vector3.INF
	var from := creature.global_position
	var flat := Vector3(spot.x - from.x, 0.0, spot.z - from.z)
	if flat.length() > REACH:
		spot = from + flat.normalized() * REACH
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		spot.y = world.surface_at(spot.x, spot.z)
	return spot


## Where one eye is, in the world, right now.
func _eye_at(side: int) -> Vector3:
	var facing := creature.global_transform.basis
	var across := 1.0 if side == 1 else -1.0
	return creature.global_position \
		+ Vector3.UP * (EYE_UP * creature.scale.y) \
		+ facing.z.normalized() * (EYE_OUT * creature.scale.x) \
		+ facing.x.normalized() * (EYE_SIDE * across * creature.scale.x)


func _sit_the_glow_on_the_eyes() -> void:
	for side in 2:
		if side < _glow.size() and is_instance_valid(_glow[side]):
			_glow[side].global_position = _eye_at(side)
			# The eye that is about to go is the bright one.
			_glow[side].light_energy = 3.4 if side == _side else 1.6


## ONE EYE FIRES: three blobs, scattered about the aim, each its own small
## eruption where it lands.
func _fire(aim: Vector3) -> void:
	var from := _eye_at(_side)
	if _side < _glow.size() and is_instance_valid(_glow[_side]):
		_glow[_side].light_color = FLARE
		_glow[_side].light_energy = 9.0
	_side = 1 - _side
	left -= 1
	SoundBank.play_at("boom", aim, -1.0)
	_shake()
	for i in BLOBS:
		var spread := Vector3(randf_range(-SCATTER, SCATTER), 0.0,
			randf_range(-SCATTER, SCATTER))
		_throw_blob(from, aim + spread)
	creature.witness(LESSON)
	creature.heart.stir("fury", 0.12)
	creature.express("angry", 1.2)
	if left <= 0:
		GameState.announce("The last of the fire leaves your creature's eyes.")


## A blob out of the eye, arcing to where it was sent, and a miniature volcano
## where it lands. The arc is a single quadratic Bezier, exactly as the
## mountain's own globs are thrown — see MiracleManager._hurl_glob.
func _throw_blob(from: Vector3, to: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		to.y = world.surface_at(to.x, to.z)
	var blob := Util.sphere(randf_range(0.3, 0.55), EMBER, from, true)
	get_tree().current_scene.add_child(blob)
	blob.global_position = from
	var apex := from.lerp(to, 0.45) + Vector3(0, LIFT * randf_range(0.7, 1.3), 0)
	var arc := create_tween()
	arc.tween_method(func(t: float) -> void:
		if is_instance_valid(blob):
			var a := from.lerp(apex, t)
			var b := apex.lerp(to, t)
			blob.global_position = a.lerp(b, t),
		0.0, 1.0, FLIGHT).set_trans(Tween.TRANS_LINEAR)
	arc.tween_callback(func() -> void:
		if is_instance_valid(blob):
			blob.queue_free()
		_land(to))


## WHAT A BLOB DOES WHERE IT COMES DOWN. Everything goes through the manager's
## own doors, so this burns exactly what molten rock burns — and, the reason it
## is routed this way rather than written out here, it reaches the HERD MASS
## and not only the couple of dozen head that happen to be real nodes.
## See tools/herd_reach.py.
func _land(at: Vector3) -> void:
	MiracleManager.pour_lava_at(at, RISE * randf_range(0.8, 1.2),
		POUR_REACH * randf_range(0.9, 1.2))
	MiracleManager.ignite_trees_near(at, BURN_REACH)
	MiracleManager.ignite_animals_near(at, BURN_REACH)
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		var d := villager.global_position.distance_to(at)
		if d < POUR_REACH:
			villager.ignite()
			villager.take_damage(HURT, true)
		elif d < BURN_REACH * 3.0:
			villager.scare(at)


func _shake() -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig") as CameraRig
	if rig != null:
		rig.shake(0.5)
