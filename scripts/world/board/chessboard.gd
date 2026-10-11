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
## AND THE BOARD KEEPS TIME. Every ROUND_EVERY seconds each folded town whose
## next step is due is stepped up to now — out of sight is not frozen; towns
## out there grow, starve and send people away while nobody watches — and the
## road between towns goes round (Migration): bands set off, walk, and arrive.
## A band crossing loaded land, with either end of its road standing, is real
## villagers walking (Migrant); out of loaded land it is folded back into its
## record.
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
## How often the board steps the folded towns and the road goes round, seconds.
const ROUND_EVERY := 4.0

var _since := 0.0
var _far := {}        # Village -> seconds it has been past the fold line
var _round := 0.0


func _ready() -> void:
	Migration.walkers.clear()      # a new scene: nobody is walking yet


func _process(delta: float) -> void:
	Ledger.open(&"Chessboard")
	_pray(delta)
	_walk_the_road(delta)
	_since += delta
	_round += delta
	if _since < LOOK_EVERY:
		return
	_since = 0.0
	var world := _world()
	if world == null:
		return
	var eye := WorldGen.cell_of(GameState.camera_focus.x, GameState.camera_focus.z)
	_fold_the_far(world, eye)
	_unfold_the_near(world, eye)
	if _round >= ROUND_EVERY:
		_round = 0.0
		_step_the_folded(world)
		Migration.go_round(get_tree(), GameState.game_years)
		_show_the_road(world, eye)


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
	var land := _land_of(record, world)
	var clock := Ledger.swap(&"Chessboard:alibi", String(record.get("name", "")))
	TownFold.catch_up(record, land, world.world_seed, GameState.game_years)
	# AND WHAT ITS HUNTING LEFT is what the herds round it are when they stand.
	var board: Dictionary = record.get("board", {})
	TownLand.write_back(world, Vector2(spot.x, spot.z), float(board.get("game_stock", 1.0)),
		float(board.get("beast_stock", 1.0)))
	TownLand.write_back_woods(world, Vector2(spot.x, spot.z), float(board.get("wood_stock", 1.0)))
	Ledger.resume(clock)


## THE LAND A RECORD'S TOWN READ when it folded, read again if a miracle has
## moved it since, or if it never had one (a record from an older save).
static func _land_of(record: Dictionary, world: WorldGen) -> TownLand:
	var land: TownLand = null
	if record.has("land"):
		land = TownLand.from_dict(record["land"])
	if land == null or land.edition != world.land_edition() or land.rings.is_empty():
		var at: Array = record.get("pos", [0.0, 0.0])
		var spot := Vector3(float(at[0]), 0.0, float(at[1]))
		land = TownLand.read(world, spot, neighbours(world.get_tree(), Vector2(spot.x, spot.z), record))
		record["land"] = land.to_dict()
	return land


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
	if land.wood > 0.0:
		board["wood_stock"] = clampf(land.wood_now / land.wood, 0.0, 1.0)
	record["board"] = board
	SaveGame.village_memory.append(record)
	_far.erase(town)
	# Any band walking on its ground goes back to being a record first.
	for band: Dictionary in SaveGame.bands:
		for one in Migration.walkers.get(band["id"], []):
			if is_instance_valid(one) and (one as Villager).village == town:
				_fold_band(band)
				break
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


## THE TOWNS OUT OF SIGHT, each stepped up to now once its next step is due. A
## record with no land read yet has it read — one a round, the board's slowest call.
func _step_the_folded(world: WorldGen) -> void:
	var now := GameState.game_years
	var read := false
	for record: Dictionary in SaveGame.village_memory:
		if bool(record.get("home", false)) \
				or now - float(record.get("at_years", now)) < TownRules.step_years():
			continue
		if not record.has("land"):
			if read:
				continue
			read = true
		var clock := Ledger.swap(&"Chessboard:step", String(record.get("name", "")))
		TownFold.catch_up(record, _land_of(record, world), world.world_seed, now, true)
		Ledger.resume(clock)


## THE ROAD, every frame: bands muster, walk, and arrive.
func _walk_the_road(delta: float) -> void:
	for band: Dictionary in SaveGame.bands.duplicate():
		if not band["set_off"]:
			band["muster"] = float(band["muster"]) - delta
			if float(band["muster"]) <= 0.0 or _gathered(band):
				band["set_off"] = true
			continue
		if Migration.advance(band, delta) and Migration.arrive(band, get_tree(), GameState.game_years):
			SaveGame.bands.erase(band)


func _gathered(band: Dictionary) -> bool:
	var at := Vector2(float(band["pos"][0]), float(band["pos"][1]))
	for one in Migration.walkers.get(band["id"], []):
		if is_instance_valid(one) and Vector2((one as Node3D).global_position.x,
				(one as Node3D).global_position.z).distance_to(at) > Migrant.WITH_IT:
			return false
	return true


## A BAND IN LOADED LAND IS PEOPLE WALKING, so long as either end of its road
## stands; anywhere else it is its record. Anybody the hand took out of a band
## (or who otherwise stopped walking with it) stays where they were put.
func _show_the_road(world: WorldGen, eye: Vector2i) -> void:
	for band: Dictionary in SaveGame.bands.duplicate():
		var at := Vector2(float(band["pos"][0]), float(band["pos"][1]))
		var cell := WorldGen.cell_of(at.x, at.y)
		var near := maxi(absi(cell.x - eye.x), absi(cell.y - eye.y)) <= world.unload_radius
		var host := _standing(String(band["to"]), band["to_pos"])
		if host == null:
			host = _standing(String(band["from"]), band["from_pos"])
		var walking: Array = []
		for one in Migration.walkers.get(band["id"], []):
			if not is_instance_valid(one):
				continue
			if (one as Villager).state == Villager.State.MIGRATE:
				walking.append(one)
			else:
				Migrant.arrive(one as Villager, (one as Villager).village)
		if walking.is_empty() and (band["folk"] as Array).is_empty():
			Migration.walkers.erase(band["id"])
			SaveGame.bands.erase(band)        # nobody left on this road
		elif not walking.is_empty() or Migration.walkers.has(band["id"]):
			Migration.walkers[band["id"]] = walking
			band["names"] = walking.map(func(w): return w.villager_name) \
				+ (band["folk"] as Array).map(func(one): return String(one.get("name", "")))
			if not near or host == null:
				_fold_band(band)
		elif near and host != null and not (band["folk"] as Array).is_empty():
			band["names"] = (band["folk"] as Array).map(func(one): return String(one.get("name", "")))
			for one: Dictionary in band["folk"]:
				var place := Migrant.place_in(band, String(one.get("name", "")))
				var spot := Vector3(at.x + place.x, 0.0, at.y + place.y)
				spot.y = world.height_at(spot.x, spot.z)
				walking.append(Migrant.raise(one, host, spot, band))
			Migration.walkers[band["id"]] = walking
			band["folk"] = []
			band["names"] = walking.map(func(w): return w.villager_name)


## WALKERS BACK INTO THEIR RECORD: written down by name, and freed.
static func _fold_band(band: Dictionary) -> void:
	for one in Migration.walkers.get(band["id"], []):
		if is_instance_valid(one):
			(band["folk"] as Array).append(Migrant.entry_of(one as Villager))
			(one as Node).queue_free()
	Migration.walkers.erase(band["id"])


func _standing(town_name: String, at: Array) -> Village:
	var spot := Vector2(float(at[0]), float(at[1]))
	for node in get_tree().get_nodes_in_group("village"):
		var town := node as Village
		if is_instance_valid(town) and town.village_name == town_name and not town.is_queued_for_deletion() \
				and Vector2(town.global_position.x, town.global_position.z).distance_to(spot) < SaveGame.SAME_TOWN:
			return town
	return null
