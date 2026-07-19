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
	STALK_PREY, WATCH, GO_GATHER, CARRYING, PLAY, GUARD, SULK, CATCH,
	GO_FISH, FISHING, GO_STORE,
}

const WALK_SPEED := 3.5
const GRAVITY := 20.0
## The growth arc: at 1% grown the creature stands about twice a villager's
## height; at 100% it towers over the tallest trees.
const MIN_SCALE := 1.1
const MAX_SCALE := 4.2
const GROWTH_PER_MEAL := 0.015
const STUCK_SECONDS := 30.0   # no state may hold the creature hostage
const OBSERVE_PERIOD := 2.5

var hunger := 40.0
var energy := 90.0
var growth := 0.01            # 0..1 of its destined size; every game starts small
var walks_on_water := false   # granted by a future miracle buff

## Feelings. Mood is the weather of its heart; bond is trust in your hand;
## boredom is the itch that play and curiosity scratch.
var mood := 60.0     # 0 wretched .. 100 delighted
var bond := 20.0     # 0 stranger .. 100 devoted
var boredom := 20.0

## Independent karma: -100 monstrous .. +100 angelic.
var morality := 0.0

## What the creature WANTS, learned by watching and by your praise/scolding.
## These weights multiply into every decision it makes.
var desires := {
	"tend": 0.6, "gather": 0.6, "play": 0.9, "watch": 1.1,
	"guard": 0.5, "mischief": 0.35, "fish": 0.7, "catch": 0.3,
}

## ATTENTION: how closely it is watching your hand right now. Handing it
## things raises it (innate); it decays with neglect. Catching a thrown
## object requires attention — and catch skill grows when you praise it.
var attention := 20.0
var divine_hand: DivineHand = null  # wired by main

var state := State.IDLE
var _last_deed := ""  # the deed a pet or scolding will be credited to
var _target := Vector3.ZERO
var _target_food: Node3D = null      # FoodItem or Corpse
var _target_prey: Node3D = null      # Villager or livestock Animal
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
		State.STALK_PREY:
			_process_stalk(delta)
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
			var farm := _nearest_farm()
			if farm != null:
				farm.tend()
			if _action_time <= 0.0:
				_finish_deed("tend", 4.0)
		State.SLEEPING:
			_apply_gravity_only(delta)
			energy = minf(energy + 6.0 * delta, 100.0)
			_body.rotation_degrees.z = 80
			if energy > 85.0:
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
			_body.rotation_degrees.x = sin(Time.get_ticks_msec() / 300.0) * 10.0
			if _action_time <= 0.0:
				_body.rotation_degrees.x = 0
				_land_a_fish()
		State.GO_STORE:
			var store := _nearest_store()
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

	_observe_time -= delta
	if _observe_time <= 0.0:
		_observe_time = OBSERVE_PERIOD
		_observe_world()

	_try_catch_throw()

	# Whatever the claws hold rides along, up at the shoulder.
	if _carried != null:
		if is_instance_valid(_carried):
			_carried.global_position = global_position + Vector3.UP * (1.5 * scale.y) \
				+ global_transform.basis.z.normalized() * (0.9 * scale.x)
		else:
			_carried = null

	_animate_waddle(delta)
	var status := _status_text()
	if _label.text != status:
		_label.text = status


## Feelings drift every frame: hunger gnaws, idleness bores, mood follows.
func _tick_feelings(delta: float) -> void:
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
	attention = maxf(attention - 0.6 * delta, 0.0)


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
	# Fell out of the world (chunk streamed away) or buried in a hillside
	# (bad spawn, collision hiccup)? Pop back to the surface.
	if global_position.y < -12.0 or fmod(_state_time, 3.0) < delta:
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null:
			var h := world.height_at(global_position.x, global_position.z)
			if global_position.y < h - 1.2:
				global_position.y = h + 0.5
				velocity = Vector3.ZERO


## The slow gaze: passively learn from whatever is happening nearby.
func _observe_world() -> void:
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		if villager.global_position.distance_to(global_position) > 14.0:
			continue
		match villager.state:
			Villager.State.FARMING:
				_bump_desire("tend", 0.01)
			Villager.State.FISHING:
				_bump_desire("fish", 0.012)
			Villager.State.BUILDING, Villager.State.CHOPPING, Villager.State.QUARRYING:
				_bump_desire("gather", 0.008)
	if GameState.is_night():
		for a in get_tree().get_nodes_in_group("animals"):
			var animal := a as Animal
			if is_instance_valid(animal) and animal.species == "wolf" \
					and animal.global_position.distance_to(global_position) < 25.0:
				_bump_desire("guard", 0.05)


func _bump_desire(key: String, amount: float) -> void:
	desires[key] = clampf(desires[key] + amount, 0.1, 2.5)


## Decision-making: needs first, then a weighted draw from its desires,
## colored by mood, boredom, bond, and morality.
func _decide() -> void:
	# A watchdog abort mid-carry sets the cargo down, never drops it forever.
	if _carried != null:
		_release_carried(true)
	_last_deed = ""
	if energy < 15.0:
		state = State.SLEEPING
		return
	if hunger > 55.0 and _plan_food():
		return
	if GameState.is_night():
		if morality > 0.0 and energy > 40.0 and desires["guard"] * (0.5 + bond / 100.0) > 0.6:
			state = State.GUARD
			_action_time = randf_range(10.0, 18.0)
			_pick_guard_waypoint()
			return
		if energy < 85.0:
			state = State.SLEEPING
			return

	var pool := {}
	if morality > 10.0 and _nearest_farm() != null:
		pool["tend"] = desires["tend"] * (1.0 + morality / 100.0)
	if _nearest_carriable(35.0) != null:
		pool["gather"] = desires["gather"] * (1.0 + maxf(morality, 0.0) / 100.0)
	if _find_working_villager() != null:
		pool["watch"] = desires["watch"] * (0.6 + boredom / 100.0)
	pool["play"] = desires["play"] * (0.3 + mood / 150.0 + boredom / 100.0)
	if morality > 20.0 and _home_village() != null \
			and _home_village().tamed_count() < Village.MAX_TAMED \
			and _nearest_giftable() != null:
		pool["gift"] = desires["gather"] * 0.8
	pool["fish"] = desires["fish"] * 0.5  # fishing for the fun of it
	# Logging: uproot a tree smaller than itself and haul it home whole.
	if morality > 0.0 and _home_village() != null \
			and _home_village().store.lumber < 8 and _nearest_uprootable_tree() != null:
		pool["logging"] = desires["gather"] * 0.7
	if morality < 10.0:
		pool["mischief"] = desires["mischief"] * (1.0 - morality / 100.0) * (boredom / 60.0)
	pool["wander"] = 0.7

	match _weighted_pick(pool):
		"tend":
			state = State.GO_TEND
			_target = _nearest_farm().global_position
		"gather":
			_target_food = _nearest_carriable(35.0)
			state = State.GO_GATHER
		"watch":
			_watch_subject = _find_working_villager()
			state = State.WATCH
			_action_time = randf_range(5.0, 8.0)
		"play":
			state = State.PLAY
			_action_time = randf_range(6.0, 10.0)
			_play_toy = _find_toy()
		"gift":
			_catch_target = _nearest_giftable()
			_carry_intent = "gift"
			state = State.CATCH
		"fish":
			var shore := _find_shore()
			if shore != Vector3.INF:
				_target = shore
				state = State.GO_FISH
			else:
				_wander()
		"logging":
			_catch_target = _nearest_uprootable_tree()
			_carry_intent = "deliver"
			state = State.CATCH
		"mischief":
			# Half the time a lunge and a roar; half the time it MAKES OFF
			# with someone, carries them a way, and sets them down shaking.
			if randf() < 0.5:
				_target_prey = _nearest_villager()
				if _target_prey != null:
					state = State.STALK_PREY
				else:
					_wander()
			else:
				_catch_target = _nearest_villager()
				if _catch_target != null:
					_carry_intent = "snatch"
					state = State.CATCH
					var angle := randf() * TAU
					_target = global_position + Vector3(cos(angle), 0, sin(angle)) * 12.0
				else:
					_wander()
		_:
			_wander()


func _wander() -> void:
	state = State.WANDER
	var angle := randf() * TAU
	var dist := randf_range(4.0, 18.0)
	_target = Vector3(cos(angle) * dist, 0, sin(angle) * dist)


func _weighted_pick(pool: Dictionary) -> String:
	var total := 0.0
	for key: String in pool:
		total += maxf(pool[key], 0.0)
	if total <= 0.0:
		return "wander"
	var roll := randf() * total
	for key: String in pool:
		roll -= maxf(pool[key], 0.0)
		if roll <= 0.0:
			return key
	return "wander"


## Hunger: ground food first; a fallen creature raids the pens; a monster
## looks at the villagers themselves.
func _plan_food() -> bool:
	if morality < -30.0 and hunger > 75.0:
		_target_prey = _nearest_villager()
		if _target_prey != null:
			state = State.STALK_PREY
			GameState.announce("Your creature's eyes settle on the villagers. It is hungry.")
			return true
	if morality < -10.0 and hunger > 65.0:
		var livestock := _nearest_livestock()
		if livestock != null:
			_target_prey = livestock
			state = State.STALK_PREY
			return true
	_target_food = _nearest_food()
	if _target_food != null:
		state = State.SEEK_FOOD
		return true
	# Nothing lying around? Catch dinner. (Skipping whatever it has
	# learned, one bad taste at a time, that it cannot eat.)
	var quarry := _nearest_catchable()
	if quarry != null:
		_catch_target = quarry
		_carry_intent = "eat"
		state = State.CATCH
		return true
	# Or fish for it — the gentle hunter's option.
	var shore := _find_shore()
	if shore != Vector3.INF:
		_target = shore
		state = State.GO_FISH
		return true
	# Last resort: raid the granary. The villagers notice.
	var store := _nearest_store()
	if store != null and store.total_food() > 0:
		state = State.GO_STORE
		return true
	return false


## A deed is done: remember it (for praise/scolding), feel it, move on.
func _finish_deed(deed: String, mood_gain: float) -> void:
	_last_deed = deed
	mood = minf(mood + mood_gain, 100.0)
	boredom = maxf(boredom - 25.0, 0.0)
	if deed in ["tend", "gather", "guard", "gift", "fish"]:
		morality = clampf(morality + 1.0, -100.0, 100.0)
	_decide()


## State processors ----------------------------------------------------------

func _process_seek_food(delta: float) -> void:
	if _target_food == null or not is_instance_valid(_target_food) \
			or _target_food.is_queued_for_deletion():
		_target_food = null
		_decide()
	elif _move_toward(_target_food.global_position, WALK_SPEED, delta):
		_consume_food_target()


func _process_stalk(delta: float) -> void:
	if _target_prey == null or not is_instance_valid(_target_prey) \
			or _target_prey.is_queued_for_deletion():
		_target_prey = null
		_decide()
	elif _move_toward(_target_prey.global_position, WALK_SPEED * 1.15, delta):
		if hunger > 55.0:
			_devour_prey()
		else:
			_spook_prey()


func _process_watch(delta: float) -> void:
	if _watch_subject == null or not is_instance_valid(_watch_subject) \
			or not _is_working(_watch_subject):
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


## Watching a job long enough plants the desire to help with it.
func _learn_from(watched_state: Villager.State) -> void:
	match watched_state:
		Villager.State.FARMING:
			_bump_desire("tend", 0.15)
		Villager.State.BUILDING, Villager.State.CHOPPING, Villager.State.QUARRYING:
			_bump_desire("gather", 0.1)
		_:
			_bump_desire("watch", 0.05)


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
	var skill := clampf(desires["catch"] * 0.55, 0.12, 0.95)
	if randf() > skill:
		GameState.announce("Your creature lunged... and fumbled the catch. Practice.")
		mood = maxf(mood - 2.0, 0.0)
		return
	_pick_up_thing(thrown, _intent_for(thrown))
	_last_deed = "catch"
	mood = minf(mood + 10.0, 100.0)
	bond = minf(bond + 2.0, 100.0)
	attention = minf(attention + 10.0, 100.0)
	GameState.announce("Your creature CAUGHT it! It looks extremely pleased with itself.")


## Handing the creature something is innate — it always accepts, and it
## teaches it to watch your hand (attention up, bond up).
func receive_gift(item: Node3D) -> void:
	if _carried != null:
		_release_carried(true)
	attention = minf(attention + 15.0, 100.0)
	bond = minf(bond + 2.0, 100.0)
	mood = minf(mood + 6.0, 100.0)
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
	return WALK_SPEED * (1.1 + growth * 0.9)


func _pick_up_thing(node: Node3D, intent: String) -> void:
	_carried = node
	_carry_intent = intent
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	elif node.has_method("pick_up"):
		node.call("pick_up")
	state = State.CARRYING
	_action_time = 1.8 if intent == "eat" else 5.0


func _process_carrying(delta: float) -> void:
	if _carried == null or not is_instance_valid(_carried):
		_carried = null
		_decide()
		return
	match _carry_intent:
		"deliver":
			var store := _nearest_store()
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
			var village := _home_village()
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
				morality = clampf(morality - 1.0, -100.0, 100.0)
				mood = minf(mood + 6.0, 100.0)
				_release_carried(false)
				_last_deed = "mischief"
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
		hunger = maxf(hunger - FoodItem.NUTRITION, 0.0)
		morality = clampf(morality - 0.5, -100.0, 100.0)  # that was somebody's dinner
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
		morality = clampf(morality - 3.0, -100.0, 100.0)
		GameState.announce("Your creature has eaten a penned %s. The herders grieve." % animal.species)
	elif animal.spec.get("predator", false):
		morality = clampf(morality + 1.0, -100.0, 100.0)  # culling wolves is a service
	else:
		morality = clampf(morality - 0.5, -100.0, 100.0)
	hunger = maxf(hunger - (30.0 + animal.meat_yield() * 10.0), 0.0)
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


func _process_play(delta: float) -> void:
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
	var wolf := _nearest_wolf(18.0)
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
		morality = clampf(morality - 3.0, -100.0, 100.0)
		GameState.announce("Your creature feeds on the dead. The villagers pretend not to see.")
		hunger = maxf(hunger - 50.0, 0.0)
		_last_deed = "mischief"
	else:
		hunger = maxf(hunger - FoodItem.NUTRITION * 1.5, 0.0)
		_last_deed = "eat"
	_target_food.queue_free()
	_target_food = null
	state = State.EATING
	_action_time = 1.5


func _devour_prey() -> void:
	if is_instance_valid(_target_prey):
		if _target_prey is Villager:
			_devour_villager(_target_prey as Villager)
		elif _target_prey is Animal:
			var animal := _target_prey as Animal
			hunger = maxf(hunger - 55.0, 0.0)
			morality = clampf(morality - 2.0, -100.0, 100.0)
			GameState.announce("Your creature has eaten a penned %s. The herders grieve." % animal.species)
			animal.die(false)
			_last_deed = "hunt"
	_target_prey = null
	state = State.EATING
	_action_time = 2.0


func _devour_villager(victim: Villager) -> void:
	var victim_name := victim.villager_name
	victim.queue_free()
	hunger = maxf(hunger - 70.0, 0.0)
	morality = clampf(morality - 5.0, -100.0, 100.0)
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


## Not hungry, just mean: a lunge and a roar, no teeth.
func _spook_prey() -> void:
	if _target_prey is Villager and is_instance_valid(_target_prey):
		(_target_prey as Villager).scare(global_position)
		morality = clampf(morality - 1.0, -100.0, 100.0)
		mood = minf(mood + 6.0, 100.0)
		boredom = maxf(boredom - 20.0, 0.0)
		_last_deed = "mischief"
	_target_prey = null
	state = State.IDLE
	_action_time = 2.0


## Training: the hand that pets and the hand that scolds ---------------------

## P while the hand is near: reinforce the last deed. Praising cruelty is
## how monsters are made — the creature learns what YOU reward.
func praise() -> void:
	bond = minf(bond + 4.0, 100.0)
	mood = minf(mood + 12.0, 100.0)
	attention = minf(attention + 8.0, 100.0)
	var key := _deed_desire_key(_last_deed)
	if key != "":
		_bump_desire(key, 0.25)
	if _last_deed in ["hunt", "mischief"]:
		morality = clampf(morality - 3.0, -100.0, 100.0)
		GameState.announce("Your creature purrs. It believes cruelty pleases you.")
	else:
		morality = clampf(morality + 1.0, -100.0, 100.0)
		GameState.announce("Your creature purrs and leans into your hand.")


## L while the hand is near: discourage the last deed.
func scold() -> void:
	bond = maxf(bond - 2.0, 0.0)
	mood = maxf(mood - 14.0, 0.0)
	var key := _deed_desire_key(_last_deed)
	if key != "":
		desires[key] = clampf(desires[key] - 0.3, 0.1, 2.5)
	if _last_deed in ["hunt", "mischief"]:
		morality = clampf(morality + 2.0, -100.0, 100.0)
		GameState.announce("Your creature cowers. It understands that was wrong.")
	else:
		GameState.announce("Your creature whimpers, confused. It was only trying to help.")
	state = State.SULK
	_action_time = 8.0


func _deed_desire_key(deed: String) -> String:
	match deed:
		"tend", "gather", "play", "watch", "guard", "mischief", "fish", "catch":
			return deed
		"gift":
			return "gather"
		"receive":
			return "catch"  # praised for accepting = learns to watch the hand
		"hunt":
			return "mischief"
	return ""


## The creature learns right and wrong from watching its god at work.
func witness(weight: float) -> void:
	morality = clampf(morality + weight, -100.0, 100.0)
	boredom = maxf(boredom - 5.0, 0.0)
	# Wrath thrills a dark heart and frightens a gentle one.
	if weight < 0.0:
		mood = clampf(mood + (5.0 if morality < -20.0 else -6.0), 0.0, 100.0)


## Target finding -------------------------------------------------------------

func _nearest_farm() -> Farm:
	return _nearest_in_group("farms", 60.0) as Farm


func _nearest_store() -> FoodStore:
	return _nearest_in_group("stores", 80.0) as FoodStore


func _nearest_villager() -> Villager:
	return _nearest_in_group("villagers", 50.0) as Villager


func _home_village() -> Village:
	for v in get_tree().get_nodes_in_group("village"):
		if is_instance_valid(v) and (v as Village).is_player_home:
			return v as Village
	return null


## Something it might eat: any animal it hasn't learned is inedible.
## A good creature leaves the villages' livestock alone; a fallen one
## does not distinguish.
func _nearest_catchable() -> Animal:
	var best: Animal = null
	var best_dist := 35.0
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or animal.is_queued_for_deletion():
			continue
		if animal.state == Animal.State.HELD or _inedible.has(animal.species):
			continue
		if animal.tamed_by != null and morality > -10.0:
			continue
		var d := global_position.distance_to(animal.global_position)
		if d < best_dist:
			best_dist = d
			best = animal
	return best


## A tree it can uproot: one that stands shorter than the creature itself.
func _nearest_uprootable_tree() -> WildTree:
	var my_height := 2.55 * scale.y
	var best: WildTree = null
	var best_dist := 30.0
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if not is_instance_valid(tree) or tree.is_felled() or tree.is_held():
			continue
		if tree.current_height() >= my_height:
			continue
		var d := global_position.distance_to(tree.global_position)
		if d < best_dist:
			best_dist = d
			best = tree
	return best


## A wild, tamable beast worth carrying home to the pen as a gift.
func _nearest_giftable() -> Animal:
	var best: Animal = null
	var best_dist := 30.0
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or not animal.is_tamable():
			continue
		if animal.state == Animal.State.HELD:
			continue
		var d := global_position.distance_to(animal.global_position)
		if d < best_dist:
			best_dist = d
			best = animal
	return best


func _nearest_in_group(group: String, radius: float) -> Node3D:
	var best: Node3D = null
	var best_dist := radius
	for n in get_tree().get_nodes_in_group(group):
		var node := n as Node3D
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


## Anything edible: ground food always; corpses only for a corrupted soul.
func _nearest_food() -> Node3D:
	var best := _nearest_ground_food(60.0) as Node3D
	var best_dist := 60.0 if best == null \
		else global_position.distance_to(best.global_position)
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


## Anything worth hauling to the storehouse: stray food or building
## materials lying about the land.
func _nearest_carriable(radius: float) -> Node3D:
	var best: Node3D = _nearest_ground_food(radius)
	var best_dist := radius if best == null else global_position.distance_to(best.global_position)
	for r in get_tree().get_nodes_in_group("resource_items"):
		var item := r as ResourceItem
		if not is_instance_valid(item) or item.is_queued_for_deletion() or item.freeze:
			continue
		var d := global_position.distance_to(item.global_position)
		if d < best_dist:
			best_dist = d
			best = item
	return best


func _nearest_ground_food(radius: float) -> FoodItem:
	var best: FoodItem = null
	var best_dist := radius
	for f in get_tree().get_nodes_in_group("food"):
		var food := f as FoodItem
		if not is_instance_valid(food) or food.is_queued_for_deletion():
			continue
		var d := global_position.distance_to(food.global_position)
		if d < best_dist:
			best_dist = d
			best = food
	return best


func _nearest_livestock() -> Animal:
	var best: Animal = null
	var best_dist := 45.0
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or animal.tamed_by == null:
			continue
		if animal.meat_yield() <= 0:
			continue
		var d := global_position.distance_to(animal.global_position)
		if d < best_dist:
			best_dist = d
			best = animal
	return best


func _nearest_wolf(radius: float) -> Animal:
	var best: Animal = null
	var best_dist := radius
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or animal.species != "wolf":
			continue
		var d := global_position.distance_to(animal.global_position)
		if d < best_dist:
			best_dist = d
			best = animal
	return best


func _find_working_villager() -> Villager:
	var best: Villager = null
	var best_dist := 30.0
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager) or not _is_working(villager):
			continue
		var d := global_position.distance_to(villager.global_position)
		if d < best_dist:
			best_dist = d
			best = villager
	return best


func _is_working(villager: Villager) -> bool:
	return villager.state in [
		Villager.State.FARMING, Villager.State.BUILDING,
		Villager.State.CHOPPING, Villager.State.QUARRYING,
	]


## Something small and harmless to chase for fun.
func _find_toy() -> Animal:
	var best: Animal = null
	var best_dist := 25.0
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or animal.spec.get("predator", false):
			continue
		if animal.spec["body"].length() > 1.6:  # only the small and fluffy
			continue
		var d := global_position.distance_to(animal.global_position)
		if d < best_dist:
			best_dist = d
			best = animal
	return best


## Body ----------------------------------------------------------------------

func _grow() -> void:
	if growth < 1.0:
		var before := int(growth * 10.0)
		growth = minf(growth + GROWTH_PER_MEAL, 1.0)
		scale = Vector3.ONE * lerpf(MIN_SCALE, MAX_SCALE, growth)
		# Announce only when crossing a 10% milestone, not on every meal.
		if int(growth * 10.0) > before:
			GameState.announce("Your creature grows. It is now %.0f%% of its destined size." \
				% (growth * 100.0))


func _move_toward(target: Vector3, speed: float, delta: float) -> bool:
	var to_target := target - global_position
	to_target.y = 0
	if to_target.length() < 1.0:
		_apply_gravity_only(delta)
		return true
	var dir := to_target.normalized()
	# The creature WADES: water is passable but slow — half speed with
	# its legs in the lake. (A future miracle will let it walk ON water.)
	if not walks_on_water:
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null and world.is_underwater(global_position.x, global_position.z):
			speed *= 0.5
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y -= GRAVITY * delta
	move_and_slide()
	# Body faces +Z; look_at aims -Z. Look away from travel to face it.
	look_at(global_position - Vector3(dir.x, 0, dir.z), Vector3.UP)
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
	elif state != State.SLEEPING and state != State.PLAY:
		_body.position.y = lerpf(_body.position.y, 0.0, 0.2)
		_body.rotation_degrees.z = lerpf(_body.rotation_degrees.z, 0.0, 0.2)


func receive_heal() -> void:
	energy = minf(energy + 40.0, 100.0)
	mood = minf(mood + 10.0, 100.0)


## Words ----------------------------------------------------------------------

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


func mood_word() -> String:
	if mood > 80.0:
		return "delighted"
	if mood > 55.0:
		return "cheerful"
	if mood > 35.0:
		return "content"
	if mood > 15.0:
		return "glum"
	return "wretched"


func favorite_deed() -> String:
	var best := ""
	var best_weight := 0.0
	for key: String in desires:
		if desires[key] > best_weight:
			best_weight = desires[key]
			best = key
	return best


func hover_text() -> String:
	return ("Your creature — %s (%s, %s) · bond %d · attention %d\n" +
		"hunger %d · energy %d · size %.0f%% · loves to %s\n" +
		"[P — pet   ·   L — scold   ·   C — lock camera]") % [
		_status_word(), morality_word(), mood_word(), int(bond), int(attention),
		int(hunger), int(energy), growth * 100.0, favorite_deed()]


## What to call the thing it's hauling — honest about lumber and stone,
## not "food" for everything.
func _carriable_word(item: Node3D) -> String:
	if item is ResourceItem:
		return (item as ResourceItem).kind
	if item is WildTree:
		return "timber"
	return "food"


func _status_word() -> String:
	match state:
		State.IDLE: return "pondering"
		State.WANDER: return "exploring"
		State.SEEK_FOOD: return "hunting for a snack"
		State.STALK_PREY: return "stalking someone"
		State.EATING: return "eating happily"
		State.GO_TEND, State.TENDING: return "helping on the farm"
		State.SLEEPING: return "sleeping"
		State.WATCH: return "watching the villagers, learning"
		State.GO_GATHER: return "fetching %s for the store" % _carriable_word(_target_food)
		State.CARRYING:
			match _carry_intent:
				"deliver": return "carrying %s to the store" % _carriable_word(_carried)
				"eat": return "about to eat what it caught"
				"gift": return "bringing a gift to the pen"
				"snatch": return "making off with someone"
			return "carrying something"
		State.CATCH: return "chasing something down"
		State.GO_FISH, State.FISHING: return "fishing"
		State.GO_STORE: return "raiding the granary"
		State.PLAY: return "playing"
		State.GUARD: return "standing guard"
		State.SULK: return "sulking"
	return "?"


func _status_text() -> String:
	match state:
		State.SLEEPING: return "zzz"
		State.EATING: return "nom nom"
		State.SEEK_FOOD: return "food?"
		State.STALK_PREY: return "..."
		State.TENDING: return "help!"
		State.WATCH: return "hmm..."
		State.CATCH: return "!!"
		State.FISHING: return "..."
		State.GO_GATHER: return "for you!"
		State.CARRYING: return "nom?" if _carry_intent == "eat" else "for you!"
		State.PLAY: return "wheee!"
		State.GUARD: return "grrr"
		State.SULK: return ":("
	return ""
