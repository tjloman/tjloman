class_name Corpse
extends RigidBody3D
## What remains of a villager. A physical object: it can be picked up,
## thrown, eaten by an evil creature, or butchered for meat by a village
## with the cannibal diet. Decays after a while.

const DECAY_SECONDS := 120.0

var villager_name := "someone"


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 4.0
	# The dead stay where they fall — no rolling downhill into the lake.
	var phys := PhysicsMaterial.new()
	phys.friction = 1.0
	phys.bounce = 0.0
	physics_material_override = phys
	linear_damp = 0.8
	angular_damp = 8.0


func _ready() -> void:
	add_to_group("corpses")
	add_to_group("pickable")

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.2
	col.shape = shape
	col.rotation_degrees.z = 90  # lying down
	add_child(col)

	var body := Util.capsule(0.26, 1.0, Color(0.55, 0.55, 0.5))
	body.rotation_degrees.z = 90
	add_child(body)
	add_child(Util.sphere(0.16, Color(0.7, 0.62, 0.55), Vector3(0.65, 0, 0)))

	get_tree().create_timer(DECAY_SECONDS).timeout.connect(_decay)


func _decay() -> void:
	if is_instance_valid(self):
		queue_free()


func hover_text() -> String:
	return "The remains of %s" % villager_name
