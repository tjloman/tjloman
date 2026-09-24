class_name RockDeposit
extends StaticBody3D
## A cluster of boulders that quarriers pick apart for stone — a deep vein:
## up to 300 stone before it's spent. The boulders visibly shrink as the
## deposit is worked down.

const STONE_PER_HARVEST := 3
const TOTAL_STONE := 300

## THE LADDER OF STONES, from a thing you could throw at a bird to a thing that
## has to be cut down before anybody can carry any of it.
##
## Every rock in the world was one rock: three hundred stone, one mesh, one
## behaviour, scattered two or three to a hillside. So a riverbank had no
## pebbles on it, and the only way to interact with stone at all was to work a
## vein like a quarry.
##
## `whole` is the size at which a thing stops being liftable and starts being
## a job. Under it the hand takes the rock — the actual rock, gone from the
## ground — and over it the rock stays where it is and gives up pieces, which
## is what cleaving means and why a tor is scenery until you work at it. That
## is expressed as an ADVERB and not as a number anybody has to test: a small
## stone joins PICKABLE, a big one joins QUARRIED, and both are just true. See
## Affords.
##
## `worth` is stone; `looks` is the model name, tried before the plain "rock"
## so `rock_pebble.glb` takes over every pebble in the world the day it lands.
const SIZES: Array[Dictionary] = [
	{"kind": "pebble", "worth": 1, "size": 0.22, "whole": true},
	{"kind": "cobble", "worth": 4, "size": 0.40, "whole": true},
	{"kind": "block", "worth": 15, "size": 0.75, "whole": true},
	{"kind": "boulder", "worth": 60, "size": 1.2, "whole": false},
	{"kind": "tor", "worth": TOTAL_STONE, "size": 1.9, "whole": false},
]

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

## WHICH RUNG OF `SIZES` this one is. Set before it enters the tree; everything
## else about the rock follows from it.
var rung := 4
## WHAT KIND OF ROCK THIS IS, over and above its size — granite, flint, chalk.
## Names a mesh and nothing else, so a new kind of stone is a file in
## res://models/ and a word here, and no other file ever learns it.
var style := ""
var stone_left := TOTAL_STONE
var _boulders: Array[MeshInstance3D] = []


## What this rock is, as a row of SIZES.
func spec() -> Dictionary:
	return SIZES[clampi(rung, 0, SIZES.size() - 1)]


## A stone small enough to pick up entire.
func liftable_whole() -> bool:
	return bool(spec()["whole"])


func _ready() -> void:
	var row := spec()
	stone_left = int(row["worth"])
	add_to_group("rock_deposits")
	# THE HAND CAN REACH IT NOW. A vein was scenery with a number on it: the
	# only way stone ever left one was a villager with a pick, and a god who
	# wanted a rock — to build with, to give, or to throw — had no way to get
	# one at all.
	#
	# WHICH ADVERBS A ROCK ANSWERS TO DEPEND ON HOW BIG IT IS, and that is the
	# whole of the difference between a pebble and a tor. Both are grabbable;
	# what the grab DOES is the thing the size decides, and neither the hand
	# nor the creature has to ask how heavy anything is to find out.
	add_to_group(Affords.PICKABLE)
	add_to_group(Affords.QUARRIED)
	collision_layer = 1
	collision_mask = 0
	set_meta("hover_name", "Rock deposit")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = float(row["size"])
	col.shape = shape
	col.position = Vector3(0, float(row["size"]) * 0.6, 0)
	add_child(col)

	# THE STYLED MESH FIRST, then the plain one — the same ladder a tree climbs
	# (see WildTree). Drop `rock_flint.glb` in res://models/ and every flint
	# outcrop in the world takes it, with `rock.glb` still answering for the
	# rest and the generated boulders answering for both if neither exists.
	# THE LADDER OF MESHES: this exact kind of rock at this exact size, then
	# either on its own, then the plain one. `rock_flint_pebble`, `rock_flint`,
	# `rock_pebble`, `rock` — drop any of them in and it takes over from there
	# down. Same ladder a tree climbs; see WildTree.
	var named: Array = []
	if style != "":
		named.append("rock_%s_%s" % [style, row["kind"]])
		named.append("rock_" + style)
	named.append("rock_" + String(row["kind"]))
	named.append("rock")
	var custom := ModelBank.instantiate_any(named)
	if custom != null:
		# ON ITS FOOTING, whatever pivot the model was authored with — of
		# whichever of these names the bank actually had. See
		# ModelBank.footing_any.
		custom.position.y += ModelBank.footing_any(named)
		# A custom rock model won't shrink as it's worked, but quarries fine.
		add_child(custom)
	else:
		var wide: float = float(row["size"])
		for i in 3:
			var r := randf_range(0.42, 0.75) * wide
			var b := Util.lite_sphere(r, Color(0.52, 0.51, 0.53),
				Vector3(randf_range(-0.6, 0.6) * wide, r * 0.6,
					randf_range(-0.6, 0.6) * wide))
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
## `most` is how much the one asking can actually manage. THIS IS THE WHOLE OF
## "cleave it down to size": a full-grown beast takes a boulder off in one
## piece, a whelp has to keep chipping, and the rock does not care which — it
## gives up what was asked for and keeps the rest. A pebble comes away entire
## on the first ask whoever is asking, because there was only ever one stone
## in it.
func prise(most := STONE_PER_BOULDER) -> ResourceItem:
	if stone_left <= 0:
		return null
	var taken := mini(maxi(most, 1), stone_left)
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
	var row := spec()
	var what := String(row["kind"]).capitalize()
	if liftable_whole():
		return "%s — %d stone. Take it." % [what, stone_left]
	# TELLING THE PLAYER WHICH KIND OF ROCK THIS IS is the whole reason a rock
	# knows whether it can be lifted whole. A tor and a cobble look like the
	# same grey lump from a god's height, and reaching for one and getting a
	# chip off it — with no word of explanation — reads as the game failing to
	# pick it up rather than as the rock being too big to move.
	return "%s — %d stone left. Too big to lift; take hold to cleave a piece off." \
		% [what, stone_left]
