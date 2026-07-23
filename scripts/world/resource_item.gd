class_name ResourceItem
extends RigidBody3D
## A physical unit of building material — a bundle of planks or a cut
## stone block. Withdrawn from a storehouse by the divine hand (or hauled
## by the creature), throwable like anything else, and absorbed back into
## whichever storehouse it comes to rest on.

var kind := "lumber"  # or "stone"
var count := 1        # a bundle: this many units in one carriable


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 2.0
	var phys := PhysicsMaterial.new()
	phys.friction = 1.0
	phys.bounce = 0.1
	physics_material_override = phys
	linear_damp = 0.6
	angular_damp = 6.0


func _ready() -> void:
	add_to_group("pickable")
	add_to_group("resource_items")

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.4, 0.5)
	col.shape = shape
	add_child(col)

	if kind == "lumber":
		add_child(Util.box(Vector3(1.0, 0.14, 0.28), Color(0.55, 0.4, 0.25), Vector3(0, -0.08, 0)))
		add_child(Util.box(Vector3(1.0, 0.14, 0.28), Color(0.6, 0.44, 0.28), Vector3(0, 0.08, 0.06)))
	else:
		add_child(Util.box(Vector3(0.5, 0.4, 0.45), Color(0.55, 0.54, 0.56)))
		add_child(Util.box(Vector3(0.3, 0.22, 0.28), Color(0.5, 0.49, 0.52), Vector3(0.05, 0.3, 0)))

	refresh_bundle()  # a bigger bundle looks bigger


## Re-fit the visual to the current count — called as a held bundle grows.
func refresh_bundle() -> void:
	scale = Vector3.ONE * clampf(1.0 + (count - 1) * 0.05, 1.0, 1.7)


func hover_text() -> String:
	var tail := " ×%d" % count if count > 1 else ""
	return "%s%s — drop it on a storehouse to store it" % [kind.capitalize(), tail]
