extends SceneTree
## TOWNS RAISED TOGETHER SHARE THE FRAME — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/founding_live.gd
##
## Three remembered towns of a hundred and twenty souls each — houses, fields,
## trades, a school, a barn of pigs and the creature's nest — are put back into
## the world at once, as the board does when you come over a hill to them, with
## the frame meter on. Checked:
##   1. all three stand, with their people, their roofs and their nests;
##   2. no frame spends more than MOST_MS of itself founding them, between all
##      three (VillageRaise.turn / spend: one budget, shared), where a nest
##      looked for in one frame was thirty to ninety milliseconds on its own —
##      and so no single founding step is that long either; and the board
##      raises them a frame apart (Chessboard._unfold_the_near), where all
##      three first frames on one were 19 to 30 ms;
##   3. and the meter names the step that was slowest even when its clock was
##      lent to something else and given back (Ledger.resume): a founding step
##      that raised a villager came back as "<null>".
## Exits non-zero on failure. Names no class of the game's (see look.gd).

## The founding budget (VillageRaise.FOUNDING_USEC, 6 ms) and the one step
## nobody can cut in two that may share its frame — a town's first, its square
## (5 to 7 ms headless), towns being raised a frame apart. 10.7 to 11.2 ms over
## four runs; it was 18 while the board raised them all in one look.
const MOST_MS := 14.0
const TOWNS := 3
const SOULS := 120

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
	var ledger: Script = load("res://scripts/ledger.gd")
	for meter in root.find_children("*", "FrameMeter", true, false):
		meter.visible = true
	for i in 90:
		await physics_frame
	print("TOWNS RAISED TOGETHER")
	var saves: Node = root.get_node("/root/SaveGame")
	var state: Node = root.get_node("/root/GameState")
	var names: Array[String] = []
	var sites: Array[Vector2] = []
	# In a ring round home, inside the land the board raises towns in (its
	# unload radius, in chunks) and clear of every town standing.
	var reach: float = float(world.unload_radius) * world.CHUNK_SIZE * 0.7
	var standing: Array = get_nodes_in_group("village")
	for i in 720:
		if sites.size() >= TOWNS:
			break
		var probe := Vector2.from_angle(TAU * float(i % 72) / 72.0) * (reach - 8.0 * float(i / 72))
		if not world.village_site_dry(probe.x, probe.y) or world.slope_at(probe.x, probe.y) > 0.8:
			continue
		if sites.any(func(s): return s.distance_to(probe) < 60.0) or standing.any(func(v):
				return Vector2(v.global_position.x, v.global_position.z).distance_to(probe) < 60.0):
			continue
		sites.append(probe)
	check(sites.size() == TOWNS, "%d dry sites for towns near home" % sites.size())
	for t in sites.size():
		var folk := []
		for i in SOULS:
			folk.append({"name": "Soul %d-%d" % [t, i], "female": i % 2 == 0,
				"age": 4.0 + float(i * 37 % 60), "lifespan": 80.0, "health": 100.0,
				"hunger": 20.0, "energy": 80.0})
		var houses := []
		for i in 18:
			houses.append(1)
		names.append("Togetherholm%d" % t)
		saves.village_memory.append({"name": names[t], "home": false,
			"pos": [sites[t].x, sites[t].y], "at_years": state.game_years, "folk": folk,
			"houses": houses, "farms": 3, "converted": true, "belief": 80.0,
			"store": {"plant": 400, "meat": 60, "lumber": 40, "stone": 40},
			"trades": {"well": 2, "barn": 1}, "edubba": true, "nest": true,
			"kept": {"pig": 12}})
	var towns := {}
	var worst_frame := 0.0
	var worst_frame_at := 0
	var frames := 0
	var until := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < until:
		await process_frame
		frames += 1
		for row: Array in ledger.rows():
			if row[0] == "Village:founding" and float(row[1]) > worst_frame:
				worst_frame = float(row[1])
				worst_frame_at = frames
		for v in get_nodes_in_group("village"):
			if is_instance_valid(v) and names.has(v.village_name):
				towns[v.village_name] = v
		if towns.size() == names.size() and towns.values().all(func(v): return v.founded):
			break
	var stood := towns.values().filter(func(v): return is_instance_valid(v) and v.founded)
	var people := 0
	var roofs := 0
	var nests := 0
	for v in stood:
		people += v.my_villagers().size()
		roofs += v.houses.size()
		nests += 1 if v.nest != null else 0
	check(stood.size() == names.size() and people >= names.size() * (SOULS - 5) and roofs >= names.size()
		and nests == names.size(), "all %d stand: %d people, %d roofs, %d nests (in %d frames)"
		% [stood.size(), people, roofs, nests, frames])
	check(worst_frame <= MOST_MS, "never more than %.0f ms of a frame founding them (worst %.1f ms, frame %d)"
		% [MOST_MS, worst_frame, worst_frame_at])

	# 3. A clock lent and given back keeps its name.
	ledger.open(&"Probe:outer", "the outer step")
	var was: StringName = ledger.swap(&"Probe:inner", "lent")
	ledger.resume(was)
	var spin := Time.get_ticks_usec() + 25000
	while Time.get_ticks_usec() < spin:
		pass
	ledger.open(&"Probe:after")
	ledger.turn_the_page()
	var slow: Array = ledger.slowest_call(false)
	check(slow.size() == 3 and slow[0] == "Probe:outer" and slow[1] == "the outer step",
		"a step whose clock was lent and given back keeps its name (%s)" % str(slow))
	print("FOUNDING LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
