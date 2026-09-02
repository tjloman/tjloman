class_name MiracleManager
extends Node3D
## Two-step casting: draw a MENU-OPENING gesture (spiral / reverse-spiral /
## wave) to choose a set, then a SELECTOR gesture to pick a miracle within
## it. The miracle is conjured as an ORB into the divine hand; you throw or
## place it, and it unleashes wherever it lands (see MiracleOrb / Fireball).
##
## Add a miracle: give it a MIRACLES entry, slot its selector into a MENU,
## and add a `resolve()` case. Effects scale with your reach — more
## converted villages and higher belief make storms wider and flocks larger.

## MENU OPENER -> { label, selectors: {gesture -> miracle} }.
## name -> { cost, color }. Cost is gated by your prayer-power cap, which
## grows with every converted village — the mightiest miracles need a wide
## flock behind you.
const MIRACLES := {
	"food": {"cost": 20.0, "color": Color(0.95, 0.7, 0.2)},
	"rain": {"cost": 25.0, "color": Color(0.5, 0.7, 1.0)},
	"heal": {"cost": 15.0, "color": Color(0.4, 1.0, 0.5)},
	"lightning": {"cost": 30.0, "color": Color(1.0, 1.0, 0.7)},
	"fireball": {"cost": 25.0, "color": Color(1.0, 0.5, 0.15)},
	"forest_seed": {"cost": 45.0, "color": Color(0.3, 0.7, 0.3)},
	"forage_thicket": {"cost": 30.0, "color": Color(0.5, 0.75, 0.3)},
	"lightning_storm": {"cost": 90.0, "color": Color(0.8, 0.85, 1.0)},
	"tornado": {"cost": 110.0, "color": Color(0.6, 0.6, 0.65)},
	"bird_flock": {"cost": 40.0, "color": Color(0.85, 0.85, 0.9)},
	"flight": {"cost": 55.0, "color": Color(0.7, 0.9, 1.0)},
	"portal": {"cost": 70.0, "color": Color(0.5, 0.75, 1.0)},
	"strength": {"cost": 35.0, "color": Color(0.9, 0.5, 0.35)},
	# The weather, by degrees. One rune of water is a sprinkle; three is a
	# deluge; water and force together bring the sky down.
	"gust": {"cost": 12.0, "color": Color(0.75, 0.8, 0.85)},
	"thunderclap": {"cost": 15.0, "color": Color(0.9, 0.9, 0.75)},
	"cloudburst": {"cost": 45.0, "color": Color(0.4, 0.6, 0.95)},
	"deluge": {"cost": 80.0, "color": Color(0.3, 0.5, 0.9)},
	"thunderstorm": {"cost": 60.0, "color": Color(0.6, 0.7, 0.95)},
	"tempest": {"cost": 150.0, "color": Color(0.7, 0.75, 1.0)},
	"firestorm": {"cost": 130.0, "color": Color(1.0, 0.45, 0.2)},
	"hurricane": {"cost": 190.0, "color": Color(0.55, 0.65, 0.8)},
}

## How each resolved miracle moves the player's karma, and what the creature
## learns from witnessing it.
const KARMA := {
	"food": {"player": 2.0, "creature": 1.5},
	"rain": {"player": 2.0, "creature": 1.5},
	"heal": {"player": 3.0, "creature": 2.0},
	"forest_seed": {"player": 2.5, "creature": 2.0},
	"forage_thicket": {"player": 2.0, "creature": 1.5},
	"bird_flock": {"player": 1.0, "creature": 1.0},
	"flight": {"player": 1.5, "creature": 2.0},
	"portal": {"player": 1.0, "creature": 1.5},
	"strength": {"player": 1.0, "creature": 2.0},
	"lightning": {"player": -4.0, "creature": -3.0},
	"lightning_storm": {"player": -7.0, "creature": -5.0},
	"tornado": {"player": -8.0, "creature": -6.0},
	"fireball": {"player": -2.5, "creature": -2.0},
	"gust": {"player": 0.0, "creature": 0.5},
	"thunderclap": {"player": -1.0, "creature": -0.5},
	"cloudburst": {"player": 1.5, "creature": 1.5},
	"deluge": {"player": -1.0, "creature": 0.5},
	"thunderstorm": {"player": -5.0, "creature": -3.5},
	"tempest": {"player": -9.0, "creature": -7.0},
	"firestorm": {"player": -9.0, "creature": -7.0},
	"hurricane": {"player": -11.0, "creature": -8.0},
}

## THE UNLOCK LADDER now runs on RUNES, not on finished miracles — see
## Spellbook.RUNE_TIERS. Learning a rudiment opens every combination it takes
## part in at once, so a village teaches you far more than one wonder, and the
## spellbook grows combinatorially instead of a fixed dozen at a time.

const LIGHTNING_KILL_RADIUS := 3.0
const LIGHTNING_BURN_RADIUS := 8.0
const CREATURE_SIGHT_RANGE := 45.0

var divine_hand: DivineHand = null  # wired by main; orbs land in the grip
## What the PLAYER has cast, and how many runes went into the last one. Only
## `cast_runes` touches these, so the creature's own casting never counts —
## the tutorial watches them to know a lesson actually landed.
var casts_made := 0
var last_rune_count := 0


## Your reach: 1.0 alone, rising with converted villages and their belief.
## Scales the extent of the grander miracles.
func _ready() -> void:
	add_to_group("miracles")


func power() -> float:
	var believers := 0
	var belief_sum := 0.0
	for v in get_tree().get_nodes_in_group("village"):
		if (v as Village).converted:
			believers += 1
			belief_sum += (v as Village).belief
	return 1.0 + believers * 0.35 + belief_sum / 300.0


## CAST WHAT WAS DRAWN. The hand hands over the runes; the spellbook says what
## they mean; we check you know every rudiment involved, take the prayer, and
## put the result in your grip.
func cast_runes(runes: Array) -> bool:
	var reading := Spellbook.interpret(runes)
	if reading.is_empty():
		GameState.hint("Those runes mean nothing together.")
		return false
	# RUDIMENTS FIRST. You cannot hold a storm before you hold rain and
	# lightning apart — and the moment you hold both, the storm is yours with
	# nothing further to learn.
	var known := known_runes()
	for rune: String in Spellbook.runes_needed(runes):
		if not known.has(rune):
			GameState.hint("You do not know the rune of %s yet — bring another village to the faith."
				% rune)
			return false
	var cost := _cost_of(reading)
	if cost > GameState.max_prayer_power:
		GameState.hint("%s needs more devoted villages before you can hold it."
			% String(reading.get("label", "that")).capitalize().replace("_", " "))
		return false
	if not GameState.try_spend(cost):
		GameState.hint("Not enough prayer power — your followers must worship more.")
		return false
	casts_made += 1
	last_rune_count = runes.size()
	return _conjure_reading(reading)


## What a drawing costs: the sum of what it is made of, eased a little so that
## combining is always worth doing rather than a tax on ambition.
func _cost_of(reading: Dictionary) -> float:
	if reading.has("miracle"):
		var base: float = MIRACLES.get(reading["miracle"], {}).get("cost", 25.0)
		return base * (1.0 + (float(reading.get("potency", 1.0)) - 1.0) * 0.7)
	var total := 0.0
	for part: Dictionary in reading.get("blend", []):
		total += float(MIRACLES.get(part["miracle"], {}).get("cost", 25.0)) * float(part["potency"])
	return total * Spellbook.COMBO_MULTIPLIER


## The runes your dominion has taught you. Villages teach RUDIMENTS; every
## combination of what you hold follows for free.
func known_runes() -> Array:
	var known := []
	var tiers := mini(maxi(faithful_villages(), 1), Spellbook.RUNE_TIERS.size())
	for i in tiers:
		for rune: String in Spellbook.RUNE_TIERS[i]:
			known.append(rune)
	return known


## How many villages hold your faith (the home village counts once converted).
func faithful_villages() -> int:
	var n := 0
	for v in get_tree().get_nodes_in_group("village"):
		if (v as Village).converted:
			n += 1
	return n


## Every miracle you could actually cast right now — every named recipe whose
## runes you hold, plus the rudiments themselves. This is what the creature
## watches, and what the roster brags about.
func unlocked_miracles() -> Array:
	var known := known_runes()
	var castable := []
	for rune: String in known:
		var base: String = Spellbook.BASE.get(rune, "")
		if base != "" and not castable.has(base):
			castable.append(base)
	for key: String in Spellbook.RECIPES:
		var needed: PackedStringArray = key.split("+")
		var holds := true
		for rune in needed:
			if not known.has(rune):
				holds = false
				break
		if holds and not castable.has(Spellbook.RECIPES[key]):
			castable.append(Spellbook.RECIPES[key])
	return castable


func is_unlocked(miracle: String) -> bool:
	return unlocked_miracles().has(miracle)


## The runes just taught by the newest convert — announced on conversion.
func newly_taught() -> Array:
	var tier := faithful_villages() - 1
	if tier > 0 and tier < Spellbook.RUNE_TIERS.size():
		return Spellbook.RUNE_TIERS[tier]
	return []


## The rudiments the NEXT convert would teach — shown to tempt the player on.
func next_tier_preview() -> Array:
	var tier := faithful_villages()
	if tier < Spellbook.RUNE_TIERS.size():
		return Spellbook.RUNE_TIERS[tier]
	return []


## Put a reading in the hand. A named miracle becomes one orb; a BLEND becomes
## one orb per part, so an invented combination lands as several effects at
## once wherever you throw them.
func _conjure_reading(reading: Dictionary) -> bool:
	if reading.has("miracle"):
		return _make_orb(reading["miracle"], float(reading.get("potency", 1.0)))
	var made := false
	for part: Dictionary in reading.get("blend", []):
		made = _make_orb(part["miracle"], float(part["potency"])) or made
	if made:
		GameState.hint("A working of your own making, conjured — THROW it.")
	return made


## Conjures a named miracle as an orb into the divine hand (or drops it in the
## air if the hand is full). Spends prayer power up front. Used by the creature
## and by tests; the player's own casting goes through `cast_runes`.
func conjure(miracle: String) -> bool:
	if not MIRACLES.has(miracle):
		return false
	if not is_unlocked(miracle):
		GameState.hint("%s is beyond you yet — bring another village to the faith."
			% miracle.capitalize().replace("_", " "))
		return false
	var cost: float = MIRACLES[miracle]["cost"]
	if cost > GameState.max_prayer_power:
		GameState.hint("%s needs more devoted villages before you can hold it." % miracle.capitalize())
		return false
	if not GameState.try_spend(cost):
		GameState.hint("Not enough prayer power — your followers must worship more.")
		return false
	return _make_orb(miracle, 1.0)


## The orb itself. `potency` rides along so that the same miracle can arrive
## as a sprinkle or as a downpour without needing a separate name for each.
func _make_orb(miracle: String, potency: float) -> bool:
	if not MIRACLES.has(miracle):
		return false
	var body: RigidBody3D
	if miracle == "fireball":
		body = Fireball.new()
	else:
		var orb := MiracleOrb.new()
		orb.miracle_name = miracle
		orb.potency = potency
		orb.color = MIRACLES[miracle]["color"]
		orb.manager = self
		body = orb
	add_child(body)
	if divine_hand == null or not divine_hand.force_hold(body):
		body.global_position = global_position + Vector3(0, 4.0, 0)
	GameState.hint("%s conjured — now THROW it where you want it."
		% miracle.capitalize().replace("_", " "))
	return true


## Called by a thrown orb when it lands: unleash the effect at that spot,
## apply karma, and let the villages witness it.
func resolve(miracle: String, pos: Vector3, momentum := Vector3.ZERO,
		scale_up := 1.0) -> void:
	pos.y = 0
	var potency := power() * scale_up
	match miracle:
		"food": _cast_food(pos)
		"rain": _cast_rain(pos, potency)
		"lightning": _cast_lightning(pos)
		"heal": _cast_heal(pos, potency)
		"forest_seed": _cast_forest_seed(pos, potency)
		"forage_thicket": _cast_forage_thicket(pos, potency)
		"lightning_storm": _cast_lightning_storm(pos, potency)
		"tornado": _cast_tornado(pos, potency, momentum)
		"bird_flock": _cast_bird_flock(pos, potency, momentum)
		"flight": _cast_flight(pos, potency)
		"portal": _cast_portal(pos)
		"strength": _cast_strength(pos, potency)
		# The weather, by degrees — all of it built from the pieces above.
		"gust": _cast_gust(pos, potency, momentum)
		"thunderclap": _cast_thunderclap(pos, potency)
		"cloudburst": _cast_rain(pos, potency * 2.2)
		"deluge": _cast_rain(pos, potency * 3.6)
		"thunderstorm": _cast_thunderstorm(pos, potency)
		"tempest": _cast_tempest(pos, potency, momentum)
		"firestorm": _cast_firestorm(pos, potency, momentum)
		"hurricane": _cast_hurricane(pos, potency, momentum)
		_: return
	_apply_karma(miracle, pos)
	for v in get_tree().get_nodes_in_group("village"):
		(v as Village).witness_miracle(miracle, pos)


func _apply_karma(miracle: String, pos: Vector3) -> void:
	if not KARMA.has(miracle):
		return
	GameState.shift_alignment(KARMA[miracle]["player"])
	var creature := get_tree().get_first_node_in_group("creature") as Creature
	if creature != null and creature.global_position.distance_to(pos) < CREATURE_SIGHT_RANGE:
		creature.witness(KARMA[miracle]["creature"])
		# Watching the power work teaches it, a little, how to work it itself.
		creature.mind.witness_miracle(miracle)


func _cast_food(pos: Vector3) -> void:
	for i in 4:
		var food := FoodItem.new()
		food.position = pos + Vector3(randf_range(-1.5, 1.5), 6.0 + i * 1.5, randf_range(-1.5, 1.5))
		add_child(food)


func _cast_rain(pos: Vector3, potency := 1.0) -> void:
	var reach := 14.0 * potency
	var cloud := Node3D.new()
	cloud.position = pos + Vector3(0, 12, 0)

	for i in 5:
		var puff := Util.sphere(
			randf_range(1.5, 2.5), Color(0.55, 0.58, 0.65),
			Vector3(randf_range(-2.5, 2.5), randf_range(-0.5, 0.5), randf_range(-2.5, 2.5)))
		cloud.add_child(puff)

	var drops := CPUParticles3D.new()
	drops.amount = 400
	drops.lifetime = 1.4
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(5, 0.2, 5)
	drops.direction = Vector3.DOWN
	drops.initial_velocity_min = 8.0
	drops.initial_velocity_max = 10.0
	drops.gravity = Vector3(0, -12, 0)
	drops.mesh = _drop_mesh()
	cloud.add_child(drops)
	add_child(cloud)

	var bless := 12.0 * potency
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if farm.global_position.distance_to(pos) < reach:
			farm.water(bless)
	# Rain also quickens the wild larder: trees and berry bushes it falls on.
	for grp in ["trees", "forage"]:
		for n in get_tree().get_nodes_in_group(grp):
			var plant := n as Node3D
			if is_instance_valid(plant) and plant.has_method("rain") \
					and plant.global_position.distance_to(pos) < reach:
				plant.call("rain", bless)

	# Rain is the counter to fire: it douses every blaze it falls on —
	# trees, and burning villagers and beasts alike.
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.burning \
				and tree.global_position.distance_to(pos) < reach:
			tree.extinguish()
	for grp in ["villagers", "animals", "farms"]:
		for n in get_tree().get_nodes_in_group(grp):
			var body := n as Node3D
			if is_instance_valid(body) and body.get("burning") \
					and body.global_position.distance_to(pos) < reach:
				body.call("extinguish")

	get_tree().create_timer(12.0).timeout.connect(cloud.queue_free)


func _drop_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.04
	m.height = 0.12
	m.material = Util.mat(Color(0.5, 0.7, 1.0, 0.8))
	return m


## Lightning is now lethal at the point of impact. An evil god's bread
## and butter; a good god's gravest temptation.
func _cast_lightning(pos: Vector3) -> void:
	var bolt := Util.cylinder(0.3, 30.0, Color(1.0, 1.0, 0.9), pos + Vector3(0, 15, 0), true)
	add_child(bolt)
	var scorch := Util.cylinder(1.6, 0.06, Color(0.12, 0.1, 0.08), pos + Vector3(0, 0.03, 0))
	add_child(scorch)

	var flash := OmniLight3D.new()
	flash.light_energy = 8.0
	flash.omni_range = 25.0
	flash.position = pos + Vector3(0, 5, 0)
	add_child(flash)

	get_tree().create_timer(0.25).timeout.connect(bolt.queue_free)
	get_tree().create_timer(0.25).timeout.connect(flash.queue_free)
	get_tree().create_timer(20.0).timeout.connect(scorch.queue_free)

	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		var dist := villager.global_position.distance_to(pos)
		if dist < LIGHTNING_KILL_RADIUS:
			GameState.shift_alignment(-4.0)  # on top of the cast itself
			villager.take_damage(999.0, true, true)  # a direct bolt is instant
		elif dist < LIGHTNING_BURN_RADIUS:
			villager.take_damage(40.0, true)
			villager.ignite()  # the near-miss sets them ablaze

	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		var adist := animal.global_position.distance_to(pos)
		if adist < LIGHTNING_KILL_RADIUS:
			animal.die()  # drops cooked-ish meat where it stood
		elif adist < LIGHTNING_BURN_RADIUS:
			animal.ignite()

	# A bolt sets the nearest trees — and any field it strikes — alight.
	ignite_trees_near(pos, 5.0)
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(pos) < LIGHTNING_BURN_RADIUS:
			farm.ignite()


## Sets trees within `radius` of a point ablaze. The fire spreads and
## self-limits from there (see WildTree). Shared by lightning and fireballs.
func ignite_trees_near(pos: Vector3, radius: float) -> void:
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(pos) < radius:
			tree.ignite()


func _cast_heal(pos: Vector3, potency := 1.0) -> void:
	var reach := 8.0 * potency
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	var ring := Util.mesh_node(torus, Color(0.4, 1.0, 0.5, 0.8), pos + Vector3(0, 0.3, 0), true)
	add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3(reach, 1, reach), 1.2)
	tween.parallel().tween_property(ring, "transparency", 1.0, 1.2)
	tween.tween_callback(ring.queue_free)

	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if villager.global_position.distance_to(pos) < reach:
			villager.receive_heal()
	for c in get_tree().get_nodes_in_group("creature"):
		var creature := c as Creature
		if creature.global_position.distance_to(pos) < reach:
			creature.receive_heal()


## Nature -------------------------------------------------------------------

## Plants a stand of thirteen saplings that shoot up to ~4 lumber quickly.
func _cast_forest_seed(pos: Vector3, potency := 1.0) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	var biome := "grassland"
	if world != null:
		biome = world.biome_at(pos.x, pos.z)
	var planted := 0
	for i in 13:
		var a := TAU * i / 13.0 + randf() * 0.4
		var r := randf_range(1.5, 5.0 * potency)
		var spot := pos + Vector3(cos(a) * r, 0, sin(a) * r)
		if world != null and world.is_underwater(spot.x, spot.z):
			continue
		var tree := WildTree.new()
		tree.style = biome if biome in ["savanna", "wetland", "grassland"] else "forest"
		tree.rng_seed = randi()
		tree.lumber = 1.0
		tree.set_meta("quicken_to", 4.0)   # WildTree reads this and races to 4
		add_child(tree)
		if world != null:
			spot.y = world.height_at(spot.x, spot.z) - 0.1
		tree.global_position = spot
		planted += 1
	GameState.announce("A grove of %d springs from the earth." % planted)


## Scatters a thicket of berry bushes — wild forage for beast and villager.
func _cast_forage_thicket(pos: Vector3, potency := 1.0) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	var n := int(6 * potency)
	for i in n:
		var a := TAU * i / maxf(n, 1) + randf() * 0.5
		var r := randf_range(1.0, 4.0 * potency)
		var spot := pos + Vector3(cos(a) * r, 0, sin(a) * r)
		if world != null and world.is_underwater(spot.x, spot.z):
			continue
		var bush := ForageBush.new()
		bush.berries = ForageBush.MAX_BERRIES
		add_child(bush)
		if world != null:
			spot.y = world.height_at(spot.x, spot.z)
		bush.global_position = spot


## Wrath --------------------------------------------------------------------

## A rolling storm: several bolts strike across a wide area over a few
## seconds, each lethal at its point of impact. Widens with your reach.
func _cast_lightning_storm(pos: Vector3, potency := 1.0) -> void:
	var reach := 10.0 * potency
	var strikes := int(4 + potency * 3)
	for i in strikes:
		var delay := i * 0.35
		var a := randf() * TAU
		var r := randf_range(0.0, reach)
		var strike_pos := pos + Vector3(cos(a) * r, 0, sin(a) * r)
		get_tree().create_timer(delay).timeout.connect(
			func() -> void: _cast_lightning(strike_pos))
	GameState.announce("A storm of wrath breaks over the land!")


## A tornado: a spinning funnel that wanders, flinging loose things and
## terrifying (and battering) whoever it passes.
func _cast_tornado(pos: Vector3, potency := 1.0, momentum := Vector3.ZERO) -> void:
	var funnel := Node3D.new()
	funnel.position = pos
	add_child(funnel)
	for i in 6:
		var t := i / 6.0
		var ring := Util.cylinder(0.4 + t * 2.6, 1.4, Color(0.55, 0.55, 0.6, 0.6),
			Vector3(0, 0.7 + i * 1.4, 0))
		funnel.add_child(ring)
	var life := 8.0 + potency * 2.0
	# The throw sets it wandering: it drifts the way you flung it, and a harder
	# fling sends it careening faster. A merely placed twister roams at random.
	var heading := Vector3(momentum.x, 0.0, momentum.z)
	if heading.length() < 0.5:
		heading = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var strength := clampf(heading.length() / 12.0, 0.6, 1.8)
	var drift := heading.normalized() * strength
	_run_tornado(funnel, drift, life, 5.0 * potency)


func _run_tornado(funnel: Node3D, drift: Vector3, life: float, radius: float) -> void:
	if life <= 0.0 or not is_instance_valid(funnel):
		if is_instance_valid(funnel):
			funnel.queue_free()
		return
	funnel.rotate_y(0.6)
	funnel.global_position += drift * 4.0 * 0.2
	var here := funnel.global_position
	for grp in ["villagers", "animals"]:
		for n in get_tree().get_nodes_in_group(grp):
			var node := n as Node3D
			if not is_instance_valid(node):
				continue
			if node.global_position.distance_to(here) < radius:
				if node.has_method("scare"):
					node.call("scare", here)
				if node.has_method("take_damage"):
					node.call("take_damage", 6.0)
	get_tree().create_timer(0.2).timeout.connect(
		func() -> void: _run_tornado(funnel, drift, life - 0.2, radius))


## Sky ----------------------------------------------------------------------

## A V of birds sweeps overhead — doves if you are good, ravens if neutral,
## screeching bats if you are wicked. An omen the villages read plainly.
func _cast_bird_flock(pos: Vector3, potency := 1.0, momentum := Vector3.ZERO) -> void:
	var flock := Node3D.new()
	var body_color := Color(0.95, 0.95, 0.95)
	var sound := "coo"
	if GameState.alignment < -30.0:
		body_color = Color(0.15, 0.1, 0.18)
		sound = "screech"
	elif GameState.alignment < 30.0:
		body_color = Color(0.12, 0.12, 0.14)
		sound = "caw"
	# A true wedge: one leader at the apex (front), the rest trailing BACK in
	# two even arms to either side. Built in local space with -Z as "forward";
	# the whole flock is then turned to face its line of flight, so the V
	# always points the way the birds are going (not skewed into a "<").
	var count := int(7 + potency * 4)
	_add_bird(flock, Vector3.ZERO, body_color, 0.0)          # the leader
	var placed := 1
	var k := 1
	while placed < count:
		_add_bird(flock, Vector3(-k * 0.7, 0, k * 0.7), body_color, -18.0)
		placed += 1
		if placed < count:
			_add_bird(flock, Vector3(k * 0.7, 0, k * 0.7), body_color, 18.0)
			placed += 1
		k += 1

	# The flock flies the way you flung it: the throw's heading is the line of
	# flight, sweeping in over the cast point and on past it. A placed (not
	# thrown) omen takes a default diagonal sweep.
	var forward := Vector3(momentum.x, 0.0, momentum.z)
	if forward.length() < 0.5:
		forward = Vector3(1, 0, 0.6)
	forward = forward.normalized()
	var start := pos - forward * 34.0 + Vector3(0, 15, 0)
	var finish := pos + forward * 34.0 + Vector3(0, 17, 0)
	# Basis.looking_at (not look_at) so this is safe before the node is in
	# the tree — a -Z-forward orientation aligned to the flight path.
	flock.transform.basis = Basis.looking_at(forward, Vector3.UP)
	flock.position = start
	add_child(flock)
	SoundBank.play_at(sound, pos + Vector3(0, 10, 0), 2.0)
	var tween := create_tween()
	tween.tween_property(flock, "position", finish, 6.0)
	tween.tween_callback(flock.queue_free)


## One bird in a flock: a wide, thin body (wings) with a slight bank.
func _add_bird(flock: Node3D, local_pos: Vector3, body_color: Color, bank: float) -> void:
	var bird := Util.box(Vector3(0.5, 0.12, 0.2), body_color, local_pos)
	bird.rotation_degrees.z = bank
	flock.add_child(bird)


## The CREATURE casts a miracle it has learned by watching you. Its command is
## imperfect: `skill` (0..1 familiarity) scales the potency, so an apprentice's
## rain is a drizzle. It costs the creature nothing but effort — this is its own
## power, not your prayer — and the villages read it as a wonder all the same.
## WHAT A MIRACLE TAKES OUT OF A BEAST. The prayer a miracle costs YOU is a
## fair measure of how grand it is, so the creature is charged in the same
## coin — out of its own reserves rather than yours. Working a tornado should
## lay it flat; a heal should not.
static func effort_of(miracle: String) -> float:
	return float(MIRACLES.get(miracle, {}).get("cost", 25.0))


func creature_cast(miracle: String, pos: Vector3, skill: float) -> void:
	if not MIRACLES.has(miracle):
		return
	pos.y = 0
	var potency := maxf(power() * clampf(skill, 0.1, 1.0) * 0.6, 0.25)
	match miracle:
		"food": _cast_food(pos)
		"rain": _cast_rain(pos, potency)
		"lightning": _cast_lightning(pos)
		"heal": _cast_heal(pos, potency)
		"forest_seed": _cast_forest_seed(pos, potency)
		"forage_thicket": _cast_forage_thicket(pos, potency)
		"lightning_storm": _cast_lightning_storm(pos, potency)
		"tornado": _cast_tornado(pos, potency)
		"bird_flock": _cast_bird_flock(pos, potency)
		_: return
	for v in get_tree().get_nodes_in_group("village"):
		(v as Village).witness_miracle(miracle, pos)


## Sky, continued -------------------------------------------------------------

## FLIGHT: the creature takes to the air and soars over water, wood and hill
## alike — the only sane way to keep it beside you on a map this wide.
func _cast_flight(pos: Vector3, potency := 1.0) -> void:
	var creature := get_tree().get_first_node_in_group("creature") as Creature
	if creature == null:
		GameState.hint("Your creature is nowhere near enough to be lifted.")
		return
	if creature.global_position.distance_to(pos) > 60.0:
		GameState.hint("Cast it nearer your creature to lift it.")
		return
	creature.grant_flight(35.0 + potency * 25.0)
	var swirl := CPUParticles3D.new()
	swirl.amount = 60
	swirl.lifetime = 1.6
	swirl.one_shot = true
	swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	swirl.emission_sphere_radius = 3.0
	swirl.direction = Vector3.UP
	swirl.initial_velocity_min = 5.0
	swirl.initial_velocity_max = 9.0
	swirl.gravity = Vector3(0, 2.0, 0)
	swirl.position = creature.global_position
	add_child(swirl)
	get_tree().create_timer(4.0).timeout.connect(swirl.queue_free)


## PORTAL: gates are cast in PAIRS. The first stands open and waiting; the next
## links to it, and from then on anything entering one steps out of the other.
## Casting a third begins a fresh pair (the old gates close).
func _cast_portal(pos: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		pos.y = maxf(world.height_at(pos.x, pos.z), WorldGen.WATER_LEVEL)
	var waiting: Portal = null
	var open: Array = []
	for p in get_tree().get_nodes_in_group("portals"):
		var gate := p as Portal
		if not is_instance_valid(gate):
			continue
		open.append(gate)
		if gate.twin == null or not is_instance_valid(gate.twin):
			waiting = gate
	# A finished pair already stands: this cast starts a new one, so retire them.
	if waiting == null and open.size() >= 2:
		for gate: Portal in open:
			gate.queue_free()
	var portal := Portal.new()
	add_child(portal)
	portal.global_position = pos
	if waiting != null and is_instance_valid(waiting):
		portal.link(waiting)
		GameState.announce("The gates are joined! Step through and cross the world.")
	else:
		GameState.announce("A gate hangs open, waiting for its twin. Cast portal again elsewhere.")


## STRENGTH: the creature's thews swell with borrowed might. For a while it has
## a giant's grip — enough to uproot forest trees far beyond its own muscle —
## and moves like a beast in its prime. Real strength is EARNED by work; this
## is only a loan against it.
func _cast_strength(pos: Vector3, potency := 1.0) -> void:
	var creature := get_tree().get_first_node_in_group("creature") as Creature
	if creature == null or creature.global_position.distance_to(pos) > 60.0:
		GameState.hint("Cast it nearer your creature to lend it strength.")
		return
	creature.grant_strength(30.0 + potency * 20.0)
	var flare := CPUParticles3D.new()
	flare.amount = 40
	flare.lifetime = 1.2
	flare.one_shot = true
	flare.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flare.emission_sphere_radius = 2.5
	flare.direction = Vector3.UP
	flare.initial_velocity_min = 3.0
	flare.initial_velocity_max = 6.0
	flare.position = creature.global_position
	add_child(flare)
	get_tree().create_timer(3.0).timeout.connect(flare.queue_free)


## THE WEATHER, BUILT FROM PIECES ------------------------------------------------
##
## Every storm below is made of the same handful of effects the rudiments
## already cast — rain, strikes, wind, fire — stacked and timed. That is the
## point of the whole system: the player composes runes, and the code composes
## the very same parts, so a hurricane is honestly "rain and wind and strikes
## together" rather than a separate bespoke thing that merely looks like one.


## A shove of wind: no harm in it, but everything loose goes tumbling and
## everyone nearby is startled. The gentlest thing air can do.
func _cast_gust(pos: Vector3, potency: float, momentum: Vector3) -> void:
	var push := momentum
	push.y = 0.0
	if push.length() < 1.0:
		push = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	push = push.normalized() * (7.0 + potency * 4.0)
	var radius := 10.0 + potency * 4.0
	SoundBank.play_at("saw", pos, -6.0, 0.4)
	for group in ["pickable", "animals", "villagers"]:
		for n in get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if not is_instance_valid(node) or node.global_position.distance_to(pos) > radius:
				continue
			if node is RigidBody3D:
				(node as RigidBody3D).apply_central_impulse(push + Vector3.UP * 2.0)
			elif node is Animal:
				(node as Animal).scare(pos)
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(pos) < radius:
			tree.sway(pos, 0.8)


## All the noise of the storm and none of its violence: a crack of thunder that
## empties a field. Useful, and it costs you almost nothing but a fright.
func _cast_thunderclap(pos: Vector3, potency: float) -> void:
	SoundBank.play_at("boom", pos, 4.0, 0.5)
	var radius := 16.0 + potency * 6.0
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if is_instance_valid(villager) and villager.global_position.distance_to(pos) < radius:
			villager.scare(pos)
			villager.witness_horror(1.0)
	for a in get_tree().get_nodes_in_group("animals"):
		var beast := a as Animal
		if is_instance_valid(beast) and beast.global_position.distance_to(pos) < radius:
			beast.scare(pos)


## RAIN AND LIGHTNING TOGETHER — the first real storm, and the one the player
## reaches by learning its two halves separately.
func _cast_thunderstorm(pos: Vector3, potency: float) -> void:
	_cast_rain(pos, potency * 1.3)
	_strike_repeatedly(pos, 3, 18.0 + potency * 5.0, 0.55)


## Everything at once, and the sky torn open with it.
func _cast_tempest(pos: Vector3, potency: float, momentum: Vector3) -> void:
	_cast_rain(pos, potency * 2.6)
	_strike_repeatedly(pos, 9, 26.0 + potency * 8.0, 0.32)
	_cast_gust(pos, potency * 1.5, momentum)


## Wind and fire: the wind spreads the burning, which is the whole horror of it.
func _cast_firestorm(pos: Vector3, potency: float, momentum: Vector3) -> void:
	_cast_gust(pos, potency * 1.4, momentum)
	var radius := 14.0 + potency * 6.0
	ignite_trees_near(pos, radius)
	for i in 5:
		var spot := pos + Vector3(randf_range(-radius, radius), 0, randf_range(-radius, radius))
		ignite_trees_near(spot, 7.0)
	SoundBank.play_at("boom", pos, 2.0, 0.7)


## THE WHOLE SKY: a walking funnel, torrential rain, and strikes all round it.
## Nothing here is new — it is the tornado, the deluge and the storm at once,
## which is exactly what the runes said.
func _cast_hurricane(pos: Vector3, potency: float, momentum: Vector3) -> void:
	_cast_rain(pos, potency * 3.0)
	_cast_tornado(pos, potency * 1.4, momentum)
	_strike_repeatedly(pos, 12, 34.0 + potency * 10.0, 0.4)
	GameState.announce("The sky itself comes apart. Nothing in its path will stand.")


## Strikes scattered around a point over time — the shared spine of every storm.
func _strike_repeatedly(pos: Vector3, count: int, radius: float, gap: float) -> void:
	for i in count:
		var spot := pos + Vector3(
			randf_range(-radius, radius), 0, randf_range(-radius, radius))
		get_tree().create_timer(gap * i).timeout.connect(
			_cast_lightning.bind(spot))
