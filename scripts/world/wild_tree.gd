class_name WildTree
extends StaticBody3D
## A harvestable tree. Lumberjacks chop it; it falls over dramatically and
## yields lumber. Styles vary by biome (savanna acacias are flat-topped).

const LUMBER_YIELD := 3

var style := "forest"
var rng_seed := 0
var _felled := false


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
	return LUMBER_YIELD


func is_felled() -> bool:
	return _felled


func hover_text() -> String:
	return "Tree — %d lumber if chopped" % LUMBER_YIELD
