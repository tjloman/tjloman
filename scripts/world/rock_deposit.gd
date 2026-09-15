class_name RockDeposit
extends StaticBody3D
## A cluster of boulders that quarriers pick apart for stone — a deep vein:
## up to 300 stone before it's spent. The boulders visibly shrink as the
## deposit is worked down.

const STONE_PER_HARVEST := 3
const TOTAL_STONE := 300

## WHAT A GOD PRISES LOOSE IN ONE GO, against the three a quarrier chips off
## with a pick. A hand that can lift a bull does not work a rock face by the
## handful — and twenty of these is the whole vein, which is about right for
## something that took a village a season to find.
##
## It is also the weight of the thing: ResourceItem.refresh_bundle reckons mass
## from the count, so this number is what decides whether a boulder through a
## roof is a nuisance or a siege. Fifteen comes to about three throws for a
## house — see tools/blow.py.
const STONE_PER_BOULDER := 15

## WHAT KIND OF ROCK THIS IS. Names a mesh and nothing else so far — the
## adverb is what the hand and the creature go by, so a new kind of stone is a
## file in res://models/ and a word here, and neither of them ever learns it.
var style := "rock"
var stone_left := TOTAL_STONE
var _boulders: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("rock_deposits")
	# THE HAND CAN REACH IT NOW. A vein was scenery with a number on it: the
	# only way stone ever left one was a villager with a pick, and a god who
	# wanted a rock — to build with, to give, or to throw — had no way to get
	# one at all.
	#
	# QUARRIED AND NOT PICKABLE, and the difference is not a nicety: a hand
	# that tries to LIFT this drags a StaticBody3D through the terrain. You
	# take a piece off it and leave the rest. See Affords.
	add_to_group(Affords.PICKABLE)
	add_to_group(Affords.QUARRIED)
	collision_layer = 1
	collision_mask = 0
	set_meta("hover_name", "Rock deposit")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.2
	col.shape = shape
	col.position = Vector3(0, 0.7, 0)
	add_child(col)

	# THE STYLED MESH FIRST, then the plain one — the same ladder a tree climbs
	# (see WildTree). Drop `rock_flint.glb` in res://models/ and every flint
	# outcrop in the world takes it, with `rock.glb` still answering for the
	# rest and the generated boulders answering for both if neither exists.
	var custom := ModelBank.instantiate_any(["rock_" + style, "rock"])
	if custom != null:
		# A custom rock model won't shrink as it's worked, but quarries fine.
		add_child(custom)
	else:
		for i in 3:
			var r := randf_range(0.5, 0.9)
			var b := Util.lite_sphere(r, Color(0.52, 0.51, 0.53),
				Vector3(randf_range(-0.7, 0.7), r * 0.6, randf_range(-0.7, 0.7)))
			add_child(b)
			_boulders.append(b)


## One quarrying pass: yields stone, wears the pile down, frees when spent.
func quarry() -> int:
	if stone_left <= 0:
		return 0
	var taken := mini(STONE_PER_HARVEST, stone_left)
	stone_left -= taken
	_wear_down()
	if stone_left <= 0:
		queue_free()
	return taken


## The pile shrinks as the vein empties, however the stone is leaving it.
func _wear_down() -> void:
	var fraction := float(stone_left) / TOTAL_STONE
	for i in _boulders.size():
		var b := _boulders[i]
		if not is_instance_valid(b):
			continue
		# Boulders shed one by one as the vein empties; survivors shrink.
		if fraction < float(i) / _boulders.size():
			b.visible = false
		else:
			b.scale = Vector3.ONE * lerpf(0.45, 1.0, fraction)


## PRISE ONE LOOSE. Returns a boulder, or null if there is nothing left worth
## taking. The vein wears down exactly as it does under a pick, because it is
## the same stone either way — a god taking it is quarrying, just rudely.
##
## The caller owns what comes back and has to put it in the tree; it is made
## with no parent so it can go straight into a hand or into the world without
## being moved twice.
func prise() -> ResourceItem:
	if stone_left <= 0:
		return null
	var taken := mini(STONE_PER_BOULDER, stone_left)
	stone_left -= taken
	_wear_down()
	var rock := ResourceItem.new()
	rock.kind = "stone"
	rock.count = taken
	if stone_left <= 0:
		queue_free()
	return rock


func is_exhausted() -> bool:
	return stone_left <= 0


func hover_text() -> String:
	return "Rock deposit — %d stone. Take hold to prise a boulder loose." % stone_left
