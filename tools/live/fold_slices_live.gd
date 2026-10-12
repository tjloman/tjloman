extends SceneTree
## A FOLD, A SLICE A FRAME — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/fold_slices_live.gd
##
## Folding a town read the land round it in one go: a fifth of a second on a
## PC, and three towns folding together was two thirds. Now:
##   1. the land read a slice at a time is the very land read whole;
##   2. it takes many slices, and none runs far past the board's budget;
##   3. a town that comes back into sight while the board is reading its land
##      is not folded at all. (That the board folds a town through the slices
##      is fold_live's first check.)
##   4. a land written by an older game, before `wood_now` was counted, still
##      steps: it reads as the woods it grew, not as an error every round.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var main: Node = current_scene
	var world: Node = main.world_gen
	var land_script: Script = load("res://scripts/world/board/town_land.gd")
	var board: Node = null
	for n in root.find_children("*", "Node", true, false):
		if n.has_method("_fold_some"):
			board = n
	print("A FOLD, A SLICE A FRAME")
	for i in 120:
		await process_frame
	var at: Vector3 = main.village.global_position + Vector3(60.0, 0.0, 40.0)

	# 1 and 2. Whole, and in slices.
	var t0 := Time.get_ticks_usec()
	var whole: Dictionary = land_script.read(world, at).to_dict()
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	var budget: int = board.FOLD_SLICE_USEC if board != null else 2500
	var sliced = land_script.begin_read(world, at)
	var slices := 0
	var worst := 0
	while true:
		var s0 := Time.get_ticks_usec()
		var done: bool = sliced.read_some(world, s0 + budget)
		worst = maxi(worst, Time.get_ticks_usec() - s0)
		slices += 1
		await process_frame
		if done or slices > 5000:
			break
	print("    whole: %.1f ms; in %d slices, the longest %.2f ms" % [took, slices, worst / 1000.0])
	check(sliced.to_dict() == whole, "the land read a slice at a time is the land read whole")
	check(slices >= 3, "it is read over several frames (%d)" % slices)
	check(worst < budget * 3, "and no slice runs far past the budget (%.2f ms)" % (worst / 1000.0))

	# 3. The board, through its slices: back in sight half way, not folded.
	check(board != null, "the board is there")
	if board != null:
		var town: Node = null
		for v in get_nodes_in_group("village"):
			if is_instance_valid(v) and not v.is_player_home and v.founded:
				town = v
				break
		if town == null:
			town = main.village
		board._begin_fold(town, world)
		board._fold_some()
		var reading_now: bool = board._reading != null
		board._fold_the_far(world, world.cell_of(town.global_position.x, town.global_position.z))
		check(reading_now and board._reading == null and is_instance_valid(town)
			and not town.is_queued_for_deletion(),
			"a town back in sight while its land is read is let be")
	# 4. An older game's land.
	var old_land: Dictionary = whole.duplicate(true)
	old_land.erase("wood_now")
	for ring: Dictionary in old_land["rings"]:
		ring.erase("wood_now")
	var back = land_script.from_dict(old_land)
	var near = back.near(40.0)
	check(near != null and back.wood_now == back.wood and near.wood_now == near.wood,
		"a land saved before woods were counted as they stand reads as grown")
	print("FOLD SLICES LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
