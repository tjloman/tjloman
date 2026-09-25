class_name FoodItem
extends RigidBody3D
## A physical morsel of food. Falls from the sky (food miracle), drops from
## slain animals, can be thrown by the hand, eaten by villagers and the
## creature. Meat is named for the beast it came from. Human meat exists
## only in the darkest of villages.

enum FoodType { PLANT, MEAT }

const NUTRITION := 40.0

## MOST THAT WILL EVER GO IN ONE HAND.
##
## It was twenty-four, on the principle that a bundle is a convenience and not a
## cart. That was the wrong principle for the thing people actually do with it:
## a culled herd leaves more meat on the grass than twenty-four, and the player
## who hunted it is then making trips — which is not a decision, it is carrying.
## A hunt goes home in one lift now.
const MOST_IN_A_BUNDLE := 64
## WHAT A PILE IS CALLED once there is more than one animal in it. Nobody wants
## to know which joint came off which beast, and the game should not make them
## keep three piles apart to avoid finding out.
const MYSTERY := "mystery meat"

var food_type := FoodType.PLANT
var meat_name := "mutton"
var is_human_meat := false
var count := 1  # a bundle: this many units in one carriable


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 1.0
	# Thrown food should skid and settle where it lands — not roll downhill
	# into the nearest lake. High friction, a little bounce, heavy damping.
	var phys := PhysicsMaterial.new()
	phys.friction = 1.0
	phys.bounce = 0.2
	physics_material_override = phys
	linear_damp = 0.6
	angular_damp = 6.0


func _ready() -> void:
	add_to_group("food")
	add_to_group(Affords.PICKABLE)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 0.4, 0.45)
	col.shape = shape
	add_child(col)

	if food_type == FoodType.PLANT:
		_build_sheaf()
	elif meat_name == "fish":
		_build_fish()
	else:
		_build_meat()

	refresh_bundle()  # a bigger bundle looks bigger


## TAKE THAT ONE INTO THIS ONE. True when any of it moved.
##
## ONE JOINT IS AS GOOD AS ANOTHER. Mutton, bison and venison used to be three
## piles that could not be made into one, so a hunt that killed three kinds of
## animal was three trips home — and once a pile was full it could take nothing
## at all, so two half-piles stayed two piles for ever. Neither of those was a
## decision anybody was making; they were bookkeeping. Any meat goes in with any
## other meat now, and what comes out is MYSTERY MEAT, which is the honest name
## for a pile nobody can tell apart any more.
##
## A SHEAF IS STILL NOT A JOINT. Grain and meat stay separate: they look
## different in the hand, they are wanted for different things, and a village
## with a granary full of mutton is a different game.
##
## AND A JOINT OF SOMEBODY NEVER JOINS AN HONEST PILE.
##
## It was tried the other way for exactly one commit: let the flesh in, and let
## it TAINT the pile — every villager who would have refused the joint refuses
## the whole stack, the hover line says so, the player is told. Nothing is
## laundered by that, and it is still wrong, because the question was never
## whether the mixing could be made honest.
##
## HUMAN MEAT IS NOT A WORSE KIND OF MEAT. It is a different thing with a
## different life, and the life is the point: it never goes to a store, it is
## never carried home, and it is eaten where it lies by people who have run out
## of other options or out of decency. A pile it could be mixed into is a pile
## that would be carried, banked and served at a hearth, and all three of those
## are exactly what must never happen to it. Keeping it out of the pile is not a
## squeamish rule about bookkeeping; it is what makes the eating of it the
## separate, wretched thing it is.
func absorb(other_given: Variant) -> bool:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(other_given):
		return false
	var other := other_given as FoodItem
	if other == null or not is_instance_valid(other) or other == self:
		return false
	if other.food_type != food_type:
		return false
	if other.is_human_meat != is_human_meat:
		return false
	# AS MUCH AS WILL FIT, and the rest stays on the ground. The flat refusal is
	# what stopped two piles ever becoming one.
	var room := MOST_IN_A_BUNDLE - count
	if room <= 0:
		return false
	var took := mini(other.count, room)
	if took <= 0:
		return false
	if food_type == FoodType.MEAT and other.meat_name != meat_name:
		meat_name = MYSTERY
	count += took
	other.count -= took
	refresh_bundle()
	if other.count <= 0:
		other.queue_free()
	else:
		other.refresh_bundle()
	return true


## WHAT COMES OFF A BODY. The one place human meat is made, so that everything
## true of it is true in one place: it is physical, it lies where it was cut,
## and no other kind of meat is ever flagged this way by accident.
##
## It is deliberately NOT a haul. A butcher used to turn a corpse into two
## abstract units of "meat" and walk them to the granary, where they became
## ordinary stock and were served to the whole village — which is the laundering
## the merge rule was written to prevent, happening by a different door and at a
## larger scale. A body leaves joints on the grass now, and they stay there.
static func joints_of_a_person(many: int, at: Vector3, into: Node) -> FoodItem:
	var item := FoodItem.new()
	item.food_type = FoodType.MEAT
	item.is_human_meat = true
	item.meat_name = "flesh"
	item.count = maxi(many, 1)
	into.add_child(item)
	item.global_position = at
	return item


## Re-fit the visual to the current count — called when a bundle grows (held
## over a store) or shrinks (partly eaten).
func refresh_bundle() -> void:
	scale = Vector3.ONE * clampf(1.0 + (count - 1) * 0.05, 1.0, 1.7)


## THESE THREE ARE THE THINGS A TOWN CARRIES ABOUT ALL DAY, and they were built
## like display pieces: 1,104 triangles for a joint of meat, 872 for a fish, out
## of `Util.sphere` and `Util.capsule`, which mint a FRESH mesh and a FRESH
## material every time they are called. A busy village has dozens of these in
## hands and on the ground at once, so it was paying both a hundred thousand
## triangles and a unique material per item — and a unique material cannot be
## batched with anything, which costs more than the triangles did.
##
## They are pooled and low now. Three rules make the pooling actually work:
##
##   RADII ON THE BUCKET. `_pooled_*_mesh` snaps size to 5cm so a spread of
##   near-identical parts still shares one mesh. Ask for 0.14 and you get 0.15
##   anyway — so ask for 0.15, and shape the part with NODE SCALE, which is free
##   and does not mint anything.
##
##   A DOT IS A DOT. An eye is a black full stop seen from one angle. It was a
##   288-triangle sphere; it is two triangles that face the camera.
##
##   A TIP IS A CONE. `top = 0.0` costs the fan on the end that is a point.

## A bound sheaf of grain: golden bundle, darker tie, splayed tips.
func _build_sheaf() -> void:
	var grain := Color(0.87, 0.72, 0.32)
	add_child(Util.lite_cylinder(0.15, 0.42, grain, Vector3.ZERO, -1.0, 6))
	add_child(Util.lite_cylinder(
		0.20, 0.07, Color(0.5, 0.36, 0.18), Vector3(0, 0.02, 0), -1.0, 6))
	for i in 5:
		var a := TAU * i / 5.0
		var tip := Util.lite_cylinder(0.05, 0.20, grain.lightened(0.2),
			Vector3(cos(a) * 0.07, 0.26, sin(a) * 0.07), 0.0, 4)
		tip.rotation_degrees = Vector3(cos(a) * 14.0, 0, sin(a) * 14.0)
		tip.scale = Vector3(0.7, 0.8, 0.7)   # thinner than its bucket, for free
		add_child(tip)


## A joint of meat on the bone: red flesh, white bone with a knuckle.
func _build_meat() -> void:
	var flesh := Color(0.72, 0.24, 0.2) if not is_human_meat else Color(0.48, 0.14, 0.17)
	# An ovoid, not a capsule: a capsule is three sweeps of geometry and this is
	# one, scaled long. At a hand's size nobody can tell them apart.
	var meat := Util.lite_sphere(0.15, flesh, Vector3(0, 0.0, -0.05), 6)
	meat.scale = Vector3(1.0, 1.0, 2.2)
	add_child(meat)
	var bone_white := Color(0.93, 0.9, 0.82)
	var bone := Util.lite_cylinder(0.05, 0.3, bone_white, Vector3(0, 0.0, 0.3), -1.0, 5)
	bone.rotation_degrees.x = 90
	add_child(bone)
	for side in [-1.0, 1.0]:
		add_child(Util.lite_sphere(
			0.05, bone_white, Vector3(0.05 * side, 0.0, 0.44), 4))


## A fish, fresh from the shallows: silver body, forked tail, staring eye.
func _build_fish() -> void:
	var silver := Color(0.62, 0.7, 0.78)
	var body := Util.lite_sphere(0.25, silver, Vector3.ZERO, 6)
	body.scale = Vector3(0.53, 0.77, 1.54)
	add_child(body)
	var tail := Util.prism(Vector3(0.05, 0.28, 0.22), silver.darkened(0.15), Vector3(0, 0, -0.42))
	tail.rotation_degrees.z = 90
	add_child(tail)
	add_child(Util.dot_node(0.07, Color.BLACK, Vector3(0.07, 0.05, 0.3)))
	add_child(Util.dot_node(0.07, Color.BLACK, Vector3(-0.07, 0.05, 0.3)))


func hover_text() -> String:
	var tail := " ×%d" % count if count > 1 else ""
	if food_type == FoodType.PLANT:
		return "Sheaf of grain" + tail
	if is_human_meat:
		return "Meat (of unspeakable origin)" + tail
	if meat_name == MYSTERY:
		return "Mystery meat" + tail
	return "Meat (%s)%s" % [meat_name, tail]
