class_name Edubba
extends StaticBody3D
## The Edubba — a village schoolhouse (the word is Sumerian, "tablet house").
## Once built, the village's children gather here under a teacher instead of
## trailing their mothers, which frees the mothers to bear more children.

var village: Village


func _ready() -> void:
	add_to_group("edubba")
	set_meta("hover_name", "Edubba (school)")
	collision_layer = 4  # hoverable; villagers pass through
	collision_mask = 0

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.4, 3.0, 3.4)
	col.shape = shape
	col.position = Vector3(0, 1.5, 0)
	add_child(col)

	var custom := ModelBank.instantiate("school")
	if custom != null:
		add_child(custom)
	else:
		# A broad, low hall with a pale plastered look and a flat reed roof.
		add_child(Util.box(Vector3(4.4, 1.2, 3.4), Color(0.5, 0.47, 0.42), Vector3(0, -0.5, 0)))
		add_child(Util.box(Vector3(4.0, 2.0, 3.0), Color(0.82, 0.76, 0.62), Vector3(0, 1.0, 0)))
		add_child(Util.box(Vector3(4.4, 0.4, 3.4), Color(0.55, 0.45, 0.3), Vector3(0, 2.2, 0)))
		# A doorway and two small windows.
		add_child(Util.box(Vector3(0.7, 1.3, 0.1), Color(0.35, 0.25, 0.15), Vector3(0, 0.65, 1.5)))
		for x in [-1.1, 1.1]:
			add_child(Util.box(Vector3(0.5, 0.5, 0.08), Color(0.4, 0.55, 0.6), Vector3(x, 1.3, 1.5)))
		# A little standing tablet by the door, to read as "school".
		add_child(Util.box(Vector3(0.5, 0.7, 0.08), Color(0.72, 0.64, 0.5), Vector3(1.5, 0.9, 1.2)))


## Where children and the teacher gather — the yard just outside the door.
func yard_position() -> Vector3:
	return global_position + Vector3(0, 0, 3.0)


func hover_text() -> String:
	var n := 0
	if village != null and is_instance_valid(village):
		for v in village.my_villagers():
			if not v.is_adult():
				n += 1
	return "Edubba (school) — %d children learning" % n
