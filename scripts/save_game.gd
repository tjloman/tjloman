extends Node
## Autoload `SaveGame`: writing a world down, and picking it back up.
##
## The terrain, the placement of towns and every tree regenerate exactly from
## the WORLD SEED, so none of that is written to disk. What is saved is only
## what PLAY has changed: your standing with the heavens, each village's faith,
## stocks, people and hard-won doctrine — and, most precious of all, your
## creature's mind, beliefs and body, which no seed could ever reproduce.
##
## Restoring works by RELOADING THE SCENE and handing it a parcel to unpack, so
## there is never a half-torn-down world lying about. Three things can be
## handed over, which is what makes the debug menu's tricks possible:
##
##   pending_world    — a whole saved game to restore
##   pending_creature — JUST the creature, to carry into a brand new world
##   pending_seed     — the seed the next world should grow from
##
## Villages are the awkward part, because the world STREAMS: the town you saved
## forty chunks north does not exist at load time and will not for some while.
## So their saved lives are kept in `village_memory` for the whole session, and
## each village asks for its own past as it is born (see `recall`). A town you
## never travel back to simply keeps its memory waiting.

const SAVE_PATH := "user://hand_of_the_heavens.save"
const VERSION := 1

## How near a freshly generated town must stand to a saved one to BE it.
const SAME_TOWN := 60.0

## Handed across a scene reload; consumed by Main when the new world is built.
var pending_world: Dictionary = {}
var pending_creature: Dictionary = {}
var pending_seed := 0

## Saved village records still waiting for their town to stream in.
var village_memory: Array = []


## Gather the living world into a dictionary.
func snapshot(world: WorldGen, creature: Creature) -> Dictionary:
	var villages := []
	for v in get_tree().get_nodes_in_group("village"):
		villages.append((v as Village).to_dict())
	# A town we saved but never revisited this session has never been rebuilt,
	# so its memory is the only record of it — carry it forward.
	for remembered: Dictionary in village_memory:
		villages.append(remembered)
	return {
		"version": VERSION,
		"seed": world.world_seed,
		"years": GameState.game_years,
		"alignment": GameState.alignment,
		"prayer": GameState.prayer_power,
		"max_prayer": GameState.max_prayer_power,
		"creature": creature.to_dict(),
		"villages": villages,
	}


func save_to_disk(world: WorldGen, creature: Creature) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		GameState.announce("The heavens could not write this world down.")
		return false
	file.store_string(JSON.stringify(snapshot(world, creature)))
	file.close()
	GameState.announce("The world is written down.")
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func read_from_disk() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


## Load a saved game: hand the parcel over and rebuild the scene around it.
func load_game() -> bool:
	var data := read_from_disk()
	if data.is_empty():
		GameState.announce("There is no world written down to return to.")
		return false
	pending_world = data
	pending_creature = {}
	pending_seed = int(data.get("seed", 0))
	# The village records must be in memory BEFORE the reload, because the home
	# village is built during Main's very first breath and asks for its past
	# straight away.
	village_memory = (data.get("villages", []) as Array).duplicate(true)
	_reload({
		"years": float(data.get("years", 0.0)),
		"alignment": float(data.get("alignment", 0.0)),
		"prayer": float(data.get("prayer", 60.0)),
		"max_prayer": float(data.get("max_prayer", 100.0)),
	})
	return true


## Start over completely: a new seed, a newborn creature, nothing remembered.
func new_game() -> void:
	pending_world = {}
	pending_creature = {}
	village_memory.clear()
	pending_seed = randi()
	_reload({})


## Roll a NEW WORLD but carry this creature into it, mind and all. Its beliefs,
## its habits, its body and everything you taught it come along; the land,
## the villages and their people are strangers.
func regenerate_world(creature: Creature) -> void:
	pending_world = {}
	pending_creature = creature.to_dict() if is_instance_valid(creature) else {}
	village_memory.clear()   # none of the old towns exist in the new land
	pending_seed = randi()
	_reload({})


## Reset the run-scoped globals to the given state (empty means "as new"),
## then rebuild the scene around them.
func _reload(globals: Dictionary) -> void:
	GameState.game_years = float(globals.get("years", 0.0))
	GameState.alignment = float(globals.get("alignment", 0.0))
	GameState.set_max_prayer_power(float(globals.get("max_prayer", 100.0)))
	GameState.prayer_power = float(globals.get("prayer", 60.0))
	GameState.camera_focus = Vector3.ZERO
	get_tree().reload_current_scene()


## Called by a village the moment it is built — whether at startup or forty
## minutes later as you wander back to it. If we remember a town that stood
## about here, its whole life is handed back and the memory is spent.
func recall(village: Village) -> void:
	if village_memory.is_empty():
		return
	var here := Vector2(village.global_position.x, village.global_position.z)
	var best := -1
	var best_dist := SAME_TOWN
	for i in village_memory.size():
		var entry: Dictionary = village_memory[i]
		var pos: Array = entry.get("pos", [])
		if pos.size() < 2:
			continue
		var d := here.distance_to(Vector2(float(pos[0]), float(pos[1])))
		# The home village is unique and must never be mistaken for a neighbour.
		if bool(entry.get("home", false)) != village.is_player_home:
			continue
		if d < best_dist:
			best_dist = d
			best = i
	if best < 0:
		return
	var record: Dictionary = village_memory[best]
	village_memory.remove_at(best)
	village.from_dict(record)


## Called by Main once the fresh world exists. Unpacks whichever parcel is
## waiting and then clears it, so a later reload starts clean.
func apply_pending(world: WorldGen, creature: Creature) -> void:
	if not pending_creature.is_empty():
		creature.from_dict(pending_creature)
		# Its old coordinates mean nothing in a new land — set it down beside
		# the home village, on whatever ground is actually there.
		creature.global_position = Vector3(
			10.0, world.height_at(10, 10) + 0.5 + creature.scale.y, 10.0)
		GameState.announce("A new world — but your creature remembers everything.")
	elif not pending_world.is_empty():
		creature.from_dict(pending_world.get("creature", {}))
		GameState.announce("The world returns as you left it.")
	pending_world = {}
	pending_creature = {}
	pending_seed = 0
