extends SceneTree
## FIRE MEETS WATER, AND LAVA CHURNS — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/quench_live.gd
##
##   1. a gout let fall on a lake fizzles at the surface, not on the bed, and
##      it burned and dug nothing;
##   2. a fireblast goes off on the surface, not on the bed, and digs nothing;
##   3. a lavaball into the lake throws burning boulders up out of it, and its
##      core sets as new floor — higher than the bed was, and black, with no
##      ember in it; and enough of them in the shallows make new land;
##   4. a firestorm's orb fizzles at the surface and casts nothing;
##   5. lava poured on land is laid over with a churning skin, on the ground's
##      own surface, that is gone once the lava has crusted over.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0
var main: Node
var world: Node


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await physics_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	main = current_scene
	world = main.world_gen
	# THE CREATURE SITS THIS OUT: it picks up fire within reach and flings it,
	# which once caught the falling gout and threw it fifty metres up.
	main.creature.process_mode = Node.PROCESS_MODE_DISABLED
	await seconds(2.0)
	print("FIRE MEETS WATER")
	var deep := _water_near(Vector2.ZERO, 2.0)
	check(deep != Vector2.INF, "there is open water near home")
	if deep == Vector2.INF:
		_done()
		return
	var top: float = world.water_level_at(deep.x, deep.y)
	main.camera_rig.global_position = Vector3(deep.x, 0.0, deep.y)
	await seconds(1.0)

	# 1. A gout.
	var fire: Script = load("res://scripts/miracles/fireball.gd")
	var scars_before: int = world.scars.count()
	var gout = fire.new()
	gout.kind = "fireball"
	world.add_child(gout)
	gout.global_position = Vector3(deep.x, top + 3.0, deep.y)
	var gout_id: int = gout.get_instance_id()
	var gout_y := INF
	for f in 120:
		await physics_frame
		if not is_instance_id_valid(gout_id):
			break
		gout_y = gout.global_position.y
	var under: float = world.height_at(deep.x, deep.y)
	check(not is_instance_id_valid(gout_id) and gout_y > top - 0.5 and gout_y > under + 1.0,
		"a gout let fall on a lake fizzles at the surface (%.1f), not the bed (%.1f)" % [gout_y, under])
	check(world.scars.count() == scars_before, "and it dug and burned nothing")

	# 2. A blast: it goes off at the surface, well above the bed.
	var blast = fire.new()
	blast.kind = "fireblast"
	world.add_child(blast)
	blast.global_position = Vector3(deep.x, top + 3.0, deep.y)
	var last_y := INF
	var blast_id: int = blast.get_instance_id()
	for f in 120:
		await physics_frame
		if not is_instance_id_valid(blast_id):
			break
		last_y = blast.global_position.y
	var bed: float = world.height_at(deep.x, deep.y)
	check(not is_instance_id_valid(blast_id) and last_y > bed + 1.0 and last_y > top - 0.5,
		"a fireblast goes off on the surface (%.1f), not the bed (%.1f)" % [last_y, bed])
	check(world.scars.count() == scars_before, "and digs no crater under the water")

	# 3. A lavaball into the lake.
	var orb_script: Script = load("res://scripts/miracles/miracle_orb.gd")
	var spot := deep + Vector2(-6.0, 0.0)
	var floor_was: float = world.height_at(spot.x, spot.y)
	var rocks_were := _burning_rocks()
	var orb = orb_script.new()
	orb.miracle_name = "lavaball"
	orb.manager = main.miracles
	world.add_child(orb)
	orb.global_position = Vector3(spot.x, top + 2.0, spot.y)
	orb.linear_velocity = Vector3(0, -6, 0)
	await seconds(0.4)
	var thrown := _burning_rocks() - rocks_were
	check(thrown >= 2, "a lavaball into the lake throws burning boulders up out of it (%d)" % thrown)
	await seconds(2.0)
	var floor_now: float = world.height_at(spot.x, spot.y)
	check(floor_now > floor_was + 0.2,
		"and its core sets as new floor (%.2f -> %.2f)" % [floor_was, floor_now])
	var colour: Color = world.scars.burn_at(spot.x, spot.y)
	check(colour.a > 0.0 and colour.r < 0.3,
		"black rock, with no ember in it (%s)" % str(colour))
	# Enough of them in the shallows and the floor breaks the surface.
	var shallow := _water_near(Vector2.ZERO, 0.5, 1.5)
	var risen := false
	if shallow != Vector2.INF:
		for i in 24:
			main.miracles.resolve("lavaball", Vector3(shallow.x, 0.0, shallow.y))
			await seconds(1.4)
			if not world.is_underwater(shallow.x, shallow.y):
				risen = true
				break
	check(risen, "enough of them in the shallows make new land")

	# 4. A firestorm's orb. A firestorm cast anywhere begins with a gust that
	# shoves everything pickable near it, so a buoy beside it tells whether one was.
	var buoy := RigidBody3D.new()
	buoy.gravity_scale = 0.0
	var ball := CollisionShape3D.new()
	ball.shape = SphereShape3D.new()
	buoy.add_child(ball)
	buoy.add_to_group("pickable")
	world.add_child(buoy)
	buoy.global_position = Vector3(deep.x + 3.0, top + 1.0, deep.y + 3.0)
	var storm = orb_script.new()
	storm.miracle_name = "firestorm"
	storm.manager = main.miracles
	world.add_child(storm)
	storm.global_position = Vector3(deep.x, top + 2.0, deep.y)
	storm.linear_velocity = Vector3(0, -6, 0)
	var storm_id: int = storm.get_instance_id()
	var storm_y := INF
	for f in 60:
		await physics_frame
		if not is_instance_id_valid(storm_id):
			break
		storm_y = storm.global_position.y
	var storm_bed: float = world.height_at(deep.x, deep.y)
	check(not is_instance_id_valid(storm_id) and storm_y > top - 0.5 and storm_y > storm_bed + 1.0,
		"a firestorm's orb fizzles at the surface (%.1f), not the bed (%.1f)" % [storm_y, storm_bed])
	check(buoy.linear_velocity.length() < 0.1,
		"and casts nothing: no gust (%.1f m/s)" % buoy.linear_velocity.length())
	buoy.queue_free()

	# 5. Lava on land.
	var dry := _dry_near(Vector2(60.0, 60.0))
	main.camera_rig.global_position = Vector3(dry.x, 0.0, dry.y)
	await seconds(1.0)
	main.miracles.resolve("lavaball", Vector3(dry.x, 0.0, dry.y))
	await seconds(0.3)
	var skins: Array = get_nodes_in_group("lava_skins")
	var skin: MeshInstance3D = skins[0] if not skins.is_empty() else null
	check(skin != null and skin.mesh != null, "lava poured on land is laid over with a churning skin")
	if skin != null and skin.mesh != null:
		var verts: PackedVector3Array = skin.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var off := 0.0
		for v in verts:
			off = maxf(off, absf(v.y - world.drawn_height_at(v.x, v.z) - skin.LIFT))
		check(verts.size() > 6 and off < 0.02,
			"on the ground's own surface (%d vertices, %.3f m off)" % [verts.size(), off])
		var shader: Shader = (skin.material_override as ShaderMaterial).shader
		check(shader.code.contains("deep_orange") and shader.code.contains("bulbous_red")
			and shader.code.contains("TIME"), "churning deep orange and bulbous red, never still")
		var skin_id := skin.get_instance_id()
		world.scars.clock += 60.0
		await seconds(0.3)
		check(not is_instance_id_valid(skin_id), "and gone once the lava has crusted over")
	_done()


func _burning_rocks() -> int:
	return get_nodes_in_group("rock_deposits").filter(
		func(r): return is_instance_valid(r) and r.ablaze).size()


## Water at least `deep` metres deep (and no deeper than `most`), near `at`.
func _water_near(at: Vector2, deep: float, most := 999.0) -> Vector2:
	for ring in 60:
		for i in 24:
			var p := at + Vector2.from_angle(TAU * i / 24.0) * (20.0 + ring * 12.0)
			var top: float = world.water_level_at(p.x, p.y)
			if is_inf(top):
				continue
			var depth: float = top - world.height_at(p.x, p.y)
			if depth >= deep and depth <= most:
				return p
	return Vector2.INF


func _dry_near(at: Vector2) -> Vector2:
	for i in 400:
		var p := at + Vector2((i % 20) * 3.0, (i / 20) * 3.0)
		if not world.is_underwater(p.x, p.y) and world.slope_at(p.x, p.y) < 0.4:
			return p
	return at


func _done() -> void:
	print("QUENCH LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
