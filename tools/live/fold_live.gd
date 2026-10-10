extends SceneTree
## A TOWN OUT OF SIGHT, AND BACK — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/fold_live.gd
##
##   1. a town the camera leaves far behind is FOLDED: its people and houses
##      freed, its record — land read and all — remembered, once;
##   2. home never folds;
##   3. a town that believes keeps praying while it is folded, and still counts
##      toward the prayer the god can hold;
##   4. years pass; the camera comes back, and the town is UNFOLDED where it
##      stood, caught up: its people agree with the board's numbers, the ones
##      who lived are the ones the player knew, older by the years away, and
##      its history says what happened;
##   5. and holding its totem reads the town — its people by age and sex, what
##      they are doing, and the alibi — in the stone panel.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var state: Node = root.get_node("/root/GameState")
	var saves: Node = root.get_node("/root/SaveGame")
	var main: Node = current_scene
	var rig: Node3D = main.camera_rig
	var world: Node = main.world_gen
	saves.village_memory.clear()
	print("A TOWN OUT OF SIGHT")

	# A town of our own to fold, founded beside home so it is near to begin with.
	var town = load("res://scripts/world/village.gd").new()
	town.is_player_home = false
	town.village_name = "Foldwick"
	var at := Vector2(150.0, 40.0)
	town.position = Vector3(at.x, world.height_at(at.x, at.y), at.y)
	world.add_sibling(town)
	for i in 3000:
		if town.founded:
			break
		await process_frame
	town.converted = true
	town.belief = 70.0
	# Founders arrive in stages, with pauses: give them time, and note who it
	# has at the last moment before the camera leaves.
	await seconds(6.0)
	var knew := {}
	for v in town.my_villagers():
		knew[v.villager_name] = v.age
	var had: int = knew.size()
	print("    Foldwick founded with %d souls" % had)

	# 1. Gone far away: it folds. A live town grows fast, so what it had is
	# taken as it leaves, not before.
	var at_fold := [-1]
	town.tree_exiting.connect(func(): at_fold[0] = town.my_villagers().size())
	rig.global_position = Vector3(3000.0, 0.0, 3000.0)
	await seconds(14.0)
	var standing: Array = get_nodes_in_group("village").filter(
		func(v): return is_instance_valid(v) and v.village_name == "Foldwick")
	var records: Array = saves.village_memory.filter(func(r): return r.get("name", "") == "Foldwick")
	check(standing.is_empty(), "the town the camera left behind is folded: no longer standing")
	check(records.size() == 1, "and remembered, once (%d)" % records.size())
	var record: Dictionary = records[0] if not records.is_empty() else {}
	var written: int = (record.get("folk", []) as Array).size()
	check(written == int(at_fold[0]) and written > 0 and record.has("land"),
		"with its people (%d of %d) and the land round it written down" % [written, at_fold[0]])
	# It went out of sight hungry, every one of them: years later, a town with
	# food put by must not bring them back still starving.
	for one: Dictionary in record.get("folk", []):
		one["hunger"] = 90.0
	# 2. Home stays.
	var home: Array = get_nodes_in_group("village").filter(
		func(v): return is_instance_valid(v) and v.is_player_home)
	check(home.size() == 1, "home never folds")
	# 3. The faithful keep praying.
	var prayer_before: float = state.prayer_power
	state.prayer_power = 0.0
	await seconds(2.0)
	check(state.prayer_power > 0.0 and float(record.get("prayer_rate", 0.0)) > 0.0,
		"a town that believes prays while folded (%.2f a second)" % float(record.get("prayer_rate", 0.0)))
	state.prayer_power = prayer_before
	var chessboard: Script = load("res://scripts/world/board/chessboard.gd")
	check(chessboard.remembered_believers() >= 1, "and still counts toward the prayer the god can hold")

	# 4. Twenty years on, back again.
	state.game_years += 20.0
	rig.global_position = Vector3(at.x, 0.0, at.y)
	var back = null
	for i in 600:
		await process_frame
		for v in get_nodes_in_group("village"):
			if is_instance_valid(v) and v.village_name == "Foldwick":
				back = v
		if back != null and back.founded:
			break
	await seconds(1.0)
	check(back != null and back.founded, "back in sight, it is raised again")
	if back == null:
		_done()
		return
	check(Vector2(back.global_position.x, back.global_position.z).distance_to(at) < 1.0, "where it stood")
	var book: Dictionary = back.board
	# Each age is rounded on its own at the door, so the record holds exactly the
	# sum of the three rounded ages; the live town is a moment older than that.
	var counted := roundi(float(book.get("children", 0.0))) + roundi(float(book.get("adults", 0.0))) \
		+ roundi(float(book.get("elders", 0.0)))
	var folk: Array = back.my_villagers()
	print("    %d souls became %d; the board says %d, its record held %d" % [had, folk.size(), counted,
		(record.get("folk", []) as Array).size()])
	var held: int = (record.get("folk", []) as Array).size()
	check(held == counted and absi(folk.size() - held) <= 2,
		"its people agree with the board's numbers (%d, %d standing)" % [held, folk.size()])
	# Names come from a small pool, so a newcomer can share one: a survivor is
	# a name the town had, standing at exactly its old age plus twenty.
	var lived := 0
	for name: String in knew:
		if folk.any(func(v): return v.villager_name == name \
				and absf(v.age - float(knew[name]) - 20.0) < 0.5):
			lived += 1
	check(lived >= had / 2, "those who lived are the ones it had, twenty years older (%d of %d)" % [lived, had])
	# AS THEIR TOWN IS: with food put by, nobody comes back starving, and their
	# spirits are the town's.
	var need := 0.0
	var hungry := 0
	var glad := 0.0
	var grown := 0
	for v in folk:
		if v.is_adult():
			grown += 1
			glad += v.happiness
			if v.hunger > 50.0:
				hungry += 1
	var store: Dictionary = record.get("store", {})
	var meals := float(store.get("plant", 0)) + float(store.get("meat", 0))
	need = grown * 0.85
	var morale := float(book.get("morale", 60.0))
	print("    %d meals put by for %d grown; %d hungry; spirits %.0f against the town's %.0f"
		% [meals, grown, hungry, glad / maxf(grown, 1), morale])
	check(meals < need * 0.25 or hungry == 0, "with food put by, nobody comes back starving")
	check(absf(glad / maxf(grown, 1) - morale) < 12.0, "and their spirits are the town's")
	var history: Array = book.get("chronicle", [])
	var told: bool = history.any(func(e): return String(e[1]).contains("years passed"))
	check(told, "and its history says what happened (%d lines)" % history.size())
	check(saves.village_memory.filter(func(r): return r.get("name", "") == "Foldwick").is_empty(),
		"its record is taken back, not left waiting")

	# 5. Holding the totem.
	var reading: Script = load("res://scripts/world/board/town_reading.gd")
	var read: Dictionary = reading.of(back)
	var heads: Array = (read.get("blocks", []) as Array).map(func(b): return b["head"])
	print("    the totem reads: %s" % ", ".join(heads))
	var people: Array = read["blocks"][1]["rows"]
	check(heads.has("ITS PEOPLE") and heads.has("WHAT THEY ARE DOING") and heads.has("WHILE YOU WERE AWAY")
		and String(people[-1][1]).begins_with(str(folk.size())),
		"its totem reads the town: people by age and sex, their work, the alibi")
	var hand: Node = main.divine_hand
	check(String(hand.describe(back.totem)).contains("hold") and hand._readable(back.totem),
		"the hand says the totem can be held, and a hold on it reads")
	var hud: Node = main.hud
	state.stone_read.emit(back.totem)
	await process_frame
	check(hud._stone_panel.visible and String(hud._stone_label.text).contains("FOLDWICK"),
		"and holding it opens the reading (%s)" % hud._stone_label.text)
	_done()


func _done() -> void:
	print("FOLD LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
