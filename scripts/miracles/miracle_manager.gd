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
	# THE EARTH-MOVERS and two mercies. DELIBERATELY CHEAP FOR NOW — these are
	# new and want playing with, and an earthquake at two hundred prayer would
	# be cast twice and never understood. They will be priced properly once it
	# is clear what they are actually worth.
	"earthquake": {"cost": 30.0, "color": Color(0.62, 0.5, 0.36)},
	"lavaball": {"cost": 38.0, "color": Color(1.0, 0.42, 0.1)},
	"volcano": {"cost": 45.0, "color": Color(0.95, 0.35, 0.12)},
	"water_walk": {"cost": 20.0, "color": Color(0.55, 0.85, 0.95)},
	"healing_shower": {"cost": 25.0, "color": Color(0.55, 1.0, 0.7)},
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
	# Shaking the ground under people terrifies them even when nobody is hurt;
	# opening a volcano under them is among the worst things a god can do.
	"earthquake": {"player": -4.0, "creature": -3.0},
	# It burns like a fireball, but it BUILDS — a god who fills in his own
	# craters is doing something less purely destructive than one who digs them.
	"lavaball": {"player": -1.5, "creature": -1.0},
	"volcano": {"player": -10.0, "creature": -7.5},
	"water_walk": {"player": 1.5, "creature": 2.5},
	"healing_shower": {"player": 4.5, "creature": 3.5},
}

## THE UNLOCK LADDER now runs on RUNES, not on finished miracles — see
## Spellbook.RUNE_TIERS. Learning a rudiment opens every combination it takes
## part in at once, so a village teaches you far more than one wonder, and the
## spellbook grows combinatorially instead of a fixed dozen at a time.

const LIGHTNING_KILL_RADIUS := 3.0
const LIGHTNING_BURN_RADIUS := 8.0
const CREATURE_SIGHT_RANGE := 45.0

## HOW MUCH RAIN IS ALLOWED IN THE SKY AT ONCE.
##
## A cloud lives twelve seconds, and the storms are built by stacking casts —
## a hurricane is rain and wind and strikes together — so without a ceiling a
## few seconds of enthusiasm puts half a dozen showers over the same field and
## multiplies the whole cost by six. Three is plenty to look like weather.
const RAIN_DROPS := 400
const RAIN_CLOUDS := 3

## How wide a probe a NATURAL hollow gets when the rain falls somewhere nothing
## has been dug. Deliberately modest: a wide probe finds a downhill sample on
## almost any real ground and concludes, wrongly, that the water drains.
const NATURAL_HOLLOW := 7.0

## A VOLCANO, and how slowly it arrives. It used to be two deforms half a
## second apart, which read as a spire appearing — and because scars ADD, a
## second cast on the same spot doubled it. It now grows ONE scar over a full
## minute, spilling lava the whole way, and is capped both by its own height
## and by how much relief already stands there.
## A LAVABALL IS A TRUCKFUL, not a hill. A handful of molten earth: it lands,
## it spreads, it cools into a low mound about knee height and a few paces
## across. Anyone who wants a mountain out of these has to stand there and
## throw them, which is the point — the volcano is the shortcut, and it works by
## throwing thirty of them itself.
const LAVA_RISE := 0.55
const LAVA_REACH := 3.4

## A VOLCANO IS A LAVA FOUNTAIN. It hurls globs straight up out of the vent and
## the mountain GROWS FROM WHERE THEY LAND, over a full minute — rather than a
## scripted cone that simply inflates. Everything about its shape comes from the
## spread of the throws.
const VOLCANO_GLOBS := 30
const VOLCANO_SECONDS := 60.0
## How far from the vent a glob may fall. Biased hard toward the middle (see
## `_glob_landing`), which is what makes a heap of random throws a CONE.
const VOLCANO_SPREAD := 11.0
## How long one glob spends in the air.
const GLOB_FLIGHT := 1.7
## How much of a poured load goes into filling a hole rather than piling up.
## Above 1 so a crater takes fewer loads to level than a hill takes to build —
## pouring into a bowl is easier than stacking on flat ground.
const FILL_RATE := 1.6
## Where a dug crater's rim actually sits, as a fraction of its radius — the
## ring of spoil it threw up around itself. See `_maybe_flood`.
const LIP_OF := 0.82
## And how wide the water sits inside it: just short of the lip, so the pool
## lies IN the bowl rather than lapping over the edge of it.
const POOL_OF := 0.9
## How far below the rim a pond's surface must sit. Level with the rim, the
## water spills and every point out to the pond's radius reads as underwater.
const FREEBOARD := 0.4
## And how clear of a town's edge standing water must keep.
const TOWN_CLEARANCE := 8.0

var divine_hand: DivineHand = null  # wired by main; orbs land in the grip
## What the PLAYER has cast, and how many runes went into the last one. Only
## `cast_runes` touches these, so the creature's own casting never counts —
## the tutorial watches them to know a lesson actually landed.
var casts_made := 0
var last_rune_count := 0
## The showers currently in the sky, oldest first.
var _clouds: Array[StormCloud] = []


## Your reach: 1.0 alone, rising with converted villages and their belief.
## Scales the extent of the grander miracles.
func _ready() -> void:
	add_to_group("miracles")
	# Draw the cloud texture now, while the world is being built and a few
	# milliseconds cost nothing, rather than on the first shower.
	StormCloud.vapour_texture()


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
		# The earth-movers, and two mercies.
		"earthquake": _cast_earthquake(pos, potency)
		"lavaball": _cast_lavaball(pos, potency)
		"volcano": _cast_volcano(pos, potency)
		"water_walk": _cast_water_walk(pos, potency)
		"healing_shower": _cast_healing_shower(pos, potency)
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
	# Heavy rain into a hollow stands in it (see `_maybe_flood`). A sprinkle
	# never does, and rain on open ground never does whatever its weight.
	_maybe_flood(pos, potency)
	# THE CLOUD ITSELF. A swirl of soft streaked layers that turn, breathe, and
	# come and go — the fiercer the working, the more of them, the darker and
	# the faster they churn. See StormCloud; it is one draw call either way.
	var cloud := StormCloud.new()
	cloud.position = pos + Vector3(0, 12, 0)
	cloud.brew(potency)

	var drops := CPUParticles3D.new()
	drops.amount = Quality.particles(RAIN_DROPS)
	drops.lifetime = 1.4
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	# The rain falls from the UNDERSIDE of the mass, and spreads as wide as the
	# weather does, so a deluge is not a shower through a bigger cloud.
	drops.emission_box_extents = Vector3(4.0 * potency, 0.2, 4.0 * potency)
	drops.position.y = cloud.underside()
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

	_hold_cloud(cloud)
	# It disperses rather than being deleted: the layers fade out over a few
	# seconds and the node frees itself when the sky is clear.
	get_tree().create_timer(12.0).timeout.connect(cloud.disperse)


## Keep the sky to a few showers. A new one over a crowded sky sends the oldest
## away, which is both cheaper and better weather — rain that stacks six deep
## over one field looks like a bug, not a downpour.
func _hold_cloud(cloud: StormCloud) -> void:
	# Pruned in place, never reassigned: filter() hands back a plain untyped
	# Array, which will not go into an Array[StormCloud] and fails on the frame
	# the line first runs. See Util.prune.
	Util.prune(_clouds)
	_clouds.append(cloud)
	while _clouds.size() > RAIN_CLOUDS:
		var oldest: StormCloud = _clouds.pop_front()
		if is_instance_valid(oldest):
			oldest.disperse()


## A raindrop: two triangles, billboarded, stretched into a streak. It used to
## be a default SphereMesh — 4,224 triangles apiece, four hundred at a time.
func _drop_mesh() -> QuadMesh:
	return Util.speck_mesh(0.03, 0.22, Color(0.5, 0.7, 1.0, 0.8))


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


## RAIN THAT STANDS. A heavy enough downpour over a hollow does not run off it
## — it fills it. This is what turns a fireball crater from a scar into a pond,
## and it is the only way water is ever added to the world.
##
## The test is whether the ground actually holds water: the rim is checked all
## the way round, and if it is open on any side the rain drains away and
## nothing is left behind. So a deluge on a hillside does nothing, and a deluge
## in a crater makes a pool — which is exactly the intuition.
func _maybe_flood(pos: Vector3, potency: float) -> void:
	if potency < 2.0:
		return                       # a shower does not fill anything
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	# THE HOLE DECIDES THE SIZE OF THE QUESTION, not the storm.
	#
	# This first asked whether there was a rim at the RAIN'S reach — sixteen
	# metres for a deluge — when the crater it was meant to fill is under five
	# across. On real ground something within sixteen metres is nearly always
	# downhill, so it concluded the water ran off and left nothing behind:
	# measured, a deluge filled a fireball crater 15 times in 100. Asked at the
	# crater's own scale it is 59, and the rest are craters cut into a slope,
	# where the water really would run away.
	#
	# So if something has been DUG here, its own scar says how wide it is; a
	# natural hollow gets a modest fixed probe instead. Either way the storm's
	# size decides how FULL it gets, never how wide.
	var here := Vector2(pos.x, pos.z)
	var hollow := world.scars.hollow_near(here)
	var reach := NATURAL_HOLLOW
	if not hollow.is_empty():
		here = Vector2(float(hollow["x"]), float(hollow["z"]))
		# ON THE LIP, not past it. A crater throws a ring of spoil up around
		# itself, and that ring is LITERALLY what holds the water in — it sits
		# at about four fifths of the radius. Probing outside it samples natural
		# ground instead, which slopes, so the answer becomes "it drains" on any
		# ground that is not a billiard table. Measured over 200 craters on
		# rough terrain: on the lip 200 fill, one radius out 145, and at the
		# storm's own reach (where this started) 24.
		reach = float(hollow["radius"]) * LIP_OF
	# NEVER ON A TOWN. A pond makes its ground "underwater", and underwater
	# ground is not workable: the farms stop, and a village quietly starves
	# around a pretty blue disc. Whatever else rain may do, it does not drown
	# your own people while your back is turned.
	if _settled_near(here):
		return
	var rim := world.basin_rim(here, reach)
	if rim == -INF:
		return                       # open on a side: it runs off
	var floor_y := world.height_at(here.x, here.y)
	if rim - floor_y < 0.8:
		return                       # barely a dip; not worth a pond
	# It fills toward the rim and STOPS SHORT OF IT. A surface level with the
	# rim spills over the edge, and every point out to the pond's radius then
	# reads as underwater — including ground that is plainly dry. Held a clear
	# margin below, the water sits in the bowl where it belongs.
	var level := lerpf(floor_y, rim - FREEBOARD, clampf(potency / 3.6, 0.35, 0.92))
	if level <= floor_y + 0.25:
		return                       # not enough to be worth calling a pond
	var pool := reach if hollow.is_empty() else float(hollow["radius"]) * POOL_OF
	world.flood(here, pool, level)
	GameState.announce("The water has nowhere to run. A pool stands where the ground was broken.")


## Is there a settlement here? Ponds and other standing water keep away from
## the ground people live and farm on.
func _settled_near(at: Vector2) -> bool:
	for v in get_tree().get_nodes_in_group("village"):
		var town := v as Village
		if not is_instance_valid(town):
			continue
		var flat := Vector2(town.global_position.x, town.global_position.z)
		if flat.distance_to(at) < town.influence_radius + TOWN_CLEARANCE:
			return true
	return false


## Moving the earth -----------------------------------------------------------
##
## The first miracles that change the SHAPE of the world rather than what is
## standing on it. They go through `WorldGen.deform`, which cuts a scar into the
## land; every other system finds out through `height_at()` a frame later, so
## the water, the collision, the routing and where villagers may build all
## agree with the new ground without any of them being told.

## THE GROUND CONVULSES. A ripple of standing waves grows outward from the
## point of the blow — the land itself still ringing — and everything on it is
## thrown about.
##
## The ripple GROWS: three passes over a second and a half, each wider than the
## last, so you watch it spread rather than finding a finished pattern. Each
## pass re-cuts the land, which is why there are three of them and not thirty.
func _cast_earthquake(pos: Vector3, potency := 1.0) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	var reach := minf(11.0 + 5.0 * potency, TerrainScars.BUCKET)
	var lift := 1.1 + 0.5 * potency
	SoundBank.play_at("boom", pos, 2.0)
	_quake_everything(pos, reach * 1.6, potency)
	if world == null:
		return
	for pass_no in 3:
		var grown := reach * lerpf(0.45, 1.0, pass_no / 2.0)
		var here := pos + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		world.deform(TerrainScars.Kind.RIPPLE, Vector2(here.x, here.z),
			grown, lift * (1.0 - pass_no * 0.22), 3.0 + pass_no)
		_shake_camera(1.1 - pass_no * 0.25)
		if pass_no < 2:
			await get_tree().create_timer(0.55).timeout
			if not is_instance_valid(self):
				return


## Everyone and everything within reach is thrown about: people and beasts
## panic, loose objects are tossed, and the towns rouse.
func _quake_everything(pos: Vector3, reach: float, potency: float) -> void:
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if is_instance_valid(villager) and villager.global_position.distance_to(pos) < reach:
			villager.scare(pos)
			villager.take_damage(6.0 * potency, true)
	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if is_instance_valid(animal) and animal.global_position.distance_to(pos) < reach:
			animal.scare(pos)
	for h in get_tree().get_nodes_in_group("houses"):
		var house := h as House
		if is_instance_valid(house) and house.global_position.distance_to(pos) < reach:
			house.damage(18.0 * potency)
	# Anything loose is thrown into the air — the readable signature of a quake.
	for p in get_tree().get_nodes_in_group("pickable"):
		var loose := p as RigidBody3D
		if not is_instance_valid(loose) or loose.freeze:
			continue
		if loose.global_position.distance_to(pos) < reach:
			loose.apply_impulse(Vector3(
				randf_range(-2.0, 2.0), randf_range(3.0, 6.0), randf_range(-2.0, 2.0)))
	var creature := get_tree().get_first_node_in_group("creature") as Creature
	if creature != null and creature.global_position.distance_to(pos) < reach:
		creature.feel("fear", 0.7, 2.5)


## MOLTEN ROCK, THROWN. A fireball's opposite number: where a fireball digs a
## bowl out of the ground, this pours a dome of lava onto it, which cools into
## a hill. It burns what it lands on either way — it is still fire — but what
## it leaves behind is MORE ground rather than less.
##
## AND SO IT FILLS CRATERS, with no special case anywhere. Scars simply add up,
## so a dome laid into a bowl of the same depth cancels it and the land is
## level again. A god who has cratered a field can smooth it back out, and a god
## who overdoes it builds a hill instead — which is the right kind of mistake to
## be able to make.
func _cast_lavaball(pos: Vector3, potency := 1.0) -> void:
	SoundBank.play_at("boom", pos, -2.0)
	_pour_lava(pos, LAVA_RISE * lerpf(0.85, 1.3, clampf(potency / 3.0, 0.0, 1.0)),
		LAVA_REACH, true)


## ONE TRUCKFUL OF MOLTEN ROCK, landing. Shared by the lavaball and by every
## glob a volcano throws, so a mountain is made of exactly the same stuff as
## the thing you can throw by hand — it is only a question of how many.
##
## Into a HOLE it fills rather than piles: the hollow's own scar is shrunk
## toward flat by this load's worth. A crater takes several to level, which is
## the same bargain as building a hill.
func _pour_lava(pos: Vector3, rise: float, reach: float, loud := false) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null or world.is_underwater(pos.x, pos.z):
		return
	var here := Vector2(pos.x, pos.z)
	var hollow := world.scars.hollow_near(here, reach + 2.0)
	if hollow.is_empty():
		world.pour(TerrainScars.Kind.BASIN, here, reach, rise)
	else:
		# Filling: move the hole's own amount toward zero by what was poured,
		# never past it, so the ground levels off rather than becoming a mound
		# in the middle of the old crater.
		var left := float(hollow["amount"])
		var filled := minf(left + rise * FILL_RATE, 0.0)
		world.reshape(hollow, filled)
		if filled >= -0.05 and loud:
			GameState.announce("The crater is level again.")
	_lava_splash(pos, reach, loud)
	# It burns what it lands on, and only that.
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(pos) < reach:
			tree.ignite()
	for grp in ["villagers", "animals"]:
		for n in get_tree().get_nodes_in_group(grp):
			var body := n as Node3D
			if is_instance_valid(body) \
					and body.global_position.distance_to(pos) < reach \
					and body.has_method("ignite"):
				body.call("ignite")


## The look of a load landing: a brief spatter and a glow that cools.
func _lava_splash(pos: Vector3, reach: float, loud: bool) -> void:
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.4, 0.1)
	glow.light_energy = 3.0 if not loud else 4.5
	glow.omni_range = reach * 3.0
	glow.shadow_enabled = false
	glow.position = pos + Vector3(0, 1.2, 0)
	add_child(glow)
	var spatter := CPUParticles3D.new()
	spatter.amount = Quality.particles(34)
	spatter.lifetime = 1.3
	spatter.one_shot = true
	spatter.mesh = Util.speck_mesh(0.22, 0.22, Color(1.0, 0.62, 0.18, 0.95), true)
	spatter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spatter.emission_sphere_radius = reach * 0.35
	spatter.direction = Vector3.UP
	spatter.spread = 55.0
	spatter.initial_velocity_min = 3.0
	spatter.initial_velocity_max = 7.0
	spatter.gravity = Vector3(0, -14.0, 0)
	spatter.position = pos
	add_child(spatter)
	var cool := create_tween()
	cool.tween_property(glow, "light_energy", 0.0, 4.0)
	cool.tween_callback(glow.queue_free)
	cool.tween_callback(spatter.queue_free)


## THE EARTH SPLITS OPEN. A mountain is raised where the miracle lands, with a
## crater bitten out of its summit, and then it erupts: fire thrown from the
## mouth, embers raining, and everything around it set alight.
##
## The single most destructive thing a god can do here, and the terrain it
## leaves behind is permanent — a volcano is a landmark, not an event.
## A VOLCANO IS A LAVA FOUNTAIN, and the mountain is what its throws pile up.
##
## It was a scripted cone that inflated, which is why it read as a spire
## appearing rather than a mountain building. It now hurls thirty globs of the
## same molten rock a lavaball is made of, straight up out of the vent, over a
## full minute — and the mountain grows from WHERE THEY LAND. Nothing shapes
## the cone but the spread of the throws, and anyone patient enough could build
## the same hill by hand, one lavaball at a time.
func _cast_volcano(pos: Vector3, potency := 1.0) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	SoundBank.play_at("boom", pos, 6.0)
	GameState.announce("The ground splits, and the earth begins to throw itself into the sky.")
	var vent := pos
	vent.y = world.height_at(pos.x, pos.z)
	var glare := _lava_glare(vent, VOLCANO_SPREAD)
	var thrown := int(VOLCANO_GLOBS * lerpf(0.7, 1.3, clampf(potency / 3.0, 0.0, 1.0)))

	for i in thrown:
		await get_tree().create_timer(VOLCANO_SECONDS / float(thrown)).timeout
		if not is_instance_valid(self) or not is_instance_valid(world):
			return
		# The vent rises with its own mountain, so later globs are thrown from
		# higher up and the cone keeps its shape instead of drowning its source.
		vent.y = world.height_at(pos.x, pos.z)
		if is_instance_valid(glare):
			glare.position = vent + Vector3(0, 3.0, 0)
			glare.light_energy = 4.0 + sin(float(i)) * 1.5
		_hurl_glob(vent, _glob_landing(pos))
		if i % 4 == 0:
			_shake_camera(0.7)
			_scorch_around(vent, VOLCANO_SPREAD * 1.6, potency)

	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(self):
		return
	GameState.announce("The mountain stands, and the fires begin to cool.")
	if is_instance_valid(glare):
		var cool := create_tween()
		cool.tween_property(glare, "light_energy", 0.0, 6.0)
		cool.tween_callback(glare.queue_free)


## WHERE A GLOB COMES DOWN. Biased hard toward the vent — the square of a
## random gives most of the loads to the middle and a scattering to the flanks,
## which is precisely the distribution that makes a heap into a CONE. An even
## spread would build a plateau.
func _glob_landing(vent: Vector3) -> Vector3:
	var away := randf() * TAU
	var out := VOLCANO_SPREAD * randf() * randf()
	return Vector3(vent.x + cos(away) * out, 0.0, vent.z + sin(away) * out)


## Throw one glob out of the vent and let it fall. It arcs, it glows, and when
## it lands it pours exactly what a lavaball pours.
func _hurl_glob(from: Vector3, to: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	to.y = world.height_at(to.x, to.z)
	var glob := Util.sphere(randf_range(0.5, 0.95), Color(1.0, 0.55, 0.12), from, true)
	add_child(glob)
	# High and slow: the arc is most of what sells this, so it is thrown well
	# clear of the summit rather than lobbed.
	var apex := (from + to) * 0.5 + Vector3(0, randf_range(14.0, 26.0), 0)
	var arc := create_tween()
	arc.tween_method(func(t: float) -> void:
		if is_instance_valid(glob):
			# One quadratic Bezier: vent, high point, landing.
			var a := from.lerp(apex, t)
			var b := apex.lerp(to, t)
			glob.position = a.lerp(b, t),
		0.0, 1.0, GLOB_FLIGHT).set_trans(Tween.TRANS_LINEAR)
	arc.tween_callback(func() -> void:
		if is_instance_valid(glob):
			glob.queue_free()
		_pour_lava(to, LAVA_RISE * randf_range(0.7, 1.1), LAVA_REACH * randf_range(0.9, 1.3)))


func _lava_glare(at: Vector3, reach: float) -> OmniLight3D:
	var glare := OmniLight3D.new()
	glare.light_color = Color(1.0, 0.42, 0.12)
	glare.light_energy = 5.0
	glare.omni_range = reach * 3.0
	glare.shadow_enabled = false
	glare.position = at + Vector3(0, 3.0, 0)
	add_child(glare)
	return glare


## Everything within reach catches, called now and then as the mountain climbs.
func _scorch_around(at: Vector3, reach: float, potency: float) -> void:
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(at) < reach:
			tree.ignite()
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(at) < reach:
			farm.ignite()
	for grp in ["villagers", "animals"]:
		for n in get_tree().get_nodes_in_group(grp):
			var body := n as Node3D
			if not is_instance_valid(body):
				continue
			var d := body.global_position.distance_to(at)
			if d < reach and body.has_method("ignite"):
				body.call("ignite")
			if d < reach * 1.5 and body.has_method("scare"):
				body.call("scare", at)
	_quake_everything(at, reach, potency * 0.4)


func _shake_camera(strength: float) -> void:
	var rig := get_tree().get_first_node_in_group("camera_rig") as CameraRig
	if rig != null:
		rig.shake(strength)


## Two mercies -----------------------------------------------------------------

## FOOTING ON WATER. Ward is a shelter held over a thing; held over water it is
## ground. The creature crosses lakes at full stride instead of wading them at
## half speed, and its router will happily plan straight across open water.
func _cast_water_walk(pos: Vector3, potency := 1.0) -> void:
	var creature := get_tree().get_first_node_in_group("creature") as Creature
	if creature == null:
		GameState.hint("There is no creature here to bless.")
		return
	if creature.global_position.distance_to(pos) > 60.0:
		GameState.hint("Cast it nearer your creature to bless its feet.")
		return
	creature.grant_water_walking(30.0 + potency * 20.0)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 1.0
	var halo := Util.mesh_node(ring, Color(0.55, 0.85, 0.95, 0.85),
		creature.global_position + Vector3(0, 0.25, 0), true)
	add_child(halo)
	var tween := create_tween()
	tween.tween_property(halo, "scale", Vector3(4.0, 1, 4.0), 1.0)
	tween.parallel().tween_property(halo, "transparency", 1.0, 1.0)
	tween.tween_callback(halo.queue_free)


## A HEALING SHOWER. Rain that is also calm and life: for ten seconds it puts
## out every fire under it and mends everything standing in it, over and over.
## The kindest thing in the spellbook, and the answer to a fire you started.
func _cast_healing_shower(pos: Vector3, potency := 1.0) -> void:
	var reach := 9.0 * potency
	var cloud := StormCloud.new()
	cloud.position = pos + Vector3(0, 11, 0)
	cloud.brew(1.0)

	# A child of the cloud, exactly as ordinary rain is: `underside()` is a
	# LOCAL offset down to the base of the mass, not a world height.
	var drops := CPUParticles3D.new()
	drops.amount = Quality.particles(int(RAIN_DROPS * 0.5))
	drops.lifetime = 1.3
	drops.mesh = Util.speck_mesh(0.04, 0.24, Color(0.6, 1.0, 0.75, 0.85), true)
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(reach, 0.2, reach)
	drops.direction = Vector3.DOWN
	drops.initial_velocity_min = 9.0
	drops.initial_velocity_max = 13.0
	drops.gravity = Vector3(0, -12.0, 0)
	drops.position.y = cloud.underside()
	cloud.add_child(drops)
	add_child(cloud)

	GameState.announce("A green rain falls. What is burning goes out; what is hurt begins to mend.")
	await _shower_mercy(pos, reach)

	# Stop making new drops and let the ones in the air finish falling; the
	# cloud dissolves on its own.
	if is_instance_valid(drops):
		drops.emitting = false
	cloud.disperse()


## The ten seconds of mercy: twenty passes, half a second apart, each one
## dousing what burns and mending what hurts. Continuous rather than a single
## pulse, so walking someone INTO the rain saves them.
func _shower_mercy(pos: Vector3, reach: float) -> void:
	for tick in 20:
		if not is_instance_valid(self):
			return
		for v in get_tree().get_nodes_in_group("villagers"):
			var villager := v as Villager
			if not is_instance_valid(villager):
				continue
			if villager.global_position.distance_to(pos) < reach:
				villager.extinguish()
				villager.receive_heal()
		for a in get_tree().get_nodes_in_group("animals"):
			var animal := a as Animal
			if is_instance_valid(animal) and animal.global_position.distance_to(pos) < reach:
				animal.extinguish()
		for t in get_tree().get_nodes_in_group("trees"):
			var tree := t as WildTree
			if is_instance_valid(tree) and tree.burning \
					and tree.global_position.distance_to(pos) < reach:
				tree.extinguish()
		for f in get_tree().get_nodes_in_group("farms"):
			var farm := f as Farm
			if is_instance_valid(farm) and farm.global_position.distance_to(pos) < reach:
				farm.extinguish()
		var creature := get_tree().get_first_node_in_group("creature") as Creature
		if creature != null and creature.global_position.distance_to(pos) < reach:
			creature.receive_heal()
		await get_tree().create_timer(0.5).timeout


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
	swirl.amount = Quality.particles(60)
	swirl.lifetime = 1.6
	# It had no mesh at all, which in Godot 4 means it drew nothing: the gust
	# that lifts your creature has been invisible this whole time.
	swirl.mesh = Util.speck_mesh(0.14, 0.14, Color(0.85, 0.92, 1.0, 0.55))
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
	flare.amount = Quality.particles(40)
	flare.lifetime = 1.2
	flare.mesh = Util.speck_mesh(0.16, 0.16, Color(1.0, 0.85, 0.4), true)
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
