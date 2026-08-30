class_name Creature
extends CharacterBody3D
## Your creature: an ugly, lovable capsule-beast with an inner life. It
## OBSERVES the world (watching villagers work teaches it their jobs, wolves
## teach it to guard), it LEARNS (every deed can be reinforced with a pet or
## discouraged with a scolding — hover it and press P or L), and it FEELS
## (mood, boredom, and a bond with you that colors everything it chooses).
##
## Its morality is NOT yours: it drifts with what it witnesses you do — and
## with what you praise. Praise cruelty and you raise a monster.
##
##   Good creature:   tends farms, carries food to the granary, guards at night.
##   Bored creature:  plays — chasing sheep, dancing for the children.
##   Evil creature:   spooks villagers for fun, eats livestock, then people.

enum State {
	IDLE, WANDER, SEEK_FOOD, EATING, SLEEPING, GO_TEND, TENDING,
	WATCH, GO_GATHER, CARRYING, PLAY, GUARD, SULK, CATCH,
	GO_FISH, FISHING, GO_STORE, SMASH, FLEE, CAST, LEASHED,
	LOUNGE, DANCE, PRAY, COMMUNE, RUN, MIMIC, SHUN, DEPART,
}

const WALK_SPEED := 3.5
const GRAVITY := 20.0
## The growth arc: at 1% grown the creature stands about twice a villager's
## height; at 100% it towers over the tallest trees.
const MIN_SCALE := 1.1
## At full growth the creature stands ~38m — a clear head above the tallest
## ~30m trees, the towering B&W silhouette over the land.
const MAX_SCALE := 15.0
const STUCK_SECONDS := 30.0   # no state may hold the creature hostage
const OBSERVE_PERIOD := 2.5
## How sharply a deed's moral weight colours how it FELT to do. This is what
## makes cruelty sour for a kind creature and sweet for a wicked one.
const REMORSE := 2.0
## The shortest a deed may take, in seconds. Actions that resolve the instant
## they begin would otherwise re-decide every frame — see `_decide`.
const DEED_FLOOR := 0.5
## AMENDS. What it takes to end an exile: this much trust regained AND this
## many seconds without a repeat of what it left over. Both, or it stays away.
const AMENDS_SECONDS := 120.0
const AMENDS_TRUST := 45.0

var hunger := 40.0
var energy := 90.0
var growth := 0.01            # 0..1 of its destined size; every game starts small
var walks_on_water := false   # granted by a future miracle buff
## FLIGHT, granted by a miracle: while aloft the creature ignores the ground
## entirely — it soars over water, forest and hill alike, which is how it keeps
## up with a god on a map this wide.
var flight_time := 0.0
## THE LEASH: where you have ordered it to go. While set, your command overrides
## its own wants — it goes there and waits — but it still LEARNS from whatever
## happens on the way, so leading it somewhere is itself a way of teaching.
var leash_target := Vector3.INF

## Feelings. Mood is the weather of its heart; bond is how attached it is to
## you; boredom is the itch that play and curiosity scratch.
var mood := 60.0     # 0 wretched .. 100 delighted
var bond := 20.0     # 0 stranger .. 100 devoted
var boredom := 20.0

## TRUST — what it thinks of YOU, kept apart from bond on purpose. Bond is
## attachment; trust is whether your judgement is worth anything. A creature can
## be desperately attached to a god it has learned to flinch from.
##
## Trust is the valve on your whole influence: it decides how hard your example
## lands (see `witness_god_deed`), and when it falls far enough the creature
## stops taking your corrections, keeps its distance from your hand, and — if
## its own heart has grown kinder than yours — walks away to live by its own
## lights somewhere you are not.
var trust := 55.0

## EXILE. Not a one-off flight but a CONDITION: it lives out there, keeping its
## distance, refusing the leash, and getting on with its own life. It is always
## recoverable — but not by simply patting it until the number climbs. It comes
## home only once the thing it walked away from HAS ACTUALLY STOPPED.
var exiled := false
## What it holds against you, and how long since you last did it. Every fresh
## offence resets the clock, so a god who apologises and carries on offending
## never runs it down.
var grievance := ""
var grievance_time := 0.0

## Independent karma: -100 monstrous .. +100 angelic.
var morality := 0.0

## How good it is at catching what you throw — the one hand-eye SKILL it has,
## and the only thing praise trains directly rather than through the mind.
var catch_skill := 0.3

## ATTENTION: how closely it is watching your hand right now. Handing it
## things raises it (innate); it decays with neglect. Catching a thrown
## object requires attention — and catch skill grows when you praise it.
var attention := 20.0
var divine_hand: DivineHand = null  # wired by main

## THE MIND: an online-learning agent that chooses what to do from what it has
## learned, and updates those beliefs from how each deed turns out. Its
## `temperament` is what `morality` now reads from — character is EMERGENT.
var mind := CreatureMind.new()
## THE BODY: a real stomach that fills and takes time to empty, fat from
## overeating, and muscle earned by work. See CreatureBody.
var body := CreatureBody.new()
## Learned dread, raised by pain and fright. High fear makes fleeing attractive,
## so a creature that keeps getting hurt near people can become a recluse.
var fear := 0.0

var state := State.IDLE
var _last_deed := ""  # the deed a pet or scolding will be credited to
var _act_verb := ""    # the verb the mind chose (what the next reward teaches)
var _act_type := ""    # the kind of thing it chose to act on
var _smash_target: Node3D = null
var _cast_miracle := ""
var _mood_before := 60.0   # mood when the deed began, to judge how it went
var _deed_verb := ""       # the last FINISHED deed — what praise/scold judges
var _deed_type := ""
var _last_decision := 0    # ticks (ms) of the last real choice, for DEED_FLOOR
var _decay_tick := 0.0
var _target := Vector3.ZERO
var _target_food: Node3D = null      # FoodItem or Corpse
var _watch_subject: Villager = null
var _play_toy: Animal = null

## The claws: the creature can carry animals, food, and villagers.
## _carry_intent says why: "deliver" (to the granary), "eat" (if it can),
## "gift" (a tamable set down at the pen), "snatch" (villager mischief).
var _carried: Node3D = null
var _carry_intent := ""
var _catch_target: Node3D = null
var _catch_checked_id := 0  # one catch attempt per throw
## What it has learned it CANNOT eat, the hard way, one taste at a time.
var _inedible := {}
var _action_time := 2.0
var _observe_time := 0.0
var _state_time := 0.0
var _prev_state := State.IDLE
var _cheer_time := 0.0
var _look_time := 0.0      # when it next turns its head, while lounging
var _body: Node3D
var _label: Label3D
var _animator: ModelAnimator = null   # non-null only for a rigged custom model
var _walk_phase := 0.0

# Appearance & expression. Procedural parts are recoloured/animated directly;
# a custom model is driven through instance shader params ("alignment",
# "expression") and matching blend shapes if it has them.
var _fur_mat: StandardMaterial3D = null
var _eyes: Array[MeshInstance3D] = []      # eye whites, scaled for expressions
var _pupils: Array[MeshInstance3D] = []    # pupils, recoloured for mood/menace
var _model_meshes: Array[GeometryInstance3D] = []
var _shown_align := 999.0                  # last applied alignment (throttle)
var _expression := "neutral"
var _expr_time := 0.0
var _wedge_time := 0.0             # seconds shoving forward without advancing
var _fly_height := 0.0             # how high the flight miracle currently holds it
var _sway_tick := 0                # throttles the push-trees-aside sweep


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

	# A custom creature model (creature.glb) stands in for the whole beast. If
	# it's rigged with clips, an animator drives them and the procedural
	# waddle/pose steps aside.
	var custom := ModelBank.instantiate("creature")
	if custom != null:
		_body.add_child(custom)
		_animator = ModelAnimator.create(custom)
		# Collect renderables so alignment/expression can be pushed to the
		# model's shader (instance params) or blend shapes.
		for m in custom.find_children("*", "GeometryInstance3D", true, false):
			_model_meshes.append(m as GeometryInstance3D)
		if custom is GeometryInstance3D:
			_model_meshes.append(custom as GeometryInstance3D)
	else:
		# One shared fur material so the whole hide recolours with alignment.
		_fur_mat = Util.mat(Color(0.55, 0.42, 0.3))
		var body_part := Util.capsule(0.6, 1.8, Color.WHITE, Vector3(0, 1.0, 0))
		body_part.material_override = _fur_mat
		_body.add_child(body_part)
		var head := Util.sphere(0.45, Color.WHITE, Vector3(0, 2.1, 0.15))
		head.material_override = _fur_mat
		_body.add_child(head)
		for side in [-1, 1]:
			var white := Util.sphere(0.12, Color.WHITE, Vector3(0.18 * side, 2.25, 0.5))
			_eyes.append(white)
			_body.add_child(white)
			var pupil := Util.sphere(0.05, Color.BLACK, Vector3(0.18 * side, 2.25, 0.6))
			_pupils.append(pupil)
			_body.add_child(pupil)
		for side in [-1, 1]:
			var arm := Util.capsule(0.15, 0.8, Color.WHITE, Vector3(0.7 * side, 1.3, 0))
			arm.material_override = _fur_mat
			arm.rotation_degrees.z = 25 * side
			_body.add_child(arm)

	_label = Util.status_label()
	_label.position = Vector3(0, 3.0, 0)
	add_child(_label)
	scale = Vector3.ONE * lerpf(MIN_SCALE, MAX_SCALE, growth)


func _physics_process(delta: float) -> void:
	_tick_feelings(delta)
	_tick_watchdogs(delta)

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
			_process_seek_food(delta)
		State.EATING:
			_action_time -= delta
			_apply_gravity_only(delta)
			_body.scale.y = 1.0 + sin(Time.get_ticks_msec() / 60.0) * 0.08
			if _action_time <= 0.0:
				_body.scale.y = 1.0
				# A meal TEACHES: it filled the belly (good), but the mind also
				# books the moral weight of what was eaten, so devouring people
				# actually drags the creature's heart down. Without this the
				# deed had no consequence at all and it never learned.
				_finish_choice(1.0)
		State.GO_TEND:
			if _move_toward(_target, WALK_SPEED * 0.8, delta):
				state = State.TENDING
				_action_time = 5.0
		State.TENDING:
			_action_time -= delta
			_apply_gravity_only(delta)
			var farm := CreatureEyes.nearest_farm(get_tree(), global_position)
			if farm != null:
				farm.tend()
			if _action_time <= 0.0:
				_finish_deed("tend", 4.0)
		State.SLEEPING:
			_apply_gravity_only(delta)
			energy = minf(energy + 6.0 * delta, 100.0)
			if _animator == null:
				_body.rotation_degrees.z = 80
			if energy > 85.0:
				if _animator == null:
					_body.rotation_degrees.z = 0
				_decide()
		State.WATCH:
			_process_watch(delta)
		State.GO_GATHER:
			_process_go_gather(delta)
		State.CARRYING:
			_process_carrying(delta)
		State.CATCH:
			_process_catch(delta)
		State.GO_FISH:
			if _target == Vector3.ZERO:
				_decide()
			elif _move_toward(_target, WALK_SPEED * 0.8, delta):
				state = State.FISHING
				_action_time = 5.0
		State.FISHING:
			_apply_gravity_only(delta)
			_action_time -= delta
			if _animator == null:
				_body.rotation_degrees.x = sin(Time.get_ticks_msec() / 300.0) * 10.0
			if _action_time <= 0.0:
				if _animator == null:
					_body.rotation_degrees.x = 0
				_land_a_fish()
		State.GO_STORE:
			var store := CreatureEyes.nearest_store(get_tree(), global_position)
			if store == null:
				_decide()
			elif _move_toward(store.global_position, WALK_SPEED, delta):
				_eat_from_store(store)
		State.PLAY:
			_process_play(delta)
		State.GUARD:
			_process_guard(delta)
		State.SULK:
			_action_time -= delta
			_apply_gravity_only(delta)
			if _action_time <= 0.0:
				_decide()
		State.SMASH:
			_process_smash(delta)
		State.FLEE:
			_process_flee(delta)
		State.CAST:
			_process_cast(delta)
		State.LEASHED:
			_process_leashed(delta)
		State.LOUNGE:
			_process_lounge(delta)
		State.DANCE:
			_process_dance(delta)
		State.PRAY:
			_process_pray(delta)
		State.COMMUNE:
			_process_commune(delta)
		State.RUN:
			_process_run(delta)
		State.MIMIC:
			_process_mimic(delta)
		State.SHUN:
			_process_shun(delta)
		State.DEPART:
			_process_depart(delta)

	_observe_time -= delta
	if _observe_time <= 0.0:
		_observe_time = OBSERVE_PERIOD
		_observe_world()

	_try_catch_throw()

	# Bulldoze the meadow: nearby trees lean out of the giant's way (they spring
	# back once it passes). Throttled — the trees' own spring keeps it smooth.
	_sway_tick += 1
	if _sway_tick >= 3:
		_sway_tick = 0
		_sway_trees()

	# Whatever the claws hold rides along, up at the shoulder.
	if _carried != null:
		if is_instance_valid(_carried):
			_carried.global_position = global_position + Vector3.UP * (1.5 * scale.y) \
				+ global_transform.basis.z.normalized() * (0.9 * scale.x)
		else:
			_carried = null

	if _animator != null:
		_animator.play(_anim_state())
	else:
		_animate_waddle(delta)
	_apply_appearance()
	_tick_expression(delta)
	_tick_flight(delta)
	var status := _status_text()
	if _label.text != status:
		_label.text = status


## Feelings drift every frame: hunger gnaws, idleness bores, mood follows.
func _tick_feelings(delta: float) -> void:
	_tick_exile(delta)
	hunger = minf(hunger + 1.0 * delta, 100.0)
	if state != State.SLEEPING:
		energy = maxf(energy - 0.4 * delta, 0.0)
	if state in [State.IDLE, State.WANDER]:
		boredom = minf(boredom + 1.2 * delta, 100.0)
	if hunger > 80.0:
		mood = maxf(mood - 1.0 * delta, 0.0)
	if boredom > 70.0:
		mood = maxf(mood - 0.4 * delta, 0.0)
	# Mood slowly settles toward contentment scaled by bond: a loved
	# creature's resting state is happier.
	mood = lerpf(mood, 45.0 + bond * 0.3, 0.03 * delta)
	# Attention fades with neglect — but a hand hovering close-by is
	# magnetic: the creature watches it, and stays ready to learn or catch.
	attention = maxf(attention - 0.6 * delta, 0.0)
	fear = maxf(fear - 1.2 * delta, 0.0)
	# Digest: the stomach empties over time, and where the food GOES depends on
	# whether the body wanted it. Eating when sated is what makes it fat.
	var d := body.digest(delta, growth, hunger)
	hunger = d["hunger"]
	if d["growth"] > 0.0:
		_grow_by(d["growth"])
	body.idle(delta)
	# Opinions it stops rehearsing fade slowly back toward neutral.
	_decay_tick -= delta
	if _decay_tick <= 0.0:
		_decay_tick = 1.0
		mind.decay()
	if divine_hand != null and is_instance_valid(divine_hand):
		var reach := 5.0 + scale.x * 2.0
		if divine_hand.global_position.distance_to(global_position) < reach:
			attention = minf(attention + 12.0 * delta, 100.0)
			bond = minf(bond + 0.3 * delta, 100.0)


## Never stuck, never lost: re-decide if a state drags on, and snap back
## onto the terrain if the ground was streamed out from underneath us.
func _tick_watchdogs(delta: float) -> void:
	if state != _prev_state:
		_prev_state = state
		_state_time = 0.0
	_state_time += delta
	if _state_time > STUCK_SECONDS and state != State.SLEEPING:
		_state_time = 0.0
		_decide()
	# Wedged against a grove for more than a beat: give up this target now
	# rather than grinding a huge collider into the trunks (jank AND physics
	# lag) until STUCK_SECONDS finally trips.
	if _wedge_time > 1.4 and state != State.SLEEPING:
		_wedge_time = 0.0
		_decide()
	# Fell out of the world (chunk streamed away) or buried in a hillside
	# (bad spawn, collision hiccup)? Pop back to the surface.
	if global_position.y < -12.0 or fmod(_state_time, 3.0) < delta:
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null:
			var h := world.height_at(global_position.x, global_position.z)
			if global_position.y < h - 1.2:
				global_position.y = h + 0.5
				velocity = Vector3.ZERO


## The slow gaze: passively learn from whatever the villagers are doing
## nearby — and simply watching them work holds its attention.
func _observe_world() -> void:
	var watched_work := false
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		if villager.global_position.distance_to(global_position) > 16.0:
			continue
		match villager.state:
			Villager.State.FARMING:
				mind.teach("tend", "farm", 1.0, 0.02)
				watched_work = true
			Villager.State.FISHING:
				mind.teach("fish", "water", 1.0, 0.02)
				watched_work = true
			Villager.State.BUILDING, Villager.State.CHOPPING, Villager.State.QUARRYING:
				mind.teach("gather", "goods", 1.0, 0.015)
				watched_work = true
			Villager.State.GO_FEED, Villager.State.TAMING:
				mind.teach("gift", "sheep", 1.0, 0.01)
				watched_work = true
			# THE PRACTICES. A creature cannot dance until it has seen dancing,
			# and cannot lead a prayer it has never watched anyone say. This is
			# the whole of how its repertoire widens: villages that celebrate
			# and worship raise creatures that celebrate and worship, and a
			# grim, joyless village raises a creature that knows neither.
			Villager.State.PLAY:
				mind.witness_practice("dance")
			Villager.State.WORSHIPPING, Villager.State.PREACHING:
				mind.witness_practice("pray")
	if watched_work:
		# Curiosity about the villagers' work keeps it engaged and alert.
		attention = minf(attention + 5.0, 100.0)
		boredom = maxf(boredom - 4.0, 0.0)
	if GameState.is_night():
		for a in get_tree().get_nodes_in_group("animals"):
			var animal := a as Animal
			if is_instance_valid(animal) and animal.species == "wolf" \
					and animal.global_position.distance_to(global_position) < 25.0:
				mind.teach("guard", "village", 1.0, 0.05)


## Decision-making — THE MIND DECIDES ------------------------------------------
##
## The creature no longer follows a script of behaviours. Each time it must act,
## it PERCEIVES the world as a list of (verb, thing) opportunities, asks its
## learning mind to predict how each would feel, and enacts whichever it picks.
## Everything it becomes — kind, cruel, cowardly, obsessive — grows out of what
## those choices taught it.
func _decide() -> void:
	# A watchdog abort mid-carry sets the cargo down, never drops it forever.
	if _carried != null:
		_release_carried(true)
	_last_deed = ""
	_mood_before = mood
	# YOUR COMMAND FIRST, and instantly: a leashed creature never waits.
	if leash_target != Vector3.INF:
		state = State.LEASHED
		_action_time = 2.0
		return
	# A DEED TAKES A MOMENT. Some actions finish the instant they begin — a
	# smash when already in reach lands, finishes and decides again on the very
	# next frame. Unbounded, the creature lives a hundred lifetimes a second and
	# its habits, beliefs and character all form in a blur before you can see
	# what it is doing. It rests a beat between deeds instead.
	var since := float(Time.get_ticks_msec() - _last_decision) / 1000.0
	if _last_decision > 0 and since < DEED_FLOOR:
		state = State.IDLE
		_action_time = DEED_FLOOR - since
		return
	_last_decision = Time.get_ticks_msec()
	var drive := {
		"hunger": hunger, "energy": energy, "boredom": boredom,
		"mood": mood, "fear": fear, "wounded": _wounded_nearby(),
		"full": body.fullness(growth), "lazy": body.laziness(),
		# Being alone is a need like any other. A creature with nobody about
		# leans toward whatever brings it near people — which for one creature
		# means holding court and for another means going and finding someone
		# to torment. The drive does not care which.
		"lonely": 1.0 if _audience(24.0) == 0 else 0.0,
	}
	var choice := mind.choose(_perceive(), drive, _circumstances())
	_act_verb = choice["verb"]
	_act_type = choice.get("type", "none")
	_enact(choice)


## THE CIRCUMSTANCES it notices right now — the situation its beliefs are
## learned against. "I was starving, in their village, at night, with armed men
## about, and my god was nowhere near." Every value is 0..1.
func _circumstances() -> Dictionary:
	var crowd := 0
	var armed := 0
	var predator := 0.0
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		if villager.global_position.distance_to(global_position) < 22.0:
			crowd += 1
			if villager.weapon != "":
				armed += 1
	for a in get_tree().get_nodes_in_group("animals"):
		var beast := a as Animal
		if is_instance_valid(beast) and beast.spec.get("predator", false) \
				and beast.global_position.distance_to(global_position) < 20.0:
			predator = 1.0
			break
	var home := CreatureEyes.home_village(get_tree())
	var in_village := 0.0
	if home != null and home.global_position.distance_to(global_position) \
			< home.influence_radius:
		in_village = 1.0
	var god_near := 0.0
	if divine_hand != null and is_instance_valid(divine_hand) \
			and divine_hand.global_position.distance_to(global_position) < 18.0:
		god_near = 1.0
	return {
		"hungry": clampf(hunger / 100.0, 0.0, 1.0),
		"stuffed": body.fullness(growth),
		"tired": clampf((100.0 - energy) / 100.0, 0.0, 1.0),
		"afraid": clampf(fear / 100.0, 0.0, 1.0),
		"hurt": clampf((100.0 - mood) / 100.0, 0.0, 1.0),
		"bored": clampf(boredom / 100.0, 0.0, 1.0),
		"crowd": clampf(crowd / 5.0, 0.0, 1.0),
		"armed": clampf(armed / 3.0, 0.0, 1.0),
		"predator": predator,
		"god_near": god_near,
		"in_village": in_village,
		"night": 1.0 if GameState.is_night() else 0.0,
		"alone": 1.0 if crowd == 0 else 0.0,
	}


## Everything the creature can see worth doing right now, as (verb, type,
## target) opportunities. This is PERCEPTION ONLY — it expresses what is
## POSSIBLE, never what is preferable; the mind alone weighs them.
func _perceive() -> Array:
	# Keyed by "verb|type" so each distinct ACTION gets exactly ONE ballot. This
	# matters enormously: listing every villager separately would give "eat a
	# villager" a dozen entries against a single "cast heal", and the choice
	# would be decided by how many bodies happen to be standing about rather
	# than by what the creature actually values. Nearest target wins the slot.
	var opts := {}
	_offer(opts, "wander", "none", null)
	if energy < 55.0:
		_offer(opts, "rest", "none", null)

	# A FULL creature does not hunt. Appetite, not just hunger, decides.
	var can_eat := _can_eat(1.0)
	var food := CreatureEyes.nearest_food(get_tree(), global_position, morality)
	if food != null and can_eat:
		_offer(opts, "eat", _type_of(food), food)
	# Things it could carry off — to the granary, or to hurl, or to devour.
	var carriable := CreatureEyes.nearest_carriable(get_tree(), global_position, 35.0)
	if carriable != null and not can_lift(carriable):
		carriable = null   # beyond its strength; it knows better than to try
	if carriable != null:
		_offer(opts, "gather", _type_of(carriable), carriable)
		_offer(opts, "throw", _type_of(carriable), carriable)
	# Every creature, beast and building nearby is something it COULD attack,
	# carry, hurl or eat. Whether it ever does is entirely learned.
	for node in _things_around(26.0):
		var t := _type_of(node)
		_offer(opts, "smash", t, node)
		if node is Animal or node is Villager:
			_offer(opts, "throw", t, node)
			if node is Villager:
				# Eating people is only ever CONSIDERED by a creature that has not
				# grown kind. Its conscience does the rest of the work.
				if mind.temperament < 20.0 and can_eat:
					_offer(opts, "eat_kin", t, node)
			elif (node as Animal).meat_yield() > 0 and can_eat \
					and not _inedible.has((node as Animal).species):
				_offer(opts, "eat", t, node)
		if node is Villager:
			_offer(opts, "watch", t, node)
			if fear > 25.0:
				_offer(opts, "flee", t, node)   # only a frightened beast thinks of running
			if (node as Villager).is_dying():
				_offer(opts, "rescue", t, node)
		if node is WildTree and can_lift(node):
			# Only as much tree as its muscle can manage. A hatchling wrestles
			# saplings; a forest giant needs a grown beast — or the Strength
			# miracle. Hauling one home is the exercise that builds the muscle.
			_offer(opts, "gather", t, node)
		if node is Animal:
			_offer(opts, "play", t, node)
			if (node as Animal).is_tamable():
				_offer(opts, "gift", t, node)

	var farm := CreatureEyes.nearest_farm(get_tree(), global_position)
	if farm != null:
		_offer(opts, "tend", "farm", farm)
	if _find_shore() != Vector3.INF:
		_offer(opts, "fish", "water", null)
	# The granary: an easy meal it can learn to raid (the villagers notice).
	var store := CreatureEyes.nearest_store(get_tree(), global_position)
	if store != null and store.total_food() > 0 and can_eat:
		_offer(opts, "eat", "store", store)
	if GameState.is_night():
		_offer(opts, "guard", "village", null)
	# Miracles it has watched often enough to try itself.
	for m: String in mind.known_miracles():
		_offer(opts, "cast", m, null)
	_offer_quiet_life(opts)
	return opts.values()


## THE HOURS IN BETWEEN. Most of a life is not spent killing or saving anyone,
## and a creature offered only those two things will pick one and become it.
## These are always on the ballot; none of them is ever forced, and none is
## worth anything until the creature finds out for itself whether it likes them.
func _offer_quiet_life(opts: Dictionary) -> void:
	# Doing nothing much, with its eyes open. Not sleep — this is the creature
	# sprawled in the grass watching the world go by, and it is a real choice.
	_offer(opts, "lounge", "none", null)
	_offer(opts, "run", "none", null)
	# Running with something heavy is how muscle is actually earned.
	var load_bearing := CreatureEyes.nearest_carriable(get_tree(), global_position, 30.0)
	if load_bearing != null and can_lift(load_bearing):
		_offer(opts, "run", _type_of(load_bearing), load_bearing)

	# Practices are LEARNED, not innate: it can only dance if it has seen
	# dancing. A creature raised beside a joyless village never picks them up.
	var village := CreatureEyes.home_village(get_tree())
	var near_home := village != null \
		and global_position.distance_to(village.global_position) < village.influence_radius * 1.6
	if mind.knows("dance"):
		_offer(opts, "dance", "village" if near_home else "none", null)
	if near_home:
		if mind.knows("pray"):
			_offer(opts, "pray", "village", null)
		# Standing before the people and being attended to. It costs them
		# nothing and wins you belief — the whole non-violent road.
		_offer(opts, "commune", "village", null)

	# COPYING YOU. Only ever on the table while it still thinks you are worth
	# copying, and only once it has watched you do enough to have a habit of it.
	if trust > 35.0 and not exiled and mind.knows("mimic") and divine_hand != null \
			and is_instance_valid(divine_hand):
		_offer(opts, "mimic", "god", divine_hand)

	# What a mistreated creature has instead of obedience. These are options,
	# not fates: a creature can be badly used and still choose to stay.
	if trust < 40.0 or exiled:
		_offer(opts, "sulk", "none", null)
		if divine_hand != null and is_instance_valid(divine_hand) \
				and (exiled or divine_hand.global_position
					.distance_to(global_position) < 30.0):
			_offer(opts, "shun", "god", divine_hand)
	# LEAVING. Offered only when it has stopped trusting you AND its own heart
	# has outgrown yours — a good creature with a cruel god. It is still only an
	# option among many, and a creature that has learned to love you anyway
	# (bond) will rarely take it.
	if trust < 20.0 and mind.temperament > 15.0 and not exiled:
		_offer(opts, "depart", "none", null)


## Put an opportunity on the ballot, keeping the NEAREST target for each
## distinct (verb, type) — one entry per action, never one per body.
func _offer(opts: Dictionary, verb: String, type: String, target: Node3D) -> void:
	var key := verb + "|" + type
	if opts.has(key) and target != null:
		var held: Node3D = opts[key]["target"]
		if held != null and is_instance_valid(held) \
				and held.global_position.distance_squared_to(global_position) \
					<= target.global_position.distance_squared_to(global_position):
			return
	opts[key] = {"verb": verb, "type": type, "target": target}


## Whatever is close enough to be an opportunity, capped so a busy village
## never makes one decision expensive.
func _things_around(radius: float) -> Array:
	var found := []
	for group in ["villagers", "animals", "houses", "trees", "rock_deposits", "corpses"]:
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if not is_instance_valid(node) or node == self:
				continue
			if node.global_position.distance_to(global_position) < radius:
				found.append(node)
				if found.size() >= 24:
					return found
	return found


## The KIND of a thing — the creature learns about categories, not individuals,
## so one bad sheep teaches it about sheep.
func _type_of(node: Node) -> String:
	return CreatureEyes.kind_of(node)


## Carry out the mind's choice by driving the body's existing motor states.
func _enact(choice: Dictionary) -> void:
	var verb: String = choice["verb"]
	var target: Node3D = choice.get("target", null)
	if target != null and not is_instance_valid(target):
		_wander()
		return
	match verb:
		"rest":
			state = State.SLEEPING
		"eat":
			if target is FoodStore:
				state = State.GO_STORE
			elif target is FoodItem or target is Corpse:
				_target_food = target
				state = State.SEEK_FOOD
			else:
				_catch_target = target
				_carry_intent = "eat"
				state = State.CATCH
		"eat_kin":
			_catch_target = target
			_carry_intent = "eat"
			state = State.CATCH
		"gather":
			_target_food = target
			state = State.GO_GATHER
		"throw":
			_catch_target = target
			_carry_intent = "hurl"
			state = State.CATCH
		"smash":
			_smash_target = target
			state = State.SMASH
		"tend":
			state = State.GO_TEND
			_target = target.global_position
		"watch":
			_watch_subject = target as Villager
			state = State.WATCH
			_action_time = randf_range(5.0, 8.0)
		"play":
			_play_toy = target as Animal
			state = State.PLAY
			_action_time = randf_range(6.0, 10.0)
		"gift":
			_catch_target = target
			_carry_intent = "gift"
			state = State.CATCH
		"rescue":
			_catch_target = target
			_carry_intent = "rescue"
			state = State.CATCH
			var home := CreatureEyes.home_village(get_tree())
			_target = home.global_position if home != null else global_position
		"guard":
			state = State.GUARD
			_action_time = randf_range(10.0, 18.0)
			_pick_guard_waypoint()
		"fish":
			var shore := _find_shore()
			if shore == Vector3.INF:
				_wander()
			else:
				_target = shore
				state = State.GO_FISH
		"flee":
			state = State.FLEE
			_action_time = randf_range(3.0, 6.0)
			var away := global_position - target.global_position
			away.y = 0.0
			_target = global_position + away.normalized() * 16.0
		"cast":
			_cast_miracle = choice.get("type", "")
			state = State.CAST
			_action_time = 2.0
		"lounge":
			# A long, unhurried stretch of nothing. The creature is not idle
			# between deeds here — being at ease IS the deed, and it lasts long
			# enough for you to sit and watch it.
			state = State.LOUNGE
			_action_time = randf_range(9.0, 20.0)
			express("happy", 3.0)
		"dance":
			state = State.DANCE
			_action_time = randf_range(6.0, 11.0)
		"pray":
			state = State.PRAY
			_action_time = randf_range(8.0, 15.0)
		"commune":
			state = State.COMMUNE
			_action_time = randf_range(7.0, 13.0)
			var home := CreatureEyes.home_village(get_tree())
			_target = home.global_position if home != null else global_position
		"run":
			# For the joy of it, and for the muscle. Somewhere far, at speed.
			if target != null:
				_catch_target = target
				_carry_intent = "run"
				state = State.CATCH
			else:
				_begin_run()
		"mimic":
			state = State.MIMIC
			_action_time = randf_range(5.0, 9.0)
		"sulk":
			state = State.SULK
			_action_time = randf_range(6.0, 12.0)
			express("sad", 4.0)
		"shun":
			state = State.SHUN
			_action_time = randf_range(4.0, 8.0)
			var off := global_position - target.global_position
			off.y = 0.0
			_target = global_position + off.normalized() * 22.0
		"depart":
			_begin_departure()
		_:
			_wander()


func _wander() -> void:
	state = State.WANDER
	var angle := randf() * TAU
	var dist := randf_range(4.0, 18.0)
	_target = Vector3(cos(angle) * dist, 0, sin(angle) * dist)


## A deed is done: remember it (for praise/scolding), feel it, move on.
func _finish_deed(deed: String, mood_gain: float) -> void:
	_last_deed = deed
	mood = minf(mood + mood_gain, 100.0)
	boredom = maxf(boredom - 25.0, 0.0)
	# Every finished deed teaches the mind what it was worth.
	_deed_verb = _act_verb
	_deed_type = _act_type
	mind.reinforce(clampf(mood_gain / 8.0 + (mood - _mood_before) / 50.0, -3.0, 3.0))
	# A creature working among a people IS divine attention — the village it
	# labours in quickens and grows.
	if deed in ["tend", "gather", "guard", "gift", "play", "fish"]:
		var home := CreatureEyes.home_village(get_tree())
		if home != null and home.global_position.distance_to(global_position) < 45.0:
			home.notice(14.0)
	morality = mind.temperament
	match deed:
		"play": express("happy")
		"guard": express("angry", 1.2)
		"watch": express("curious")
		"hunt", "mischief", "rampage": express("angry")
		"gift", "tend", "gather": express("happy", 1.2)
	_decide()


## State processors ----------------------------------------------------------

func _process_seek_food(delta: float) -> void:
	if _target_food == null or not is_instance_valid(_target_food) \
			or _target_food.is_queued_for_deletion():
		_target_food = null
		_decide()
	elif _move_toward(_target_food.global_position, WALK_SPEED, delta):
		_consume_food_target()


func _process_watch(delta: float) -> void:
	if _watch_subject == null or not is_instance_valid(_watch_subject) \
			or not CreatureEyes.is_working(_watch_subject):
		_watch_subject = null
		_decide()
		return
	var spot := _watch_subject.global_position
	if global_position.distance_to(spot) > 3.5:
		_move_toward(spot, WALK_SPEED * 0.7, delta)
		return
	_apply_gravity_only(delta)
	look_at(global_position - (spot - global_position), Vector3.UP)
	_action_time -= delta
	if _action_time <= 0.0:
		_learn_from(_watch_subject.state)
		_finish_deed("watch", 3.0)


## Watching a job through to the end is the strongest version of the same
## lesson — straight onto the value it will weigh when it next chooses.
func _learn_from(watched_state: Villager.State) -> void:
	match watched_state:
		Villager.State.FARMING:
			mind.teach("tend", "farm", 1.5, 0.15)
		Villager.State.BUILDING, Villager.State.CHOPPING, Villager.State.QUARRYING:
			mind.teach("gather", "goods", 1.5, 0.1)
		Villager.State.PLAY:
			mind.witness_practice("dance", CreatureMind.PRACTICE_STEP * 2.0)
		Villager.State.WORSHIPPING, Villager.State.PREACHING:
			mind.witness_practice("pray", CreatureMind.PRACTICE_STEP * 2.0)


func _process_go_gather(delta: float) -> void:
	if _target_food == null or not is_instance_valid(_target_food) \
			or _target_food.is_queued_for_deletion() \
			or not (_target_food is FoodItem or _target_food is ResourceItem):
		_target_food = null
		_decide()
	elif _move_toward(_target_food.global_position, WALK_SPEED * 0.9, delta):
		_pick_up_thing(_target_food, "deliver")
		_target_food = null


## PLAYING CATCH: if the hand throws something and the creature is paying
## attention, it may snatch the object out of the air — a skill that
## grows each time you praise a catch.
func _try_catch_throw() -> void:
	if _carried != null or divine_hand == null \
			or state in [State.SLEEPING, State.SULK]:
		return
	var thrown := divine_hand.last_thrown
	if thrown == null or not is_instance_valid(thrown) or thrown.is_queued_for_deletion():
		return
	if thrown.get_instance_id() == _catch_checked_id:
		return
	if global_position.distance_to(thrown.global_position) > 2.2 + scale.x:
		return
	_catch_checked_id = thrown.get_instance_id()  # one attempt per throw
	if attention < 35.0:
		return  # not watching your hand; it sails past
	var skill := clampf(catch_skill * 0.55, 0.12, 0.95)
	if randf() > skill:
		GameState.announce("Your creature lunged... and fumbled the catch. Practice.")
		mood = maxf(mood - 2.0, 0.0)
		return
	_pick_up_thing(thrown, _intent_for(thrown))
	_last_deed = "catch"
	mood = minf(mood + 10.0, 100.0)
	bond = minf(bond + 2.0, 100.0)
	attention = minf(attention + 10.0, 100.0)
	express("happy")
	GameState.announce("Your creature CAUGHT it! It looks extremely pleased with itself.")


## Handing the creature something is innate — it always accepts, and it
## teaches it to watch your hand (attention up, bond up).
func receive_gift(item: Node3D) -> void:
	if _carried != null:
		_release_carried(true)
	attention = minf(attention + 15.0, 100.0)
	bond = minf(bond + 2.0, 100.0)
	mood = minf(mood + 6.0, 100.0)
	earn_trust(2.5)   # a hand that gives is a hand worth watching
	express("curious")
	_pick_up_thing(item, _intent_for(item))
	_last_deed = "receive"


## What would the creature DO with this thing?
func _intent_for(item: Node3D) -> String:
	if item is FoodItem:
		return "eat" if hunger > 45.0 else "deliver"
	if item is ResourceItem or item is WildTree:
		return "deliver"
	if item is Animal:
		var animal := item as Animal
		if hunger > 55.0 and animal.meat_yield() > 0 and not _inedible.has(animal.species):
			return "eat"
		if animal.is_tamable() and morality > 0.0:
			return "gift"
		return "release"
	if item is Corpse:
		return "eat"  # feeding it the dead is a dark offering it won't refuse
	if item is Villager:
		# Force-fed a living villager: a wild or cruel beast DEVOURS them — a
		# black deed that corrupts it fast. Only a good-hearted one (gentle+)
		# refuses, sparing the person (and cradling a dying one back to life).
		if morality >= 20.0:
			return "release"
		return "eat"
	return "release"


## The chase: run the quarry down and take it in the claws.
func _process_catch(delta: float) -> void:
	if _catch_target == null or not is_instance_valid(_catch_target) \
			or _catch_target.is_queued_for_deletion():
		_catch_target = null
		_decide()
		return
	var reach := 2.0 + scale.x * 0.6
	if global_position.distance_to(_catch_target.global_position) < reach:
		_pick_up_thing(_catch_target, _carry_intent)
		_catch_target = null
	else:
		_move_toward(_catch_target.global_position, _run_speed(), delta)


## A bigger creature is a faster creature — full-grown, it runs down wolves.
func _run_speed() -> float:
	# A fat creature lumbers; a strong one moves well (see CreatureBody).
	return WALK_SPEED * (1.1 + growth * 0.9) * body.speed_factor()


func _pick_up_thing(node: Node3D, intent: String) -> void:
	# A GOOD creature (gentle+) lifting a dying villager cradles them back to a
	# sliver of life, same as the hand. A wild or cruel one does no such mercy —
	# it will eat what it's handed (see _intent_for / _eat_carried).
	if node is Villager and (node as Villager).is_dying() and morality >= 20.0:
		(node as Villager).rescue()
	_carried = node
	_carry_intent = intent
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	elif node.has_method("pick_up"):
		node.call("pick_up")
	state = State.CARRYING
	_action_time = 1.4 if intent in ["eat", "hurl"] else 5.0


func _process_carrying(delta: float) -> void:
	if _carried == null or not is_instance_valid(_carried):
		_carried = null
		_decide()
		return
	match _carry_intent:
		"run":
			# It has what it wanted to carry; now go and run with it.
			_begin_run()
		"deliver":
			var store := CreatureEyes.nearest_store(get_tree(), global_position)
			if store == null:
				_release_carried(true)
				_decide()
			elif _move_toward(store.global_position, WALK_SPEED * 0.9, delta):
				if _carried is FoodItem:
					store.add((_carried as FoodItem).food_type, 1)
					_carried.queue_free()
				elif _carried is ResourceItem:
					if (_carried as ResourceItem).kind == "lumber":
						store.add_lumber(1)
					else:
						store.add_stone(1)
					_carried.queue_free()
				elif _carried is WildTree:
					store.add_lumber(maxi(int((_carried as WildTree).lumber), 1))
					_carried.queue_free()
				_carried = null
				for v in get_tree().get_nodes_in_group("villagers"):
					if v.global_position.distance_to(global_position) < 8.0:
						v.cheer(2.0)
				_finish_deed("gather", 6.0)
		"eat":
			_apply_gravity_only(delta)
			_action_time -= delta
			if _action_time <= 0.0:
				_eat_carried()
		"gift":
			var village := CreatureEyes.home_village(get_tree())
			if village == null:
				_release_carried(true)
				_decide()
			elif _move_toward(village.pen_position(), WALK_SPEED * 0.9, delta):
				GameState.announce("Your creature sets a %s down by the pen. A gift."
					% (_carried as Animal).species)
				_release_carried(true)  # gentle landing in a kind pen tames it
				_finish_deed("gift", 8.0)
		"snatch":
			_action_time -= delta
			_move_toward(_target, _run_speed() * 0.8, delta)
			if _action_time <= 0.0:
				if _carried is Villager:
					(_carried as Villager).witness_horror(2.0)
				mind.judge(-0.20)
				morality = mind.temperament
				mood = minf(mood + 6.0, 100.0)
				_release_carried(false)
				_last_deed = "mischief"
				_decide()
		"rescue":
			# Carry the saved soul home and set them gently down.
			var village := CreatureEyes.home_village(get_tree())
			var dest := village.global_position if village != null else global_position
			if _move_toward(dest, WALK_SPEED, delta):
				var saved_name := ""
				if _carried is Villager:
					saved_name = (_carried as Villager).villager_name
				_release_carried(true)
				express("love")
				_finish_deed("gift", 10.0)  # a saintly act
				if saved_name != "":
					GameState.announce("Your creature carried %s to safety." % saved_name)
		"hurl":
			# A brief wind-up, then FLING it far and hard. Cruel joy.
			_action_time -= delta
			_apply_gravity_only(delta)
			if _action_time <= 0.0:
				_hurl_carried()
				_last_deed = "rampage"
				mind.judge(-0.40)
				morality = mind.temperament
				mood = minf(mood + 8.0, 100.0)
				boredom = maxf(boredom - 25.0, 0.0)
				_decide()
		_:
			_release_carried(true)
			_decide()


## The line comes up: a real fish, held in the claws. Eat it, or carry
## it home for the granary if the belly can wait.
func _land_a_fish() -> void:
	var fish := FoodItem.new()
	fish.food_type = FoodItem.FoodType.MEAT
	fish.meat_name = "fish"
	get_parent().add_child(fish)
	fish.global_position = global_position + Vector3(0, 1.0, 0)
	_last_deed = "fish"
	_pick_up_thing(fish, "eat" if hunger > 45.0 else "deliver")


func _eat_from_store(store: FoodStore) -> void:
	var got := store.take(FoodItem.FoodType.PLANT, 1)
	if got == 0:
		got = store.take(FoodItem.FoodType.MEAT, 1)
	if got > 0:
		_swallow_units(1.0)
		mind.judge(-0.10)  # that was somebody's dinner
		morality = mind.temperament
		state = State.EATING
		_action_time = 1.5
	else:
		_decide()


## A dry spot at the water's edge, or INF if no shore is near.
func _find_shore() -> Vector3:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return Vector3.INF
	for dist: float in [12.0, 25.0, 40.0]:
		for i in 8:
			var angle := TAU * i / 8.0 + randf() * 0.3
			var probe := global_position + Vector3(cos(angle), 0, sin(angle)) * dist
			if world.is_underwater(probe.x, probe.z):
				return global_position + (probe - global_position) * 0.85
	return Vector3.INF


## The moment of truth: some things are food, some things are lessons.
func _eat_carried() -> void:
	# The darkest meals: a villager it was handed (or ran down), or a corpse.
	if _carried is Villager:
		_devour_villager(_carried as Villager)
		_carried = null
		state = State.EATING
		_action_time = 2.0
		return
	if _carried is Corpse:
		mind.judge(-0.60)
		morality = mind.temperament
		_swallow_units(1.6)
		GameState.announce("Your creature feeds on the dead. The villagers look away.")
		_last_deed = "mischief"
		_carried.queue_free()
		_carried = null
		state = State.EATING
		_action_time = 2.0
		return
	var animal := _carried as Animal
	if animal == null:
		_release_carried(true)
		_decide()
		return
	if animal.meat_yield() <= 0:
		_inedible[animal.species] = true
		GameState.announce("Your creature tastes a %s, gags, and sets it down. Lesson learned."
			% animal.species)
		mood = maxf(mood - 4.0, 0.0)
		_release_carried(true)
		_decide()
		return
	if animal.tamed_by != null:
		mind.judge(-0.60)
		morality = mind.temperament
		GameState.announce("Your creature has eaten a penned %s. The herders grieve." % animal.species)
	elif animal.spec.get("predator", false):
		mind.judge(0.20)  # culling wolves is a service
		morality = mind.temperament
	else:
		mind.judge(-0.10)
		morality = mind.temperament
	_swallow_units(1.0 + animal.meat_yield() * 0.7)
	_last_deed = "hunt"
	animal.die(false)
	_carried = null
	state = State.EATING
	_action_time = 2.0


func _release_carried(gentle: bool) -> void:
	if _carried != null and is_instance_valid(_carried):
		if _carried is RigidBody3D:
			(_carried as RigidBody3D).freeze = false
			(_carried as RigidBody3D).linear_velocity = Vector3.ZERO
		elif _carried.has_method("drop"):
			var toss := Vector3.ZERO if gentle \
				else Vector3(randf_range(-2, 2), 2.0, randf_range(-2, 2))
			_carried.call("drop", toss, gentle)
	_carried = null


## Fling the held thing away hard, in a random direction. Scares and
## bruises whatever it was.
func _hurl_carried() -> void:
	if _carried == null or not is_instance_valid(_carried):
		_carried = null
		return
	var dir := Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)).normalized()
	var v := dir * randf_range(14.0, 22.0)
	if _carried.has_method("take_damage"):
		_carried.call("take_damage", 25.0)  # one arg: works for animal and villager
	if _carried is RigidBody3D:
		(_carried as RigidBody3D).freeze = false
		(_carried as RigidBody3D).linear_velocity = v
	elif is_instance_valid(_carried) and _carried.has_method("drop"):
		_carried.call("drop", v, false)
	_carried = null


## Stomp the house: heavy damage, a boom, terror for anyone watching.
## Shove every tree within reach out of the way (they lean and spring back).
## Reach scales with the creature's size, so a full-grown giant clears a wide
## swathe. Only trees near enough do any work; the rest are skipped by distance.
func _sway_trees() -> void:
	var reach := 0.6 * scale.x + 2.5
	var reach2 := reach * reach
	# The lean angle grows with the creature's size: a hatchling barely nudges a
	# tree, a full-grown giant bends it right over. (WildTree clamps to MAX_LEAN.)
	var strength := clampf(scale.x * 0.09, 0.2, 1.1)
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if not is_instance_valid(tree):
			continue
		var dx := tree.global_position.x - global_position.x
		var dz := tree.global_position.z - global_position.z
		var d2 := dx * dx + dz * dz
		if d2 > reach2 or d2 < 0.0001:
			continue
		tree.sway(global_position, (1.0 - sqrt(d2) / reach) * strength)


## SMASH: charge the thing and hit it — anything at all. What that costs the
## creature's soul, and whether it ever does it again, is learned, not scripted.
func _process_smash(delta: float) -> void:
	if _smash_target == null or not is_instance_valid(_smash_target):
		_smash_target = null
		_decide()
		return
	var reach := 2.4 + scale.x * 0.7
	if global_position.distance_to(_smash_target.global_position) > reach:
		_move_toward(_smash_target.global_position, _run_speed(), delta)
		return
	var victim := _smash_target
	_smash_target = null
	SoundBank.play_at("boom", global_position, -2.0)
	express("angry")
	# A release, yes — but not inherently more satisfying than honest work, or
	# every creature drifts into vandalism whatever its nature.
	var thrill := 0.15 + boredom / 260.0
	if victim is House:
		(victim as House).kick(global_position, 1.0)
		_scare_witnesses(14.0, 3.0)
	elif victim is WildTree:
		var tree := victim as WildTree
		tree.sway(global_position, 1.1)
		if tree.lumber > 1.0 and randf() < 0.5:
			tree.fell()
	elif victim is Villager:
		# They know exactly what hit them — this is how a village comes to hate
		# (and eventually take up arms against) your creature.
		(victim as Villager).hurt_by(self, 45.0)
		if is_instance_valid(victim):
			(victim as Villager).scare(global_position)
		_scare_witnesses(14.0, 4.0)
	elif victim is Animal:
		var beast := victim as Animal
		var was_predator: bool = beast.spec.get("predator", false)
		beast.take_damage(50.0)
		if is_instance_valid(beast):
			beast.scare(global_position)
		# Driving off a wolf feels GOOD and the village cheers; bullying a lamb
		# earns nothing but a flinch. The creature learns the difference itself.
		if was_predator:
			thrill += 0.9
			_cheer_nearby(10.0, 2.0)
		else:
			_scare_witnesses(12.0, 2.0)
	elif victim.has_method("damage"):
		victim.call("damage", 40.0)
	_last_deed = "smash"
	body.exert(3.0, 0.35)   # a real swing is real effort
	boredom = maxf(boredom - 22.0, 0.0)
	_finish_choice(thrill)


## FLEE: put distance between itself and whatever frightens it. A creature that
## keeps getting hurt near villagers can learn to live as a recluse.
func _process_flee(delta: float) -> void:
	_action_time -= delta
	if _move_toward(_target, _run_speed(), delta) or _action_time <= 0.0:
		fear = maxf(fear - 12.0, 0.0)   # distance soothes
		_last_deed = "flee"
		_finish_choice(0.25 + fear / 200.0)


## CAST: attempt a miracle it has watched its god perform often enough to have
## some feel for. Its version is weaker (familiarity scales the potency) and it
## learns from how the result lands.
func _process_cast(delta: float) -> void:
	_apply_gravity_only(delta)
	_action_time -= delta
	if _action_time > 0.0:
		return
	var miracle := _cast_miracle
	_cast_miracle = ""
	if miracle == "":
		_decide()
		return
	var manager := get_tree().get_first_node_in_group("miracles") as MiracleManager
	if manager == null:
		_decide()
		return
	# Aim where the miracle is WANTED — over the hurt, if any — rather than at a
	# random patch of grass. A miracle that helps somebody teaches it far more.
	var need := _neediest_villager()
	var spot := global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	if need != null:
		spot = need.global_position
	manager.creature_cast(miracle, spot, float(mind.familiarity.get(miracle, 0.0)))
	express("curious")
	GameState.announce("Your creature works a miracle of its own: %s!" % miracle.replace("_", " "))
	_last_deed = "cast"
	mood = minf(mood + 10.0, 100.0)
	_finish_choice(1.6 if need != null else 0.6)


## How badly the people nearby need help right now (0..1) — the pull behind
## reaching for a healing miracle instead of standing about.
func _wounded_nearby() -> float:
	var hurt := 0
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		if villager.global_position.distance_to(global_position) > 30.0:
			continue
		if villager.is_dying() or villager.health < 60.0 or villager.burning:
			hurt += 1
	return clampf(hurt / 3.0, 0.0, 1.0)


## Whoever most needs a miracle worked over them.
func _neediest_villager() -> Villager:
	var best: Villager = null
	var worst := 60.0
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		if villager.global_position.distance_to(global_position) > 30.0:
			continue
		var state_score := 0.0 if villager.is_dying() else villager.health
		if state_score < worst:
			worst = state_score
			best = villager
	return best


## Scare (and horrify) everyone who saw that.
func _scare_witnesses(radius: float, horror: float) -> void:
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if is_instance_valid(villager) \
				and villager.global_position.distance_to(global_position) < radius:
			villager.scare(global_position)
			villager.witness_horror(horror)


func _cheer_nearby(radius: float, amount: float) -> void:
	for v in get_tree().get_nodes_in_group("villagers"):
		if v.global_position.distance_to(global_position) < radius:
			v.cheer(amount)


## A chosen deed is finished: tell the mind how it FELT. The reward blends the
## deed's own payoff with how the creature's mood actually moved, so outcomes
## it disliked (pain, fright, a bad taste) teach it to stop — that is the whole
## engine of its personality.
func _finish_choice(payoff: float) -> void:
	_deed_verb = _act_verb
	_deed_type = _act_type
	var felt: float = payoff + (mood - _mood_before) / 50.0
	# REMORSE (or relish). A deed also FEELS like what it means to this
	# particular creature: a kind beast is sickened by its own cruelty, a
	# monstrous one savours it. Without this, violence paid a flat thrill every
	# time and became a habit no character could talk it out of — the conscience
	# would steer it away from choosing, then reward it for having chosen.
	var conscience: float = mind.conscience_of(_act_verb) * (REMORSE / CreatureMind.CONSCIENCE)
	felt += conscience
	if conscience < -0.5:
		mood = maxf(mood - 8.0, 0.0)   # it did not like itself for that
		express("sad", 2.0)
	mind.reinforce(clampf(felt, -3.0, 3.0))
	morality = mind.temperament
	_decide()


func _process_play(delta: float) -> void:
	_apply_root_motion()
	_action_time -= delta
	_cheer_time -= delta
	if _play_toy != null and is_instance_valid(_play_toy):
		# Gently chase something small and fluffy. It is not amused; you are.
		if _move_toward(_play_toy.global_position, WALK_SPEED * 0.95, delta):
			_play_toy.scare(global_position)
	else:
		# No toy? Dance. Spin on the spot near whoever will watch.
		_apply_gravity_only(delta)
		rotate_y(delta * 4.0)
		if _animator == null:
			_body.position.y = absf(sin(_walk_phase)) * 0.3
		_walk_phase += delta * 10.0
	if _cheer_time <= 0.0:
		_cheer_time = 1.5
		for v in get_tree().get_nodes_in_group("villagers"):
			if v.global_position.distance_to(global_position) < 9.0:
				v.cheer(1.5)
	if _action_time <= 0.0:
		_finish_deed("play", 12.0)


func _process_guard(delta: float) -> void:
	if not GameState.is_night() or energy < 20.0:
		_finish_deed("guard", 3.0)
		return
	var wolf := CreatureEyes.nearest_wolf(get_tree(), global_position, 18.0)
	if wolf != null:
		if _move_toward(wolf.global_position, WALK_SPEED * 1.2, delta):
			wolf.scare(global_position)
			SoundBank.play_at("bark", global_position, 2.0, 0.3)  # a deep warning woof
			mood = minf(mood + 3.0, 100.0)
		return
	if _move_toward(_target, WALK_SPEED * 0.6, delta):
		_pick_guard_waypoint()
	_action_time -= delta
	if _action_time <= 0.0:
		_finish_deed("guard", 3.0)


func _pick_guard_waypoint() -> void:
	var village := get_tree().get_first_node_in_group("village") as Village
	if village == null:
		_target = global_position
		return
	var angle := randf() * TAU
	_target = village.global_position \
		+ Vector3(cos(angle), 0, sin(angle)) * village.influence_radius * 0.8


## Deeds of appetite and malice ----------------------------------------------

func _consume_food_target() -> void:
	if _target_food is Corpse:
		mind.judge(-0.60)
		morality = mind.temperament
		GameState.announce("Your creature feeds on the dead. The villagers pretend not to see.")
		_swallow_units(1.6)
		_last_deed = "mischief"
	else:
		_swallow_units(1.5)
		_last_deed = "eat"
	_target_food.queue_free()
	_target_food = null
	state = State.EATING
	_action_time = 1.5


func _devour_villager(victim: Villager) -> void:
	var victim_name := victim.villager_name
	# Eating people is the fastest way to make a village hate you enough to
	# arm itself against your creature.
	if victim.village != null and is_instance_valid(victim.village):
		victim.village.raise_alarm(global_position, true)
		victim.village.grudge = minf(victim.village.grudge + 30.0, 100.0)
	victim.queue_free()
	_swallow_units(3.0)
	mind.judge(-1.00)
	morality = mind.temperament
	_last_deed = "hunt"
	GameState.announce("Your creature has eaten %s. The village will not forget this." % victim_name)
	var village := get_tree().get_first_node_in_group("village") as Village
	if village != null:
		village.change_belief(4.0)  # terror is still proof of the divine
		for v in get_tree().get_nodes_in_group("villagers"):
			var onlooker := v as Villager
			if onlooker.global_position.distance_to(global_position) < 15.0:
				onlooker.scare(global_position)
				onlooker.witness_horror(4.0)


## Training: the hand that pets and the hand that scolds ---------------------

## P while the hand is near: reinforce the last deed. Praising cruelty is
## how monsters are made — the creature learns what YOU reward.
func praise() -> void:
	bond = minf(bond + 4.0, 100.0)
	mood = minf(mood + 12.0, 100.0)
	# Kindness is what buys the right to be listened to.
	earn_trust(5.0)
	attention = minf(attention + 8.0, 100.0)
	if _last_deed == "catch":
		catch_skill = clampf(catch_skill + 0.25, 0.1, 2.5)
	express("love")
	mind.experience("praised", 2.0)
	# THE STRONGEST LESSON: your approval teaches the mind that whatever it just
	# did is worth doing. Praise cruelty and it learns to be cruel.
	# Judge the deed it actually FINISHED, not whatever it has wandered off to
	# start since — otherwise your approval lands on the wrong lesson entirely.
	if _deed_verb != "":
		mind.teach(_deed_verb, _deed_type, 3.0)
		# Approval endorses the deed's own moral weight, hard — but still as a
		# pull toward the character it implies, never a free run to sainthood.
		mind.judge(CreatureMind.VERB_VALENCE.get(_deed_verb, 0.0), 0.25, false)
		morality = mind.temperament
	if _last_deed in ["hunt", "mischief", "smash"]:
		GameState.announce("Your creature purrs. It believes cruelty pleases you.")
	else:
		GameState.announce("Your creature purrs and leans into your hand.")


## L while the hand is near: discourage the last deed.
func scold() -> void:
	bond = maxf(bond - 2.0, 0.0)
	mood = maxf(mood - 14.0, 0.0)
	if _last_deed == "catch":
		catch_skill = clampf(catch_skill - 0.3, 0.1, 2.5)
	# Your disapproval teaches the mind that deed is not worth repeating.
	mind.experience("scolded", -2.0)
	# Likewise: scolding must land on the deed it just did. A scolding is
	# emphatic — one telling-off genuinely shifts what it believes.
	if _deed_verb != "":
		mind.teach(_deed_verb, _deed_type, -3.0)
		# Disapproval pushes its heart the OPPOSITE way from the deed's weight.
		mind.judge(-CreatureMind.VERB_VALENCE.get(_deed_verb, 0.0), 0.22, false)
		morality = mind.temperament
	# WAS IT FAIR? A telling-off for something genuinely cruel is a correction,
	# and the creature takes it. A telling-off for lounging in the sun, dancing
	# for the village or hauling grain home is simply a god being cruel, and it
	# costs you exactly what cruelty should. This is the whole of how a player
	# becomes someone their creature stops believing.
	var deserved: float = CreatureMind.VERB_VALENCE.get(_deed_verb, 0.0)
	if deserved < -0.3:
		earn_trust(-0.5)   # it knows what it did
	else:
		earn_trust(-7.0 + deserved * 4.0, "blamed")
	if _last_deed in ["hunt", "mischief", "smash"]:
		GameState.announce("Your creature cowers. It understands that was wrong.")
	elif trust < 30.0:
		GameState.announce(
			"Your creature flinches from your hand. It no longer believes you are fair.")
	else:
		GameState.announce("Your creature whimpers, confused. It was only trying to help.")
	express("hurt", 2.4)
	state = State.SULK
	_action_time = 8.0


func witness(weight: float) -> void:
	# Seeing its god act shifts the creature's own heart, and colours what it
	# believes violence is worth — the lesson generalises to its own choices.
	mind.observe_god(weight)
	morality = mind.temperament
	if weight < 0.0:
		for t: String in ["villager", "house"]:
			mind.teach("smash", t, -weight * 0.35)
	boredom = maxf(boredom - 5.0, 0.0)
	# Wrath thrills a dark heart and frightens a gentle one.
	if weight < 0.0:
		mood = clampf(mood + (5.0 if morality < -20.0 else -6.0), 0.0, 100.0)


## Body ----------------------------------------------------------------------

## Growth is EARNED BY DIGESTION now, a little at a time, rather than jumping
## whenever a meal is swallowed.
func _grow_by(amount: float) -> void:
	if growth < 1.0:
		var before := int(growth * 10.0)
		growth = minf(growth + amount, 1.0)
		scale = Vector3.ONE * lerpf(MIN_SCALE, MAX_SCALE, growth)
		# A quiet word when it visibly grows (each 10% of its arc) — no
		# numbers on screen; you watch it get bigger.
		if int(growth * 10.0) > before:
			GameState.announce("Your creature grows a little larger.")


func _move_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < 1.0:
		_apply_gravity_only(delta)
		_wedge_time = 0.0
		return true
	var dir := to_target.normalized()
	# Steer around trees and rocks (not the one it's heading for). The avoid
	# radius tracks the creature's ACTUAL size (its collider is 0.6 * scale) so
	# a grown beast swerves wide around groves instead of ramming the trunks.
	# skip_trees: the creature wades straight THROUGH groves (shoving them aside,
	# see _sway_trees), steering only around solid rock.
	dir = NavField.steer(global_position, dir, 0.6 * scale.x + 0.4, target, true)
	# The creature WADES: water is passable but slow — half speed with
	# its legs in the lake. (A future miracle will let it walk ON water.)
	if not walks_on_water:
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null and world.is_underwater(global_position.x, global_position.z):
			speed *= 0.5
	var before := global_position
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y -= GRAVITY * delta
	move_and_slide()
	# Wedged? If it's pushing but barely advancing, RELAX the drive so a
	# giant collider stops grinding into the trunks (the source of the jank
	# and the physics-contact lag); the watchdog re-decides shortly after.
	var advanced := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if is_on_wall() and advanced < speed * delta * 0.3:
		_wedge_time += delta
		if _wedge_time > 0.35:
			velocity.x = 0.0  # stop shoving the trunk (kills the jank and lag)
			velocity.z = 0.0
	else:
		_wedge_time = 0.0
	# Body faces +Z; look_at aims -Z. Look away from travel to face it.
	look_at(global_position - Vector3(dir.x, 0, dir.z), Vector3.UP)
	_walk_phase += delta * 9.0
	# Moving under its own power is exercise — more so while carrying something.
	body.exert(0.25 if _carried == null else 0.7, delta)
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
	elif state != State.SLEEPING and state != State.PLAY:
		_body.position.y = lerpf(_body.position.y, 0.0, 0.2)
		_body.rotation_degrees.z = lerpf(_body.rotation_degrees.z, 0.0, 0.2)


## A miracle lifts the beast into the air for a while. Cast it again to top up.
func grant_flight(seconds: float) -> void:
	flight_time = maxf(flight_time, seconds)
	walks_on_water = true
	express("happy")
	GameState.announce("Your creature takes to the air!")


## Order it to a spot (the hand's ground point). It drops what it is doing.
func leash_to(pos: Vector3) -> void:
	# A creature that has walked away from you does not come when called. This
	# is the one command it will refuse, and it refuses it until amends are made.
	if exiled:
		GameState.announce("Your creature looks at your hand, and does not come.")
		express("sad", 2.0)
		return
	leash_target = pos
	if _carried != null:
		_release_carried(true)
	state = State.LEASHED
	express("curious")
	attention = minf(attention + 25.0, 100.0)


func release_leash() -> void:
	if leash_target == Vector3.INF:
		return
	leash_target = Vector3.INF
	if state == State.LEASHED:
		_decide()


func is_leashed() -> bool:
	return leash_target != Vector3.INF


## Walk to where it was sent and wait there. It stays put (drifting a little)
## until you release it, so you can post it somewhere and leave it.
func _process_leashed(delta: float) -> void:
	if leash_target == Vector3.INF:
		_decide()
		return
	if global_position.distance_to(leash_target) > 3.0:
		_move_toward(leash_target, _run_speed() * 0.9, delta)
		return
	_apply_gravity_only(delta)
	_action_time -= delta
	if _action_time <= 0.0:
		_action_time = 3.0
		# Waiting where it was told, but still watching the world go by.
		_observe_world()


## The quiet life ---------------------------------------------------------------
##
## None of what follows advances anything. That is the point: a world where
## every act is a move in a game leaves the player managing a creature instead
## of keeping one. These are the things it does when nothing is wrong.


## LOUNGING. Sprawled out, taking the world in. It genuinely rests here — less
## than sleep, but it is awake, it is looking around, and it is very slowly
## working out what it thinks of the place. A creature that has learned to like
## this is a creature you can just sit and watch.
func _process_lounge(delta: float) -> void:
	_apply_gravity_only(delta)
	_action_time -= delta
	energy = minf(energy + 1.4 * delta, 100.0)
	body.idle(delta)
	# It turns its head to whatever is nearby. This is where its opinions of
	# ordinary things quietly form.
	_look_time -= delta
	if _look_time <= 0.0:
		_look_time = randf_range(2.0, 4.0)
		_observe_world()
		var about := _things_around(20.0)
		if not about.is_empty():
			_face(about[randi() % about.size()].global_position)
	if _action_time <= 0.0:
		_last_deed = "lounge"
		_finish_choice(0.5 + boredom / 300.0)


## DANCING — learned by watching villagers dance, and performed AT them. It is
## a spectacle, and a village that stops to watch its god's creature caper is a
## village warming to you.
func _process_dance(delta: float) -> void:
	_apply_gravity_only(delta)
	_action_time -= delta
	rotation.y += delta * 2.4
	_body.scale.y = 1.0 + sin(Time.get_ticks_msec() / 120.0) * 0.12
	_cheer_time -= delta
	if _cheer_time <= 0.0:
		_cheer_time = 1.0
		_cheer_nearby(18.0, 1.2)
		var village := CreatureEyes.home_village(get_tree())
		if village != null and _audience(18.0) > 0:
			village.change_belief(0.35)
	if _action_time <= 0.0:
		_body.scale.y = 1.0
		body.exert(0.8, 0.4)
		boredom = maxf(boredom - 30.0, 0.0)
		_last_deed = "dance"
		# The bigger the crowd, the better it felt. Nobody watching is a
		# lesson too — it may well decide dancing is not worth the effort.
		_finish_choice(0.4 + _audience(18.0) * 0.35)


## LEADING PRAYER. Sat still, eyes shut, arms out. The villagers at their totem
## pray harder with it there, and the prayer flows to you.
func _process_pray(delta: float) -> void:
	_apply_gravity_only(delta)
	_action_time -= delta
	express("love", 0.6)
	var faithful := 0
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager) or villager.global_position \
				.distance_to(global_position) > 22.0:
			continue
		if villager.is_worshipping():
			faithful += 1
	if faithful > 0:
		GameState.add_prayer_power(faithful * 1.6 * delta)
		var village := CreatureEyes.home_village(get_tree())
		if village != null:
			village.change_belief(0.22 * delta * faithful)
	if _action_time <= 0.0:
		mood = minf(mood + 6.0, 100.0)
		_last_deed = "pray"
		_finish_choice(0.5 + faithful * 0.4)


## HOLDING COURT. It walks into the middle of the village and simply stands
## there being enormous, and the people turn and look. No violence, no miracle,
## no gift — just presence, and belief grows from it.
func _process_commune(delta: float) -> void:
	var village := CreatureEyes.home_village(get_tree())
	if village == null:
		_decide()
		return
	if global_position.distance_to(_target) > village.influence_radius * 0.45:
		_move_toward(_target, WALK_SPEED * 0.8, delta)
		return
	_apply_gravity_only(delta)
	_action_time -= delta
	var audience := _audience(20.0)
	if audience > 0:
		village.change_belief(0.3 * delta * minf(audience, 6))
		village.notice(0.4 * delta)
		_cheer_time -= delta
		if _cheer_time <= 0.0:
			_cheer_time = 2.0
			for v in get_tree().get_nodes_in_group("villagers"):
				var villager := v as Villager
				if is_instance_valid(villager) and villager.global_position \
						.distance_to(global_position) < 20.0:
					villager.attend(global_position)
	if _action_time <= 0.0:
		_last_deed = "commune"
		_finish_choice(0.4 + audience * 0.3)


func _begin_run() -> void:
	state = State.RUN
	_action_time = randf_range(7.0, 14.0)
	var angle := randf() * TAU
	_target = global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(30.0, 60.0)


## RUNNING, for no reason at all — or with something heavy on its back, which
## is how a creature actually builds the muscle to carry bigger things later.
func _process_run(delta: float) -> void:
	_action_time -= delta
	var burden := 1.0 if _carried == null else 2.6
	body.exert(burden, delta)
	energy = maxf(energy - 1.6 * delta * burden, 0.0)
	if _move_toward(_target, _run_speed(), delta) or _action_time <= 0.0:
		if _carried != null:
			_release_carried(true)
		boredom = maxf(boredom - 22.0, 0.0)
		_last_deed = "run"
		_finish_choice(0.45 + (0.3 if burden > 1.5 else 0.0))


## MIMICRY. It follows your hand about and copies what it sees you do. The
## copying itself happens wherever you act (see `witness_god_deed`); this is
## the creature CHOOSING to shadow you so that it sees more of it.
func _process_mimic(delta: float) -> void:
	_action_time -= delta
	if divine_hand == null or not is_instance_valid(divine_hand):
		_decide()
		return
	var hand := divine_hand.global_position
	if global_position.distance_to(hand) > 6.0 + scale.x * 1.5:
		_move_toward(hand, WALK_SPEED * 1.15, delta)
	else:
		_apply_gravity_only(delta)
		_face(hand)
		attention = minf(attention + 9.0 * delta, 100.0)
	if _action_time <= 0.0:
		_last_deed = "mimic"
		# Shadowing a god who is doing nothing is dull; one who is busy is not.
		_finish_choice(0.3 + attention / 160.0)


## KEEPING ITS DISTANCE. Not fear of the world — wariness of YOU.
func _process_shun(delta: float) -> void:
	_action_time -= delta
	if _move_toward(_target, _run_speed() * 0.8, delta) or _action_time <= 0.0:
		_last_deed = "shun"
		_finish_choice(0.35)


## LEAVING. A creature that has stopped trusting you, but has NOT stopped being
## good, walks out of your reach to live by its own lights. It is not gone from
## the world — it is out there, and sustained kindness can still win it back.
func _begin_departure() -> void:
	state = State.DEPART
	_action_time = 45.0
	exiled = true
	grievance_time = 0.0
	var angle := randf() * TAU
	_target = global_position + Vector3(cos(angle), 0, sin(angle)) * 220.0
	release_leash()
	GameState.announce(
		"Your creature turns away from you and walks. It has decided it is better than you.")
	express("sad", 6.0)


## The walk out. After this it simply LIVES out there — see `_tick_exile`.
func _process_depart(delta: float) -> void:
	_action_time -= delta
	body.exert(1.0, delta)
	if _move_toward(_target, _run_speed(), delta) or _action_time <= 0.0:
		_last_deed = "depart"
		_finish_choice(0.6)


## AMENDS. Exile ends only when BOTH are true: it has come to trust you again,
## and the thing it left over has not happened for a good long while. Kindness
## alone will not do it — a god who pets the creature between beatings never
## gets it back, because every beating puts the clock to zero.
func _tick_exile(delta: float) -> void:
	if not exiled:
		return
	grievance_time += delta
	if trust < AMENDS_TRUST or grievance_time < AMENDS_SECONDS:
		return
	exiled = false
	grievance = ""
	mind.experience("forgiven", 1.6)
	express("love", 4.0)
	GameState.announce(
		"Your creature comes back to you of its own accord. You have not done it again.")


## How many people are actually watching it right now. Half the quiet life is
## worth nothing without an audience, and the creature learns that itself.
func _audience(radius: float) -> int:
	var count := 0
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if is_instance_valid(villager) and not villager.is_afraid() \
				and villager.global_position.distance_to(global_position) < radius:
			count += 1
	return count


func _face(point: Vector3) -> void:
	var flat := point - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 0.08)


## Trust and your example -------------------------------------------------------

## Move what it thinks of you. Announced only at the thresholds that actually
## change how it behaves, so the player learns the mechanic by living it.
func earn_trust(amount: float, cause := "") -> void:
	var before := trust
	trust = clampf(trust + amount, 0.0, 100.0)
	# A real injury names itself and restarts the clock. This is what makes
	# exile recoverable only by STOPPING, not by apologising: every repeat of
	# the same treatment puts the reckoning back to the beginning.
	if amount <= -3.0 and cause != "":
		if exiled and cause == grievance:
			GameState.announce(
				"Your creature sees you do it again, and goes further off.")
		grievance = cause
		grievance_time = 0.0
	if before >= 35.0 and trust < 35.0:
		GameState.announce("Your creature has stopped copying you.")
	elif before >= 20.0 and trust < 20.0:
		GameState.announce("Your creature will barely look at you now.")
	elif before < 55.0 and trust >= 55.0 and amount > 0.0:
		GameState.announce("Your creature watches your hand again, and trusts it.")


## YOU DID SOMETHING, AND IT SAW. Every act of your hand in the world is an
## example the creature may take up — what you lift, what you set down kindly,
## what you fling, who you mend. It only learns from what it can actually see,
## and only in proportion to what it thinks of you.
##
## There is deliberately no list here of deeds worth copying. Whatever you do
## with your hands is what you are teaching, and a player who never notices
## that is a player raising a creature in their own image without meaning to.
func witness_god(verb: String, type: String, valence := 0.0) -> void:
	if divine_hand == null or not is_instance_valid(divine_hand):
		return
	# Out of sight, out of mind: it copies what it WATCHES, not what you do
	# across the map. Attention widens how far that reaches.
	var reach := 24.0 + attention * 0.3 + scale.x * 1.5
	if divine_hand.global_position.distance_to(global_position) > reach:
		return
	mind.witness_god_deed(verb, type, trust)
	attention = minf(attention + 4.0, 100.0)
	# It also reads your character off your conduct, faintly — this is the same
	# slow channel that watching your miracles uses.
	if valence != 0.0:
		mind.observe_god(valence * clampf(trust / 100.0, 0.0, 1.0))
		morality = mind.temperament


## A miracle lends it a giant's grip for a while — enough to uproot trees far
## beyond what its own muscle could manage.
func grant_strength(seconds: float) -> void:
	body.boost_time = maxf(body.boost_time, seconds)
	express("angry", 1.5)   # a roar of borrowed power
	GameState.announce("Your creature swells with borrowed might!")


## Can it actually lift this? A sapling needs little; a forest giant needs real
## muscle — earned by work, or lent by the Strength miracle.
func can_lift(thing: Node3D) -> bool:
	if thing is WildTree:
		return (thing as WildTree).lumber <= body.lift_limit(growth)
	return true


func is_flying() -> bool:
	return flight_time > 0.0


## While aloft the body rises off the terrain and drifts; when the miracle runs
## out it settles back down to walking.
func _tick_flight(delta: float) -> void:
	var want := 0.0
	if flight_time > 0.0:
		flight_time -= delta
		want = 9.0 + scale.y * 1.5
		if flight_time <= 0.0:
			walks_on_water = false
			GameState.announce("Your creature sinks back to the earth.")
	_fly_height = lerpf(_fly_height, want, minf(delta * 1.6, 1.0))
	if _fly_height > 0.05:
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null:
			var ground := maxf(
				world.height_at(global_position.x, global_position.z), WorldGen.WATER_LEVEL)
			global_position.y = ground + _fly_height
			velocity.y = 0.0


## Put a meal in the stomach. A small body simply cannot finish a big animal —
## whatever will not fit is left, and it must digest before eating again.
func _swallow_units(units: float) -> void:
	var taken := body.swallow(units, growth)
	if taken < units * 0.6:
		GameState.announce("Your creature's belly is full — it leaves the rest.")
	# Eating when it was not hungry is exactly how a creature gets fat, and the
	# body books that during digestion.
	mood = minf(mood + 4.0, 100.0)


## Has it room (and appetite) for a meal of roughly this size?
func _can_eat(units: float) -> bool:
	return body.has_room_for(units, growth)


## Pain: the creature has no health bar, but it FEELS being hurt — fright rises,
## mood drops, and the mind learns that whatever it was just doing hurt. Enough
## of that near people and it may become a nervous recluse.
func take_damage(amount: float, _by_god := false, _instant := false) -> void:
	# It works out for ITSELF what brought this on — no rule tells it that
	# being beaten follows from eating people.
	mind.experience("hurt", -clampf(amount / 25.0, 0.3, 2.0))
	# Being hurt BY YOUR OWN GOD is a different wound entirely. Nothing else in
	# the game costs trust this fast, and nothing should.
	if _by_god:
		earn_trust(-clampf(amount * 0.5, 4.0, 30.0), "struck")
	fear = minf(fear + amount * 0.8, 100.0)
	mood = maxf(mood - amount * 0.4, 0.0)
	express("hurt", 2.0)
	if _act_verb != "":
		mind.teach(_act_verb, _act_type, -1.2)
	if fear > 60.0 and state != State.FLEE:
		_decide()


func receive_heal() -> void:
	energy = minf(energy + 40.0, 100.0)
	mood = minf(mood + 10.0, 100.0)
	earn_trust(6.0)
	express("love")


## Appearance & expression ---------------------------------------------------

## Flash an emotion for a moment. It shapes the procedural eyes and drives a
## model's "expression" instance shader param; then it settles to neutral.
func express(emotion: String, dur := 1.6) -> void:
	_expression = emotion
	_expr_time = dur


## The hide and eyes reflect the soul (see CreatureLook). Throttled to changes.
func _apply_appearance() -> void:
	var align := clampf(morality / 100.0, -1.0, 1.0)
	if absf(align - _shown_align) < 0.02:
		return
	_shown_align = align
	CreatureLook.apply_alignment(align, _fur_mat, _pupils, _model_meshes)


func _tick_expression(delta: float) -> void:
	if _expr_time > 0.0:
		_expr_time -= delta
		if _expr_time <= 0.0:
			_expression = "neutral"
	CreatureLook.apply_expression(_expression, delta, _eyes, _model_meshes)


## Apply this frame's ROOT MOTION from a one-shot action clip (a lunge into a
## kick, a hop while playing), rotated into world space and kept planar. A
## no-op unless the model's AnimationPlayer has a root_motion_track set, so it
## never disturbs ordinary game-driven movement.
func _apply_root_motion() -> void:
	if _animator == null:
		return
	var delta_pos := _animator.root_motion()
	if delta_pos == Vector3.ZERO:
		return
	var world := global_transform.basis * delta_pos
	global_position += Vector3(world.x, 0.0, world.z)


## Words ----------------------------------------------------------------------

func state_name() -> String:
	return State.keys()[state]


## A plain-language phrase for what it is doing right now (for the HUD's
## creature dashboard). Public wrapper over the internal status word.
func activity_word() -> String:
	return _status_word()


## The semantic clip a rigged model plays for the current state. Missing clips
## are ignored, so a model with only walk/idle still animates sensibly.
## The semantic clip a rigged model plays for the current state.
func _anim_state() -> String:
	return CreatureLook.anim_for(
		state_name(), Vector2(velocity.x, velocity.z).length() > 0.3)


func _status_word() -> String:
	return CreatureLook.doing_word(state_name(), _carry_intent, _cargo_word())


func _status_text() -> String:
	return CreatureLook.says_word(state_name(), _carry_intent)


## Whatever it is holding or heading for, named honestly — lumber and stone,
## not "food" for everything. Empty when its hands are free.
func _cargo_word() -> String:
	if state == State.GO_GATHER:
		return _carriable_word(_target_food)
	if _carried != null and is_instance_valid(_carried):
		return _carriable_word(_carried)
	return ""


func morality_word() -> String:
	return CreatureLook.morality_word(morality)


func mood_word() -> String:
	return CreatureLook.mood_word(mood)


## What it most wants to do, straight from what it has actually learned —
## there is no second table of wants any more.
func favorite_deed() -> String:
	return mind.strongest_urge()


func hover_text() -> String:
	return ("Your creature — %s (%s, %s)\n" +
		"bond %d · trusts you %d · attention %d\n" +
		"hunger %d · energy %d · %s\n" +
		"[P — pet   ·   L — scold   ·   C — lock camera]") % [
		_status_word(), morality_word(), mood_word(),
		int(bond), int(trust), int(attention),
		int(hunger), int(energy), favorite_deed()]


## What to call the thing it's hauling — honest about lumber and stone,
## not "food" for everything.
## Variant (not Node3D): the carried/targeted item may have been freed between
## the creature's physics tick and a HUD read, and passing a freed object to a
## typed parameter crashes. Guard it here instead.
func _carriable_word(item: Variant) -> String:
	if not is_instance_valid(item):
		return "food"
	if item is ResourceItem:
		return (item as ResourceItem).kind
	if item is WildTree:
		return "timber"
	return "food"


func to_dict() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"growth": growth,
		"hunger": hunger,
		"energy": energy,
		"mood": mood,
		"bond": bond,
		"trust": trust,
		"exiled": exiled,
		"grievance": grievance,
		"grievance_time": grievance_time,
		"catch_skill": catch_skill,
		"boredom": boredom,
		"fear": fear,
		"attention": attention,
		"walks_on_water": walks_on_water,
		"flight": flight_time,
		"inedible": _inedible.duplicate(),
		"mind": mind.to_dict(),
		"body": body.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	var p: Array = data.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	growth = float(data.get("growth", 0.01))
	hunger = float(data.get("hunger", 40.0))
	energy = float(data.get("energy", 90.0))
	mood = float(data.get("mood", 60.0))
	bond = float(data.get("bond", 20.0))
	trust = float(data.get("trust", 55.0))
	exiled = bool(data.get("exiled", false))
	grievance = String(data.get("grievance", ""))
	grievance_time = float(data.get("grievance_time", 0.0))
	catch_skill = float(data.get("catch_skill", 0.3))
	boredom = float(data.get("boredom", 20.0))
	fear = float(data.get("fear", 0.0))
	attention = float(data.get("attention", 20.0))
	walks_on_water = bool(data.get("walks_on_water", false))
	flight_time = float(data.get("flight", 0.0))
	_inedible = (data.get("inedible", {}) as Dictionary).duplicate()
	mind.from_dict(data.get("mind", {}))
	body.from_dict(data.get("body", {}))
	morality = mind.temperament
	scale = Vector3.ONE * lerpf(MIN_SCALE, MAX_SCALE, growth)
	_shown_align = 999.0   # force the hide/eyes to re-colour for the restored soul

