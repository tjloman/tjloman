class_name Animal
extends CharacterBody3D
## Every beast in the world, driven by one data table. Livestock can be
## tamed (by the good), penned (by anyone), eaten (by policy), and thrown
## (by you). Predators hunt prey — and sometimes people.
##
## Add a species by adding a SPECIES row. That's the whole job.

enum State {
	IDLE, WANDER, FLEE, CHASE, MAUL, HELD, FALLING, GO_DRINK, DRINKING, GO_FORAGE, GRAZE,
}

const GRAVITY := 20.0

## How much of itself a beast will spend on a kill before it bolts. Above this
## it keeps its grip through anything; below, it is off the body and running.
## This single number is what a spear is WORTH: one thrust takes a wolf under
## it, four bare-handed blows do the same, and either way somebody gets up.
const MAUL_NERVE := 0.55

## What the butcher calls it. Anything not listed is just "<species> meat".
const MEAT_NAMES := {
	"sheep": "mutton", "pig": "pork", "chicken": "chicken", "deer": "venison",
	"ox": "beef", "giraffe": "giraffe steak", "llama": "llama chop",
	"bear": "bear flank", "wolf": "wolf flesh", "lion": "lion flesh",
	"tiger": "tiger flesh", "caribou": "caribou haunch",
	"reindeer": "reindeer haunch", "bison": "bison chuck", "elk": "elk loin",
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
	# THE GREAT HERD. Caribou gather in numbers nothing else here comes near —
	# see Herd.SOCIAL, where they roll 2d100 — which is exactly why the herd had
	# to stop being a pile of separate beasts before any of these could be added.
	#
	# CARIBOU AND REINDEER ARE THE SAME ANIMAL AND THAT IS THE POINT. Caribou is
	# the wild one: it runs in the great tundra herds and it is skittish. Tame a
	# caribou and what you have is a reindeer — steadier, heavier, a pack beast,
	# and no longer part of anything wild. The only difference between them is
	# whose they are, which is the whole of what domestication is.
	"caribou": {"body": Vector3(0.55, 0.75, 1.4), "leg": 0.75, "color": Color(0.58, 0.52, 0.44),
		"speed": 5.4, "meat": 3, "skittish": true, "neck": 0.3,
		"tame": true, "tames_into": "reindeer"},
	"reindeer": {"body": Vector3(0.6, 0.78, 1.45), "leg": 0.75, "color": Color(0.72, 0.66, 0.56),
		"speed": 4.4, "meat": 3, "tame": true, "pack": true, "neck": 0.3},
	"bison": {"body": Vector3(1.0, 1.1, 2.1), "leg": 0.65, "color": Color(0.32, 0.24, 0.2),
		"speed": 4.5, "meat": 6},
	"elk": {"body": Vector3(0.7, 0.95, 1.7), "leg": 0.95, "color": Color(0.5, 0.38, 0.26),
		"speed": 5.2, "meat": 4, "skittish": true, "neck": 0.5},
	"anteater": {"body": Vector3(0.35, 0.4, 1.0), "leg": 0.22, "color": Color(0.4, 0.35, 0.34),
		"speed": 1.8, "meat": 1},
	"coati": {"body": Vector3(0.25, 0.28, 0.65), "leg": 0.2, "color": Color(0.55, 0.4, 0.28),
		"speed": 3.4, "meat": 1, "skittish": true},
}

## HOW LONG A BURNING BEAST LASTS, and how often it changes its mind about which
## way to run while it does. Eight seconds is long enough that setting an animal
## alight is something you watch happen rather than something that resolves
## before you have looked up — which is the point of it being cruel.
const BURN_SECONDS := 8.0
const BURN_PANIC := 0.7
## How far a beast that is alight frightens everything else. It is a fire that
## moves, and it is treated as one.
const BURN_TERROR := 9.0

var species := "sheep"
var spec: Dictionary
var health := 30.0
var burning := false           # ablaze: drains health until doused or dead
var tamed_by: Village = null
var night_spawned := false     # wolves of the wolf-raid despawn at dawn

## An animal's real needs: it must drink and eat, and it grows old.
## Wild herds breed when fed and watered — and die, way out in the woods.
var hunger := randf_range(0.0, 40.0)
var thirst := randf_range(0.0, 40.0)
var age_seconds := 0.0
var lifespan_seconds := randf_range(12.0, 28.0) * GameState.DAY_SECONDS

## WHO THIS ONE HAS ON THE GROUND. Non-null only while it is holding a villager
## down, which is now the only way a predator ever kills a person — see Mauling.
var pinning: Villager = null
var state := State.IDLE
var _target := Vector3.ZERO
var _prey: Node3D = null
var _water_target := Vector3.INF
var _bush: ForageBush = null
var _action_time := 2.0
var _sim_last := 0   # see Scheduler
## Ground one throttled step must cover to match real time (see Villager).
var _sim_scale := 1.0
var _state_time := 0.0
var _prev_state := State.IDLE
var _think_time := 0.0
var _flee_from := Vector3.ZERO
var _world_cache: WorldGen = null
var _fall_speed := 0.0
var _gentle_drop := false
var _spin_ang := Vector3.ZERO   # aftertouch spin axis*rate while thrown (rad/s)
var _animator: ModelAnimator = null   # non-null only for a rigged custom model
## A thought is due and not yet granted — see the spool gate in _physics_process.
var _think_due := false
var _burn_visual: Node3D = null
var _full_health := 30.0
var _burn_rate := 0.0
var _panic_left := 0.0
var _rider: Node3D = null


static func create(species_name: String) -> Animal:
	var a := Animal.new()
	a.species = species_name
	return a


func _ready() -> void:
	spec = SPECIES[species]
	health = 20.0 + spec["body"].length() * 15.0
	_full_health = health
	add_to_group("animals")
	add_to_group("pickable")
	collision_layer = 2
	collision_mask = 1 | 8  # world + trees (their own layer)

	var body: Vector3 = spec["body"]
	var leg_h: float = spec["leg"]
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(body.x, body.y + leg_h, body.z)
	col.shape = shape
	col.position = Vector3(0, (body.y + leg_h) * 0.5, 0)
	add_child(col)
	# A custom per-species model (e.g. sheep.glb) replaces the box-beast; if
	# it's rigged, an animator plays its clips.
	var custom := ModelBank.instantiate(species)
	if custom != null:
		add_child(custom)
		_animator = ModelAnimator.create(custom)
		Util.apply_lod(self, Quality.actor_distance())
	else:
		_build_body(body, leg_h)


func _build_body(body: Vector3, leg_h: float) -> void:
	# Pooled parts: every beast of a species draws from the same handful of
	# meshes and shared materials (all its colours are fixed per species), so
	# a herd batches instead of minting a unique mesh+material per limb.
	var color: Color = spec["color"]
	add_child(Util.lite_box(body, color, Vector3(0, leg_h + body.y * 0.5, 0)))
	# Legs.
	if leg_h > 0.1:
		for corner in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
			var offset := Vector3(corner.x * body.x * 0.35, leg_h * 0.5, corner.z * body.z * 0.35)
			add_child(Util.lite_box(Vector3(0.12, leg_h, 0.12), color.darkened(0.25), offset))
	# Head (on a neck, for the tall ones).
	var neck_h: float = spec.get("neck", 0.0)
	var head_y := leg_h + body.y + neck_h
	if neck_h > 0.0:
		add_child(Util.lite_box(Vector3(0.25, neck_h, 0.25), color,
			Vector3(0, leg_h + body.y + neck_h * 0.5 - 0.1, body.z * 0.35)))
	var head_r: float = clampf(body.y * 0.4, 0.08, 0.35)
	add_child(Util.lite_sphere(head_r, color.darkened(0.15),
		Vector3(0, head_y, body.z * 0.5 + head_r * 0.5)))
	# Distant beasts stop drawing (they already freeze physics far off).
	Util.apply_lod(self, Quality.actor_distance())


func _physics_process(delta: float) -> void:
	# Life goes on even beyond the camera: aging, appetite, and quiet
	# deaths of old age happen way out in the woods.
	if state != State.HELD:
		age_seconds += delta
		hunger = minf(hunger + 0.35 * delta, 100.0)
		thirst = minf(thirst + 0.3 * delta, 100.0)
		if age_seconds > lifespan_seconds:
			die(false)  # returns to the earth, no butcher involved
			return

	# Simulation LOD: a beast the player isn't looking at runs on a slower
	# clock — still alive and wandering, just updated every few frames with the
	# skipped time folded into delta. (Held/falling always simulate full-rate.)
	if state != State.HELD and state != State.FALLING:
		var stride := Util.sim_stride(global_position)
		_sim_scale = 1.0
		if stride > 1:
			var turn: int = Scheduler.turn(self, stride, _sim_last)
			if turn == 0:
				return
			delta *= float(turn)
			# See Villager: move_and_slide() runs on the engine's frame, so a
			# throttled beast crawls unless the stride is folded into velocity.
			_sim_scale = float(turn)
	# THE CLOCK IS STAMPED WHENEVER IT ACTUALLY RUNS, not only on the frames it
	# runs coarsely. This line used to live inside the `stride > 1` branch, so a
	# beast standing near the camera — stride 1, branch skipped — went on
	# not writing it for as long as it stayed there. `_sim_last` then meant "the
	# frame it was last FAR AWAY", and the moment anything nudged the stride
	# above 1 (the camera panning off, or the heat band moving, which a casting
	# session did all by itself) Scheduler.turn handed back every frame since,
	# multiplied it into delta AND into the velocity scale, and threw it across
	# the field. See Scheduler.MOST_OWED.
	_sim_last = Scheduler.now()

	if _animator != null:
		_animator.play(_anim_state())

	_tick_hazards(delta)

	# Watchdogs: no chase or trek lasts forever, and nothing falls out of
	# the world when its chunk streams away.
	if state != _prev_state:
		_prev_state = state
		_state_time = 0.0
	_state_time += delta
	if _state_time > 25.0 and state in [State.WANDER, State.CHASE, State.GO_DRINK, State.GO_FORAGE]:
		_state_time = 0.0
		_prey = null
		_water_target = Vector3.INF
		state = State.IDLE
		_action_time = 2.0
	if global_position.y < -12.0:
		var world := _world()
		if world != null:
			global_position.y = world.height_at(global_position.x, global_position.z) + 0.5
			velocity = Vector3.ZERO
			if state == State.FALLING:
				state = State.IDLE

	match state:
		State.HELD:
			velocity = Vector3.ZERO
			return
		State.FALLING:
			_fall_speed = velocity.length()
			velocity.y -= Sling.gravity_for(self, GRAVITY) * delta   # see Sling
			move_and_slide()
			if _spin_ang.length() > 0.001:  # aftertouch tumble about a 3D axis
				global_rotate(_spin_ang.normalized(), _spin_ang.length() * delta)
			if is_on_floor():
				_spin_ang = Vector3.ZERO
				rotation = Vector3.ZERO
				if _gentle_drop:
					_gentle_drop = false
					state = State.IDLE
					_action_time = 2.0
					velocity = Vector3.ZERO
					_maybe_pen_tame()
					return
				# THE TOWN SAW AN OX COME DOWN IN THE SQUARE. Judged before the
				# fall damage, so a beast that bursts on landing still counts
				# as the thing everybody watched arrive — see VillageWonder.
				VillageWonder.landed(get_tree(), species, global_position,
					_fall_speed, burning)
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
		State.MAUL:
			# STANDING ON SOMEBODY. It does not move, it does not re-target, and
			# it does not look around: for the next half minute this animal is a
			# stationary thing in the middle of a village, which is exactly what
			# gives the village its shot. The clock is the Mauling's.
			_apply_gravity_only(delta)
			if pinning == null or not is_instance_valid(pinning) or pinning.pin == null:
				release_hold()
			else:
				var over := pinning.global_position - global_position
				over.y = 0.0
				if over.length() > 1.2:
					_move_toward(pinning.global_position, spec["speed"], delta)
				elif over.length() > 0.05:
					rotation.y = atan2(over.x, over.z)
		State.GO_DRINK:
			if _water_target == Vector3.INF:
				state = State.IDLE
			elif _move_toward(_water_target, spec["speed"] * 0.8, delta):
				state = State.DRINKING
				_action_time = 3.0
		State.DRINKING:
			_apply_gravity_only(delta)
			_action_time -= delta
			if _action_time <= 0.0:
				thirst = 0.0
				_water_target = Vector3.INF
				state = State.IDLE
				_action_time = 2.0
		State.GO_FORAGE:
			if _bush == null or not is_instance_valid(_bush) or not _bush.has_berries():
				_bush = null
				state = State.IDLE
			elif _move_toward(_bush.global_position, spec["speed"] * 0.8, delta):
				if _bush.take_berry():
					hunger = maxf(hunger - 55.0, 0.0)
				_bush = null
				state = State.GRAZE
				_action_time = 2.0
		State.GRAZE:
			_apply_gravity_only(delta)
			_action_time -= delta
			if _action_time <= 0.0:
				hunger = maxf(hunger - 30.0, 0.0)  # grass is always there
				state = State.IDLE
				_action_time = randf_range(2.0, 5.0)

	_think_time -= delta
	if _think_time <= 0.0:
		_think_time = randf_range(0.7, 1.3)
		_think_due = true
	# ...AND THE SPOOL SAYS WHEN. The clock says a beast is due a thought; the
	# queue says whether the frame can afford one. Refused, it goes on grazing
	# or walking exactly as it was and asks again next frame. See Spool.
	if _think_due and Spool.turn_to_think(self):
		_think_due = false
		_think()

	# Ridden animals glue themselves under their rider.
	if _rider != null:
		if is_instance_valid(_rider):
			global_position = _rider.global_position + Vector3(0, -0.4, 0)
		else:
			_rider = null

	_ambient_sound(delta)


## Slow thinking: needs first (drink, eat), then predator targeting,
## guard-dog work, breeding, night despawn.
func _think() -> void:
	# MAUL is on this list for the same reason HELD is: the animal is not
	# choosing anything right now. Nothing it thirsts for, hungers for or is
	# frightened of takes it off a body — only the Mauling ending does.
	if state in [State.HELD, State.FALLING, State.FLEE, State.MAUL,
			State.DRINKING, State.GO_DRINK, State.GO_FORAGE, State.GRAZE]:
		return
	if night_spawned and not GameState.is_night():
		queue_free()  # wolves of the raid melt away at dawn
		return

	# Buried waist-deep in a hillside (bad spawn, collision hiccup)? Pop up.
	var world := _world()
	if world != null:
		var h := world.height_at(global_position.x, global_position.z)
		if global_position.y < h - 1.0:
			global_position.y = h + 0.4
			velocity = Vector3.ZERO

	# Thirst: tamed animals drink at the village well, wild ones seek water.
	if thirst > 65.0 and state != State.CHASE:
		if tamed_by != null:
			_water_target = tamed_by.well_position()
			state = State.GO_DRINK
			return
		_water_target = _find_water(world)
		if _water_target != Vector3.INF:
			state = State.GO_DRINK
			return

	# Hunger: predators hunt (below); herbivores browse bushes or graze.
	# Tamed animals graze lightly and wait to be fed at the pen.
	if hunger > 65.0 and not spec.get("predator", false):
		_bush = _find_forage_bush()
		if _bush != null and tamed_by == null:
			state = State.GO_FORAGE
			return
		state = State.GRAZE
		_action_time = 3.0
		return

	if spec.get("predator", false) and hunger > 55.0 and state != State.CHASE:
		_prey = _find_prey()
		if _prey != null:
			state = State.CHASE
			return

	_maybe_breed()

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
		var worth: float = (_prey as Animal).spec.get("meat", 1)
		(_prey as Animal).take_damage(25.0)
		if not is_instance_valid(_prey) or _prey.is_queued_for_deletion():
			hunger = maxf(hunger - 70.0, 0.0)
			# THE PACK EATS, not just the wolf. A kill banks toward the hunting
			# herd's own next head, so wolves living beside fat cattle become
			# more wolves — which is what makes a herd worth defending and a
			# predator worth driving off. The victim's herd learns of it by its
			# own bookkeeping; see Herd._tend_agents.
			var pack = get_meta("herd", null)
			if pack != null and is_instance_valid(pack):
				(pack as Herd).fed_on(worth)
			_prey = null
			state = State.IDLE
	elif _prey is Villager:
		# IT DOES NOT BITE AND WALK AWAY. A wolf used to take twenty health out
		# of somebody and go looking for the next one, so five wolves killed
		# five people in the time it takes to cross a field and no village could
		# answer that. It pulls them DOWN and holds them, which takes half a
		# minute of standing perfectly still in somebody else's village. See
		# Mauling — the whole balance of predators now lives there.
		var quarry := _prey as Villager
		_prey = null
		quarry.hurt_by(self, 8.0)   # the wound that takes them off their feet
		if is_instance_valid(quarry) and not quarry.is_dying():
			Mauling.seize(quarry, self)
		if pinning == null:
			state = State.IDLE
	elif _prey.has_method("take_damage"):
		_prey.call("take_damage", 20.0, false)
		_prey.call("scare", global_position)
		hunger = maxf(hunger - 45.0, 0.0)
		_prey = null
		state = State.IDLE


## Probes rings of points for open water; returns the near shore, or INF.
func _find_water(world: WorldGen) -> Vector3:
	if world == null:
		return Vector3.INF
	for dist: float in [12.0, 24.0, 40.0, 60.0]:
		for i in 8:
			var angle := TAU * i / 8.0 + randf() * 0.3
			var probe := global_position + Vector3(cos(angle), 0, sin(angle)) * dist
			if world.is_underwater(probe.x, probe.z):
				# Stop at the water's edge, not in the drink.
				return global_position + (probe - global_position) * 0.85
	return Vector3.INF


func _find_forage_bush() -> ForageBush:
	var best: ForageBush = null
	var best_dist := 35.0
	for b in get_tree().get_nodes_in_group("forage"):
		var bush := b as ForageBush
		if not is_instance_valid(bush) or not bush.has_berries():
			continue
		var d := global_position.distance_to(bush.global_position)
		if d < best_dist:
			best_dist = d
			best = bush
	return best


## Wild herds grow: a fed, watered adult near its own kind may calve —
## unless the ground is already crowded with them.
func _maybe_breed() -> void:
	if tamed_by != null or night_spawned or spec.get("predator", false):
		return
	if hunger > 40.0 or thirst > 50.0 or age_seconds < lifespan_seconds * 0.2:
		return
	if randf() > 0.012:  # per think-tick (~1s): a calf every few minutes of comfort
		return
	var kin := 0
	for a in get_tree().get_nodes_in_group("animals"):
		var other := a as Animal
		if other != self and is_instance_valid(other) and other.species == species \
				and other.global_position.distance_to(global_position) < 30.0:
			kin += 1
	if kin < 1 or kin >= 4:
		return  # needs a mate nearby; stops when the meadow is full
	var calf := Animal.create(species)
	var parent := get_parent() as Node3D
	calf.position = parent.to_local(global_position
		+ Vector3(randf_range(-2, 2), 0.3, randf_range(-2, 2)))
	parent.add_child(calf)


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
	# Steer around trees and rocks on the way (but not the target).
	dir = NavField.steer(global_position, dir, 0.4, target)
	# Beasts don't swim: route along the shore around water (frogs excepted —
	# they belong to both worlds).
	if not spec.get("hops", false):
		# ...and the probe reaches as far as THIS STEP will actually carry it. The
		# probe was a fixed 1.7m while velocity is scaled by `_sim_scale`, so a body
		# on a coarse clock covers several metres in one physics step and can step
		# clean over the only warning it gets. Three frames of its real travel.
		dir = NavField.water_route(self, global_position, dir, _world(),
			maxf(1.7, speed * _sim_scale * 0.05))
		if dir == Vector3.ZERO:
			_apply_gravity_only(delta)
			return false
	velocity.x = dir.x * speed * _sim_scale
	velocity.z = dir.z * speed * _sim_scale
	velocity.y -= GRAVITY * delta
	move_and_slide()
	_stick_to_ground()
	# Heads are modeled at +Z; look_at aims -Z. Look away from travel to face it.
	look_at(global_position - Vector3(dir.x, 0, dir.z), Vector3.UP)
	return false


func _apply_gravity_only(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	velocity.y -= GRAVITY * delta
	move_and_slide()
	_stick_to_ground()


## Glue to the analytic terrain surface (which exists even where the collision
## chunk hasn't streamed in) so far-off or just-warped-to beasts never fall
## through unloaded ground. Skipped while held or in flight.
func _stick_to_ground() -> void:
	if state == State.HELD or state == State.FALLING:
		return
	var world := _world()
	if world == null:
		return
	var h := world.height_at(global_position.x, global_position.z)
	if global_position.y < h - 0.3:
		global_position.y = h
		if velocity.y < 0.0:
			velocity.y = 0.0


func _ambient_sound(delta: float) -> void:
	var sound: String = spec.get("sound", "")
	if sound == "" or state == State.HELD:
		return
	# sound_chance is per-second probability: a sheep baas every ~20s,
	# not twice a second. (The old x10 here made the world a wall of noise.)
	if randf() < spec.get("sound_chance", 0.0) * delta:
		SoundBank.play_at(sound, global_position, -6.0)


## Interactions ---------------------------------------------------------------

## Hazards: beasts drown in deep water and burn — both drain 10 health/sec
## (100 -> 0 in ten seconds) and, unlike villagers, simply kill.
func _tick_hazards(delta: float) -> void:
	if state == State.HELD or state == State.FALLING:
		return
	var world := _world()
	if world != null:
		# Against whatever water is ACTUALLY here, the same as the villagers:
		# the sea, or a pond standing in a flooded crater — and NOT a dry pit
		# dug below sea level, which the sea's bare constant called deep water.
		var surface := world.water_level_at(global_position.x, global_position.z)
		var depth := surface - world.height_at(global_position.x, global_position.z)
		if depth > 1.0 and global_position.y < surface + 0.4:
			if burning:
				extinguish()
			health -= 10.0 * delta
			if health <= 0.0:
				die()
				return
	if burning:
		health -= _burn_rate * delta
		if is_instance_valid(_burn_visual):
			_burn_visual.scale.y = 1.0 + sin(Time.get_ticks_msec() / 60.0) * 0.2
		# TORTURED SCURRYING. A beast on fire does not flee a THING — there is
		# nothing to get away from — so it bolts, and then bolts somewhere else,
		# and keeps doing it until it goes down. It overrides a hunt: a wolf
		# that is alight has stopped being interested in dinner.
		_panic_left -= delta
		if _panic_left <= 0.0:
			_panic_left = BURN_PANIC
			if state != State.HELD:
				var a := randf() * TAU
				state = State.FLEE
				_flee_from = global_position - Vector3(cos(a), 0.0, sin(a)) * 9.0
				_action_time = BURN_PANIC * 2.0
			_terrify_nearby()
		if health <= 0.0:
			die()


func ignite() -> void:
	if burning or state == State.HELD:
		return
	var world := _world()
	if world != null and world.is_underwater(global_position.x, global_position.z):
		return
	burning = true
	# BURNING IS A CLOCK, not a damage rate. It used to take ten health a
	# second, and health is sized off the body — so a chicken burned out in
	# under three seconds and an ox took over five, which made how long an
	# animal suffered an accident of its measurements. It is eight seconds for
	# everything now, from full health; a beast already hurt goes sooner, which
	# is the one variation worth keeping.
	_burn_rate = _full_health / BURN_SECONDS
	_panic_left = 0.0
	var body: Vector3 = spec["body"]
	_burn_visual = Util.small_flame(body.y + spec["leg"])
	add_child(_burn_visual)


## A BURNING BEAST IS ITSELF A FIRE, and everything near it goes. This is what
## makes one lit animal running into a herd a disaster rather than a curiosity:
## it panics the mass it runs through, which then runs, which is the whole
## reason setting one animal alight in the middle of a herd is a cruel thing to
## do rather than a small one. Only on the panic tick, so the cost is bounded
## by how many things are actually alight.
func _terrify_nearby() -> void:
	for a in get_tree().get_nodes_in_group("animals"):
		var other := a as Animal
		if other == self or not is_instance_valid(other) or other.burning:
			continue
		if other.global_position.distance_to(global_position) < BURN_TERROR:
			other.scare(global_position)
	for h in get_tree().get_nodes_in_group("herds"):
		var herd := h as Herd
		if is_instance_valid(herd):
			herd.bolt_from(global_position, BURN_TERROR)


func extinguish() -> void:
	burning = false
	if is_instance_valid(_burn_visual):
		_burn_visual.queue_free()
	_burn_visual = null


func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		die()
		return
	if state == State.MAUL:
		if health / maxf(_full_health, 1.0) > MAUL_NERVE:
			return   # it has its teeth in something and it is not letting go
		# DRIVEN OFF THE BODY — which is the whole of what the militia is for.
		Mauling.free_of(self)
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
	# A BEAST ON A KILL IS NOT SHOOED OFF IT. MAUL is on this list with CHASE
	# and for a stronger reason: if a shout were enough, one bare-handed child
	# could poke a whole pack off a body, and the thirty seconds would never
	# cost the village anything to win. It lets go when it is HURT enough —
	# see take_damage — or when it is dead.
	if state in [State.HELD, State.CHASE, State.MAUL]:
		return
	state = State.FLEE
	_flee_from = from_pos
	_action_time = 3.0
	if spec.get("skittish", false):
		_action_time = 5.0


## THE OPPOSITE OF scare(), and nothing had one. Fright only ever ran out on
## its own clock, so a miracle of peace had no door to say "stop" through.
func calm() -> void:
	if state == State.FLEE:
		state = State.IDLE
		_action_time = randf_range(1.0, 3.0)
		_flee_from = Vector3.INF


## Set down gently inside a kind village's pen? That IS a taming: the
## herders take in what the god delivers.
func _maybe_pen_tame() -> void:
	if not is_tamable():
		return
	for v in get_tree().get_nodes_in_group("village"):
		var village := v as Village
		if not is_instance_valid(village):
			continue
		if village.pen_position().distance_to(global_position) < 9.0 \
				and village.average_morality() > 20.0:
			tame(village)
			if village.is_player_home:
				GameState.announce("The %s settles into %s's pen, delivered by the hand."
					% [species, village.village_name])
			return


## TAMED. For most beasts that is only a change of owner; for a caribou it is a
## change of KIND. A wild thing that has been gentled and brought home is not the
## same animal any more, and the table says so rather than any code here —
## `tames_into` is a species row, so making some other creature domesticable into
## something else later is a one-line edit.
func tame(by: Village) -> void:
	var becomes: String = spec.get("tames_into", "")
	if becomes != "" and Animal.SPECIES.has(becomes):
		var kept := global_position
		var made := Animal.create(becomes)
		made.tamed_by = by
		by.add_child(made)
		made.global_position = kept
		by.on_tamed_gained(made)
		queue_free()
		return
	tamed_by = by
	night_spawned = false
	by.on_tamed_gained(self)
	# Tamed animals belong to the village now — reparent so they survive
	# their birth-chunk unloading as the camera roams.
	if get_parent() != by:
		reparent.call_deferred(by)


## DRIVEN. Told where to stand by whoever is herding it — a barn on its daily
## round, or a villager. It is a suggestion, not a leash: a hungry or frightened
## beast still has its own mind and will break off, which is why this only sets
## a target rather than taking the animal over.
func drive_to(spot: Vector3) -> void:
	if state in [State.HELD, State.FALLING, State.FLEE, State.CHASE]:
		return
	_target = spot
	state = State.WANDER
	_action_time = maxf(_action_time, 6.0)


func is_tamable() -> bool:
	return spec.get("tame", false) and tamed_by == null and not spec.get("predator", false)


func set_rider(rider: Node3D) -> void:
	_rider = rider


func has_rider() -> bool:
	return _rider != null and is_instance_valid(_rider)


func meat_yield() -> int:
	return spec["meat"]


## THE JAWS. Called by the Mauling, both ways — it owns the pin, this only
## reflects it, so that a beast demoted back into its herd mid-kill (or freed
## with the chunk it stood in) cannot leave a villager pinned by a ghost.
func hold_down(who: Villager) -> void:
	pinning = who
	_prey = null
	state = State.MAUL


func release_hold() -> void:
	pinning = null
	if state == State.MAUL:
		state = State.IDLE
		_action_time = randf_range(0.5, 1.5)


## THE WORLD, FOUND ONCE. Villager has had this since the beginning; Animal
## never did, and asked the scene tree for it afresh on every step of every
## beast — inside `_move_toward`, which runs every frame for everything that is
## walking anywhere. A group lookup is cheap and a group lookup per animal per
## frame is not, and this is the busiest class in the game.
func _world() -> WorldGen:
	if _world_cache == null or not is_instance_valid(_world_cache):
		_world_cache = get_tree().get_first_node_in_group("world_gen") as WorldGen
	return _world_cache


## Divine hand interface ------------------------------------------------------

func pick_up() -> void:
	# OUT OF THE HERD, if it came from one. A beast being carried is not in a
	# formation any more, and leaving it in the herd's books stretched the mass
	# across the map behind it — see Herd.release.
	# ASKED WITH has_meta FIRST. get_meta's default argument does not spare you
	# the complaint when the object carries no metadata at all, and most animals
	# carry none — only a beast promoted out of a herd is ever handed this. So
	# every ordinary sheep picked up by hand printed an error, which is both
	# noise in the log and the wrong thing to print.
	if has_meta("herd"):
		var from = get_meta("herd")
		if from is Herd and is_instance_valid(from):
			(from as Herd).release(self)
	Mauling.free_of(self)   # whatever it had hold of, it does not any more
	state = State.HELD
	_rider = null
	velocity = Vector3.ZERO


## MENDED. The same door a villager is healed through, so a miracle does not
## have to know what it is putting right — it was simply missing here, and a
## healing shower fell on a burning, half-eaten sheep and did nothing for it.
func receive_heal() -> void:
	extinguish()
	health = _full_health


func drop(throw_velocity: Vector3, gentle := false) -> void:
	state = State.FALLING
	velocity = throw_velocity
	_gentle_drop = gentle


## Aftertouch hooks: bend a thrown beast's arc, and set its tumble axis.
func in_flight_push(dv: Vector3) -> void:
	if state == State.FALLING:
		velocity += dv


func set_flight_spin(angular: Vector3) -> void:
	_spin_ang = angular


## The semantic clip a rigged model plays for the current state.
func _anim_state() -> String:
	match state:
		State.FALLING: return "fall"
		State.HELD: return "idle"
		State.FLEE, State.CHASE: return "run"
		State.MAUL: return "graze"   # head down over a body; the nearest clip there is
		State.DRINKING: return "drink"
		State.GRAZE: return "graze"
	return "walk" if Vector2(velocity.x, velocity.z).length() > 0.3 else "idle"


func hover_text() -> String:
	var flavor := "wild"
	if tamed_by != null:
		flavor = "of %s" % tamed_by.village_name
	elif spec.get("predator", false):
		flavor = "predator"
	return "%s (%s) — hunger %d · thirst %d" % [
		species.capitalize(), flavor, int(hunger), int(thirst)]
