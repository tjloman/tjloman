class_name MiracleManager
extends Node3D
## Owns the miracle catalog: gesture mapping, prayer costs, karmic weight,
## and effects. Add a new miracle by extending MIRACLES and adding a _cast_*
## method — this table is the seam where "dozens of miracles, unlockable and
## improvable" will plug in later.

const MIRACLES := {
	"circle": {"name": "food", "cost": 20.0},
	"zigzag": {"name": "rain", "cost": 25.0},
	"vline": {"name": "lightning", "cost": 30.0},
	"hline": {"name": "heal", "cost": 15.0},
}

## How each miracle moves the player's karma, and what the creature learns
## from watching it happen.
const KARMA := {
	"food": {"player": 2.0, "creature": 1.5},
	"rain": {"player": 2.0, "creature": 1.5},
	"heal": {"player": 3.0, "creature": 2.0},
	"lightning": {"player": -4.0, "creature": -3.0},
}

const LIGHTNING_KILL_RADIUS := 3.0
const LIGHTNING_BURN_RADIUS := 8.0
const CREATURE_SIGHT_RANGE := 45.0


func cast_gesture(gesture: String, pos: Vector3) -> bool:
	if not MIRACLES.has(gesture):
		return false
	return cast(MIRACLES[gesture]["name"], pos, MIRACLES[gesture]["cost"])


func cast(miracle: String, pos: Vector3, cost := 0.0) -> bool:
	if cost > 0.0 and not GameState.try_spend(cost):
		GameState.announce("Not enough prayer power. Your followers must worship more.")
		return false
	pos.y = 0
	match miracle:
		"food":
			_cast_food(pos)
		"rain":
			_cast_rain(pos)
		"lightning":
			_cast_lightning(pos)
		"heal":
			_cast_heal(pos)
		_:
			return false
	_apply_karma(miracle, pos)
	# Every village close enough to see it reacts — this is how the
	# unbelieving are converted.
	for v in get_tree().get_nodes_in_group("village"):
		(v as Village).witness_miracle(miracle, pos)
	return true


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


func _cast_rain(pos: Vector3) -> void:
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
		if farm.global_position.distance_to(pos) < 14.0:
			farm.water(12.0)

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
			villager.take_damage(999.0, true)
		elif dist < LIGHTNING_BURN_RADIUS:
			villager.take_damage(40.0, true)

	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if animal.global_position.distance_to(pos) < LIGHTNING_KILL_RADIUS:
			animal.die()  # drops cooked-ish meat where it stood


func _cast_heal(pos: Vector3) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	var ring := Util.mesh_node(torus, Color(0.4, 1.0, 0.5, 0.8), pos + Vector3(0, 0.3, 0), true)
	add_child(ring)
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3(8, 1, 8), 1.2)
	tween.parallel().tween_property(ring, "transparency", 1.0, 1.2)
	tween.tween_callback(ring.queue_free)

	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if villager.global_position.distance_to(pos) < 8.0:
			villager.receive_heal()
	for c in get_tree().get_nodes_in_group("creature"):
		var creature := c as Creature
		if creature.global_position.distance_to(pos) < 8.0:
			creature.receive_heal()
