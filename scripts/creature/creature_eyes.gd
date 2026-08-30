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
