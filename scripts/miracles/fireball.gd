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
const TRAIL_INTERVAL := 0.09     # seconds between flames dropped in flight
const TRAIL_IGNITE_RADIUS := 1.7  # a narrow lick of fire along the path
const REST_SPEED := 1.2           # below this it has come to rest -> bursts

## THE ROLLING PROBLEM. A fireball is a sphere, and `friction` on a physics
## material only resists SLIDING — a rolling ball it barely touches. With no
## damping at all, one thrown at a hillside would roll to the lowest point in
## the county and burst three villages away from where it was aimed.
##
## So it is braked BY HAND, and only once it is actually on the ground: damping
## it in flight would flatten the ballistic arc that makes throwing feel like
## throwing. GRIP is per second and exponential, so a 20 m/s roll is down to a
## walking pace inside a second.
const GROUND_GRIP := 3.6
const SPIN_GRIP := 4.5
## How close to the ground counts as rolling rather than flying.
const TOUCHING := 0.7
## And a hard stop: however gentle the slope, it bursts after this long on the
## ground. Nothing rolls out of the shot the player actually took.
const ROLL_SECONDS := 2.5

## HOW DEEP IT DIGS. A fireball does not only scorch — it gouges a bowl out of
## the earth and blackens what is left, and the mark stays in the world.
const GOUGE_DEPTH := 1.7
const GOUGE_CHAR := 0.9

var _armed := false
var _exploded := false
var _trail_time := 0.0
var _rolling := 0.0


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	mass = 2.0
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
	embers.amount = Quality.particles(40)
	embers.lifetime = 0.7
	embers.mesh = _ember_mesh()
	embers.direction = Vector3.UP
	embers.initial_velocity_min = 0.5
	embers.initial_velocity_max = 1.5
	embers.gravity = Vector3(0, 1.5, 0)
	add_child(embers)

	get_tree().create_timer(FUSE_SECONDS).timeout.connect(_explode)


## Two triangles, glowing, always facing you. It was a full 64x32 UV sphere.
func _ember_mesh() -> QuadMesh:
	return Util.speck_mesh(0.1, 0.1, Color(1.0, 0.7, 0.2), true)


func _physics_process(delta: float) -> void:
	if freeze:
		return  # still in the grip
	# Arms the moment the hand lets go and it's genuinely in flight.
	if not _armed and linear_velocity.length() > 2.0:
		_armed = true
	if _armed:
		_lay_trail(delta)
		_brake(delta)
		# It rolls until it stops, then bursts where it settles.
		if linear_velocity.length() < REST_SPEED or _rolling > ROLL_SECONDS:
			_explode()


## Slow the roll — but only once it is down. In the air it keeps every bit of
## the momentum the throw gave it; the moment it touches, the ground drags it
## down hard. Horizontal only, so gravity is never fought.
func _brake(delta: float) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	var ground := world.surface_at(global_position.x, global_position.z)
	if global_position.y > ground + TOUCHING:
		return                       # still flying: leave the arc alone
	_rolling += delta
	var drag := exp(-GROUND_GRIP * delta)
	linear_velocity.x *= drag
	linear_velocity.z *= drag
	angular_velocity *= exp(-SPIN_GRIP * delta)


## Drops a small flame at the ball's ground track and lightly sets alight
## whatever it rolls past — a narrow, spreading wake of fire behind the throw.
func _lay_trail(delta: float) -> void:
	_trail_time -= delta
	if _trail_time > 0.0:
		return
	_trail_time = TRAIL_INTERVAL
	var scene := get_tree().current_scene
	if scene == null:
		return
	var gp := global_position
	var ground_y := gp.y
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		ground_y = world.surface_at(gp.x, gp.z)
	var flame := Util.small_flame(0.4)
	flame.scale = Vector3.ONE * 0.5
	flame.position = Vector3(gp.x, ground_y, gp.z)
	scene.add_child(flame)
	get_tree().create_timer(2.2).timeout.connect(flame.queue_free)
	_ignite_trail(gp)


## The narrow trail catches trees, fields, and any soul it brushes.
func _ignite_trail(pos: Vector3) -> void:
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(pos) < TRAIL_IGNITE_RADIUS:
			tree.ignite()
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(pos) < TRAIL_IGNITE_RADIUS:
			farm.ignite()
	for grp in ["villagers", "animals"]:
		for n in get_tree().get_nodes_in_group(grp):
			var node := n as Node3D
			if is_instance_valid(node) and node.global_position.distance_to(pos) < TRAIL_IGNITE_RADIUS \
					and node.has_method("ignite"):
				node.call("ignite")


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

	# THE EARTH ITSELF. A bowl gouged out of the ground with a lip of thrown
	# spoil around it, and the whole of it burned black — and unlike everything
	# else here, it stays. Come back in an hour and the crater is still there.
	_gouge(pos)

	# The blast is the sermon: terror converts where the fireball LANDS.
	for v in get_tree().get_nodes_in_group("village"):
		(v as Village).witness_miracle("fireball", pos)

	queue_free()


## Dig the crater. Skipped over open water, where there is no ground to dig and
## a bowl in the lake bed would only be a bigger lake.
func _gouge(pos: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null or world.is_underwater(pos.x, pos.z):
		return
	# Dry when we got here — the guard above already turned back over water.
	world.deform(TerrainScars.Kind.CRATER, Vector2(pos.x, pos.z),
		BLAST_RADIUS * 0.8, -GOUGE_DEPTH, 3.0, GOUGE_CHAR)
	# THE WATERLINE IS A THING YOU CAN DIG THROUGH, and craters stack: the
	# village cradle sits two metres above the sea, and a fireball takes 1.7,
	# so the SECOND one on a spot opens the ground to the water. That is a fair
	# consequence and it stays — but it should be a choice, not a discovery
	# made by counting bodies afterwards.
	#
	# Asked of the WATER and not of the number: digging below sea level well
	# inland leaves a dry pit, because the sea is not everywhere at once (see
	# WorldGen.sea_reaches). Only say the water came in when it did.
	if world.is_underwater(pos.x, pos.z):
		GameState.announce("The crater breaks below the waterline, and the water comes in.")


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
	# There used to be a black disc laid on the ground here, faded out after
	# twenty-five seconds. It is gone: the scorch is now cut into the terrain
	# itself (see `_gouge`), so it is a real feature of the world rather than a
	# decal with a timer, and it does not vanish while you are looking at it.
	var tween := scene.create_tween()
	tween.tween_property(fire, "scale", Vector3.ONE * BLAST_RADIUS, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(fire, "transparency", 1.0, 0.45)
	tween.parallel().tween_property(flash, "light_energy", 0.0, 0.5)
	tween.tween_callback(fire.queue_free)
	tween.tween_callback(flash.queue_free)


func hover_text() -> String:
	return "Fireball (throw it!)"
