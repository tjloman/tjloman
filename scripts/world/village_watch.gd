class_name VillageWatch
extends RefCounted
## WHAT THE TOWN CAN SEE AROUND IT, looked at once and read by everybody.
##
## Choosing a job asks a dozen questions about the country: is there timber
## worth walking to, is there stone, is there game, is there anything tamable,
## is there a shore, is there a heathen village within a missionary's reach.
## Every one of those was answered by walking a whole node group — the trees
## group is every tree in every loaded chunk — and every villager asked all of
## them, every time it chose what to do next. Fifty people doing that twice a
## minute each is thousands of group walks a minute to answer questions whose
## answers are the same for all of them, because they are all standing in the
## same village.
##
## So the town looks, once, on its own clock, and the answers are read. This is
## the same bargain the crowd mind made and for the same reason: what a village
## KNOWS is a property of the village.
##
## The split that makes it honest is between SCORING and ACTING. Scoring asks
## "is there timber near the town" — a shared question, answered here. Acting
## asks "which tree do I walk to" — the villager's own question, still answered
## by its own scan, once, by the one person actually going. Nobody is sent to a
## tree the town saw a second ago and somebody else already felled: a stale
## answer can only ever cost one wasted walk, which the job's own checks already
## handle, and never a wrong decision by forty-nine other people.

## How long an answer stands before the town looks again. Long by the standards
## of a frame and short by the standards of a forest: trees do not move, game
## drifts slowly, and the shore has not gone anywhere since the last look.
const LOOK_EVERY := 1.1

## How far the town's eye reaches, as multiples of its influence — the same
## numbers the villagers used, measured from the totem rather than from
## wherever one particular person happened to be standing. That is a slightly
## smaller catchment for a villager out at the edge and a slightly larger one
## for a villager in the middle, and it is the more correct question of the two:
## it is the TOWN that has timber in reach, not the individual.
const TIMBER_REACH := 2.5
const STONE_REACH := 2.5
const GAME_REACH := 2.0
const CORPSE_REACH := 1.5
const SHORE_STEPS: Array[float] = [10.0, 20.0, 35.0, 50.0]
const SHORE_SPOKES := 8

var timber: WildTree = null
var stone: RockDeposit = null
var game: Animal = null
var tamable: Animal = null
## A WILD HERD WORTH TAKING STOCK FROM. Not the same question as `tamable`
## above: that is one loose beast standing about, this is a herd the village
## can cut a head out of and raise as its own.
var stock: Herd = null
var corpse: Corpse = null
var shore := Vector3.INF
var heathen: Village = null

var _left := 0.0


## The town looks round. Everything here is one pass per group, once a second,
## for a village — not once per villager per decision.
func scan(delta: float, town: Village) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = LOOK_EVERY
	var here := town.global_position
	var reach := town.influence_radius
	var tree := town.get_tree()
	_look_for_timber(tree, here, reach * TIMBER_REACH)
	_look_for_stone(tree, here, reach * STONE_REACH)
	_look_for_beasts(tree, here, reach * GAME_REACH)
	_look_for_corpse(tree, here, reach * CORPSE_REACH)
	_look_for_stock(tree, here, reach * GAME_REACH)
	_look_for_shore(tree, here)
	_look_for_heathen(tree, town, here)


func _look_for_timber(tree: SceneTree, here: Vector3, reach: float) -> void:
	timber = null
	var best := reach
	for n in tree.get_nodes_in_group("trees"):
		var wood := n as WildTree
		if wood == null or not is_instance_valid(wood) or wood.is_queued_for_deletion():
			continue
		if wood.is_felled() or wood.is_held() or wood.burning:
			continue
		if _unreachable(tree, wood.global_position):
			continue
		var d := here.distance_to(wood.global_position)
		if d < best:
			best = d
			timber = wood


func _look_for_stone(tree: SceneTree, here: Vector3, reach: float) -> void:
	stone = null
	var best := reach
	for n in tree.get_nodes_in_group("rock_deposits"):
		var rock := n as RockDeposit
		if rock == null or not is_instance_valid(rock) or rock.is_queued_for_deletion():
			continue
		if _unreachable(tree, rock.global_position):
			continue
		var d := here.distance_to(rock.global_position)
		if d < best:
			best = d
			stone = rock


## GAME AND STOCK IN ONE PASS. Both questions are about the same group, and
## walking it twice to ask them separately was half the cost of the whole look.
func _look_for_beasts(tree: SceneTree, here: Vector3, reach: float) -> void:
	game = null
	tamable = null
	var best_game := reach
	var best_tame := reach
	for n in tree.get_nodes_in_group("animals"):
		var beast := n as Animal
		if beast == null or not is_instance_valid(beast) or beast.is_queued_for_deletion():
			continue
		if _unreachable(tree, beast.global_position):
			continue
		var d := here.distance_to(beast.global_position)
		if d >= reach:
			continue
		if d < best_game and beast.meat_yield() > 0 and beast.tamed_by == null \
				and not beast.spec.get("predator", false):
			best_game = d
			game = beast          # villagers hunt dinner, not death
		if d < best_tame and beast.is_tamable():
			best_tame = d
			tamable = beast


## THE NEAREST HERD THE TOWN COULD TAKE STOCK FROM: wild (a barn's own herd is
## already theirs), still standing, and of a kind that can be kept at all.
func _look_for_stock(tree: SceneTree, here: Vector3, reach: float) -> void:
	stock = null
	var best := reach
	for n in tree.get_nodes_in_group("herds"):
		var herd := n as Herd
		if herd == null or not is_instance_valid(herd) or herd.keeper != null:
			continue
		if herd.alive() <= 0 or not Animal.SPECIES[herd.species].get("tame", false):
			continue
		var d := here.distance_to(herd.global_position) - herd.spread()
		if d < best:
			best = d
			stock = herd


## IS THAT SOMEWHERE A VILLAGER WOULD DROWN GETTING TO?
##
## The town's eye is where most of what anybody walks to comes from, so the
## question is asked once here rather than by each job afterwards. A drowned
## animal drops its meat in the water; a felled tree can be thrown into a lake
## by the god; a rock can sit in the shallows. Every one of those was a whole
## village walking in after it, one at a time.
##
## Asked once a second for a town, which is what makes the depth read
## affordable here and not in anybody's per-frame work.
func _unreachable(tree: SceneTree, at: Vector3) -> bool:
	var world := tree.get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return false
	return world.water_level_at(at.x, at.z) - world.height_at(at.x, at.z) \
		> Villager.DROWN_DEPTH


## THE NEAREST BODY WORTH WALKING TO — and the drowned are not.
##
## A corpse lying under the water sent a butcher in after it, who drowned and
## left another corpse under the water, which sent the next one. Looked for once
## a second for the whole town, so the depth read costs a town what it used to
## cost one villager a frame.
func _look_for_corpse(tree: SceneTree, here: Vector3, reach: float) -> void:
	corpse = null
	var best := reach
	for n in tree.get_nodes_in_group("corpses"):
		var body := n as Corpse
		if body == null or not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if _unreachable(tree, body.global_position):
			continue
		var d := here.distance_to(body.global_position)
		if d < best:
			best = d
			corpse = body


## THE WATER'S EDGE, found by probing outward in rings. Thirty-two noise lookups
## is nothing once a second for a town and a great deal fifty times over.
func _look_for_shore(tree: SceneTree, here: Vector3) -> void:
	shore = Vector3.INF
	var world := tree.get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	for dist: float in SHORE_STEPS:
		for i in SHORE_SPOKES:
			var angle := TAU * float(i) / float(SHORE_SPOKES) + randf() * 0.3
			var probe := here + Vector3(cos(angle), 0.0, sin(angle)) * dist
			if world.is_underwater(probe.x, probe.z):
				var spot := here + (probe - here) * 0.85
				spot.y = world.height_at(spot.x, spot.z)
				shore = spot
				return


func _look_for_heathen(tree: SceneTree, town: Village, here: Vector3) -> void:
	heathen = null
	var best := Villager.MISSION_RANGE
	for n in tree.get_nodes_in_group("village"):
		var other := n as Village
		if other == null or not is_instance_valid(other) or other == town or other.converted:
			continue
		var d := here.distance_to(other.global_position)
		if d < best:
			best = d
			heathen = other
