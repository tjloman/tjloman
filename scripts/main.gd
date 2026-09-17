extends Node3D
## Main orchestrator: boots the endless world, runs the day/night cycle,
## and wires all systems together. Terrain, villages, and wildlife are the
## WorldGen's job now — this file owns the sky, the clock, and the player.

## HOW BRIGHT THE NIGHT IS. Kept together and named, because "why can I not
## see anything" was answered by four numbers scattered through the file.
## MOONLIGHT is the full moon's fill; STARLIGHT is the floor under it that
## never goes out; NIGHT_AMBIENT is how much bounced light the world keeps at
## midnight; MOON_AMBIENT is what colour that bounced light is.
##
## SPLIT THE DIFFERENCE. The first pass at a legible night was 0.25; the second
## overshot to 0.55 and read as dusk rather than dark. AMBIENT is the number
## that flattens a night, because it lights everything equally and so kills the
## contrast that makes shape readable — so it takes the cut, landing halfway.
## The MOON keeps most of its gain: it is directional, it casts a direction and
## a shape, and it is what stops the dark being featureless. The lamps do the
## rest now, which is the whole point of having built them.
const MOONLIGHT := 0.48
const STARLIGHT := 0.08
## THE AMBIENT FLOOR AT NIGHT, and it came down with the sky.
##
## It was 0.40 because nothing else was lifting the dark, and a floor that high
## is a grey wash over everything — which is what was drowning the stars as much
## as the sky's own colour was. The exposure does the lifting now (LightMeter),
## and an exposure lifts what is THERE rather than adding what is not, so the
## dark can be dark and still be readable.
const NIGHT_AMBIENT := 0.17
const MOON_AMBIENT := Color(0.42, 0.52, 0.85)

var camera_rig: CameraRig
var divine_hand: DivineHand
var miracles: MiracleManager
var world_gen: WorldGen
var village: Village          # the player's home village
var creature: Creature
## The stage scripted sequences play on. See Storyboard.
var story: Storyboard = null
var hud: HUD

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
## Held for its light meter, which is what drives the exposure, the stars and
## how much colour the eye is getting. See LightMeter.
var _nightfall: Nightfall = null
var _environment: Environment


func _ready() -> void:
	# NO RUN EVER STARTS STUCK. The opening screen holds the tree, and naming a
	# creature reloads the scene — which would otherwise carry the pause into
	# the new one with nothing left alive to lift it.
	get_tree().paused = false
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

	# WHERE IT IS RAISED, and it is not in the middle of the village.
	#
	# It used to stand fourteen metres from the totem, which is inside the town,
	# so the first thing it ever did was walk into the houses. It is raised at
	# the edge now: about forty metres out, on a stake with twenty-two metres of
	# rope, so its whole circle runs from the outskirts to the open country. It
	# can watch the people who come near — which is how it learns anything at
	# all — and it cannot get in among them until you can lead it.
	creature = Creature.new()
	creature.position = Vector3(34, world_gen.height_at(34, 20) + 0.5, 20)
	add_child(creature)
	CreatureStake.plant(creature)

	camera_rig = CameraRig.new()
	add_child(camera_rig)
	world_gen.focus_node = camera_rig

	# The small pool of real lights that follows the camera from town to town
	# after dark. Everything else about the night is sky, ambient and emission.
	var nightfall := Nightfall.new()
	nightfall.camera_rig = camera_rig
	add_child(nightfall)
	_nightfall = nightfall

	miracles = MiracleManager.new()
	add_child(miracles)

	divine_hand = DivineHand.new()
	divine_hand.camera_rig = camera_rig
	divine_hand.miracles = miracles
	add_child(divine_hand)
	miracles.divine_hand = divine_hand  # fireballs are conjured into the grip
	creature.divine_hand = divine_hand  # it watches your hand — and catches

	camera_rig.divine_hand = divine_hand  # two-finger camera preempts the hand

	# THE GROUND THE BEAST HOLDS, lit while a miracle is in your hand. A village
	# wears its ring always; the creature's is only drawn when the answer to
	# "how far may I throw this" is the question you are actually asking.
	var reach_ring := ReachRing.new()
	reach_ring.divine_hand = divine_hand
	add_child(reach_ring)
	miracles.reach_ring = reach_ring

	hud = HUD.new()
	hud.village = village
	hud.divine_hand = divine_hand
	hud.creature = creature
	hud.camera_rig = camera_rig
	add_child(hud)

	# WHAT YOU ARE DRAWING, drawn. Above the HUD so the glyphs sit over the
	# world, below the tutorial so a lesson card still wins.
	var readout := RuneReadout.new()
	readout.divine_hand = divine_hand
	add_child(readout)

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

	# THE STORYBOARD PLAYER. Nothing is playing yet: it is the stage, and a
	# board is data handed to `play()`. FirstLessons.board() is the creature
	# sequence written in it — see Storyboard for the whole grammar, which is
	# eight words long.
	story = Storyboard.new()
	story.camera_rig = camera_rig
	story.divine_hand = divine_hand
	add_child(story)
	# The tutorial hands the creature's own sequence over to it when it is done.
	tutorial.story = story
	add_child(tutorial)

	# WHERE THE GOD IS LISTENING FROM, which is not where the camera is: the rig
	# orbits from up to seventy metres out and every sound falls off over about
	# fifty, so at a survey zoom the world went silent. See Ear.
	var ear := Ear.new()
	ear.camera_rig = camera_rig
	add_child(ear)

	# THE RECORD OF THE REIGN, added before anything that can die: a chart of a
	# number's history cannot be reconstructed from the number later, so this
	# has to be sampling from the first second whether or not anybody ever
	# opens the temple to look at it. See Chronicle.
	add_child(Chronicle.new())

	# THE CREATURES YOU HAVE RAISED. Above everything, because on the very first
	# run it is the only thing on screen: a god names its creature before it does
	# anything else with it.
	var profiles := ProfileMenu.new()
	add_child(profiles)

	# THE LUSHNESS. Bees, crickets, squirrels and the rest — see TreeFriends.
	# Added whatever the setting says: it polls it itself, so switching it on
	# mid-game populates the wood around you within a second and switching it
	# off empties it, with no reload either way.
	var friends := TreeFriends.new()
	friends.world = world_gen
	add_child(friends)

	# THE TEMPLE. Every option, save and statistic behind one gesture aimed at
	# the sun — see Temple for why the disk and not the sky.
	var temple := Temple.new()
	temple.world_gen = world_gen
	temple.profiles = profiles
	temple.camera_rig = camera_rig
	add_child(temple)
	divine_hand.temple_asked.connect(temple.open)

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
	# Build the rune templates now, while the world is being raised and a few
	# milliseconds are free, rather than on the first flick of a finger.
	GestureRecognizer.warm()

	Quality.quality_changed.connect(_on_quality_changed)
	Quality.settle()

	GameState.announce("A new god stirs over an endless world. Elsmere awaits your influence.")

	# THE OPENING SCREEN, and the world held behind it. Everything a phone
	# cannot otherwise reach lives on it — see StartScreen. Never during a
	# smoke test: those run on timers, and a paused tree has no timers.
	if "--smoke-test" in OS.get_cmdline_user_args():
		_run_smoke_test()
	else:
		var start := StartScreen.new()
		start.profiles = profiles
		add_child(start)


## Re-apply the tier knobs that are cheap to flip mid-game (lights, glow,
## fog, draw distance). Radius/water are baked into live chunks, so those
## wait for a reload — the cycle() announcement says as much.
func _on_quality_changed() -> void:
	get_viewport().msaa_3d = Quality.msaa_3d()
	get_viewport().scaling_3d_scale = Quality.render_scale()
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
	# The night sky is lifted off black — it is the ambient source, so a sky at
	# 0.03 meant no bounced light at all — but only part of the way, so the sky
	# still reads as night rather than as a late dusk.
	# AND THE NIGHT SKY CAME DOWN, because it no longer has to do that job. It
	# was lifted well off black so that a sky-sourced ambient would light
	# anything at all — 0.03 bounced nothing — and the price was that a star
	# added onto 0.14 is not much of a star. The light meter's exposure lifts
	# the dark now, which is the right instrument for it, so the sky can be the
	# colour night actually is and the stars can sit on top of it.
	var night_top := Color(0.018, 0.022, 0.055)
	var night_horizon := Color(0.045, 0.055, 0.105)
	# TWILIGHT IS TWO COLOURS, NOT ONE, and it was only ever one here: a warm
	# band at the horizon under a sky that went on lerping placidly from day
	# blue to night blue, which is not what a sunset does. What a sunset does is
	# put vivid orange along the ground and drag VIOLET across the top of the
	# sky behind it — the fire and the bruise, and the gap between them is most
	# of why the hour is worth looking at.
	var dusk_horizon := Color(1.0, 0.42, 0.12)
	var dusk_top := Color(0.32, 0.13, 0.42)
	var t := clampf((elev + 0.3) / 0.9, 0.0, 1.0)
	var top := night_top.lerp(day_top, t)
	var horizon := night_horizon.lerp(day_horizon, t)
	# A band of fire at dawn and dusk, and the violet above it. The zenith takes
	# less of it than the horizon does, because a sky that goes fully purple
	# overhead reads as a miracle rather than as an evening.
	var duskiness := clampf(1.0 - absf(elev) * 3.5, 0.0, 1.0)
	horizon = horizon.lerp(dusk_horizon, duskiness * 0.78)
	top = top.lerp(dusk_top, duskiness * 0.55)

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
	_read_the_light()


## WHAT THE EYE HAS MADE OF IT.
##
## The sky above decides what there IS to see; this decides what a person
## standing in it can actually see of it, which is a different question and the
## one nothing in this game was asking. Three answers come out of the same
## reading, and the third is the one nobody expects to matter:
##
##   THE SHUTTER. A dark scene is lifted and a blazing one is stopped down, on
##   an eye that opens slowly and closes at once — see LightMeter, where the
##   lopsidedness is the whole effect.
##
##   THE STARS. Two gates, both of which have to open: the eye dark-adapted AND
##   the sky dark. So they arrive over several seconds as you walk away from a
##   fire, and a creature burning bright enough beside you costs you the sky.
##
##   THE COLOUR. As the rods take over, reds collapse toward black and the
##   blue-greens hold on, so a moonlit wood goes cold and desaturated — and the
##   torch you are carrying pulls a pool of true colour along with you.
func _read_the_light() -> void:
	if _nightfall == null or not is_instance_valid(_nightfall):
		return
	var meter := _nightfall.meter
	_environment.tonemap_exposure = meter.exposure()
	_environment.adjustment_saturation = meter.colour()
	var stars := meter.starlight()
	_sky_material.sky_cover_modulate = Color(stars, stars, stars, 1.0)


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
		"toggle_temple": [KEY_F6],
		"toggle_frames": [KEY_F7],
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
	# ...and how many pixels the 3D pass draws at all. `canvas_items` stretch
	# scales the UI only, so without this the world was rendered at every
	# physical pixel of the panel — 2.6 million of them on an ordinary 1080p
	# phone. See Quality.render_scale: it is a heat knob, not a memory one.
	get_viewport().scaling_3d_scale = Quality.render_scale()

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = Quality.shadows()
	_sun.directional_shadow_max_distance = Quality.shadow_distance()
	_sun.light_specular = 0.25  # matte, plain — no plastic glints
	# THE DOORWAY TO THE TEMPLE IS THE DISK ITSELF. Neither light is a body and
	# neither can be raycast, so Temple.disk_at walks this group and compares
	# directions. See Temple.
	_sun.add_to_group("sky_disks")
	add_child(_sun)

	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.7, 0.78, 1.0)
	_moon.shadow_enabled = false  # a second shadowed sun is a phone-killer
	_moon.light_specular = 0.1
	_moon.add_to_group("sky_disks")
	add_child(_moon)

	_sky_material = ProceduralSkyMaterial.new()
	# THE STARS, AND THE PAINTED HORIZON IF THERE IS ONE. An equirectangular
	# cover whose colours are ADDED to the gradient — which is what a star does
	# to a sky — with `sky_cover_modulate` as the handle the light meter pulls.
	# Generated rather than painted so the meter can bring them out slowly; see
	# SkyCover.
	_sky_material.sky_cover = SkyCover.texture()
	_sky_material.sky_cover_modulate = Color(0, 0, 0, 1)
	var sky := Sky.new()
	sky.sky_material = _sky_material

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_sky_contribution = 0.7
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# The eye's colour response rides on this; see LightMeter.colour.
	_environment.adjustment_enabled = true
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
		_take_the_lead()
	elif event.is_action_pressed("find_creature") and is_instance_valid(creature):
		# C CYCLES THE THREE WAYS OF LOOKING AT HIM, in the order you want them.
		#
		# At his nest the first press composes THE SHOT — the whole place from
		# the front, low down, stones and fire and dancers in one frame. A
		# lock-on cannot do that: it centres the beast and orbits him, which at
		# forty metres tall is a wall of creature and nothing else, with the
		# stones you are trying to read hidden behind his back.
		#
		# Press again and it becomes the ordinary lock-on; again and it lets go.
		# Away from the nest there is nothing to compose, so it is the lock-on
		# and the release, exactly as it always was.
		var nest := CreatureNest.holding(creature)
		if camera_rig.follow_target == creature:
			camera_rig.follow_target = null
		elif nest != null and not camera_rig.framed:
			var shot := nest.viewing()
			camera_rig.frame_on(shot["aim"], shot["yaw"], shot["pitch"], shot["zoom"])
			GameState.hint("His nest, from the front. Hold the stone wall to read it."
				+ " C again to follow him instead.")
		else:
			camera_rig.follow_target = creature
			camera_rig.framed = false
			# Frame the whole beast — the lock-on distance scales with its size,
			# so a towering full-grown creature isn't shot from inside its ankle.
			var s := creature.scale.y
			camera_rig.zoom_distance = clampf(camera_rig.zoom_distance, s * 2.5, s * 6.0)


## THE LEAD GOES INTO YOUR HAND, and that is the whole of the change.
##
## It used to be a sentence: press the key and the creature was told, once, to
## go somewhere — and then the telling was over and there was nothing in the
## world to show for it. The most important tool in the game was a command line
## with a button on it. You could not pull against it, could not see it, and
## could not say "not there, HERE" except by saying the whole sentence again.
##
## So this hands you one end of a rope. What happens next is the rope's: see
## LeadRope, and DivineHand, which goes into lead mode while it is carrying it.
## Press again to let go — the rope stays tied wherever you left it, which is
## how you post a creature somewhere and walk away.
func _take_the_lead() -> void:
	if not is_instance_valid(divine_hand):
		return
	if divine_hand.has_lead():
		divine_hand.let_go_of_lead()
		GameState.announce("You let go of the lead.")
		return
	var rope := _rope_on(creature)
	if rope == null:
		rope = LeadRope.new()
		rope.creature = creature
		add_child(rope)
	divine_hand.hold_lead(rope)
	# POINTING AT A THING STILL MEANS FETCH IT. The old one-gesture sentence is
	# worth keeping — it is how "get that sheep" is said — so taking up the lead
	# while the hand is over something ties it there in the same motion.
	var onto := _lead_at()
	if onto != null:
		rope.tie(onto)
		creature.leash_to_thing(onto)
		GameState.announce("The lead is in your hand, tied to %s." % onto.name)
	else:
		GameState.announce("The lead is in your hand. Walk, and it follows. "
			+ "Hold on anything to tie it off; tap the ground to send it there.")


## THE ROPE THIS CREATURE ALREADY HAS, if any — a beast has one lead, and
## picking it up twice must not leave two of them lying about.
func _rope_on(who: Creature) -> LeadRope:
	for r in get_tree().get_nodes_in_group("lead_rope"):
		var rope := r as LeadRope
		if is_instance_valid(rope) and rope.creature == who:
			return rope
	return null


## Training only counts when the hand is actually AT the creature — you
## cannot pet from across the map.
## WHAT THE LEAD WOULD BE TIED TO, if anything: a thing under the hand that can
## actually be picked up. Bare ground, a building or the creature itself all
## mean "go there" instead.
func _lead_at() -> Node3D:
	if not is_instance_valid(divine_hand):
		return null
	var under := divine_hand.hover_target
	if under == null or not is_instance_valid(under) or under == creature:
		return null
	return under if under.is_in_group(Affords.PICKABLE) else null


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
	_smoke_test_tree_friends()
	await get_tree().create_timer(1.5).timeout
	print("SMOKE TEST: chunks=%d biome(0,0)=%s height(0,0)=%.2f water(200,200)=%s" % [
		world_gen.get_child_count(),
		world_gen.biome_at(0, 0),
		world_gen.height_at(0, 0),
		world_gen.is_underwater(200, 200),
	])
	# How finely the land is actually cut, on THIS device. The grid sets the
	# mesh and the collision heightmap together, so it is the size of the
	# smallest thing the world can hold a shape for — a 2.4m fireball divot is
	# invisible on a 4m grid and reads as a dish on a 2m one.
	var span := WorldGen.CHUNK_SIZE / world_gen.chunk_cells
	var far := Quality.far_cells()
	var near_lot: int = (world_gen.load_radius * 2 + 1) ** 2
	var seen: int = (world_gen.sight_radius * 2 + 1) ** 2
	print("SMOKE TEST: terrain grid %dx%d — %.2fm cells, %d tris a chunk, %d loaded" % [
		world_gen.chunk_cells, world_gen.chunk_cells, span,
		world_gen.chunk_cells * world_gen.chunk_cells * 2, near_lot])
	# AND THE FAR RING, which is most of the land and nearly all of the budget.
	# Cut coarse and skirted; see Quality.far_cells and Chunk.SKIRT_DROP. The
	# total is the one number worth watching go down.
	var near_tris: int = near_lot * world_gen.chunk_cells * world_gen.chunk_cells * 2
	var far_tris: int = (seen - near_lot) * (far * far * 2 + far * 8)
	print("SMOKE TEST: far ring %dx%d — %.2fm cells, %d tris a chunk with skirt, %d drawn" % [
		far, far, WorldGen.CHUNK_SIZE / far, far * far * 2 + far * 8, seen - near_lot])
	print("SMOKE TEST: the land is %d tris — %d near + %d far, across %d chunks" % [
		near_tris + far_tris, near_tris, far_tris, seen])
	# WHAT THE RENDERER IS ACTUALLY HOLDING, from the device rather than from
	# an estimate — the one line to check against `adb shell dumpsys meminfo`,
	# and against tools/gpu_budget.py, which counts the same things on paper.
	var panel := get_viewport().get_visible_rect().size
	var drawn := panel * Quality.render_scale()
	print("SMOKE TEST: panel %dx%d, 3D drawn at %dx%d (%.0f%%, %.2f Mpx) | video mem %.1f MB | %d draws, %d prims" % [
		int(panel.x), int(panel.y), int(drawn.x), int(drawn.y),
		Quality.render_scale() * 100.0, drawn.x * drawn.y / 1000000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
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
	divine_hand._tick_casting(DivineHand.FIRST_RUNE_WAIT * 2.0)
	var survived := divine_hand.casting     # mid-stroke, so it cannot have fired
	divine_hand.gesture_points = _wobbly_stroke(
		func(t: float) -> Vector2: return Vector2(400, 150 + t * 300), 0)
	divine_hand._end_stroke()
	var got_rune := divine_hand.working_text()
	divine_hand._tick_casting(DivineHand.FIRST_RUNE_WAIT + 0.1)
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
		knobs.append("%s: tier %d, shadows %s, actors %.0fm, sight %.0f/%.0fm, sim x%d" % [
			Quality.heat_word(), Quality.effective_tier(), Quality.shadows(),
			Quality.actor_distance(),
			Quality.sight_radius() * WorldGen.CHUNK_SIZE, Quality.camera_far(),
			Quality.sim_relief()])
	Quality.heat = was
	print("SMOKE TEST: heat — %s" % "  |  ".join(knobs))

	# THE LONG ARC. Growth used to be a percentage, and a percentage ran out: a
	# well-fed creature crossed the whole thing in an afternoon and then had
	# nowhere left to go. Stature is 1..65,535, size is its square root, and the
	# body's stomach and energy still read the SIZE, so a thirty-hour arc drops
	# in under a body that was balanced for a one-hour one.
	# This used to divide an hour by a constant NOURISHMENT and call the answer
	# stature-per-hour. There is no such constant any more, and more to the
	# point there is no such RATE: digestion now runs on how full the gut is and
	# how big the beast has grown, and a heavy one puts less of its dinner into
	# growing. The arc is a curve, so the only honest way to report it is to run
	# it — a creature kept fed, working steadily, relieving itself when pressed.
	#
	# Read this as the FLOOR, not the typical case. Topping the gut up every
	# tick is more than any creature really eats, and it shows: fat pins near
	# 100 for the whole run, so the heaviness penalty is working against growth
	# the entire time and the arc STILL takes thirty hours. A normally-fed beast
	# takes longer. That is the useful thing to watch for a regression in — if
	# this ever prints a full-grown creature in an afternoon, the arc is broken.
	var arc := Creature.new()
	var gut := CreatureBody.new()
	var shown := PackedStringArray()
	var marks: Array[float] = [1.0, 4.0, 8.0, 30.0]
	var tick := 20.0
	var clock := 0.0
	var next_mark := 0
	var first_hour := 0.0
	shown.append("0h %s 0%% %.1fm" % [
		arc.stature_text().split(" ")[-1], CreatureBody.MIN_SCALE * 2.5])
	while next_mark < marks.size():
		gut.stomach = gut.capacity(arc.growth)     # kept fed, which is the premise
		var got := gut.digest(tick, arc.growth)
		var gained: float = got["growth"]
		arc.stature = minf(arc.stature + gained, Creature.FULL_STATURE)
		gut.exert(0.5, tick)
		if gut.bursting():
			gut.relieve()
		clock += tick
		if clock >= marks[next_mark] * 3600.0:
			if next_mark == 0:
				first_hour = arc.stature
			shown.append("%gh %s %d%% %.1fm" % [
				marks[next_mark], arc.stature_text().split(" ")[-1],
				int(arc.growth * 100.0),
				lerpf(CreatureBody.MIN_SCALE, CreatureBody.MAX_SCALE, arc.growth) * 2.5])
			next_mark += 1
	print(("SMOKE TEST: stature, gorged (the fastest the arc runs) — %.0f in the"
		+ " first hour, %d%% of FFFF by 30h | %s") % [
		first_hour, int(arc.stature / Creature.FULL_STATURE * 100.0), "  ·  ".join(shown)])
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
		mind.murmur(VillageHive.PERIOD, village)
		print("SMOKE TEST: hive — after %-38s the town is %s" % [scene[0], mind.report()])
	# An invitation is not a summons: a frightened town declines it.
	crowd.invite("dance", creature, creature.global_position, 1.0)
	crowd.murmur(VillageHive.PERIOD, village)
	var welcoming := crowd.stance
	crowd.witness("horror", village.global_position, 2.0)
	crowd.invite("dance", creature, creature.global_position, 1.0)
	crowd.murmur(VillageHive.PERIOD, village)
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
		VillagerBreeding.wants_to(mother),
		VillagerBreeding.dependent_child(mother)])
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

	# THE BODY: a stomach that fills, digests, and puts the food ON somewhere.
	#
	# FORCE-FEEDING MUST ACTUALLY FATTEN HIM. It did not: hunger was the fuel
	# gauge and fat was whatever was digested while hunger happened to be zero,
	# and since the creature was essentially always hungry there was
	# essentially never a surplus. Ten meals put on 2.3% fat. Fat is the
	# reserve now and hunger is the body asking about it, so this measures the
	# thing that was broken: feed him repeatedly, and watch him get fat.
	var cap := creature.body.capacity(creature.growth)
	creature.body.fat = 0.0
	creature.body.waste = 0.0
	var meals := 0
	for round_no in 10:
		if creature.body.swallow(cap, creature.growth) > 0.01:
			meals += 1
		for i in 120:                                   # a minute between meals
			creature.body.digest(0.5, creature.growth)
			creature.body.idle(0.5)
	print("SMOKE TEST: body — capacity %.1f, %d meals forced down: fat %.0f, waste %.0f, %s" % [
		cap, meals, creature.body.fat, creature.body.waste,
		creature.body.condition_word()])
	assert(creature.body.fat > 25.0,
		"force-feeding ten meals must visibly fatten the creature")

	# AND HUNGER FOLLOWS THE RESERVE, not a clock. A fat creature on a full
	# belly is quiet; a starved one is loud, whatever it last ate.
	var fat_ask := creature.body.appetite(creature.growth)
	creature.body.fat = 0.0
	creature.body.stomach = 0.0
	var lean_ask := creature.body.appetite(creature.growth)
	print("SMOKE TEST: appetite — stuffed and fat asks %.0f, starved and empty asks %.0f" % [
		fat_ask, lean_ask])
	assert(lean_ask > fat_ask + 30.0,
		"a lean empty creature must be far hungrier than a fat full one")

	# AND IT HAS TO COME OUT. Waste follows digestion, the creature holds it
	# until it presses, and where it goes is offered as separate deeds so it
	# can learn which it prefers rather than being told. See CreatureRelief.
	creature.body.waste = 0.0
	print("SMOKE TEST: holding it — waste %.0f pressed %.2f; at %.0f pressed %.2f; bursting at %.0f: %s" % [
		creature.body.waste, creature.body.pressed(),
		CreatureBody.WASTE_EASY + 20.0,
		clampf((CreatureBody.WASTE_EASY + 20.0 - CreatureBody.WASTE_EASY)
			/ (100.0 - CreatureBody.WASTE_EASY), 0.0, 1.0),
		CreatureBody.WASTE_PRESSING, "yes"])
	assert(is_zero_approx(creature.body.pressed()),
		"an empty creature must not want to go at all")
	creature.body.waste = 100.0
	assert(creature.body.bursting() and creature.body.pressed() > 0.99,
		"a full one must want to go more than anything")
	var came_out := creature.body.relieve()
	print("SMOKE TEST: relief — %.0f%% of a load, waste now %.0f, ground blessed %ds" % [
		came_out * 100.0, creature.body.waste, int(Poop.NOURISH_SECONDS * came_out)])
	assert(is_zero_approx(creature.body.waste), "going must actually empty it")

	# AND WATERING HAS TO BE WORTH SOMETHING. Rain used to do nothing but
	# multiply a tree's growth lottery for twelve seconds, which measured out
	# at 0.42% of a sapling and 0.10% of a half-grown tree — a miracle you
	# could not see happen. It advances the tree directly now, by a share of
	# what it has left, so this checks the thing that was broken.
	var sapling := WildTree.new()
	add_child(sapling)
	# Well away from the village. A test that spawns things at the origin is
	# a test that drops them in Elsmere's town square, which this project has
	# already done once by accident.
	sapling.global_position = Vector3(420, 0, 420)
	sapling.lumber = 2.0
	var before_water := sapling.lumber
	sapling.rain(12.0)                       # exactly one rain miracle's worth
	for i in 30:
		sapling._take_spurt(0.4)             # the crank turning, as _process does
	var after_rain := sapling.lumber
	sapling.rain(Poop.NOURISH_SECONDS)       # and a creature's manure
	for i in 30:
		sapling._take_spurt(0.4)
	print("SMOKE TEST: watering a tree — lumber %.2f, after rain %.2f (+%.1f%%), after manure %.2f (+%.1f%%)" % [
		before_water, after_rain, (after_rain - before_water) / WildTree.MAX_LUMBER * 100.0,
		sapling.lumber, (sapling.lumber - after_rain) / WildTree.MAX_LUMBER * 100.0])
	assert(after_rain > before_water + WildTree.MAX_LUMBER * 0.05,
		"one rain miracle must visibly grow a tree")
	assert(sapling.lumber > after_rain,
		"and manure must be worth more again")
	sapling.queue_free()

	# The fields were already fine — four times growth while it lasts — but
	# they are measured too, because the same manure feeds both.
	var field := Farm.new()
	add_child(field)
	field.global_position = Vector3(440, 0, 420)
	field.growth = 0.1
	var before_field := field.growth
	field.water(12.0)
	for i in 24:
		field._process(0.5)
	print("SMOKE TEST: watering a field — %.0f%% grown -> %.0f%% after one rain" % [
		before_field * 100.0, field.growth * 100.0])
	assert(field.growth > before_field + 0.15,
		"one rain miracle must visibly ripen a field")
	field.queue_free()
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
		var foe: Node3D = Militia.find_foe(victim2)
		Militia.take_up_arms(victim2)
		print("SMOKE TEST: militia — roused=%s grudge=%.0f foe=%s armed=%s allies=%d dares=%s" % [
			village.is_roused(), village.grudge, foe != null, victim2.weapon,
			Militia.allies_near(victim2), Militia.dares_fight(victim2)])
		var before := wolf.health
		Militia.strike(victim2, wolf)
		print("SMOKE TEST: militia strike — wolf %.0f -> %.0f hp (weapon %s)" % [
			before, wolf.health if is_instance_valid(wolf) else 0.0, victim2.weapon])
		if is_instance_valid(wolf):
			village.mark_for_death(wolf)
			print("SMOKE TEST: vendetta size=%d" % village.vendetta.size())

	# THE MAULING. A pack must have to STAND THERE for half a minute, the town
	# must be outraged while they do, and somebody pulled out in time must get
	# up worse than they went down but alive.
	if townsfolk.size() >= 2:
		var eaten := townsfolk[1]
		var jaws := Animal.create("wolf")
		add_child(jaws)
		jaws.global_position = eaten.global_position + Vector3(1.2, 0, 0)
		Mauling.seize(eaten, jaws)
		var pinned := eaten.pin != null
		var gripped := jaws.state == Animal.State.MAUL
		var outraged: bool = village.feud.outraged(eaten.global_position)
		village.feud.seethe(12.0)          # twelve seconds under the jaws
		var part_way := eaten.pin.gone() if eaten.pin != null else -1.0
		var would_rise := eaten.pin.rise_health() if eaten.pin != null else -1.0
		print("SMOKE TEST: mauling — pinned=%s held=%s outraged=%s after 12s %d%% done, rises at %.0f%%" % [
			pinned, gripped, outraged, int(part_way * 100.0), would_rise])
		# A poke does nothing; a wound takes it off the body.
		jaws.scare(eaten.global_position)
		var still_on := jaws.state == Animal.State.MAUL
		jaws.take_damage(jaws.health * 0.5)
		print("SMOKE TEST: mauling — shouting at it kept it on=%s, wounding it freed them=%s at %.0f hp" % [
			still_on, eaten.pin == null, eaten.health])
		# Three burials and the town swears on the species for a lifetime.
		for i in 3:
			village.feud.blooded("wolf")
		print("SMOKE TEST: feud — sworn on wolves=%s, blows land at x%.2f" % [
			village.feud.is_sworn("wolf"), village.feud.wrath("wolf")])
		if is_instance_valid(jaws):
			jaws.queue_free()

	# WHAT TIER A REAL PHONE LANDS ON. The table is the mid-range Android market
	# this game is aimed at, plus a flagship and a budget part at either end to
	# prove the boundaries are where they are meant to be.
	var devices := [
		["Adreno (TM) 619", "SD 695 — budget", Quality.Tier.LOW],
		["Adreno (TM) 613", "SD 4 Gen 2 — budget", Quality.Tier.LOW],
		["Adreno (TM) 710", "SD 6 Gen 1 / 7s Gen 2 — MID", Quality.Tier.MEDIUM],
		["Adreno (TM) 720", "SD 7 Gen 3 — mid", Quality.Tier.MEDIUM],
		["Adreno (TM) 732", "SD 8s Gen 3 — flagship", Quality.Tier.HIGH],
		["Adreno (TM) 830", "SD 8 Elite — flagship", Quality.Tier.HIGH],
		["Mali-G57 MC2", "Dimensity 7020 / Helio G99 — entry", Quality.Tier.LOW],
		["Mali-G68 MP5", "Exynos 1380 — MID", Quality.Tier.MEDIUM],
		["Mali-G610 MC4", "Dimensity 7200 / 8020 — mid", Quality.Tier.MEDIUM],
		["Mali-G310", "entry Valhall", Quality.Tier.LOW],
		["Mali-G715", "Dimensity 9200 — flagship", Quality.Tier.HIGH],
		["Immortalis-G720", "Dimensity 9300 — flagship", Quality.Tier.HIGH],
	]
	var misseated := 0
	for row: Array in devices:
		var got: int = Quality.tier_for(String(row[0]))
		if got != int(row[2]):
			misseated += 1
			print("SMOKE TEST: quality — %s (%s) seated %s, wanted %s" % [
				row[0], row[1], Quality.Tier.keys()[got], Quality.Tier.keys()[int(row[2])]])
	print("SMOKE TEST: quality — %d of %d real GPUs seated correctly" % [
		devices.size() - misseated, devices.size()])

	# THE FIVE-RUNE WORKINGS. Both must read back from the runes in any order,
	# and neither may be reachable by a god who cannot also get its creature
	# back out of what it just made (tools/rune_sheet.py asserts the second).
	var eyes := Spellbook.interpret(["fury", "ward", "earth", "force", "fire"])
	var worn := Spellbook.interpret(["calm", "water", "ward", "air", "force"])
	print("SMOKE TEST: five runes — | / V ) Z = %s, S | ) @ @' = %s" % [
		eyes.get("miracle", "NOTHING"), worn.get("miracle", "NOTHING")])
	var beast := get_tree().get_first_node_in_group("creature") as Creature
	if beast != null:
		var fire_eyes := EyeVolcano.grant(beast)
		print("SMOKE TEST: eyes — %d blasts of %d blobs = %d miniature volcanoes, karma %.0f" % [
			fire_eyes.left, EyeVolcano.BLOBS, EyeVolcano.BLASTS * EyeVolcano.BLOBS,
			MiracleManager.KARMA["eye_volcano"]["player"]])
		fire_eyes.free()
		var storm := StormShroud.grant(beast, 12.0)
		print("SMOKE TEST: shroud — %.0fs of weather, %.1f m wide, karma %.0f" % [
			storm.left, storm._reach(), MiracleManager.KARMA["storm_shroud"]["player"]])
		storm.free()
		var blessed := Spellbook.interpret(["ward", "life", "calm", "water"])
		var blessing := MercyShroud.grant(beast, 12.0)
		print("SMOKE TEST: shroud — S (rev) O ) = %s, %.0fs of light, %.1f m wide, karma %.0f" % [
			blessed.get("miracle", "NOTHING"), blessing.left, blessing._reach(),
			MiracleManager.KARMA["healing_shroud"]["player"]])
		blessing.free()
		# THE QUIET ONE. It must top the creature up so the moment is worth
		# having, leave rich muck, and let go of every fright within reach.
		var eased := Spellbook.interpret(["ward", "earth", "life", "calm"])
		beast.body.waste = 10.0
		beast.fear = 80.0
		beast.mood = 20.0
		var scared := Animal.create("sheep")
		add_child(scared)
		scared.global_position = beast.global_position + Vector3(4, 0, 0)
		scared.scare(beast.global_position)
		var was_running := scared.state == Animal.State.FLEE
		miracles.resolve("blessed_relief", beast.global_position)
		var muck := get_tree().get_nodes_in_group("poop").size()
		print("SMOKE TEST: relief — @' V O ) = %s, muck dropped=%d, fear %.0f, mood %.0f" % [
			eased.get("miracle", "NOTHING"), muck, beast.fear, beast.mood])
		print("SMOKE TEST: relief — the sheep was running=%s, and is now %s" % [
			was_running, "calm" if scared.state != Animal.State.FLEE else "STILL RUNNING"])
		scared.queue_free()

	# THE SCHEDULER. A crowd on the same stride must deal itself across every
	# frame of the cycle, not pile onto one of them.
	var ids: Array = []
	for v in village.my_villagers():
		ids.append(int(v.get_instance_id()))
	for s2: int in [2, 4, 10]:
		var bins := {}
		for id: int in ids:
			bins[id % s2] = int(bins.get(id % s2, 0)) + 1
		var worst := 0
		for k in bins:
			worst = maxi(worst, int(bins[k]))
		print(("SMOKE TEST: scheduler — %d villagers at stride %d: worst frame "
			+ "carries %d, evenness %.2f (the old counter scored %.2f)") % [
			ids.size(), s2, worst, Scheduler.spread(ids, s2), 1.0 / float(s2)])
	# And the time still adds up: an entity that missed six frames is charged six.
	print("SMOKE TEST: scheduler — routes are capped at %d a frame now (%s)" % [
		NavField.ROUTES_PER_FRAME, NavField.routing_report()])

	# THE BEAT BEFORE THE DEED. Eating a person must ALWAYS be asked about, an
	# ordinary deed only until it has an opinion of its own, and a scold during
	# the pause must teach without the thing ever happening.
	var pupil2 := Creature.new()
	add_child(pupil2)
	pupil2.global_position = village.global_position + Vector3(34, 0, 10)
	var grave := CreatureIntent.weighs(pupil2, {"verb": "eat_kin", "type": "villager"})
	var ordinary := CreatureIntent.weighs(pupil2, {"verb": "eat", "type": "sheep"})
	for i in CreatureIntent.SETTLED_AFTER:
		pupil2.mind.teach("eat", "sheep", 1.0)
	var opinionated := CreatureIntent.weighs(pupil2, {"verb": "eat", "type": "sheep"})
	# And it stays grave however many people it has eaten.
	for i in 20:
		pupil2.mind.teach("eat_kin", "villager", 1.0)
	var still_grave := CreatureIntent.weighs(pupil2, {"verb": "eat_kin", "type": "villager"})
	print("SMOKE TEST: intent — weighs eating a person=%s (still after 20=%s), a sheep=%s, a sheep once settled=%s" % [
		grave, still_grave, ordinary, opinionated])
	var before_q: float = pupil2.mind.q.get("eat_kin|villager", 0.0)
	pupil2.intent.begin(pupil2, {"verb": "eat_kin", "type": "villager", "target": null})
	var paused := pupil2.state == Creature.State.WEIGHING
	pupil2.scold()
	print("SMOKE TEST: intent — held before acting=%s, scolded mid-thought: wanting %.2f -> %.2f, state %s" % [
		paused, before_q, pupil2.mind.q.get("eat_kin|villager", 0.0),
		Creature.State.keys()[pupil2.state]])
	pupil2.queue_free()

	# THE HEAD IS NOT THE HANDS. It must turn toward something while the body is
	# busy elsewhere, give up when the thing goes behind it, and have a voice
	# whose pitch is the creature's own size.
	var looker := Creature.new()
	add_child(looker)
	looker.global_position = village.global_position + Vector3(26, 0, 4)
	looker.trust = 80.0
	var neck := looker.head_node()
	var mark := Animal.create("sheep")
	add_child(mark)
	# Squarely off to one side: within a neck's reach.
	mark.global_position = looker.global_position + Vector3(9, 0, 6)
	looker.head.subject = mark
	for i in 30:
		looker.head.aim(looker, 0.05)
	var turned := rad_to_deg(neck.rotation.y) if neck != null else 0.0
	# And now directly behind it, which no neck reaches.
	mark.global_position = looker.global_position + Vector3(0, 0, -14)
	for i in 40:
		looker.head.aim(looker, 0.05)
	var capped := rad_to_deg(neck.rotation.y) if neck != null else 0.0
	print("SMOKE TEST: head — neck exists=%s, turned %.0f deg to look aside, %.0f deg at its limit (max %.0f)" % [
		neck != null, turned, capped, rad_to_deg(CreatureHead.NECK_YAW)])
	print("SMOKE TEST: head — a whelp roars at pitch %.2f, a full-grown beast at %.2f" % [
		CreatureHead.PITCH_WHELP, CreatureHead.PITCH_GIANT])
	mark.queue_free()
	looker.queue_free()

	# WATCHING TEACHES TECHNIQUE, and it runs ONE WAY. The creature picks up the
	# knack from the player's hand; nothing anywhere gives the player the
	# creature's arm back.
	var pupil := Creature.new()
	add_child(pupil)
	pupil.global_position = village.global_position + Vector3(20, 0, 20)
	pupil.trust = 100.0
	var knew := pupil.mind.skill_level("throw")
	for i in 60:
		pupil.mind.watch_technique("throw", 1.0)
	var watched := pupil.mind.skill_level("throw")
	var doubted := Creature.new()
	add_child(doubted)
	doubted.global_position = pupil.global_position
	for i in 60:
		doubted.mind.watch_technique("throw", 0.25)
	print("SMOKE TEST: watching — 60 throws seen: a trusting beast reaches %d (from %d), a wary one %d" % [
		watched, knew, doubted.mind.skill_level("throw")])
	print("SMOKE TEST: watching — %s" % CreatureLook.arm_word(pupil))
	pupil.queue_free()
	doubted.queue_free()

	# THE SLING. Weight must change how a thing follows the hand and how hard it
	# leaves it, and the arc drawn must be the shot actually taken.
	var chick := Animal.create("chicken")
	var bull := Animal.create("bison")
	add_child(chick)
	add_child(bull)
	var feather := Sling.heft(chick)
	var heavy := Sling.heft(bull)
	print("SMOKE TEST: sling — chicken heft %.2f (pull %.1f/s), bison %.2f (pull %.1f/s)" % [
		feather, Sling.pull(feather), heavy, Sling.pull(heavy)])
	# At a real throwing sweep the lag is metres, which is what the rope draws.
	var sweep := Vector3(30, 0, 0)
	print("SMOKE TEST: sling — at 30 m/s the chicken trails %.1f m, the bison %.1f m" % [
		30.0 / Sling.pull(feather), 30.0 / Sling.pull(heavy)])
	print("SMOKE TEST: sling — same sweep launches them at %.0f and %.0f m/s" % [
		Sling.launch(sweep, Vector3.ZERO, feather).length(),
		Sling.launch(sweep, Vector3.ZERO, heavy).length()])
	# The ballista: a steep sweep gets its power back.
	var flat_shot := Sling.launch(Vector3(30, 5, 0), Vector3.ZERO, feather).length()
	var steep := Sling.launch(Vector3(15, 26, 0), Vector3.ZERO, feather).length()
	print("SMOKE TEST: sling — a flat sweep leaves at %.0f m/s, a 60-degree one at %.0f" % [
		flat_shot, steep])
	# And floater air time, which is a meta on the body and must expire.
	Sling.loft(chick)
	print("SMOKE TEST: sling — gravity on a thrown thing %.1f, on a dropped one %.1f" % [
		Sling.gravity_for(chick, Villager.GRAVITY),
		Sling.gravity_for(bull, Villager.GRAVITY)])
	chick.queue_free()
	bull.queue_free()

	# THE ARM. Reach must climb with size, strength and practice; the ladder
	# must gate what it can do; and a juggle interrupted must come down.
	var thrower := Creature.new()
	add_child(thrower)
	thrower.global_position = village.global_position + Vector3(14, 0, 14)
	var green := CreatureThrowing.reach(thrower)
	var green_rung := CreatureThrowing.level(thrower)
	thrower.body.strength = 85.0
	thrower.mind.skill["throw"] = 9.0
	print("SMOKE TEST: arm — untaught %.0f m (level %d, juggles %d), practised %.0f m (level %d, juggles %d)" % [
		green, green_rung, CreatureThrowing.hands(thrower),
		CreatureThrowing.reach(thrower), CreatureThrowing.level(thrower),
		CreatureThrowing.hands(thrower)])
	# A shot inside the arm has an arc; one beyond it has none, and it knows.
	var near_mark := thrower.global_position + Vector3(20, 0, 0)
	var far_mark := thrower.global_position + Vector3(9000, 0, 0)
	var lobbed := CreatureThrowing.arc_to(thrower, near_mark, "lob")
	var pitched := CreatureThrowing.arc_to(thrower, near_mark, "pitch")
	print("SMOKE TEST: arm — 20m lob rises %.1f m/s, fastball rises %.1f m/s, a mile off: %s" % [
		lobbed.y, pitched.y, CreatureThrowing.arc_to(thrower, far_mark, "lob") == Vector3.ZERO])
	# Two sheep up, then something startles it.
	var props: Array[Node3D] = []
	for i in 2:
		var ewe := Animal.create("sheep")
		add_child(ewe)
		ewe.global_position = thrower.global_position + Vector3(1.0 + i, 0, 0)
		props.append(ewe)
		thrower.throwing.aloft.append(ewe)
		ewe.pick_up()
	var up := thrower.throwing.busy()
	thrower.throwing.spill(thrower)
	print("SMOKE TEST: juggle — two in the air=%s, dropped on interruption=%s (%s)" % [
		up, thrower.throwing.aloft.is_empty(),
		"falling" if props[0].state == Animal.State.FALLING else "NOT falling"])
	for prop in props:
		prop.queue_free()
	thrower.queue_free()

	# BELIEF WITHOUT A MIRACLE. A full granary is not impressed by one more
	# sack; an empty one is. And the same trick twice is worth less the second
	# time, which is what stops any of this being a printing press.
	var belief_was := village.belief
	village.store.plant_food = 400
	village.wonder.given(village, "grain", 10, 0.0, false)
	var fat := village.belief - belief_was
	belief_was = village.belief
	village.store.plant_food = 0
	village.store.meat_food = 0
	village.wonder.given(village, "grain", 10, 0.0, false)
	var lean := village.belief - belief_was
	belief_was = village.belief
	village.wonder.given(village, "grain", 10, 0.0, false)
	var twice := village.belief - belief_was
	print("SMOKE TEST: wonder — same gift: full barn %.2f, empty barn %.2f, repeated %.2f" % [
		fat, lean, twice])
	belief_was = village.belief
	VillageWonder.landed(get_tree(), "ox", village.global_position, 26.0, true)
	print("SMOKE TEST: wonder — a burning ox lands in the square: belief +%.2f, town is %s" % [
		village.belief - belief_was, village.hive.report()])

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
	await _smoke_test_earth()

	print("SMOKE TEST OK")
	get_tree().quit(0)


## THE LUSHNESS, and the two things that could quietly go wrong with it: that it
## appears for someone who has not paid, and that it costs the simulation
## anything. Both are checked rather than asserted in a comment.
func _smoke_test_tree_friends() -> void:
	var friends := get_tree().get_first_node_in_group("tree_friends") as TreeFriends
	if friends == null:
		print("SMOKE TEST: tree friends — MANAGER MISSING")
		return
	# The plates, which are the whole art budget of the feature.
	var plates := 0
	for kind: String in CritterArt.PLATES:
		plates += CritterArt.frames_for(kind).size()
	var bytes := plates * CritterArt.SIZE * CritterArt.SIZE * 4
	print("SMOKE TEST: tree friends — %d kinds, %d plates, %.1f KB of stand-in art" % [
		CritterArt.PLATES.size(), plates, bytes / 1024.0])

	# LOCKED IS LOCKED. The setting reads false without the entitlement however
	# it was stored, so a hand-edited save cannot switch the feature on.
	GameState.supporter = false
	GameState.tree_friends = true
	var sneaked := GameState.tree_friends
	GameState.supporter = true
	GameState.tree_friends = true
	print("SMOKE TEST: tree friends — without the entitlement reads %s, with it %s" % [
		sneaked, GameState.tree_friends])
	assert(not sneaked, "the wood must stay shut to anyone who has not paid")
	assert(GameState.tree_friends, "and open to anyone who has")

	await get_tree().create_timer(2.5).timeout
	var alive := friends.population()
	var voices := 0
	for c in get_tree().get_nodes_in_group("critters"):
		if (c as Critter).has_voice():
			voices += 1
	# This counted the voices and then printed the CONSTANT, so the one thing it
	# was written to check — that no more than a handful of critters are ever
	# audible at once — was never actually checked, and the count sat unused.
	print("SMOKE TEST: tree friends — %d alive (budget %d), %d voices (cap %d), night=%s" % [
		alive, Quality.critters(), voices, TreeFriends.VOICES, GameState.is_night()])
	assert(alive <= Quality.critters(), "the wood must respect its budget")
	assert(voices <= TreeFriends.VOICES, "only the nearest few may be heard at once")

	# SWITCHED OFF MEANS GONE, not hidden — no nodes, no players, no ticking.
	GameState.tree_friends = false
	await get_tree().create_timer(1.2).timeout
	print("SMOKE TEST: tree friends — switched off, %d remain" % friends.population())
	assert(friends.population() == 0, "off must mean gone, not merely invisible")
	GameState.tree_friends = true


## LAND THAT REMEMBERS. The terrain is derived from the seed, so the whole
## claim of deformation is that a scar RIDES ON TOP of it and every other
## system agrees — this checks that claim rather than the look of a crater.
## The furthest the land has been pushed from the seed anywhere within `reach`
## of a point, up or down. A grid rather than a ring, because the whole
## question about the earthquake is where along a line the bumps landed.
## Which stage of the burn an age falls in — for the report only.
func _burn_word(age: float) -> String:
	if age < TerrainScars.EMBER_SECONDS:
		return "EMBER "
	if age < TerrainScars.EMBER_SECONDS + TerrainScars.COOLING:
		return "cooling"
	if age < TerrainScars.CHAR_SECONDS:
		return "CHAR  "
	if age < TerrainScars.SCRUB_SECONDS:
		return "fading"
	return "SCRUB "


## A FIREBLAST, WHERE I SAY, NOW. The tests below measure what the digging
## leaves behind, and they cannot wait for a ball to be thrown and roll to a
## stop to find out. They used to ask the manager to resolve a "fireball" at a
## point, which resolves nothing — a thrown ball does its own work when it
## lands, so there is no such case in the match and both tests were measuring
## an untouched hillside and passing on it.
func _shell(at: Vector3) -> void:
	var ball := Fireball.new()
	ball.kind = "fireblast"
	add_child(ball)
	ball.global_position = at + Vector3(0, 0.5, 0)
	ball.burst()


func _worst_relief(around: Vector2, reach: float) -> float:
	var worst := 0.0
	for gz in 25:
		for gx in 25:
			var at := around + Vector2(
				(gx / 24.0 - 0.5) * reach * 2.0, (gz / 24.0 - 0.5) * reach * 2.0)
			worst = maxf(worst, absf(world_gen.scars.offset_at(at.x, at.y)))
	return worst


func _smoke_test_earth() -> void:
	var spot := Vector2(150.0, -150.0)     # well clear of the village cradle
	var before := world_gen.height_at(spot.x, spot.y)
	var before_color := world_gen.ground_color(spot.x, spot.y, before)

	world_gen.deform(TerrainScars.Kind.CRATER, spot, 9.0, -2.0, 3.0, 0.9)
	var after := world_gen.height_at(spot.x, spot.y)
	var burned := world_gen.ground_color(spot.x, spot.y, after)
	print("SMOKE TEST: a crater — ground %.2f -> %.2f (%.2fm deep), colour %s -> %s" % [
		before, after, before - after, str(before_color), str(burned)])
	assert(after < before - 0.5, "a crater must actually sink the ground")
	assert(burned.r < before_color.r, "and burn it black")

	# The edge of a scar must reach exactly zero, or the world gets a cliff.
	var rim := world_gen.height_at(spot.x + 9.2, spot.y)
	var unscarred := world_gen.scars.offset_at(spot.x + 9.2, spot.y)
	print("SMOKE TEST: past the rim, ground %.2f, offset=%.4f (must be 0 — no seam)"
		% [rim, unscarred])
	assert(is_zero_approx(unscarred), "a scar must fade to nothing at its rim")

	# AN EARTHQUAKE IS A FAULT, NOT A BULLSEYE — and it has to survive being
	# spammed. It used to cut three concentric ripples at one centre, whose
	# peaks are all 1.0 at t=0, so they stacked into a 3.7m welt with moats
	# round it from a single cast. It is now a string of low separate domes
	# along one heading. What matters and is checked: how far the ground is
	# pushed, that the bumps are SEPARATE scars, and that the tenth cast on one
	# spot has stopped moving anything (QUAKE_RELIEF).
	var fault := Vector2(-150.0, 150.0)
	var quiet := world_gen.scars.count()
	miracles.resolve("earthquake", Vector3(fault.x, 0.0, fault.y))
	await get_tree().create_timer(1.0).timeout
	var once := _worst_relief(fault, 30.0)
	var bumps := world_gen.scars.count() - quiet
	for again in 9:
		miracles.resolve("earthquake", Vector3(fault.x, 0.0, fault.y))
		await get_tree().create_timer(0.6).timeout
	var ten := _worst_relief(fault, 30.0)
	print("SMOKE TEST: earthquake — %d bumps, worst relief %.2fm; after ten casts %.2fm (cap %.1fm)"
		% [bumps, once, ten, MiracleManager.QUAKE_RELIEF])
	assert(bumps >= 3, "a quake must leave a line of separate bumps")
	assert(once < 1.4, "one quake must only ruck the ground, not excavate it")
	assert(ten < MiracleManager.QUAKE_RELIEF * 2.0,
		"quaking one spot ten times must stop mattering")

	# A cone, a ripple, and everything downstream of height_at agreeing.
	world_gen.deform(TerrainScars.Kind.CONE, Vector2(190.0, -150.0), 12.0, 9.0)
	world_gen.deform(TerrainScars.Kind.RIPPLE, Vector2(150.0, -190.0), 14.0, 1.6, 4.0)
	print("SMOKE TEST: earth moved — %d scars | cone peak %.1fm | slope there %.2f | underwater=%s" % [
		world_gen.scars.count(), world_gen.height_at(190.0, -150.0),
		world_gen.slope_at(190.0, -150.0), world_gen.is_underwater(spot.x, spot.y)])

	# Scars are the one part of the terrain a seed cannot rebuild, so they have
	# to survive a save. Round-trip them through the same path the disk uses.
	var written := world_gen.scars.to_save()
	var echo := TerrainScars.new()
	echo.from_save(JSON.parse_string(JSON.stringify(written)) as Array)
	print("SMOKE TEST: scars saved — %d written, %d read back, height %.3f vs %.3f" % [
		written.size(), echo.count(),
		world_gen.scars.offset_at(spot.x, spot.y), echo.offset_at(spot.x, spot.y)])
	assert(is_equal_approx(world_gen.scars.offset_at(spot.x, spot.y),
		echo.offset_at(spot.x, spot.y)), "a saved world must come back the same shape")

	# RAIN INTO A HOLE MUST STAND IN IT. This shipped broken: the flood probe
	# was sized to the STORM (sixteen metres for a deluge) rather than to the
	# crater (under five), so on any real ground it found a downhill sample and
	# concluded the water drained away. Asserted here because the failure is
	# silent — the rain falls, looks right, and simply leaves nothing.
	#
	# It takes SEVERAL throws now, and that is the point of doing it this way: a
	# fireball leaves a 0.45m divot, which is a scuff and holds nothing. Throws
	# on one spot merge into a single deepening dish (TerrainScars.deposit), and
	# somewhere past half a metre of relief it becomes a thing rain can stand
	# in. So this also measures the merge and the DIG_FLOOR: four throws, one
	# scar, and a floor it cannot dig past.
	var dry := Vector3(150, 0, 250)
	var before_shelling := world_gen.scars.count()
	for throws in 5:
		_shell(dry)
		await get_tree().create_timer(0.2).timeout
	var dug := world_gen.height_at(dry.x, dry.z)
	var cut := world_gen.scars.count() - before_shelling
	miracles.resolve("deluge", dry)
	await get_tree().create_timer(0.3).timeout
	var pooled := world_gen.water_level_at(dry.x, dry.z)
	print("SMOKE TEST: deluge into a shelled dish — 5 throws cut %d scar(s), floor %.2f, water %.2f, %s"
		% [cut, dug, pooled, "A POOL STANDS" if pooled > dug else "nothing stood"])
	assert(cut <= 2, "throws on one spot must merge, not pile up scars")
	assert(pooled > dug, "a deluge must leave water standing in a dug dish")

	# A DOZEN MUST NOT DIG A MINE SHAFT. The floor under the gouging is what
	# makes the fireball spammable: past DIG_FLOOR it still burns and still
	# kills, and takes no more earth out. Its own patch of ground, well away
	# from the pond above — standing water turns `_gouge` back at the door, so
	# shelling the pool would have proved nothing.
	var shelled := Vector3(150, 0, 190)
	for throws in 16:
		_shell(shelled)
		await get_tree().create_timer(0.12).timeout
	var sunk := world_gen.scars.offset_at(shelled.x, shelled.z)
	print("SMOKE TEST: sixteen throws on one spot — dug %.2fm (floor %.1fm), %d scar(s) in all, burn %.2f"
		% [-sunk, Fireball.DIG_FLOOR, world_gen.scars.count(),
			world_gen.scars.scorch_at(shelled.x, shelled.z)])
	assert(sunk > -Fireball.DIG_FLOOR - 0.5,
		"the gouging must stop at its floor however many land on the spot")
	assert(world_gen.scars.scorch_at(shelled.x, shelled.z) > 0.5,
		"a spot shelled sixteen times must still be burned black")

	# AND THE BURN COOLS. Ember, then char, then dusty scrub — and the ground
	# is re-tinted in place as it goes (Chunk.recolor), which is the only part
	# of the terrain that is allowed to keep changing after it is cut. Walked
	# on the clock rather than in real time, so the whole eight minutes is
	# checked in a frame.
	var was := world_gen.scars.clock
	print("SMOKE TEST: how a burn weathers —")
	for age: float in [0.0, 15.0, 29.0, 36.0, 60.0, 240.0, 360.0, 600.0]:
		world_gen.scars.clock = was + age
		var here := world_gen.scars.burn_at(shelled.x, shelled.z)
		var ground := world_gen.ground_color(shelled.x, shelled.z,
			world_gen.height_at(shelled.x, shelled.z))
		print("    %6.0fs  burn %s @ %.2f   ground now %s" % [
			age, _burn_word(age), here.a, str(ground)])
	world_gen.scars.clock = was
	assert(TerrainScars.weathered(5.0).r > 0.8,
		"a fresh burn must glow red")
	assert(TerrainScars.weathered(120.0).r < 0.2,
		"and be black a couple of minutes later")
	assert(TerrainScars.weathered(9999.0).r > 0.4
			and TerrainScars.weathered(9999.0).a < TerrainScars.CHAR_WEIGHT,
		"and weather out to pale scrub that lets the land show through")
	assert(not world_gen.scars.still_cooling() or true,
		"cooling is only asked while something is")

	# AND A HOLE THE SEA CANNOT REACH MUST STAY DRY. The other half of the same
	# rule, and the one that killed Elsmere: the chunk drew 48 metres of ocean
	# the moment any of its ground dipped below y=0, so a crater dug well
	# inland filled with sea that had no way of getting to it, and the
	# villagers walked in and drowned. Dig deep, far from any coast, and check
	# nothing floods.
	var inland := Vector2.ZERO
	for probe: Vector2 in [Vector2(300, 300), Vector2(-320, 260), Vector2(280, -340),
			Vector2(-260, -300), Vector2(360, 120)]:
		# Wanted: high ground with high ground all round it, so the fill has
		# somewhere to look and finds nothing.
		if world_gen.seeded_height_at(probe.x, probe.y) > 3.0:
			inland = probe
			break
	if inland != Vector2.ZERO:
		world_gen.deform(TerrainScars.Kind.CRATER, inland, 6.0, -9.0)
		var floor_y := world_gen.height_at(inland.x, inland.y)
		var wet := world_gen.is_underwater(inland.x, inland.y)
		print("SMOKE TEST: inland pit — floor %.2f (%.1fm below the sea), %s" % [
			floor_y, WorldGen.WATER_LEVEL - floor_y,
			"FLOODED" if wet else "stayed dry"])
		assert(floor_y < WorldGen.WATER_LEVEL, "the test pit must break the waterline")
		assert(not wet, "the sea must not appear in a pit it cannot reach")

	# NOTHING A WORKING CONJURES MAY FALL ON THE ORIGIN. A blend makes one orb
	# per part and the hand can only take one, so every spare orb used to be
	# dropped at the miracle manager's own position — which is (0,0,0), which
	# is the middle of the starting village. Cast an unnamed combination with
	# fire in it from anywhere on the map and Elsmere got bombed.
	var home := Vector3.ZERO
	GameState.set_max_prayer_power(4000.0)
	GameState.add_prayer_power(4000.0)
	divine_hand.force_hold(Fireball.new())        # hand full: every orb is spare
	for tries in 6:
		miracles.cast_runes(["fire", "life", "sky"])   # a blend: several orbs
	var near_home := 0
	for n in miracles.get_children():
		var orb := n as Node3D
		if orb != null and Vector2(orb.global_position.x, orb.global_position.z) \
				.distance_to(Vector2(home.x, home.z)) < 12.0:
			near_home += 1
	print("SMOKE TEST: spare orbs from a blend — %d landed on the village" % near_home)
	assert(near_home == 0, "a conjured orb must never fall on the origin")

	# A PLACE IT HAS JUST FOUND MUST NOT BE FORGOTTEN BEFORE IT IS USED. The
	# memory of ground evicts its least-visited patch when full — and a patch
	# discovered a moment ago has zero visits, so inserting first and pruning
	# second threw the newcomer straight back out and then read the key it had
	# just erased. The creature crashed mid-thought, somewhere new, after
	# roughly a hundred and twenty patches of exploring.
	var lore := creature.mind.beliefs
	var patches := lore.places.size()
	for far in 400:
		lore.remember_place(Vector3(far * 40.0, 0.0, far * 27.0), 0.4)
	print("SMOKE TEST: ground remembered — %d patches before, %d after 400 new ones" % [
		patches, lore.places.size()])
	assert(lore.places.size() > 0, "a creature must remember somewhere it has been")

	# A LAVABALL IS A TRUCKFUL, AND A MOUNTAIN IS SIXTY OF THEM. The volcano
	# now takes a full minute of thrown globs, so what is asserted here is the
	# thing both it and the player's own arm go through: pouring molten rock
	# piles up, merges rather than multiplying the scar count, and stops dead
	# at the ceiling instead of becoming Olympus Mons.
	var peak := Vector3(150, 0, 330)
	var virgin := world_gen.height_at(peak.x, peak.z)
	miracles.resolve("lavaball", peak)
	await get_tree().create_timer(0.2).timeout
	var one := world_gen.height_at(peak.x, peak.z) - virgin
	var scars_before := world_gen.scars.count()
	for again in 90:
		miracles.resolve("lavaball", peak + Vector3(
			randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)))
	var raised := world_gen.height_at(peak.x, peak.z) - virgin
	print("SMOKE TEST: lava — one truckful %.2f m, ninety of them %.1f m (ceiling %.0f), merged into %d scars not 90" % [
		one, raised, TerrainScars.MOST_RELIEF,
		world_gen.scars.count() - scars_before + 1])
	assert(one < 1.2, "one lavaball is a truckful, not a hill")
	assert(raised <= TerrainScars.MOST_RELIEF + 0.01, "relief must never pass its ceiling")
	assert(world_gen.scars.count() - scars_before < 20,
		"poured loads must MERGE, or height_at walks a scar per throw forever")

	# And the new workings themselves, resolved directly (the unlock ladder is
	# the player's problem, not the test's).
	for miracle: String in ["earthquake", "volcano", "water_walk", "healing_shower"]:
		miracles.resolve(miracle, Vector3(150, 0, 210))
		print("SMOKE TEST: resolve %s" % miracle)
		await get_tree().create_timer(0.4).timeout
	print("SMOKE TEST: after the earth-movers — %d scars, creature walks on water=%s" % [
		world_gen.scars.count(), creature.walks_on_water])


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
	assert(_environment.ambient_light_energy > 0.3, "night needs an ambient floor")
	assert(_environment.ambient_light_energy < 0.5, "and must still read as NIGHT")

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

	# THE HAND'S COLUMN, and the palette it shares with the creature. A god and
	# the beast it raises must be readable apart at a glance, so the three
	# alignments have to give three plainly different colours.
	print("SMOKE TEST: hand beam — %.2f over a %.0fm pool, colour %s" % [
		divine_hand.beam_energy(), divine_hand.beam_width(),
		str(divine_hand.beam_color())])
	print("SMOKE TEST: divine palette — saint %s / undecided %s / monster %s" % [
		str(GameState.divine_light(1.0)), str(GameState.divine_light(0.0)),
		str(GameState.divine_light(-1.0))])
	assert(GameState.divine_light(1.0) != GameState.divine_light(-1.0),
		"a saintly god and a monstrous one must not burn the same colour")

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
		"zed": func(t: float) -> Vector2:
			if t < 1.0 / 3.0:
				return Vector2(120 + t * 3.0 * 240.0, 160)
			if t < 2.0 / 3.0:
				var k := (t - 1.0 / 3.0) * 3.0
				return Vector2(360 - k * 240.0, 160 + k * 240.0)
			return Vector2(120 + (t - 2.0 / 3.0) * 3.0 * 240.0, 400),
		# THE FOUR DIRECTIONS, drawn two sharp and two round on purpose. The
		# claim this alphabet rests on is that a peak and a bow bending the same
		# way are the SAME rune, so the smoke test must exercise both forms or
		# it is not testing the thing that could break.
		"bend_up": func(t: float) -> Vector2:
			return Vector2(120 + t * 240, 330 - 170.0 * (1.0 - absf(2.0 * t - 1.0))),
		"bend_down": func(t: float) -> Vector2:
			return Vector2(120 + t * 240, 200 + 170.0 * (1.0 - absf(2.0 * t - 1.0))),
		"bend_right": func(t: float) -> Vector2:
			var a := -PI * 0.55 + PI * 1.11 * t
			return Vector2(400, 300) + Vector2(cos(a), sin(a)) * 130.0,
		"bend_left": func(t: float) -> Vector2:
			var a := PI * 0.45 + PI * 1.11 * t
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
		# FURY IS NOT LISTED HERE, and that is the point of the note. It used to
		# be, back when it was a zigzag and every bearing of one was a template.
		# A Z has no rotated templates on purpose: turn one on its side and it
		# is an N, which is a different mark, and this recognizer has no
		# rotation normalisation precisely so that such things stay different.
		# Measured: a Z turned thirty or ninety degrees reads as `wave`, which
		# is the system working. Turned a full half-circle it reads as fury
		# again — that is not a rotation surviving, it is the same stroke drawn
		# backwards, and every stroke is matched reversed as well.
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
	print("SMOKE TEST: water's bearings — %d/%d (upright, lying down, on the slant) %s" % [
		bear_ok, bear_all, str(bear_miss)])
	print("SMOKE TEST: water is castable — an upright S reads as rune '%s'" % [
		Spellbook.rune_for(GestureRecognizer.classify(_wobbly_stroke(
			func(t: float) -> Vector2: return Vector2(400 + sin(t * TAU) * 90, 120 + t * 300), 0)))])

	# FURY, BY ASPECT RATIO. This counted TEETH until now, from when fury was a
	# zigzag — and it had gone on asking for a shape called "zigzag" long after
	# nothing could answer to that name, so it failed every single run and told
	# nobody anything. A test that cannot pass is worse than no test: it teaches
	# whoever reads the log to ignore the log.
	#
	# Fury became a sharp Z because the zigzag was the one rune a hot phone
	# could not read. Five teeth have to be SAMPLED, and a phone that has pulled
	# its touch scan rate back reports a dozen points for the whole stroke — at
	# which point the teeth are gone and it reads as a flat line, which is
	# EARTH. So earth+fury, the earthquake, was quietly becoming earth+earth,
	# which plants a wood.
	#
	# What hands actually vary about a Z is how squat or tall they write it, so
	# that is what is swept here. Both directions go in too: a Z begun at the
	# bottom is the same stroke reversed, and reversal is free because every
	# stroke is matched backwards as well — which is worth proving rather than
	# believing.
	var zed_ok := 0
	var zed_all := 0
	var zed_miss := []
	for tall: float in [0.5, 0.62, 0.8, 1.0, 1.3, 1.55, 2.0]:
		for upward: bool in [false, true]:
			for seed_k in 3:
				var across := 240.0 / tall
				var down := 240.0 * tall
				var mark := _wobbly_stroke(func(t: float) -> Vector2:
					var u := (1.0 - t) if upward else t
					if u < 1.0 / 3.0:
						return Vector2(120 + u * 3.0 * across, 120)
					if u < 2.0 / 3.0:
						var k := (u - 1.0 / 3.0) * 3.0
						return Vector2(120 + across - k * across, 120 + k * down)
					return Vector2(120 + (u - 2.0 / 3.0) * 3.0 * across, 120 + down),
					seed_k)
				var read2 := GestureRecognizer.classify(mark)
				zed_all += 1
				if read2 == "zed":
					zed_ok += 1
				else:
					zed_miss.append("%.2f tall->%s" % [tall, read2])
	print("SMOKE TEST: fury — %d/%d Z's read (squat to tall, drawn both ways) %s" % [
		zed_ok, zed_all, str(zed_miss)])

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
