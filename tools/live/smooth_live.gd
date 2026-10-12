extends SceneTree
## STEADY FRAMES — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/smooth_live.gd
##
##   1. a crater across the line between two of the land's buckets is as deep
##      as it was asked to be, not twice that (TerrainScars.offset_at read all
##      nine buckets round a point, and a scar is filed in every one it touches);
##   2. the crowd clock spends a bounded time a frame, and nobody starves for it:
##      every villager in the world has had a turn within a second;
##   3. the frame meter's walks of the world go a slice a frame, and no slice
##      is dear.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	print("STEADY FRAMES")
	# 1. The crater, on its own.
	var scars_script: Script = load("res://scripts/world/terrain_scars.gd")
	var scars = scars_script.new()
	var line: float = scars_script.BUCKET
	# Centred a metre short of a bucket line, wide enough to cross it — and a
	# second straddling a corner, filed under four.
	scars.add(0, Vector2(line - 1.0, 10.0), 6.0, -3.0)
	scars.add(0, Vector2(line * 3.0 + 1.0, line * 2.0 - 1.0), 5.0, -2.0)
	var across: float = scars.offset_at(line - 1.0, 10.0)
	var corner: float = scars.offset_at(line * 3.0 + 1.0, line * 2.0 - 1.0)
	check(absf(across - -3.0) < 0.001,
		"a crater across a bucket line is as deep as asked (%.2f of -3)" % across)
	check(absf(corner - -2.0) < 0.001,
		"and one on a corner of four (%.2f of -2)" % corner)

	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var main: Node = current_scene
	for i in 300:
		await process_frame

	# 2. Every villager gets a turn.
	var clock: Node = root.get_node_or_null("CrowdClock")
	check(clock != null and clock.FRAME_BUDGET_USEC > 0, "the crowd clock has a budget a frame")
	var people: Array = get_nodes_in_group("villagers").filter(
		func(v): return is_instance_valid(v) and v.is_inside_tree() and v.can_process())
	var before := {}
	for v in people:
		before[v] = v._sim_last
	var until := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < until:
		await physics_frame
	var missed := people.filter(func(v): return is_instance_valid(v) and v._sim_last == before[v])
	check(people.size() > 20 and missed.is_empty(),
		"every one of %d villagers has had a turn within a second and a half (%d missed)"
		% [people.size(), missed.size()])

	# 3. The meter's walks.
	var meter: Node = root.find_child("FrameMeter", true, false)
	meter.visible = true
	meter._survey_left = 0.0
	var dearest := 0
	var slices := 0
	for i in 400:
		var t0 := Time.get_ticks_usec()
		meter._survey_some()
		dearest = maxi(dearest, Time.get_ticks_usec() - t0)
		slices += 1
		await process_frame
		if meter._survey.is_empty() and meter._big_line != "":
			break
	check(meter._big_line != "", "the meter's walk of the world finishes (%d slices)" % slices)
	check(dearest < 8000, "and no slice of it is dear (%.1f ms)" % (dearest / 1000.0))
	var t1 := Time.get_ticks_usec()
	meter._readout()
	var wrote := (Time.get_ticks_usec() - t1) / 1000.0
	check(wrote < 8.0, "writing the readout walks nothing (%.1f ms)" % wrote)
	print("SMOOTH LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
