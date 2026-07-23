class_name MiracleOrb
extends RigidBody3D
## A conjured miracle, held in the divine hand until you decide where to
## cast it. Throw or place it; wherever it comes to rest (or strikes), it
## calls back into the MiracleManager to unleash its effect. One physics
## path for every placeable miracle — the same satisfying wind-up as the
## fireball.

const FUSE_SECONDS := 30.0

var miracle_name := "food"
var color := Color(1.0, 0.85, 0.3)
var manager: MiracleManager = null

var _armed := false
var _spent := false
var _momentum := Vector3.ZERO  # last real horizontal flight velocity of the throw


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	mass = 1.5
	contact_monitor = true
	max_contacts_reported = 4
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.1
	physics_material_override = phys


func _ready() -> void:
	add_to_group("pickable")
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	col.shape = shape
	add_child(col)

	add_child(Util.sphere(0.35, color, Vector3.ZERO, true))
	add_child(Util.sphere(0.22, color.lightened(0.4), Vector3.ZERO, true))

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 7.0
	add_child(light)

	body_entered.connect(_on_body_entered)
	get_tree().create_timer(FUSE_SECONDS).timeout.connect(_resolve)


func _physics_process(_delta: float) -> void:
	# Arms once genuinely thrown; a placed orb resolves when it settles.
	if not _armed and not freeze and linear_velocity.length() > 1.5:
		_armed = true
	if _armed and not freeze:
		# Remember the throw's heading (its last real horizontal speed) so the
		# effect can fly the way you flung it — birds, tornado, and the rest.
		var horiz := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		if horiz.length() > 1.0:
			_momentum = horiz
		if linear_velocity.length() < 0.4:
			_resolve()


func _on_body_entered(_body: Node) -> void:
	if _armed:
		_resolve()


func _resolve() -> void:
	if _spent or freeze:
		return
	_spent = true
	if manager != null and is_instance_valid(manager):
		manager.resolve(miracle_name, global_position, _momentum)
	queue_free()


func hover_text() -> String:
	return "%s (cast it where you will)" % miracle_name.capitalize().replace("_", " ")
