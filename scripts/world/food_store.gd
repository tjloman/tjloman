class_name FoodStore
extends Node3D
## The village storehouse: plant food, meat, lumber, and stone.
## Stock is visualized in piles — orange spheres (plants), red cubes (meat),
## brown planks (lumber), gray blocks (stone).

var plant_food := 14
var meat_food := 0
var lumber := 6
var stone := 3

var _stack: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("stores")
	set_meta("hover_name", "Storehouse")
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


func add_lumber(amount: int) -> void:
	lumber += amount
	_refresh_stack()


func add_stone(amount: int) -> void:
	stone += amount
	_refresh_stack()


## Spends lumber and stone together (for construction); false if short.
func try_spend_materials(lumber_cost: int, stone_cost: int) -> bool:
	if lumber < lumber_cost or stone < stone_cost:
		return false
	lumber -= lumber_cost
	stone -= stone_cost
	_refresh_stack()
	return true


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
	for i in mini(lumber, 6):
		var layer := floorf(i / 3.0)
		var m := Util.box(Vector3(1.0, 0.18, 0.3), Color(0.55, 0.4, 0.25),
			Vector3(randf_range(-0.3, 0.3), 0.45 + layer * 0.22, 1.6))
		add_child(m)
		_stack.append(m)
	for i in mini(stone, 6):
		var layer := floorf(i / 3.0)
		var m := Util.box(Vector3(0.35, 0.3, 0.35), Color(0.55, 0.54, 0.56),
			Vector3(1.6, 0.45 + layer * 0.32, randf_range(-0.4, 0.4)))
		add_child(m)
		_stack.append(m)


func hover_text() -> String:
	return "Storehouse — %d plants · %d meat · %d lumber · %d stone" \
		% [plant_food, meat_food, lumber, stone]
