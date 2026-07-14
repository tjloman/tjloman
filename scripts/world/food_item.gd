class_name FoodItem
extends RigidBody3D
## A physical morsel of food. Falls from the sky (food miracle), drops from
## slain sheep, can be thrown by the hand, eaten by villagers and the
## creature. Human meat exists only in the darkest of villages.

enum FoodType { PLANT, MEAT }

const NUTRITION := 35.0

var food_type := FoodType.PLANT
var is_human_meat := false


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 1.0


func _ready() -> void:
	add_to_group("food")
	add_to_group("pickable")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	col.shape = shape
	add_child(col)

	var color := Color(0.95, 0.65, 0.15)
	if food_type == FoodType.MEAT:
		color = Color(0.75, 0.25, 0.2) if not is_human_meat else Color(0.5, 0.15, 0.18)
	add_child(Util.sphere(0.3, color))


func hover_text() -> String:
	if food_type == FoodType.PLANT:
		return "Food (grain & fruit)"
	return "Meat (of unspeakable origin)" if is_human_meat else "Meat (mutton)"
