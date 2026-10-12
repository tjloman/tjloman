extends SceneTree
## WHAT EACH PIECE OF A VILLAGER'S TURN COSTS — measured, headless:
##
##     godot --headless --path . --script tools/live/unit_costs.gd
##
## Calls each building block of a turn many times on a real villager in a real
## town and prints microseconds a call. A measuring stick for choosing what is
## worth moving into native code: nothing exits non-zero. Names no class of the
## game's (see look.gd).

const MANY := 20000


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var main: Node = current_scene
	var world: Node = main.world_gen
	for i in 240:
		await process_frame
	var who: Node = null
	for v in main.village.my_villagers():
		if is_instance_valid(v) and v.age > 16.0:
			who = v
			break
	var nav: Node = root.get_node("/root/NavField")
	var pose: Script = load("res://scripts/villager/villager_pose.gd")
	var words: Script = load("res://scripts/villager/villager_words.gd")
	var feet: Script = load("res://scripts/villager/villager_feet.gd")
	var at: Vector3 = who.global_position
	var fwd := Vector3(1, 0, 0)
	print("A VILLAGER'S TURN, PIECE BY PIECE (microseconds a call)")
	_time("an empty loop", func(i): pass)
	_time("height_at (shared tile)", func(i): world.height_at(at.x + (i % 7) * 0.5, at.z))
	_time("height_at (fresh ground)", func(i): world.height_at(at.x + i * 0.37, at.z + 900.0))
	_time("drawn_height_at", func(i): world.drawn_height_at(at.x + (i % 13) * 0.3, at.z))
	_time("is_underwater", func(i): world.is_underwater(at.x + (i % 7) * 0.5, at.z))
	_time("water_level_at", func(i): world.water_level_at(at.x + (i % 7) * 0.5, at.z))
	_time("NavField.steer", func(i): nav.steer(at + Vector3((i % 9) * 0.2, 0, 0), fwd, 0.4))
	_time("NavField.water_route (fresh)", func(i):
		who.remove_meta("route_at")
		nav.water_route(who, at, fwd, world, 1.7))
	_time("NavField.water_route (kept)", func(i): nav.water_route(who, at, fwd, world, 1.7))
	_time("VillagerFeet.step_by (0 m)", func(i): feet.step_by(who, Vector3.ZERO))
	_time("look_at", func(i): who.look_at(who.global_position + Vector3(cos(i), 0, sin(i)), Vector3.UP))
	_time("VillagerPose.apply", func(i): pose.apply(who))
	_time("VillagerWords.status_text", func(i): words.status_text(who))
	_time("get_meta", func(i): who.get_meta("stroll_legs", 0))
	_time("set_meta", func(i): who.set_meta("probe_x", i))
	quit(0)


func _time(what: String, call: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	for i in MANY:
		call.call(i)
	var each := float(Time.get_ticks_usec() - t0) / MANY
	print("  %-34s %7.2f" % [what, each])
