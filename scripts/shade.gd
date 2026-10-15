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
## SHADOWS OF TALL THINGS, CUT FINER. A hull is a handful of big triangles, and
## the shader sets only their CORNERS down on the ground: between them each is
## flat, so a tree's shadow thrown three times its height down a hillside cut
## straight through the hill and went under it in patches. The hull of anything
## at least TALL is cut, once, as it is baked, into a grid of triangles with no
## edge much over SPLIT metres AS IT LIES ON THE GROUND — where a metre of
## height is up to STRETCH metres long (the shader's LONGEST) — and at most
## CUTS_BY_TIER a side on the device's tier (MOST_CUTS on the best): a phone on
## LOW draws a quarter of the triangles HIGH does for the same forest. Every
## triangle is cut into the same number a side, so a cut edge meets the same
## cuts from the triangle across it and nothing gaps or doubles. Shorter things
## lie flat enough as they are, and a crowd of villagers is most of the shadows
## drawn.
const TALL := 3.0
const SPLIT := 3.0
const STRETCH := 3.0
const MOST_CUTS := 4
const CUTS_BY_TIER: Array[int] = [2, 3, MOST_CUTS]
## AND A THING THAT GROWS is cut for the size it will grow to: the creature is
## baked at a whelp's 2.5m and drawn at up to fifteen times that, so measured as
## baked its shadow was never cut at all, and a metre-long edge lay forty-five
## metres across the ground. There is one of it, so it may have more cuts.
const GROWN_CUTS_BY_TIER: Array[int] = [6, 9, 12]
const SHADER := preload("res://shaders/baked_shadow.gdshader")

static var _sky: Node = null
static var _baker: RefCounted = null
static var _skin: ShaderMaterial = null
## The land under the shadows, read a few rows a frame. See ShadeGround.
static var _ground: ShadeGround = null
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


## The time of day, 0..1. The sky decides whether the sun has moved; and the
## ground under the shadows is read on, a few rows a frame, on its own clock so
## the meter can see it.
static func day(fraction: float) -> void:
	if not on():
		return
	_sky.call(&"set_day", fraction)
	if _ground == null:
		_ground = ShadeGround.new()
	var clock := Ledger.swap(&"Shade:ground")
	_ground.step(_sky.get_tree().get_first_node_in_group("world_gen") as WorldGen,
		GameState.camera_focus, _sky.get_process_delta_time())
	Ledger.resume(clock)


## A SHADOW FOR ONE MESH, laid at the foot of `owner` (where its origin is).
## `key` is what the shape is remembered by; the mesh itself if none, which is
## right for a mesh a crowd shares and harmless for one that is unique.
static func cast(owner: MeshInstance3D, reach: float, key: Variant = null) -> void:
	if not on() or owner == null or owner.mesh == null:
		return
	var k: Variant = key if key != null else owner.mesh.get_instance_id()
	if not _hulls.has(k):
		_hulls[k] = _fine(_baker.call(&"bake", owner.mesh))
	_lay(owner, _hulls[k], reach)


## A SHADOW FOR A THING MADE OF PARTS — a creature, a tree — every mesh under
## `root`, gathered into its space. Baked once per `key` when one is given.
static func cast_parts(root: Node3D, reach: float, key: Variant = null,
		grows_to := 1.0) -> void:
	if not on() or root == null:
		return
	if key == null or not _hulls.has(key):
		var hull: Variant = _fine(_baker.call(&"bake_points", _points_under(root)), grows_to)
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


## A TALL HULL, CUT FINER (see TALL), measured at the size it will be drawn:
## `grows_to` times as baked. Anything else comes back as it was.
static func _fine(hull: Variant, grows_to := 1.0) -> Variant:
	var mesh := hull as ArrayMesh
	var big := maxf(grows_to, 1.0)
	if mesh == null or mesh.get_surface_count() == 0 or mesh.get_aabb().size.y * big < TALL:
		return hull
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var corners := points
	var order: Variant = arrays[Mesh.ARRAY_INDEX]
	if order is PackedInt32Array and not (order as PackedInt32Array).is_empty():
		corners = PackedVector3Array()
		for i: int in order:
			corners.append(points[i])
	var longest := 0.0
	for t in range(0, corners.size() - 2, 3):
		for e in 3:
			longest = maxf(longest, _on_the_ground(corners[t + e], corners[t + (e + 1) % 3]) * big)
	var most: int = (GROWN_CUTS_BY_TIER if big > 1.0 else CUTS_BY_TIER)[Quality.effective_tier()]
	var cuts := clampi(ceili(longest / SPLIT), 1, most)
	if cuts == 1:
		return hull
	# Each triangle a, b, c into cuts x cuts, wound as it was: the shader's
	# one-winding trick (see baked_shadow.gdshader) holds piece by piece. Every
	# point is its corners weighted by whole numbers over `cuts`, so a point on
	# an edge comes out to the bit the same from the triangle on either side of
	# it — no hairline seams — and each is kept once, its triangles indexing it.
	var fine := PackedVector3Array()
	var order_out := PackedInt32Array()
	var n := float(cuts)
	for t in range(0, corners.size() - 2, 3):
		var a := corners[t]
		var b := corners[t + 1]
		var c := corners[t + 2]
		var first := fine.size()
		for i in cuts + 1:
			for j in cuts + 1 - i:
				fine.append(a * (float(cuts - i - j) / n) + b * (float(i) / n) + c * (float(j) / n))
		for i in cuts:
			for j in cuts - i:
				var here := first + _grid_at(i, j, cuts)
				var up := first + _grid_at(i + 1, j, cuts)
				var over := first + _grid_at(i, j + 1, cuts)
				order_out.append_array([here, up, over])
				if j < cuts - i - 1:
					order_out.append_array([up, first + _grid_at(i + 1, j + 1, cuts), over])
	var made := []
	made.resize(Mesh.ARRAY_MAX)
	made[Mesh.ARRAY_VERTEX] = fine
	made[Mesh.ARRAY_INDEX] = order_out
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made)
	return out


## Where grid point i, j of a triangle cut `cuts` a side sits in its points:
## row i holds cuts + 1 - i of them.
static func _grid_at(i: int, j: int, cuts: int) -> int:
	return i * (cuts + 1) - ((i * (i - 1)) >> 1) + j


## How long an edge can lie on the ground once flattened: its run, or its rise
## stretched as a low sun stretches it, whichever is longer.
static func _on_the_ground(a: Vector3, b: Vector3) -> float:
	return maxf(Vector2(a.x - b.x, a.z - b.z).length(), absf(a.y - b.y) * STRETCH)


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
