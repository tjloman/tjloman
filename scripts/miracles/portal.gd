class_name Portal
extends Node3D
## A standing gate in the world. Portals are cast in PAIRS: the first hangs
## open and waiting, the second links to it — and from then on anything that
## walks, wanders or is thrown into one steps out of the other.
##
## On a world this sprawling, this is the difference between a village on the
## far shore being a curiosity and being part of your kingdom: villagers,
## livestock, your creature and your own hand all travel through.

const RADIUS := 2.2
const COOLDOWN := 1.5   # seconds a traveller is ignored after arriving

var twin: Portal = null

var _ring: MeshInstance3D
var _area: Area3D
var _spin := 0.0
var _recent := {}       # instance id -> time it may travel again


func _ready() -> void:
	add_to_group("portals")
	set_meta("hover_name", "Portal")

	# The arch: a bright ring standing upright, with a shimmer inside it.
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.28
	torus.outer_radius = RADIUS
	torus.rings = 32
	torus.ring_segments = 6
	_ring = Util.mesh_node(torus, Color(0.55, 0.8, 1.0), Vector3(0, RADIUS, 0), true)
	_ring.rotation_degrees.x = 90.0
	add_child(_ring)

	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS - 0.3
	disc.bottom_radius = RADIUS - 0.3
	disc.height = 0.05
	var shimmer := Util.mesh_node(disc, Color(0.4, 0.7, 1.0, 0.4), Vector3(0, RADIUS, 0), true)
	shimmer.rotation_degrees.x = 90.0
	add_child(shimmer)

	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.75, 1.0)
	light.light_energy = 2.0
	light.omni_range = 9.0
	light.position = Vector3(0, RADIUS, 0)
	add_child(light)

	# Anything that can walk or be thrown may travel: units and props alike.
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2 | 4
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	shape.position = Vector3(0, RADIUS, 0)
	_area.add_child(shape)
	add_child(_area)


## Tie two gates together, both ways.
func link(other: Portal) -> void:
	twin = other
	other.twin = self


func _process(delta: float) -> void:
	_spin += delta * 1.2
	_ring.rotation_degrees.y = rad_to_deg(_spin)
	if twin == null or not is_instance_valid(twin):
		return
	var now := Time.get_ticks_msec() / 1000.0
	for body in _area.get_overlapping_bodies():
		_send(body, now)


## Step a traveller out of the far gate, just clear of it so it doesn't
## immediately fall back through.
func _send(body: Node3D, now: float) -> void:
	if not is_instance_valid(body):
		return
	var id := body.get_instance_id()
	if float(_recent.get(id, 0.0)) > now:
		return
	# The far side marks the traveller too, so it doesn't bounce straight back.
	twin._recent[id] = now + COOLDOWN
	_recent[id] = now + COOLDOWN
	var out := twin.global_position + Vector3(0, 0.6, 0) \
		+ Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
	body.global_position = out
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	SoundBank.play_at("coo", out, 0.0, 0.35)


func hover_text() -> String:
	if twin == null or not is_instance_valid(twin):
		return "Portal — open, waiting for its twin"
	return "Portal — step through to travel"
