extends SceneTree
## WHAT A LIVE TOWN ACTUALLY BRINGS IN — measured, headless, so the chessboard's
## rates for a town out of sight can be held to it:
##
##     godot --headless --path . --script tools/live/calibrate_live.gd [-- days]
##
## Runs the home town for a few game days at four times speed with Yields
## switched on, sampling how many hands are at each job, and prints, by source:
## meals a game year, meals a hand-year, and for the fields meals a field-year;
## berries a bush-year; and what a grown person actually eats a year. Those are
## the numbers TownRules' FIELD_YIELD, FISH_PER_HAND, HUNT_PER_HAND,
## BERRIES_PER_HAND and EAT_ADULT stand for. A measuring stick, not a test:
## nothing exits non-zero. Names no class of the game's (see look.gd).

const DAYS := 3.0
const SPEED := 4.0
## Which job's hands bring in which source's meals.
const HANDS_FOR := {"farm": "farm", "fish": "fish", "boat": "fish", "hunt": "hunt",
	"skin": "skin", "butcher": "butcher"}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var days: float = float(args[0]) if args.size() > 0 else DAYS
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var state: Node = root.get_node("/root/GameState")
	var yields: Script = load("res://scripts/world/board/yields.gd")
	var town: Node = current_scene.village
	await _frames(120)
	var day_years: float = state.get_script().get_script_constant_map()["DAY_YEARS"]
	yields.clear()
	yields.on = true
	# The hand sets the world's speed every frame (it slows time while a rune is
	# drawn): out of the way while this runs, or nothing speeds up.
	var hand: Node = current_scene.divine_hand
	hand.process_mode = Node.PROCESS_MODE_DISABLED
	Engine.time_scale = SPEED
	var from: float = state.game_years
	var store0: int = town.store.total_food()
	var hands := {}
	var samples := 0
	var souls := 0.0
	var grown := 0.0
	var fields := 0.0
	var t0 := Time.get_ticks_msec()
	while state.game_years - from < days * day_years:
		await _frames(10)
		samples += 1
		for job: String in town.job_counts():
			hands[job] = float(hands.get(job, 0.0)) + float(town.job_counts()[job])
		var folk: Array = town.my_villagers()
		souls += folk.size()
		grown += folk.filter(func(v): return v.is_adult()).size()
		fields += town.farms.size()
	Engine.time_scale = 1.0
	hand.process_mode = Node.PROCESS_MODE_INHERIT
	yields.on = false
	var years: float = state.game_years - from
	var bushes := _bushes_near(town.global_position, 120.0)
	print("WHAT A LIVE TOWN BRINGS IN: %s, %.1f game years (%.1f days) in %.0f s" % [
		town.village_name, years, years / day_years, (Time.get_ticks_msec() - t0) / 1000.0])
	print("    on average %.0f souls, %.0f grown, %.1f fields, %d berry bushes within 120 m" % [
		souls / samples, grown / samples, fields / samples, bushes])
	for source: String in yields.meals:
		var got: float = yields.meals[source]
		var job: String = HANDS_FOR.get(source, "")
		var at := float(hands.get(job, 0.0)) / samples
		var line := "    %-8s %7.0f meals  %6.1f a year" % [source, got, got / years]
		if at > 0.0:
			line += "  %5.1f hands  %6.2f a hand-year" % [at, got / years / at]
		if source == "farm" and fields > 0.0:
			line += "  %6.2f a field-year" % (got / years / (fields / samples))
		if source == "berries" and bushes > 0:
			line += "  %6.2f a bush-year" % (got / years / bushes)
		print(line)
	var eaten: float = yields.eaten
	print("    the store went %d -> %d; %.0f meals eaten: %.2f a grown person a year" % [
		store0, town.store.total_food(), eaten, eaten / years / maxf(grown / samples, 1.0)])
	print("    hands at work, on average: %s" % _avg(hands, samples))
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _avg(hands: Dictionary, samples: int) -> String:
	var parts := []
	for job: String in hands:
		parts.append("%s %.1f" % [job, float(hands[job]) / samples])
	return ", ".join(parts)


func _bushes_near(at: Vector3, reach: float) -> int:
	var n := 0
	for bush in root.find_children("*", "StaticBody3D", true, false):
		if bush.get_script() != null and String(bush.get_script().get_global_name()) == "ForageBush" \
				and bush.global_position.distance_to(at) < reach:
			n += 1
	return n
