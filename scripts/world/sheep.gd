class_name Sheep
extends CharacterBody3D
## World fauna and the village's meat supply. Wanders, panics, breeds
## (handled by main's fauna tick), gets hunted, and is fully throwable.

enum State { IDLE, WANDER, FLEE, HELD, FALLING }

const WALK_SPEED := 2.0
const FLEE_SPEED := 6.0
const GRAVITY := 20.0
const MEAT_DROPPED := 2

var health := 30.0
var state := State.IDLE
var _target := Vector3.ZERO
var _action_time := 2.0
var _flee_from := Vector3.ZERO
var _fall_speed := 0.0


func _ready() -> void:
	add_to_group("animals")
	add_to_group("pickable")
	collision_layer = 2
	collision_mask = 1

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.0
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	add_child(col)

	var wool := Color(0.92, 0.9, 0.85)
	var body := Util.capsule(0.35, 1.1, wool, Vector3(0, 0.55, 0))
	body.rotation_degrees.x = 90
	add_child(body)
	add_child(Util.sphere(0.2, Color(0.25, 0.22, 0.2), Vector3(0, 0.7, 0.6)))
	for corner in [Vector3(0.18, 0.15, 0.3), Vector3(-0.18, 0.15, 0.3),
			Vector3(0.18, 0.15, -0.3), Vector3(-0.18, 0.15, -0.3)]:
		add_child(Util.box(Vector3(0.1, 0.3, 0.1), Color(0.3, 0.28, 0.25), corner))


func _physics_process(delta: float) -> void:
	match state:
		State.HELD:
			velocity = Vector3.ZERO
			return
		State.FALLING:
			_fall_speed = velocity.length()
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if is_on_floor():
				if _fall_speed > 16.0:
					take_damage((_fall_speed - 16.0) * 4.0)
				if state == State.FALLING:  # not dead
					scare(global_position + Vector3(randf() - 0.5, 0, randf() - 0.5))
			return
		State.IDLE:
			_action_time -= delta
			_apply_gravity_only(delta)
			if _action_time <= 0.0:
				state = State.WANDER
				var angle := randf() * TAU
				_target = global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(3.0, 10.0)
		State.WANDER:
			if _move_toward(_target, WALK_SPEED, delta):
				state = State.IDLE
				_action_time = randf_range(2.0, 6.0)
		State.FLEE:
			_action_time -= delta
			var away := global_position - _flee_from
			away.y = 0
			_move_toward(global_position + away.normalized() * 5.0, FLEE_SPEED, delta)
			if _action_time <= 0.0:
				state = State.IDLE
				_action_time = 2.0


func _move_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < 0.8:
		_apply_gravity_only(delta)
		return true
	var dir := to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y -= GRAVITY * delta
	move_and_slide()
	look_at(global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)
	return false


func _apply_gravity_only(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	velocity.y -= GRAVITY * delta
	move_and_slide()


func scare(from_pos: Vector3) -> void:
	if state == State.HELD:
		return
	state = State.FLEE
	_flee_from = from_pos
	_action_time = 3.0


func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		die()


## Death drops physical meat on the ground (creature food, or hauled by
## villagers). Hunters bypass this and take meat straight to the granary.
func die(drop_meat := true) -> void:
	if drop_meat:
		for i in MEAT_DROPPED:
			var meat := FoodItem.new()
			meat.food_type = FoodItem.FoodType.MEAT
			meat.position = global_position + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))
			get_parent().add_child(meat)
	queue_free()


## Divine hand interface -----------------------------------------------------

func pick_up() -> void:
	state = State.HELD
	velocity = Vector3.ZERO


func drop(throw_velocity: Vector3) -> void:
	state = State.FALLING
	velocity = throw_velocity


func hover_text() -> String:
	return "Sheep — blissfully unaware"
