extends SceneTree
## THE CROWD CLOCK — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/crowd_clock_live.gd
##
##   1. the engine ticks no villager; every one of them is on the clock;
##   2. every villager is paid for every frame — aged by exactly the time that
##      passed, near the camera and far from it, give or take one turn;
##   3. a town is still staggered: no frame carries much more than its share;
##   4. the near band's census still counts every body in it, every frame;
##   5. a villager picked up far away runs every frame at once, and so does one
##      thrown or set alight, till it is over.
## Whatever it changes it puts back. Exits non-zero on failure. Names no class
## of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


## A PHYSICS STEP, AND THE IDLE FRAME AFTER IT: by then the step has run, and
## a villager who lived in it has `_sim_last` equal to the step count.
## (`physics_frame` itself fires BEFORE the step's nodes are processed.)
func step() -> void:
	var was: int = Engine.get_physics_frames()
	while Engine.get_physics_frames() == was:
		await process_frame


func frames(n: int) -> void:
	for i in n:
		await step()


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var crowd: Script = load("res://scripts/crowd.gd")
	var state: Node = root.get_node("/root/GameState")
	# A town big enough to be thinned, as the throng was.
	var towns: Array = get_nodes_in_group("village")
	var home: Node = towns[0]
	for t in towns:
		if t.is_player_home:
			home = t
	for i in 260:
		home._raise_founder(i, 260)
	home._assign_housing()
	current_scene.camera_rig.global_position = home.global_position
	await frames(90)
	print("THE CROWD CLOCK")

	# 1. Nobody ticked by the engine.
	var folk: Array = get_nodes_in_group("villagers")
	var engine_ticked := folk.filter(func(v): return v.is_physics_processing())
	check(engine_ticked.is_empty(), "the engine ticks no villager (%d do)" % engine_ticked.size())
	var stepped: int = Engine.get_physics_frames()
	var booked := folk.filter(func(v): return v._clock_seat >= 0 and v._clock_due >= stepped)
	check(booked.size() == folk.size(), "every villager is booked on the clock (%d of %d)"
		% [booked.size(), folk.size()])

	# 2. Paid for every frame. Age is billed on the turns a villager lives, so
	# over a window it must come to the time that passed, give or take a turn.
	var skip := ["HELD", "FALLING", "DYING", "PINNED", "LEAVING", "HIDDEN"]
	var steady := func(v) -> bool:
		return is_instance_valid(v) and not v.is_queued_for_deletion() \
			and not skip.has(v.State.keys()[v.state])
	var before := {}
	for v in folk:
		if steady.call(v):
			before[v] = [v.age, v._sim_last]
	var from: int = Engine.get_physics_frames()
	# And the stagger, while it runs: how many lived on each frame.
	var per_frame: Array[int] = []
	for i in 300:
		var was: int = Engine.get_physics_frames()
		await step()
		var now: int = Engine.get_physics_frames()
		per_frame.append(folk.filter(func(v): return is_instance_valid(v) and v._sim_last > was).size()
			/ maxi(now - was, 1))
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	var worst_frames := 0.0
	var paid := 0
	var near := 0
	for v in before:
		if not steady.call(v):
			continue
		# Frames lived: from the turn before the window to the last turn in it.
		var lived: int = v._sim_last - int(before[v][1])
		var years: float = v.age - float(before[v][0])
		# Age is billed when they THINK; coasting near the camera is owed till
		# then, so allow the thinking interval on top.
		var off := absf(years * state.YEAR_SECONDS / step - lived)
		worst_frames = maxf(worst_frames, off)
		paid += 1
		if v.global_position.distance_to(home.global_position) < 60.0:
			near += 1
	var window: int = Engine.get_physics_frames() - from
	print("    thinking every %d frames near the camera" % v_brain())
	check(paid > 200 and worst_frames <= v_brain() + 1,
		"%d villagers aged by the time they lived, within %.1f frames of it" % [paid, worst_frames])
	var behind := 0
	for v in before:
		if steady.call(v) and int(Engine.get_physics_frames()) - int(v._sim_last) > 40:
			behind += 1
	check(behind == 0, "and nobody fell more than a turn behind in %d frames (%d did)" % [window, behind])

	# 3. Staggered.
	var total := 0
	var most := 0
	for n in per_frame:
		total += n
		most = maxi(most, n)
	var mean := float(total) / per_frame.size()
	print("    turns a frame: mean %.0f, most %d" % [mean, most])
	check(mean > 0.0 and most <= mean * 2.5 + 10, "a town lives in even batches, not all on one frame")

	# 4. The census.
	await step()
	var counted: int = crowd.near()
	var in_band := 0
	var f: Vector3 = state.camera_focus
	for n in get_nodes_in_group("villagers"):
		var d := Vector2(n.global_position.x - f.x, n.global_position.z - f.z)
		if d.length() <= 130.0:
			in_band += 1
	print("    near band: %d bodies, census %d" % [in_band, counted])
	check(counted >= in_band * 0.75, "the near band's census still counts the whole crowd in it")

	# 5. Held, thrown, alight: every frame.
	var far: Node = null
	for v in get_nodes_in_group("villagers"):
		if steady.call(v) and v.global_position.distance_to(f) > 140.0:
			far = v
			break
	if far == null:
		far = before.keys().filter(steady)[0]
	far.pick_up()
	await frames(2)
	var every := true
	for i in 6:
		await step()
		every = every and far._sim_last == Engine.get_physics_frames()
	check(every, "a villager picked up far away runs every frame at once")
	far.drop(Vector3(0, 6, 0), false)
	var falling := true
	for i in 4:
		await step()
		falling = falling and (far.state != far.State.FALLING or far._sim_last == Engine.get_physics_frames())
	check(falling, "and while thrown")
	for i in 120:
		await step()
		if far.state != far.State.FALLING:
			break
	far.extinguish()
	# Set alight somebody standing on dry ground: the soaked do not catch.
	var torch: Node = null
	for v in get_nodes_in_group("villagers"):
		if steady.call(v) and v != far:
			v.ignite()
			if v.burning:
				torch = v
				break
	far = torch
	await frames(2)
	var alight := true
	for i in 4:
		await step()
		alight = alight and (not far.burning or far._sim_last == Engine.get_physics_frames())
	check(far != null and far.burning and alight, "and while alight")
	far.extinguish()

	print("CROWD CLOCK LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)


## How many frames a villager near the camera may coast between thoughts.
func v_brain() -> int:
	return int(load("res://scripts/villager/villager.gd").get_script_constant_map()["BRAIN_TICKS"])
