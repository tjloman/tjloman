class_name RockDeposit
extends StaticBody3D
## A cluster of boulders that quarriers pick apart for stone — a deep vein:
## up to 300 stone before it's spent. The boulders visibly shrink as the
## deposit is worked down.

const STONE_PER_HARVEST := 3
const TOTAL_STONE := 300

var stone_left := TOTAL_STONE
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

	var custom := ModelBank.instantiate("rock")
	if custom != null:
		# A custom rock model won't shrink as it's worked, but quarries fine.
		add_child(custom)
	else:
		for i in 3:
			var r := randf_range(0.5, 0.9)
			var b := Util.lite_sphere(r, Color(0.52, 0.51, 0.53),
				Vector3(randf_range(-0.7, 0.7), r * 0.6, randf_range(-0.7, 0.7)))
			add_child(b)
			_boulders.append(b)


## One quarrying pass: yields stone, wears the pile down, frees when spent.
func quarry() -> int:
	if stone_left <= 0:
		return 0
	var taken := mini(STONE_PER_HARVEST, stone_left)
	stone_left -= taken
	var fraction := float(stone_left) / TOTAL_STONE
	for i in _boulders.size():
		var b := _boulders[i]
		if not is_instance_valid(b):
			continue
		# Boulders shed one by one as the vein empties; survivors shrink.
		if fraction < float(i) / _boulders.size():
			b.visible = false
		else:
			b.scale = Vector3.ONE * lerpf(0.45, 1.0, fraction)
	if stone_left <= 0:
		queue_free()
	return taken


func is_exhausted() -> bool:
	return stone_left <= 0


func hover_text() -> String:
	return "Rock deposit — %d stone remaining" % stone_left
