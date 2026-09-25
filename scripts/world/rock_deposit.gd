class_name RockDeposit
extends RigidBody3D
## EVERY ROCK IN THE WORLD, from a chip you skip off a pond to a thing the size
## of a hut.
##
## IT USED TO BECOME SOMETHING ELSE THE MOMENT YOU TOUCHED IT. A rock was
## scenery with a number on it, and the only way stone ever left one was for the
## hand to `prise` a bundle out of it — so picking up a field rock handed you
## fifteen units of building material and the rock itself vanished. You could
## not carry a rock. You could not drop one on a roof. What you were throwing
## was a crate.
##
## A ROCK IS NOW A ROCK, all the way through. The hand lifts the thing itself,
## with its own mesh and its own weight; it flies, it lands on somebody's house,
## it rolls down the hill and lies where it stops, and it is still the same
## rock. It only stops being one at a storehouse door, which is where stone
## turns into stores.
##
## WHAT A ROCK IS WORTH climbs the same ladder a tree does — WildTree.TIMBER,
## the running sum of the Fibonacci sequence — and for the same reason: a thing
## is worth everything it has been. One, two, four, seven, twelve, twenty,
## thirty-three, fifty-four, eighty-eight, a hundred and forty-three. The top of
## it is about the size of a hut and a fledgling has no hope of lifting it.
##
## AND IT CAN BE BROKEN DOWN. Crack a rock enough times and it comes apart into
## TWO of the rung below — which is more stone than you started with, because
## twice eighty-eight is a hundred and seventy-six. That is the one way in the
## game to end up with more stone than the map was made with, and it is bounded:
## pulverising a hundred-and-forty-three all the way to chips yields 512 and not
## a grain more, and costs five hundred and eleven cracks to do it. See
## tools/stones.py, which prints the whole ladder and the ceiling.
##
## A VEIN IS THE OTHER THING, and it is unchanged: an outcrop too much a part of
## the hill to lift, three hundred stone deep, worked by quarriers with picks
## and by a god too impatient to wait for them. That is what a village's stone
## economy stands on, and none of the above touches it.

const STONE_PER_HARVEST := 3
const TOTAL_STONE := 300

## WHAT A GOD PRISES OFF AN OUTCROP IN ONE PULL, against the three a quarrier
## chips off with a pick. Twenty of these is the whole vein, which is about
## right for something that took a village a season to find.
##
## It applies ONLY to outcrops now. A rock on the ladder is lifted whole and is
## worth what its rung says — this is the hill giving up a piece of itself, and
## the piece is a bundle of resource because that is all a piece of a hill is.
const STONE_PER_BOULDER := 15

## THE LADDER OF WORTH, and it is WildTree.TIMBER written out a second time.
##
## It cannot be `const WORTH := WildTree.TIMBER`: Godot resolves constants
## across `class_name` scripts at parse time and refuses a cycle, and this file
## and that one are both reachable from the chunk that scatters them. Two
## classes in this codebase have been through that already. So it is written
## twice and tools/stones.py fails the build the day the two disagree.
const WORTH: Array[int] = [1, 2, 4, 7, 12, 20, 33, 54, 88, 143]

## WHAT EACH RUNG IS CALLED — for the player, and for the model ladder. Drop
## `rock_boulder.glb` in res://models/ and every rung-five rock in the world
## takes it, with `rock.glb` still answering for the rest.
const NAMES: Array[String] = ["pebble", "chip", "cobble", "block", "slab",
	"boulder", "crag", "tor", "monolith", "megalith"]

## HOW BIG A ROCK OF A GIVEN WORTH IS, as a radius in metres. The cube root,
## because worth is volume and a rock is a lump: the ladder then runs from a
## pebble you could palm to a megalith two and a half metres across, which is
## a hut. A flat scale gave a hundred-and-forty-three-stone rock a hundred and
## forty-three times a pebble's radius, which is a mountain.
const GIRTH := 0.235

## WHAT A ROCK WEIGHS, per stone of worth, over a bare two.
##
## THE SAME LINE A TREE USES — see WildTree._land, which hands Blow
## `2.0 + timber() * 0.12`. A hundred-and-forty-three-stone rock and a
## hundred-and-forty-three-timber oak weigh the same, because they are the same
## number off the same ladder, and there is no reason on earth they should not.
## At a good throw that is about three quarters of a house in one blow, which is
## "more than half the hut's damage in a single throw" and stops short of a
## building being a one-shot. See tools/blow.py.
const HEFT_BARE := 2.0
const HEFT_PER_STONE := 0.12

## HOW MANY CRACKS IT TAKES TO BREAK ONE OPEN: its rung. A cobble goes in two,
## a megalith in nine. Cracking is a double tap, so this is the one thing in the
## game that is bought purely with the player's own time — which is the point.
## A pebble is rung zero and cannot be broken at all; there is nothing in it.
const CRACKS_PER_RUNG := 1

## WHERE THE HALVES GO when a rock comes apart — half a metre either side of
## where it stood, so they are two rocks and not one rock drawn twice.
const SPLIT_APART := 0.55

## WHICH RUNG OF `WORTH` this one is. Set before it enters the tree; everything
## else about the rock follows from it. Ignored on a vein.
var rung := 4
## AN OUTCROP, not a rock: part of the hill, three hundred stone deep, quarried
## rather than lifted. The one kind of stone a god cannot pick up.
var vein := false
## WHAT KIND OF ROCK THIS IS, over and above its size — granite, flint, chalk.
## Names a mesh and nothing else, so a new kind of stone is a file in
## res://models/ and a word here, and no other file ever learns it.
var style := ""
var stone_left := 1

var _cracks := 0
var _boulders: Array[MeshInstance3D] = []


func _init() -> void:
	# SCENERY UNTIL SOMEBODY LIFTS IT. A frozen rigid body in static mode is a
	# static body — it is out of the solver entirely — so a hillside of two
	# hundred rocks costs what it always did. Being a RigidBody at all is what
	# lets the hand throw the rock ITSELF rather than a crate of stone: the
	# whole release path (unfreeze, velocity, Blow.ride) already exists for
	# rigid bodies and none of it had to be written again. See
	# DivineHand._release_body.
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	# Layer 1 as it always was, so people walk round it and the ground ray
	# finds it; masking ground and props so a thrown one hits the hill and the
	# houses on it.
	collision_layer = 1
	collision_mask = 1 | 4
	var phys := PhysicsMaterial.new()
	phys.friction = 1.0
	phys.bounce = 0.05      # stone does not bounce; it thuds and rolls
	physics_material_override = phys
	angular_damp = 1.4


func _ready() -> void:
	stone_left = worth()
	add_to_group("rock_deposits")
	# WHICH ADVERBS A ROCK ANSWERS TO DEPEND ON WHETHER IT IS PART OF THE HILL,
	# and that is the whole of the difference. A rock is PICKABLE and nothing
	# else — the hand takes the rock. A vein is QUARRIED and nothing else — the
	# hand takes a piece and the vein stays. Neither the hand nor the creature
	# has to ask how heavy anything is to find out which; see Affords.
	#
	# It used to be BOTH, on everything, with QUARRIED tested first — which is
	# exactly why every rock in the world turned into a bundle of resource the
	# instant it was touched.
	add_to_group(Affords.QUARRIED if vein else Affords.PICKABLE)
	set_meta("hover_name", kind_name().capitalize())

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = girth()
	col.shape = shape
	col.position = Vector3(0, girth() * 0.6, 0)
	add_child(col)
	# The centre of mass sits at the middle of the rock rather than at the
	# pivot under it, or a thrown megalith cartwheels about a point in the air.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, girth() * 0.6, 0)
	mass = heft()
	# A rock that has been thrown and has come to rest is scenery again.
	sleeping_state_changed.connect(_on_sleep_changed)

	# THE LADDER OF MESHES: this exact kind of rock at this exact size, then
	# either on its own, then the plain one. `rock_flint_pebble`, `rock_flint`,
	# `rock_pebble`, `rock` — drop any of them in and it takes over from there
	# down. Same ladder a tree climbs; see WildTree.
	var named: Array = []
	if style != "":
		named.append("rock_%s_%s" % [style, kind_name()])
		named.append("rock_" + style)
	named.append("rock_" + kind_name())
	named.append("rock")
	var custom := ModelBank.instantiate_any(named)
	if custom != null:
		# ON ITS FOOTING, whatever pivot the model was authored with — of
		# whichever of these names the bank actually had. See
		# ModelBank.footing_any.
		custom.position.y += ModelBank.footing_any(named)
		custom.scale = Vector3.ONE * girth()
		add_child(custom)
	else:
		var wide := girth()
		for i in 3:
			var r := randf_range(0.42, 0.75) * wide
			var b := Util.lite_sphere(r, Color(0.52, 0.51, 0.53),
				Vector3(randf_range(-0.6, 0.6) * wide, r * 0.6,
					randf_range(-0.6, 0.6) * wide))
			add_child(b)
			_boulders.append(b)


## WHAT THIS ROCK IS WORTH IN STONE. A vein is worth its whole depth; a rock is
## worth its rung of the ladder.
func worth() -> int:
	if vein:
		return TOTAL_STONE
	return WORTH[clampi(rung, 0, WORTH.size() - 1)]


## The radius of it, in metres — the cube root of its worth, so the ladder
## looks like a ladder rather than like a range of mountains.
func girth() -> float:
	return GIRTH * pow(float(worth()), 1.0 / 3.0)


## What it weighs. See HEFT_PER_STONE: the same line a tree's timber uses.
func heft() -> float:
	return HEFT_BARE + float(worth()) * HEFT_PER_STONE


func kind_name() -> String:
	if vein:
		return "outcrop"
	return NAMES[clampi(rung, 0, NAMES.size() - 1)]


## What this rock is, as a row — kept because it reads well at the call site and
## because everything about a rock really does follow from its rung.
func spec() -> Dictionary:
	return {"kind": kind_name(), "worth": worth(), "size": girth(),
		"whole": not vein}


## A stone small enough to lift entire — which is every rock that is not a vein.
## How much of it a given pair of hands can manage is a question for the hands:
## see Creature.can_lift, which asks the rock its worth and compares.
func liftable_whole() -> bool:
	return not vein


## HOW MANY MORE CRACKS BEFORE IT COMES APART. Zero means the next one does it;
## a pebble answers -1, because there is nothing inside a pebble.
func cracks_left() -> int:
	if not can_split():
		return -1
	return maxi(rung * CRACKS_PER_RUNG - _cracks, 0)


## Can this one be broken down at all? A vein is the hill and a pebble is
## already the bottom of the ladder.
func can_split() -> bool:
	return not vein and rung > 0


## ONE CRACK. Returns true when that was the one that broke it open.
##
## THE GESTURE IS A DOUBLE TAP — see DivineHand._tapped_twice — so a megalith
## is nine deliberate taps and a cobble is two. Nothing is spent but the
## player's own time, which is the whole idea: a god who will stand there and
## work at a rock ends up with more stone than the world was made with, and a
## god in a hurry does not.
func crack() -> bool:
	if not can_split():
		return false
	_cracks += 1
	# It jolts. A crack you cannot see is a crack you cannot count.
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.06, 0.94, 1.06), 0.06)
	tween.tween_property(self, "scale", Vector3.ONE, 0.12)
	if _cracks < rung * CRACKS_PER_RUNG:
		return false
	split()
	return true


## BREAK IT IN HALF. Two rocks of the rung below, which between them are worth
## MORE than this one was — see the header. The rock is gone; what replaces it
## is put in the same parent so it belongs to the same chunk.
func split() -> void:
	if not can_split():
		return
	var parent := get_parent()
	if parent == null:
		return
	for side in [-1.0, 1.0]:
		var half := RockDeposit.new()
		half.rung = rung - 1
		half.style = style
		parent.add_child(half)
		half.global_position = global_position \
			+ Vector3(side * SPLIT_APART, girth() * 0.4, 0.0)
		half.rotation.y = randf() * TAU
		# Loose, so they tumble apart and settle rather than hanging in the air
		# where the old rock's middle used to be.
		half.shake_loose()
		half.linear_velocity = Vector3(side * 1.6, 1.2, randf_range(-0.6, 0.6))
	queue_free()


## LET PHYSICS HAVE IT. Called when a rock is split off another — the hand's
## own release path already unfreezes what it throws (see
## DivineHand._release_body), which is exactly the same thing said by somebody
## who does not know what a rock is.
func shake_loose() -> void:
	freeze = false
	sleeping = false


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


## PRISE ONE LOOSE — a vein's answer, and now only a vein's. Returns a boulder,
## or null if there is nothing left worth taking. The vein wears down exactly as
## it does under a pick, because it is the same stone either way: a god taking
## it is quarrying, just rudely.
##
## The caller owns what comes back and has to put it in the tree.
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


## Is this one in the air, or rolling? FROZEN IS THE WHOLE ANSWER — a rock that
## is part of the scenery is out of the solver, and a rock that is not is either
## in flight or in somebody's hand. Nothing has to tell it which; asked this way
## it cannot disagree with the physics server about its own state.
func is_loose() -> bool:
	return not freeze


func hover_text() -> String:
	if vein:
		# TELLING THE PLAYER WHICH KIND OF ROCK THIS IS is the whole reason a
		# rock knows whether it can be lifted. An outcrop and a cobble look like
		# the same grey lump from a god's height, and reaching for one and
		# getting a chip off it — with no word of explanation — reads as the
		# game failing to pick it up rather than as the rock being part of the
		# hill.
		return "Outcrop — %d stone left. Part of the hill; take hold to cleave a piece off." \
			% stone_left
	var what := kind_name().capitalize()
	if not can_split():
		return "%s — %d stone. Lift it, throw it, or drop it on a storehouse." % [what, worth()]
	return "%s — %d stone. Drop it on a storehouse, or double-tap to crack it (%d to go)." \
		% [what, worth(), cracks_left()]


## The pile shrinks as the vein empties, however the stone is leaving it.
func _wear_down() -> void:
	var fraction := float(stone_left) / float(maxi(worth(), 1))
	for i in _boulders.size():
		var b := _boulders[i]
		if not is_instance_valid(b):
			continue
		# Boulders shed one by one as the vein empties; survivors shrink.
		if fraction < float(i) / _boulders.size():
			b.visible = false
		else:
			b.scale = Vector3.ONE * lerpf(0.45, 1.0, fraction)


## IT HAS STOPPED. A rock that has come to rest is scenery again — frozen, out
## of the solver, and standing there to be walked round, quarried or picked up
## a second time. And if it stopped on somebody's storehouse, it is stone.
func _on_sleep_changed() -> void:
	if not sleeping or freeze:
		return
	if _banked():
		return
	# DEFERRED: this arrives from inside the physics server's own step, and
	# freezing a body it is in the middle of solving is how you get a frame
	# where the rock is in two places.
	set_deferred("freeze", true)


## DROPPED ON A STOREHOUSE, IT IS STORES. The one place a rock stops being a
## rock — which is the whole of "it shouldn't convert into resource stone
## unless you put it where resources go". Mirrors WildTree._land.
func _banked() -> bool:
	for s in get_tree().get_nodes_in_group("stores"):
		var store := s as FoodStore
		if not is_instance_valid(store):
			continue
		if store.global_position.distance_to(global_position) \
				> FoodStore.PLATFORM_RADIUS + 1.0:
			continue
		store.add_stone(worth())
		var town := store.get_parent() as Village
		if town != null and is_instance_valid(town):
			town.wonder.given(town, "stone", worth(), 0.0,
				has_meta("hurled_by_creature"))
		queue_free()
		return true
	return false
