extends SceneTree
## UP AFTER SLEEP, AND DOWN WHEN SPENT — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/rest_live.gd
##
## A villager put to bed and then taken out of it by a way that never stood it
## up must be standing again within a few ticks; a creature at zero energy on
## the lead must drop where it stands; a call on the lead while it sleeps must
## be kept, not obeyed; and it must take the lead up again once it wakes.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-62s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	await process_frame
	print("UP AFTER SLEEP")
	# THE NEAREST TO THE CAMERA: a far villager runs on a slower clock (see
	# Util.sim_stride) and may not think for many frames.
	var eye: Vector3 = root.get_node("/root/GameState").camera_focus
	var who = null
	for v in root.get_tree().get_nodes_in_group("villagers"):
		if who == null or v.global_position.distance_to(eye) < who.global_position.distance_to(eye):
			who = v
	var states: Dictionary = who.State
	who.state = states["SLEEPING"]
	who._pitch_body(80.0)
	await process_frame
	# Out of bed by a way that does not stand them up: just a new state.
	who.state = states["WANDER"]
	for i in 90:
		await physics_frame
		if is_zero_approx(who._body_mesh.rotation_degrees.x):
			break
	check(is_zero_approx(who._body_mesh.rotation_degrees.x),
		"a villager out of bed stands up (%.0f deg)" % who._body_mesh.rotation_degrees.x)
	# Tired and fed, so they do not wake of their own accord mid-check: a day
	# nap ends once a villager is rested, which is right, and not this check.
	who.energy = 5.0
	who.hunger = 0.0
	who.state = states["SLEEPING"]
	who._pitch_body(80.0)
	for i in 12:
		await physics_frame
	check(who._body_mesh.rotation_degrees.x > 70.0, "and one asleep stays lying down")

	print("DOWN WHEN SPENT")
	var beast = root.get_tree().get_first_node_in_group("creature")
	var cs: Dictionary = beast.State
	var spot: Vector3 = beast.global_position + Vector3(6, 0, 0)
	beast.leash_target = spot
	beast.state = cs["LEASHED"]
	beast.energy = 0.0
	for i in 6:
		await physics_frame
	check(beast.state == cs["SLEEPING"], "at zero energy on the lead, it drops and sleeps")
	var lead = load("res://scripts/creature/creature_lead.gd")
	beast.energy = 10.0
	lead.to_spot(beast, spot + Vector3(2, 0, 0))
	for i in 6:
		await physics_frame
	check(beast.state == cs["SLEEPING"], "a tug on the lead does not wake a tired beast")
	check(beast.leash_target != Vector3.INF, "but the order is kept")
	beast.energy = 99.0
	for i in 30:
		await physics_frame
		if beast.state == cs["LEASHED"]:
			break
	check(beast.state == cs["LEASHED"], "rested, it wakes and takes the lead up again")
	beast.energy = 8.0
	beast._decide()
	check(beast.state == cs["SLEEPING"], "and a tired one called on the lead rests first")
	print("\n%s" % ("Success: no problems found" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails else 0)
