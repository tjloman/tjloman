class_name CreatureEyes
extends RefCounted
## What the creature can SEE — pure scene-tree searching, no state and no
## opinions. Everything here answers "what is the nearest X?" and nothing here
## decides whether X is worth going to; that is the mind's business alone.
##
## Keeping perception separate from judgement is what lets the same eyes serve
## a saint and a monster: they both see the shepherd, and only their learned
## values differ on what to do about it.

## The nearest field with work in it.
static func nearest_farm(tree: SceneTree, from: Vector3, radius := 60.0) -> Farm:
	var best: Farm = null
	var best_d := radius
	for f in tree.get_nodes_in_group("farms"):
		var farm := f as Farm
		if not is_instance_valid(farm) or not farm.is_workable():
			continue
		var d := from.distance_to(farm.global_position)
		if d < best_d:
			best_d = d
			best = farm
	return best


static func nearest_store(tree: SceneTree, from: Vector3, radius := 80.0) -> FoodStore:
	return nearest_in_group(tree, from, "stores", radius) as FoodStore


static func home_village(tree: SceneTree) -> Village:
	for v in tree.get_nodes_in_group("village"):
		if is_instance_valid(v) and (v as Village).is_player_home:
			return v as Village
	return null


## THE CIRCUMSTANCES a creature is in right now — the situation its beliefs are
## learned against. "I was starving, in their village, at night, with armed men
## about, and my god was nowhere near." Every value is 0..1, and the vocabulary
## is deliberately the same one `plight_of` describes other people in, because
## that shared vocabulary is what its empathy runs on.
static func circumstances(who: Creature) -> Dictionary:
	var crowd := 0
	var armed := 0
	var predator := 0.0
	# HOW EVERYONE ELSE IS DOING is part of the situation too. Beliefs learned
	# against these read like "smashing the store goes badly when the people are
	# already frightened" — the creature can be contextual about other people's
	# states, not merely about its own hunger and the hour.
	var kin_afraid := 0.0
	var kin_hurting := 0.0
	var kin_glad := 0.0
	for v in who.get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		if villager.global_position.distance_to(who.global_position) < 22.0:
			crowd += 1
			if villager.weapon != "":
				armed += 1
			if villager.is_afraid() or villager.burning:
				kin_afraid += 1.0
			if villager.is_dying() or villager.health < 55.0 or villager.hunger > 80.0:
				kin_hurting += 1.0
			if villager.happiness > 70.0:
				kin_glad += 1.0
	for a in who.get_tree().get_nodes_in_group("animals"):
		var beast := a as Animal
		if is_instance_valid(beast) and beast.spec.get("predator", false) \
				and beast.global_position.distance_to(who.global_position) < 20.0:
			predator = 1.0
			break
	var home := home_village(who.get_tree())
	var in_village := 0.0
	if home != null and home.global_position.distance_to(who.global_position) \
			< home.influence_radius:
		in_village = 1.0
	var god_near := 0.0
	if who.divine_hand != null and is_instance_valid(who.divine_hand) \
			and who.divine_hand.global_position.distance_to(who.global_position) < 18.0:
		god_near = 1.0
	return {
		"hungry": clampf(who.hunger / 100.0, 0.0, 1.0),
		"stuffed": who.body.fullness(who.growth),
		"tired": clampf((100.0 - who.energy) / 100.0, 0.0, 1.0),
		"afraid": clampf(who.fear / 100.0, 0.0, 1.0),
		"hurt": clampf((100.0 - who.mood) / 100.0, 0.0, 1.0),
		"bored": clampf(who.boredom / 100.0, 0.0, 1.0),
		"crowd": clampf(crowd / 5.0, 0.0, 1.0),
		"armed": clampf(armed / 3.0, 0.0, 1.0),
		"predator": predator,
		"god_near": god_near,
		"in_village": in_village,
		"night": 1.0 if GameState.is_night() else 0.0,
		"alone": 1.0 if crowd == 0 else 0.0,
		"kin_afraid": clampf(kin_afraid / 3.0, 0.0, 1.0),
		"kin_hurting": clampf(kin_hurting / 3.0, 0.0, 1.0),
		"kin_glad": clampf(kin_glad / 3.0, 0.0, 1.0),
	}


## SOMEBODY ELSE'S SITUATION, described in exactly the same vocabulary the
## creature uses for its own (see CreatureBeliefs.FEATURES). That shared
## vocabulary is what makes empathy possible at all: the creature has no window
## into a villager's head, only a look at the circumstances they are in, which
## it can then match against what those circumstances have felt like to IT.
##
## Nothing here says what any of it means. A villager on fire is simply
## reported as hurt and afraid; whether that is pitiable, interesting or funny
## is decided entirely by the creature's own history (see CreatureHeart).
static func plight_of(villager: Villager) -> Dictionary:
	if not is_instance_valid(villager):
		return {}
	var dying := 1.0 if villager.is_dying() else 0.0
	return {
		"hungry": clampf(villager.hunger / 100.0, 0.0, 1.0),
		"stuffed": clampf((60.0 - villager.hunger) / 60.0, 0.0, 1.0),
		"hurt": maxf(clampf((100.0 - villager.health) / 100.0, 0.0, 1.0), dying),
		"afraid": maxf(1.0 if villager.is_afraid() else 0.0,
			1.0 if villager.burning else 0.0),
		"tired": clampf((100.0 - villager.energy) / 100.0, 0.0, 1.0),
		"alone": clampf((100.0 - villager.social) / 100.0, 0.0, 1.0),
		"crowd": clampf(villager.social / 100.0, 0.0, 1.0),
		"in_village": 1.0,
		"night": 1.0 if GameState.is_night() else 0.0,
	}


## Whoever nearby is worst off — the one a creature that cared would go to
## first. Ranked by plain visible trouble, not by anything it has learned.
static func neediest_soul(tree: SceneTree, from: Vector3, radius := 30.0) -> Villager:
	var best: Villager = null
	var worst := 0.35
	for v in tree.get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		if villager.global_position.distance_to(from) > radius:
			continue
		var plight := plight_of(villager)
		var trouble: float = float(plight.get("afraid", 0.0)) \
			+ float(plight.get("hurt", 0.0)) * 0.8 \
			+ float(plight.get("hungry", 0.0)) * 0.5
		if trouble > worst:
			worst = trouble
			best = villager
	return best


static func nearest_in_group(tree: SceneTree, from: Vector3, group: String,
		radius: float) -> Node3D:
	var best: Node3D = null
	var best_dist := radius
	for n in tree.get_nodes_in_group(group):
		var node := n as Node3D
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var d := from.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


## Anything edible: ground food always; corpses only for a corrupted soul.
static func nearest_food(tree: SceneTree, from: Vector3, morality: float,
		radius := 60.0) -> Node3D:
	var best := nearest_ground_food(tree, from, radius) as Node3D
	var best_dist := radius if best == null else from.distance_to(best.global_position)
	if morality < -10.0:
		for c in tree.get_nodes_in_group("corpses"):
			var corpse := c as Corpse
			if not is_instance_valid(corpse) or corpse.is_queued_for_deletion():
				continue
			var d := from.distance_to(corpse.global_position)
			if d < best_dist:
				best_dist = d
				best = corpse
	return best


## Anything worth hauling to the storehouse: stray food or building materials
## lying about the land.
static func nearest_carriable(tree: SceneTree, from: Vector3, radius: float) -> Node3D:
	var best: Node3D = nearest_ground_food(tree, from, radius)
	var best_dist := radius if best == null else from.distance_to(best.global_position)
	for r in tree.get_nodes_in_group("resource_items"):
		var item := r as ResourceItem
		if not is_instance_valid(item) or item.is_queued_for_deletion() or item.freeze:
			continue
		var d := from.distance_to(item.global_position)
		if d < best_dist:
			best_dist = d
			best = item
	return best


static func nearest_ground_food(tree: SceneTree, from: Vector3, radius: float) -> FoodItem:
	var best: FoodItem = null
	var best_dist := radius
	for f in tree.get_nodes_in_group("food"):
		var food := f as FoodItem
		if not is_instance_valid(food) or food.is_queued_for_deletion():
			continue
		var d := from.distance_to(food.global_position)
		if d < best_dist:
			best_dist = d
			best = food
	return best


static func nearest_wolf(tree: SceneTree, from: Vector3, radius: float) -> Animal:
	var best: Animal = null
	var best_dist := radius
	for a in tree.get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or animal.species != "wolf":
			continue
		var d := from.distance_to(animal.global_position)
		if d < best_dist:
			best_dist = d
			best = animal
	return best


## Is this villager visibly at a JOB? The creature learns trades by watching.
static func is_working(villager: Villager) -> bool:
	return villager.state in [
		Villager.State.FARMING, Villager.State.BUILDING,
		Villager.State.CHOPPING, Villager.State.QUARRYING,
	]


## THE BUCKETS the creature thinks in. Not "that particular sheep" but "a
## sheep" — coarse enough that a lesson about one wolf is a lesson about
## wolves. The divine hand uses the very same buckets, so watching YOU hurl a
## villager lands on the identical learned value as hurling one itself.
static func kind_of(node: Node) -> String:
	if node is Villager:
		return "villager"
	if node is Animal:
		var a := node as Animal
		if a.spec.get("predator", false):
			return "predator"
		return a.species
	if node is House:
		return "house"
	if node is WildTree:
		return "tree"
	if node is RockDeposit:
		return "rock"
	if node is Corpse:
		return "corpse"
	if node is FoodItem:
		return "food"
	if node is ResourceItem:
		return "goods"
	return "thing"
