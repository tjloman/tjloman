class_name WildTree
extends StaticBody3D
## A living, growing tree. Saplings hold 1 lumber and stand knee-high;
## over the days they grow to 30-lumber giants, the whole model scaling
## with maturity. Mature trees replant themselves — seedlings spring up
## nearby, so a forest logged with restraint is a forest forever.
## Lumberjacks fell them for their CURRENT lumber; felled trees are gone.

const MAX_LUMBER := 30.0
const GROWTH_PER_SEC := 0.018   # sapling to giant across ~5 day cycles
const SAPLING_SCALE := 0.22
const REPLANT_PERIOD := 50.0
const REPLANT_CROWDING := 4     # no seeding when this many trees stand close

var style := "forest"
var rng_seed := 0
var lumber := 1.0

var _felled := false
var _shown_lumber := -1
var _replant_time := REPLANT_PERIOD * randf_range(0.5, 1.5)


func _ready() -> void:
	add_to_group("trees")
	collision_layer = 1
	collision_mask = 0
	set_meta("hover_name", "Tree")

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var h := rng.randf_range(2.5, 4.5)
	var trunk_color := Color(0.42, 0.3, 0.18)
	var leaf_color := Color(0.2, 0.45, 0.2)
	match style:
		"savanna":
			h = rng.randf_range(3.5, 5.0)
			leaf_color = Color(0.4, 0.5, 0.22)
		"wetland":
			h = rng.randf_range(2.0, 3.2)
			trunk_color = Color(0.35, 0.28, 0.2)
			leaf_color = Color(0.25, 0.4, 0.24)
		"grassland":
			leaf_color = Color(0.28, 0.52, 0.24)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = h
	col.shape = shape
	col.position = Vector3(0, h * 0.5, 0)
	add_child(col)

	add_child(Util.cylinder(0.25, h, trunk_color, Vector3(0, h * 0.5, 0)))
	if style == "savanna":
		# Acacia: wide flat canopy.
		add_child(Util.cylinder(2.2, 0.5, leaf_color, Vector3(0, h + 0.3, 0)))
	else:
		var canopy := CylinderMesh.new()
		canopy.top_radius = 0.0
		canopy.bottom_radius = 1.6
		canopy.height = 2.8
		add_child(Util.mesh_node(canopy, leaf_color, Vector3(0, h + 1.2, 0)))

	_apply_growth_scale()


func _process(delta: float) -> void:
	if _felled:
		return
	if lumber < MAX_LUMBER:
		lumber = minf(lumber + GROWTH_PER_SEC * delta, MAX_LUMBER)
		if int(lumber) != _shown_lumber:
			_apply_growth_scale()
	else:
		_replant_time -= delta
		if _replant_time <= 0.0:
			_replant_time = REPLANT_PERIOD * randf_range(0.8, 1.6)
			_try_replant()


## The whole tree scales with its stored lumber: 1 = sapling, 30 = giant.
func _apply_growth_scale() -> void:
	_shown_lumber = int(lumber)
	scale = Vector3.ONE * lerpf(SAPLING_SCALE, 1.0, lumber / MAX_LUMBER)


## A mature tree drops a seed nearby — if the stand isn't already crowded
## and the ground is dry.
func _try_replant() -> void:
	var neighbors := 0
	for t in get_tree().get_nodes_in_group("trees"):
		if t != self and is_instance_valid(t) \
				and (t as Node3D).global_position.distance_to(global_position) < 9.0:
			neighbors += 1
			if neighbors >= REPLANT_CROWDING:
				return
	var angle := randf() * TAU
	var spot := global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(3.5, 7.5)
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null or world.is_underwater(spot.x, spot.z):
		return
	var sapling := WildTree.new()
	sapling.style = style
	sapling.rng_seed = randi()
	sapling.lumber = 1.0
	var parent := get_parent() as Node3D
	spot.y = world.height_at(spot.x, spot.z) - 0.1
	sapling.position = parent.to_local(spot)
	parent.add_child(sapling)


## Called by a lumberjack when the chop completes. Timber!
func fell() -> int:
	if _felled:
		return 0
	_felled = true
	collision_layer = 0
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees:x",
		88.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(2.0)
	tween.tween_callback(queue_free)
	return maxi(int(lumber), 1)


func is_felled() -> bool:
	return _felled


func hover_text() -> String:
	if lumber >= MAX_LUMBER:
		return "Tree — %d lumber, fully grown" % int(lumber)
	return "Tree — %d lumber and growing" % int(lumber)
