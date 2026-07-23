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
const MENUS := {
	"spiral": {
		"label": "NATURE:  O food   |  forest   —  thicket   \\  bloom",
		"selectors": {
			"circle": "food", "vline": "forest_seed",
			"hline": "forage_thicket", "dline": "rain",
		},
	},
	"rev_spiral": {
		"label": "WRATH:  |  lightning   O  storm   \\  fireball   —  tornado",
		"selectors": {
			"vline": "lightning", "circle": "lightning_storm",
			"dline": "fireball", "hline": "tornado",
		},
	},
	"wave": {
		"label": "SKY:  —  heal   O  birds   |  rain",
		"selectors": {"hline": "heal", "circle": "bird_flock", "vline": "rain"},
	},
}

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
	"lightning": {"player": -4.0, "creature": -3.0},
	"lightning_storm": {"player": -7.0, "creature": -5.0},
	"tornado": {"player": -8.0, "creature": -6.0},
	"fireball": {"player": -2.5, "creature": -2.0},
}

const LIGHTNING_KILL_RADIUS := 3.0
const LIGHTNING_BURN_RADIUS := 8.0
const CREATURE_SIGHT_RANGE := 45.0

var divine_hand: DivineHand = null  # wired by main; orbs land in the grip


## Your reach: 1.0 alone, rising with converted villages and their belief.
## Scales the extent of the grander miracles.
func power() -> float:
	var believers := 0
	var belief_sum := 0.0
	for v in get_tree().get_nodes_in_group("village"):
		if (v as Village).converted:
			believers += 1
			belief_sum += (v as Village).belief
	return 1.0 + believers * 0.35 + belief_sum / 300.0


## Step one of casting: a menu opener was drawn. Returns its label to show,
## or "" if this gesture opens no menu.
func menu_label(opener: String) -> String:
	return MENUS.get(opener, {}).get("label", "")


func is_menu_opener(gesture: String) -> bool:
	return MENUS.has(gesture)


## Step two: a selector was drawn inside an open menu. Conjures the chosen
## miracle into the hand. Returns false (with a reason) if it can't.
func select(opener: String, selector: String) -> bool:
	var menu: Dictionary = MENUS.get(opener, {})
	var selectors: Dictionary = menu.get("selectors", {})
	if not selectors.has(selector):
		GameState.hint("That gesture means nothing in this menu.")
		return false
	return conjure(selectors[selector])


## Conjures a named miracle as an orb into the divine hand (or drops it
## in the air if the hand is full). Spends prayer power up front.
func conjure(miracle: String) -> bool:
	if not MIRACLES.has(miracle):
		return false
	var cost: float = MIRACLES[miracle]["cost"]
	if cost > GameState.max_prayer_power:
		GameState.hint("%s needs more devoted villages before you can hold it." % miracle.capitalize())
		return false
	if not GameState.try_spend(cost):
		GameState.hint("Not enough prayer power — your followers must worship more.")
		return false
	var body: RigidBody3D
	if miracle == "fireball":
		body = Fireball.new()
	else:
		var orb := MiracleOrb.new()
		orb.miracle_name = miracle
		orb.color = MIRACLES[miracle]["color"]
		orb.manager = self
		body = orb
	add_child(body)
	if divine_hand == null or not divine_hand.force_hold(body):
		body.global_position = global_position + Vector3(0, 4.0, 0)
	GameState.hint("%s conjured — now THROW it where you want it." % miracle.capitalize())
	return true


## Called by a thrown orb when it lands: unleash the effect at that spot,
## apply karma, and let the villages witness it.
func resolve(miracle: String, pos: Vector3) -> void:
	pos.y = 0
	var potency := power()
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

	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if farm.global_position.distance_to(pos) < reach:
			farm.water(12.0 * potency)

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
func _cast_tornado(pos: Vector3, potency := 1.0) -> void:
	var funnel := Node3D.new()
	funnel.position = pos
	add_child(funnel)
	for i in 6:
		var t := i / 6.0
		var ring := Util.cylinder(0.4 + t * 2.6, 1.4, Color(0.55, 0.55, 0.6, 0.6),
			Vector3(0, 0.7 + i * 1.4, 0))
		funnel.add_child(ring)
	var life := 8.0 + potency * 2.0
	var drift := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
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
func _cast_bird_flock(pos: Vector3, potency := 1.0) -> void:
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

	var start := pos + Vector3(-34, 15, -20)
	var finish := pos + Vector3(34, 17, 20)
	var forward := finish - start
	forward.y = 0.0
	forward = forward.normalized()
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
