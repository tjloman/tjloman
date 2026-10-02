class_name Shade
extends RefCounted
## THE BAKED SHADOWS, from GDScript's side of the door.
##
## The work is in C++ (native/, built into bin/shade/): ShadowBaker turns a
## model into its shadow shape once, and ShadowSky moves the sun a step at a
## time and follows every light a miracle makes. This file is the only place
## GDScript talks to either, and it NEVER NAMES THEM — they are made through
## ClassDB by name — so the game parses and runs exactly as before on a machine
## where the library has not been built: `on()` is false and every call here
## does nothing.
##
## THREE THINGS A CALLER DOES:
##   cast / cast_parts  give a model its shadow, once, as it is built.
##   light              make a miracle's light. THE ONLY WAY to — tools/shade.py
##                      fails any miracle that makes an OmniLight3D itself, so
##                      every light a miracle ever emits throws shadows.
##   day                tell the sky the time (Main does, every frame).

## How often the sun moves, how long it eases into its new place, and the yaw
## of its arc — the same arc Main turns the DirectionalLight3D through.
const STEP_SECONDS := 4.0
const EASE_SECONDS := 0.5
const SUN_YAW := 20.0
## How much further a building's shadow is drawn than a walker's: it is bigger,
## and there are fewer of them.
const BUILDING_REACH := 1.6
const SHADER := preload("res://shaders/baked_shadow.gdshader")

static var _sky: Node = null
static var _baker: RefCounted = null
static var _skin: ShaderMaterial = null
## Hulls baked, by whatever the caller said identifies the shape: a crowd of
## villagers is one bake. A key that baked to nothing is kept as null.
static var _hulls := {}


## Make the sky under `parent`. False when the library is not there.
static func start(parent: Node) -> bool:
	if not ClassDB.class_exists(&"ShadowSky") or not ClassDB.class_exists(&"ShadowBaker"):
		_sky = null
		return false
	_sky = ClassDB.instantiate(&"ShadowSky") as Node
	_sky.name = "ShadowSky"
	_sky.set(&"day_seconds", GameState.DAY_SECONDS)
	_sky.set(&"step_seconds", STEP_SECONDS)
	_sky.set(&"ease_seconds", EASE_SECONDS)
	_sky.set(&"sun_yaw", SUN_YAW)
	parent.add_child(_sky)
	if _baker == null:
		_baker = ClassDB.instantiate(&"ShadowBaker") as RefCounted
	return true


static func on() -> bool:
	return _sky != null and is_instance_valid(_sky)


## The time of day, 0..1. The sky decides whether the sun has moved.
static func day(fraction: float) -> void:
	if on():
		_sky.call(&"set_day", fraction)


## A SHADOW FOR ONE MESH, laid at the foot of `owner` (where its origin is).
## `key` is what the shape is remembered by; the mesh itself if none, which is
## right for a mesh a crowd shares and harmless for one that is unique.
static func cast(owner: MeshInstance3D, reach: float, key: Variant = null) -> void:
	if not on() or owner == null or owner.mesh == null:
		return
	var k: Variant = key if key != null else owner.mesh.get_instance_id()
	if not _hulls.has(k):
		_hulls[k] = _baker.call(&"bake", owner.mesh)
	_lay(owner, _hulls[k], reach)


## A SHADOW FOR A THING MADE OF PARTS — a creature, a tree — every mesh under
## `root`, gathered into its space. Baked once per `key` when one is given.
static func cast_parts(root: Node3D, reach: float, key: Variant = null) -> void:
	if not on() or root == null:
		return
	if key == null or not _hulls.has(key):
		var hull: Variant = _baker.call(&"bake_points", _points_under(root))
		if key == null:
			_lay(root, hull, reach)
			return
		_hulls[key] = hull
	_lay(root, _hulls[key], reach)


## THE ONE DOOR FOR A MIRACLE'S LIGHT. It lights the world as an omni always
## did (never shadowed: one shadowed point light cost more than every other
## light in the night together), and from the frame it is made the sky follows
## it — its place, energy and range read live, so a tweened flash throws
## shadows that fade with it, and a freed one is forgotten.
static func light(parent: Node, color: Color, energy: float, reach: float,
		at := Vector3.ZERO) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.shadow_enabled = false
	lamp.position = at
	parent.add_child(lamp)
	if on():
		_sky.call(&"follow", lamp)
	return lamp


## How many lights threw shadows last frame, and how many the sky is following.
static func lights() -> Vector2i:
	if not on():
		return Vector2i.ZERO
	return Vector2i(int(_sky.call(&"get_burning")), int(_sky.call(&"get_alive")))


static func _lay(owner: Node3D, hull: Variant, reach: float) -> void:
	var mesh := hull as ArrayMesh
	if mesh == null:
		return          # flat, or nothing to it: casts nothing
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.set_meta(&"shadow", true)
	shadow.mesh = mesh
	shadow.material_override = _material()
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.visibility_range_end = reach
	owner.add_child(shadow)


static func _material() -> ShaderMaterial:
	if _skin == null:
		_skin = ShaderMaterial.new()
		_skin.shader = SHADER
	return _skin


## Every vertex of every mesh under `root`, in `root`'s space — worked out from
## the local transforms, so it is right before `root` is in the tree.
static func _points_under(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var part := n as MeshInstance3D
		if part.mesh == null or part.has_meta(&"shadow") or not part.visible:
			continue
		var place := part.transform
		var up := part.get_parent()
		while up != null and up != root:
			if up is Node3D:
				place = (up as Node3D).transform * place
			up = up.get_parent()
		for s in part.mesh.get_surface_count():
			var verts: PackedVector3Array = part.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				out.append(place * v)
	return out
