class_name FoodStore
extends Node3D
## The village granary. Food stock is visualized as a stack of spheres.

var food_count := 10

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


func add(amount: int) -> void:
	food_count += amount
	_refresh_stack()


func take(amount: int) -> int:
	var taken: int = mini(amount, food_count)
	food_count -= taken
	_refresh_stack()
	return taken


func has_food() -> bool:
	return food_count > 0


func _refresh_stack() -> void:
	for m in _stack:
		m.queue_free()
	_stack.clear()
	var shown: int = mini(food_count, 12)
	for i in shown:
		var layer := floorf(i / 6.0)
		var m := Util.sphere(0.22, Color(0.9, 0.6, 0.2),
			Vector3(randf_range(-0.8, 0.8), 0.5 + layer * 0.4, randf_range(-0.8, 0.8)))
		add_child(m)
		_stack.append(m)


func hover_text() -> String:
	return "Granary — %d food stored" % food_count
