extends SceneTree
## A TOWN THAT BELIEVES IS NEVER LOST — checked in a real engine, across two
## launches, headless:
##
##     godot --headless --path . --script tools/saves/faithful_live.gd -- write
##     godot --headless --path . --script tools/saves/faithful_live.gd -- read
##
## `write` founds a town far past the horizon, makes it believe, and saves.
## `read` launches again on that save and asks, before the camera has gone
## anywhere near it: is the town kept — once, folded or standing, never both —
## where it was, believing what it believed, and are its prayers still coming
## in? Then saves again and checks the save holds it exactly once. Exits
## non-zero on failure.
##
## Names no class of the game's (a --script is compiled before the autoloads).

const NAME := "Faithwick"
const AT := Vector2(700.0, 520.0)
const BELIEF := 83.0

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-62s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	var mode := "read"
	if not OS.get_cmdline_user_args().is_empty():
		mode = OS.get_cmdline_user_args()[0]
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30:
		await process_frame
	var saves := root.get_node("/root/SaveGame")
	var world = root.find_child("WorldGen*", true, false)
	for n in root.get_tree().get_nodes_in_group("world_gen"):
		world = n
	var creature = root.get_tree().get_first_node_in_group("creature")
	if mode == "write":
		await _write(saves, world, creature)
	else:
		await _read(saves, world, creature)
	print("\n%s" % ("Success: no problems found" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails else 0)


func _write(saves: Node, world: Node, creature: Node) -> void:
	print("FAITHFUL TOWNS: writing")
	# A CLEAN SLATE: launched on an earlier run's save, there may be a
	# Faithwick standing already, or a record of one waiting. Both go, so this
	# launch writes exactly the one town it founds.
	for v in root.get_tree().get_nodes_in_group("village"):
		if String(v.village_name) == NAME:
			v.queue_free()
	var kept: Array = []
	for entry in saves.village_memory:
		if String(entry.get("name", "")) != NAME:
			kept.append(entry)
	saves.village_memory = kept
	await process_frame
	var town = load("res://scripts/world/village.gd").new()
	town.is_player_home = false
	town.village_name = NAME
	town.position = Vector3(AT.x, world.height_at(AT.x, AT.y), AT.y)
	world.add_sibling(town)
	for i in 3000:
		if town.founded:
			break
		await process_frame
	check(town.founded, "a town past the horizon is founded")
	town.converted = true
	town.belief = BELIEF
	check(bool(saves.save_to_disk(world, creature, true)), "and the world is saved with it believing")


func _read(saves: Node, world: Node, creature: Node) -> void:
	print("FAITHFUL TOWNS: reading")
	var eye: Vector3 = root.get_node("/root/GameState").camera_focus
	print("    the camera is %.0fm from it" % Vector2(eye.x, eye.z).distance_to(AT))
	# Far past the horizon, it is out of sight: kept as its record, folded —
	# or, if the land has reached it, standing. Once, either way.
	var found: Array = []
	for v in root.get_tree().get_nodes_in_group("village"):
		if String(v.village_name) == NAME:
			found.append(v)
	var waiting: Array = []
	for entry in saves.village_memory:
		if String(entry.get("name", "")) == NAME:
			waiting.append(entry)
	check(found.size() + waiting.size() == 1,
		"the believing town is kept, once (%d standing, %d folded)" % [found.size(), waiting.size()])
	if found.size() + waiting.size() != 1:
		return
	var record: Dictionary = waiting[0] if not waiting.is_empty() else found[0].to_dict()
	var at: Array = record.get("pos", [0.0, 0.0])
	check(Vector2(float(at[0]), float(at[1])).distance_to(AT) < 1.0, "where it stood")
	check(bool(record.get("converted", false)) and absf(float(record.get("belief", 0.0)) - BELIEF) < 0.5,
		"believing what it believed (%.1f)" % float(record.get("belief", 0.0)))
	# Past the opening screen, which pauses the world: nothing prays in a pause.
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var state: Node = root.get_node("/root/GameState")
	state.prayer_power = 0.0
	for i in 120:
		await process_frame
	check(state.prayer_power > 0.0, "and its prayers still come in (%.2f)" % state.prayer_power)
	check(bool(saves.save_to_disk(world, creature, true)), "saved again")
	var again: Dictionary = saves.read_from_disk()
	var times := 0
	for entry in again.get("villages", []):
		if String(entry.get("name", "")) == NAME:
			times += 1
	check(times == 1, "and the save holds it exactly once (%d)" % times)
