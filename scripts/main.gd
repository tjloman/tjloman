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

	var debug_menu := DebugMenu.new()
	debug_menu.world_gen = world_gen
	debug_menu.creature = creature
	add_child(debug_menu)

	# Whatever a reload was carrying — a whole saved game, or just a creature
	# being moved into a new land — is unpacked now that the world stands.
	SaveGame.apply_pending(world_gen, creature)

	# F2 (or the settings cycle) re-tunes what can change live; the world's
	# stream radius and water rebuild on the next reload.
	Quality.quality_changed.connect(_on_quality_changed)

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
	print("SMOKE TEST: unlocks — villages=%d known=%s next=%s" % [
		miracles.faithful_villages(), str(miracles.unlocked_miracles()),
		str(miracles.next_tier_preview())])
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
	for miracle: String in ["food", "rain", "heal", "lightning", "forest_seed",
			"forage_thicket", "lightning_storm", "tornado", "bird_flock", "flight"]:
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
		if CreatureMind.VERB_VALENCE.get(opt["verb"], 0.0) == 0.0:
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
	var lonely := {"energy": 90.0, "mood": 60.0, "lonely": 1.0}
	print("SMOKE TEST: loneliness wants company — commune %.2f vs smash %.2f" % [
		creature.mind._drive_fit("commune", lonely),
		creature.mind._drive_fit("smash", lonely)])

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
	print("SMOKE TEST: creed -> %s" % str(creature.mind.beliefs.creed(4)))

	# CHARACTER IS PACED BY TIME, not by how many deeds got squeezed into a
	# frame. A tight burst of cruelty must NOT make a monster on its own.
	var burst := CreatureMind.new()
	for i in 400:
		burst.judge(-1.0)
	var spaced := CreatureMind.new()
	spaced.judge(-1.0, CreatureMind.DEED_ALPHA, false)
	print("SMOKE TEST: pacing — 400 instant cruelties = %.1f, one lived deed = %.1f" % [
		burst.temperament, spaced.temperament])

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

	# THE MILITIA: a wolf mauls someone, the village rouses, arms itself, and
	# (in a band) fights back. A lone villager must NOT dare to stand.
	village.store.add_lumber(12)
	village.store.add_stone(9)
	var folk := village.my_villagers()
	if folk.size() >= 2:
		var victim2 := folk[0]
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

	# PERSISTENCE: a mind written down and read back must be the same mind.
	creature.body.fat = 44.0
	creature.mind.q["smash|tree"] = 1.75
	var wrote := SaveGame.save_to_disk(world_gen, creature)
	var parcel := SaveGame.read_from_disk()
	var twin := CreatureMind.new()
	twin.from_dict((parcel.get("creature", {}) as Dictionary).get("mind", {}))
	var body_twin := CreatureBody.new()
	body_twin.from_dict((parcel.get("creature", {}) as Dictionary).get("body", {}))
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
	# A SMOOTH S / sine — no sharp corners at all (the case the old detector
	# missed). Should now read as "wave" via curvature inflections.
	var smooth_s := PackedVector2Array()
	for i in 30:
		var t := i / 29.0
		smooth_s.append(Vector2(120 + t * 300.0, 300 + sin(t * TAU) * 90.0))
	print("SMOKE TEST: gesture circle -> ", GestureRecognizer.classify(circle))
	print("SMOKE TEST: gesture vline  -> ", GestureRecognizer.classify(vline))
	print("SMOKE TEST: gesture hline  -> ", GestureRecognizer.classify(hline))
	print("SMOKE TEST: gesture wave   -> ", GestureRecognizer.classify(zigzag))
	print("SMOKE TEST: gesture wave/S -> ", GestureRecognizer.classify(smooth_s))
	print("SMOKE TEST: gesture dline  -> ", GestureRecognizer.classify(dline))
	print("SMOKE TEST: gesture spiral -> ", GestureRecognizer.classify(spiral))
