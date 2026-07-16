class_name FoodItem
extends RigidBody3D
## A physical morsel of food. Falls from the sky (food miracle), drops from
## slain animals, can be thrown by the hand, eaten by villagers and the
## creature. Meat is named for the beast it came from. Human meat exists
## only in the darkest of villages.

enum FoodType { PLANT, MEAT }

const NUTRITION := 35.0

var food_type := FoodType.PLANT
var meat_name := "mutton"
var is_human_meat := false


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
	else:
		_build_meat()


## A bound sheaf of grain: golden bundle, darker tie, splayed tips.
func _build_sheaf() -> void:
	var grain := Color(0.87, 0.72, 0.32)
	add_child(Util.cylinder(0.14, 0.42, grain, Vector3(0, 0.0, 0)))
	add_child(Util.cylinder(0.155, 0.07, Color(0.5, 0.36, 0.18), Vector3(0, 0.02, 0)))
	for i in 5:
		var a := TAU * i / 5.0
		var tip := Util.cylinder(0.035, 0.16, grain.lightened(0.2),
			Vector3(cos(a) * 0.07, 0.26, sin(a) * 0.07))
		tip.rotation_degrees = Vector3(cos(a) * 14.0, 0, sin(a) * 14.0)
		add_child(tip)


## A joint of meat on the bone: red flesh, white bone with a knuckle.
func _build_meat() -> void:
	var flesh := Color(0.72, 0.24, 0.2) if not is_human_meat else Color(0.48, 0.14, 0.17)
	var meat := Util.capsule(0.16, 0.42, flesh, Vector3(0, 0.0, -0.05))
	meat.rotation_degrees.x = 90
	add_child(meat)
	var bone := Util.cylinder(0.045, 0.3, Color(0.93, 0.9, 0.82), Vector3(0, 0.0, 0.3))
	bone.rotation_degrees.x = 90
	add_child(bone)
	for side in [-1.0, 1.0]:
		add_child(Util.sphere(0.06, Color(0.93, 0.9, 0.82), Vector3(0.05 * side, 0.0, 0.44)))


func hover_text() -> String:
	if food_type == FoodType.PLANT:
		return "Sheaf of grain"
	if is_human_meat:
		return "Meat (of unspeakable origin)"
	return "Meat (%s)" % meat_name
