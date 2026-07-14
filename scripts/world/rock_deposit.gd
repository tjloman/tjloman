class_name RockDeposit
extends StaticBody3D
## A cluster of boulders that quarriers pick apart for stone. Shrinks with
## every harvest, and is gone after three.

const STONE_PER_HARVEST := 3
const MAX_HARVESTS := 3

var harvests_left := MAX_HARVESTS
var _boulders: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("rock_deposits")
	collision_layer = 1
	collision_mask = 0
	set_meta("hover_name", "Rock deposit")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.2
	col.shape = shape
	col.position = Vector3(0, 0.7, 0)
	add_child(col)

	for i in 3:
		var r := randf_range(0.5, 0.9)
		var b := Util.sphere(r, Color(0.52, 0.51, 0.53),
			Vector3(randf_range(-0.7, 0.7), r * 0.6, randf_range(-0.7, 0.7)))
		add_child(b)
		_boulders.append(b)


## One quarrying pass: yields stone, shrinks the pile, frees when exhausted.
func quarry() -> int:
	if harvests_left <= 0:
		return 0
	harvests_left -= 1
	if _boulders.size() > 0:
		_boulders.pop_back().queue_free()
	if harvests_left <= 0:
		queue_free()
	return STONE_PER_HARVEST


func is_exhausted() -> bool:
	return harvests_left <= 0


func hover_text() -> String:
	return "Rock deposit — %d harvests left" % harvests_left
