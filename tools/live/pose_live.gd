extends SceneTree
## ONE POSE AT A TIME — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/pose_live.gd
##
## One villager is walked through the ways a body has gone wrong before: put to
## bed and taken out by a bare change of state; seated in school and moved on
## with the seat still asked for; laid out dying and pulled back; lifted and
## thrown and landed. Each time the pose byte, the body's pitch, the figure's
## drop and its rotation must all say the same thing. Exits non-zero on failure.
## Names no class of the game's (see tools/look/look.gd).

var fails := 0
var who = null
var S: Dictionary = {}


func check(ok: bool, what: String) -> void:
	print("  %-62s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


## Wait until the pose byte is `code` (or up to 90 frames), then report.
func settle(code: int) -> bool:
	for i in 90:
		await physics_frame
		if who.pose_code == code:
			return true
	return false


func pitch() -> float:
	return who._body_mesh.rotation_degrees.x


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	await process_frame
	var eye: Vector3 = root.get_node("/root/GameState").camera_focus
	for v in root.get_tree().get_nodes_in_group("villagers"):
		if who == null or v.global_position.distance_to(eye) < who.global_position.distance_to(eye):
			who = v
	S = who.State
	print("ONE POSE AT A TIME — %s" % who.villager_name)
	who.energy = 5.0
	who.hunger = 0.0
	who.state = S["SLEEPING"]
	check(await settle(0x20) and absf(pitch() - 80.0) < 0.5, "asleep: 0x20, lying (%.0f deg)" % pitch())
	who.state = S["WANDER"]          # out of bed by nothing that stands them up
	check(await settle(0x00) or who.pose_code == 0x01, "out of bed by a bare change of state: on their feet (0x%02X)" % who.pose_code)
	check(is_zero_approx(pitch()) and is_zero_approx(who._visuals.position.y),
		"body upright, figure at rest")

	who.state = S["AT_SCHOOL"]
	who.sit_down(true)
	check(await settle(0x10) and who._visuals.position.y < -0.3, "seated in school: 0x10, on the dirt")
	who.state = S["WANDER"]          # moved on, the seat still asked for
	await settle(0x00)
	check(who.pose_code >> 4 == 0 and is_zero_approx(who._visuals.position.y),
		"out of school with the seat still asked for: standing (0x%02X)" % who.pose_code)
	who.sit_down(false)

	who.state = S["DYING"]
	who._dying_time = 30.0
	check(await settle(0x32) and who._visuals.rotation_degrees.x > 80.0, "dying: 0x32, prone")
	who.state = S["WANDER"]
	await settle(0x00)
	check(who.pose_code >> 4 == 0 and absf(who._visuals.rotation_degrees.x) < 0.5,
		"pulled back: the figure stands again")

	who.pick_up()
	check(await settle(0x40), "in the hand: 0x40")
	who.state = S["FALLING"]
	who.set_flight_spin(Vector3(6.0, 0.0, 0.0))
	who.velocity = Vector3(0, 6, 0)
	await settle(0x30)
	for i in 8:
		await physics_frame
	var tumbled: bool = absf(who._visuals.rotation.x) > 0.05
	check(who.pose_code == 0x30 and tumbled, "thrown: 0x30, and the throw turns the figure")
	who.set_flight_spin(Vector3.ZERO)
	who.state = S["WANDER"]          # down, however it came down
	await settle(0x00)
	check(who.pose_code >> 4 == 0 and who._visuals.rotation.length() < 0.01,
		"landed: upright, not left at the angle it tumbled to")
	print("\n%s" % ("Success: no problems found" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails else 0)
