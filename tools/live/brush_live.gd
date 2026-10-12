extends SceneTree
## THE BRUSH BURNS — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/brush_live.gd
##
## A forage bush was the one dry thing on a hillside nothing could light. Now:
##   1. a fireball landing on one lights it;
##   2. so does a bolt of lightning, and lava poured on it;
##   3. so does a burning tree beside it;
##   4. a burning bush lights the brush touching it, and is ash a few seconds on;
##   5. rain puts one out, and it stands, bare.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0
var main: Node
var used := []


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	main = current_scene
	print("THE BRUSH BURNS")
	await seconds(3.0)
	var world: Node = main.world_gen
	var manager: Node = main.miracles

	# 1. A fireball, landing on one.
	var a := _bush()
	check(a != null, "a forage bush stands in loaded land")
	if a == null:
		_done()
		return
	var ball: Node3D = load("res://scripts/miracles/fireball.gd").new()
	world.add_child(ball)
	ball.global_position = a.global_position + Vector3(0.0, 0.4, 0.0)
	ball.burst()
	await process_frame
	check(a.burning, "a fireball landing on a bush sets it alight")

	# 2. A bolt, and lava.
	var b := _bush()
	if b != null:
		manager._cast_lightning(b.global_position)
		await process_frame
		check(b.burning, "a bolt of lightning on a bush sets it alight")
	var c := _bush()
	if c != null:
		manager.pour_lava_at(c.global_position, 0.05, 2.0)
		await process_frame
		check(c.burning, "lava poured on a bush sets it alight")

	# 3. A burning tree beside one.
	var d := _bush()
	var tree: Node3D = null
	for t in get_nodes_in_group("trees"):
		if is_instance_valid(t) and not t.burning and t.global_position.distance_to(d.global_position) > 20.0:
			tree = t
			break
	if d != null and tree != null:
		d.global_position = tree.global_position + Vector3(1.5, 0.0, 0.0)
		tree.ignite()
		await seconds(3.0)
		check(d.burning, "a burning tree sets the bush beside it alight")

	# 4. Bush to bush, and then ash.
	var e := _bush()
	var f := _bush()
	if e != null and f != null:
		f.global_position = e.global_position + Vector3(1.2, 0.0, 0.0)
		e.ignite()
		check(e.burning and not e.has_berries(), "a burning bush has no berries to give")
		await seconds(e.BURNS_FOR * 0.7)
		check(f.burning, "a burning bush lights the brush touching it")
		await seconds(e.BURNS_FOR * 0.7)
		check(not is_instance_valid(e), "and a burnt bush is gone")

	# 5. Rain.
	var g := _bush()
	if g != null:
		g.ignite()
		manager._douse_the_built(g.global_position, 3.0)
		await seconds(g.BURNS_FOR * 1.3)
		check(is_instance_valid(g) and not g.burning, "rain puts a burning bush out, and it stands")
	_done()


## A bush not yet used here, on dry land near home.
func _bush() -> Node3D:
	var world: Node = main.world_gen
	for n in get_nodes_in_group("forage"):
		var bush := n as Node3D
		if not is_instance_valid(bush) or used.has(bush) or bush.burning \
				or world.is_underwater(bush.global_position.x, bush.global_position.z):
			continue
		# Far from every other one used, so no fire reaches the next check's.
		var apart := true
		for u in used:
			if is_instance_valid(u) and u.global_position.distance_to(bush.global_position) < 25.0:
				apart = false
		if apart:
			used.append(bush)
			return bush
	return null


func _done() -> void:
	print("BRUSH LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
