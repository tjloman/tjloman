extends SceneTree
## BURNING EARTH IS FEARED AND WALKED ROUND — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/hot_ground_live.gd
##
##   1. lava poured beside a town sends the people who can see it running (the
##      children into shelter), and they run away from it (HotGround.frighten,
##      from LavaSkin);
##      and the heat is only where the lava lies, not in the town's ground it
##      landed on (TerrainScars.deposit);
##   2. somebody sent straight across a molten pool goes round it and never
##      sets foot on ground too hot to walk (HotGround.heading, VillagerFeet);
##   3. and the same inside their own town, where the water check is skipped;
##   4. somebody standing in it catches fire (Villager._tick_hazards), and the
##      way they are told to step takes them somewhere cooler;
##   5. once it has cooled, the way straight across is open again.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0
var main: Node
var world: Node
var hot: Script


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
	hot = load("res://scripts/villager/hot_ground.gd")
	main.creature.process_mode = Node.PROCESS_MODE_DISABLED   # it picks fire up
	await seconds(2.0)
	print("BURNING EARTH")
	var home: Node = main.village
	var folk: Array = home.my_villagers()
	check(folk.size() >= 10, "%s has people to frighten (%d)" % [home.village_name, folk.size()])
	if folk.size() < 10:
		_done()
		return

	# 1. Poured beside them, on open dry ground near the middle of the crowd.
	var spot := _open_ground(_middle_of(folk))
	main.camera_rig.global_position = spot
	main.miracles.resolve("lavaball", spot)
	await seconds(0.6)
	var skin: Node = _skin_near(spot)
	check(skin != null, "the lava lies molten on the ground")
	if skin == null:
		_done()
		return
	# And only where it lies: not merged into the broad basins a town stands on.
	var beyond: float = world.scars.heat_at(skin.centre.x + skin.radius + 2.0, skin.centre.y)
	check(beyond == 0.0, "and only where it lies: no heat %.1f m past its rim (%.2f)" % [2.0, beyond])
	var centre := Vector3(skin.centre.x, 0.0, skin.centre.y)
	var sees: float = skin.radius + hot.SEEN_FROM
	var near := []
	for one in home.my_villagers():
		if not one.burning and _flat(one.global_position, centre) < sees:
			near.append(one)
	# A CHILD TAKES SHELTER rather than running (ChildSafety): that is their fear.
	var running := near.filter(func(one): return one.is_afraid())
	var sheltering := near.filter(func(one): return one.sheltering)
	check(near.size() >= 3 and running.size() + sheltering.size() >= near.size() * 0.7,
		"of %d who can see it, %d run and %d children take shelter"
		% [near.size(), running.size(), sheltering.size()])
	var was := 0.0
	for one in running:
		was += _flat(one.global_position, centre)
	await seconds(2.0)
	var now := 0.0
	for one in running:
		if is_instance_valid(one):
			now += _flat(one.global_position, centre)
	check(not running.is_empty() and now > was + running.size() * 2.0,
		"and they run away from it (%.1f m further each)" % ((now - was) / maxf(running.size(), 1)))

	# 2 and 3. Across it, out in the open and as a townsman going about the town.
	var walker = folk[0]
	walker.process_mode = Node.PROCESS_MODE_DISABLED
	walker.extinguish()
	for placed in [false, true]:
		main.miracles.resolve("lavaball", spot)           # hot again for the walk
		await physics_frame
		var reach: float = skin.radius
		var from: Vector3 = centre + Vector3(-(reach + 3.0), 0.0, 0.0)
		var to: Vector3 = centre + Vector3(reach + 3.0, 0.0, 0.0)
		walker.global_position = Vector3(from.x, world.height_at(from.x, from.z), from.z)
		var hottest := 0.0
		var arrived := false
		for f in 900:
			await physics_frame
			arrived = walker.call("_move_toward", to, 3.0, 1.0 / 30.0, 0.9, placed)
			var at: Vector3 = walker.global_position
			hottest = maxf(hottest, world.scars.heat_at(at.x, at.z))
			if arrived:
				break
		# A step LOOKED AT is refused past TOO_HOT; the feet may brush the
		# fringe between looks, a whisker past it and nowhere near catching.
		check(arrived and hottest <= hot.TOO_HOT + 0.05,
			"sent across it%s: round it (%s), never hotter than %.3f underfoot"
			% [" inside the town" if placed else "", "there" if arrived else "NOT there", hottest])

	# 4. Standing in it.
	main.miracles.resolve("lavaball", spot)
	await physics_frame
	walker.global_position = Vector3(centre.x, world.height_at(centre.x, centre.z), centre.z)
	walker.call("_tick_hazards", 0.5)
	check(walker.burning, "somebody standing in it catches fire")
	walker.extinguish()
	# Off the middle, and wanting to go further in: the way they are told to
	# step must take them out instead.
	var inside: Vector3 = centre + Vector3(skin.radius * 0.4, 0.0, 0.0)
	var out: Vector3 = hot.heading(walker, inside, Vector3.LEFT, world, 1.7)
	var here: float = world.scars.heat_at(inside.x, inside.z)
	var there: float = world.scars.heat_at(inside.x + out.x * 1.7, inside.z + out.z * 1.7)
	check(out != Vector3.ZERO and there < here,
		"and, wanting to go further in, steps out the coolest way (%.2f to %.2f)" % [here, there])

	# 5. Cooled.
	world.scars.clock += 60.0
	var across: Vector3 = hot.heading(null, centre + Vector3(-(skin.radius + 1.0), 0, 0), Vector3.RIGHT, world, 1.7)
	check(not world.scars.hot_anywhere() and across.is_equal_approx(Vector3.RIGHT),
		"cooled, and the way straight across is open")
	_done()


func _middle_of(folk: Array) -> Vector3:
	var sum := Vector3.ZERO
	for one in folk:
		sum += one.global_position
	return sum / float(folk.size())


## Dry, gentle ground near `at`, clear of the town's buildings.
func _open_ground(at: Vector3) -> Vector3:
	for ring in 12:
		for i in 12:
			var p := at + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 12.0) * (4.0 + ring * 3.0)
			if not world.is_underwater(p.x, p.z) and world.slope_at(p.x, p.z) < 0.35:
				return Vector3(p.x, world.height_at(p.x, p.z), p.z)
	return at


func _skin_near(at: Vector3) -> Node:
	for one in get_nodes_in_group("lava_skins"):
		if is_instance_valid(one) and Vector2(at.x, at.z).distance_to(one.centre) < one.radius + 2.0:
			return one
	return null


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _done() -> void:
	print("HOT GROUND LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
