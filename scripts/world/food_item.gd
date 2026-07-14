class_name FoodItem
extends RigidBody3D
## A physical morsel of food. Falls from the sky (food miracle), can be
## picked up and thrown by the hand, eaten by villagers and the creature.

const NUTRITION := 35.0


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 1.0


func _ready() -> void:
	add_to_group("food")
	add_to_group("pickable")
	set_meta("hover_name", "Food")
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	col.shape = shape
	add_child(col)
	add_child(Util.sphere(0.3, Color(0.95, 0.65, 0.15)))
