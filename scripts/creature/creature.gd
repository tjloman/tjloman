class_name Creature
extends CharacterBody3D
## Your creature: an ugly, lovable capsule-beast with needs, a waddle — and
## its own soul. Its morality is NOT yours: it drifts with what the creature
## witnesses you do, and it acts on it independently.
##
##   Good creature (morality > 30): tends the farm when content.
##   Evil creature (morality < -10): eats corpses.
##   Monstrous creature (morality < -30): hunts villagers when hungry.
##
## Reward/punishment training is the next layer to build on this.

enum State { IDLE, WANDER, SEEK_FOOD, EATING, SLEEPING, GO_TEND, TENDING, STALK_PREY }

const WALK_SPEED := 3.5
const GRAVITY := 20.0
const MAX_SCALE := 1.6

var hunger := 40.0
var energy := 90.0
var growth_scale := 1.0

## Independent karma: -100 monstrous .. +100 angelic.
var morality := 0.0

var state := State.IDLE
var _target := Vector3.ZERO
var _target_food: Node3D = null   # FoodItem or Corpse
var _target_prey: Villager = null
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
	for side in [-1, 1]:
		_body.add_child(Util.sphere(0.12, Color.WHITE, Vector3(0.18 * side, 2.25, 0.5)))
		_body.add_child(Util.sphere(0.05, Color.BLACK, Vector3(0.18 * side, 2.25, 0.6)))
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
				_consume_food_target()
		State.STALK_PREY:
			if _target_prey == null or not is_instance_valid(_target_prey) \
					or _target_prey.is_queued_for_deletion():
				_target_prey = null
				_decide()
			elif _move_toward(_target_prey.global_position, WALK_SPEED * 1.15, delta):
				_devour_prey()
		State.EATING:
			_action_time -= delta
			_apply_gravity_only(delta)
			_body.scale.y = 1.0 + sin(Time.get_ticks_msec() / 60.0) * 0.08
			if _action_time <= 0.0:
				_body.scale.y = 1.0
				_grow()
				_decide()
		State.GO_TEND:
			if _move_toward(_target, WALK_SPEED * 0.8, delta):
				state = State.TENDING
				_action_time = 5.0
		State.TENDING:
			_action_time -= delta
			_apply_gravity_only(delta)
			var farm := get_tree().get_first_node_in_group("farms") as Farm
			if farm != null:
				farm.tend()
			if _action_time <= 0.0:
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
		# A monstrous creature considers the villagers a food group.
		if morality < -30.0 and hunger > 75.0:
			_target_prey = _nearest_villager()
			if _target_prey != null:
				state = State.STALK_PREY
				GameState.announce("Your creature's eyes settle on the villagers. It is hungry.")
				return
		_target_food = _nearest_food()
		if _target_food != null:
			state = State.SEEK_FOOD
			return
	# A kind creature helps with the crops when it has a full belly.
	if morality > 30.0 and hunger < 40.0 and randf() < 0.4:
		var farm := get_tree().get_first_node_in_group("farms") as Farm
		if farm != null:
			state = State.GO_TEND
			_target = farm.global_position
			GameState.announce("Your creature lumbers over to help in the fields.")
			return
	state = State.WANDER
	var angle := randf() * TAU
	var dist := randf_range(4.0, 18.0)
	_target = Vector3(cos(angle) * dist, 0, sin(angle) * dist)


## Anything edible: ground food always; corpses only for a corrupted soul.
func _nearest_food() -> Node3D:
	var best: Node3D = null
	var best_dist := 60.0
	for f in get_tree().get_nodes_in_group("food"):
		var food := f as FoodItem
		if not is_instance_valid(food) or food.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(food.global_position)
		if d < best_dist:
			best_dist = d
			best = food
	if morality < -10.0:
		for c in get_tree().get_nodes_in_group("corpses"):
			var corpse := c as Corpse
			if not is_instance_valid(corpse) or corpse.is_queued_for_deletion():
				continue
			var d := global_position.distance_to(corpse.global_position)
			if d < best_dist:
				best_dist = d
				best = corpse
	return best


func _nearest_villager() -> Villager:
	var best: Villager = null
	var best_dist := 50.0
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager) or villager.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(villager.global_position)
		if d < best_dist:
			best_dist = d
			best = villager
	return best


func _consume_food_target() -> void:
	if _target_food is Corpse:
		morality = clampf(morality - 3.0, -100.0, 100.0)
		GameState.announce("Your creature feeds on the dead. The villagers pretend not to see.")
		hunger = maxf(hunger - 50.0, 0.0)
	else:
		hunger = maxf(hunger - FoodItem.NUTRITION * 1.5, 0.0)
	_target_food.queue_free()
	_target_food = null
	state = State.EATING
	_action_time = 1.5


func _devour_prey() -> void:
	if is_instance_valid(_target_prey):
		var victim_name := _target_prey.villager_name
		_target_prey.queue_free()
		hunger = maxf(hunger - 70.0, 0.0)
		morality = clampf(morality - 5.0, -100.0, 100.0)
		GameState.announce("Your creature has eaten %s. The village will not forget this." % victim_name)
		var village := get_tree().get_first_node_in_group("village") as Village
		if village != null:
			village.change_belief(4.0)  # terror is still proof of the divine
			for v in get_tree().get_nodes_in_group("villagers"):
				var witness := v as Villager
				if witness.global_position.distance_to(global_position) < 15.0:
					witness.scare(global_position)
					witness.witness_horror(4.0)
	_target_prey = null
	state = State.EATING
	_action_time = 2.0


## The creature learns right and wrong from watching its god at work.
func witness(weight: float) -> void:
	morality = clampf(morality + weight, -100.0, 100.0)


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
		_apply_gravity_only(delta)
		return true
	var dir := to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y -= GRAVITY * delta
	move_and_slide()
	look_at(global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)
	_walk_phase += delta * 9.0
	return false


func _apply_gravity_only(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	velocity.y -= GRAVITY * delta
	move_and_slide()


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


func morality_word() -> String:
	if morality > 60.0:
		return "angelic"
	if morality > 20.0:
		return "gentle"
	if morality > -20.0:
		return "wild"
	if morality > -60.0:
		return "vicious"
	return "monstrous"


func hover_text() -> String:
	return "Your creature — %s (%s)  (hunger %d · energy %d · size %.0f%%)" % [
		_status_word(), morality_word(), int(hunger), int(energy),
		growth_scale / MAX_SCALE * 100.0]


func _status_word() -> String:
	match state:
		State.IDLE: return "pondering"
		State.WANDER: return "exploring"
		State.SEEK_FOOD: return "hunting for a snack"
		State.STALK_PREY: return "stalking someone"
		State.EATING: return "eating happily"
		State.GO_TEND, State.TENDING: return "helping on the farm"
		State.SLEEPING: return "sleeping"
	return "?"


func _status_text() -> String:
	match state:
		State.SLEEPING: return "zzz"
		State.EATING: return "nom nom"
		State.SEEK_FOOD: return "food?"
		State.STALK_PREY: return "..."
		State.TENDING: return "help!"
	return ""
