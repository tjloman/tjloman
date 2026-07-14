class_name Creature
extends CharacterBody3D
## Your creature: an ugly, lovable capsule-beast with needs and a waddle.
## PoC behaviors: wander near the village, seek and eat food when hungry
## (growing a little each meal), collapse into sleep when exhausted.
##
## This is the foundation the real creature AI grows from — learning,
## discipline, desires, and eventually direct control all hang off the same
## need/state skeleton.

enum State { IDLE, WANDER, SEEK_FOOD, EATING, SLEEPING }

const WALK_SPEED := 3.5
const GRAVITY := 20.0
const MAX_SCALE := 1.6

var hunger := 40.0
var energy := 90.0
var growth_scale := 1.0

var state := State.IDLE
var _target := Vector3.ZERO
var _target_food: FoodItem = null
var _action_time := 2.0
var _body: Node3D
var _label: Label3D
var _walk_phase := 0.0


func _ready() -> void:
	add_to_group("creature")
	collision_layer = 2
	collision_mask = 1
	set_meta("hover_name", "Your creature")

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.6
	shape.height = 2.2
	col.shape = shape
	col.position = Vector3(0, 1.1, 0)
	add_child(col)

	_body = Node3D.new()
	add_child(_body)

	var fur := Color(0.55, 0.42, 0.3)
	_body.add_child(Util.capsule(0.6, 1.8, fur, Vector3(0, 1.0, 0)))
	_body.add_child(Util.sphere(0.45, fur, Vector3(0, 2.1, 0.15)))
	# Googly eyes: the cheapest possible charm.
	for side in [-1, 1]:
		_body.add_child(Util.sphere(0.12, Color.WHITE, Vector3(0.18 * side, 2.25, 0.5)))
		_body.add_child(Util.sphere(0.05, Color.BLACK, Vector3(0.18 * side, 2.25, 0.6)))
	# Stubby arms.
	for side in [-1, 1]:
		var arm := Util.capsule(0.15, 0.8, fur, Vector3(0.7 * side, 1.3, 0))
		arm.rotation_degrees.z = 25 * side
		_body.add_child(arm)

	_label = Util.status_label()
	_label.position = Vector3(0, 3.0, 0)
	add_child(_label)


func _physics_process(delta: float) -> void:
	hunger = minf(hunger + 1.0 * delta, 100.0)
	if state != State.SLEEPING:
		energy = maxf(energy - 0.4 * delta, 0.0)

	match state:
		State.IDLE:
			_action_time -= delta
			_apply_gravity_only(delta)
			if _action_time <= 0.0:
				_decide()
		State.WANDER:
			if _move_toward(_target, WALK_SPEED * 0.7, delta):
				state = State.IDLE
				_action_time = randf_range(1.5, 4.0)
		State.SEEK_FOOD:
			if _target_food == null or not is_instance_valid(_target_food) \
					or _target_food.is_queued_for_deletion():
				_target_food = null
				_decide()
			elif _move_toward(_target_food.global_position, WALK_SPEED, delta):
				_target_food.queue_free()
				_target_food = null
				state = State.EATING
				_action_time = 1.5
		State.EATING:
			_action_time -= delta
			_apply_gravity_only(delta)
			# Chomping animation: enthusiastic squash and stretch.
			_body.scale.y = 1.0 + sin(Time.get_ticks_msec() / 60.0) * 0.08
			if _action_time <= 0.0:
				_body.scale.y = 1.0
				hunger = maxf(hunger - FoodItem.NUTRITION * 1.5, 0.0)
				_grow()
				_decide()
		State.SLEEPING:
			_apply_gravity_only(delta)
			energy = minf(energy + 6.0 * delta, 100.0)
			_body.rotation_degrees.z = 80
			if energy > 85.0:
				_body.rotation_degrees.z = 0
				_decide()

	_animate_waddle(delta)
	_label.text = _status_text()


func _decide() -> void:
	if energy < 15.0:
		state = State.SLEEPING
		return
	if hunger > 55.0:
		_target_food = _nearest_food()
		if _target_food != null:
			state = State.SEEK_FOOD
			return
	state = State.WANDER
	var angle := randf() * TAU
	var dist := randf_range(4.0, 18.0)
	_target = Vector3(cos(angle) * dist, 0, sin(angle) * dist)


func _nearest_food() -> FoodItem:
	var best: FoodItem = null
	var best_dist := 60.0
	for f in get_tree().get_nodes_in_group("food"):
		var food := f as FoodItem
		if not is_instance_valid(food) or food.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(food.global_position)
		if d < best_dist:
			best_dist = d
			best = food
	return best


func _grow() -> void:
	if growth_scale < MAX_SCALE:
		growth_scale = minf(growth_scale * 1.03, MAX_SCALE)
		scale = Vector3.ONE * growth_scale
		GameState.announce("Your creature grows a little. It is now %.0f%% of its destined size." \
			% (growth_scale / MAX_SCALE * 100.0))


func _move_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < 1.0:
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
	var face := global_position + dir
	look_at(Vector3(face.x, global_position.y, face.z), Vector3.UP)
	_walk_phase += delta * 9.0
	return false


func _apply_gravity_only(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	velocity.y -= GRAVITY * delta
	move_and_slide()


## The famous "poorly-animated" clause, delivered: bob + lean while moving.
func _animate_waddle(_delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if moving:
		_body.position.y = absf(sin(_walk_phase)) * 0.15
		_body.rotation_degrees.z = sin(_walk_phase) * 6.0
	elif state != State.SLEEPING:
		_body.position.y = lerpf(_body.position.y, 0.0, 0.2)
		_body.rotation_degrees.z = lerpf(_body.rotation_degrees.z, 0.0, 0.2)


func receive_heal() -> void:
	energy = minf(energy + 40.0, 100.0)


func state_name() -> String:
	return State.keys()[state]


func hover_text() -> String:
	return "Your creature — %s  (hunger %d · energy %d · size %.0f%%)" % [
		_status_word(), int(hunger), int(energy), growth_scale / MAX_SCALE * 100.0]


func _status_word() -> String:
	match state:
		State.IDLE: return "pondering"
		State.WANDER: return "exploring"
		State.SEEK_FOOD: return "hunting for a snack"
		State.EATING: return "eating happily"
		State.SLEEPING: return "sleeping"
	return "?"


func _status_text() -> String:
	match state:
		State.SLEEPING: return "zzz"
		State.EATING: return "nom nom"
		State.SEEK_FOOD: return "food?"
	return ""
