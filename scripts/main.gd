extends Node3D
## Main orchestrator: boots the endless world, runs the day/night cycle,
## and wires all systems together. Terrain, villages, and wildlife are the
## WorldGen's job now — this file owns the sky, the clock, and the player.

var camera_rig: CameraRig
var divine_hand: DivineHand
var miracles: MiracleManager
var world_gen: WorldGen
var village: Village          # the player's home village
var creature: Creature
var hud: HUD

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _environment: Environment


func _ready() -> void:
	_setup_input()
	_build_environment()

	world_gen = WorldGen.new()
	add_child(world_gen)

	# The player's home village sits at the origin, in the flattened cradle.
	village = Village.new()
	village.is_player_home = true
	village.village_name = "Elsmere"
	village.position = Vector3(0, world_gen.height_at(0, 0), 0)
	add_child(village)
	world_gen.player_village = village

	creature = Creature.new()
	creature.position = Vector3(10, world_gen.height_at(10, 10) + 0.5, 10)
	add_child(creature)

	camera_rig = CameraRig.new()
	add_child(camera_rig)
	world_gen.focus_node = camera_rig

	miracles = MiracleManager.new()
	add_child(miracles)

	divine_hand = DivineHand.new()
	divine_hand.camera_rig = camera_rig
	divine_hand.miracles = miracles
	add_child(divine_hand)
	miracles.divine_hand = divine_hand  # fireballs are conjured into the grip
	creature.divine_hand = divine_hand  # it watches your hand — and catches

	camera_rig.divine_hand = divine_hand  # two-finger camera preempts the hand

	hud = HUD.new()
	hud.village = village
	hud.divine_hand = divine_hand
	add_child(hud)

	var touch := TouchControls.new()
	touch.divine_hand = divine_hand
	touch.camera_rig = camera_rig
	touch.creature = creature
	add_child(touch)

	GameState.announce("A new god stirs over an endless world. Elsmere awaits your influence.")

	if "--smoke-test" in OS.get_cmdline_user_args():
		_run_smoke_test()


func _process(_delta: float) -> void:
	_update_daylight()


## The day/night cycle: one full cycle per 16 villager years. The sun wheels
## overhead, hands off to a pale moon, and house windows light up at dusk.
func _update_daylight() -> void:
	var df := GameState.day_fraction()
	var elev := GameState.sun_elevation()   # -1 midnight .. +1 noon

	_sun.rotation_degrees = Vector3(-(df * 360.0 - 90.0), 20.0, 0)
	_sun.light_energy = maxf(elev, 0.0) * 1.2 + 0.02
	_sun.light_color = Color(1.0, 0.75 + 0.25 * clampf(elev, 0, 1), 0.6 + 0.4 * clampf(elev, 0, 1))

	_moon.rotation_degrees = Vector3(-(df * 360.0 + 90.0), -30.0, 0)
	_moon.light_energy = maxf(-elev, 0.0) * 0.22

	var day_top := Color(0.32, 0.52, 0.82)
	var day_horizon := Color(0.7, 0.78, 0.85)
	var night_top := Color(0.03, 0.04, 0.1)
	var night_horizon := Color(0.08, 0.09, 0.16)
	var dusk_horizon := Color(0.9, 0.5, 0.3)
	var t := clampf((elev + 0.3) / 0.9, 0.0, 1.0)
	var top := night_top.lerp(day_top, t)
	var horizon := night_horizon.lerp(day_horizon, t)
	# A band of fire at dawn and dusk.
	var duskiness := clampf(1.0 - absf(elev) * 3.5, 0.0, 1.0)
	horizon = horizon.lerp(dusk_horizon, duskiness * 0.7)

	# The heavens are the god's conscience: a saintly hand gilds the sky
	# warm and golden; a monstrous one bruises it ash and blood.
	var a := GameState.alignment / 100.0
	if a > 0.0:
		horizon = horizon.lerp(Color(1.0, 0.88, 0.55), a * 0.22)
		top = top.lerp(Color(0.55, 0.62, 0.75), a * 0.12)
	elif a < 0.0:
		horizon = horizon.lerp(Color(0.5, 0.18, 0.13), -a * 0.35)
		top = top.lerp(Color(0.22, 0.09, 0.1), -a * 0.28)

	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_horizon_color = horizon
	_environment.ambient_light_energy = lerpf(0.25, 1.0, t)
	_environment.fog_light_color = horizon.darkened(0.2)


func _setup_input() -> void:
	var actions := {
		"cam_forward": [KEY_W, KEY_UP],
		"cam_back": [KEY_S, KEY_DOWN],
		"cam_left": [KEY_A, KEY_LEFT],
		"cam_right": [KEY_D, KEY_RIGHT],
		"cam_rotate_left": [KEY_Q],
		"cam_rotate_right": [KEY_E],
		"toggle_help": [KEY_F1],
		"diet_vegan": [KEY_1],
		"diet_omnivore": [KEY_2],
		"diet_carnivore": [KEY_3],
		"diet_cannibal": [KEY_4],
		"pet_creature": [KEY_P],
		"scold_creature": [KEY_L],
		"find_creature": [KEY_C],
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
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	# Tighter shadow range = crisper shadows and cheaper on weak GPUs.
	_sun.directional_shadow_max_distance = 140.0
	_sun.light_specular = 0.25  # matte, plain — no plastic glints
	add_child(_sun)

	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.7, 0.78, 1.0)
	_moon.shadow_enabled = false  # a second shadowed sun is a phone-killer
	_moon.light_specular = 0.1
	add_child(_moon)

	_sky_material = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_material

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_sky_contribution = 0.7
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Good and plain: distance fog and gentle bloom, nothing the mobile
	# renderer can't do. (SSAO is Forward+-only — deliberately absent.)
	_environment.fog_enabled = true
	_environment.fog_density = 0.004
	_environment.fog_sky_affect = 0.2
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.5
	_environment.glow_bloom = 0.1

	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)


## Diet policy hotkeys (1-4) apply to the player's home village.
## P/L pet or scold the creature (the hand must be near it); C finds it.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("diet_vegan"):
		village.set_diet(Village.Diet.VEGAN)
	elif event.is_action_pressed("diet_omnivore"):
		village.set_diet(Village.Diet.OMNIVORE)
	elif event.is_action_pressed("diet_carnivore"):
		village.set_diet(Village.Diet.CARNIVORE)
	elif event.is_action_pressed("diet_cannibal"):
		village.set_diet(Village.Diet.CANNIBAL)
	elif event.is_action_pressed("pet_creature"):
		_touch_creature(true)
	elif event.is_action_pressed("scold_creature"):
		_touch_creature(false)
	elif event.is_action_pressed("find_creature") and is_instance_valid(creature):
		# C toggles a LOCK-ON: the camera glides to the creature, keeps it
		# centered, and orbits around it until you pan away (or press C again).
		if camera_rig.follow_target == creature:
			camera_rig.follow_target = null
		else:
			camera_rig.follow_target = creature
			camera_rig.zoom_distance = clampf(camera_rig.zoom_distance, 6.0, 16.0)


## Training only counts when the hand is actually AT the creature — you
## cannot pet from across the map.
func _touch_creature(kindly: bool) -> void:
	if not is_instance_valid(creature):
		return
	var near: bool = divine_hand.hover_target == creature \
		or divine_hand.global_position.distance_to(creature.global_position) < 8.0
	if not near:
		GameState.announce("Your hand is too far away to reach your creature. (C finds it.)")
		return
	if kindly:
		creature.praise()
	else:
		creature.scold()


## Headless CI/validation: exercises every major system, then exits.
##   godot --headless --path . -- --smoke-test
func _run_smoke_test() -> void:
	print("SMOKE TEST: starting")
	_smoke_test_gestures()
	await get_tree().create_timer(1.5).timeout
	print("SMOKE TEST: chunks=%d biome(0,0)=%s height(0,0)=%.2f water(200,200)=%s" % [
		world_gen.get_child_count(),
		world_gen.biome_at(0, 0),
		world_gen.height_at(0, 0),
		world_gen.is_underwater(200, 200),
	])
	# Two-step casting: open each menu, conjure a selection, and resolve it.
	GameState.set_max_prayer_power(400.0)
	for entry: Array in [["spiral", "circle"], ["rev_spiral", "vline"],
			["wave", "hline"], ["rev_spiral", "circle"], ["spiral", "vline"],
			["wave", "circle"], ["rev_spiral", "hline"]]:
		GameState.add_prayer_power(200.0)
		var opened := miracles.is_menu_opener(entry[0])
		var conjured := miracles.select(entry[0], entry[1])
		print("SMOKE TEST: menu %s + %s -> opener=%s conjured=%s" % [
			entry[0], entry[1], opened, conjured])
		await get_tree().create_timer(0.2).timeout
	# Directly resolve one of each new miracle to exercise every effect.
	for name: String in ["food", "rain", "heal", "lightning", "forest_seed",
			"forage_thicket", "lightning_storm", "tornado", "bird_flock"]:
		miracles.resolve(name, Vector3(6, 0, 6))
		print("SMOKE TEST: resolve %s" % name)
		await get_tree().create_timer(0.3).timeout

	for diet: Village.Diet in [Village.Diet.VEGAN, Village.Diet.CARNIVORE,
			Village.Diet.CANNIBAL, Village.Diet.OMNIVORE]:
		village.set_diet(diet)
	print("SMOKE TEST: alignment=%.1f (%s)" % [GameState.alignment, GameState.alignment_word()])

	var victim := get_tree().get_first_node_in_group("villagers") as Villager
	victim.take_damage(999.0, true)
	await get_tree().create_timer(1.0).timeout
	print("SMOKE TEST: corpses=%d after a divine execution" %
		get_tree().get_nodes_in_group("corpses").size())

	# Force a build cycle to exercise construction.
	village.store.add_lumber(20)
	village.store.add_stone(10)
	var site := village.start_construction(world_gen)
	print("SMOKE TEST: construction site=%s homeless=%d capacity=%d" % [
		site != null, village.homeless_count(), village.housing_capacity()])

	# Exercise creature training: praise and scold must move bond/mood/desires.
	creature._last_deed = "play"
	var desire_before: float = creature.desires["play"]
	creature.praise()
	creature.scold()
	print("SMOKE TEST: creature trained — bond=%.0f mood=%.0f (%s) play desire %.2f->%.2f, loves %s" % [
		creature.bond, creature.mood, creature.mood_word(),
		desire_before, creature.desires["play"], creature.favorite_deed()])

	await get_tree().create_timer(2.0).timeout
	print("SMOKE TEST: villagers=%d animals=%d houses=%d villages=%d creature=%s day=%.2f night=%s" % [
		get_tree().get_nodes_in_group("villagers").size(),
		get_tree().get_nodes_in_group("animals").size(),
		get_tree().get_nodes_in_group("houses").size(),
		get_tree().get_nodes_in_group("village").size(),
		creature.state_name(),
		GameState.day_fraction(),
		GameState.is_night(),
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
	var dline := PackedVector2Array([
		Vector2(100, 100), Vector2(180, 175), Vector2(260, 250), Vector2(340, 330),
	])
	# A spiral: two-and-a-bit widening loops (should read as "spiral").
	var spiral := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 16.0
		var rad := 20.0 + i * 3.0
		spiral.append(Vector2(400 + cos(a) * rad, 300 + sin(a) * rad))
	print("SMOKE TEST: gesture circle -> ", GestureRecognizer.classify(circle))
	print("SMOKE TEST: gesture vline  -> ", GestureRecognizer.classify(vline))
	print("SMOKE TEST: gesture hline  -> ", GestureRecognizer.classify(hline))
	print("SMOKE TEST: gesture wave   -> ", GestureRecognizer.classify(zigzag))
	print("SMOKE TEST: gesture dline  -> ", GestureRecognizer.classify(dline))
	print("SMOKE TEST: gesture spiral -> ", GestureRecognizer.classify(spiral))
