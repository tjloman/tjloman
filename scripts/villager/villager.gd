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
	GO_PREACH, PREACHING, GO_FEED, GO_BUILD_FARM, BUILDING_FARM,
	GO_FISH, FISHING, COURT, FOLLOW_MOM, AT_SCHOOL, TEACH,
	GO_BUILD_EDUBBA, BUILDING_EDUBBA,
	HAULING, GO_ARM, FIGHT, HIDE,
	FLEE, HELD, FALLING, DYING,
}

## Names are drawn by sex, so a villager's name reads with its model.
const FEMALE_NAMES := [
	"Bess", "Dara", "Greta", "Isolde", "Kira", "Mabel",
	"Opal", "Rosa", "Tilda", "Vera", "Yara", "Freya",
]
const MALE_NAMES := [
	"Aldo", "Cormac", "Edwin", "Fen", "Hobb", "Jarek",
	"Lomax", "Nol", "Pip", "Sten", "Ulf", "Wick",
]

const WALK_SPEED := 3.0
const FLEE_SPEED := 5.5
const GRAVITY := 20.0
const ARRIVE_DIST := 0.9

const ADULT_AGE := 16.0
## WEANED. A mother will not start another child while one still needs her —
## but "needs her" used to mean until the child was a grown ADULT of sixteen,
## which is more than half a woman's fertile life and, on its own, most of why
## villages could not replace their dead. Six years is a child who can be left
## with the village.
const WEANED_AGE := 6.0
const ELDER_AGE := 60.0
const PREGNANCY_YEARS := 0.75  # nine months
const STARVING_HUNGER := 90.0
const TAME_MORALITY := 40.0    # benevolent and saintly souls only

## COURAGE IN NUMBERS. A villager caught alone by a wolf runs (and is usually
## run down); it takes a BAND to stand and fight. This is the whole balance of
## the militia: one soul is prey, three are a hunting party.
const ALLY_RADIUS := 14.0      # how far apart the band may be and still count
const COURAGE_ARMED := 1       # allies an ARMED villager needs to hold ground
const COURAGE_BARE := 2        # allies a bare-handed one needs
const RETREAT_HEALTH := 30.0   # hurt this badly and even a brave one falls back

## Hazards: fire and deep water each drain 100 health to 0 in ten seconds.
const HAZARD_RATE := 10.0
const DROWN_DEPTH := 1.1        # water this deep over the feet drowns them
const DYING_SECONDS := 10.0     # the window to be healed or lifted back to life
const REVIVE_HEALTH := 10.0     # what a rescue restores them to

## How much an already-taken job is discouraged for each villager on it, so
## the flock spreads across the village's needs instead of all rushing one.
const CROWD_PENALTY := 7.0

var village: Village
var home: House = null
var villager_name := "Villager"
var is_female := randf() < 0.5
var mother: Villager = null      # who bore this one; children trail her
var is_teacher := false          # minds the Edubba, keeping children close

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
var burning := false   # ablaze: drains health until doused or dead
var weapon := ""      # "" = bare-handed; otherwise a Weapon.SPECS kind

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
var _burn_visual: Node3D = null
var _dying_time := 0.0
var _spin_ang := Vector3.ZERO   # aftertouch spin axis*rate while thrown (rad/s)
var _animator: ModelAnimator = null   # non-null only for a rigged custom model
var _work_sound_time := 0.0
var _state_time := 0.0
var _prev_state := State.WANDER
var _gentle_drop := false
var _mission_village: Village = null
var _ground_check_time := randf_range(1.0, 3.0)
var _wd_pos := Vector3.ZERO       # last spot we made real headway from
var _wd_still := 0.0             # seconds of a travel state spent going nowhere
var _sim_skip := 0               # physics frames skipped while far from the camera
var _target_bush: ForageBush = null
var _target_farm: Farm = null
var _carrying_feed := false
var _carry_kind := ""            # non-empty while hauling a gathered load home
var _carry_amount := 0
var _carry_job := ""             # the job this load came from (for crowd tally)
var _carry_announce := ""        # spoken on delivery, if the player's home
var _carry_visual: Node3D = null
var _farm_spot := Vector3.INF
var _fish_spot := Vector3.INF
var _world_cache: WorldGen = null
var _edubba_spot := Vector3.INF
var _breed_cooldown := randf_range(4.0, 12.0)
var _fight_target: Node3D = null   # the beast (or creature) being fought
var _attack_cd := 0.0
var _last_attacker: Node3D = null   # who drew blood last (for the blood debt)
var _weapon_visual: Node3D = null
var _label: Label3D
var _visuals: Node3D
var _body_mesh: Node3D   # MeshInstance3D (procedural) or a custom model root


func _ready() -> void:
	add_to_group("villagers")
	add_to_group("pickable")
	collision_layer = 2
	collision_mask = 1 | 8  # world + trees (their own layer)
	villager_name = _random_name()

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.2
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)

	_visuals = Node3D.new()
	add_child(_visuals)
	# Sex-specific art first (villager_female / villager_male), then a generic
	# villager model, then the primitive body.
	var custom := ModelBank.instantiate_any([_sex_model(), "villager"])
	if custom != null:
		# A custom villager model stands in for the whole body. If it's rigged
		# with clips, an animator drives them and the procedural "bend" yields.
		_body_mesh = custom
		_visuals.add_child(_body_mesh)
		_animator = ModelAnimator.create(custom)
	else:
		# Shirt hue is quantised to 12 buckets so a crowd shares a handful of
		# shared materials (and meshes) the renderer can batch, instead of 25
		# unique ones. The body mesh is only ever rotated, never recoloured, so
		# a shared material is safe.
		var shirt := Color.from_hsv(snappedf(randf(), 1.0 / 12.0), 0.5, 0.75)
		_body_mesh = Util.lite_capsule(0.28, 1.0, shirt, Vector3(0, 0.55, 0))
		_visuals.add_child(_body_mesh)
		_visuals.add_child(Util.lite_sphere(0.18, Color(0.9, 0.75, 0.6), Vector3(0, 1.25, 0)))
	# Distant crowds stop drawing entirely — a big village no longer renders
	# dozens of bodies at once on a budget phone.
	Util.apply_lod(_visuals, Quality.actor_distance())

	_label = Util.status_label()
	_label.position = Vector3(0, 1.8, 0)
	add_child(_label)

	_apply_life_stage()
	_decide()


func _physics_process(delta: float) -> void:
	# Simulation LOD: a villager the player isn't looking at runs on a slower
	# clock — it still lives and works, just updated every few frames with the
	# skipped time folded into delta. Held/falling always run full-rate so the
	# hand stays responsive wherever it reaches.
	if state != State.HELD and state != State.FALLING:
		var stride := Util.sim_stride(global_position)
		if stride > 1:
			_sim_skip += 1
			if _sim_skip < stride:
				return
			delta *= _sim_skip
			_sim_skip = 0
	# Dying suspends the whole normal life — they lie there, out of the fight,
	# until healed/lifted back or the window closes.
	if state == State.DYING:
		_process_dying(delta)
		_stick_to_ground()
		return
	_tick_lifecycle(delta)
	_tick_needs(delta)
	_tick_watchdogs(delta)
	_tick_hazards(delta)
	var status := _status_text()
	if _label.text != status:  # Label3D re-renders on every assignment
		_label.text = status
	if _animator != null:
		_animator.play(_anim_state())

	match state:
		State.HELD:
			velocity = Vector3.ZERO
			return
		State.FALLING:
			_fall_speed = velocity.length()
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if _spin_ang.length() > 0.001:  # aftertouch tumble about a 3D axis
				_visuals.global_rotate(_spin_ang.normalized(), _spin_ang.length() * delta)
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
				_eat_meal()
				happiness = minf(happiness + 8.0, 100.0)
				_decide()
		State.GO_SLEEP:
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.SLEEPING
				_pitch_body(80.0)
		State.SLEEPING:
			_apply_gravity_only(delta)
			# Homeless recovery is miserable: slower sleep, sapped spirits.
			var rate := 8.0 if home != null else 4.0
			if home == null:
				happiness = maxf(happiness - 0.5 * delta, 0.0)
			energy = minf(energy + rate * delta, 100.0)
			# Nobody starves to death IN BED: a growling stomach wakes you,
			# and _decide puts eating before everything else.
			if hunger > 80.0:
				_pitch_body(0.0)
				_decide()
			elif energy >= 100.0 or (energy > 60.0 and not GameState.is_night()):
				_pitch_body(0.0)
				_decide()
		State.GO_FARM:
			if _target_farm == null or not is_instance_valid(_target_farm):
				_decide()
			elif _state_time > 10.0:
				_decide()  # can't reach the field — give it up (frees the claim)
			elif _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.FARMING
				_action_time = 3.0
		State.FARMING:
			_apply_gravity_only(delta)
			_action_time -= delta
			if _target_farm == null or not is_instance_valid(_target_farm) \
					or not _target_farm.is_workable():
				_decide()
				return
			_target_farm.tend()
			_work_noise("chatter", 6.0, delta)
			if _action_time <= 0.0:
				if _target_farm.is_harvestable():
					var yield_bonus := 1 if village.has_pack_animal() else 0
					var grain := _target_farm.harvest() + yield_bonus
					_release_farm()  # done here; free the field before the long walk back
					_carry_announce = "%s brought in the harvest." % villager_name
					_begin_haul("plant", grain, "farm")
				else:
					_decide()
		State.GO_FEED:
			if not _carrying_feed:
				if _move_toward(village.store.global_position, WALK_SPEED * _speed_factor(), delta):
					if village.store.take(FoodItem.FoodType.PLANT, 1) > 0:
						_carrying_feed = true
					else:
						_decide()
			elif _move_toward(village.pen_position(), WALK_SPEED * _speed_factor(), delta):
				village.feed_penned()
				_carrying_feed = false
				_decide()
		State.GO_FISH:
			if _fish_spot == Vector3.INF:
				_decide()
			elif _move_toward(_fish_spot, WALK_SPEED * _speed_factor(), delta, 1.6):
				_dismount()
				state = State.FISHING
				_action_time = 9.0
		State.FISHING:
			_apply_gravity_only(delta)
			_action_time -= delta
			if _action_time <= 0.0:
				if village.is_player_home and randf() < 0.3:
					GameState.announce("%s pulled a fish from the shallows." % villager_name)
				_fish_spot = Vector3.INF
				_begin_haul("meat", 1, "fish")
		State.GO_BUILD_FARM:
			if _move_toward(_farm_spot, WALK_SPEED * _speed_factor(), delta):
				_dismount()
				state = State.BUILDING_FARM
				_action_time = 10.0
		State.BUILDING_FARM:
			_apply_gravity_only(delta)
			_action_time -= delta
			_work_noise("hammer", 0.8, delta)
			if _action_time <= 0.0:
				village.spawn_farm_at(_farm_spot)
				_farm_spot = Vector3.INF
				_decide()
		State.GO_BUILD_EDUBBA:
			if _move_toward(_edubba_spot, WALK_SPEED * _speed_factor(), delta):
				_dismount()
				state = State.BUILDING_EDUBBA
				_action_time = 22.0
		State.BUILDING_EDUBBA:
			_apply_gravity_only(delta)
			_action_time -= delta
			_work_noise("hammer", 0.8, delta)
			if _action_time <= 0.0:
				village.spawn_edubba_at(_edubba_spot)
				_edubba_spot = Vector3.INF
				_decide()
		State.GO_ARM:
			# To the storehouse for arms. If the stores can't pay for a weapon
			# they go bare-handed rather than stand about.
			if village == null or not is_instance_valid(village.store):
				_decide()
			elif _move_toward(village.store.global_position,
					WALK_SPEED * _speed_factor(), delta, 2.2):
				_take_up_arms()
				_decide()
		State.FIGHT:
			_process_fight(delta)
		State.HIDE:
			# Not every people answers terror with steel. Run for the nearest
			# home and cower there until the danger passes.
			_action_time -= delta
			if _move_toward(_target, FLEE_SPEED, delta, 1.5):
				_apply_gravity_only(delta)
				happiness = maxf(happiness - 2.0 * delta, 0.0)
			if _action_time <= 0.0:
				_decide()
		State.HAULING:
			# Carry the gathered load home on foot — nothing teleports to the
			# store; if the store is gone, the load is simply dropped.
			if village == null or village.store == null \
					or not is_instance_valid(village.store):
				_clear_carry()
				_decide()
			elif _move_toward(village.store.global_position,
					WALK_SPEED * _speed_factor(), delta, 2.2):
				_deliver_carry()
				_decide()
		State.COURT:
			# Court at the totem; conception happens while worshipping there.
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				state = State.WORSHIPPING
				_action_time = 8.0
		State.FOLLOW_MOM:
			_process_follow_mom(delta)
		State.AT_SCHOOL:
			_process_at_school(delta)
		State.TEACH:
			# The teacher keeps station in the school yard.
			if _move_toward(_target, WALK_SPEED * _speed_factor(), delta):
				_apply_gravity_only(delta)
			_action_time -= delta
			if _action_time <= 0.0 or not village.has_edubba():
				_decide()
		State.GO_HUNT:
			_process_go_target(_target_animal, delta, State.HUNTING, 2.0)
		State.HUNTING:
			if _wait(delta):
				var meat := 0
				if is_instance_valid(_target_animal):
					meat = _target_animal.meat_yield() + (1 if village.has_pack_animal() else 0)
					_target_animal.die(false)
				_target_animal = null
				if meat > 0:
					_begin_haul("meat", meat, "hunt")
				else:
					_decide()
		State.GO_BUTCHER:
			_process_go_target(_target_corpse, delta, State.BUTCHERING, 2.5)
		State.BUTCHERING:
			if _wait(delta):
				var butchered := false
				if is_instance_valid(_target_corpse):
					var corpse_name := _target_corpse.villager_name
					_target_corpse.queue_free()
					morality = maxf(morality - 20.0, -100.0)
					butchered = true
					if village.is_player_home:
						GameState.announce("%s butchered the remains of %s. The gods avert their eyes."
							% [villager_name, corpse_name])
				_target_corpse = null
				if butchered:
					_begin_haul("meat", 2, "butcher")
				else:
					_decide()
		State.GO_CHOP:
			_process_go_target(_target_tree, delta, State.CHOPPING, 4.0)
		State.CHOPPING:
			_apply_gravity_only(delta)
			_action_time -= delta
			_work_noise("saw", 0.9, delta)
			if _action_time <= 0.0:
				var lumber := 0
				if is_instance_valid(_target_tree) and not _target_tree.is_felled() \
						and not _target_tree.is_held():
					lumber = _target_tree.fell() + (1 if village.has_pack_animal() else 0)
				_target_tree = null
				if lumber > 0:
					_begin_haul("lumber", lumber, "chop")
				else:
					_decide()
		State.GO_QUARRY:
			_process_go_target(_target_deposit, delta, State.QUARRYING, 4.0)
		State.QUARRYING:
			_apply_gravity_only(delta)
			_action_time -= delta
			_work_noise("pick", 0.8, delta)
			if _action_time <= 0.0:
				var stone := 0
				if is_instance_valid(_target_deposit):
					stone = _target_deposit.quarry() + (1 if village.has_pack_animal() else 0)
				_target_deposit = null
				if stone > 0:
					_begin_haul("stone", stone, "quarry")
				else:
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
		State.GO_PREACH:
			if _mission_village == null or not is_instance_valid(_mission_village):
				_mission_village = null
				_decide()
			elif _move_toward(_mission_village.totem.global_position
					+ Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)),
					WALK_SPEED * _speed_factor(), delta):
				state = State.PREACHING
				_action_time = 35.0
		State.PREACHING:
			_apply_gravity_only(delta)
			_action_time -= delta
			_work_noise("murmur", 3.0, delta)
			if _mission_village == null or not is_instance_valid(_mission_village):
				_mission_village = null
				_decide()
			elif _mission_village.converted:
				GameState.announce("%s has brought %s into the light!"
					% [villager_name, _mission_village.village_name])
				morality = minf(morality + 5.0, 100.0)
				_mission_village = null
				_decide()
			else:
				_mission_village.change_belief(0.45 * delta)
				if _action_time <= 0.0:
					_mission_village = null
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
	_stick_to_ground()


## Glue to the terrain SURFACE every frame (using the analytic height, which
## exists even where the collision chunk hasn't streamed in). This is what
## stops far-off — or just-warped-to — villagers from falling through unloaded
## ground and being popped back up a second later; they simply never leave it.
func _stick_to_ground() -> void:
	if state == State.FALLING or state == State.HELD:
		return
	var world := _world()
	if world == null:
		return
	var h := world.height_at(global_position.x, global_position.z)
	if global_position.y < h - 0.3:  # tolerance clears resting offsets/mesh dips
		global_position.y = h
		if velocity.y < 0.0:
			velocity.y = 0.0


## True while the villager is en route somewhere (as opposed to working,
## resting, or socialising in place) — the states the no-progress breaker
## watches, since only a moving villager can be "blocked".
func _is_travelling() -> bool:
	return state in [
		State.WANDER, State.GO_EAT, State.GO_SLEEP, State.GO_FARM, State.GO_FEED,
		State.GO_FISH, State.GO_BUILD_FARM, State.GO_BUILD_EDUBBA, State.GO_HUNT,
		State.GO_BUTCHER, State.GO_CHOP, State.GO_QUARRY, State.GO_BUILD,
		State.GO_TAME, State.GO_WORSHIP, State.GO_PREACH, State.COURT, State.HAULING,
		State.GO_ARM,
	]


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
	# No-progress breaker: a villager on a TRIP (heading somewhere) that hasn't
	# covered ground for a few seconds is blocked — a lakeshore it can't round,
	# a knot of bodies. Re-decide now so it picks a reachable errand instead of
	# starving at the water's edge until the 40s timeout.
	if _is_travelling():
		if global_position.distance_to(_wd_pos) > 0.5:
			_wd_pos = global_position
			_wd_still = 0.0
		else:
			_wd_still += delta
			if _wd_still > 4.0:
				_wd_still = 0.0
				_wd_pos = global_position
				_decide()
	else:
		_wd_still = 0.0
		_wd_pos = global_position
	if global_position.y < -12.0:
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null:
			global_position.y = world.height_at(global_position.x, global_position.z) + 1.0
			velocity = Vector3.ZERO
			if state == State.FALLING:
				state = State.WANDER
				_decide()
	# Waist-deep in a hillside (bad spawn, collision hiccup): pop back up.
	_ground_check_time -= delta
	if _ground_check_time <= 0.0:
		_ground_check_time = 3.0
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null:
			var h := world.height_at(global_position.x, global_position.z)
			if global_position.y < h - 1.0:
				global_position.y = h + 0.4
				velocity = Vector3.ZERO


## Small helpers for the state machine.
func _wait(delta: float) -> bool:
	_apply_gravity_only(delta)
	_action_time -= delta
	return _action_time <= 0.0


# target is deliberately untyped: a typed Node3D parameter rejects freed
# instances at the call site, before the validity guard below can run.
# Work range is generous: rock deposits and animals have fat colliders
# that physically stop a villager ~1.5m out — "arrived" must reach past
# them or the villager shoves at the rock forever and quarries nothing.
func _process_go_target(target: Variant, delta: float, next: State, work_time: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		_decide()
		return
	if _move_toward(target.global_position, WALK_SPEED * _speed_factor(), delta, 2.4):
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
			village.spawn_child(global_position, self)
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


## Give up any claimed field so another farmer may work it.
func _release_farm() -> void:
	if _target_farm != null and is_instance_valid(_target_farm):
		_target_farm.release(self)
	_target_farm = null


## Sex framework ------------------------------------------------------------
## `is_female` (set at birth) already drives courtship, pregnancy, and the
## "she/he" of the hover. These give it a name and a model to match, so
## custom male/female art and gendered names slot straight in.

func _sex_model() -> String:
	return "villager_female" if is_female else "villager_male"


func _random_name() -> String:
	var pool := FEMALE_NAMES if is_female else MALE_NAMES
	return pool[randi() % pool.size()]


func sex_word() -> String:
	return "woman" if is_female else "man"


## Animation ----------------------------------------------------------------

## Tilt the body forward to mime work — but only when NOT driven by a rigged
## model, whose own clips own the pose.
func _pitch_body(deg: float) -> void:
	if _animator == null:
		_body_mesh.rotation_degrees.x = deg


## The semantic clip a rigged model should play for the current state. Missing
## clips are ignored, so a model with only walk/idle still works.
func _anim_state() -> String:
	match state:
		State.DYING: return "dying"
		State.FALLING: return "fall"
		State.HAULING: return "carry"
		State.GO_ARM: return "run"
		State.FIGHT: return "attack"
		State.HELD: return "idle"
		State.FLEE: return "run"
		State.SLEEPING: return "sleep"
		State.EATING: return "eat"
		State.WORSHIPPING, State.PREACHING: return "pray"
		State.PLAY: return "play"
		State.FARMING, State.CHOPPING, State.QUARRYING, State.BUILDING, \
		State.BUILDING_FARM, State.BUILDING_EDUBBA, State.BUTCHERING, \
		State.TAMING, State.HUNTING, State.FISHING, State.TEACH:
			return "work"
	# Everything else: walking if moving, otherwise idle.
	return "walk" if Vector2(velocity.x, velocity.z).length() > 0.3 else "idle"


## Interest reawakens at adulthood and stays high while the body is fed
## and rested — but a mother won't conceive again while a child still
## trails her (they must be grown or gone to school first).
func wants_to_breed() -> bool:
	if not is_adult() or pregnant or age > 45.0:
		return false
	if _breed_cooldown > 0.0:
		return false
	if hunger > 55.0 or energy < 35.0 or happiness < 45.0:
		return false
	if village.store.total_food() < 4 or village.at_capacity():
		return false
	if is_teacher:
		return false
	return not _has_dependent_child()


## A child of mine still at the breast (and no school to mind it).
func _has_dependent_child() -> bool:
	if village.has_edubba():
		return false
	for v in village.my_villagers():
		if v.mother == self and v.age < WEANED_AGE:
			return true
	return false


func _try_conceive(delta: float) -> void:
	if not is_female or pregnant or not is_adult() or age > 45.0:
		return
	if happiness < 45.0 or village.store.total_food() < 4:
		return
	if village.at_capacity() or _has_dependent_child():
		return  # shelter bounds the flock — and a mother finishes one child first
	# Untended villages barely grow; tended ones quicken (see conception_chance).
	if randf() > village.conception_chance() * delta:
		return
	# A partner who came to the totem for the same reason. Courting AND
	# worshipping both count: insisting the man be mid-worship at the exact
	# instant of the roll was a coincidence the pair could rarely manage.
	for other in village.my_villagers():
		if other == self or other.is_female or not other.is_adult():
			continue
		if other.state != State.WORSHIPPING and other.state != State.COURT:
			continue
		if other.happiness < 40.0 or other.age > 55.0:
			continue
		if global_position.distance_to(other.global_position) < 7.0:
			pregnant = true
			pregnancy_progress = 0.0
			_breed_cooldown = 30.0
			if village.is_player_home:
				GameState.announce("%s and %s are expecting a child."
					% [villager_name, other.villager_name])
			return


## Needs ---------------------------------------------------------------------

func _tick_needs(delta: float) -> void:
	# Bellies empty at HALF the old rate: with hauling, militia duty and spread
	# job priorities all competing for hands, the village could not out-farm the
	# old appetite and starved. A slower burn lets the granary keep ahead.
	var hunger_rate := 0.25 * (1.4 if pregnant else 1.0)
	if state == State.SLEEPING:
		hunger_rate *= 0.4  # a sleeping body burns slow
	hunger = minf(hunger + hunger_rate * delta, 100.0)
	if state != State.SLEEPING:
		var working := state in [State.FARMING, State.HUNTING, State.CHOPPING,
			State.QUARRYING, State.BUILDING]
		energy = maxf(energy - (0.5 if working else 0.25) * delta, 0.0)
	social = maxf(social - 0.3 * delta, 0.0)
	_breed_cooldown = maxf(_breed_cooldown - delta, 0.0)
	# A fed body knits itself back together — small wounds heal.
	if hunger < 70.0 and health < 100.0:
		health = minf(health + 1.5 * delta, 100.0)
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
	_release_farm()  # re-deciding drops any field claim, so others may take it
	if _carry_kind != "":
		_clear_carry()  # a load abandoned mid-haul is lost (interrupted by fear, etc.)
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
	# Children: off to school if the village has one, otherwise trailing
	# their mother; only orphans and idlers just play.
	if not is_adult():
		if village.has_edubba():
			state = State.AT_SCHOOL
			return
		if mother != null and is_instance_valid(mother) and mother.village == village:
			state = State.FOLLOW_MOM
			_action_time = randf_range(2.0, 4.0)
			return
		state = State.PLAY
		_action_time = randf_range(3.0, 6.0)
		_target = village.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 8.0
		return
	# Lost the post (school gone, or replaced)? Stop being a teacher.
	if is_teacher and (not village.has_edubba() or village.teacher != self):
		is_teacher = false
	# A teacher is needed and I'm free to take the post.
	if village.needs_teacher() and not _has_dependent_child():
		is_teacher = true
		village.teacher = self
	if is_teacher and village.has_edubba():
		state = State.TEACH
		_action_time = randf_range(8.0, 16.0)
		_target = village.edubba.yard_position()
		return
	# Breeding is a high drive once of age, when body and larder allow.
	if wants_to_breed():
		state = State.COURT
		# How OFTEN they court is what paces a village's growth now, so this is
		# the number to turn if towns grow too fast or too slowly.
		_breed_cooldown = randf_range(12.0, 25.0)
		_target = village.totem.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		return
	if social < 30.0:
		state = State.GO_WORSHIP
		_target = village.totem.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		return
	# THE ALARM outranks ordinary work: while the village is roused, the able
	# arm themselves and go for the threat — but only if they dare. Caught alone
	# and bare-handed, a villager runs instead (and is often run down).
	if village != null and village.is_roused() and is_adult():
		var foe := _find_foe()
		if foe != null:
			# WHETHER THEY FIGHT AT ALL is their own hard-won doctrine: a village
			# that has stood and won reaches for weapons, one that has buried its
			# dead bars its doors instead (see Village.resolve).
			var allies := _allies_near()
			if village.will_fight(allies, weapon != ""):
				if weapon == "" and Weapon.affordable(village.store) != "" and allies >= 1:
					state = State.GO_ARM
					return
				if _dares_fight():
					_fight_target = foe
					state = State.FIGHT
					_attack_cd = 0.3
					return
			# No stomach for it: hide, and let the beast have the run of the place.
			state = State.HIDE
			_action_time = randf_range(8.0, 16.0)
			_target = village.refuge(global_position)
			_report_terror(foe)
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
		# Hungry and short of fields? Break new ground.
		if food_worry > 20.0 and village.wants_new_farm() and store.lumber >= 4:
			scores["build_farm"] = 30.0 + food_worry * 0.5
	if village.penned_hungry() and store.plant_food > 2:
		scores["feed"] = 26.0
	# A village with children and no school wants an Edubba raised.
	if village.wants_edubba():
		scores["build_edubba"] = 34.0
	if village.diet == Village.Diet.CANNIBAL and store.meat_food < 4 \
			and _will_eat_human_flesh() and _nearest_corpse() != null:
		scores["butcher"] = 50.0 + food_worry
	if eats_meat and store.meat_food < 5:
		if abandoned and village.best_penned_meat() != null:
			scores["butcher_pen"] = 40.0 + food_worry
		if _nearest_huntable() != null:
			scores["hunt"] = (35.0 if abandoned else 25.0) + food_worry
		# The shore feeds anyone patient enough to stand on it.
		if _find_shore() != Vector3.INF:
			scores["fish"] = 23.0 + food_worry * 0.6

	# Taming: a privilege of the good, pointless for the fallen. An empty
	# pen makes it urgent — a dog and a mount change everything.
	if morality >= TAME_MORALITY and not abandoned and village.tamed_count() < Village.MAX_TAMED:
		if _nearest_tamable() != null:
			scores["tame"] = 24.0 + (12.0 if village.tamed_count() == 0 else 0.0)

	if scores.is_empty():
		return false
	# Pooled distribution: discourage jobs the flock is already crowding onto,
	# so villagers fan out across the village's needs instead of all rushing the
	# nearest tree or field (the first-run conga line).
	var crowd := village.job_counts()
	var best: String = ""
	var best_score := -INF
	for job: String in scores:
		var jittered: float = scores[job] + randf_range(-5.0, 5.0) \
			- CROWD_PENALTY * float(crowd.get(job, 0))
		if jittered > best_score:
			best_score = jittered
			best = job
	if best == "":
		return false
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
			_target_farm = village.pick_farm(global_position, self)
			if _target_farm == null:
				state = State.WANDER
				_action_time = 2.0
				return
			state = State.GO_FARM
			_target = _target_farm.global_position  # the field centre is dry
		"feed":
			_carrying_feed = false
			state = State.GO_FEED
		"build_farm":
			var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
			_farm_spot = village.find_build_spot(world)
			if _farm_spot == Vector3.INF or not village.store.try_spend_materials(4, 0):
				_farm_spot = Vector3.INF
				state = State.WANDER
				_action_time = 2.0
				return
			state = State.GO_BUILD_FARM
			_maybe_mount()
		"build_edubba":
			var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
			_edubba_spot = village.find_build_spot(world)
			if _edubba_spot == Vector3.INF:
				state = State.WANDER
				_action_time = 2.0
				return
			state = State.GO_BUILD_EDUBBA
			_maybe_mount()
		"hunt":
			_target_animal = _nearest_huntable()
			state = State.GO_HUNT
			_maybe_mount()
		"fish":
			_fish_spot = _find_shore()
			state = State.GO_FISH
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
	_target_bush = null
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
	# The granary is bare: go foraging in the wild like anyone's ancestors.
	_target_bush = _nearest_forage_bush()
	if _target_bush != null:
		state = State.GO_EAT
		return true
	return false


func _process_go_eat(delta: float) -> void:
	if _target_bush != null:
		if not is_instance_valid(_target_bush) or not _target_bush.has_berries():
			_target_bush = null
			_decide()
			return
		if _move_toward(_target_bush.global_position, WALK_SPEED * _speed_factor(), delta):
			if _target_bush.take_berry():
				_dismount()
				state = State.EATING
				_action_time = 2.0
			_target_bush = null
		return
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
			# Keep the food (it may be a bundle) — EATING takes only as much
			# as this belly needs, leaving the rest for the next hungry mouth.
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


## Consume the meal at hand. A ground bundle (_target_food) is eaten a mouthful
## at a time — only as many units as this belly needs, leaving the rest of the
## bundle on the ground for the next hungry villager. Bush berries and store
## meals are already single servings, so they just top up hunger by one unit.
func _eat_meal() -> void:
	if _target_food != null and is_instance_valid(_target_food) \
			and not _target_food.is_queued_for_deletion():
		var need := clampi(int(ceil(hunger / FoodItem.NUTRITION)), 1, maxi(_target_food.count, 1))
		hunger = maxf(hunger - need * FoodItem.NUTRITION, 0.0)
		_target_food.count -= need
		if _target_food.count <= 0:
			_target_food.queue_free()
		else:
			_target_food.refresh_bundle()
	else:
		hunger = maxf(hunger - FoodItem.NUTRITION, 0.0)
	_target_food = null


## Hauling -------------------------------------------------------------------

## Shoulder a gathered load and set off for the storehouse on foot. Nothing is
## banked until they actually arrive (see State.HAULING / _deliver_carry).
func _begin_haul(kind: String, amount: int, origin_job: String) -> void:
	if amount <= 0 or village == null:
		_decide()
		return
	_carry_kind = kind
	_carry_amount = amount
	_carry_job = origin_job
	_make_carry_visual(kind)
	state = State.HAULING


## Bank the carried load into the store and put the load down.
func _deliver_carry() -> void:
	if village != null and is_instance_valid(village.store):
		match _carry_kind:
			"plant": village.store.add(FoodItem.FoodType.PLANT, _carry_amount)
			"meat": village.store.add(FoodItem.FoodType.MEAT, _carry_amount)
			"lumber": village.store.add_lumber(_carry_amount)
			"stone": village.store.add_stone(_carry_amount)
		if _carry_announce != "" and village.is_player_home:
			GameState.announce(_carry_announce)
	_clear_carry()


## Drop whatever is being carried (delivered, or abandoned) and forget it.
func _clear_carry() -> void:
	_carry_kind = ""
	_carry_amount = 0
	_carry_job = ""
	_carry_announce = ""
	if is_instance_valid(_carry_visual):
		_carry_visual.queue_free()
	_carry_visual = null


## A little bundle in the hands so the eye can see WHAT they are carrying.
func _make_carry_visual(kind: String) -> void:
	if is_instance_valid(_carry_visual):
		_carry_visual.queue_free()
	var color := Color(0.87, 0.72, 0.32)  # plant / grain
	match kind:
		"meat": color = Color(0.72, 0.24, 0.2)
		"lumber": color = Color(0.55, 0.4, 0.25)
		"stone": color = Color(0.55, 0.54, 0.56)
	_carry_visual = Util.lite_box(Vector3(0.34, 0.28, 0.34), color, Vector3(0, 0.95, 0.34))
	_visuals.add_child(_carry_visual)


## The job this villager currently occupies, for the village's crowd tally
## (so the flock spreads across needs). "" when idle/at home tasks.
func current_job() -> String:
	match state:
		State.GO_BUILD, State.BUILDING: return "build"
		State.GO_CHOP, State.CHOPPING: return "chop"
		State.GO_QUARRY, State.QUARRYING: return "quarry"
		State.GO_FARM, State.FARMING: return "farm"
		State.GO_FEED: return "feed"
		State.GO_BUILD_FARM, State.BUILDING_FARM: return "build_farm"
		State.GO_BUILD_EDUBBA, State.BUILDING_EDUBBA: return "build_edubba"
		State.GO_HUNT, State.HUNTING: return "hunt"
		State.GO_FISH, State.FISHING: return "fish"
		State.GO_BUTCHER, State.BUTCHERING: return "butcher"
		State.GO_TAME, State.TAMING: return "tame"
		State.HAULING: return _carry_job
	return ""


## The militia -----------------------------------------------------------------

## Draw a weapon from the storehouse (paying its materials). Bare hands if the
## village is too poor — a mob is still a mob.
func _take_up_arms() -> void:
	if weapon != "" or village == null:
		return
	var made := Weapon.forge(village.store)
	if made == "":
		return
	weapon = made
	if is_instance_valid(_weapon_visual):
		_weapon_visual.queue_free()
	_weapon_visual = Weapon.build_visual(weapon)
	_visuals.add_child(_weapon_visual)


## How many of my people are close enough to fight alongside me. Courage —
## and therefore the whole balance of predator attacks — rests on this count.
func _allies_near() -> int:
	if village == null:
		return 0
	var n := 0
	for v in village.my_villagers():
		if v == self or not v.is_adult() or v.state == State.DYING:
			continue
		if v.global_position.distance_to(global_position) < ALLY_RADIUS:
			n += 1
	return n


## Will this villager stand and fight, or run? Alone, they run — and a wolf
## runs them down. Together, they turn and kill it.
func _dares_fight() -> bool:
	if health < RETREAT_HEALTH:
		return false
	var needed := COURAGE_ARMED if weapon != "" else COURAGE_BARE
	return _allies_near() >= needed


## Close with the enemy and strike it on the weapon's cooldown. Breaks off if
## the target dies, if the villager is badly hurt, or if their nerve fails.
func _process_fight(delta: float) -> void:
	if _fight_target == null or not is_instance_valid(_fight_target) \
			or _fight_target.is_queued_for_deletion():
		_fight_target = null
		_decide()
		return
	if health < RETREAT_HEALTH or not _dares_fight():
		# Nerve broken: run, and let the fear spread the alarm further.
		var flee_from := _fight_target.global_position
		_fight_target = null
		scare(flee_from)
		return
	var reach := Weapon.reach(weapon)
	if global_position.distance_to(_fight_target.global_position) > reach:
		_move_toward(_fight_target.global_position, FLEE_SPEED * 0.85, delta, reach * 0.8)
		return
	_apply_gravity_only(delta)
	# Face the enemy while trading blows.
	var to_foe := _fight_target.global_position - global_position
	to_foe.y = 0.0
	if to_foe.length() > 0.05:
		look_at(global_position - to_foe.normalized(), Vector3.UP)
	_attack_cd -= delta
	if _attack_cd > 0.0:
		return
	_attack_cd = Weapon.cooldown(weapon)
	_strike(_fight_target)


## Land a blow (Weapon resolves the damage) and settle up if the foe drops.
func _strike(foe: Node3D) -> void:
	var killed := Weapon.strike(self, foe, weapon)
	if killed and foe is Animal:
		if village != null:
			village.remember_battle(true)   # standing together WORKED
			village.vendetta.erase(foe)
			if village.is_player_home:
				GameState.announce("%s and their neighbours have killed the beast."
					% villager_name)
		_fight_target = null
		happiness = minf(happiness + 12.0, 100.0)
		_decide()
	elif foe is Creature:
		# A mob is a lesson. The creature is left to work out for ITSELF which
		# of its recent deeds brought this on — perhaps eating one of them.
		(foe as Creature).mind.experience("mobbed", -1.4)
		if village != null and village.is_player_home:
			GameState.announce("%s strikes at your creature with %s!"
				% [villager_name, Weapon.label(weapon)])


## Fleeing from the creature TEACHES IT that terror works — the mirror of the
## lesson a mob teaches. Which one it learns depends on what the people do.
func _report_terror(foe: Node3D) -> void:
	if foe is Creature:
		(foe as Creature).mind.experience("feared", 0.8)


## What this villager should be fighting right now, if anything: a marked beast
## or a predator inside the bounds — or the creature itself, once the village
## has taken enough from it.
func _find_foe() -> Node3D:
	if village == null:
		return null
	var beast := village.fight_target(global_position)
	if beast != null:
		return beast
	if village.hates_creature():
		var c := get_tree().get_first_node_in_group("creature") as Creature
		if c != null and c.global_position.distance_to(global_position) < 30.0:
			return c
	return null


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


## A dry spot right at the water's edge, or INF if no shore is in reach.
func _find_shore() -> Vector3:
	var world := _world()
	if world == null:
		return Vector3.INF
	for dist: float in [10.0, 20.0, 35.0, 50.0]:
		for i in 8:
			var angle := TAU * i / 8.0 + randf() * 0.3
			var probe := global_position + Vector3(cos(angle), 0, sin(angle)) * dist
			if world.is_underwater(probe.x, probe.z):
				var shore := global_position + (probe - global_position) * 0.85
				shore.y = world.height_at(shore.x, shore.z)
				return shore
	return Vector3.INF


func _nearest_forage_bush() -> ForageBush:
	var best: ForageBush = null
	var best_dist := INF
	for b in get_tree().get_nodes_in_group("forage"):
		var bush := b as ForageBush
		if not is_instance_valid(bush) or not bush.has_berries():
			continue
		var d := global_position.distance_to(bush.global_position)
		if d < best_dist and d < village.influence_radius * 2.0:
			best_dist = d
			best = bush
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
		if node is WildTree and ((node as WildTree).is_felled() \
				or (node as WildTree).is_held() or (node as WildTree).burning):
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


## Children ------------------------------------------------------------------

## Trail mother: keep within a few paces of her, otherwise scamper close.
func _process_follow_mom(delta: float) -> void:
	if mother == null or not is_instance_valid(mother) or mother.village != village \
			or village.has_edubba():
		_decide()
		return
	var to_mom := mother.global_position - global_position
	to_mom.y = 0
	if to_mom.length() > 2.5:
		_move_toward(mother.global_position, WALK_SPEED * 1.1, delta)
	else:
		_apply_gravity_only(delta)
		_action_time -= delta
		if _action_time <= 0.0:
			_decide()  # re-check needs (hunger, sleep) now and then
	social = minf(social + 2.0 * delta, 100.0)


## At school: play in the Edubba yard near the teacher and the other children.
func _process_at_school(delta: float) -> void:
	if not village.has_edubba() or is_adult():
		_decide()
		return
	var yard := village.edubba.yard_position()
	if global_position.distance_to(yard) > 4.0:
		_move_toward(yard + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)),
			WALK_SPEED * _speed_factor(), delta)
	else:
		_apply_gravity_only(delta)
		social = minf(social + 3.0 * delta, 100.0)
		happiness = minf(happiness + 0.5 * delta, 100.0)
		_action_time -= delta
		if _action_time <= 0.0:
			_decide()  # re-check needs now and then


## Movement ------------------------------------------------------------------

func _move_toward(target: Vector3, speed: float, delta: float, arrive := ARRIVE_DIST) -> bool:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < arrive:
		_apply_gravity_only(delta)
		return true
	var dir := to_target.normalized()
	# Steer around trees and rocks (but not the one we're walking to).
	dir = NavField.steer(global_position, dir, 0.4, target)
	# Villagers cannot swim: route ALONG the shore around open water rather
	# than stepping in. Only a body hemmed in by water on every side stalls
	# (and the stuck watchdog re-decides them).
	dir = NavField.water_route(self, global_position, dir, _world())
	if dir == Vector3.ZERO:
		_apply_gravity_only(delta)
		return false
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


func _world() -> WorldGen:
	if _world_cache == null or not is_instance_valid(_world_cache):
		_world_cache = get_tree().get_first_node_in_group("world_gen") as WorldGen
	return _world_cache


## Harm, fear, death ---------------------------------------------------------

## Hazards: fire & drowning ---------------------------------------------------

## Fire and deep water drain health every frame; either brings on the DYING
## state at zero rather than instant death, leaving a window for rescue.
func _tick_hazards(delta: float) -> void:
	if state == State.HELD or state == State.FALLING:
		return
	var world := _world()
	if world != null:
		var depth := WorldGen.WATER_LEVEL - world.height_at(global_position.x, global_position.z)
		if depth > DROWN_DEPTH and global_position.y < WorldGen.WATER_LEVEL + 0.4:
			if burning:
				extinguish()  # water douses the flames, but the drowning goes on
			health -= HAZARD_RATE * delta
			if health <= 0.0:
				enter_dying()
				return
	if burning:
		health -= HAZARD_RATE * delta
		_flicker_flame()
		if health <= 0.0:
			enter_dying()


## The 10-second twilight: prone and helpless, waiting for a healing miracle
## or a merciful hand/creature — or the end.
func _process_dying(delta: float) -> void:
	_apply_gravity_only(delta)
	if _animator != null:
		_animator.play("dying")
	elif _visuals != null:
		_visuals.rotation_degrees.x = 88.0  # fallen prone
	if burning:
		_flicker_flame()
	_dying_time -= delta
	if _dying_time <= 0.0:
		die(false)


func enter_dying() -> void:
	if state == State.DYING:
		return
	_dismount()
	state = State.DYING
	_dying_time = DYING_SECONDS
	health = 0.0
	velocity = Vector3.ZERO
	if village != null and village.is_player_home:
		GameState.announce("%s is dying! A heal — or a merciful hand — could still save them."
			% villager_name)


## Back from the brink at a sliver of life. From heal miracles and from a
## kindly hand/creature lifting them up.
func rescue() -> void:
	extinguish()
	health = maxf(health, REVIVE_HEALTH)
	if state == State.DYING:
		state = State.WANDER
		_dying_time = 0.0
		if _animator == null and _visuals != null:
			_visuals.rotation = Vector3.ZERO
		happiness = maxf(happiness, 30.0)
		if village != null and village.is_player_home:
			GameState.announce("%s was pulled back from death's door." % villager_name)
		_decide()


func is_dying() -> bool:
	return state == State.DYING


func ignite() -> void:
	if burning or state == State.HELD or state == State.DYING:
		return
	var world := _world()
	if world != null and world.is_underwater(global_position.x, global_position.z):
		return  # can't catch fire soaking wet
	burning = true
	_burn_visual = Util.small_flame(1.4)
	_visuals.add_child(_burn_visual)


func extinguish() -> void:
	burning = false
	if is_instance_valid(_burn_visual):
		_burn_visual.queue_free()
	_burn_visual = null


func _flicker_flame() -> void:
	if is_instance_valid(_burn_visual):
		_burn_visual.scale.y = 1.0 + sin(Time.get_ticks_msec() / 60.0) * 0.2


## Struck by a beast (or your creature). Remembers WHO, rouses the village, and
## then takes the wound. This is what turns a lone killing into a manhunt.
func hurt_by(foe: Node3D, amount: float) -> void:
	_last_attacker = foe
	if village != null:
		village.raise_alarm(
			foe.global_position if is_instance_valid(foe) else global_position,
			foe is Creature)
	take_damage(amount)


func take_damage(amount: float, by_god := false, instant := false) -> void:
	if state == State.DYING:
		return
	health -= amount
	happiness = maxf(happiness - 10.0, 0.0)
	if health <= 0.0:
		if by_god:
			village.change_belief(3.0)
		if instant:
			die(false)
		else:
			enter_dying()


func die(of_old_age: bool) -> void:
	_dismount()
	# Killed by a beast? The whole village swears a blood debt against THAT
	# animal and will hunt it down wherever it runs.
	if not of_old_age and village != null and _last_attacker is Animal \
			and is_instance_valid(_last_attacker):
		village.mark_for_death(_last_attacker as Animal)
	# Dying while the village was up in arms teaches them the cost of standing.
	if not of_old_age and village != null and village.is_roused():
		village.remember_battle(false)
	# The creature learns cruelty from the deaths it witnesses its god allow —
	# a violent end nearby drags its heart toward the dark. (Old age teaches
	# nothing; the creature is only reading its god's hand in the world.)
	if not of_old_age:
		var creature := get_tree().get_first_node_in_group("creature") as Creature
		if creature != null and creature.global_position.distance_to(global_position) < 40.0:
			creature.witness(-2.0)
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


## Aftertouch hooks: bend a thrown villager's arc, and set their tumble axis.
func in_flight_push(dv: Vector3) -> void:
	if state == State.FALLING:
		velocity += dv


func set_flight_spin(angular: Vector3) -> void:
	_spin_ang = angular


func _land() -> void:
	_spin_ang = Vector3.ZERO
	_visuals.rotation = Vector3.ZERO
	if _gentle_drop:
		_gentle_drop = false
		velocity = Vector3.ZERO
		_on_placed_gently()
		return
	if _fall_speed > 14.0:
		take_damage((_fall_speed - 14.0) * 5.0, true)
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	if state == State.DYING:
		return  # a killing toss — they lie dying, don't snap into a flee
	scare(global_position + Vector3(randf() - 0.5, 0, randf() - 0.5))
	GameState.announce("%s survived a divine toss. Mostly." % villager_name)


## Set down by a careful god. If this is another village's ground, that
## was no accident: the faithful defect TO belief, and believers carry
## the word INTO the heathen dark.
func _on_placed_gently() -> void:
	var host := _village_here()
	if host == null or host == village:
		_decide()
		return
	if host.converted:
		_defect_to(host)
	elif village.converted:
		_mission_village = host
		state = State.GO_PREACH
		GameState.announce("%s carries the word of the heavens into %s."
			% [villager_name, host.village_name])
	else:
		_decide()  # two heathen villages; they will simply walk home


func _village_here() -> Village:
	var best: Village = null
	var best_dist := INF
	for v in get_tree().get_nodes_in_group("village"):
		var candidate := v as Village
		if not is_instance_valid(candidate):
			continue
		var flat := candidate.global_position - global_position
		flat.y = 0
		var d := flat.length()
		if d < maxf(candidate.influence_radius * 1.2, 18.0) and d < best_dist:
			best_dist = d
			best = candidate
	return best


func _defect_to(host: Village) -> void:
	var old_name := village.village_name
	_dismount()
	home = null
	village = host
	host.adopt(self)
	if host.is_player_home or host.converted:
		GameState.announce("%s of %s now calls %s home."
			% [villager_name, old_name, host.village_name])
	_decide()


func scare(from_pos: Vector3) -> void:
	if state == State.HELD or state == State.DYING:
		return
	_dismount()
	state = State.FLEE
	_flee_from = from_pos
	_action_time = 4.0
	happiness = maxf(happiness - 10.0, 0.0)
	_pitch_body(0.0)


func witness_horror(weight: float) -> void:
	morality = clampf(morality - weight, -100.0, 100.0)


func receive_heal() -> void:
	extinguish()
	if state == State.DYING:
		rescue()  # healed from the brink -> back at a sliver of life
		return
	health = 100.0
	energy = minf(energy + 40.0, 100.0)
	happiness = minf(happiness + 15.0, 100.0)


func is_worshipping() -> bool:
	return state == State.WORSHIPPING


func is_afraid() -> bool:
	return state in [State.FLEE, State.HIDE]


## Something enormous is standing there being peaceful. The villager stops what
## they are doing, turns, and looks at it — the ordinary human reaction to an
## awesome thing that is not, right now, hurting anybody. Being ATTENDED to is
## what the creature's quieter deeds are actually for.
func attend(point: Vector3) -> void:
	if is_afraid() or state in [State.HELD, State.FALLING, State.DYING, State.FIGHT]:
		return
	var flat := point - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		rotation.y = atan2(flat.x, flat.z)
	happiness = minf(happiness + 0.5, 100.0)


## Divine hand interface -----------------------------------------------------

func pick_up() -> void:
	_dismount()
	state = State.HELD
	_pitch_body(0.0)
	velocity = Vector3.ZERO


## A still hand sets a villager down gently (no fear, no harm — and where
## you set them down MATTERS); a moving hand throws them, with all that
## implies for their body and your soul.
func drop(throw_velocity: Vector3, gentle := false) -> void:
	state = State.FALLING
	velocity = throw_velocity
	_gentle_drop = gentle
	if not gentle and throw_velocity.length() > 10.0:
		GameState.shift_alignment(-1.0)


## Descriptions --------------------------------------------------------------

func hover_text() -> String:
	var stage: String
	if age < ADULT_AGE:
		stage = "girl" if is_female else "boy"
	elif age >= ELDER_AGE:
		stage = "elder"
	else:
		stage = "woman" if is_female else "man"
	var extra := ", pregnant" if pregnant else ""
	if weapon != "":
		extra += ", armed with %s" % Weapon.label(weapon)
	if home == null:
		extra += ", HOMELESS"
	return "%s of %s — %s %s, age %d%s — %s\n(health %d · hunger %d · energy %d · happy %d · %s)" % [
		villager_name, village.village_name, _morality_word(), stage, int(age), extra,
		_status_word(), int(health), int(hunger), int(energy), int(happiness),
		"she" if is_female else "he"]


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
		State.GO_PREACH, State.PREACHING: return "on a mission"
		State.GO_FEED: return "feeding the animals"
		State.GO_BUILD_FARM, State.BUILDING_FARM: return "breaking new ground"
		State.GO_BUILD_EDUBBA, State.BUILDING_EDUBBA: return "raising the Edubba"
		State.GO_FISH, State.FISHING: return "fishing"
		State.HAULING: return "hauling to the storehouse"
		State.GO_ARM: return "running for a weapon"
		State.FIGHT: return "FIGHTING for their life"
		State.COURT: return "courting at the totem"
		State.FOLLOW_MOM: return "following mother"
		State.AT_SCHOOL: return "at school"
		State.TEACH: return "teaching the children"
		State.FLEE: return "fleeing in terror"
		State.HELD: return "in the grip of a god"
		State.FALLING: return "airborne"
	return "?"


func _status_text() -> String:
	match state:
		State.DYING: return "SAVE ME!"
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
		State.PREACHING: return "hear me!"
		State.FISHING: return "fish?"
		State.HAULING: return "haul"
		State.GO_ARM: return "arms!"
		State.FIGHT: return "FIGHT!"
		State.COURT: return "♥"
		State.FOLLOW_MOM: return "mama"
		State.AT_SCHOOL: return "abc"
		State.TEACH: return "teach"
		State.BUILDING_EDUBBA, State.GO_BUILD_EDUBBA: return "build"
		State.PLAY: return "wheee"
		State.FLEE, State.FALLING: return "!!!"
		State.HELD: return "?!"
	if pregnant:
		return "+"
	return ""
