extends SceneTree
## THE PLAYER'S GRAPHICS — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/graphics_live.gd
##
##   1. the rings slider applies at once: the land held, the far plane, the fog;
##   2. MSAA is its own switch, and the screen follows it;
##   3. glow is for HIGH alone;
##   4. the land in front of the camera is built before the land beside and
##      behind it — near ring and far ring both;
##   5. the sea is pale over the shallows and dark over the deeps;
##   6. and the settings wall's slider and box do all of that from the screen.
## Whatever it changes it puts back. Exits non-zero on failure. Names no class of
## the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await frames(120)
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var quality: Node = root.get_node("/root/Quality")
	var main: Node = current_scene
	var world: Node = main.world_gen
	var rig: Node = main.camera_rig
	var was_rings: int = quality.rings
	var was_msaa: bool = quality.msaa
	var was_cap: int = quality.fps_cap
	print("THE PLAYER'S GRAPHICS")

	# 1. Rings.
	quality.set_rings(9)
	await frames(3)
	check(world.sight_radius == 9, "nine rings: the land held is nine rings (%d)" % world.sight_radius)
	check(is_equal_approx(rig.camera.far, 9 * 48.0 - 12.0),
		"and the far plane is at its edge (%.0f m)" % rig.camera.far)
	var env: Environment = main._environment
	check(env.fog_mode == Environment.FOG_MODE_DEPTH
		and is_equal_approx(env.fog_depth_end, rig.camera.far)
		and is_equal_approx(env.fog_depth_begin, rig.camera.far * quality.FOG_BEGINS),
		"and the fog is clear to %.0f m and closed at the edge" % env.fog_depth_begin)
	quality.set_fog(false)
	check(not env.fog_enabled, "fog off: none")
	quality.set_fog(true)
	check(env.fog_enabled, "fog on again")
	quality.set_rings(40)
	check(quality.rings == quality.RINGS_MOST, "the slider stops at %d" % quality.RINGS_MOST)
	quality.set_rings(was_rings)
	await frames(3)

	# 2. MSAA.
	quality.set_msaa(false)
	check(root.msaa_3d == Viewport.MSAA_DISABLED, "MSAA off: the screen draws without it")
	quality.set_msaa(true)
	check(root.msaa_3d == Viewport.MSAA_2X, "MSAA on: 2x, whatever the tier")
	quality.set_msaa(was_msaa)

	# 2b. The frame cap, and a thermostat that does not mistake it for strain.
	quality.set_fps_cap(30)
	check(Engine.max_fps == 30, "held to 30: the engine waits out the rest of each frame")
	var warm: float = quality._line(quality.FRAME_WARM, quality.CAPPED_WARM)
	var cool: float = quality._line(quality.FRAME_COOL, quality.CAPPED_COOL)
	check(warm > 1.0 / 30.0 * 1.2 and cool > 1.0 / 30.0,
		"and a steady 33 ms is neither warm nor short of fine (warm past %.0f ms)" % (warm * 1000.0))
	quality.set_fps_cap(20)
	check(quality._line(quality.FRAME_HOT, quality.CAPPED_HOT) > 0.05 * 1.5,
		"held to 20, a steady 50 ms is not called hot")
	quality.set_fps_cap(45)
	check(quality.fps_cap == 20, "only the four notches are taken (45 refused)")
	quality.set_fps_cap(0)
	check(Engine.max_fps == 0 and is_equal_approx(warm, warm) \
		and is_equal_approx(quality._line(quality.FRAME_WARM, quality.CAPPED_WARM), quality.FRAME_WARM),
		"uncapped: no cap, and the thermostat's own lines")
	quality.set_fps_cap(was_cap)

	# 3. Glow.
	var tier: int = quality.tier
	quality.tier = 1
	var medium: bool = quality.glow()
	quality.tier = 2
	var high: bool = quality.glow()
	quality.tier = tier
	check(not medium and high, "glow on HIGH, and not on MEDIUM")

	# 4. Ahead first. Somewhere nobody has been, facing east.
	rig.global_position = Vector3(4800.0, 0.0, 4800.0)
	rig.rotation.y = -PI * 0.5          # -Z turned to +X: facing east
	await frames(2)
	var seen := {}
	for cell in world._chunks.keys():
		seen[cell] = true
	var order: Array[Vector2i] = []
	var refilling := false
	for i in 3000:
		await process_frame
		for cell in world._chunks.keys():
			if not seen.has(cell):
				seen[cell] = true
				order.append(cell)
		# Filled again since the move — the flag is still up from before it
		# until the far ring is next swept, so wait for it to have gone down.
		refilling = refilling or not world._sight_filled
		if refilling and world._sight_filled:
			break
	var centre := Vector2i(floori(rig.global_position.x / 48.0), floori(rig.global_position.z / 48.0))
	# The near band and the far band are each filled ahead-first: inside each,
	# no cell ahead may come after one beside or behind.
	check(order.size() > 20, "the land was built after the move (%d cells)" % order.size())
	for band in ["near", "far"]:
		var late := 0
		var side_seen := false
		for cell in order:
			var ring: int = maxi(absi(cell.x - centre.x), absi(cell.y - centre.y))
			if (ring <= world.load_radius) != (band == "near"):
				continue
			if not world._ahead(centre, cell):
				side_seen = true
			elif side_seen:
				late += 1
		check(late == 0, "%s ring: nothing ahead was built after anything beside or behind (%d)"
			% [band, late])

	# 5. The sea by depth.
	var darkest := 1.0
	var palest := 0.0
	for chunk in world._chunks.values():
		var water: MeshInstance3D = chunk._water
		if water == null or not is_instance_valid(water) or water.mesh == null:
			continue
		var colours: PackedColorArray = water.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for c in colours:
			darkest = minf(darkest, c.get_luminance())
			palest = maxf(palest, c.get_luminance())
	print("    water: palest %.2f, darkest %.2f" % [palest, darkest])
	check(palest - darkest > 0.3, "the sea is pale in the shallows and dark in the deeps")
	# AND IT FACES UP. The ground's material draws both sides, so a sea wound
	# the ground's way round looked right in every test that read the mesh and
	# was culled away on the screen — the lake bed showing through where the
	# water should be. Wound as Godot's own upward plane is wound, or nothing.
	var plane := PlaneMesh.new()
	var up: PackedVector3Array = plane.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var plane_idx: PackedInt32Array = plane.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var want := signf((up[plane_idx[1]] - up[plane_idx[0]]).cross(up[plane_idx[2]] - up[plane_idx[0]]).y)
	var wrong := 0
	var faces := 0
	for chunk in world._chunks.values():
		var water: MeshInstance3D = chunk._water
		if water == null or not is_instance_valid(water) or water.mesh == null:
			continue
		var v: PackedVector3Array = water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size(), 3):
			faces += 1
			if signf((v[i + 1] - v[i]).cross(v[i + 2] - v[i]).y) != want:
				wrong += 1
	check(faces > 0 and wrong == 0, "every face of the sea is wound to face up (%d of %d wrong)"
		% [wrong, faces])
	var tint: Script = load("res://scripts/world/chunk.gd")
	var shallow: Color = tint.water_tint(0.2, true)
	var deep: Color = tint.water_tint(20.0, true)
	check(shallow.a < deep.a and deep.get_luminance() < shallow.get_luminance(),
		"and on the clear tiers the shallows let more of the bottom through")
	check(tint.water_tint(0.2, false).a == 1.0, "and LOW's water is opaque")
	var edge: Color = tint.water_tint(0.0, true)
	var off_shore: Color = tint.water_tint(1.0, true)
	check(edge.get_luminance() > 0.85 and off_shore.get_luminance() < edge.get_luminance() - 0.15,
		"foam at the water's very edge, gone a metre out")

	# 6. The settings wall itself: the slider and the box, as a player uses them.
	var wall: ScrollContainer = load("res://scripts/ui/temple_rites.gd").new()
	root.add_child(wall)
	await frames(2)
	var slider: HSlider = wall.find_children("*", "HSlider", true, false) \
		.filter(func(n): return n.max_value == quality.RINGS_MOST)[0]
	check(slider.min_value == 3 and slider.max_value == 12 and slider.step == 1.0
		and slider.tick_count == 10, "the slider runs 3 to 12, one notch a ring")
	slider.value = 9
	check(quality.rings == 9 and wall._rings_said.text.contains("caution"),
		"dragged to 9: nine rings, and a caution (%s)" % wall._rings_said.text)
	slider.value = 5
	check(quality.rings == 5 and wall._rings_said.text.contains("recommended"),
		"at 5: recommended (%s)" % wall._rings_said.text)
	var box: CheckBox = wall.find_children("*", "CheckBox", true, false) \
		.filter(func(n): return n.text.contains("MSAA"))[0]
	box.button_pressed = not was_msaa
	check(quality.msaa != was_msaa, "the MSAA box switches it")
	box.button_pressed = was_msaa
	var caps: HSlider = wall.find_children("*", "HSlider", true, false) \
		.filter(func(n): return n.max_value == quality.FPS_CAPS.size() - 1)[0]
	check(caps.tick_count == 4, "the frame-rate slider has four notches")
	caps.value = 3
	check(quality.fps_cap == 0 and wall._cap_said.text.contains("caution"),
		"at the last notch: uncapped, and a caution (%s)" % wall._cap_said.text)
	caps.value = 1
	check(quality.fps_cap == 30, "at the second: 30")
	wall.queue_free()
	quality.set_fps_cap(was_cap)
	quality.set_rings(was_rings)
	quality.set_msaa(was_msaa)

	print("GRAPHICS LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
