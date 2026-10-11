extends SceneTree
## WHAT IT COSTS TO RAISE A REMEMBERED TOWN — measured, headless:
##
##     godot --headless --path . --script tools/live/unfold_cost.gd [-- souls houses]
##
## Puts a record of a big town (300 souls, 50 houses by default) in loaded land
## beside home and lets the Chessboard raise it, timing every frame until it
## stands: the worst frame, how many frames, and the whole of it. Then raises a
## few houses and people by hand on a standing town, to say what ONE of each
## costs. A measuring stick, not a test: nothing exits non-zero. Names no class
## of the game's (see look.gd).

const SOULS := 300
const HOUSES := 50


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var souls: int = int(args[0]) if args.size() > 0 else SOULS
	var many_houses: int = int(args[1]) if args.size() > 1 else HOUSES
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var saves: Node = root.get_node("/root/SaveGame")
	var state: Node = root.get_node("/root/GameState")
	var main: Node = current_scene
	var world: Node = main.world_gen
	var home: Node = main.village
	await _frames(120)
	# Good ground a little way from home, where the world would found a town.
	var at := Vector2.INF
	for i in 600:
		var probe := Vector2(110.0 + (i % 20) * 9.0, -120.0 + (i / 20) * 9.0)
		if world.village_site_dry(probe.x, probe.y) and world.slope_at(probe.x, probe.y) < 0.8:
			at = probe
			break
	if at == Vector2.INF:
		print("no ground to raise a town on")
		quit(1)
		return
	var folk := []
	for i in souls:
		folk.append({"name": "Soul %d" % i, "female": i % 2 == 0, "age": 4.0 + float(i * 37 % 60),
			"lifespan": 80.0, "health": 100.0, "hunger": 20.0, "energy": 80.0})
	var houses := []
	for i in many_houses:
		houses.append(1)
	saves.village_memory.append({"name": "Bigholm", "home": false, "pos": [at.x, at.y],
		"at_years": state.game_years, "folk": folk, "houses": houses, "farms": 6,
		"store": {"plant": 900, "meat": 100, "lumber": 80, "stone": 80}, "converted": false})
	var town: Node = null
	var began := Time.get_ticks_usec()
	var last := began
	var worst := 0
	var frames := 0
	while Time.get_ticks_usec() - began < 60_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
		if town == null:
			for v in get_nodes_in_group("village"):
				if is_instance_valid(v) and v.village_name == "Bigholm":
					town = v
		elif town.founded and town.my_villagers().size() >= souls * 0.9:
			break
	var took := (Time.get_ticks_usec() - began) / 1000.0
	print("RAISING A REMEMBERED TOWN of %d souls and %d houses:" % [souls, many_houses])
	if town == null or not town.founded:
		print("    it never stood (in %.0f ms)" % took)
	else:
		print("    stood in %.0f ms over %d frames; the worst frame %.1f ms" % [took, frames, worst / 1000.0])
		print("    it has %d souls and %d houses" % [town.my_villagers().size(), town.houses.size()])
	# ONE OF EACH, by hand, on home.
	var t0 := Time.get_ticks_usec()
	for i in 20:
		home._restore_villager({"name": "Extra %d" % i, "age": 30.0, "female": true})
	var one_soul := (Time.get_ticks_usec() - t0) / 20.0
	t0 = Time.get_ticks_usec()
	var placed := 0
	for i in 10:
		var spot: Vector3 = home.find_build_spot(world, 4.0)
		if spot != Vector3.INF:
			placed += 1
	var one_spot := (Time.get_ticks_usec() - t0) / 10.0
	print("    one soul raised: %.2f ms; one house spot found: %.2f ms (%d of 10 found)"
		% [one_soul / 1000.0, one_spot / 1000.0, placed])
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
