extends SceneTree
## THE LAND KERNEL AND ITS TWINS — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/kernel_live.gd
##
## Every question the C++ land kernel answers (native/src/land_kernel.*) has a
## GDScript twin that answers it where the library is not built. Asked of both
## at thousands of points, with craters in the land and trees in the way:
##   1. the land as the seed made it;          4. a chunk's whole grid of heights;
##   2. the scars on it;                        5. the ground as a chunk draws it;
##   3. the land as it is (seed and scars);     6. the way round the trees;
## all the same, to the last place a float keeps. And how much faster.
## Where the library is not built there is nothing to compare, and it says so
## and passes. Exits non-zero on failure. Names no class of the game's.

const MANY := 3000

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
	for i in 120:
		await process_frame
	var main: Node = current_scene
	var world: Node = main.world_gen
	var kernel: Object = load("res://scripts/kernel.gd").land()
	print("THE LAND KERNEL AND ITS TWINS")
	if kernel == null:
		print("  the native library is not built here: nothing to compare")
		print("KERNEL LIVE: all pass")
		quit(0)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Craters and a mound, some across bucket lines, where the points will fall.
	for i in 24:
		world.scars.add(i % 4, Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300)),
			rng.randf_range(2.0, 30.0), rng.randf_range(-6.0, 6.0), rng.randf_range(2.0, 5.0))
	world.scars.kernel_ready()

	# 1-3. Point by point.
	var worst_seed := 0.0
	var worst_scar := 0.0
	var worst_land := 0.0
	for i in MANY:
		var x := rng.randf_range(-2000.0, 2000.0)
		var z := rng.randf_range(-2000.0, 2000.0)
		if i % 3 == 0:
			x = rng.randf_range(-320.0, 320.0)       # among the scars
			z = rng.randf_range(-320.0, 320.0)
		worst_seed = maxf(worst_seed, absf(kernel.seeded_height(x, z) - world._seeded_height(x, z)))
		worst_scar = maxf(worst_scar, absf(kernel.offset_at(x, z) - world.scars._offset_here(x, z)))
		var sx := float(roundi(x * 2.0)) / 2.0
		var sz := float(roundi(z * 2.0)) / 2.0
		var twin: float = world._seeded_height(sx, sz) + world.scars._offset_here(x, z)
		worst_land = maxf(worst_land, absf(kernel.height_at(x, z) - twin))
	check(worst_seed < 1e-9, "the land as the seed made it is the same in both (%s)" % String.num_scientific(worst_seed))
	check(worst_scar < 1e-9, "the scars on it are the same in both (%s)" % String.num_scientific(worst_scar))
	check(worst_land < 1e-9, "and the land as it is (%s)" % String.num_scientific(worst_land))

	# 4. A chunk's grid, against the loop the chunk runs without the kernel.
	var grid_worst := 0.0
	var lows := 0.0
	for g in 6:
		var x0 := float(rng.randi_range(-8, 8)) * 48.0
		var z0 := float(rng.randi_range(-8, 8)) * 48.0
		var wide: int = [25, 13, 7][g % 3]
		var step := 48.0 / float(wide - 1)
		var grid: Dictionary = kernel.height_grid(x0, z0, step, wide)
		var heights: PackedFloat32Array = grid["heights"]
		var lowest := INF
		for zz in wide:
			for xx in wide:
				var wx := x0 + xx * step
				var wz := z0 + zz * step
				var h: float = world._seeded_height(float(roundi(wx * 2.0)) / 2.0,
					float(roundi(wz * 2.0)) / 2.0) + world.scars._offset_here(wx, wz)
				var as_kept := PackedFloat32Array([h])
				grid_worst = maxf(grid_worst, absf(heights[zz * wide + xx] - as_kept[0]))
				lowest = minf(lowest, h)
		lows = maxf(lows, absf(float(grid["lowest"]) - lowest))
	check(grid_worst == 0.0 and lows < 1e-9,
		"a chunk's whole grid of heights is the same in both (%s, lowest %s)" % [String.num_scientific(grid_worst), String.num_scientific(lows)])

	# 5. The ground as a chunk draws it.
	var chunk: Node = null
	for c in world.get_children():
		if "terrain_only" in c and not c.terrain_only and c._cells > 0:
			chunk = c
			break
	var drawn_worst := 0.0
	if chunk != null:
		for i in MANY:
			var lx := rng.randf_range(0.0, 48.0)
			var lz := rng.randf_range(0.0, 48.0)
			drawn_worst = maxf(drawn_worst, absf(
				kernel.drawn_local(chunk._heights, chunk._cells, lx, lz) - chunk._drawn_here(lx, lz)))
	check(chunk != null and drawn_worst < 1e-9,
		"the ground as a chunk draws it is the same in both (%s)" % String.num_scientific(drawn_worst))

	# 6. The way round the trees.
	var nav: Node = root.get_node("/root/NavField")
	nav._rebuild()
	var steer_worst := 0.0
	var turned := 0
	var trees: Array = get_nodes_in_group("trees")
	for i in MANY:
		var near: Node3D = trees[i % trees.size()]
		var at: Vector3 = near.global_position + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		var want := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		var ignore := near.global_position if i % 5 == 0 else Vector3.INF
		var a: Vector3 = kernel.steer(at, want, 0.4, ignore, i % 7 == 0)
		var b: Vector3 = nav._steer_here(at, want, 0.4, ignore, i % 7 == 0)
		steer_worst = maxf(steer_worst, (a - b).length())
		if not b.is_equal_approx(want):
			turned += 1
	check(steer_worst < 1e-6 and turned > MANY / 10,
		"the way round the trees is the same in both (%s, %d turned)" % [String.num_scientific(steer_worst), turned])

	# How much faster, for the record.
	var t0 := Time.get_ticks_usec()
	for i in MANY:
		world._seeded_height(float(i), 3.0)
	var gd := float(Time.get_ticks_usec() - t0) / MANY
	t0 = Time.get_ticks_usec()
	for i in MANY:
		kernel.seeded_height(float(i), 3.0)
	var cc := float(Time.get_ticks_usec() - t0) / MANY
	print("    the seed's land: %.2f us in GDScript, %.2f us in C++" % [gd, cc])
	t0 = Time.get_ticks_usec()
	for i in MANY:
		nav._steer_here(trees[0].global_position + Vector3(1, 0, 0), Vector3(1, 0, 0), 0.4)
	gd = float(Time.get_ticks_usec() - t0) / MANY
	t0 = Time.get_ticks_usec()
	for i in MANY:
		kernel.steer(trees[0].global_position + Vector3(1, 0, 0), Vector3(1, 0, 0), 0.4, Vector3.INF, false)
	cc = float(Time.get_ticks_usec() - t0) / MANY
	print("    the way round the trees: %.2f us in GDScript, %.2f us in C++" % [gd, cc])
	print("KERNEL LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
