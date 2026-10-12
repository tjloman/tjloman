extends SceneTree
## PLAYING CATCH — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/catch_live.gd
##
## A thrown rock flew on no layer at all and rolled for minutes: nothing could
## take hold of it, and it went through everyone. Now:
##   1. a rock in flight is under the hand's pick, and the hand catches it —
##      and a rock caught in the air has struck nothing;
##   2. a rock in flight strikes a body standing in its way;
##   3. thrown, it rolls, slows and lies down as scenery within seconds;
##   4. the creature catches a rock thrown to it, and lobs it back to the hand;
##      the same rock thrown again is a new throw to catch.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0
var main: Node
var hand: Node
var world: Node
var rock_script: Script


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await physics_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	main = current_scene
	hand = main.divine_hand
	world = main.world_gen
	rock_script = load("res://scripts/world/rock_deposit.gd")
	print("PLAYING CATCH")
	await seconds(3.0)
	var home: Vector3 = main.village.global_position
	var at := _flat_near(home + Vector3(14.0, 0.0, 10.0))

	# 1. Thrown, and caught in the air.
	var rock := _rock(at + Vector3(0.0, 1.5, 0.0))
	await physics_frame
	hand.force_hold(rock)
	hand._release_body(rock, Vector3(4.0, 7.0, 0.0), false)
	hand.held_body = null
	hand.state = hand.HandState.IDLE
	await seconds(0.25)
	var up: float = rock.global_position.y - world.height_at(rock.global_position.x, rock.global_position.z)
	check(not rock.freeze and up > 1.0, "a thrown rock is in the air (%.1f m up)" % up)
	check(hand._nearly_under(rock.global_position) == rock, "and the hand's pick finds it there")
	hand.ground_point = rock.global_position
	hand.hover_target = rock
	hand._on_grab()
	await physics_frame
	await physics_frame
	check(hand.held_body == rock and rock.freeze, "the hand catches it out of the air")
	var blow: Node = rock.get_node_or_null("blow")
	check(blow == null or blow.is_queued_for_deletion(), "and a rock caught in the air struck nothing")

	# 3. Thrown along the ground: it rolls, slows, and lies down.
	hand._release_body(rock, Vector3(6.0, 2.0, 3.0), false)
	hand.held_body = null
	hand.state = hand.HandState.IDLE
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 20000 and not (is_instance_valid(rock) and rock.freeze):
		await physics_frame
	var took := (Time.get_ticks_msec() - began) / 1000.0
	check(is_instance_valid(rock) and rock.freeze and rock.collision_layer == 1,
		"thrown, it lies down as scenery again (in %.1f s)" % took)
	check(took < 14.0, "within seconds, not minutes")

	# 2. In the way of something standing — a person's layer.
	var post := StaticBody3D.new()
	post.collision_layer = 2
	post.collision_mask = 0
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	(box.shape as BoxShape3D).size = Vector3(0.6, 4.0, 3.0)
	post.add_child(box)
	world.add_child(post)
	var wall_at := _flat_near(home + Vector3(-16.0, 0.0, 12.0))
	post.global_position = wall_at + Vector3(0.0, 2.0, 0.0)
	var shot := _rock(wall_at + Vector3(-4.0, 1.2, 0.0))
	await physics_frame
	hand.force_hold(shot)
	shot.global_position = wall_at + Vector3(-4.0, 1.2, 0.0)
	hand._release_body(shot, Vector3(12.0, 0.5, 0.0), false)
	hand.held_body = null
	hand.state = hand.HandState.IDLE
	await seconds(1.0)
	check(is_instance_valid(shot) and shot.global_position.x < wall_at.x,
		"a rock in flight strikes a body in its way (%.1f m short of it)"
		% (wall_at.x - shot.global_position.x if is_instance_valid(shot) else 0.0))
	post.queue_free()

	# 4. The creature catches, and throws it back.
	var beast: Node = main.creature
	beast.attention = 100.0
	beast.catch_skill = 10.0
	beast.growth = maxf(beast.growth, 0.5)     # a fresh whelp cannot lift a pebble
	var caught := false
	var back := false
	# Something its arms can manage, young as it is.
	if is_instance_valid(rock):
		rock.queue_free()
	rock = _rock(hand.global_position + Vector3(0.0, 1.0, 0.0), 0)
	await physics_frame
	# The hand held still, on the ground beside it, where a player's would be —
	# in the open, where nothing stands between them to strike.
	hand.set_physics_process(false)
	# Off the tutorial's rope, or it is hauled back to its stake every frame.
	load("res://scripts/world/creature_stake.gd").pull_up(self)
	await physics_frame
	var field := _open_near(main.village.global_position + Vector3(40.0, 0.0, -40.0))
	for go in 3:
		if not is_instance_valid(rock):
			break
		beast.global_position = field
		hand.global_position = field + Vector3(-8.0, 2.0, 0.0)
		beast._carried = null
		beast.state = beast.State.IDLE
		await physics_frame
		hand.force_hold(rock)
		rock.global_position = beast.global_position + Vector3(-1.0, 1.6, 0.0)
		hand._release_body(rock, Vector3(1.0, 1.0, 0.0), false)
		hand.held_body = null
		hand.state = hand.HandState.IDLE
		hand.last_thrown = rock
		hand.throws += 1
		for f in 30:
			await physics_frame
			if beast._carried == rock:
				break
		if beast._carried != rock:
			print("    missed: state %s, %.1f m off, attention %.0f, lifts %s, checked %d of %d, asleep %s" % [
				beast.State.keys()[beast.state], beast.global_position.distance_to(rock.global_position),
				beast.attention, beast.can_lift(rock), beast._catch_checked, hand.throws,
				beast.state == beast.State.SLEEPING])
			continue
		caught = true
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 4000 and beast._carried == rock:
			await physics_frame
		var aimed: Vector3 = hand.global_position
		var from: Vector3 = rock.global_position if is_instance_valid(rock) else Vector3.ZERO
		var toward: Vector3 = ((aimed - beast.global_position) * Vector3(1, 0, 1)).normalized()
		await seconds(1.5)
		var went: float = (rock.global_position - from).dot(toward) if is_instance_valid(rock) else 0.0
		back = went > 2.0
		print("    caught on throw %d; it went %.1f m back toward the hand" % [go + 1, went])
		break
	check(caught, "the creature catches a rock thrown to it")
	check(back, "and lobs it back toward the hand")
	if caught:
		while is_instance_valid(rock) and not rock.freeze:
			await physics_frame
		var before: int = hand.throws
		beast.global_position = field
		beast.state = beast.State.IDLE
		await physics_frame
		hand.force_hold(rock)
		rock.global_position = beast.global_position + Vector3(-1.0, 1.6, 0.0)
		hand._release_body(rock, Vector3(1.0, 1.0, 0.0), false)
		hand.held_body = null
		hand.state = hand.HandState.IDLE
		hand.last_thrown = rock
		hand.throws = before + 1
		beast._carried = null
		var again := false
		for f in 30:
			await physics_frame
			if beast._carried == rock:
				again = true
				break
		check(again or beast._catch_checked == hand.throws,
			"the same rock thrown again is a new throw to catch")
	_done()


func _rock(at: Vector3, rung := 3) -> Node3D:
	var rock: Node3D = rock_script.new()
	rock.rung = rung
	world.add_child(rock)
	rock.global_position = at
	return rock


## Gentle dry ground near `at`, at its height.
func _flat_near(at: Vector3) -> Vector3:
	for i in 400:
		var p := at + Vector3((i % 20) * 2.0, 0.0, (i / 20) * 2.0)
		if world.slope_at(p.x, p.z) < 0.25 and not world.is_underwater(p.x, p.z):
			return Vector3(p.x, world.height_at(p.x, p.z), p.z)
	return Vector3(at.x, world.height_at(at.x, at.z), at.z)


## Flat dry ground with nothing standing within twelve metres of it.
func _open_near(at: Vector3) -> Vector3:
	for i in 900:
		var p := at + Vector3((i % 30) * 3.0, 0.0, (i / 30) * 3.0)
		if world.slope_at(p.x, p.z) > 0.25 or world.is_underwater(p.x, p.z) \
				or world.is_underwater(p.x - 8.0, p.z):
			continue
		var clear := true
		for group in ["houses", "trees", "rock_deposits", "villagers", "forage", "burnable"]:
			for n in get_nodes_in_group(group):
				if is_instance_valid(n) and Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length() < 12.0:
					clear = false
					break
			if not clear:
				break
		if clear:
			return Vector3(p.x, world.height_at(p.x, p.z), p.z)
	return _flat_near(at)


func _done() -> void:
	print("CATCH LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
