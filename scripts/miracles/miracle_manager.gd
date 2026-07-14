class_name MiracleManager
extends Node3D
## Owns the miracle catalog: gesture mapping, prayer costs, and effects.
## Add a new miracle by extending MIRACLES and adding a _cast_* method —
## this table is the seam where "dozens of miracles, unlockable/improvable"
## will plug in later.

const MIRACLES := {
	"circle": {"name": "food", "cost": 20.0},
	"zigzag": {"name": "rain", "cost": 25.0},
	"vline": {"name": "lightning", "cost": 30.0},
	"hline": {"name": "heal", "cost": 15.0},
}

var village: Village


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
	if village != null:
		village.witness_miracle(miracle, pos)
	return true


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

	# Water everything in range.
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if farm.global_position.distance_to(pos) < 14.0:
			farm.water(12.0)

	var timer := get_tree().create_timer(12.0)
	timer.timeout.connect(cloud.queue_free)


func _drop_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.04
	m.height = 0.12
	m.material = Util.mat(Color(0.5, 0.7, 1.0, 0.8))
	return m


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
