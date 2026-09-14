class_name FoodItem
extends RigidBody3D
## A physical morsel of food. Falls from the sky (food miracle), drops from
## slain animals, can be thrown by the hand, eaten by villagers and the
## creature. Meat is named for the beast it came from. Human meat exists
## only in the darkest of villages.

enum FoodType { PLANT, MEAT }

const NUTRITION := 40.0

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
	add_to_group("pickable")

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
	return "Meat (%s)%s" % [meat_name, tail]
