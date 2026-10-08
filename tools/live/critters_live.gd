extends SceneTree
## ONLY UNDER THE CANOPY — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/critters_live.gd
##
## With the camera high, the wood must be still: nothing processing, no voices,
## no census. Brought down under the trees it must wait while the camera is
## still moving, then wake and fill once it stops; taken back up it must go
## still again with every critter where it was, still drawn.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-62s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func busy(critters: Array) -> int:
	var n := 0
	for c in critters:
		if is_instance_valid(c) and c.is_processing():
			n += 1
	return n


func voices(critters: Array) -> int:
	var n := 0
	for c in critters:
		if is_instance_valid(c) and c.has_voice():
			n += 1
	return n


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var state := root.get_node("/root/GameState")
	state.supporter = true
	state.tree_friends = true
	# Midday, so bees are out over any flowers and squirrels in any wood.
	state.game_years = fposmod(0.5 - 0.35, 1.0) * float(state.DAY_YEARS)
	var wood = root.find_children("*", "TreeFriends", true, false)[0]
	var rig = root.find_children("*", "CameraRig", true, false)[0]
	print("ONLY UNDER THE CANOPY")

	rig.zoom_distance = 60.0
	for i in 120:
		await process_frame
	var high: float = wood.camera_height()
	check(not wood.is_awake() and high > 15.0, "camera %.0fm up: the wood is still" % high)
	check(wood.population() == 0, "and nothing was raised in it (%d)" % wood.population())

	rig.zoom_distance = 4.0
	rig.pitch_node.rotation_degrees.x = -12.0
	# STILL MOVING, down under the trees: a slow push along the ground. The wood
	# must not wake while the camera is on the move — only once it stops.
	var woke_moving := false
	var under := 0
	for i in 150:
		rig.position.x += 0.05
		await process_frame
		if wood.camera_height() < 12.0:
			under += 1
		woke_moving = woke_moving or wood.is_awake()
	check(under > 100 and not woke_moving,
		"down under the trees but still moving: the wood waits (%d frames under)" % under)
	var woke := false
	for i in 300:
		await process_frame
		if wood.is_awake() and wood.population() > 0:
			woke = true
			break
	var low: float = wood.camera_height()
	var critters: Array = root.get_tree().get_nodes_in_group("critters")
	check(woke, "camera %.1fm up: awake, and %d critters about" % [low, wood.population()])
	check(busy(critters) == critters.size() and critters.size() > 0, "every one of them moving")

	rig.zoom_distance = 60.0
	rig.pitch_node.rotation_degrees.x = -50.0
	# The zoom eases out over a moment, and the wood is asked only once the
	# camera has come to rest — so this waits for that, as a player would.
	for i in 900:
		await process_frame
		if not wood.is_awake():
			break
	critters = root.get_tree().get_nodes_in_group("critters")
	var drawn := 0
	for c in critters:
		if is_instance_valid(c) and c.is_inside_tree():
			drawn += 1
	check(not wood.is_awake(), "back up %.0fm: still again" % wood.camera_height())
	check(busy(critters) == 0 and voices(critters) == 0,
		"nothing moving, nothing heard (%d moving, %d voices)" % [busy(critters), voices(critters)])
	check(drawn == critters.size() and drawn > 0, "but still drawn where they were (%d)" % drawn)
	print("\n%s" % ("Success: no problems found" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails else 0)
