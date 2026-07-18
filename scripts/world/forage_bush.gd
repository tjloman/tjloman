class_name ForageBush
extends StaticBody3D
## A wild berry bush. Villagers forage it when the granary runs dry;
## herbivores browse it between trips to water. Berries regrow with time,
## so the land itself is a slow, renewable larder.

const MAX_BERRIES := 4
const REGROW_SECONDS := 45.0

var berries := 3

var _berry_meshes: Array[MeshInstance3D] = []
var _regrow_time := REGROW_SECONDS


func _ready() -> void:
	add_to_group("forage")
	collision_layer = 4
	collision_mask = 0
	set_meta("hover_name", "Forage bush")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	add_child(col)

	var leaf := Color(0.18, 0.38, 0.16)
	add_child(Util.sphere(0.65, leaf, Vector3(0, 0.45, 0)))
	add_child(Util.sphere(0.45, leaf.lightened(0.1), Vector3(0.4, 0.35, 0.2)))
	add_child(Util.sphere(0.4, leaf.lightened(0.05), Vector3(-0.35, 0.35, -0.15)))
	for i in MAX_BERRIES:
		var a := TAU * i / MAX_BERRIES + 0.5
		var berry := Util.sphere(0.09, Color(0.75, 0.15, 0.25),
			Vector3(cos(a) * 0.45, 0.65 + sin(i * 2.1) * 0.15, sin(a) * 0.45))
		add_child(berry)
		_berry_meshes.append(berry)
	_update_berries()


func _process(delta: float) -> void:
	if berries >= MAX_BERRIES:
		return
	_regrow_time -= delta
	if _regrow_time <= 0.0:
		_regrow_time = REGROW_SECONDS
		berries += 1
		_update_berries()


func has_berries() -> bool:
	return berries > 0


## One handful picked (by hand, hoof, or beak). False if bare.
func take_berry() -> bool:
	if berries <= 0:
		return false
	berries -= 1
	_regrow_time = REGROW_SECONDS
	_update_berries()
	return true


func _update_berries() -> void:
	for i in _berry_meshes.size():
		_berry_meshes[i].visible = i < berries


func hover_text() -> String:
	return "Forage bush — %d berries" % berries
