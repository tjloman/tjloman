extends Node
## Autoload `SaveGame`: writing a world down, and picking it back up.
##
## The terrain, the placement of towns and every tree regenerate exactly from
## the WORLD SEED, so none of that is written to disk. What is saved is only
## what PLAY has changed: your standing with the heavens, each village's faith,
## stocks, people and hard-won doctrine — and, most precious of all, your
## creature's mind, beliefs, heart and body, which no seed could ever reproduce.
##
## PROFILES. A creature is a long relationship, and the same player very
## reasonably wants more than one: a beloved beast raised kindly over weeks, and
## a monster to let off the leash on a wet afternoon. Neither should cost the
## other. So a save is not a file, it is a PROFILE — its own creature, its own
## world seed, its own towns — and the game remembers which one you were last
## playing and returns you to it.
##
## AUTOSAVE. Nobody should lose an hour of raising a creature to a phone call.
## The active profile is written down every couple of minutes, when the app is
## put in the background (the way a phone game actually ends), and on quit. Save
## is not a thing the player has to remember; the workshop's Save button is now
## only there for making a deliberate checkpoint.
##
## Restoring works by RELOADING THE SCENE and handing it a parcel to unpack, so
## there is never a half-torn-down world lying about. Three things can be handed
## over, which is what makes the workshop's tricks possible:
##
##   pending_world    — a whole saved game to restore
##   pending_creature — JUST the creature, to carry into a brand new world
##   pending_seed     — the seed the next world should grow from
##
## At startup there is no scene to reload, so the parcel is simply armed from
## disk before the world is built and Main walks into the saved game directly.
##
## Villages are the awkward part, because the world STREAMS: the town you saved
## forty chunks north does not exist at load time and will not for some while.
## So their saved lives are kept in `village_memory` for the whole session, and
## each village asks for its own past as it is born (see `recall`). A town you
## never travel back to simply keeps its memory waiting.

const SAVE_DIR := "user://saves"
const INDEX_PATH := "user://profiles.json"
## The single-slot save from before profiles existed. Anyone updating mid-game
## keeps their creature: it is adopted as their first profile and then left
## alone, never deleted, in case they roll back.
const LEGACY_PATH := "user://hand_of_the_heavens.save"
## 3 adds the terrain scars — craters, ripples, volcanoes. An older save simply
## has none, which is exactly right: nothing had moved the earth yet.
const VERSION := 3

## How near a freshly generated town must stand to a saved one to BE it.
const SAME_TOWN := 60.0

## How often the world writes itself down while you play. Two minutes is short
## enough that nothing much is ever lost and long enough that a phone is not
## writing a hundred kilobytes at every opportunity.
const AUTOSAVE_SECONDS := 120.0
## And never twice in quick succession, however many things ask for it.
const SAVE_FLOOR := 5.0

## Handed across a scene reload; consumed by Main when the new world is built.
var pending_world: Dictionary = {}
var pending_creature: Dictionary = {}
var pending_seed := 0

## Saved village records still waiting for their town to stream in.
var village_memory: Array = []

## Every creature this god has raised: {id, name, seed, created, played,
## saved_at, character, growth}. The index is small and separate from the saves
## themselves so the profile menu never has to read a whole world to list one.
var profiles: Array = []
var active := ""

var _since_save := 0.0
var _last_written := 0.0
var _played := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_read_index()
	_adopt_legacy()
	# Quitting must not lose the last two minutes, so the close is intercepted,
	# the world written down, and the quit finished by hand.
	get_tree().set_auto_accept_quit(false)
	_arm_active()


## Everything that ends a session on a phone or a desktop: the window closing,
## Android's back gesture, and — the one that actually happens — the app being
## pushed into the background by a phone call or a home swipe.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			autosave()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			autosave()


func _process(delta: float) -> void:
	if active == "":
		return
	_played += delta
	_since_save += delta
	if _since_save >= AUTOSAVE_SECONDS:
		autosave()


## Profiles -------------------------------------------------------------------

func _path_for(id: String) -> String:
	return "%s/%s.save" % [SAVE_DIR, id]


func profile(id: String) -> Dictionary:
	for entry: Dictionary in profiles:
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func active_profile() -> Dictionary:
	return profile(active)


func has_save() -> bool:
	return active != "" and FileAccess.file_exists(_path_for(active))


## START A NEW LIFE. A fresh creature with a name, a fresh world, and its own
## slot — none of which touches any creature already raised.
func start_new(creature_name: String) -> void:
	var id := "%d_%d" % [Time.get_unix_time_from_system(), randi() % 9999]
	profiles.append({
		"id": id, "name": creature_name.strip_edges().substr(0, 24),
		"seed": randi(), "created": Time.get_unix_time_from_system(),
		"played": 0.0, "saved_at": 0.0, "character": "newborn", "growth": 0.0,
	})
	active = id
	_played = 0.0
	_write_index()
	pending_world = {}
	pending_creature = {}
	village_memory.clear()
	pending_seed = int(profile(id).get("seed", randi()))
	GameState.creature_name = String(profile(id).get("name", ""))
	_reload({})


## Put down one creature and pick up another.
func switch_to(id: String) -> bool:
	if profile(id).is_empty():
		return false
	if active != "" and active != id:
		autosave()
	active = id
	_played = float(profile(id).get("played", 0.0))
	_write_index()
	GameState.creature_name = String(profile(id).get("name", ""))
	if FileAccess.file_exists(_path_for(id)):
		return load_game()
	# A profile that was made but never saved: begin its world from its seed.
	pending_world = {}
	pending_creature = {}
	village_memory.clear()
	pending_seed = int(profile(id).get("seed", randi()))
	_reload({})
	return true


## Forget a creature entirely. Deliberate, irreversible, and never the active
## one without saying so — the menu asks twice before calling this.
func forget(id: String) -> void:
	var at := -1
	for i in profiles.size():
		if String((profiles[i] as Dictionary).get("id", "")) == id:
			at = i
			break
	if at < 0:
		return
	if FileAccess.file_exists(_path_for(id)):
		DirAccess.remove_absolute(_path_for(id))
	profiles.remove_at(at)
	if active == id:
		active = ""
	_write_index()


func _read_index() -> void:
	profiles = []
	active = ""
	if not FileAccess.file_exists(INDEX_PATH):
		return
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	profiles = ((parsed as Dictionary).get("profiles", []) as Array).duplicate(true)
	active = String((parsed as Dictionary).get("active", ""))
	if profile(active).is_empty():
		active = ""
	_played = float(profile(active).get("played", 0.0))


## Write the index out. Public because the profile menu renames creatures.
func write_index() -> void:
	_write_index()


func _write_index() -> void:
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"profiles": profiles, "active": active}))
	file.close()


## A save from before profiles existed becomes this god's first creature. The
## old file is left where it is: adopting it must not be able to destroy it.
func _adopt_legacy() -> void:
	if not profiles.is_empty() or not FileAccess.file_exists(LEGACY_PATH):
		return
	var file := FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var data := parsed as Dictionary
	var id := "adopted_%d" % Time.get_unix_time_from_system()
	profiles.append({
		"id": id, "name": "", "seed": int(data.get("seed", 0)),
		"created": Time.get_unix_time_from_system(), "played": 0.0,
		"saved_at": Time.get_unix_time_from_system(),
		"character": "an older creature", "growth": 0.0,
	})
	active = id
	var out := FileAccess.open(_path_for(id), FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(data))
		out.close()
	_write_index()


## THE PARCEL, ARMED FROM DISK. At startup there is no scene to reload, so the
## saved world is unpacked into the pending fields and the globals set BEFORE
## Main builds anything — and the player simply finds themselves back where they
## left off, with no menu and no loading step.
func _arm_active() -> void:
	if not has_save():
		return
	var data := read_from_disk()
	if data.is_empty():
		return
	pending_world = data
	pending_seed = int(data.get("seed", 0))
	village_memory = (data.get("villages", []) as Array).duplicate(true)
	GameState.game_years = float(data.get("years", 0.0))
	GameState.alignment = float(data.get("alignment", 0.0))
	GameState.set_max_prayer_power(float(data.get("max_prayer", 100.0)))
	GameState.prayer_power = float(data.get("prayer", 60.0))
	GameState.creature_name = String(active_profile().get("name", ""))


## Writing and reading ---------------------------------------------------------

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
		# WHAT WAS DONE TO THE LAND. Everything else about the terrain comes
		# back from the seed; craters, ripples and volcanoes do not, so they are
		# the one part of the ground that has to be written down.
		"scars": world.scars.to_save(),
	}


func save_to_disk(world: WorldGen, creature: Creature, quiet := false) -> bool:
	if active == "":
		return false
	var file := FileAccess.open(_path_for(active), FileAccess.WRITE)
	if file == null:
		GameState.announce("The heavens could not write this world down.")
		return false
	file.store_string(JSON.stringify(snapshot(world, creature)))
	file.close()
	_since_save = 0.0
	_last_written = float(Time.get_ticks_msec()) / 1000.0
	# The index carries just enough to describe the creature in a list without
	# opening its world: what it has become, how big it has grown, how long you
	# have spent with it.
	var entry := profile(active)
	if not entry.is_empty():
		entry["played"] = _played
		entry["saved_at"] = Time.get_unix_time_from_system()
		entry["growth"] = creature.growth
		entry["character"] = creature.morality_word()
		if String(entry.get("name", "")) == "" and creature.creature_name != "":
			entry["name"] = creature.creature_name
		_write_index()
	if not quiet:
		GameState.announce("The world is written down.")
	return true


## The quiet save: on a timer, on going to the background, on quitting. Finds
## the world and the creature itself, so anything at all can ask for one.
func autosave() -> bool:
	if active == "":
		return false
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _last_written < SAVE_FLOOR:
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var world := tree.get_first_node_in_group("world_gen") as WorldGen
	var creature := tree.get_first_node_in_group("creature") as Creature
	if world == null or creature == null:
		return false
	return save_to_disk(world, creature, true)


func read_from_disk() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(_path_for(active), FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


## Load the active profile: hand the parcel over and rebuild the scene.
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


## Roll a NEW WORLD but carry this creature into it, mind and all. Its beliefs,
## its habits, its body and everything you taught it come along; the land,
## the villages and their people are strangers. Stays in the same profile —
## it is the same creature, and its life goes on.
func regenerate_world(creature: Creature) -> void:
	pending_world = {}
	pending_creature = creature.to_dict() if is_instance_valid(creature) else {}
	village_memory.clear()   # none of the old towns exist in the new land
	pending_seed = randi()
	var entry := profile(active)
	if not entry.is_empty():
		entry["seed"] = pending_seed
		_write_index()
	_reload({})


## Reset the run-scoped globals to the given state (empty means "as new"),
## then rebuild the scene around them.
func _reload(globals: Dictionary) -> void:
	GameState.game_years = float(globals.get("years", 0.0))
	GameState.alignment = float(globals.get("alignment", 0.0))
	GameState.set_max_prayer_power(float(globals.get("max_prayer", 100.0)))
	GameState.prayer_power = float(globals.get("prayer", 60.0))
	GameState.camera_focus = Vector3.ZERO
	_since_save = 0.0
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
		# The land as the player left it, not as the seed made it. The chunks
		# under them were already raised from an unscarred seed, so every one
		# of them is re-cut now that the scars are known.
		var scars := pending_world.get("scars", []) as Array
		if not scars.is_empty():
			world.scars.from_save(scars)
			world.rebuild_all()
		GameState.announce("The world returns as you left it.")
	# A brand-new profile names its creature the moment it draws breath.
	var named := String(active_profile().get("name", ""))
	if named != "" and creature.creature_name == "":
		creature.name_it(named)
	pending_world = {}
	pending_creature = {}
	pending_seed = 0


## How long this creature has been alive under your hand, in plain words.
## Not static: everything reaches it through the `SaveGame` autoload instance,
## and calling a static function on an instance is a warning.
func spent(seconds: float) -> String:
	@warning_ignore("integer_division")
	var hours := int(seconds) / 3600
	@warning_ignore("integer_division")
	var minutes := (int(seconds) % 3600) / 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes
