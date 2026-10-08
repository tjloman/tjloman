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
	await _the_creature()
	await _a_beast()
	print("\n%s" % ("Success: no problems found" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails else 0)


## THE CREATURE: down onto its side for sleep and up again by a bare change of
## state; a dance's pulse gone the moment the dance is.
func _the_creature() -> void:
	var beast = root.get_tree().get_first_node_in_group("creature")
	var cs: Dictionary = beast.State
	print("THE CREATURE")
	beast.leash_target = Vector3.INF
	beast.energy = 10.0
	beast._target = Vector3.INF
	beast.state = cs["SLEEPING"]
	for i in 90:
		await physics_frame
	check(beast.pose_code == 0x20 and absf(beast._body.rotation_degrees.z - 80.0) < 1.0,
		"asleep: 0x20, rolled onto its side (%.0f deg)" % beast._body.rotation_degrees.z)
	beast.state = cs["IDLE"]          # woken by nothing that stood it up
	beast._action_time = 30.0
	for i in 120:
		await physics_frame
	check(beast.pose_code == 0x00 and beast._body.rotation_degrees.length() < 0.01 \
		and beast._body.position.length() < 0.001,
		"up by a bare change of state: 0x00, upright and over its feet")
	beast.state = cs["DANCE"]
	beast._action_time = 30.0
	var pulsed := false
	for i in 40:
		await physics_frame
		pulsed = pulsed or absf(beast._body.scale.y - 1.0) > 0.03
	check(beast.pose_code == 0x06 and pulsed, "dancing: 0x06, and it pulses")
	beast.state = cs["IDLE"]          # the dance cut short
	beast._action_time = 30.0
	for i in 90:
		await physics_frame
	check(is_equal_approx(beast._body.scale.y, 1.0), "the dance cut short: not left squashed (%.3f)"
		% beast._body.scale.y)


## A BEAST: thrown, only its looks tumble — the body that faces and collides is
## never tipped — and caught or landed, the looks stand up, still facing its way.
func _a_beast() -> void:
	var eye: Vector3 = root.get_node("/root/GameState").camera_focus
	var animal = null
	for a in root.get_tree().get_nodes_in_group("animals"):
		if a._figure != null and (animal == null \
				or a.global_position.distance_to(eye) < animal.global_position.distance_to(eye)):
			animal = a
	print("A BEAST — %s" % (animal.species if animal != null else "none near"))
	if animal == null:
		check(false, "a beast to test")
		return
	var st: Dictionary = animal.State
	animal.rotation.y = 1.2
	animal.state = st["FALLING"]
	animal.velocity = Vector3(0, 8, 0)
	animal.set_flight_spin(Vector3(5.0, 0.0, 3.0))
	for i in 10:
		await physics_frame
	check(animal.pose_code == 0x30 and animal._figure.rotation.length() > 0.1,
		"thrown: 0x30, and the tumble turns its looks")
	check(absf(animal.rotation.x) < 0.001 and absf(animal.rotation.z) < 0.001,
		"while the body that collides stays upright")
	animal.set_flight_spin(Vector3.ZERO)
	animal.state = st["HELD"]          # caught mid-tumble
	for i in 4:
		await physics_frame
	check(animal.pose_code == 0x40 and animal._figure.rotation.length() < 0.001,
		"caught mid-air: 0x40, its looks stood up")
	check(absf(animal.rotation.y - 1.2) < 0.001, "and still facing the way it faced")
	animal.state = st["GRAZE"]
	animal._action_time = 30.0
	for i in 30:
		await physics_frame
		if animal.pose_code == 0x03:
			break
	check(animal.pose_code == 0x03 and animal._figure.rotation_degrees.x > 10.0,
		"grazing: 0x03, head down")

