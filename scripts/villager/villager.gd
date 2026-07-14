class_name Villager
extends CharacterBody3D
## A needs-driven villager. Every villager continuously balances hunger,
## energy, and social needs, and picks whichever action serves the most
## urgent one. This is the seam where richer routines (jobs, festivals,
## music, romance) will slot in: add a need, add actions that satisfy it.

enum State {
	WANDER, GO_EAT, EATING, GO_SLEEP, SLEEPING,
	GO_WORK, WORKING, GO_WORSHIP, WORSHIPPING,
	FLEE, HELD, FALLING,
}

const NAMES := [
	"Aldo", "Bess", "Cormac", "Dara", "Edwin", "Fen", "Greta", "Hobb",
	"Isolde", "Jarek", "Kira", "Lomax", "Mabel", "Nol", "Opal", "Pip",
	"Quill", "Rosa", "Sten", "Tilda", "Ulf", "Vera", "Wick", "Yara",
]

const WALK_SPEED := 3.0
const FLEE_SPEED := 5.5
const GRAVITY := 20.0
const ARRIVE_DIST := 0.8

var village: Village
var home_position := Vector3.ZERO
var villager_name := "Villager"

# Needs: 0 = fully satisfied urgency-wise where noted.
var hunger := 30.0    # rises over time; eat to lower
var energy := 80.0    # falls over time; sleep to restore
var social := 70.0    # falls over time; worship/gather to restore
var happiness := 60.0

var state := State.WANDER
var _target := Vector3.ZERO
var _action_time := 0.0
var _target_food: FoodItem = null
var _flee_from := Vector3.ZERO
var _label: Label3D
var _body_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("villagers")
	add_to_group("pickable")
	collision_layer = 2
	collision_mask = 1
	villager_name = NAMES[randi() % NAMES.size()]

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.2
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)

	var shirt := Color.from_hsv(randf(), 0.55, 0.8)
	_body_mesh = Util.capsule(0.28, 1.0, shirt, Vector3(0, 0.55, 0))
	add_child(_body_mesh)
	add_child(Util.sphere(0.18, Color(0.9, 0.75, 0.6), Vector3(0, 1.25, 0)))

	_label = Util.status_label()
	_label.position = Vector3(0, 1.8, 0)
	add_child(_label)

	_decide()


func _physics_process(delta: float) -> void:
	_tick_needs(delta)

	match state:
		State.HELD:
			velocity = Vector3.ZERO
			return
		State.FALLING:
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if is_on_floor():
				scare(global_position + Vector3(randf() - 0.5, 0, randf() - 0.5))
				GameState.announce("%s survived a divine toss. Mostly." % villager_name)
			return
		State.FLEE:
			_action_time -= delta
			var away := (global_position - _flee_from)
			away.y = 0
			_move_toward(global_position + away.normalized() * 5.0, FLEE_SPEED, delta)
			if _action_time <= 0.0:
				_decide()
		State.WANDER:
			_action_time -= delta
			if _move_toward(_target, WALK_SPEED * 0.6, delta) or _action_time <= 0.0:
				_decide()
		State.GO_EAT:
			_process_go_eat(delta)
		State.EATING:
			_action_time -= delta
			if _action_time <= 0.0:
				hunger = maxf(hunger - FoodItem.NUTRITION, 0.0)
				happiness = minf(happiness + 8.0, 100.0)
				_decide()
		State.GO_SLEEP:
			if _move_toward(_target, WALK_SPEED, delta):
				state = State.SLEEPING
				_body_mesh.rotation_degrees.x = 80  # "lying down", PoC-style
		State.SLEEPING:
			energy = minf(energy + 8.0 * delta, 100.0)
			if energy > 90.0:
				_body_mesh.rotation_degrees.x = 0
				_decide()
		State.GO_WORK:
			if _move_toward(_target, WALK_SPEED, delta):
				state = State.WORKING
				_action_time = 3.0
		State.WORKING:
			_action_time -= delta
			if village.farm != null:
				village.farm.tend()
				if _action_time <= 0.0:
					if village.farm.is_harvestable():
						village.store.add(village.farm.harvest())
						GameState.announce("%s brought in the harvest." % villager_name)
					_decide()
			else:
				_decide()
		State.GO_WORSHIP:
			if _move_toward(_target, WALK_SPEED, delta):
				state = State.WORSHIPPING
				_action_time = 8.0
		State.WORSHIPPING:
			_action_time -= delta
			social = minf(social + 5.0 * delta, 100.0)
			happiness = minf(happiness + 1.0 * delta, 100.0)
			if _action_time <= 0.0:
				_decide()

	_label.text = _status_text()


func _tick_needs(delta: float) -> void:
	hunger = minf(hunger + 0.7 * delta, 100.0)
	if state != State.SLEEPING:
		var drain := 0.5 if state == State.WORKING else 0.25
		energy = maxf(energy - drain * delta, 0.0)
	social = maxf(social - 0.3 * delta, 0.0)
	if hunger > 85.0:
		happiness = maxf(happiness - 1.5 * delta, 0.0)


## Utility selection: hard priorities for the PoC. Replace with weighted
## utility scoring when needs multiply.
func _decide() -> void:
	if energy < 20.0:
		state = State.GO_SLEEP
		_target = home_position
		return
	if hunger > 60.0:
		_target_food = _nearest_ground_food()
		if _target_food != null:
			state = State.GO_EAT
			return
		if village.store.has_food():
			_target_food = null
			state = State.GO_EAT
			_target = village.store.global_position
			return
	if social < 30.0:
		state = State.GO_WORSHIP
		var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		_target = village.totem.global_position + offset
		return
	if randf() < 0.65:
		state = State.GO_WORK
		_target = village.farm.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		return
	state = State.WANDER
	_action_time = randf_range(4.0, 9.0)
	var wander_offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * village.influence_radius * 0.6
	_target = village.global_position + wander_offset


func _process_go_eat(delta: float) -> void:
	if _target_food != null:
		if not is_instance_valid(_target_food) or _target_food.is_queued_for_deletion():
			_target_food = null
			_decide()
			return
		_target = _target_food.global_position
		if _move_toward(_target, WALK_SPEED, delta):
			_target_food.queue_free()
			_target_food = null
			state = State.EATING
			_action_time = 2.0
	else:
		if _move_toward(_target, WALK_SPEED, delta):
			if village.store.take(1) > 0:
				state = State.EATING
				_action_time = 2.0
			else:
				_decide()


func _nearest_ground_food() -> FoodItem:
	var best: FoodItem = null
	var best_dist := INF
	for f in get_tree().get_nodes_in_group("food"):
		var food := f as FoodItem
		if not is_instance_valid(food) or food.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(food.global_position)
		if d < best_dist and d < village.influence_radius * 1.5:
			best_dist = d
			best = food
	return best


## Returns true when arrived. Applies gravity and simple steering.
func _move_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < ARRIVE_DIST:
		velocity.x = 0
		velocity.z = 0
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return true
	var dir := to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y -= GRAVITY * delta
	move_and_slide()
	if to_target.length() > 0.1:
		var face := global_position + dir
		look_at(Vector3(face.x, global_position.y, face.z), Vector3.UP)
	return false


func is_worshipping() -> bool:
	return state == State.WORSHIPPING


func scare(from_pos: Vector3) -> void:
	if state == State.HELD:
		return
	state = State.FLEE
	_flee_from = from_pos
	_action_time = 4.0
	happiness = maxf(happiness - 10.0, 0.0)
	_body_mesh.rotation_degrees.x = 0


func receive_heal() -> void:
	energy = minf(energy + 40.0, 100.0)
	happiness = minf(happiness + 15.0, 100.0)


## Divine hand interface -----------------------------------------------------

func pick_up() -> void:
	state = State.HELD
	_body_mesh.rotation_degrees.x = 0
	velocity = Vector3.ZERO


func drop(throw_velocity: Vector3) -> void:
	state = State.FALLING
	velocity = throw_velocity


func hover_text() -> String:
	return "%s — %s  (hunger %d · energy %d · happy %d)" % [
		villager_name, _status_word(), int(hunger), int(energy), int(happiness)]


func _status_word() -> String:
	match state:
		State.WANDER: return "strolling"
		State.GO_EAT, State.EATING: return "eating"
		State.GO_SLEEP, State.SLEEPING: return "sleeping"
		State.GO_WORK, State.WORKING: return "working the farm"
		State.GO_WORSHIP, State.WORSHIPPING: return "worshipping you"
		State.FLEE: return "fleeing in terror"
		State.HELD: return "in the grip of a god"
		State.FALLING: return "airborne"
	return "?"


func _status_text() -> String:
	match state:
		State.SLEEPING: return "zzz"
		State.EATING: return "nom"
		State.WORKING: return "work"
		State.WORSHIPPING: return "pray"
		State.FLEE, State.FALLING: return "!!!"
		State.HELD: return "?!"
	return ""
