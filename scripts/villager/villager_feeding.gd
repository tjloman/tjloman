class_name VillagerFeeding
extends RefCounted
## WHERE THE NEXT MEAL COMES FROM, and what it costs to take it.
##
## Lifted out of Villager, which lives permanently on its line cap, and which
## had no room left for the one thing this file is actually about.
##
## There are five places a villager can eat, and they are asked about in an
## order that is itself the character of the town:
##
##   1. FOOD ON THE GROUND. A bundle somebody dropped, or a god did.
##   2. A BODY, if they would rather. See `_a_body` — this one comes before the
##      granary for the wicked and after it for the starving, which is the
##      whole difference between appetite and desperation.
##   3. THE GRANARY, which is what a village is for.
##   4. A BODY, if there is nothing else left.
##   5. A BUSH, foraging like anyone's ancestors.
##
## Most of this is moved code and reads as it always did. The body is new.

## HOW WICKED IS WICKED ENOUGH. Below this a villager will eat human flesh
## because they would rather; above it, only when starving. One number, read in
## both places that ask, so "would they?" and "would they FIRST?" can never
## drift apart.
const WICKED := 30.0
## WHAT A BODY IS WORTH. All of it: a grown person is a great deal more meat
## than one belly can hold, and the point of the mechanic is not the arithmetic.
const BODY_FILLS := 0.0


## Good souls refuse human flesh — until they are starving.
static func will_eat_flesh(who: Villager) -> bool:
	return who.morality < WICKED or who.hunger > Villager.STARVING_HUNGER


## WHOSE BODY THEY WILL EAT, AND WHY IT IS STILL THERE AFTERWARDS.
##
## Eating from a corpse does not consume it. One villager fills their belly and
## the body is still lying in the grass, so the next one who has run out of
## options comes and does the same, and a third joins them. Nobody waits their
## turn and nobody is served: there is nothing being handed out and nothing
## being taken away, which is exactly why several of them can be down over the
## same person at once.
##
## That is the darkest thing in this game and it is dark in the right way — not
## a special event, not a cutscene, just three people who each separately
## decided that this is what they are doing now.
##
## It is NOT the butcher's job, which is a different sentence: a butcher takes
## the body away and leaves joints. This leaves everything where it is.
static func _a_body(who: Villager) -> Corpse:
	if not will_eat_flesh(who):
		return null
	return VillagerSearch.corpse(who)


## Choose a meal. False when there is nothing anywhere, which is what a famine
## actually is.
static func plan(who: Villager) -> bool:
	who.target_bush = null
	who.feeding_on = null
	who.target_food = _ground_food(who)
	if who.target_food != null:
		who.state = Villager.State.GO_EAT
		return true
	# BEFORE THE GRANARY, for somebody who would rather. A villager this far
	# gone is not choosing the body because there is nothing else; the granary
	# may be full. They are choosing it.
	var body := _a_body(who)
	if body != null and who.morality < WICKED:
		return _go_to(who, body)
	for type: FoodItem.FoodType in who.village.allowed_food_types():
		if who.village.store.has(type):
			who.target_food = null
			who.state = Villager.State.GO_EAT
			who._target = who.village.store.global_position
			return true
	# And after it, for somebody who has nothing else. The same act, and a
	# different person doing it.
	if body != null:
		return _go_to(who, body)
	# The granary is bare: go foraging in the wild like anyone's ancestors.
	who.target_bush = VillagerSearch.forage(who)
	if who.target_bush != null:
		who.state = Villager.State.GO_EAT
		return true
	return false


static func _go_to(who: Villager, body: Corpse) -> bool:
	who.feeding_on = body
	who.state = Villager.State.GO_EAT
	who._target = body.global_position
	return true


## Walk to whatever was chosen, and start on it when it is underfoot.
static func go(who: Villager, delta: float) -> void:
	var pace := Villager.WALK_SPEED * who._speed_factor()
	if who.target_bush != null:
		if not is_instance_valid(who.target_bush) or not who.target_bush.has_berries():
			who.target_bush = null
			who._rethink()
			return
		if who._move_toward(who.target_bush.global_position, pace, delta):
			if who.target_bush.take_berry():
				who._dismount()
				who.state = Villager.State.EATING
				who._action_time = 2.0
			who.target_bush = null
		return
	if who.feeding_on != null:
		if not is_instance_valid(who.feeding_on) \
				or who.feeding_on.is_queued_for_deletion():
			who.feeding_on = null
			who._rethink()
			return
		who._target = who.feeding_on.global_position
		if who._move_toward(who._target, pace, delta):
			who._dismount()
			VillagerLook.gone_to_carrion(who)
			who.state = Villager.State.EATING
			who._action_time = 2.0
		return
	if who.target_food != null:
		if not is_instance_valid(who.target_food) or who.target_food.is_queued_for_deletion():
			who.target_food = null
			who._rethink()
			return
		who._target = who.target_food.global_position
		if who._move_toward(who._target, pace, delta):
			if who.target_food.is_human_meat:
				VillagerLook.gone_to_carrion(who)
			# Keep the food (it may be a bundle) — EATING takes only as much
			# as this belly needs, leaving the rest for the next hungry mouth.
			who._dismount()
			who.state = Villager.State.EATING
			who._action_time = 2.0
		return
	if who._move_toward(who._target, pace, delta):
		who._dismount()
		for type: FoodItem.FoodType in who.village.allowed_food_types():
			if who.village.store.take(type, 1) > 0:
				who.state = Villager.State.EATING
				who._action_time = 2.0
				return
		who._rethink()


## Consume the meal at hand. A ground bundle is eaten a mouthful at a time —
## only as many units as this belly needs, leaving the rest of the bundle on the
## ground for the next hungry villager. Bush berries and store meals are already
## single servings, so they just top up hunger by one unit.
##
## AND A BODY IS NOT CONSUMED AT ALL. Nothing is taken off it, nothing is used
## up, and it lies there afterwards exactly as it lay before — see `_a_body`.
static func meal(who: Villager) -> void:
	if who.feeding_on != null:
		who.hunger = BODY_FILLS
		who.feeding_on = null
		return
	if who.target_food != null and is_instance_valid(who.target_food) \
			and not who.target_food.is_queued_for_deletion():
		var need := clampi(int(ceil(who.hunger / FoodItem.NUTRITION)), 1,
			maxi(who.target_food.count, 1))
		who.hunger = maxf(who.hunger - need * FoodItem.NUTRITION, 0.0)
		who.target_food.count -= need
		if who.target_food.count <= 0:
			who.target_food.queue_free()
		else:
			who.target_food.refresh_bundle()
	else:
		who.hunger = maxf(who.hunger - FoodItem.NUTRITION, 0.0)
	who.target_food = null


static func _ground_food(who: Villager) -> FoodItem:
	var allowed := who.village.allowed_food_types()
	var best: FoodItem = null
	var best_dist := INF
	for f in who.get_tree().get_nodes_in_group("food"):
		var food := f as FoodItem
		if not is_instance_valid(food) or food.is_queued_for_deletion():
			continue
		if not allowed.has(food.food_type):
			continue
		if food.is_human_meat and not will_eat_flesh(who):
			continue
		# AND NOTHING WORTH DROWNING FOR. An animal that drowns drops its meat
		# where it died, which is the bottom of the water — and a village that
		# can see it will send everybody in after it, one at a time, each new
		# corpse leaving more meat in the water than the last. The god can fish
		# it out; the village leaves it.
		if who.would_drown_at(food.global_position):
			continue
		var d := who.global_position.distance_to(food.global_position)
		if d < best_dist and d < who.village.influence_radius * 1.5:
			best_dist = d
			best = food
	return best
