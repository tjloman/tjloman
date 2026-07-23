class_name Fireball
extends RigidBody3D
## A miraculous ball of fire, conjured into the divine hand. Throw it: it
## flies with real momentum, arcs under gravity, and detonates on impact —
## killing at the core, burning and terrifying around it. Terror converts.
## The gods of peace do not learn this one.

const BLAST_RADIUS := 6.0
const KILL_RADIUS := 2.2
const FUSE_SECONDS := 25.0
const KARMA_PER_KILL := -3.0

var _armed := false
var _exploded := false


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	mass = 2.0
	contact_monitor = true
	max_contacts_reported = 4
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.0
	physics_material_override = phys


func _ready() -> void:
	add_to_group("pickable")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	col.shape = shape
	add_child(col)

	add_child(Util.sphere(0.35, Color(1.0, 0.45, 0.1), Vector3.ZERO, true))
	add_child(Util.sphere(0.22, Color(1.0, 0.85, 0.3), Vector3.ZERO, true))

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 2.5
	light.omni_range = 9.0
	add_child(light)

	var embers := CPUParticles3D.new()
	embers.amount = 40
	embers.lifetime = 0.7
	embers.mesh = _ember_mesh()
	embers.direction = Vector3.UP
	embers.initial_velocity_min = 0.5
	embers.initial_velocity_max = 1.5
	embers.gravity = Vector3(0, 1.5, 0)
	add_child(embers)

	body_entered.connect(_on_body_entered)
	get_tree().create_timer(FUSE_SECONDS).timeout.connect(_explode)


func _ember_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	m.material = Util.mat(Color(1.0, 0.7, 0.2), true)
	return m


func _physics_process(_delta: float) -> void:
	# Arms the moment the hand lets go and it's genuinely in flight.
	if not _armed and not freeze and linear_velocity.length() > 2.0:
		_armed = true


func _on_body_entered(_body: Node) -> void:
	if _armed:
		_explode()


func _explode() -> void:
	if _exploded or freeze:  # never in the player's grip
		return
	_exploded = true
	var pos := global_position
	SoundBank.play_at("boom", pos, 4.0)
	_blast_visuals(pos)

	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		var d := villager.global_position.distance_to(pos)
		if d < KILL_RADIUS:
			GameState.shift_alignment(KARMA_PER_KILL)
			villager.take_damage(999.0, true, true)  # point-blank is instant
		elif d < BLAST_RADIUS:
			villager.take_damage(45.0, true)
			villager.ignite()  # the blast sets them alight
			villager.scare(pos)

	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		var d := animal.global_position.distance_to(pos)
		if d < KILL_RADIUS:
			animal.die()
		elif d < BLAST_RADIUS * 2.0:
			if d < BLAST_RADIUS:
				animal.ignite()
			animal.scare(pos)

	for h in get_tree().get_nodes_in_group("houses"):
		var house := h as House
		if house.global_position.distance_to(pos) < BLAST_RADIUS:
			house.damage(50.0)

	# Fire catches on the trees it touches — and spreads from there.
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(pos) < BLAST_RADIUS:
			tree.ignite()

	# A field in the blast goes up too.
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(pos) < BLAST_RADIUS:
			farm.ignite()

	# The blast is the sermon: terror converts where the fireball LANDS.
	for v in get_tree().get_nodes_in_group("village"):
		(v as Village).witness_miracle("fireball", pos)

	queue_free()


func _blast_visuals(pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fire := Util.sphere(0.5, Color(1.0, 0.55, 0.1, 0.9), Vector3.ZERO, true)
	fire.position = pos
	scene.add_child(fire)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.2)
	flash.light_energy = 7.0
	flash.omni_range = 22.0
	flash.position = pos + Vector3(0, 2, 0)
	scene.add_child(flash)
	# The scorch is burned into the GROUND, wherever the blast happened
	# above it — never left floating in mid-air.
	var ground_y := pos.y
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		ground_y = maxf(world.height_at(pos.x, pos.z), WorldGen.WATER_LEVEL)
	var scorch := Util.cylinder(BLAST_RADIUS * 0.55, 0.06, Color(0.12, 0.09, 0.07),
		Vector3(pos.x, ground_y + 0.05, pos.z))
	scene.add_child(scorch)

	var tween := scene.create_tween()
	tween.tween_property(fire, "scale", Vector3.ONE * BLAST_RADIUS, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(fire, "transparency", 1.0, 0.45)
	tween.parallel().tween_property(flash, "light_energy", 0.0, 0.5)
	tween.tween_callback(fire.queue_free)
	tween.tween_callback(flash.queue_free)
	scene.get_tree().create_timer(25.0).timeout.connect(scorch.queue_free)


func hover_text() -> String:
	return "Fireball (throw it!)"
