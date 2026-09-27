class_name Weld
extends RefCounted
## ONE DRAW FOR A BUILDING, where it used to be one draw a PART.
##
## Everything in this game is built at runtime out of primitive meshes, and a
## primitive is a MeshInstance3D with its own material: a house is a
## foundation, walls, a roof, a door and two windows — six draw calls — and a
## town of a hundred and forty houses is eight hundred of them before a single
## villager is drawn. On a phone the draw call is the thing that decides the
## framerate, not the triangle: the screenshots were at fifteen hundred.
##
## So once a building has been assembled, its still parts are WELDED: every
## plain part (one flat colour, no texture, no glow, no transparency) goes into
## ONE surface that takes its colour from the vertices, with one material shared
## by every welded building in the game. Parts wearing a material the owner will
## change later — a window that lights at night — are welded together into a
## surface of their own that keeps that material, so the glow still works and
## the two panes are still one draw.
##
## WHAT IS NEVER TOUCHED: a part the owner holds a reference to (pass it in
## `keep`), a part with children (a lamp with its light), a part with a script,
## a custom model, and anything that is not a plain one-surface mesh. Leaving a
## part alone is always safe; welding a part somebody else still reaches for
## would free it out from under them.

## The one material every welded surface of plain parts shares. Vertex colours
## are in the same sRGB space `albedo_color` was, so the colours come out the
## same as the separate parts they replace.
static var _plain: StandardMaterial3D = null
## Meshes welded once and shared by everything that asked with the same key.
static var _shared := {}


## Weld the still parts directly under `root`. Returns the welded node, or null
## if there was nothing to gain (fewer parts than surfaces it would make).
static func statics(root: Node3D, keep: Array = [], mutable: Array = []) -> MeshInstance3D:
	var plain_parts: Array[MeshInstance3D] = []
	var groups := {}                 # a mutable material -> the parts wearing it
	for child in root.get_children():
		var part := child as MeshInstance3D
		if part == null or keep.has(part) or not _still(part):
			continue
		var skin := _skin_of(part)
		if skin == null:
			continue
		if mutable.has(skin):
			if not groups.has(skin):
				groups[skin] = []
			(groups[skin] as Array).append(part)
		elif _is_plain(skin):
			plain_parts.append(part)
	var surfaces := (1 if not plain_parts.is_empty() else 0) + groups.size()
	var parts := plain_parts.size()
	for skin: Material in groups:
		parts += (groups[skin] as Array).size()
	if parts <= surfaces:
		return null                  # nothing to gain
	var mesh := ArrayMesh.new()
	if not plain_parts.is_empty():
		_add_surface(mesh, plain_parts, true)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _plain_skin())
	for skin: Material in groups:
		var worn: Array[MeshInstance3D] = []
		worn.assign(groups[skin])
		_add_surface(mesh, worn, false)
		mesh.surface_set_material(mesh.get_surface_count() - 1, skin)
	var welded := MeshInstance3D.new()
	welded.mesh = mesh
	var first: MeshInstance3D = plain_parts[0] if not plain_parts.is_empty() \
		else (groups.values()[0] as Array)[0]
	welded.cast_shadow = first.cast_shadow
	welded.visibility_range_end = first.visibility_range_end
	welded.visibility_range_end_margin = first.visibility_range_end_margin
	root.add_child(welded)
	for part in plain_parts:
		_drop(root, part)
	for skin: Material in groups:
		for part: MeshInstance3D in groups[skin]:
			_drop(root, part)
	return welded


## ONE MESH FOR A THING THERE ARE HUNDREDS OF, welded once per `key` and
## shared. `parts` are plain, unparented MeshInstance3Ds placed where they sit
## on the body; they are freed here whether or not the key was already known.
## A villager is a capsule and a head in one of twelve shirt colours, so a
## whole crowd is twelve meshes and one material.
static func shared(key: String, parts: Array[MeshInstance3D]) -> Mesh:
	var mesh: Mesh = _shared.get(key)
	if mesh == null:
		var welded := ArrayMesh.new()
		_add_surface(welded, parts, true)
		welded.surface_set_material(0, _plain_skin())
		_shared[key] = welded
		mesh = welded
	for part in parts:
		part.free()
	return mesh


static func _plain_skin() -> StandardMaterial3D:
	if _plain == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		_plain = Util.lit(m)
	return _plain


## A part that can be baked into its parent for good: a plain mesh with one
## surface, nothing hanging off it, no behaviour of its own.
static func _still(part: MeshInstance3D) -> bool:
	return part.get_script() == null and part.get_child_count() == 0 \
		and part.mesh != null and part.mesh.get_surface_count() == 1 \
		and part.visible


static func _skin_of(part: MeshInstance3D) -> Material:
	if part.material_override != null:
		return part.material_override
	return part.mesh.surface_get_material(0)


## ONE FLAT COLOUR, which is all a vertex colour can carry.
static func _is_plain(skin: Material) -> bool:
	var m := skin as StandardMaterial3D
	return m != null and m.albedo_texture == null and not m.emission_enabled \
		and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
		and m.albedo_color.a >= 1.0 and not m.vertex_color_use_as_albedo


static func _add_surface(mesh: ArrayMesh, parts: Array[MeshInstance3D], tint: bool) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	for part in parts:
		var arrays := part.mesh.surface_get_arrays(0)
		var place := part.transform
		var bend := place.basis.inverse().transposed()
		var color := (_skin_of(part) as StandardMaterial3D).albedo_color if tint else Color.WHITE
		var base := verts.size()
		var their: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v: Vector3 in their:
			verts.append(place * v)
			colors.append(color)
		var their_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for n: Vector3 in their_normals:
			norms.append((bend * n).normalized())
		var their_uvs = arrays[Mesh.ARRAY_TEX_UV]
		if their_uvs == null:
			for i in their.size():
				uvs.append(Vector2.ZERO)
		else:
			var typed_uvs: PackedVector2Array = their_uvs
			uvs.append_array(typed_uvs)
		var order = arrays[Mesh.ARRAY_INDEX]
		if order == null:
			for i in their.size():
				index.append(base + i)
		else:
			var their_order: PackedInt32Array = order
			for i: int in their_order:
				index.append(base + i)
	var welded := []
	welded.resize(Mesh.ARRAY_MAX)
	welded[Mesh.ARRAY_VERTEX] = verts
	welded[Mesh.ARRAY_NORMAL] = norms
	welded[Mesh.ARRAY_TEX_UV] = uvs
	welded[Mesh.ARRAY_COLOR] = colors
	welded[Mesh.ARRAY_INDEX] = index
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, welded)


## Gone now, not at the end of the frame: a part left standing for one frame
## under its own welded copy is a frame drawn twice.
static func _drop(root: Node3D, part: MeshInstance3D) -> void:
	root.remove_child(part)
	part.free()
