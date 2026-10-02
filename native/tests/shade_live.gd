extends SceneTree
## THE SHADE EXTENSION, CHECKED INSIDE GODOT: the built library loaded by a real
## engine, baking real meshes and following real lights. Headless, no window:
##
##     godot --headless --path . --script native/tests/shade_live.gd
##
## (tools/shade.py runs it too, when the GODOT environment variable names a
## Godot binary.) Exits non-zero on any failure. The headless renderer keeps no
## global shader values, so what the sky SENT is read back from the sky itself.

var fails := 0

func check(ok: bool, what: String) -> void:
	print("  %-60s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1

func _initialize() -> void:
	print("SHADE, LIVE")
	check(ClassDB.class_exists(&"ShadowSky") and ClassDB.class_exists(&"ShadowBaker"), "both classes registered")
	var baker = ClassDB.instantiate(&"ShadowBaker")
	var cap := CapsuleMesh.new()
	var hull: ArrayMesh = baker.bake(cap)
	var cap_v: int = cap.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	check(hull != null and hull.get_surface_count() == 1, "a capsule bakes to one surface")
	var hv: PackedVector3Array = hull.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var hi: PackedInt32Array = hull.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	print("    capsule: %d vertices in, %d points and %d triangles out" % [cap_v, hv.size(), hi.size() / 3])
	var box: ArrayMesh = baker.bake(BoxMesh.new())
	check(box != null and box.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 8, "a box bakes to its eight corners")
	check(baker.bake(PlaneMesh.new()) == null, "a flat plane casts nothing")
	check(baker.bake(null) == null, "nothing casts nothing")
	var aabb := hull.get_aabb()
	var want := cap.get_aabb()
	check(aabb.position.is_equal_approx(want.position) or aabb.position.distance_to(want.position) < 0.05,
		"the hull keeps the model's own space (feet where they were)")

	var sky = ClassDB.instantiate(&"ShadowSky")
	sky.set(&"day_seconds", 320.0)
	root.add_child(sky)
	sky.set_day(0.5)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 7.0
	lamp.omni_range = 22.0
	lamp.position = Vector3(3, 2, 0)
	root.add_child(lamp)
	sky.follow(lamp)
	await process_frame
	await process_frame
	var sun: Vector4 = sky.get_sent_sun()
	print("    shade_sun at noon: ", sun)
	check(absf(sun.y + 1.0) < 1e-3 and sun.w > 0.4, "noon: straight down, full shadow")
	var slot: Vector4 = sky.get_sent_light(0)
	var power: Vector4 = sky.get_sent_power()
	print("    shade_light_0: ", slot, "  power: ", power)
	check(slot.is_equal_approx(Vector4(3, 2, 0, 22)) and power.x > 0.99, "the followed light is handed to the shader")
	check(int(sky.get_burning()) == 1 and int(sky.get_alive()) == 1, "one burning, one alive")
	lamp.queue_free()
	await process_frame
	await process_frame
	power = sky.get_sent_power()
	check(power.x == 0.0 and int(sky.get_alive()) == 0, "a freed light is forgotten and its slot emptied")
	sky.flash(Vector3(0, 3, 0), 10.0, 4.0, 0.5)
	await process_frame
	await process_frame
	power = sky.get_sent_power()
	check(power.x > 0.0 and power.x < 1.0, "a flash burns and is already fading")
	sky.set_day(0.0)
	await process_frame
	sun = sky.get_sent_sun()
	check(sun.w == 0.0, "midnight: no sun shadow")
	var shader: Shader = load("res://shaders/baked_shadow.gdshader")
	check(shader != null and shader.get_mode() == Shader.MODE_SPATIAL, "the shader loads")
	print("\n%s" % ("Success: no problems found" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails else 0)
