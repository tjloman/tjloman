class_name Animal
extends CharacterBody3D
## Every beast in the world, driven by one data table. Livestock can be
## tamed (by the good), penned (by anyone), eaten (by policy), and thrown
## (by you). Predators hunt prey — and sometimes people.
##
## Add a species by adding a SPECIES row. That's the whole job.

enum State { IDLE, WANDER, FLEE, CHASE, HELD, FALLING }

const GRAVITY := 20.0

## What the butcher calls it. Anything not listed is just "<species> meat".
const MEAT_NAMES := {
	"sheep": "mutton", "pig": "pork", "chicken": "chicken", "deer": "venison",
	"ox": "beef", "giraffe": "giraffe steak", "llama": "llama chop",
	"bear": "bear flank", "wolf": "wolf flesh", "lion": "lion flesh",
	"tiger": "tiger flesh",
}

## body = torso box size; leg = leg height; meat = granary yield when
## butchered; tame = domesticable; ride/pack = tamed roles; predator hunts
## the listed prey species; attacks_villagers marks the truly dangerous.
const SPECIES := {
	"sheep": {"body": Vector3(0.7, 0.55, 1.1), "leg": 0.3, "color": Color(0.92, 0.9, 0.85),
		"speed": 2.0, "meat": 2, "tame": true, "sound": "baa", "sound_chance": 0.05},
	"chicken": {"body": Vector3(0.3, 0.3, 0.4), "leg": 0.15, "color": Color(0.95, 0.9, 0.8),
		"speed": 1.6, "meat": 1, "tame": true, "sound": "cluck", "sound_chance": 0.07},
	"pig": {"body": Vector3(0.7, 0.55, 1.2), "leg": 0.25, "color": Color(0.9, 0.6, 0.55),
		"speed": 2.2, "meat": 3, "tame": true, "sound": "oink", "sound_chance": 0.05},
	"horse": {"body": Vector3(0.7, 0.9, 1.8), "leg": 0.8, "color": Color(0.45, 0.3, 0.2),
		"speed": 5.0, "meat": 0, "tame": true, "ride": true, "sound": "neigh", "sound_chance": 0.02},
	"llama": {"body": Vector3(0.6, 0.8, 1.3), "leg": 0.6, "color": Color(0.85, 0.78, 0.65),
		"speed": 3.0, "meat": 1, "tame": true, "ride": true, "pack": true},
	"ox": {"body": Vector3(0.9, 0.9, 1.9), "leg": 0.6, "color": Color(0.35, 0.28, 0.22),
		"speed": 2.0, "meat": 4, "tame": true, "pack": true},
	"dog": {"body": Vector3(0.4, 0.45, 0.9), "leg": 0.35, "color": Color(0.6, 0.48, 0.3),
		"speed": 4.5, "meat": 0, "tame": true, "guard": true, "sound": "bark", "sound_chance": 0.03},
	"deer": {"body": Vector3(0.55, 0.7, 1.3), "leg": 0.7, "color": Color(0.6, 0.45, 0.3),
		"speed": 5.5, "meat": 3, "skittish": true},
	"giraffe": {"body": Vector3(0.8, 1.1, 1.8), "leg": 1.6, "color": Color(0.85, 0.7, 0.35),
		"speed": 3.5, "meat": 4, "neck": 1.8},
	"frog": {"body": Vector3(0.22, 0.15, 0.3), "leg": 0.06, "color": Color(0.35, 0.65, 0.3),
		"speed": 1.5, "meat": 0, "sound": "croak", "sound_chance": 0.08, "hops": true},
	"wolf": {"body": Vector3(0.5, 0.55, 1.1), "leg": 0.45, "color": Color(0.45, 0.45, 0.48),
		"speed": 5.0, "meat": 1, "predator": true, "prey": ["sheep", "deer", "chicken", "pig"],
		"attacks_villagers": true, "sound": "howl", "sound_chance": 0.01},
	"bear": {"body": Vector3(0.9, 1.0, 1.6), "leg": 0.5, "color": Color(0.35, 0.25, 0.18),
		"speed": 4.0, "meat": 5, "predator": true, "prey": ["deer", "sheep", "pig"],
		"attacks_villagers": true},
	"lion": {"body": Vector3(0.6, 0.65, 1.4), "leg": 0.55, "color": Color(0.78, 0.62, 0.35),
		"speed": 5.5, "meat": 3, "predator": true, "prey": ["giraffe", "deer", "llama", "ox"],
		"attacks_villagers": true},
	"tiger": {"body": Vector3(0.6, 0.6, 1.5), "leg": 0.5, "color": Color(0.85, 0.5, 0.2),
		"speed": 5.5, "meat": 3, "predator": true, "prey": ["deer", "pig", "sheep"],
		"attacks_villagers": true},
}

var species := "sheep"
var spec: Dictionary
var health := 30.0
var tamed_by: Village = null
var night_spawned := false     # wolves of the wolf-raid despawn at dawn

var state := State.IDLE
var _target := Vector3.ZERO
var _prey: Node3D = null
var _action_time := 2.0
var _think_time := 0.0
var _flee_from := Vector3.ZERO
var _fall_speed := 0.0
var _satiated := 0.0
var _rider: Node3D = null


static func create(species_name: String) -> Animal:
	var a := Animal.new()
	a.species = species_name
	return a


func _ready() -> void:
	spec = SPECIES[species]
	health = 20.0 + spec["body"].length() * 15.0
	add_to_group("animals")
	add_to_group("pickable")
	collision_layer = 2
	collision_mask = 1

	var body: Vector3 = spec["body"]
	var leg_h: float = spec["leg"]
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(body.x, body.y + leg_h, body.z)
	col.shape = shape
	col.position = Vector3(0, (body.y + leg_h) * 0.5, 0)
	add_child(col)
	_build_body(body, leg_h)


func _build_body(body: Vector3, leg_h: float) -> void:
	var color: Color = spec["color"]
	add_child(Util.box(body, color, Vector3(0, leg_h + body.y * 0.5, 0)))
	# Legs.
	if leg_h > 0.1:
		for corner in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
			var offset := Vector3(corner.x * body.x * 0.35, leg_h * 0.5, corner.z * body.z * 0.35)
			add_child(Util.box(Vector3(0.12, leg_h, 0.12), color.darkened(0.25), offset))
	# Head (on a neck, for the tall ones).
	var neck_h: float = spec.get("neck", 0.0)
	var head_y := leg_h + body.y + neck_h
	if neck_h > 0.0:
		add_child(Util.box(Vector3(0.25, neck_h, 0.25), color,
			Vector3(0, leg_h + body.y + neck_h * 0.5 - 0.1, body.z * 0.35)))
	var head_r: float = clampf(body.y * 0.4, 0.08, 0.35)
	add_child(Util.sphere(head_r, color.darkened(0.15),
		Vector3(0, head_y, body.z * 0.5 + head_r * 0.5)))


func _physics_process(delta: float) -> void:
	# Far-off beasts stand still: the world shouldn't pay physics for what
	# nobody can see. (Held/falling animals always simulate.)
	if state != State.HELD and state != State.FALLING:
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam.global_position.distance_to(global_position) > 90.0:
			return

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
				if state == State.FALLING:
					scare(global_position + Vector3(randf() - 0.5, 0, randf() - 0.5))
			return
		State.IDLE:
			_action_time -= delta
			_apply_gravity_only(delta)
			if _action_time <= 0.0:
				_pick_wander_target()
		State.WANDER:
			if _move_toward(_target, spec["speed"] * 0.6, delta):
				state = State.IDLE
				_action_time = randf_range(2.0, 6.0)
		State.FLEE:
			_action_time -= delta
			var away := global_position - _flee_from
			away.y = 0
			_move_toward(global_position + away.normalized() * 5.0, spec["speed"] * 1.5, delta)
			if _action_time <= 0.0:
				state = State.IDLE
				_action_time = 2.0
		State.CHASE:
			if _prey == null or not is_instance_valid(_prey) or _prey.is_queued_for_deletion():
				_prey = null
				state = State.IDLE
			elif _move_toward(_prey.global_position, spec["speed"] * 1.3, delta):
				_strike_prey()

	_think_time -= delta
	if _think_time <= 0.0:
		_think_time = randf_range(0.7, 1.3)
		_think()

	# Ridden animals glue themselves under their rider.
	if _rider != null:
		if is_instance_valid(_rider):
			global_position = _rider.global_position + Vector3(0, -0.4, 0)
		else:
			_rider = null

	_ambient_sound(delta)


## Slow thinking: predator targeting, guard-dog work, night despawn.
func _think() -> void:
	if state in [State.HELD, State.FALLING, State.FLEE]:
		return
	if night_spawned and not GameState.is_night():
		queue_free()  # wolves of the raid melt away at dawn
		return
	_satiated = maxf(_satiated - 1.0, 0.0)

	if spec.get("predator", false) and _satiated <= 0.0 and state != State.CHASE:
		_prey = _find_prey()
		if _prey != null:
			state = State.CHASE
			return

	if spec.get("guard", false) and tamed_by != null:
		var wolf := _find_nearby("animals", 16.0, func(n): return n is Animal \
			and n.species == "wolf")
		if wolf != null:
			SoundBank.play_at("bark", global_position, -2.0)
			(wolf as Animal).scare(global_position)
		# Guard dogs also cheer up anyone nearby. Dogs are like that.
		for v in get_tree().get_nodes_in_group("villagers"):
			if v.global_position.distance_to(global_position) < 6.0:
				v.cheer(0.3)


func _find_prey() -> Node3D:
	var prey_list: Array = spec.get("prey", [])
	var best: Node3D = null
	var best_dist := 22.0
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if animal == self or not is_instance_valid(animal):
			continue
		if not prey_list.has(animal.species):
			continue
		# Guarded livestock is safer: dogs make predators think twice.
		if animal.tamed_by != null and animal.tamed_by.has_guard_dog():
			continue
		var d := global_position.distance_to(animal.global_position)
		if d < best_dist:
			best_dist = d
			best = animal
	if best == null and spec.get("attacks_villagers", false):
		for v in get_tree().get_nodes_in_group("villagers"):
			var d := global_position.distance_to(v.global_position)
			if d < best_dist * 0.6:
				best_dist = d
				best = v
	return best


func _strike_prey() -> void:
	if _prey is Animal:
		(_prey as Animal).take_damage(25.0)
		if not is_instance_valid(_prey) or _prey.is_queued_for_deletion():
			_satiated = 25.0
			_prey = null
			state = State.IDLE
	elif _prey.has_method("take_damage"):
		_prey.call("take_damage", 20.0, false)
		_prey.call("scare", global_position)
		_satiated = 15.0
		_prey = null
		state = State.IDLE


func _find_nearby(group: String, radius: float, filter: Callable) -> Node3D:
	for n in get_tree().get_nodes_in_group(group):
		if n == self or not is_instance_valid(n):
			continue
		if not filter.call(n):
			continue
		if (n as Node3D).global_position.distance_to(global_position) < radius:
			return n
	return null


func _pick_wander_target() -> void:
	state = State.WANDER
	var center := global_position
	var reach := 10.0
	# Tamed animals graze near their village's pen; dogs roam a bit wider.
	if tamed_by != null:
		center = tamed_by.pen_position()
		reach = 12.0 if spec.get("guard", false) else 5.0
	var angle := randf() * TAU
	_target = center + Vector3(cos(angle), 0, sin(angle)) * randf_range(2.0, reach)
	if spec.get("hops", false):
		velocity.y = 5.0  # boing


func _move_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < 1.0:
		_apply_gravity_only(delta)
		return true
	var dir := to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y -= GRAVITY * delta
	move_and_slide()
	# Heads are modeled at +Z; look_at aims -Z. Look away from travel to face it.
	look_at(global_position - Vector3(dir.x, 0, dir.z), Vector3.UP)
	return false


func _apply_gravity_only(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	velocity.y -= GRAVITY * delta
	move_and_slide()


func _ambient_sound(delta: float) -> void:
	var sound: String = spec.get("sound", "")
	if sound == "" or state == State.HELD:
		return
	# sound_chance is per-second probability: a sheep baas every ~20s,
	# not twice a second. (The old x10 here made the world a wall of noise.)
	if randf() < spec.get("sound_chance", 0.0) * delta:
		SoundBank.play_at(sound, global_position, -6.0)


## Interactions ---------------------------------------------------------------

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		die()
	else:
		scare(global_position + Vector3(randf() - 0.5, 0, randf() - 0.5))


## Death drops physical meat; hunters bypass this and take it to the granary.
func die(drop_meat := true) -> void:
	if tamed_by != null:
		tamed_by.on_tamed_lost(self)
	var meat: int = spec["meat"]
	if drop_meat and meat > 0:
		var parent := get_parent() as Node3D
		for i in meat:
			var item := FoodItem.new()
			item.food_type = FoodItem.FoodType.MEAT
			item.meat_name = MEAT_NAMES.get(species, "%s meat" % species)
			item.position = parent.to_local(global_position
				+ Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)))
			parent.add_child(item)
	queue_free()


func scare(from_pos: Vector3) -> void:
	if state in [State.HELD, State.CHASE]:
		return
	state = State.FLEE
	_flee_from = from_pos
	_action_time = 3.0
	if spec.get("skittish", false):
		_action_time = 5.0


func tame(by: Village) -> void:
	tamed_by = by
	night_spawned = false
	by.on_tamed_gained(self)
	# Tamed animals belong to the village now — reparent so they survive
	# their birth-chunk unloading as the camera roams.
	if get_parent() != by:
		reparent.call_deferred(by)


func is_tamable() -> bool:
	return spec.get("tame", false) and tamed_by == null and not spec.get("predator", false)


func set_rider(rider: Node3D) -> void:
	_rider = rider


func has_rider() -> bool:
	return _rider != null and is_instance_valid(_rider)


func meat_yield() -> int:
	return spec["meat"]


## Divine hand interface ------------------------------------------------------

func pick_up() -> void:
	state = State.HELD
	_rider = null
	velocity = Vector3.ZERO


func drop(throw_velocity: Vector3) -> void:
	state = State.FALLING
	velocity = throw_velocity


func hover_text() -> String:
	var flavor := "wild"
	if tamed_by != null:
		flavor = "of %s" % tamed_by.village_name
	elif spec.get("predator", false):
		flavor = "predator"
	return "%s (%s)" % [species.capitalize(), flavor]
