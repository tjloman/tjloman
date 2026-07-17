class_name Villager
extends CharacterBody3D
## A needs-driven villager with a full life: they age, love, bear children,
## work whatever job the village needs, and die — of old age if they're lucky.
##
## JOBS ARE CHOSEN, NOT ASSIGNED: each adult scores the village's problems
## (hunger, lumber, stone, homelessness, empty pens) and takes the most
## urgent work. Morality gates the extremes: only the good may tame beasts,
## and only the fallen will butcher the dead.

enum State {
	WANDER, GO_EAT, EATING, GO_SLEEP, SLEEPING,
	GO_FARM, FARMING, GO_HUNT, HUNTING, GO_BUTCHER, BUTCHERING,
	GO_CHOP, CHOPPING, GO_QUARRY, QUARRYING, GO_BUILD, BUILDING,
	GO_TAME, TAMING, GO_WORSHIP, WORSHIPPING, PLAY,
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
const ARRIVE_DIST := 0.9

const ADULT_AGE := 16.0
const ELDER_AGE := 60.0
const PREGNANCY_YEARS := 0.75  # nine months
const MAX_POPULATION := 24
const STARVING_HUNGER := 90.0
const TAME_MORALITY := 40.0    # benevolent and saintly souls only

var village: Village
var home: House = null
var villager_name := "Villager"
var is_female := randf() < 0.5

# Lifecycle.
var age := 25.0
var lifespan := randf_range(60.0, 85.0)
var pregnant := false
var pregnancy_progress := 0.0

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
var _target_animal: Animal = null
var _target_corpse: Corpse = null
var _target_tree: WildTree = null
var _target_deposit: RockDeposit = null
var _build_site: House = null
var _mount: Animal = null
var _flee_from := Vector3.ZERO
var _fall_speed := 0.0
var _work_sound_time := 0.0
var _state_time := 0.0
var _prev_state := State.WANDER
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
	var shirt := Color.from_hsv(randf(), 0.5, 0.75)
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
	_tick_watchdogs(delta)
	var status := _status_text()
	if _label.text != status:  # Label3D re-renders on every assignment
		_label.text = status

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
			if _wait(delta):
				hunger = maxf(hunger - FoodItem.NUTRITION, 0.0)
				happiness = minf(happiness + 8.0, 100.0)
				_decide()
		State.GO_SLEEP:
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.SLEEPING
				_body_mesh.rotation_degrees.x = 80
		State.SLEEPING:
			_apply_gravity_only(delta)
			# Homeless recovery is miserable: slower sleep, sapped spirits.
			var rate := 8.0 if home != null else 4.0
			if home == null:
				happiness = maxf(happiness - 0.5 * delta, 0.0)
			energy = minf(energy + rate * delta, 100.0)
			if energy >= 100.0 or (energy > 60.0 and not GameState.is_night()):
				_body_mesh.rotation_degrees.x = 0
				_decide()
		State.GO_FARM:
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.FARMING
				_action_time = 3.0
		State.FARMING:
			_apply_gravity_only(delta)
			_action_time -= delta
			village.farm.tend()
			_work_noise("chatter", 6.0, delta)
			if _action_time <= 0.0:
				if village.farm.is_harvestable():
					var yield_bonus := 1 if village.has_pack_animal() else 0
					village.store.add(FoodItem.FoodType.PLANT, village.farm.harvest() + yield_bonus)
					if village.is_player_home:
						GameState.announce("%s brought in the harvest." % villager_name)
				_decide()
		State.GO_HUNT:
			_process_go_target(_target_animal, delta, State.HUNTING, 2.0)
		State.HUNTING:
			if _wait(delta):
				if is_instance_valid(_target_animal):
					var meat := _target_animal.meat_yield() + (1 if village.has_pack_animal() else 0)
					_target_animal.die(false)
					village.store.add(FoodItem.FoodType.MEAT, meat)
				_target_animal = null
				_decide()
		State.GO_BUTCHER:
			_process_go_target(_target_corpse, delta, State.BUTCHERING, 2.5)
		State.BUTCHERING:
			if _wait(delta):
				if is_instance_valid(_target_corpse):
					var corpse_name := _target_corpse.villager_name
					_target_corpse.queue_free()
					village.store.add(FoodItem.FoodType.MEAT, 2)
					morality = maxf(morality - 20.0, -100.0)
					if village.is_player_home:
						GameState.announce("%s butchered the remains of %s. The gods avert their eyes."
							% [villager_name, corpse_name])
				_target_corpse = null
				_decide()
		State.GO_CHOP:
			_process_go_target(_target_tree, delta, State.CHOPPING, 4.0)
		State.CHOPPING:
			_apply_gravity_only(delta)
			_action_time -= delta
			_work_noise("saw", 0.9, delta)
			if _action_time <= 0.0:
				if is_instance_valid(_target_tree) and not _target_tree.is_felled():
					var lumber := _target_tree.fell() + (1 if village.has_pack_animal() else 0)
					village.store.add_lumber(lumber)
				_target_tree = null
				_decide()
		State.GO_QUARRY:
			_process_go_target(_target_deposit, delta, State.QUARRYING, 4.0)
		State.QUARRYING:
			_apply_gravity_only(delta)
			_action_time -= delta
			_work_noise("pick", 0.8, delta)
			if _action_time <= 0.0:
				if is_instance_valid(_target_deposit):
					var stone := _target_deposit.quarry() + (1 if village.has_pack_animal() else 0)
					village.store.add_stone(stone)
				_target_deposit = null
				_decide()
		State.GO_BUILD:
			if _build_site == null or not is_instance_valid(_build_site):
				_build_site = null
				_decide()
			elif _move_toward(_build_site.global_position, WALK_SPEED * _speed_factor(), delta):
				state = State.BUILDING
		State.BUILDING:
			_apply_gravity_only(delta)
			_work_noise("hammer", 0.7, delta)
			if _build_site == null or not is_instance_valid(_build_site):
				_build_site = null
				_decide()
			elif _build_site.under_construction:
				_build_site.advance_construction(House.BUILD_RATE * delta)
			elif _build_site.needs_repair():
				_build_site.repair(20.0 * delta)
				if not _build_site.needs_repair():
					_build_site = null
					_decide()
			else:
				_build_site = null
				_decide()
		State.GO_TAME:
			_process_go_target(_target_animal, delta, State.TAMING, 3.0)
		State.TAMING:
			_apply_gravity_only(delta)
			_action_time -= delta
			if not is_instance_valid(_target_animal) or not _target_animal.is_tamable():
				_target_animal = null
				_decide()
			elif _action_time <= 0.0:
				_target_animal.tame(village)
				morality = minf(morality + 2.0, 100.0)
				if village.is_player_home:
					GameState.announce("%s gently tamed a %s. It follows them home."
						% [villager_name, _target_animal.species])
				_target_animal = null
				_decide()
		State.GO_WORSHIP:
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.WORSHIPPING
				_action_time = 8.0
		State.WORSHIPPING:
			_apply_gravity_only(delta)
			_action_time -= delta
			_work_noise("murmur", 3.5, delta)
			social = minf(social + 5.0 * delta, 100.0)
			happiness = minf(happiness + 1.0 * delta, 100.0)
			morality = minf(morality + 0.05, 100.0)
			_try_conceive(delta)
			if _action_time <= 0.0:
				_decide()


## Never stuck, never lost: re-decide if any state drags on too long
## (blocked paths, vanished targets), and snap back onto the terrain if
## the ground was streamed out from underneath us while the camera roamed.
func _tick_watchdogs(delta: float) -> void:
	if state != _prev_state:
		_prev_state = state
		_state_time = 0.0
	_state_time += delta
	if _state_time > 40.0 and state not in [State.SLEEPING, State.HELD]:
		_state_time = 0.0
		_decide()
	if global_position.y < -12.0:
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null:
			global_position.y = world.height_at(global_position.x, global_position.z) + 1.0
			velocity = Vector3.ZERO
			if state == State.FALLING:
				state = State.WANDER
				_decide()


## Small helpers for the state machine.
func _wait(delta: float) -> bool:
	_apply_gravity_only(delta)
	_action_time -= delta
	return _action_time <= 0.0


# target is deliberately untyped: a typed Node3D parameter rejects freed
# instances at the call site, before the validity guard below can run.
func _process_go_target(target: Variant, delta: float, next: State, work_time: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		_decide()
		return
	if _move_toward(target.global_position, WALK_SPEED * _speed_factor(), delta):
		_dismount()
		state = next
		_action_time = work_time


func _work_noise(sound: String, period: float, delta: float) -> void:
	_work_sound_time -= delta
	if _work_sound_time <= 0.0:
		_work_sound_time = period * randf_range(0.8, 1.3)
		SoundBank.play_at(sound, global_position, -8.0)


## Lifecycle -----------------------------------------------------------------

func _tick_lifecycle(delta: float) -> void:
	var years := delta / GameState.YEAR_SECONDS
	var was_child := age < ADULT_AGE
	age += years
	if was_child and age >= ADULT_AGE:
		_apply_life_stage()
		if village.is_player_home:
			GameState.announce("%s of %s has come of age." % [villager_name, village.village_name])

	if age > lifespan:
		die(true)
		return

	if pregnant:
		pregnancy_progress += years
		if pregnancy_progress >= PREGNANCY_YEARS:
			pregnant = false
			pregnancy_progress = 0.0
			village.spawn_child(global_position)
			if village.is_player_home:
				GameState.announce("%s has given birth! %s grows." % [villager_name, village.village_name])


func _apply_life_stage() -> void:
	_visuals.scale = Vector3.ONE * (0.55 if age < ADULT_AGE else 1.0)


func _speed_factor() -> float:
	var factor := 1.0
	if age >= ELDER_AGE:
		factor = 0.65
	elif pregnant:
		factor = 0.85
	if _mount != null and is_instance_valid(_mount):
		factor *= 1.9
	return factor


func is_adult() -> bool:
	return age >= ADULT_AGE


func _try_conceive(delta: float) -> void:
	if not is_female or pregnant or not is_adult() or age > 45.0:
		return
	if happiness < 50.0 or village.store.total_food() < 4:
		return
	if village.population() >= MAX_POPULATION:
		return
	# ~1 in 3 chance over one 8-second worship session spent near a partner.
	if randf() > 0.05 * delta:
		return
	for other in village.my_villagers():
		if other == self or other.is_female or not other.is_adult():
			continue
		if other.state != State.WORSHIPPING or other.happiness < 50.0:
			continue
		if global_position.distance_to(other.global_position) < 5.0:
			pregnant = true
			pregnancy_progress = 0.0
			if village.is_player_home:
				GameState.announce("%s and %s are expecting a child."
					% [villager_name, other.villager_name])
			return


## Needs ---------------------------------------------------------------------

func _tick_needs(delta: float) -> void:
	var hunger_rate := 0.5 * (1.4 if pregnant else 1.0)
	hunger = minf(hunger + hunger_rate * delta, 100.0)
	if state != State.SLEEPING:
		var working := state in [State.FARMING, State.HUNTING, State.CHOPPING,
			State.QUARRYING, State.BUILDING]
		energy = maxf(energy - (0.5 if working else 0.25) * delta, 0.0)
	social = maxf(social - 0.3 * delta, 0.0)
	if hunger > 85.0:
		happiness = maxf(happiness - 1.5 * delta, 0.0)
	if hunger >= 100.0:
		health -= 2.0 * delta
		if health <= 0.0:
			# You are judged for your own flock, not for strangers far away.
			if village.is_player_home:
				GameState.shift_alignment(-3.0)
				GameState.announce("%s starved to death. The heavens stayed silent." % villager_name)
			die(false)


func cheer(amount: float) -> void:
	happiness = minf(happiness + amount, 100.0)


## Decision-making -----------------------------------------------------------

func _decide() -> void:
	_dismount()
	# Survival first.
	if energy < 20.0:
		_go_sleep()
		return
	if hunger > 60.0 and _plan_eating():
		return
	# Night is for sleeping — though the well-rested potter about a while.
	if GameState.is_night() and energy < 85.0:
		_go_sleep()
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
	if _pick_job():
		return
	state = State.WANDER
	_action_time = randf_range(4.0, 9.0)
	_target = village.global_position \
		+ Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * village.influence_radius * 0.6


func _go_sleep() -> void:
	state = State.GO_SLEEP
	if home != null and is_instance_valid(home):
		_target = home.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	else:
		# Homeless: a patch of dirt near the totem.
		_target = village.totem.global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	_maybe_mount()


## Scores every job the village needs and takes the most urgent one.
func _pick_job() -> bool:
	var store := village.store
	var scores := {}

	# Housing crisis? (Scores sit below a hungry village's food worry so
	# the WHOLE town doesn't drop its ploughs to hammer one hut.)
	var homeless := village.homeless_count()
	var damaged := _find_damaged_house()
	if village.construction_site != null:
		scores["build"] = 42.0
	elif homeless > 0 and store.lumber >= 4 and store.stone >= 2:
		scores["build"] = 38.0 + homeless * 6.0
	elif damaged != null and store.lumber >= 1:
		scores["build"] = 26.0

	# Materials wanted? (for the next hut, plus a reserve)
	var want_lumber: bool = store.lumber < 10 and (homeless > 0 or store.lumber < 5)
	var want_stone: bool = store.stone < 6 and (homeless > 0 or store.stone < 3)
	if want_lumber and _nearest_in_group("trees", village.influence_radius * 2.5) != null:
		scores["chop"] = 35.0 + maxf(10.0 - store.lumber, 0.0) * 2.0
	if want_stone and _nearest_in_group("rock_deposits", village.influence_radius * 2.5) != null:
		scores["quarry"] = 33.0 + maxf(6.0 - store.stone, 0.0) * 2.0

	# Food security, per diet.
	var abandoned := village.agriculture_abandoned()
	var eats_meat := village.diet != Village.Diet.VEGAN
	var food_worry := maxf(20.0 - store.total_food(), 0.0) * 3.0
	if not abandoned:
		scores["farm"] = 20.0 + food_worry
	if village.diet == Village.Diet.CANNIBAL and store.meat_food < 4 \
			and _will_eat_human_flesh() and _nearest_corpse() != null:
		scores["butcher"] = 50.0 + food_worry
	if eats_meat and store.meat_food < 5:
		if abandoned and village.best_penned_meat() != null:
			scores["butcher_pen"] = 40.0 + food_worry
		if _nearest_huntable() != null:
			scores["hunt"] = (35.0 if abandoned else 25.0) + food_worry

	# Taming: a privilege of the good, pointless for the fallen.
	if morality >= TAME_MORALITY and not abandoned and village.tamed_count() < Village.MAX_TAMED:
		if _nearest_tamable() != null:
			scores["tame"] = 22.0

	if scores.is_empty():
		return false
	var best: String = ""
	var best_score := 0.0
	for job: String in scores:
		var jittered: float = scores[job] + randf_range(-5.0, 5.0)
		if jittered > best_score:
			best_score = jittered
			best = job
	_start_job(best)
	return true


func _start_job(job: String) -> void:
	match job:
		"build":
			if village.construction_site != null:
				_build_site = village.construction_site
			else:
				_build_site = _find_damaged_house()
				if _build_site == null:
					var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
					_build_site = village.start_construction(world)
			if _build_site == null:
				state = State.WANDER
				_action_time = 2.0
				return
			state = State.GO_BUILD
			_maybe_mount()
		"chop":
			_target_tree = _nearest_in_group("trees", village.influence_radius * 2.5) as WildTree
			state = State.GO_CHOP
			_maybe_mount()
		"quarry":
			_target_deposit = _nearest_in_group("rock_deposits",
				village.influence_radius * 2.5) as RockDeposit
			state = State.GO_QUARRY
			_maybe_mount()
		"farm":
			state = State.GO_FARM
			_target = village.farm.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		"hunt":
			_target_animal = _nearest_huntable()
			state = State.GO_HUNT
			_maybe_mount()
		"butcher":
			_target_corpse = _nearest_corpse()
			state = State.GO_BUTCHER
		"butcher_pen":
			_target_animal = village.best_penned_meat()
			state = State.GO_HUNT  # same flow: walk to it, then the deed
		"tame":
			_target_animal = _nearest_tamable()
			state = State.GO_TAME


func _find_damaged_house() -> House:
	for h in village.houses:
		if is_instance_valid(h) and h.needs_repair():
			return h
	return null


## Good souls refuse human flesh — until they are starving.
func _will_eat_human_flesh() -> bool:
	return morality < 30.0 or hunger > STARVING_HUNGER


## Eating --------------------------------------------------------------------

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
				if village.is_player_home:
					GameState.announce("%s has eaten human flesh. Something in them dims."
						% villager_name)
			_target_food.queue_free()
			_target_food = null
			_dismount()
			state = State.EATING
			_action_time = 2.0
	else:
		if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
			_dismount()
			for type in village.allowed_food_types():
				if village.store.take(type, 1) > 0:
					state = State.EATING
					_action_time = 2.0
					return
			_decide()


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


func _nearest_huntable() -> Animal:
	var best: Animal = null
	var best_dist := INF
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or animal.is_queued_for_deletion():
			continue
		if animal.meat_yield() <= 0 or animal.tamed_by != null:
			continue
		if animal.spec.get("predator", false):
			continue  # villagers hunt dinner, not death
		var d := global_position.distance_to(animal.global_position)
		if d < best_dist and d < village.influence_radius * 2.0:
			best_dist = d
			best = animal
	return best


func _nearest_tamable() -> Animal:
	var best: Animal = null
	var best_dist := INF
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or not animal.is_tamable():
			continue
		var d := global_position.distance_to(animal.global_position)
		if d < best_dist and d < village.influence_radius * 2.0:
			best_dist = d
			best = animal
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


func _nearest_in_group(group: String, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_dist := max_dist
	for n in get_tree().get_nodes_in_group(group):
		var node := n as Node3D
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is WildTree and (node as WildTree).is_felled():
			continue
		var d := global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


## Riding --------------------------------------------------------------------

## The good may ride: grab an idle tamed horse/llama for a long trip.
func _maybe_mount() -> void:
	if morality < TAME_MORALITY or _mount != null:
		return
	var mount := village.idle_mount()
	if mount == null:
		return
	if mount.global_position.distance_to(global_position) < 15.0:
		_mount = mount
		mount.set_rider(self)


func _dismount() -> void:
	if _mount != null and is_instance_valid(_mount):
		_mount.set_rider(null)
	_mount = null


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
	# Bodies are modeled facing +Z, and look_at aims -Z — so look away
	# from the direction of travel to face it. (Yes, everyone used to moonwalk.)
	look_at(global_position - Vector3(dir.x, 0, dir.z), Vector3.UP)
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
			village.change_belief(3.0)
		die(false)


func die(of_old_age: bool) -> void:
	_dismount()
	var corpse := Corpse.new()
	corpse.villager_name = villager_name
	var parent := get_parent() as Node3D
	corpse.position = parent.to_local(global_position + Vector3(0, 0.5, 0))
	parent.add_child(corpse)
	if village.is_player_home:
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
	_dismount()
	state = State.FLEE
	_flee_from = from_pos
	_action_time = 4.0
	happiness = maxf(happiness - 10.0, 0.0)
	_body_mesh.rotation_degrees.x = 0


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
	_dismount()
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
	if home == null:
		extra += ", HOMELESS"
	return "%s of %s — %s %s, age %d%s — %s\n(hunger %d · energy %d · happy %d · %s)" % [
		villager_name, village.village_name, _morality_word(), stage, int(age), extra,
		_status_word(), int(hunger), int(energy), int(happiness), "she" if is_female else "he"]


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
		State.GO_SLEEP, State.SLEEPING: return "sleeping" if home != null else "sleeping rough"
		State.GO_FARM, State.FARMING: return "working the farm"
		State.GO_HUNT, State.HUNTING: return "hunting"
		State.GO_BUTCHER, State.BUTCHERING: return "butchering the dead"
		State.GO_CHOP, State.CHOPPING: return "felling timber"
		State.GO_QUARRY, State.QUARRYING: return "quarrying stone"
		State.GO_BUILD, State.BUILDING: return "building"
		State.GO_TAME, State.TAMING: return "taming a beast"
		State.GO_WORSHIP, State.WORSHIPPING: return "worshipping"
		State.FLEE: return "fleeing in terror"
		State.HELD: return "in the grip of a god"
		State.FALLING: return "airborne"
	return "?"


func _status_text() -> String:
	match state:
		State.SLEEPING: return "zzz"
		State.EATING: return "nom"
		State.FARMING: return "farm"
		State.HUNTING: return "hunt"
		State.CHOPPING: return "chop"
		State.QUARRYING: return "mine"
		State.BUILDING: return "build"
		State.TAMING: return "shhh"
		State.BUTCHERING: return "..."
		State.WORSHIPPING: return "pray"
		State.PLAY: return "wheee"
		State.FLEE, State.FALLING: return "!!!"
		State.HELD: return "?!"
	if pregnant:
		return "+"
	return ""
