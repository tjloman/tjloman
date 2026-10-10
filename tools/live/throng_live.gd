extends SceneTree
## A THRONG: the world filled to the size of the one on the screenshots, and
## what each frame of it costs — run headless:
##
##     godot --headless --path . --script tools/live/throng_live.gd [-- souls frames]
##
## A screenshot came back at 1,400 souls and 7.5 frames a second, with one
## villager call of 19.4 ms in it. This builds that world on demand: founders
## raised into the towns that are already there, the home town to 300 and the
## rest spread over the others, the camera on the home town. Then it watches the
## frame meter's own ledger for a while and prints:
##
##   * the frame, wall clock: middle, 90th, worst;
##   * the bill, summed over the run, dearest first;
##   * every single call over SLOW_CALL ms: which class, what it was doing.
##
## Nothing is checked here and nothing exits non-zero — it is a measuring
## stick, not a test. Run it before and after a change and read the two.
## Names no class of the game's (see look.gd).

const SOULS := 1400
const HOME_SOULS := 300
const FRAMES := 900
const SLOW_CALL := 4.0


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var souls: int = int(args[0]) if args.size() > 0 else SOULS
	var watch: int = int(args[1]) if args.size() > 1 else FRAMES
	change_scene_to_file("res://scenes/main.tscn")
	await frames(150)
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var ledger: Script = load("res://scripts/ledger.gd")
	var towns: Array = get_nodes_in_group("village")
	var home: Node = null
	for t in towns:
		if t.is_player_home:
			home = t
	if home == null:
		home = towns[0]
	var had := 0
	for t in towns:
		had += t.my_villagers().size()
	print("THE THRONG: %d towns, %d souls to begin with" % [towns.size(), had])

	# Raise founders: the home town to HOME_SOULS, the rest evenly elsewhere.
	var t0 := Time.get_ticks_msec()
	var want_home := maxi(HOME_SOULS - home.my_villagers().size(), 0)
	var others := towns.filter(func(t): return t != home)
	var each := 0
	if not others.is_empty():
		@warning_ignore("integer_division")
		each = maxi(souls - had - want_home, 0) / others.size()
	for t in towns:
		var add := want_home if t == home else each
		for i in add:
			t._raise_founder(i, add)
		t._assign_housing()
	var now := 0
	for t in towns:
		now += t.my_villagers().size()
	print("  raised to %d souls in %d ms (%s has %d)" % [now, Time.get_ticks_msec() - t0,
		home.village_name, home.my_villagers().size()])

	var main: Node = current_scene
	main.camera_rig.global_position = home.global_position
	await frames(60)

	var meter: Node = root.find_children("FrameMeter", "", true, false)[0]
	meter.visible = true
	ledger.forget_worst()
	var walls: Array[float] = []
	var bill := {}
	var calls := {}
	var slow := []
	var last := Time.get_ticks_usec()
	for f in watch:
		await process_frame
		var at := Time.get_ticks_usec()
		walls.append(float(at - last) / 1000.0)
		last = at
		for row: Array in ledger.rows():
			bill[row[0]] = float(bill.get(row[0], 0.0)) + float(row[1])
			calls[row[0]] = int(calls.get(row[0], 0)) + int(row[2])
		var worst: Array = ledger.slowest_call()
		if not worst.is_empty() and float(worst[2]) > SLOW_CALL:
			slow.append([f, worst[0], str(worst[1]), float(worst[2])])
	meter.visible = false

	var sorted := walls.duplicate()
	sorted.sort()
	var alive := 0
	for t in towns:
		if is_instance_valid(t):
			alive += t.my_villagers().size()
	print("  %d frames, %d souls at the end" % [watch, alive])
	print("  frame: middle %.1f ms, 90th %.1f ms, worst %.1f ms"
		% [sorted[int(sorted.size() * 0.5)], sorted[int(sorted.size() * 0.9)], sorted[-1]])
	var rows := []
	for k in bill:
		rows.append([k, bill[k], calls[k]])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	print("  THE BILL, a frame on average:")
	for r in rows.slice(0, 12):
		print("    %-28s %8.2f ms  %7.0f calls" % [r[0], r[1] / watch, float(r[2]) / watch])
	print("  CALLS OVER %.0f ms: %d" % [SLOW_CALL, slow.size()])
	slow.sort_custom(func(a, b): return a[3] > b[3])
	for s in slow.slice(0, 25):
		print("    frame %4d  %-20s %-14s %6.1f ms" % s)
	quit(0)
