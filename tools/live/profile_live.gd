extends SceneTree
## WHERE THE FRAMES GO — measured, headless, with the frame meter on:
##
##     godot --headless --path . --script tools/live/profile_live.gd [-- scenario seconds]
##
## Scenarios:
##   town    a remembered town of 300 raised beside home, the camera on it,
##           then held there: the steady cost of a big town in view;
##   travel  the camera driven across the map at a brisk walk: chunks, herds and
##           towns coming and going;
##   both    (default) the town, then the travel.
##
## Prints the frame times (mean, 95th percentile, worst), every row of the bill
## by its mean per frame, calls a frame, cost a call and worst, and each frame
## over SPIKE_MS with what was in it. A measuring stick, not a test: nothing
## exits non-zero. Names no class of the game's (see look.gd).

const SPIKE_MS := 50.0
const TRAVEL_SPEED := 9.0         # metres a second, about the hand dragging the land

var main: Node
var world: Node
var rig: Node3D
var ledger: Script
var _frames := []                 # [ms, {row: ms}, {row: calls}]
var _nodes_then := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "both"
	var secs: float = float(args[1]) if args.size() > 1 else 30.0
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	main = current_scene
	world = main.world_gen
	rig = main.camera_rig
	ledger = load("res://scripts/ledger.gd")
	var meter: Node = root.find_child("FrameMeter", true, false)
	if meter != null:
		meter.visible = true
	# MARKERS AT THE HEAD OF EACH STEP, so what no script clocks is split: the
	# engine's work after a physics step (its solve, deferred calls) from the
	# work after the idle frame (freeing, rendering, the frame cap's sleep).
	var heads: Script = load("res://tools/live/profile_heads.gd")
	root.add_child(heads.new())
	Engine.max_fps = 0
	await _settle(4.0)
	if scenario in ["town", "both"]:
		await _raise_a_town()
		_report("A TOWN OF 300 IN VIEW", await _measure(secs, false))
	if scenario in ["travel", "both"]:
		_report("TRAVELLING", await _measure(secs, true))
	quit(0)


func _settle(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


## A REMEMBERED TOWN of 300 beside home, raised by the board as it would be, and
## the camera put on it.
func _raise_a_town() -> void:
	var saves: Node = root.get_node("/root/SaveGame")
	var state: Node = root.get_node("/root/GameState")
	var at := Vector2.INF
	for i in 600:
		var probe := Vector2(110.0 + (i % 20) * 9.0, -120.0 + (i / 20) * 9.0)
		if world.village_site_dry(probe.x, probe.y) and world.slope_at(probe.x, probe.y) < 0.8:
			at = probe
			break
	if at == Vector2.INF:
		print("no ground to raise a town on")
		return
	var folk := []
	for i in 300:
		folk.append({"name": "Soul %d" % i, "female": i % 2 == 0, "age": 4.0 + float(i * 37 % 60),
			"lifespan": 80.0, "health": 100.0, "hunger": 20.0, "energy": 80.0})
	var houses := []
	for i in 50:
		houses.append(1)
	saves.village_memory.append({"name": "Bigholm", "home": false, "pos": [at.x, at.y],
		"at_years": state.game_years, "folk": folk, "houses": houses, "farms": 6,
		"store": {"plant": 900, "meat": 100, "lumber": 80, "stone": 80}, "converted": true,
		"belief": 80.0, "trades": {"well": 6, "mill": 5, "barn": 1, "shrine": 3}, "edubba": true,
		"kept": {"pig": 30}})
	var town: Node = null
	var until := Time.get_ticks_msec() + 60000
	var solver_worst := 0.0
	var at_switch := -1.0
	while Time.get_ticks_msec() < until:
		await process_frame
		var solver := 0.0
		for row: Array in ledger.rows():
			if row[0] == "(the solver)":
				solver = float(row[1])
		solver_worst = maxf(solver_worst, solver)
		if town == null:
			for v in get_nodes_in_group("village"):
				if is_instance_valid(v) and v.village_name == "Bigholm":
					town = v
		elif town.founded:
			# The frame it stood, and the one after: the solver as it took the
			# town back into the physics world.
			for k in 12:
				await process_frame
				for row: Array in ledger.rows():
					if row[0] == "(the solver)":
						at_switch = maxf(at_switch, float(row[1]))
			break
	print("    the solver while it was raised: worst %.1f ms; the dozen frames after it stood: %.1f ms"
		% [solver_worst, at_switch])
	if town != null:
		rig.global_position = Vector3(town.global_position.x, rig.global_position.y,
			town.global_position.z)
		print("    Bigholm stands with %d souls" % town.my_villagers().size())
	await _settle(3.0)
	ledger.forget_worst()


func _measure(secs: float, travel: bool) -> Array:
	var out := []
	var heading := Vector3(1.0, 0.0, 0.35).normalized()
	# NOT THE FIRST FRAMES: the report before this one was written at the head
	# of the frame it ended in, and that is this harness's work, not the game's.
	for i in 5:
		await process_frame
	var last := Time.get_ticks_usec()
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		if travel:
			rig.global_position += heading * TRAVEL_SPEED * minf(ms / 1000.0, 0.1)
		var rows := {}
		var calls := {}
		for row: Array in ledger.rows():
			rows[row[0]] = float(row[1])
			calls[row[0]] = int(row[2])
		ms = ledger.page_ms()
		rows["(unclocked)"] = maxf(ms - _sum(rows), 0.0)
		calls["(unclocked)"] = 1
		rows["(nodes freed)"] = float(maxi(_nodes_then - nodes, 0))
		rows["(# pairs)"] = Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
		rows["(# active bodies)"] = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
		rows["(# nodes)"] = float(nodes)
		_nodes_then = nodes
		out.append([ms, rows, calls])
	return out


func _sum(rows: Dictionary) -> float:
	var all := 0.0
	for r: String in rows:
		all += float(rows[r])
	return all


func _report(title: String, frames: Array) -> void:
	if frames.is_empty():
		return
	var times: Array = frames.map(func(f): return float(f[0]))
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	for t: float in times:
		sum += t
	print("\n%s: %d frames, mean %.1f ms, p95 %.1f ms, worst %.1f ms" % [title, frames.size(),
		sum / times.size(), sorted[int(sorted.size() * 0.95)], sorted[sorted.size() - 1]])
	var turns := 0
	for f: Array in frames:
		turns += int(f[2].get("Villager", 0))
	print("    villager turns a second: %.0f" % (turns / maxf(sum / 1000.0, 0.001)))
	var crowd: Script = load("res://scripts/crowd.gd")
	var clock: Node = root.get_node_or_null("CrowdClock")
	print("    near band: %d counted, stride %d; carried over now: %d" % [crowd.near(), crowd.stride(),
		(clock._late.size() / 2) if clock != null and "_late" in clock else -1])
	var total := {}
	var many := {}
	var worst := {}
	for f: Array in frames:
		for row: String in f[1]:
			total[row] = float(total.get(row, 0.0)) + float(f[1][row])
			many[row] = int(many.get(row, 0)) + int(f[2].get(row, 0))
			worst[row] = maxf(float(worst.get(row, 0.0)), float(f[1][row]))
	var names := total.keys().filter(func(r): return not r.begins_with("(#"))
	names.sort_custom(func(a, b): return total[a] > total[b])
	print("    %-26s %8s %8s %9s %8s" % ["row", "ms/frame", "calls/f", "ms/call", "worst"])
	for row: String in names.slice(0, 22):
		var n := float(frames.size())
		var c := float(many[row])
		print("    %-26s %8.2f %8.1f %9.3f %8.1f" % [row, total[row] / n, c / n,
			total[row] / maxf(c, 1.0), worst[row]])
	# A villager's turn by its parts, when a probe has been put in it by hand
	# (a static `probe` of microseconds by part): absent, nothing is said.
	var vs: Script = load("res://scripts/villager/villager.gd")
	var probe = vs.get("probe")
	if probe is Dictionary and not probe.is_empty():
		var keys: Array = probe.keys().filter(func(k): return not k.begins_with("n "))
		keys.sort_custom(func(a, b): return probe[a] > probe[b])
		for k: String in keys.slice(0, 30):
			print("    VILLAGER %-28s %8.1f ms total %7d calls %7.3f ms/call" % [k, probe[k] / 1000.0,
				probe["n " + k], probe[k] / 1000.0 / maxf(probe["n " + k], 1.0)])
		probe.clear()
	var slow: Array = ledger.slowest_call(true)
	print("    slowest single call: %s" % str(slow))
	var spikes := frames.filter(func(f): return float(f[0]) > SPIKE_MS)
	print("    frames over %.0f ms: %d" % [SPIKE_MS, spikes.size()])
	spikes.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	if OS.get_environment("PROFILE_DUMP") != "":
		for f: Array in spikes.slice(0, 2):
			print("      FULL %.1f ms: %s" % [float(f[0]), str(f[1])])
			print("      CALLS: %s" % str(f[2]))
	for f: Array in spikes.slice(0, 8):
		var parts: Array = f[1].keys().filter(func(r): return not r.begins_with("(#"))
		parts.sort_custom(func(a, b): return f[1][a] > f[1][b])
		var said := ", ".join(parts.slice(0, 7).map(
			func(r): return "%s %.1f" % [r, f[1][r]]))
		print("      %.1f ms: %s  [%d pairs, %d awake]" % [float(f[0]), said,
			int(f[1].get("(# pairs)", 0)), int(f[1].get("(# active bodies)", 0))])
