class_name Corpse
extends RigidBody3D
## What remains of a villager. A physical object: it can be picked up,
## thrown, eaten by an evil creature, or butchered for meat by a village
## with the cannibal diet. Decays after a while.

const DECAY_SECONDS := 120.0

var villager_name := "someone"

## Set the first time it hits anything hard enough to be worth watching, so a
## body that bounces twice is one event rather than three.
var _shown := false


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
	# A THROWN BODY IS SOMETHING PEOPLE WATCH LAND. There is no other way for a
	# RigidBody to notice that it arrived, and there are never many corpses.
	contact_monitor = true
	max_contacts_reported = 1


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

	body_entered.connect(_on_hit)
	get_tree().create_timer(DECAY_SECONDS).timeout.connect(_decay)


## Touchdown. Whoever's ground this is has just had one of the dead land on it.
func _on_hit(_what: Node) -> void:
	if _shown:
		return
	_shown = true
	VillageWonder.landed(get_tree(), "corpse", global_position,
		linear_velocity.length())


func _decay() -> void:
	if is_instance_valid(self):
		queue_free()


func hover_text() -> String:
	return "The remains of %s" % villager_name
