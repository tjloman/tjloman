class_name FoodStore
extends StaticBody3D
## The village storehouse: a big round market floor, divided into four
## quadrants read like a pie from the sky — grain, meat, lumber, stone —
## each with a colored marker post at the rim and its stock piled inside.
##
##   +X+Z grain (orange) · -X+Z meat (red) · -X-Z lumber (brown) · +X-Z stone (gray)
##
## The hand can WITHDRAW from it (grab the platform: the most plentiful
## resource pops out as a physical item) and anything food- or
## resource-shaped that comes to rest on the platform is absorbed back in.

const PLATFORM_RADIUS := 3.4
const MAX_SHOWN := 12  # per resource; hover for exact counts

const GRAIN_COLOR := Color(0.9, 0.6, 0.2)
const MEAT_COLOR := Color(0.72, 0.22, 0.18)
const LUMBER_COLOR := Color(0.55, 0.4, 0.25)
const STONE_COLOR := Color(0.55, 0.54, 0.56)

var plant_food := 14
var meat_food := 0
var lumber := 6
var stone := 3

var _stack: Array[MeshInstance3D] = []
var _intake: Area3D
var _intake_time := 0.5


func _ready() -> void:
	add_to_group("stores")
	set_meta("hover_name", "Storehouse")
	collision_layer = 4  # hoverable/grabbable by the hand; villagers pass through
	collision_mask = 0

	var col := CollisionShape3D.new()
	var col_shape := CylinderShape3D.new()
	col_shape.radius = PLATFORM_RADIUS + 0.2
	col_shape.height = 0.6
	col.shape = col_shape
	col.position = Vector3(0, 0.3, 0)
	add_child(col)

	# The intake: whatever edible or useful comes to rest on the platform
	# is counted into stock.
	_intake = Area3D.new()
	_intake.collision_layer = 0
	_intake.collision_mask = 4
	var zone := CollisionShape3D.new()
	var zone_shape := CylinderShape3D.new()
	zone_shape.radius = PLATFORM_RADIUS
	zone_shape.height = 3.0
	zone.shape = zone_shape
	zone.position = Vector3(0, 1.2, 0)
	_intake.add_child(zone)
	add_child(_intake)

	# The round market floor on a slightly wider base, sunk into the slope
	# so the platform never floats on its downhill side.
	add_child(Util.cylinder(PLATFORM_RADIUS + 0.2, 1.4, Color(0.45, 0.36, 0.26),
		Vector3(0, -0.58, 0)))
	add_child(Util.cylinder(PLATFORM_RADIUS, 0.3, Color(0.58, 0.47, 0.33), Vector3(0, 0.2, 0)))

	# Low walls quartering the circle.
	var wall := Color(0.48, 0.38, 0.27)
	add_child(Util.box(Vector3(PLATFORM_RADIUS * 2.0, 0.5, 0.18), wall, Vector3(0, 0.55, 0)))
	add_child(Util.box(Vector3(0.18, 0.5, PLATFORM_RADIUS * 2.0), wall, Vector3(0, 0.55, 0)))

	# Center pole and a little canopy.
	add_child(Util.cylinder(0.12, 2.4, Color(0.5, 0.4, 0.28), Vector3(0, 1.2, 0)))
	add_child(Util.prism(Vector3(1.6, 0.7, 1.6), Color(0.65, 0.55, 0.3), Vector3(0, 2.7, 0)))

	# A colored marker post at the rim of each quadrant.
	for entry: Array in [
		[Vector3(1, 0, 1), GRAIN_COLOR], [Vector3(-1, 0, 1), MEAT_COLOR],
		[Vector3(-1, 0, -1), LUMBER_COLOR], [Vector3(1, 0, -1), STONE_COLOR],
	]:
		var dir: Vector3 = entry[0]
		var color: Color = entry[1]
		var rim := dir.normalized() * (PLATFORM_RADIUS - 0.35)
		add_child(Util.cylinder(0.06, 1.2, Color(0.5, 0.4, 0.28), rim + Vector3(0, 0.6, 0)))
		add_child(Util.sphere(0.18, color, rim + Vector3(0, 1.35, 0), true))

	_refresh_stack()


## Absorb items resting on the platform (polled: released items don't
## re-trigger area signals, so we sweep instead).
func _process(delta: float) -> void:
	_intake_time -= delta
	if _intake_time > 0.0:
		return
	_intake_time = 0.5
	for body in _intake.get_overlapping_bodies():
		var rb := body as RigidBody3D
		if rb == null or rb.freeze:
			continue  # held things aren't deposits
		if rb.has_meta("no_deposit_until") \
				and Time.get_ticks_msec() < int(rb.get_meta("no_deposit_until")):
			continue  # freshly withdrawn: give the hand time to carry it off
		if rb is FoodItem:
			add((rb as FoodItem).food_type, 1)
			rb.queue_free()
		elif rb is ResourceItem:
			if (rb as ResourceItem).kind == "lumber":
				add_lumber(1)
			else:
				add_stone(1)
			rb.queue_free()


## The hand grabs the platform: the most plentiful stock pops out as a
## physical item, ready to be carried anywhere — another storehouse, a
## hungry mouth, or the bottom of a lake. Null if the store is bare.
func withdraw() -> RigidBody3D:
	var item: RigidBody3D = null
	var top := maxi(maxi(plant_food, meat_food), maxi(lumber, stone))
	if top <= 0:
		return null
	if plant_food == top:
		plant_food -= 1
		item = FoodItem.new()
	elif meat_food == top:
		meat_food -= 1
		var f := FoodItem.new()
		f.food_type = FoodItem.FoodType.MEAT
		item = f
	elif lumber == top:
		lumber -= 1
		var r := ResourceItem.new()
		r.kind = "lumber"
		item = r
	else:
		stone -= 1
		var r := ResourceItem.new()
		r.kind = "stone"
		item = r
	_refresh_stack()
	item.set_meta("no_deposit_until", Time.get_ticks_msec() + 2500)
	get_parent().add_child(item)
	item.global_position = global_position + Vector3(0, 2.6, 0)
	return item


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


## A spot inside a quadrant for the i-th item of a pile (4 per layer).
func _pile_spot(dir: Vector3, i: int) -> Vector3:
	var layer := floorf(i / 4.0)
	return Vector3(
		randf_range(0.7, PLATFORM_RADIUS - 0.9) * dir.x,
		0.5 + layer * 0.34,
		randf_range(0.7, PLATFORM_RADIUS - 0.9) * dir.z)


func _refresh_stack() -> void:
	for m in _stack:
		m.queue_free()
	_stack.clear()
	for i in mini(plant_food, MAX_SHOWN):
		_show(Util.sphere(0.22, GRAIN_COLOR, _pile_spot(Vector3(1, 0, 1), i)))
	for i in mini(meat_food, MAX_SHOWN):
		_show(Util.box(Vector3(0.3, 0.3, 0.3), MEAT_COLOR, _pile_spot(Vector3(-1, 0, 1), i)))
	for i in mini(lumber, MAX_SHOWN):
		var plank := Util.box(Vector3(1.1, 0.16, 0.3), LUMBER_COLOR,
			_pile_spot(Vector3(-1, 0, -1), i))
		plank.rotation_degrees.y = randf_range(-15, 15)
		_show(plank)
	for i in mini(stone, MAX_SHOWN):
		_show(Util.box(Vector3(0.35, 0.3, 0.35), STONE_COLOR, _pile_spot(Vector3(1, 0, -1), i)))


func _show(m: MeshInstance3D) -> void:
	add_child(m)
	_stack.append(m)


func hover_text() -> String:
	return "Storehouse — %d plants · %d meat · %d lumber · %d stone" \
		% [plant_food, meat_food, lumber, stone]
