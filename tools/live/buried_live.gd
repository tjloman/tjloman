extends SceneTree
## NOTHING ENDS UP UNDER THE LAND — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/buried_live.gd
##
## A bison carcass, four ways into the ground and back out:
##   1. CARRIED: the hand points at a spot inside a hill (a far hill with no
##      collision rests the hand on the sea-level plane) — the held body rides
##      over the land instead;
##   2. RELEASED inside the hill — it is let go of on top of it;
##   2b. RELEASED half inside a house, which pushed it out downwards, through
##      the ground — it is let go of on top instead (a plain crate, so the
##      carcass's own catch is not what saves it);
##   3. THROWN at the ground at the hand's full speed, which took a carcass clean
##      through for 3 of these 15 throws (thrown here as plain crates, so the
##      catch in flight is tested apart from the carcass's) — and a carcass
##      already falling under the world, which never slept, so never fell apart.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0
var world: Node
var carcass: Script


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func bison(at: Vector3) -> RigidBody3D:
	var b: RigidBody3D = carcass.new()
	b.species = "bison"
	b.body = Vector3(1.0, 1.1, 2.1)
	current_scene.add_child(b)
	b.global_position = at
	return b


## A bison's size and weight with nothing of a carcass about it — a rock or a
## bundle, as far as a throw is concerned — so the catch in flight is tested on
## its own and not the carcass's own.
func crate(at: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 1 | 4
	b.mass = 9.5
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.1, 2.1)
	col.shape = box
	b.add_child(col)
	current_scene.add_child(b)
	b.global_position = at
	return b


func ground(b: Node3D) -> float:
	return world.height_at(b.global_position.x, b.global_position.z)


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	world = current_scene.world_gen
	carcass = load("res://scripts/world/carcass.gd")
	var hand: Node = current_scene.divine_hand
	var here: Vector3 = current_scene.camera_rig.global_position
	print("NOTHING ENDS UP UNDER THE LAND")
	# THE GROUND HAS TO BE CUT FIRST. A town flattens its square as it opens,
	# and until the chunk under it is cut again the solid ground there is the
	# old ground — a body set on the new land falls to the old. That is the
	# world loading, not anything under test, so wait it out.
	for t in 40:
		if solid_matches(here):
			break
		await create_timer(0.25).timeout

	# 1 and 2: in the hand, somewhere with nothing built on it.
	var spot := clear_spot(here)
	var held := bison(spot + Vector3.UP * 2.0)
	hand.force_hold(held)
	hand.ground_point = Vector3(spot.x, spot.y - 4.0, spot.z)
	for i in 20:
		hand._carry_held(0.05)
	check(held.global_position.y >= ground(held) + 0.2,
		"carried toward a point 4m inside the land, it rides over it (%.1fm up)"
		% (held.global_position.y - ground(held)))
	held.global_position = Vector3(spot.x, spot.y - 3.0, spot.z)
	let_go(hand, held)
	check(held.global_position.y >= ground(held) - 0.2,
		"let go of 3m inside the land, it is let go of on top of it")
	await create_timer(2.0).timeout
	check(held.global_position.y >= ground(held) - 1.0,
		"and it is still there two seconds later")

	# 2b: let go of half inside a house.
	var house := a_building()
	check(house != null, "there is a building to try it on")
	if house != null:
		# A crate, not a carcass: a carcass that falls through is caught by
		# its own check, and this is the release's check being tested.
		var into := crate(house.global_position + Vector3.UP * 0.6)
		hand.force_hold(into)
		into.global_position = house.global_position + Vector3.UP * 0.6
		let_go(hand, into)
		await create_timer(2.0).timeout
		check(into.global_position.y >= ground(into) - 0.5,
			"let go of inside a house, it is not pushed out under the land (%.1fm)"
			% (into.global_position.y - ground(into)))

	# 3: thrown hard, as the hand throws.
	var blow: Script = load("res://scripts/world/blow.gd")
	var thrown := []
	var i := 0
	for speed: float in [10.0, 20.0, 30.0, 38.0, 50.0]:
		for pitch: float in [-20.0, -45.0, -80.0]:
			var at := here + Vector3(i * 6.0 - 40.0, 0.0, 10.0)
			var b := crate(Vector3(at.x, ground_at(at) + 6.0, at.z))
			b.linear_velocity = Vector3(cos(deg_to_rad(pitch)), sin(deg_to_rad(pitch)), 0.0) * speed
			blow.ride(b, true)
			thrown.append(b)
			i += 1
	var lost := bison(Vector3(here.x - 60.0, ground_at(here) - 25.0, here.z))
	lost.linear_velocity = Vector3(0.0, -11.0, 0.0)
	await create_timer(4.0).timeout
	var under := 0
	for b: RigidBody3D in thrown:
		if is_instance_valid(b) and b.global_position.y < ground(b) - 1.0:
			under += 1
	check(under == 0, "thrown at the ground at up to 50 m/s, none end up under it (%d)" % under)
	check(lost.global_position.y >= ground(lost) - 1.0,
		"a body already falling under the world is brought back up (%.0fm)"
		% (lost.global_position.y - ground(lost)))
	print("BURIED LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)


func let_go(hand: Node, body: RigidBody3D) -> void:
	hand._release_body(body, Vector3.ZERO, true)
	hand.held_body = null
	hand.state = hand.HandState.IDLE


## Somewhere near with nothing built on it, as land, so the release is tested
## against the ground alone.
func clear_spot(here: Vector3) -> Vector3:
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 3.0, 3.0)
	for ring in range(1, 12):
		for k in 8:
			var a := k * TAU / 8.0
			var at := here + Vector3(cos(a), 0.0, sin(a)) * ring * 6.0
			at.y = ground_at(at)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.6)
			q.collision_mask = 4 | 8
			if current_scene.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty() \
					and not world.is_underwater(at.x, at.z) and solid_matches(at):
				return at
	return here


## One of a town's own buildings: a static box on the props layer.
func a_building() -> Node3D:
	for town in get_nodes_in_group("village"):
		for body in town.find_children("*", "StaticBody3D", true, false):
			if body.collision_layer & 4 and body.find_children("*", "CollisionShape3D", false, false) \
					.any(func(c): return c.shape is BoxShape3D and c.shape.size.y >= 2.0):
				return body
	return null


## Does the solid ground here stand where the land says it does?
func solid_matches(at: Vector3) -> bool:
	var top := Vector3(at.x, ground_at(at) + 30.0, at.z)
	var ray := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 60.0, 1)
	var hit: Dictionary = current_scene.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and absf(float(hit["position"].y) - ground_at(at)) < 0.5


func ground_at(at: Vector3) -> float:
	return world.height_at(at.x, at.z)
