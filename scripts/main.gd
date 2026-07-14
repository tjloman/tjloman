extends Node3D
## Main orchestrator: builds the world, wires all systems together.
## Everything is constructed procedurally from primitives — this is a
## deliberately ugly proof of concept. Art comes later; systems come first.

const WORLD_SIZE := 400.0

var camera_rig: CameraRig
var divine_hand: DivineHand
var miracles: MiracleManager
var village: Village
var creature: Creature
var hud: HUD


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_terrain()
	_scatter_nature()

	village = Village.new()
	village.position = Vector3.ZERO
	add_child(village)

	creature = Creature.new()
	creature.position = Vector3(10, 0, 10)
	add_child(creature)

	camera_rig = CameraRig.new()
	add_child(camera_rig)

	miracles = MiracleManager.new()
	miracles.village = village
	add_child(miracles)

	divine_hand = DivineHand.new()
	divine_hand.camera_rig = camera_rig
	divine_hand.miracles = miracles
	add_child(divine_hand)

	hud = HUD.new()
	hud.village = village
	hud.divine_hand = divine_hand
	add_child(hud)

	GameState.announce("A new god stirs. The village of Elsmere awaits your influence.")

	if "--smoke-test" in OS.get_cmdline_user_args():
		_run_smoke_test()


## Input actions are registered in code so the whole project stays reviewable
## as plain text (no opaque project.godot input blobs).
func _setup_input() -> void:
	var actions := {
		"cam_forward": [KEY_W, KEY_UP],
		"cam_back": [KEY_S, KEY_DOWN],
		"cam_left": [KEY_A, KEY_LEFT],
		"cam_right": [KEY_D, KEY_RIGHT],
		"cam_rotate_left": [KEY_Q],
		"cam_rotate_right": [KEY_E],
		"toggle_help": [KEY_F1],
	}
	for action: String in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in actions[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.7, 0.78, 0.85)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_terrain() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.add_to_group("ground")

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WORLD_SIZE, 1.0, WORLD_SIZE)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	ground.add_child(shape)

	ground.add_child(Util.box(
		Vector3(WORLD_SIZE, 1.0, WORLD_SIZE),
		Color(0.36, 0.55, 0.3),
		Vector3(0, -0.5, 0)))
	add_child(ground)

	# Random darker grass patches make camera movement readable on a flat plane.
	for i in 40:
		var patch := Util.cylinder(
			randf_range(2.0, 7.0), 0.04,
			Color(0.3, 0.48, 0.26),
			Vector3(randf_range(-150, 150), 0.02, randf_range(-150, 150)))
		add_child(patch)


func _scatter_nature() -> void:
	# Trees: ring around the village, none inside it.
	for i in 30:
		var angle := randf() * TAU
		var dist := randf_range(25.0, 120.0)
		var pos := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		add_child(_make_tree(pos))

	# Rocks: pickable rigid bodies, fun to throw.
	for i in 10:
		var angle := randf() * TAU
		var dist := randf_range(15.0, 80.0)
		var rock := RigidBody3D.new()
		rock.collision_layer = 4
		rock.collision_mask = 1 | 4
		rock.mass = 5.0
		rock.add_to_group("pickable")
		rock.set_meta("hover_name", "Rock")
		var r := randf_range(0.4, 0.8)
		var col := CollisionShape3D.new()
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = r
		col.shape = sphere_shape
		rock.add_child(col)
		rock.add_child(Util.sphere(r, Color(0.5, 0.5, 0.52)))
		rock.position = Vector3(cos(angle) * dist, r + 0.5, sin(angle) * dist)
		add_child(rock)


func _make_tree(pos: Vector3) -> Node3D:
	var tree := Node3D.new()
	tree.position = pos
	var h := randf_range(2.5, 4.5)
	tree.add_child(Util.cylinder(0.25, h, Color(0.42, 0.3, 0.18), Vector3(0, h * 0.5, 0)))
	var leaves := Util.mesh_node(_cone_mesh(1.6, 2.8), Color(0.2, 0.45, 0.2), Vector3(0, h + 1.2, 0))
	tree.add_child(leaves)
	return tree


func _cone_mesh(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = height
	return m


## Headless CI/validation mode: exercises every major system for a few
## seconds, then exits. Run with:
##   godot --headless --path . -- --smoke-test
func _run_smoke_test() -> void:
	print("SMOKE TEST: starting")
	_smoke_test_gestures()
	await get_tree().create_timer(1.0).timeout
	for miracle: String in ["food", "rain", "heal", "lightning"]:
		GameState.add_prayer_power(50.0)
		var ok := miracles.cast(miracle, Vector3(5, 0, 5))
		print("SMOKE TEST: cast %s -> %s" % [miracle, ok])
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(2.0).timeout
	print("SMOKE TEST: villagers=%d creature_state=%s belief=%.1f" % [
		get_tree().get_nodes_in_group("villagers").size(),
		creature.state_name(),
		village.belief,
	])
	print("SMOKE TEST OK")
	get_tree().quit(0)


func _smoke_test_gestures() -> void:
	var circle := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		circle.append(Vector2(400 + cos(a) * 100, 300 + sin(a) * 100))
	var vline := PackedVector2Array([Vector2(400, 100), Vector2(402, 200), Vector2(398, 300), Vector2(400, 400)])
	var hline := PackedVector2Array([Vector2(100, 300), Vector2(200, 302), Vector2(300, 298), Vector2(400, 300)])
	var zigzag := PackedVector2Array([
		Vector2(100, 300), Vector2(150, 200), Vector2(200, 300),
		Vector2(250, 200), Vector2(300, 300), Vector2(350, 200),
	])
	print("SMOKE TEST: gesture circle -> ", GestureRecognizer.classify(circle))
	print("SMOKE TEST: gesture vline  -> ", GestureRecognizer.classify(vline))
	print("SMOKE TEST: gesture hline  -> ", GestureRecognizer.classify(hline))
	print("SMOKE TEST: gesture zigzag -> ", GestureRecognizer.classify(zigzag))
