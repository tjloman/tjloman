extends SceneTree
## A FULL LAND STORE KEEPS THE GROUND PEOPLE ARE STANDING ON — headless:
##
##     godot --headless --path . --script tools/live/land_tiles_live.gd
##
## Four towns 450 to 1100 metres from the camera are walked about in every
## frame, while fresh ground arrives at eight tiles a frame (the camera moving,
## chunks being cut) so the store fills and is trimmed again and again. What is
## counted is how often a TOWN's ground has to be read from the seed again after
## it was first read: the towns are the people, and a re-read there is a
## villager paying for the land twice. Exits non-zero on failure.
## Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var world: Node = current_scene.world_gen
	var gen: Script = world.get_script()
	var ledger: Script = load("res://scripts/ledger.gd")
	var here: Vector3 = current_scene.camera_rig.global_position
	var towns: Array[Vector2] = []
	for far: float in [450.0, 700.0, 850.0, 1100.0]:
		var a := far * 0.01
		towns.append(Vector2(here.x, here.z) + Vector2(cos(a), sin(a)) * far)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	world._shared_tiles.clear()
	var most: int = gen.SHARED_TILES_MOST
	# Every point of every town read once, so that anything read after this is
	# a town paying for its own ground twice.
	ledger.on = true
	gen.reads = 0
	for town: Vector2 in towns:
		for gx in range(-60, 61):
			for gz in range(-60, 61):
				world.seeded_height_at(town.x + gx * 0.5, town.y + gz * 0.5)
	var first_pass: int = gen.reads
	var fresh := 0
	var town_reads := 0
	var trims := 0
	var was := 0
	for frame in 400:
		# The towns, walked in: 120 steps within 30 metres of each centre.
		# (Counted only while the ledger is on, and the shut meter turns it off
		# every frame, so it is turned back on every frame.)
		ledger.on = true
		gen.reads = 0
		for town: Vector2 in towns:
			for i in 120:
				var at := town + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
				world.seeded_height_at(at.x, at.y)
		town_reads += gen.reads
		# New ground, a tile at a time, marching away from everything.
		for i in 8:
			fresh += 1
			world.seeded_height_at(here.x - 2000.0 - fresh * 16.0, here.z + 3000.0)
		var size: int = world._shared_tiles.size()
		if size < was:
			trims += 1
		was = size
		await process_frame
	print("  the store was trimmed %d times; the towns were read %d times at first"
		% [trims, first_pass])
	print("  and %d times again over the next 400 frames" % town_reads)
	check(trims >= 2, "the store filled and was trimmed, more than once")
	check(town_reads < first_pass / 50,
		"the towns' ground is not read again each time it is trimmed")
	check(world._shared_tiles.size() <= most + 8, "and the store stays bounded (%d tiles)"
		% world._shared_tiles.size())
	print("LAND TILES LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
