extends SceneTree
## A BEAST KILLED IS DEAD — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/kill_live.gd
##
##   1. a herd's beast killed in plain view (a pig; a tiger) leaves its body on
##      the ground, and its herd is one head smaller AT ONCE (Animal.die tells
##      it, Herd.release);
##   2. and it does not stand up again, however long you watch: the herd is
##      still one smaller — it does not raise the dead row as a new body;
##   3. a beast freed any other way is still noticed by its herd: a freed
##      handle is null to `==` in Godot 4, and the herd must not take it for
##      a row that never had a body (Herd._has_body).
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var main: Node = current_scene
	var world: Node = main.world_gen
	var spot := Vector3(60.0, 0.0, 60.0)
	spot.y = world.height_at(spot.x, spot.z)
	main.camera_rig.global_position = spot           # on the ground there, not under it
	print("A BEAST KILLED")
	for kind in ["pig", "tiger"]:
		var herd = await _herd_in_view(world, kind, Vector3(60, 0, 60))
		var agents := _agents_of(herd)
		if agents.is_empty():
			check(false, "a %s herd in plain view has beasts standing for it" % kind)
			continue
		var before: int = herd.alive()
		var victim = agents[0]
		var where: Vector3 = victim.global_position
		victim.take_damage(9999.0)
		check(herd.alive() == before - 1, "a %s killed: its herd is one smaller at once (%d to %d)"
			% [kind, before, herd.alive()])
		for i in 600:
			await process_frame
		# THE SIGN OF THE DEAD WALKING: the herd's count back where it was. Its
		# living mates may well wander past the body; that is not it.
		var bodies := _near(where, "Carcass", "")
		check(bodies >= 1 and herd.alive() <= before - 1,
			"its body lies where it fell, and it does not stand up again (%d bodies; the herd %d of %d)"
			% [bodies, herd.alive(), before])
		herd.queue_free()
		await process_frame
	# 3. Freed some other way: no death, no telling.
	var flock = await _herd_in_view(world, "sheep", Vector3(60, 0, 60))
	var them := _agents_of(flock)
	if them.is_empty():
		check(false, "a sheep herd in plain view has beasts standing for it")
	else:
		var had: int = flock.alive()
		them[0].queue_free()
		for i in 120:
			await process_frame
		check(flock.alive() == had - 1, "a beast freed without dying is still noticed by its herd (%d to %d)"
			% [had, flock.alive()])
	print("KILL LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)


func _herd_in_view(world: Node, kind: String, at: Vector3) -> Node:
	at.y = world.height_at(at.x, at.z)
	var herd = load("res://scripts/animals/herd.gd").create(kind, 5, world)
	world.chunk_at(at.x, at.z).add_child(herd)
	herd.global_position = at
	# Until it has beasts in plain view: the world's allowance of them is shared
	# with every herd near the camera.
	for i in 900:
		await process_frame
		if i > 60 and not _agents_of(herd).is_empty():
			break
	return herd


func _agents_of(herd: Node) -> Array:
	return root.find_children("*", "", true, false).filter(
		func(a): return a.has_meta("herd") and a.get_meta("herd") == herd and not a.is_queued_for_deletion())


func _near(at: Vector3, cls: String, kind: String) -> int:
	var n := 0
	for node in root.find_children("*", "", true, false):
		if node.get_script() == null or String(node.get_script().get_global_name()) != cls:
			continue
		if kind != "" and node.species != kind:
			continue
		if (node as Node3D).global_position.distance_to(at) < 4.0:
			n += 1
	return n
