class_name FoodStore
extends Node3D
## The village granary, now with separate plant and meat stocks.
## Stock is visualized as a pile: orange spheres = plants, red cubes = meat.

var plant_food := 10
var meat_food := 0

var _stack: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("stores")
	set_meta("hover_name", "Granary")
	add_child(Util.box(Vector3(3, 0.3, 3), Color(0.6, 0.5, 0.35), Vector3(0, 0.15, 0)))
	for i in 4:
		add_child(Util.cylinder(0.12, 1.2, Color(0.5, 0.4, 0.28),
			Vector3(1.3 * (1 if i % 2 == 0 else -1), 0.9, 1.3 * (1 if i < 2 else -1))))
	add_child(Util.prism(Vector3(3.4, 0.9, 3.4), Color(0.65, 0.55, 0.3), Vector3(0, 1.9, 0)))
	_refresh_stack()


func add(type: FoodItem.FoodType, amount: int) -> void:
	if type == FoodItem.FoodType.PLANT:
		plant_food += amount
	else:
		meat_food += amount
	_refresh_stack()


## Takes up to `amount` food of the given type; returns how much was taken.
func take(type: FoodItem.FoodType, amount: int) -> int:
	var taken := 0
	if type == FoodItem.FoodType.PLANT:
		taken = mini(amount, plant_food)
		plant_food -= taken
	else:
		taken = mini(amount, meat_food)
		meat_food -= taken
	_refresh_stack()
	return taken


func has(type: FoodItem.FoodType) -> bool:
	return plant_food > 0 if type == FoodItem.FoodType.PLANT else meat_food > 0


func total_food() -> int:
	return plant_food + meat_food


func _refresh_stack() -> void:
	for m in _stack:
		m.queue_free()
	_stack.clear()
	var shown_plants: int = mini(plant_food, 8)
	var shown_meat: int = mini(meat_food, 8)
	for i in shown_plants:
		var layer := floorf(i / 4.0)
		var m := Util.sphere(0.22, Color(0.9, 0.6, 0.2),
			Vector3(randf_range(-0.8, 0.0), 0.5 + layer * 0.4, randf_range(-0.8, 0.8)))
		add_child(m)
		_stack.append(m)
	for i in shown_meat:
		var layer := floorf(i / 4.0)
		var m := Util.box(Vector3(0.3, 0.3, 0.3), Color(0.72, 0.22, 0.18),
			Vector3(randf_range(0.1, 0.8), 0.5 + layer * 0.4, randf_range(-0.8, 0.8)))
		add_child(m)
		_stack.append(m)


func hover_text() -> String:
	return "Granary — %d plants · %d meat" % [plant_food, meat_food]
