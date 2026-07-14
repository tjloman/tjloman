class_name Villager
extends CharacterBody3D
## A needs-driven villager with a full life: they age, love, bear children,
## work, worship, and die — of old age if they're lucky.
##
## Morality is personal: what a villager eats, witnesses, and endures shapes
## them. A good soul refuses human flesh until starvation breaks them.

enum State {
	WANDER, GO_EAT, EATING, GO_SLEEP, SLEEPING,
	GO_WORK, WORKING, GO_HUNT, HUNTING, GO_BUTCHER, BUTCHERING,
	GO_WORSHIP, WORSHIPPING, PLAY,
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

const ADULT_AGE := 16.0
const ELDER_AGE := 60.0
const PREGNANCY_YEARS := 0.75  # nine months
const MAX_POPULATION := 24
const STARVING_HUNGER := 90.0

var village: Village
var home_position := Vector3.ZERO
var villager_name := "Villager"
var is_female := randf() < 0.5

# Lifecycle.
var age := 25.0            # years; set by spawner
var lifespan := randf_range(60.0, 85.0)
var pregnant := false
var pregnancy_progress := 0.0  # years

# Needs and body.
var hunger := 30.0
var energy := 80.0
var social := 70.0
var happiness := 60.0
var health := 100.0

## Personal karma: -100 wicked .. +100 saintly.
var morality := randf_range(10.0, 40.0)

var state := State.WANDER
var _target := Vector3.ZERO
var _action_time := 0.0
var _target_food: FoodItem = null
var _target_sheep: Sheep = null
var _target_corpse: Corpse = null
var _flee_from := Vector3.ZERO
var _fall_speed := 0.0
var _label: Label3D
var _visuals: Node3D
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

	_visuals = Node3D.new()
	add_child(_visuals)
	var shirt := Color.from_hsv(randf(), 0.55, 0.8)
	_body_mesh = Util.capsule(0.28, 1.0, shirt, Vector3(0, 0.55, 0))
	_visuals.add_child(_body_mesh)
	_visuals.add_child(Util.sphere(0.18, Color(0.9, 0.75, 0.6), Vector3(0, 1.25, 0)))

	_label = Util.status_label()
	_label.position = Vector3(0, 1.8, 0)
	add_child(_label)

	_apply_life_stage()
	_decide()


func _physics_process(delta: float) -> void:
	_tick_lifecycle(delta)
	_tick_needs(delta)
	_label.text = _status_text()

	match state:
		State.HELD:
			velocity = Vector3.ZERO
			return
		State.FALLING:
			_fall_speed = velocity.length()
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if is_on_floor():
				_land()
			return
		State.FLEE:
			_action_time -= delta
			var away := global_position - _flee_from
			away.y = 0
			_move_toward(global_position + away.normalized() * 5.0, FLEE_SPEED, delta)
			if _action_time <= 0.0:
				_decide()
		State.WANDER, State.PLAY:
			_action_time -= delta
			var speed := WALK_SPEED * (1.4 if state == State.PLAY else 0.6)
			if _move_toward(_target, speed * _speed_factor(), delta) or _action_time <= 0.0:
				_decide()
		State.GO_EAT:
			_process_go_eat(delta)
		State.EATING:
			_action_time -= delta
			_apply_gravity_only(delta)
			if _action_time <= 0.0:
				hunger = maxf(hunger - FoodItem.NUTRITION, 0.0)
				happiness = minf(happiness + 8.0, 100.0)
				_decide()
		State.GO_SLEEP:
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.SLEEPING
				_body_mesh.rotation_degrees.x = 80
		State.SLEEPING:
			_apply_gravity_only(delta)
			energy = minf(energy + 8.0 * delta, 100.0)
			if energy > 90.0:
				_body_mesh.rotation_degrees.x = 0
				_decide()
		State.GO_WORK:
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.WORKING
				_action_time = 3.0
		State.WORKING:
			_action_time -= delta
			_apply_gravity_only(delta)
			if village.farm != null:
				village.farm.tend()
				if _action_time <= 0.0:
					if village.farm.is_harvestable():
						village.store.add(FoodItem.FoodType.PLANT, village.farm.harvest())
						GameState.announce("%s brought in the harvest." % villager_name)
					_decide()
			else:
				_decide()
		State.GO_HUNT:
			_process_go_hunt(delta)
		State.HUNTING:
			_action_time -= delta
			_apply_gravity_only(delta)
			if _action_time <= 0.0:
				if is_instance_valid(_target_sheep):
					_target_sheep.die(false)
					village.store.add(FoodItem.FoodType.MEAT, Sheep.MEAT_DROPPED + 1)
					GameState.announce("%s brought back mutton for the village." % villager_name)
				_target_sheep = null
				_decide()
		State.GO_BUTCHER:
			_process_go_butcher(delta)
		State.BUTCHERING:
			_action_time -= delta
			_apply_gravity_only(delta)
			if _action_time <= 0.0:
				if is_instance_valid(_target_corpse):
					var corpse_name := _target_corpse.villager_name
					_target_corpse.queue_free()
					village.store.add(FoodItem.FoodType.MEAT, 2)
					morality = maxf(morality - 20.0, -100.0)
					GameState.announce(
						"%s butchered the remains of %s. The gods avert their eyes."
						% [villager_name, corpse_name])
				_target_corpse = null
				_decide()
		State.GO_WORSHIP:
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.WORSHIPPING
				_action_time = 8.0
		State.WORSHIPPING:
			_action_time -= delta
			_apply_gravity_only(delta)
			social = minf(social + 5.0 * delta, 100.0)
			happiness = minf(happiness + 1.0 * delta, 100.0)
			morality = minf(morality + 0.05, 100.0)
			_try_conceive(delta)
			if _action_time <= 0.0:
				_decide()


## Lifecycle -----------------------------------------------------------------

func _tick_lifecycle(delta: float) -> void:
	var years := delta / GameState.YEAR_SECONDS
	var was_child := age < ADULT_AGE
	age += years
	if was_child and age >= ADULT_AGE:
		_apply_life_stage()
		GameState.announce("%s has come of age." % villager_name)

	if age > lifespan:
		die(true)
		return

	if pregnant:
		pregnancy_progress += years
		if pregnancy_progress >= PREGNANCY_YEARS:
			pregnant = false
			pregnancy_progress = 0.0
			village.spawn_child(global_position)
			GameState.announce("%s has given birth! The village grows." % villager_name)


func _apply_life_stage() -> void:
	_visuals.scale = Vector3.ONE * (0.55 if age < ADULT_AGE else 1.0)


func _speed_factor() -> float:
	if age >= ELDER_AGE:
		return 0.65
	if pregnant:
		return 0.85
	return 1.0


func is_adult() -> bool:
	return age >= ADULT_AGE


## While worshipping: an adult woman near an adult man, both content, with
## food in the granary, may conceive. Nine months later, a birth.
func _try_conceive(delta: float) -> void:
	if not is_female or pregnant or not is_adult() or age > 45.0:
		return
	if happiness < 50.0 or village.store.total_food() < 4:
		return
	if get_tree().get_nodes_in_group("villagers").size() >= MAX_POPULATION:
		return
	# ~50% chance over one 8-second worship session spent near a partner.
	if randf() > 0.08 * delta:
		return
	for v in get_tree().get_nodes_in_group("villagers"):
		var other := v as Villager
		if other == self or other.is_female or not other.is_adult():
			continue
		if other.state != State.WORSHIPPING or other.happiness < 50.0:
			continue
		if global_position.distance_to(other.global_position) < 5.0:
			pregnant = true
			pregnancy_progress = 0.0
			GameState.announce("%s and %s are expecting a child." % [villager_name, other.villager_name])
			return


## Needs ---------------------------------------------------------------------

func _tick_needs(delta: float) -> void:
	var hunger_rate := 0.7 * (1.4 if pregnant else 1.0)
	hunger = minf(hunger + hunger_rate * delta, 100.0)
	if state != State.SLEEPING:
		var drain := 0.5 if state in [State.WORKING, State.HUNTING] else 0.25
		energy = maxf(energy - drain * delta, 0.0)
	social = maxf(social - 0.3 * delta, 0.0)
	if hunger > 85.0:
		happiness = maxf(happiness - 1.5 * delta, 0.0)
	# Starvation kills. A god who lets this happen is judged for it.
	if hunger >= 100.0:
		health -= 2.0 * delta
		if health <= 0.0:
			GameState.shift_alignment(-3.0)
			GameState.announce("%s starved to death. The heavens stayed silent." % villager_name)
			die(false)


## Utility selection: hard priorities for the PoC. Children play instead of
## working or worshipping; diet policy decides what counts as food.
func _decide() -> void:
	if energy < 20.0:
		state = State.GO_SLEEP
		_target = home_position
		return
	if hunger > 60.0 and _plan_eating():
		return
	if not is_adult():
		state = State.PLAY
		_action_time = randf_range(3.0, 6.0)
		_target = village.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 8.0
		return
	if social < 30.0:
		state = State.GO_WORSHIP
		_target = village.totem.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		return
	if _plan_food_work():
		return
	state = State.WANDER
	_action_time = randf_range(4.0, 9.0)
	var wander_offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * village.influence_radius * 0.6
	_target = village.global_position + wander_offset


## Finds something this villager is willing and allowed to eat.
func _plan_eating() -> bool:
	_target_food = _nearest_edible_ground_food()
	if _target_food != null:
		state = State.GO_EAT
		return true
	for type in village.allowed_food_types():
		if village.store.has(type):
			_target_food = null
			state = State.GO_EAT
			_target = village.store.global_position
			return true
	return false


## Chooses productive work: butcher corpses (cannibal villages), hunt sheep
## (meat-eating villages running low), or tend/harvest the farm.
func _plan_food_work() -> bool:
	var diet := village.diet
	if diet == Village.Diet.CANNIBAL and village.store.meat_food < 4:
		_target_corpse = _nearest_corpse()
		if _target_corpse != null and _will_eat_human_flesh():
			state = State.GO_BUTCHER
			return true
	if diet != Village.Diet.VEGAN and village.store.meat_food < 3:
		_target_sheep = _nearest_sheep()
		if _target_sheep != null:
			state = State.GO_HUNT
			return true
	if diet != Village.Diet.CARNIVORE and diet != Village.Diet.CANNIBAL and randf() < 0.65:
		state = State.GO_WORK
		_target = village.farm.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		return true
	if randf() < 0.4:  # meat-only villages still tend crops for the sheep... allegedly
		state = State.GO_WORK
		_target = village.farm.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		return true
	return false


## Good souls refuse human flesh — until they are starving.
func _will_eat_human_flesh() -> bool:
	return morality < 30.0 or hunger > STARVING_HUNGER


func _process_go_eat(delta: float) -> void:
	if _target_food != null:
		if not is_instance_valid(_target_food) or _target_food.is_queued_for_deletion():
			_target_food = null
			_decide()
			return
		_target = _target_food.global_position
		if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
			if _target_food.is_human_meat:
				morality = maxf(morality - 25.0, -100.0)
				GameState.announce("%s has eaten human flesh. Something in them dims." % villager_name)
			_target_food.queue_free()
			_target_food = null
			state = State.EATING
			_action_time = 2.0
	else:
		if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
			for type in village.allowed_food_types():
				if village.store.take(type, 1) > 0:
					state = State.EATING
					_action_time = 2.0
					return
			_decide()


func _process_go_hunt(delta: float) -> void:
	if not is_instance_valid(_target_sheep):
		_target_sheep = null
		_decide()
		return
	if _move_toward(_target_sheep.global_position, WALK_SPEED * _speed_factor(), delta):
		state = State.HUNTING
		_action_time = 2.0


func _process_go_butcher(delta: float) -> void:
	if not is_instance_valid(_target_corpse):
		_target_corpse = null
		_decide()
		return
	if _move_toward(_target_corpse.global_position, WALK_SPEED * _speed_factor(), delta):
		state = State.BUTCHERING
		_action_time = 2.5


## Target finding ------------------------------------------------------------

func _nearest_edible_ground_food() -> FoodItem:
	var allowed := village.allowed_food_types()
	var best: FoodItem = null
	var best_dist := INF
	for f in get_tree().get_nodes_in_group("food"):
		var food := f as FoodItem
		if not is_instance_valid(food) or food.is_queued_for_deletion():
			continue
		if not allowed.has(food.food_type):
			continue
		if food.is_human_meat and not _will_eat_human_flesh():
			continue
		var d := global_position.distance_to(food.global_position)
		if d < best_dist and d < village.influence_radius * 1.5:
			best_dist = d
			best = food
	return best


func _nearest_sheep() -> Sheep:
	var best: Sheep = null
	var best_dist := INF
	for s in get_tree().get_nodes_in_group("animals"):
		var sheep := s as Sheep
		if not is_instance_valid(sheep) or sheep.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(sheep.global_position)
		if d < best_dist and d < village.influence_radius * 2.0:
			best_dist = d
			best = sheep
	return best


func _nearest_corpse() -> Corpse:
	var best: Corpse = null
	var best_dist := INF
	for c in get_tree().get_nodes_in_group("corpses"):
		var corpse := c as Corpse
		if not is_instance_valid(corpse) or corpse.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(corpse.global_position)
		if d < best_dist and d < village.influence_radius * 1.5:
			best_dist = d
			best = corpse
	return best


## Movement ------------------------------------------------------------------

func _move_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < ARRIVE_DIST:
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


## Harm, fear, death ---------------------------------------------------------

func take_damage(amount: float, by_god := false) -> void:
	health -= amount
	happiness = maxf(happiness - 10.0, 0.0)
	if health <= 0.0:
		if by_god:
			village.change_belief(3.0)  # a death witnessed is a god proven
		die(false)


func die(of_old_age: bool) -> void:
	var corpse := Corpse.new()
	corpse.villager_name = villager_name
	corpse.position = global_position + Vector3(0, 0.5, 0)
	get_parent().add_child(corpse)
	if of_old_age:
		GameState.announce("%s died peacefully at %d, full of years." % [villager_name, int(age)])
	else:
		GameState.announce("%s has died at %d." % [villager_name, int(age)])
	queue_free()


func _land() -> void:
	if _fall_speed > 14.0:
		take_damage((_fall_speed - 14.0) * 8.0, true)
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	scare(global_position + Vector3(randf() - 0.5, 0, randf() - 0.5))
	GameState.announce("%s survived a divine toss. Mostly." % villager_name)


func scare(from_pos: Vector3) -> void:
	if state == State.HELD:
		return
	state = State.FLEE
	_flee_from = from_pos
	_action_time = 4.0
	happiness = maxf(happiness - 10.0, 0.0)
	_body_mesh.rotation_degrees.x = 0


## Witnessing horror leaves a mark on the soul.
func witness_horror(weight: float) -> void:
	morality = clampf(morality - weight, -100.0, 100.0)


func receive_heal() -> void:
	health = 100.0
	energy = minf(energy + 40.0, 100.0)
	happiness = minf(happiness + 15.0, 100.0)


func is_worshipping() -> bool:
	return state == State.WORSHIPPING


## Divine hand interface -----------------------------------------------------

func pick_up() -> void:
	state = State.HELD
	_body_mesh.rotation_degrees.x = 0
	velocity = Vector3.ZERO


func drop(throw_velocity: Vector3) -> void:
	state = State.FALLING
	velocity = throw_velocity
	if throw_velocity.length() > 10.0:
		GameState.shift_alignment(-1.0)


## Descriptions --------------------------------------------------------------

func hover_text() -> String:
	var stage := "child" if age < ADULT_AGE else ("elder" if age >= ELDER_AGE else "adult")
	var extra := ", pregnant" if pregnant else ""
	return "%s — %s %s, age %d%s — %s\n(hunger %d · energy %d · happy %d · %s)" % [
		villager_name, _morality_word(), stage, int(age), extra, _status_word(),
		int(hunger), int(energy), int(happiness), "she" if is_female else "he"]


func _morality_word() -> String:
	if morality > 60.0:
		return "saintly"
	if morality > 20.0:
		return "decent"
	if morality > -20.0:
		return "coarse"
	if morality > -60.0:
		return "wicked"
	return "monstrous"


func _status_word() -> String:
	match state:
		State.WANDER: return "strolling"
		State.PLAY: return "playing"
		State.GO_EAT, State.EATING: return "eating"
		State.GO_SLEEP, State.SLEEPING: return "sleeping"
		State.GO_WORK, State.WORKING: return "working the farm"
		State.GO_HUNT, State.HUNTING: return "hunting"
		State.GO_BUTCHER, State.BUTCHERING: return "butchering the dead"
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
		State.HUNTING, State.GO_HUNT: return "hunt"
		State.BUTCHERING: return "..."
		State.WORSHIPPING: return "pray"
		State.PLAY: return "wheee"
		State.FLEE, State.FALLING: return "!!!"
		State.HELD: return "?!"
	if pregnant:
		return "+"
	return ""
