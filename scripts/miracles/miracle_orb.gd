class_name MiracleOrb
extends RigidBody3D
## A conjured miracle, held in the divine hand until you decide where to
## cast it. Throw or place it; wherever it comes to rest (or strikes), it
## calls back into the MiracleManager to unleash its effect. One physics
## path for every placeable miracle — the same satisfying wind-up as the
## fireball.

const FUSE_SECONDS := 30.0

var miracle_name := "food"
## How MUCH of it. One rune of water is a sprinkle and three is a deluge, and
## the difference rides here rather than needing a separate miracle for every
## rung of the ladder.
var potency := 1.0
var color := Color(1.0, 0.85, 0.3)
var manager: MiracleManager = null

var _armed := false
var _spent := false
var _momentum := Vector3.ZERO  # last real horizontal flight velocity of the throw
## HOW MUCH FUSE IS LEFT, and it burns only while the orb is LOOSE.
##
## It was a SceneTree timer, which ran down in your hand — and `_resolve`
## refuses to fire in the grip, so an orb carried around for half a minute
## while you looked for the right spot passed its fuse, returned quietly, and
## became a dead glowing ball that could never be cast at all. The prayer was
## spent. Nothing said anything. A fuse is how long a thrown working has to
## find something, not a limit on how long a god may hold one.
var _fuse_left := FUSE_SECONDS


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
	add_to_group(Affords.PICKABLE)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	col.shape = shape
	add_child(col)

	# THE ORB RESISTS THE KNIFE MORE THAN ANYTHING ELSE CARRIED, because it is
	# the only one routinely held a metre from the camera, and a glowing ball
	# with too few segments reads as a cut gem. Eight round the shell is where
	# the outline stops announcing itself; the core inside it can be coarser,
	# since it is seen through a bright translucent shell. 576 -> 128.
	add_child(Util.lite_sphere(0.35, color, Vector3.ZERO, 8, true))
	add_child(Util.lite_sphere(0.20, color.lightened(0.4), Vector3.ZERO, 6, true))

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 7.0
	add_child(light)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	Ledger.open(&"MiracleOrb")
	if freeze:
		return  # in the grip: the fuse does not burn and nothing resolves
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_resolve()
		return
	# Arms once genuinely thrown; a placed orb resolves when it settles.
	if not _armed and linear_velocity.length() > 1.5:
		_armed = true
	if _armed:
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
		manager.resolve(miracle_name, global_position, _momentum, potency)
	queue_free()


## ANOTHER OF EXACTLY THIS ONE, unthrown. What makes an orb volley — Volley
## asks every thrown body for this and for nothing else, so a working the
## player invented tomorrow comes through here without that file learning it.
func another() -> MiracleOrb:
	var twin := MiracleOrb.new()
	twin.miracle_name = miracle_name
	twin.potency = potency
	twin.color = color
	twin.manager = manager
	return twin


func hover_text() -> String:
	var strength := ""
	if potency > 1.4:
		strength = "  ·  %s" % ("overwhelming" if potency > 2.4 else "strong")
	return "%s%s (cast it where you will)" % [
		miracle_name.capitalize().replace("_", " "), strength]
