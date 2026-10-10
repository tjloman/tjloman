class_name Chessboard
extends Node
## THE TOWNS NOBODY IS LOOKING AT. A town that falls out of the loaded land is
## FOLDED: written down as its record (Village.to_dict) with the land round it
## read once (TownLand), put with every other remembered town in
## SaveGame.village_memory, and its people and houses freed. When the land comes
## back it is UNFOLDED: raised where it stood, and as it takes back its record
## (SaveGame.recall) the record is first stepped up to now by the board's rules
## and its people made to agree with the numbers by name — the alibi (TownFold).
##
## Towns used to persist forever once met, at full simulation, wherever they
## were; walking the map piled up every village crossed, which is how a phone
## came to be carrying fourteen hundred people it could not see.
##
## WHAT NEVER FOLDS: the home town; a town holding the creature's nest; a town
## still being founded; and one with somebody in the hand or in the air.
##
## AND A TOWN THAT BELIEVES STILL PRAYS FOLDED, at the rate it kept while it
## was seen (Village.to_dict "prayer_rate"), or what its grown people would
## give if it was never seen praying — and it still counts toward the prayer the
## god can hold.

## How often it looks, in seconds.
const LOOK_EVERY := 1.0
## Rings of chunks past `unload_radius` a town must be before it folds, and the
## seconds it must stay there. It unfolds within `unload_radius`: the gap
## between the two is what stops a town folding and unfolding on a border.
const FOLD_PAST := 1
const FOLD_AFTER := 8.0
## The share of a folded town's grown people at prayer at any moment, when it
## was never watched long enough to have a rate of its own.
const AT_PRAYER := 0.04

var _since := 0.0
var _far := {}        # Village -> seconds it has been past the fold line


func _process(delta: float) -> void:
	Ledger.open(&"Chessboard")
	_pray(delta)
	_since += delta
	if _since < LOOK_EVERY:
		return
	_since = 0.0
	var world := _world()
	if world == null:
		return
	var eye := WorldGen.cell_of(GameState.camera_focus.x, GameState.camera_focus.z)
	_fold_the_far(world, eye)
	_unfold_the_near(world, eye)


## TOWNS THAT BELIEVE, out of sight: they still count toward the prayer the god
## can hold (Village._update_influence).
static func remembered_believers() -> int:
	var count := 0
	for record: Dictionary in SaveGame.village_memory:
		if bool(record.get("converted", false)) and not bool(record.get("home", false)):
			count += 1
	return count


## BRING A REMEMBERED TOWN UP TO NOW, as it is taken back: called by
## SaveGame.recall before the record is handed to the town. The land is the one
## read when it folded, read again if a miracle has moved it since.
static func bring_up_to_date(record: Dictionary, world: WorldGen) -> void:
	if world == null:
		return
	var at: Array = record.get("pos", [0.0, 0.0])
	var spot := Vector3(float(at[0]), 0.0, float(at[1]))
	var land: TownLand = null
	if record.has("land"):
		land = TownLand.from_dict(record["land"])
	if land == null or land.edition != world.land_edition() or land.rings.is_empty():
		land = TownLand.read(world, spot, neighbours(world.get_tree(), Vector2(spot.x, spot.z), record))
		record["land"] = land.to_dict()
	var clock := Ledger.swap(&"Chessboard:alibi", String(record.get("name", "")))
	TownFold.catch_up(record, land, world.world_seed, GameState.game_years)
	# AND WHAT ITS HUNTING LEFT is what the herds round it are when they stand.
	var board: Dictionary = record.get("board", {})
	TownLand.write_back(world, Vector2(spot.x, spot.z), float(board.get("game_stock", 1.0)),
		float(board.get("beast_stock", 1.0)))
	Ledger.resume(clock)


## WHERE EVERY OTHER TOWN STANDS that could share ground with one at `here`,
## standing or out of sight — so each reads only the ground nearer itself.
## `except` is the town itself: its node, or its record.
static func neighbours(tree: SceneTree, here: Vector2, except: Variant) -> Array:
	var near := TownLand.REACH * 2.0
	var out := []
	for node in tree.get_nodes_in_group("village"):
		if is_same(node, except) or not is_instance_valid(node):
			continue
		var at := Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z)
		if at.distance_to(here) < near:
			out.append(at)
	for record: Dictionary in SaveGame.village_memory:
		if is_same(record, except):
			continue
		var pos: Array = record.get("pos", [])
		if pos.size() >= 2:
			var at := Vector2(float(pos[0]), float(pos[1]))
			if at.distance_to(here) < near and at.distance_to(here) > 1.0:
				out.append(at)
	return out


func _fold_the_far(world: WorldGen, eye: Vector2i) -> void:
	var line := world.unload_radius + FOLD_PAST
	var seen := {}
	for node in get_tree().get_nodes_in_group("village"):
		var town := node as Village
		if town == null or not is_instance_valid(town) or town.is_queued_for_deletion():
			continue
		var cell := WorldGen.cell_of(town.global_position.x, town.global_position.z)
		var rings := maxi(absi(cell.x - eye.x), absi(cell.y - eye.y))
		if rings <= line or not _may_fold(town):
			continue
		seen[town] = true
		_far[town] = float(_far.get(town, 0.0)) + LOOK_EVERY
		if float(_far[town]) >= FOLD_AFTER:
			fold(town, world)
	for town in _far.keys():
		if not seen.has(town):
			_far.erase(town)


func _may_fold(town: Village) -> bool:
	if town.is_player_home or not town.founded:
		return false
	if town.nest != null and is_instance_valid(town.nest):
		return false
	for one in town.my_villagers():
		if one.state == Villager.State.HELD or one.state == Villager.State.FALLING:
			return false
	return true


## FOLD A TOWN: its record, with its land read, into memory; its node freed.
func fold(town: Village, world: WorldGen) -> void:
	var clock := Ledger.swap(&"Chessboard:fold", town.village_name)
	var record := town.to_dict()
	var here := Vector2(town.global_position.x, town.global_position.z)
	var land := TownLand.read(world, town.global_position, neighbours(get_tree(), here, town))
	record["land"] = land.to_dict()
	# THE LARDERS START WHERE THE WORLD IS: the share of the beasts round it
	# still alive, hunting and all, not a land restocked by being looked away from.
	var board: Dictionary = (record.get("board", {}) as Dictionary).duplicate(true)
	if land.game > 0.0:
		board["game_stock"] = clampf(land.game_now / land.game, 0.05, 1.0)
	if land.predators > 0.0:
		board["beast_stock"] = clampf(land.predators_now / land.predators, 0.02, 1.0)
	record["board"] = board
	SaveGame.village_memory.append(record)
	_far.erase(town)
	town.queue_free()
	Ledger.resume(clock)


func _unfold_the_near(world: WorldGen, eye: Vector2i) -> void:
	var live: Array = get_tree().get_nodes_in_group("village")
	for record: Dictionary in SaveGame.village_memory.duplicate():
		if bool(record.get("home", false)):
			continue
		var at: Array = record.get("pos", [])
		if at.size() < 2:
			continue
		var spot := Vector2(float(at[0]), float(at[1]))
		var cell := WorldGen.cell_of(spot.x, spot.y)
		if maxi(absi(cell.x - eye.x), absi(cell.y - eye.y)) > world.unload_radius:
			continue
		var standing := live.any(func(v): return is_instance_valid(v) and Vector2(
			v.global_position.x, v.global_position.z).distance_to(spot) < SaveGame.SAME_TOWN)
		if not standing:
			var clock := Ledger.swap(&"Chessboard:unfold", String(record.get("name", "")))
			live.append(world.raise_record(record))
			Ledger.resume(clock)


## THE PRAYERS OF THE FAITHFUL OUT OF SIGHT, each second.
func _pray(delta: float) -> void:
	var rate := 0.0
	for record: Dictionary in SaveGame.village_memory:
		if not bool(record.get("converted", false)) or bool(record.get("home", false)):
			continue
		var kept := float(record.get("prayer_rate", 0.0))
		if kept <= 0.0:
			var grown := 0
			for one: Dictionary in record.get("folk", []):
				if float(one.get("age", 0.0)) >= TownRules.CHILD_YEARS:
					grown += 1
			kept = grown * AT_PRAYER * Village.WORSHIP_PRAYER_PER_SEC
			record["prayer_rate"] = kept
		rate += kept
	if rate > 0.0:
		GameState.add_prayer_power(rate * delta)


func _world() -> WorldGen:
	return get_tree().get_first_node_in_group("world_gen") as WorldGen
