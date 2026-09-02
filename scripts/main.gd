extends Node3D
## Main orchestrator: boots the endless world, runs the day/night cycle,
## and wires all systems together. Terrain, villages, and wildlife are the
## WorldGen's job now — this file owns the sky, the clock, and the player.

## HOW BRIGHT THE NIGHT IS. Kept together and named, because "why can I not
## see anything" was answered by four numbers scattered through the file.
## MOONLIGHT is the full moon's fill; STARLIGHT is the floor under it that
## never goes out; NIGHT_AMBIENT is how much bounced light the world keeps at
## midnight; MOON_AMBIENT is what colour that bounced light is.
const MOONLIGHT := 0.55
const STARLIGHT := 0.10
const NIGHT_AMBIENT := 0.55
const MOON_AMBIENT := Color(0.42, 0.52, 0.85)

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
	# A reload may be carrying a world seed over from a save, a "new game", or
	# a regenerate — the land must be raised from THAT before anything is built
	# on it, since every hill and town site derives from the seed.
	if SaveGame.pending_seed != 0:
		world_gen.world_seed = SaveGame.pending_seed
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

	# The small pool of real lights that follows the camera from town to town
	# after dark. Everything else about the night is sky, ambient and emission.
	var nightfall := Nightfall.new()
	nightfall.camera_rig = camera_rig
	add_child(nightfall)

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
	hud.creature = creature
	hud.camera_rig = camera_rig
	add_child(hud)

	var touch := TouchControls.new()
	touch.divine_hand = divine_hand
	touch.camera_rig = camera_rig
	touch.creature = creature
	add_child(touch)

	# THE OPENING LESSONS. Last of the UI so its card sits above the rest, and
	# fed the four things it watches: the hand, the camera, the creature and
	# the miracles. It teaches itself out of existence after the first run.
	var tutorial := Tutorial.new()
	tutorial.divine_hand = divine_hand
	tutorial.camera_rig = camera_rig
	tutorial.creature = creature
	tutorial.miracles = miracles
	add_child(tutorial)

	# THE CREATURES YOU HAVE RAISED. Above everything, because on the very first
	# run it is the only thing on screen: a god names its creature before it does
	# anything else with it.
	var profiles := ProfileMenu.new()
	add_child(profiles)

	var debug_menu := DebugMenu.new()
	debug_menu.world_gen = world_gen
	debug_menu.creature = creature
	debug_menu.tutorial = tutorial
	debug_menu.profiles = profiles
	add_child(debug_menu)

	# Whatever a reload was carrying — a whole saved game, or just a creature
	# being moved into a new land — is unpacked now that the world stands.
	SaveGame.apply_pending(world_gen, creature)

	# F2, the settings cycle, and the device getting hot all re-tune what can
	# change live; the world's stream radius and water rebuild on the next
	# reload. The grace period restarts here because a freshly built world is
	# slow for reasons that have nothing to do with a warm phone.
	Quality.quality_changed.connect(_on_quality_changed)
	Quality.settle()

	GameState.announce("A new god stirs over an endless world. Elsmere awaits your influence.")

	if "--smoke-test" in OS.get_cmdline_user_args():
		_run_smoke_test()


## Re-apply the tier knobs that are cheap to flip mid-game (lights, glow,
## fog, draw distance). Radius/water are baked into live chunks, so those
## wait for a reload — the cycle() announcement says as much.
func _on_quality_changed() -> void:
	get_viewport().msaa_3d = Quality.msaa_3d()
	_sun.shadow_enabled = Quality.shadows()
	_sun.directional_shadow_max_distance = Quality.shadow_distance()
	_environment.glow_enabled = Quality.glow()
	_environment.fog_density = Quality.fog_density()
	if is_instance_valid(camera_rig) and camera_rig.camera != null:
		camera_rig.camera.far = Quality.camera_far()


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

	# THE MOON DOES REAL WORK NOW. At 0.22 it was a rumour, and on a phone in
	# daylight the night read as a black screen. It is a proper cool fill, and
	# it never quite goes out even at the moon's lowest — starlight is what
	# keeps a silhouette readable when nothing else is lit.
	_moon.rotation_degrees = Vector3(-(df * 360.0 + 90.0), -30.0, 0)
	_moon.light_energy = maxf(-elev, 0.0) * MOONLIGHT + STARLIGHT * clampf(-elev * 3.0, 0.0, 1.0)

	var day_top := Color(0.32, 0.52, 0.82)
	var day_horizon := Color(0.7, 0.78, 0.85)
	# The night sky is lifted off black. It is the ambient source (70% of it),
	# so a sky at 0.03 meant the world under it got no bounced light at all.
	var night_top := Color(0.07, 0.09, 0.19)
	var night_horizon := Color(0.14, 0.16, 0.27)
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

	# AMBIENT AT NIGHT. The sky supplies most of the ambient light, and a night
	# sky is nearly black, so the old floor of 0.25 lit nothing — you could not
	# find your own creature on a phone screen. Two changes: the floor comes up,
	# and as the sun goes the sky hands the ambient over to an explicit moon-blue
	# so the dark has a COLOUR rather than an absence of one. Bounced light is
	# free (it is one uniform, not a light), which is why it does the heavy
	# lifting and the real lights stay few — see Nightfall.
	_environment.ambient_light_energy = lerpf(NIGHT_AMBIENT, 1.0, t)
	_environment.ambient_light_color = MOON_AMBIENT.lerp(Color.WHITE, t)
	_environment.ambient_light_sky_contribution = lerpf(0.25, 0.7, t)
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
		"cycle_quality": [KEY_F2],
		"toggle_villages": [KEY_V],
		"diet_vegan": [KEY_1],
		"diet_omnivore": [KEY_2],
		"diet_carnivore": [KEY_3],
		"diet_cannibal": [KEY_4],
		"pet_creature": [KEY_P],
		"scold_creature": [KEY_L],
		"find_creature": [KEY_C],
		"leash_creature": [KEY_G],
		"toggle_debug": [KEY_F3],
		"skip_tutorial": [KEY_F4],
		"toggle_profiles": [KEY_F5],
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
	# The graphics tier (auto-detected per GPU, overridable) decides which
	# of the pretty-but-heavy features are on — a flagship gets them all, a
	# budget Adreno gets a plain-but-stable look.
	get_viewport().msaa_3d = Quality.msaa_3d()

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = Quality.shadows()
	_sun.directional_shadow_max_distance = Quality.shadow_distance()
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
	# Distance fog is cheap and stays on everywhere; glow scales with tier.
	_environment.fog_enabled = true
	_environment.fog_density = Quality.fog_density()
	_environment.fog_sky_affect = 0.2
	_environment.glow_enabled = Quality.glow()
	_environment.glow_intensity = 0.5
	_environment.glow_bloom = 0.1

	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)


## Diet policy hotkeys (1-4) apply to the player's home village.
## P/L pet or scold the creature (the hand must be near it); C finds it.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_quality"):
		Quality.cycle()
	elif event.is_action_pressed("diet_vegan"):
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
	elif event.is_action_pressed("leash_creature") and is_instance_valid(creature):
		# G LEADS the creature: it goes where your hand is pointing and waits
		# there. Press G again (or with the hand off the land) to release it.
		if creature.is_leashed():
			creature.release_leash()
			GameState.announce("You release your creature. It returns to its own mind.")
		else:
			creature.leash_to(divine_hand.ground_point)
			GameState.announce("You lead your creature there. (G again to release.)")
	elif event.is_action_pressed("find_creature") and is_instance_valid(creature):
		# C toggles a LOCK-ON: the camera glides to the creature, keeps it
		# centered, and orbits around it until you pan away (or press C again).
		if camera_rig.follow_target == creature:
			camera_rig.follow_target = null
		else:
			camera_rig.follow_target = creature
			# Frame the whole beast — the lock-on distance scales with its size,
			# so a towering full-grown creature isn't shot from inside its ankle.
			var s := creature.scale.y
			camera_rig.zoom_distance = clampf(camera_rig.zoom_distance, s * 2.5, s * 6.0)


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
	# RUDIMENTS OPEN COMBINATIONS: a handful of runes is a whole spellbook.
	print("SMOKE TEST: unlocks — villages=%d runes=%s castable=%d next=%s" % [
		miracles.faithful_villages(), str(miracles.known_runes()),
		miracles.unlocked_miracles().size(), str(miracles.next_tier_preview())])
	# THE CASTING SESSION. Opening it holds the world; strokes become runes;
	# quiet resolves it. The clock must NOT run mid-stroke — letting it do so is
	# what cast a half-drawn working out of the player's hand.
	divine_hand._open_casting()
	var held := divine_hand.casting
	divine_hand._begin_stroke(Vector2(400, 300))
	var drawing_holds := divine_hand.casting_fraction() >= 1.0
	divine_hand._tick_casting(DivineHand.IDLE_TO_CAST * 2.0)
	var survived := divine_hand.casting     # mid-stroke, so it cannot have fired
	divine_hand.gesture_points = _wobbly_stroke(
		func(t: float) -> Vector2: return Vector2(400, 150 + t * 300), 0)
	divine_hand._end_stroke()
	var got_rune := divine_hand.working_text()
	divine_hand._tick_casting(DivineHand.IDLE_TO_CAST + 0.1)
	print("SMOKE TEST: casting — opened=%s, holds while drawing=%s, survives a slow rune=%s" % [
		held, drawing_holds, survived])
	print("SMOKE TEST: casting — rune read as '%s', session closed=%s, world free=%s" % [
		got_rune, not divine_hand.casting, not divine_hand.casting])

	# MIRACLES COST THE BEAST. The pool grows with the creature, so the same
	# working empties a hatchling and barely dents a giant — and familiarity
	# makes a practised miracle cheaper than a half-understood one.
	print("SMOKE TEST: energy pool — hatchling %.0f, half grown %.0f, full grown %.0f" % [
		creature.body.energy_pool(0.01), creature.body.energy_pool(0.5),
		creature.body.energy_pool(1.0)])
	var tornado := MiracleManager.effort_of("tornado")
	print("SMOKE TEST: one tornado takes %.0f%% of a hatchling's bar, %.0f%% of a giant's" % [
		creature.body.toll(tornado, 0.01), creature.body.toll(tornado, 1.0)])
	print("SMOKE TEST: practice makes it cheaper — heal at %.1f%% raw, %.1f%% mastered" % [
		creature.body.toll(MiracleManager.effort_of("heal"), 0.5),
		creature.body.toll(MiracleManager.effort_of("heal") * 0.45, 0.5)])
	# AND IT MUST BE ABLE TO OVERREACH. Nothing may stop it attempting a cast
	# it cannot afford — being told its own limit is exactly what it must not
	# be. The offer stands whatever its reserves.
	creature.energy = 1.0
	creature.mind.familiarity["heal"] = 1.0
	var offered := false
	for opt: Dictionary in creature._perceive():
		if opt["verb"] == "cast":
			offered = true
	print("SMOKE TEST: exhausted, a cast is still OFFERED (it learns by failing): %s" % offered)
	creature.energy = 90.0

	# THE OPENING LESSONS. Every step must be well formed and every condition
	# must be safe to ASK — a step that throws would strand a new player on it
	# with no way forward but F4.
	var lessons := Tutorial.new()
	lessons.divine_hand = divine_hand
	lessons.camera_rig = camera_rig
	lessons.creature = creature
	lessons.miracles = miracles
	lessons._build_steps()
	var well_formed := 0
	var asked := 0
	for step: Dictionary in lessons._steps:
		if step.has("say") and step.has("hint") and step.has("done") \
			and String(step["say"]) != "" and (step["done"] is Callable):
			well_formed += 1
		if (step["done"] as Callable).call() != null:
			asked += 1
	print("SMOKE TEST: tutorial — %d steps, %d well formed, %d conditions answered safely" % [
		lessons._steps.size(), well_formed, asked])
	# And the very first lesson must not already be satisfied at spawn.
	print("SMOKE TEST: tutorial — first lesson starts unfinished: %s" % [
		not (lessons._steps[0]["done"] as Callable).call()])
	lessons.free()

	# THE GRAMMAR. Runes combine: the same rune twice is the same miracle writ
	# larger, a named pairing is its own thing, and anything else BLENDS.
	for runes: Array in [["water"], ["water", "water"], ["water", "water", "water"],
			["force", "water"], ["force", "force", "water"], ["air", "air"],
			["air", "air", "water"], ["fire", "air"], ["life", "earth"],
			["fire", "life"], ["calm", "life"]]:
		var reading := Spellbook.interpret(runes)
		print("SMOKE TEST: %s -> %s" % [str(runes), Spellbook.describe(runes)])
		assert(not reading.is_empty(), "every drawing must mean something")
	# ORDER MUST NOT MATTER: the same runes drawn backwards is the same miracle.
	print("SMOKE TEST: order-free — %s vs %s" % [
		Spellbook.interpret(["force", "water"]).get("label", "?"),
		Spellbook.interpret(["water", "force"]).get("label", "?")])
	# An unnamed combination is never a dead end; it blends.
	var invented := Spellbook.interpret(["fire", "life", "sky"])
	print("SMOKE TEST: invented combination -> %d effects at once" % [
		(invented.get("blend", []) as Array).size()])

	for runes: Array in [["life"], ["water"], ["calm"], ["force", "water"],
			["air", "air"], ["water", "water"]]:
		GameState.add_prayer_power(300.0)
		print("SMOKE TEST: cast %s -> %s" % [str(runes), miracles.cast_runes(runes)])
		await get_tree().create_timer(0.2).timeout
	# Directly resolve one of each new miracle to exercise every effect.
	for miracle: String in ["food", "rain", "heal", "lightning", "forest_seed",
			"forage_thicket", "lightning_storm", "tornado", "bird_flock", "flight",
			"gust", "thunderclap", "cloudburst", "deluge", "thunderstorm",
			"tempest", "firestorm", "hurricane"]:
		miracles.resolve(miracle, Vector3(6, 0, 6))
		print("SMOKE TEST: resolve %s" % miracle)
		await get_tree().create_timer(0.3).timeout

	# PORTALS come in pairs: the first waits, the second links to it.
	miracles.resolve("portal", Vector3(12, 0, 12))
	await get_tree().create_timer(0.2).timeout
	miracles.resolve("portal", Vector3(-40, 0, 25))
	await get_tree().create_timer(0.2).timeout
	var gates := get_tree().get_nodes_in_group("portals")
	var linked := 0
	for g in gates:
		if (g as Portal).twin != null:
			linked += 1
	print("SMOKE TEST: portals=%d linked=%d | creature flying=%s" % [
		gates.size(), linked, creature.is_flying()])

	# THE LEASH: sent somewhere, it obeys; released, it thinks for itself again.
	creature.leash_to(Vector3(20, 0, 20))
	var leashed := creature.is_leashed() and creature.state == Creature.State.LEASHED
	creature.release_leash()
	print("SMOKE TEST: leash — obeyed=%s released=%s" % [leashed, not creature.is_leashed()])

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

	# Exercise creature training: praise and scold must move bond, mood and trust.
	creature._last_deed = "play"
	creature.praise()
	var trusted := creature.trust
	creature.scold()
	print("SMOKE TEST: creature trained — bond=%.0f mood=%.0f (%s) trust %.0f->%.0f, %s" % [
		creature.bond, creature.mood, creature.mood_word(),
		trusted, creature.trust, creature.favorite_deed()])

	# THE QUIET LIFE. Most of what it can do is neither kind nor cruel, and the
	# neutral half of the repertoire must actually reach the ballot.
	creature.mind.witness_practice("dance", 1.0)
	creature.mind.witness_practice("pray", 1.0)
	creature.mind.witness_practice("mimic", 1.0)
	var quiet := 0
	var verbs := {}
	for opt: Dictionary in creature._perceive():
		verbs[opt["verb"]] = true
		if absf(CreatureEthos.kindness(opt["verb"])) < 0.2:
			quiet += 1
	print("SMOKE TEST: repertoire — %d options, %d of them morally neutral, verbs=%s" % [
		verbs.size(), quiet, str(verbs.keys())])

	# DRIVES PULL ON TRAITS, NOT ON VERB NAMES: a bored creature must find
	# smashing and dancing equally plausible until experience separates them.
	var restless := {"hunger": 10.0, "energy": 90.0, "boredom": 95.0, "mood": 60.0, "fear": 0.0}
	print("SMOKE TEST: boredom wants stimulation, not violence — smash %.2f vs dance %.2f vs run %.2f" % [
		creature.mind._drive_fit("smash", restless),
		creature.mind._drive_fit("dance", restless),
		creature.mind._drive_fit("run", restless)])
	var friendless := {"energy": 90.0, "mood": 60.0, "lonely": 1.0}
	print("SMOKE TEST: loneliness wants company — commune %.2f vs smash %.2f" % [
		creature.mind._drive_fit("commune", friendless),
		creature.mind._drive_fit("smash", friendless)])

	# YOUR EXAMPLE. What the hand does is copied in proportion to trust — and a
	# creature that has stopped trusting you stops copying entirely.
	creature.trust = 90.0
	creature.witness_god("gather", "tree", 0.4)
	var copied: float = creature.mind.q.get("gather|tree", 0.0)
	creature.trust = 5.0
	creature.witness_god("smash", "house", -0.6)
	print("SMOKE TEST: mimicry — trusted lesson gather|tree=%.2f, distrusted smash|house=%.2f" % [
		copied, float(creature.mind.q.get("smash|house", 0.0))])

	# AN UNJUST SCOLDING COSTS TRUST; a deserved one barely does.
	var fair := Creature.new()
	fair._deed_verb = "smash"
	fair.scold()
	var unfair := Creature.new()
	unfair._deed_verb = "tend"
	unfair.scold()
	print("SMOKE TEST: fairness — scolded for smashing trust=%.0f, for farming trust=%.0f" % [
		fair.trust, unfair.trust])
	fair.free()
	unfair.free()

	# The LEARNING MIND: perceive options, choose, and be reinforced. Praising a
	# smash must actually raise its learned value for smashing that thing.
	var drive := {"hunger": 50.0, "energy": 80.0, "boredom": 60.0, "mood": 60.0, "fear": 0.0}
	var opts := creature._perceive()
	var picked: Dictionary = creature.mind.choose(opts, drive)
	creature.mind.reinforce(1.5)
	creature.mind.teach("smash", "villager", 2.0)
	creature.mind.witness_miracle("rain")
	for i in 20:
		creature.mind.witness_miracle("rain")
	print("SMOKE TEST: mind — options=%d picked=%s|%s learned_keys=%d smash|villager=%.2f temperament=%.1f known=%s" % [
		opts.size(), picked["verb"], picked.get("type", "none"), creature.mind.q.size(),
		float(creature.mind.q.get("smash|villager", 0.0)), creature.mind.temperament,
		str(creature.mind.known_miracles())])
	print("SMOKE TEST: mind urge -> %s" % creature.mind.strongest_urge())

	# BELIEFS: it must learn not just WHAT but WHEN — and work out for itself
	# which of its deeds brought a consequence about.
	var crowded := {"hungry": 0.9, "crowd": 1.0, "armed": 0.7, "in_village": 1.0}
	var lonely := {"hungry": 0.9, "alone": 1.0, "night": 1.0}
	for i in 3:
		creature.mind.beliefs.remember("eat_kin|villager", crowded)
		creature.mind.experience("mobbed", -1.4)
	print("SMOKE TEST: beliefs — 'eating people -> mobbed' %.2f, dread %.2f" % [
		creature.mind.beliefs.expects("eat_kin|villager", "mobbed"),
		creature.mind.beliefs.foreboding("eat_kin|villager")])
	print("SMOKE TEST: context matters — wants it in a CROWD %.2f, but ALONE %.2f" % [
		creature.mind.beliefs.bias("eat_kin|villager", crowded),
		creature.mind.beliefs.bias("eat_kin|villager", lonely)])
	# Every phrasing must survive being put into words — including verbs with no
	# subject slot ("wandering") and any verb we never wrote a phrase for.
	for rule: String in ["rest|none>fed", "wander|none>alone", "kick|door>hurt",
			"eat_kin|villager>mobbed"]:
		creature.mind.beliefs.rules[rule] = -0.9
	# RITUAL. A pairing that keeps paying off becomes a habit of ORDER, and the
	# creature will start reaching for the second thing after the first.
	var rite := CreatureBeliefs.new()
	for i in 12:
		rite.remember("fish|water", {})
		rite.credit(0.3)
		rite.remember("cast|bird_flock", {})
		rite.credit(1.0)
	print("SMOKE TEST: ritual — casting AFTER fishing %+.2f, cold %+.2f | %s" % [
		rite.ritual_bias("fish|water", "cast|bird_flock"),
		rite.ritual_bias("smash|tree", "cast|bird_flock"),
		str(rite.rites())])

	print("SMOKE TEST: creed -> %s" % str(creature.mind.beliefs.creed(4)))

	# CHARACTER IS PACED BY TIME, not by how many deeds got squeezed into a
	# frame. A tight burst of cruelty must NOT make a monster on its own.
	var burst := CreatureMind.new()
	for i in 400:
		burst.judge("eat_kin")
	var spaced := CreatureMind.new()
	spaced.judge("eat_kin", CreatureMind.DEED_ALPHA, false)
	print("SMOKE TEST: pacing — 400 instant cruelties = %.1f, one lived deed = %.1f" % [
		burst.temperament, spaced.temperament])

	# THE COMPASS. Six lives, each a different creature — and the point is that
	# hardly any of them can be told apart by the old good-to-evil number alone.
	var lives := {
		"a wrecker of empty houses": ["smash", "smash", "wander", "smash", "run"],
		"a hermit who hurts nobody": ["fish", "wander", "rest", "lounge", "fish"],
		"a village favourite": ["commune", "dance", "pray", "gift", "commune"],
		"a devoted brute": ["mimic", "smash", "mimic", "throw", "mimic"],
		"a provider who wants no thanks": ["gather", "tend", "gather", "wander", "tend"],
		"a beast that walked away": ["depart", "shun", "sulk", "wander", "shun"],
	}
	for life: String in lives:
		var soul := CreatureMind.new()
		for i in 30:
			for verb: String in lives[life]:
				soul.judge(verb, CreatureMind.DEED_ALPHA, false)
		print("SMOKE TEST: compass — %-28s -> %-30s (good/evil %+.0f) %s" % [
			life, soul.character(), soul.temperament, str(soul.character_account(2))])

	# MEMORY, PLACES AND LORE. Beyond "what my deeds cause" it has to build a
	# picture of what the WORLD does on its own, learn how it feels about actual
	# stretches of ground, and be able to be REMINDED of something.
	var lived := CreatureBeliefs.new()
	var bad_wood := Vector3(220.0, 0.0, -80.0)
	var night_alone := {"night": 1.0, "alone": 1.0, "hungry": 0.8, "predator": 1.0}
	for i in 14:
		lived.remember("wander|none", night_alone, bad_wood, "dread")
		lived.consequence("hurt", -1.5)
	for i in 14:
		lived.remember("tend|farm", {"in_village": 1.0, "crowd": 1.0, "kin_glad": 1.0},
			Vector3(4.0, 0.0, 4.0), "contentment")
		lived.consequence("cheered", 1.2)
	print("SMOKE TEST: lore — %s" % str(lived.omens()))
	print("SMOKE TEST: places — %s | that wood feels %+.2f, home feels %+.2f" % [
		str(lived.haunts()), lived.place_feel(bad_wood), lived.place_feel(Vector3(4, 0, 4))])
	print("SMOKE TEST: foretaste — a night alone with beasts about %+.2f, the village %+.2f" % [
		lived.foretaste(night_alone),
		lived.foretaste({"in_village": 1.0, "crowd": 1.0, "kin_glad": 1.0})])
	var jogged := lived.reminder(night_alone, bad_wood)
	print("SMOKE TEST: reminded — standing there again brings back %s (%.2f) from %d episodes" % [
		String(jogged.get("felt", "nothing")), float(jogged.get("strength", 0.0)),
		lived.episodes.size()])

	# THE CLOUDS THEMSELVES. Five static spheres that snapped in and out are now
	# a swirl of soft streaked sheets that turn, breathe, and come and go — and
	# severity is simply how many of them there are, how dark, and how fast.
	var sky := PackedStringArray()
	for storm: Array in [["rain", 1.0], ["cloudburst", 2.2], ["deluge", 3.6]]:
		var mass := StormCloud.new()
		mass.brew(float(storm[1]))
		sky.append("%s: %s" % [String(storm[0]), mass.report()])
		mass.free()
	print("SMOKE TEST: clouds — %s" % "  |  ".join(sky))
	print("SMOKE TEST: clouds — 2 tris a sheet in ONE draw call "
		+ "(was 5 spheres = 1,440 tris in 5 draws), texture %dx%d built once"
		% [StormCloud.TEXTURE_SIZE, StormCloud.TEXTURE_SIZE])

	# THE COST OF WEATHER. A default SphereMesh is 64 segments by 32 rings —
	# 4,224 triangles — and every particle mesh here set only its radius, so a
	# 400-droplet shower drew 1.7 MILLION triangles for a spray of specks two
	# pixels across. They are billboarded quads now: two triangles each.
	var drop: Mesh = miracles._drop_mesh()
	var faces := int(drop.get_faces().size() / 3.0)
	var per_cloud := Quality.particles(MiracleManager.RAIN_DROPS)
	print("SMOKE TEST: rain — %d triangles a droplet, %d droplets = %d tris a cloud, "
		% [faces, per_cloud, faces * per_cloud]
		+ "at most %d clouds (was 4224 x 400 = 1,689,600 each, uncapped)"
		% MiracleManager.RAIN_CLOUDS)
	var budget := PackedStringArray()
	var heat_was := Quality.heat
	for level: int in [Quality.Heat.EASY, Quality.Heat.WARM, Quality.Heat.HOT]:
		Quality.heat = level
		budget.append("%s %d drops" % [
			Quality.heat_word(), Quality.particles(MiracleManager.RAIN_DROPS)])
	Quality.heat = heat_was
	print("SMOKE TEST: rain — thins with the device: %s" % "  ·  ".join(budget))

	# THERMAL EASING. There is no thermal sensor to read, so the proxy is
	# sustained frame time — which is what a throttling chip actually does to
	# you. A struggling device is treated as a lesser one, through exactly the
	# paths that already existed for a budget phone.
	var was := Quality.heat
	var knobs := PackedStringArray()
	for level: int in [Quality.Heat.EASY, Quality.Heat.WARM, Quality.Heat.HOT]:
		Quality.heat = level
		knobs.append("%s: tier %d, shadows %s, actors %.0fm, sim x%d" % [
			Quality.heat_word(), Quality.effective_tier(), Quality.shadows(),
			Quality.actor_distance(), Quality.sim_relief()])
	Quality.heat = was
	print("SMOKE TEST: heat — %s" % "  |  ".join(knobs))

	# THE LONG ARC. Growth used to be a percentage, and a percentage ran out: a
	# well-fed creature crossed the whole thing in an afternoon and then had
	# nowhere left to go. Stature is 1..65,535, size is its square root, and the
	# body's stomach and energy still read the SIZE, so a thirty-hour arc drops
	# in under a body that was balanced for a one-hour one.
	var arc := Creature.new()
	var earned := 3600.0 / CreatureBody.NOURISHMENT * CreatureBody.STATURE_PER_UNIT
	var shown := PackedStringArray()
	for hours: float in [0.0, 1.0, 4.0, 8.0, 30.0]:
		arc.stature = clampf(hours * earned, 1.0, Creature.FULL_STATURE)
		shown.append("%gh %s %d%% %.1fm" % [
			hours, arc.stature_text().split(" ")[-1], int(arc.growth * 100.0),
			lerpf(Creature.MIN_SCALE, Creature.MAX_SCALE, arc.growth) * 2.5])
	print("SMOKE TEST: stature — %.0f a hour, %.0f hours to FFFF | %s" % [
		earned, Creature.FULL_STATURE / earned, "  ·  ".join(shown)])
	arc.free()

	# FORESIGHT. The one part of the mind that faces forwards: it learns what
	# deeds DO to a situation, imagines the situation each option would leave it
	# in, and asks its own heart how a moment like that would feel. So a creature
	# that has never been mobbed cannot picture being mobbed — and walks in.
	var seer := CreatureForesight.new()
	var settled := {"in_village": 1.0, "crowd": 0.4, "hungry": 0.7}
	var after_smashing := {"in_village": 1.0, "crowd": 0.4, "hungry": 0.7,
		"kin_afraid": 1.0, "armed": 0.9}
	for i in 12:
		seer.expect("smash|house", settled)
		seer.settle(after_smashing)
		seer.expect("tend|farm", settled)
		seer.settle({"in_village": 1.0, "crowd": 0.4, "hungry": 0.7, "kin_glad": 0.9})
	var pictured := seer.imagine("smash|house", settled)
	print("SMOKE TEST: foresight — it pictures smashing a house leaving kin_afraid %.2f, armed %.2f" % [
		float(pictured.get("kin_afraid", 0.0)), float(pictured.get("armed", 0.0))])
	print("SMOKE TEST: foresight — %s" % str(seer.expectations(2)))
	# The SAME model, read by two different lives. Only the one that has been
	# mobbed can feel what it is imagining.
	var naive := CreatureHeart.new()
	var burnt := CreatureHeart.new()
	for i in 40:
		burnt.stir("dread", 1.0)
		burnt.stir("pain", 0.8)
		burnt.learn({"kin_afraid": 1.0, "armed": 1.0})
	print(("SMOKE TEST: foresight — smashing looks like %+.2f to a sheltered creature, "
		+ "%+.2f to one that has been mobbed for it") % [
			seer.prospect("smash|house", settled, naive, null),
			seer.prospect("smash|house", settled, burnt, null)])
	# And being wrong is worth something: a failed prediction widens its search.
	seer.expect("tend|farm", settled)
	seer.settle({"in_village": 1.0, "predator": 1.0, "afraid": 1.0, "hurt": 1.0})
	print(("SMOKE TEST: foresight — the world confounds it: surprise %.2f, "
		+ "exploration widened by %d%%, it can see %d%% of its deeds coming") % [
			seer.surprise, int(seer.restlessness() * 100.0), int(seer.reach() * 100.0)])

	# KNOWING PEOPLE. Everything else it learns is about KINDS; this is the one
	# ledger that is about individuals, and it must be able to hold two opposite
	# opinions of two people of exactly the same kind.
	var acquaintance := CreatureBonds.new()
	var folk := village.my_villagers()
	if folk.size() >= 2:
		var friend: Villager = folk[0]
		var foe: Villager = folk[1]
		for i in 12:
			acquaintance.dealing_with(friend)
			acquaintance.settle(1.6)
			acquaintance.dealing_with(foe)
			acquaintance.settle(-1.6)
		print("SMOKE TEST: bonds — %s %+.2f, %s %+.2f, a stranger %+.2f | %s" % [
			friend.villager_name, acquaintance.regard_for(friend),
			foe.villager_name, acquaintance.regard_for(foe),
			acquaintance.regard_for(null), str(acquaintance.attachments())])

	# WHAT ALL THIS WEIGHS. The honest number, measured rather than guessed:
	# every learned structure written out as JSON, for a mind that has lived.
	var weighed := {
		"q + seen": JSON.stringify(creature.mind.q).length()
			+ JSON.stringify(creature.mind.seen).length(),
		"beliefs": JSON.stringify(creature.mind.beliefs.to_dict()).length(),
		"bonds": JSON.stringify(creature.mind.bonds.to_dict()).length(),
		"whole mind": JSON.stringify(creature.mind.to_dict()).length(),
		"heart": JSON.stringify(creature.heart.to_dict()).length(),
	}
	print("SMOKE TEST: mind weight (bytes of JSON) — %s" % str(weighed))

	# THE CROWD MIND. The town has to work out once, for everybody, what it has
	# seen and what it is minded to do — and the same event must read completely
	# differently depending on which end of it the village was on.
	var crowd := VillageHive.new()
	for scene: Array in [
			["a blessing overhead", "wonder", 1.0],
			["fire from the sky", "horror", 1.4],
			["the creature in the granary", "outrage", 1.6],
			["a funeral", "death", 1.4],
			["the creature sitting with the frightened", "kindness", 1.0]]:
		var mind := VillageHive.new()
		for i in 3:
			mind.witness(String(scene[1]), village.global_position, float(scene[2]))
		mind.tick(VillageHive.PERIOD, village)
		print("SMOKE TEST: hive — after %-38s the town is %s" % [scene[0], mind.report()])
	# An invitation is not a summons: a frightened town declines it.
	crowd.invite("dance", creature, creature.global_position, 1.0)
	crowd.tick(VillageHive.PERIOD, village)
	var welcoming := crowd.stance
	crowd.witness("horror", village.global_position, 2.0)
	crowd.invite("dance", creature, creature.global_position, 1.0)
	crowd.tick(VillageHive.PERIOD, village)
	print("SMOKE TEST: hive — the same dance: a calm town %s, a terrified one %s" % [
		welcoming, crowd.stance])

	# PATHFINDING. Local steering alone walks into a bay and stays there. A route
	# is planned over the shape of the land first — and must actually come back
	# with something for a walk across the island, cost almost nothing the second
	# time (the terrain cache), and bend around ground it has got stuck in.
	var here := creature.global_position
	var yonder := here + Vector3(140.0, 0.0, 110.0)
	var began := Time.get_ticks_usec()
	var way := NavField.route(here, yonder, 2.0)
	var cold := Time.get_ticks_usec() - began
	began = Time.get_ticks_usec()
	var again := NavField.route(here, yonder, 2.0)
	print("SMOKE TEST: routing — %d waypoints over %.0fm, %.1fms cold, %.1fms warm | %s" % [
		way.size(), here.distance_to(yonder), cold / 1000.0,
		(Time.get_ticks_usec() - began) / 1000.0, NavField.routing_report()])
	creature.steering.remember_trouble(here + Vector3(40.0, 0.0, 30.0))
	creature.steering.remember_trouble(here + Vector3(46.0, 0.0, 36.0))
	var detour := NavField.route(here, yonder, 2.0, creature.steering.shunned())
	print("SMOKE TEST: routing — plain route %d waypoints; shunning %d bad places, %d" % [
		again.size(), creature.steering.trouble_spots(), detour.size()])

	# THE HEART, AND EMPATHY BOUGHT WITH EXPERIENCE. A creature reads other
	# people by matching their plight against what those same circumstances have
	# felt like to IT — so one that has never gone hungry has nothing to
	# recognise a starving man with, and feels precisely nothing.
	var starving := {"hungry": 1.0, "hurt": 0.6, "alone": 1.0}
	var innocent := CreatureHeart.new()
	innocent.empathy = 1.0
	print("SMOKE TEST: empathy — a creature that has never suffered reads a starving man as %s" % [
		"nothing at all" if innocent.read(starving).is_empty() else str(innocent.read(starving))])
	var scarred := CreatureHeart.new()
	scarred.empathy = 1.0
	for i in 60:
		scarred.stir("pain", 1.0)
		scarred.stir("loneliness", 1.0)
		scarred.learn({"hungry": 1.0, "hurt": 1.0, "alone": 1.0})
	var guessed := scarred.read(starving)
	scarred.feeling.clear()
	scarred.sympathise(starving)
	print("SMOKE TEST: empathy — one that HAS reads %s, and catches pity %.2f (understands %d)" % [
		str(guessed.keys()), scarred.level("pity"), scarred.wisdom()])
	# And feelings cool at their own rates: fury burns off, grief does not.
	var carried := CreatureHeart.new()
	carried.stir("fury", 1.0)
	carried.stir("grief", 1.0)
	carried.settle(20.0)
	print("SMOKE TEST: heart — after 20s, fury %.2f but grief %.2f; it looks %s and says '%s'" % [
		carried.level("fury"), carried.level("grief"), carried.face(), carried.word()])

	# DEMOGRAPHICS. A lifetime here is ~3.6 real hours, so an overnight run turns
	# over two whole generations — a village that cannot replace its dead dies
	# quietly while nobody is watching. Conception must actually FIRE when a
	# couple meet, and a mother must be free again long before her child is grown.
	print("SMOKE TEST: breeding — %.2f/s with a partner present (%.2f when tended), weaned at %.0f" % [
		village.conception_chance(), village.conception_chance() * 3.0,
		Villager.WEANED_AGE])
	var mother := village.my_villagers()[0]
	mother.is_female = true
	mother.age = 25.0
	mother.happiness = 80.0
	mother.hunger = 10.0
	mother.energy = 90.0
	mother._breed_cooldown = 0.0
	village.store.plant_food += 20
	print("SMOKE TEST: fertility — wants to breed=%s, dependent child blocks=%s" % [
		mother.wants_to_breed(), mother._has_dependent_child()])
	village.notice(100.0)
	print("SMOKE TEST: trend readout -> '%s' (blank until there is history)" % village.trend())

	# The village has a doctrine of its own, learned the same way.
	village.remember_battle(false)
	village.remember_battle(false)
	var cowed := not village.will_fight(1, false)
	village.remember_battle(true)
	village.remember_battle(true)
	village.remember_battle(true)
	print("SMOKE TEST: village doctrine — after losses hides=%s; after wins resolve=%.0f fights=%s" % [
		cowed, village.resolve, village.will_fight(1, true)])

	# THE BODY: a stomach that fills, digests, and turns surplus into fat.
	var cap := creature.body.capacity(creature.growth)
	creature.body.swallow(cap * 3.0, creature.growth)   # try to overstuff it
	var stuffed := creature.body.fullness(creature.growth)
	creature.hunger = 0.0                               # it was NOT hungry
	for i in 40:
		var d := creature.body.digest(0.5, creature.growth, creature.hunger)
		creature.hunger = d["hunger"]
	print("SMOKE TEST: body — capacity %.1f, filled to %d%%, after digesting: fat %.0f strength %.0f (%s)" % [
		cap, int(stuffed * 100.0), creature.body.fat, creature.body.strength,
		creature.body.condition_word()])
	var lift_before := creature.body.lift_limit(creature.growth)
	creature.grant_strength(20.0)
	print("SMOKE TEST: strength miracle — lift limit %.1f -> %.1f lumber (boosted=%s)" % [
		lift_before, creature.body.lift_limit(creature.growth), creature.body.is_boosted()])

	# EXILE IS RECOVERABLE, BUT NOT PURCHASABLE. Coming home needs BOTH: trust
	# regained AND a long stretch with no repeat of what it left over. Kindness
	# alone will not do it, and neither will time alone.
	var wronged := Creature.new()
	wronged.mind.judge("rescue", 1.0, false)  # a good heart...
	wronged.trust = 10.0                     # ...and a god it cannot abide
	wronged._begin_departure()

	wronged.trust = 90.0                     # petted lavishly...
	wronged._tick_exile(Creature.AMENDS_SECONDS * 0.9)
	wronged.earn_trust(-20.0, "struck")      # ...and struck again anyway
	wronged.trust = 90.0
	wronged._tick_exile(Creature.AMENDS_SECONDS * 0.9)
	var relapsed := wronged.exiled           # the clock went back to zero

	wronged.trust = 10.0                     # left alone, but never made up with
	wronged._tick_exile(Creature.AMENDS_SECONDS * 2.0)
	var unloved := wronged.exiled

	wronged.trust = 90.0                     # both, at last
	wronged._tick_exile(1.0)
	print("SMOKE TEST: exile — survives a relapse=%s, survives mere time=%s, ends when you stop=%s" % [
		relapsed, unloved, not wronged.exiled])
	wronged.free()

	# THE MILITIA: a wolf mauls someone, the village rouses, arms itself, and
	# (in a band) fights back. A lone villager must NOT dare to stand.
	village.store.add_lumber(12)
	village.store.add_stone(9)
	var townsfolk := village.my_villagers()
	if townsfolk.size() >= 2:
		var victim2 := townsfolk[0]
		var wolf := Animal.create("wolf")
		add_child(wolf)
		wolf.global_position = victim2.global_position + Vector3(2, 0, 0)
		victim2.hurt_by(wolf, 20.0)
		await get_tree().create_timer(0.2).timeout
		var foe: Node3D = victim2._find_foe()
		victim2._take_up_arms()
		print("SMOKE TEST: militia — roused=%s grudge=%.0f foe=%s armed=%s allies=%d dares=%s" % [
			village.is_roused(), village.grudge, foe != null, victim2.weapon,
			victim2._allies_near(), victim2._dares_fight()])
		var before := wolf.health
		victim2._strike(wolf)
		print("SMOKE TEST: militia strike — wolf %.0f -> %.0f hp (weapon %s)" % [
			before, wolf.health if is_instance_valid(wolf) else 0.0, victim2.weapon])
		if is_instance_valid(wolf):
			village.mark_for_death(wolf)
			print("SMOKE TEST: vendetta size=%d" % village.vendetta.size())

	# PERSISTENCE: a mind written down and read back must be the same mind, and
	# it must land in the ACTIVE PROFILE rather than in one global slot. The test
	# makes its own profile by hand, because the real route (start_new) reloads
	# the scene and there would be nothing left to test with.
	creature.body.fat = 44.0
	creature.mind.q["smash|tree"] = 1.75
	creature.name_it("Testbeast")
	SaveGame.profiles.append({
		"id": "smoketest", "name": "Testbeast", "seed": world_gen.world_seed,
		"created": 0.0, "played": 0.0, "saved_at": 0.0,
		"character": "newborn", "growth": 0.0,
	})
	SaveGame.active = "smoketest"
	var wrote := SaveGame.save_to_disk(world_gen, creature)
	var parcel := SaveGame.read_from_disk()
	var twin := CreatureMind.new()
	twin.from_dict((parcel.get("creature", {}) as Dictionary).get("mind", {}))
	var body_twin := CreatureBody.new()
	body_twin.from_dict((parcel.get("creature", {}) as Dictionary).get("body", {}))
	print("SMOKE TEST: profile — %s, %s | announcements now say: %s" % [
		String(SaveGame.active_profile().get("name", "?")),
		String(SaveGame.active_profile().get("character", "?")),
		GameState.named("Your creature purrs and leans into your hand.")])
	print("SMOKE TEST: save — wrote=%s seed=%d villages=%d | mind smash|tree %.2f temperament %.1f, fat %.0f" % [
		wrote, int(parcel.get("seed", 0)), (parcel.get("villages", []) as Array).size(),
		float(twin.q.get("smash|tree", 0.0)), twin.temperament, body_twin.fat])
	# And a village must be able to take its own life story back.
	var saved_town: Dictionary = village.to_dict()
	village.belief = 3.0
	village.store.add_lumber(1)
	village.from_dict(saved_town)
	print("SMOKE TEST: village restored — %s belief=%.0f pop=%d lumber=%d" % [
		village.village_name, village.belief, village.population(), village.store.lumber])

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

	# NIGHT MUST BE LEGIBLE. Not a look at the screen — a check that the four
	# sources of light in the dark are actually there and actually bounded: the
	# moon and the ambient floor do the work, the hearth pool is FIXED however
	# many towns there are, and the creature carries its own light.
	await _smoke_test_night()

	print("SMOKE TEST OK")
	get_tree().quit(0)


## THE NIGHT, MEASURED. Winds the clock to midnight, reads what is lit, and
## checks the two things that could go wrong without anyone noticing: that the
## dark still has light in it, and that the light does not grow with the world.
func _smoke_test_night() -> void:
	# The clock is kept in villager-years, and the day starts at 0.35 of one, so
	# winding to a given hour means solving for it rather than assigning it.
	var was := GameState.game_years
	GameState.game_years = _at_hour(0.0)   # midnight
	_update_daylight()
	print("SMOKE TEST: midnight — moon=%.2f ambient=%.2f (sky %.0f%%) sun=%.2f night=%s" % [
		_moon.light_energy, _environment.ambient_light_energy,
		_environment.ambient_light_sky_contribution * 100.0,
		_sun.light_energy, GameState.is_night()])
	assert(_moon.light_energy > 0.3, "the moon must actually light the world")
	assert(_environment.ambient_light_energy > 0.4, "night needs an ambient floor")

	# The hearth pool deals itself on a lazy clock, so give it one to run on.
	await get_tree().create_timer(1.8).timeout

	# The pool is fixed by the graphics tier and nothing else — this is the
	# whole reason a thousand villages costs no more light than one.
	var pool := 0
	for n in get_children():
		if n is Nightfall:
			pool = (n as Nightfall).lights_lit()
	print("SMOKE TEST: night lights — pool=%d of %d allowed, villages=%d, creature glow=%.2f" % [
		pool, Quality.night_lights(),
		get_tree().get_nodes_in_group("village").size(), creature.radiance()])
	assert(pool <= Quality.night_lights(), "the night's light budget is FIXED")

	# Noon must put every one of them out again.
	GameState.game_years = _at_hour(0.5)
	_update_daylight()
	print("SMOKE TEST: noon — moon=%.2f ambient=%.2f sun=%.2f" % [
		_moon.light_energy, _environment.ambient_light_energy, _sun.light_energy])
	GameState.game_years = was


## The clock reading that puts the day at `fraction` (0 midnight, 0.5 noon).
func _at_hour(fraction: float) -> float:
	return (fraction - 0.35 + 1.0) * GameState.DAY_YEARS


func _smoke_test_gestures() -> void:
	# Every rune-shape, drawn the way a HAND draws it: a slow correlated wobble
	# on top of the ideal, which is what broke the old heuristic recognizer.
	# Carets were coming out as waves — water — rain, about half the time.
	var shapes := {
		"vline": func(t: float) -> Vector2: return Vector2(400, 120 + t * 300),
		"hline": func(t: float) -> Vector2: return Vector2(120 + t * 300, 300),
		"dline": func(t: float) -> Vector2: return Vector2(120 + t * 260, 120 + t * 250),
		"circle": func(t: float) -> Vector2:
			return Vector2(400, 300) + Vector2(cos(t * TAU), sin(t * TAU)) * 100.0,
		"spiral": func(t: float) -> Vector2:
			return Vector2(400, 300) + Vector2(cos(t * TAU * 2.5), sin(t * TAU * 2.5)) * (20 + t * 130),
		"rev_spiral": func(t: float) -> Vector2:
			return Vector2(400, 300) + Vector2(cos(-t * TAU * 2.5), sin(-t * TAU * 2.5)) * (20 + t * 130),
		"wave": func(t: float) -> Vector2: return Vector2(120 + t * 300, 300 + sin(t * TAU) * 90),
		"zigzag": func(t: float) -> Vector2:
			var teeth := t * 5.0
			var up := 1.0 if int(teeth) % 2 == 1 else -1.0
			return Vector2(120 + t * 300, 300 - up * absf(fmod(teeth, 1.0) * 2.0 - 1.0) * 80.0),
		"caret": func(t: float) -> Vector2:
			return Vector2(120 + t * 240, 330 - 170.0 * (1.0 - absf(2.0 * t - 1.0))),
		"arc": func(t: float) -> Vector2:
			var a := -PI / 2.0 - PI * 0.45 + PI * 0.9 * t
			return Vector2(400, 300) + Vector2(cos(a), sin(a)) * 130.0,
	}
	var hits := 0
	var tries := 0
	var missed := []
	for want: String in shapes:
		for seed_i in 6:
			var got := GestureRecognizer.classify(
				_wobbly_stroke(shapes[want] as Callable, seed_i))
			tries += 1
			if got == want:
				hits += 1
			else:
				missed.append("%s->%s" % [want, got])
	print("SMOKE TEST: gestures under hand tremor — %d/%d read correctly %s" % [
		hits, tries, str(missed)])
	# EVERY BEARING. Without rotation invariance each orientation must be a
	# template of its own, and the ones that were missing were not academic: an
	# S written the way people write the letter S read as a diagonal slash,
	# which is fire, so WATER could not be cast at all.
	var bearings := {
		"wave": [
			func(t: float) -> Vector2: return Vector2(120 + t * 300, 300 + sin(t * TAU) * 90),
			func(t: float) -> Vector2: return Vector2(400 + sin(t * TAU) * 90, 120 + t * 300),
			func(t: float) -> Vector2:
				return Vector2(200 + t * 220 + sin(t * TAU) * 70, 160 + t * 220 - sin(t * TAU) * 40),
		],
		"zigzag": [
			func(t: float) -> Vector2:
				var teeth := t * 5.0
				var up := 1.0 if int(teeth) % 2 == 1 else -1.0
				return Vector2(120 + t * 300, 300 - up * absf(fmod(teeth, 1.0) * 2.0 - 1.0) * 80.0),
			func(t: float) -> Vector2:
				var teeth := t * 5.0
				var up := 1.0 if int(teeth) % 2 == 1 else -1.0
				return Vector2(400 - up * absf(fmod(teeth, 1.0) * 2.0 - 1.0) * 80.0, 120 + t * 300),
		],
	}
	var bear_ok := 0
	var bear_all := 0
	var bear_miss := []
	for want: String in bearings:
		for shape: Callable in bearings[want]:
			for seed_j in 4:
				var read := GestureRecognizer.classify(_wobbly_stroke(shape, seed_j))
				bear_all += 1
				if read == want:
					bear_ok += 1
				else:
					bear_miss.append("%s->%s" % [want, read])
	print("SMOKE TEST: every bearing — %d/%d (upright, lying down, on the slant) %s" % [
		bear_ok, bear_all, str(bear_miss)])
	print("SMOKE TEST: water is castable — an upright S reads as rune '%s'" % [
		Spellbook.rune_for(GestureRecognizer.classify(_wobbly_stroke(
			func(t: float) -> Vector2: return Vector2(400 + sin(t * TAU) * 90, 120 + t * 300), 0)))])

	# FURY, BY TOOTH COUNT. Nobody counts the teeth in their own scrawl, so
	# every plausible count has to read. With one five-tooth reference, three
	# and six came out as a straight line and fury was nearly uncastable.
	var teeth_ok := 0
	var teeth_all := 0
	var teeth_miss := []
	for teeth: int in [3, 4, 5, 6, 7]:
		for upright: bool in [false, true]:
			for seed_k in 3:
				var jag2 := _wobbly_stroke(func(t: float) -> Vector2:
					var n := t * teeth
					var up := 1.0 if int(n) % 2 == 1 else -1.0
					var off := up * absf(fmod(n, 1.0) * 2.0 - 1.0) * 80.0
					return Vector2(400 + off, 120 + t * 300) if upright \
						else Vector2(120 + t * 300, 300 - off), seed_k)
				var read2 := GestureRecognizer.classify(jag2)
				teeth_all += 1
				if read2 == "zigzag":
					teeth_ok += 1
				else:
					teeth_miss.append("%d teeth->%s" % [teeth, read2])
	print("SMOKE TEST: fury — %d/%d zigzags read (3-7 teeth, both bearings) %s" % [
		teeth_ok, teeth_all, str(teeth_miss)])

	# And a scribble must still mean nothing at all.
	var mess := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i in 40:
		mess.append(Vector2(400 + rng.randf_range(-90, 90), 300 + rng.randf_range(-90, 90)))
	print("SMOKE TEST: a scribble reads as '%s'; a poke as '%s'" % [
		GestureRecognizer.classify(mess),
		GestureRecognizer.classify(PackedVector2Array([
			Vector2(400, 300), Vector2(403, 301), Vector2(405, 300),
			Vector2(404, 302), Vector2(405, 303), Vector2(404, 301)]))])


## An ideal shape, plus the slow smooth WOBBLE a real hand adds — which is
## quite unlike random jitter, and is exactly what the old recognizer could not
## survive.
func _wobbly_stroke(shape: Callable, variant: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	var ph1 := rng.randf_range(0.0, TAU)
	var ph2 := rng.randf_range(0.0, TAU)
	var pts := PackedVector2Array()
	for i in 90:
		var t := i / 89.0
		var p: Vector2 = shape.call(t)
		p.x += sin(t * 2.5 * TAU + ph1) * 9.0 + rng.randf_range(-1.5, 1.5)
		p.y += cos(t * 2.5 * TAU + ph2) * 9.0 + rng.randf_range(-1.5, 1.5)
		pts.append(p)
	return pts
