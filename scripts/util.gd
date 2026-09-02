class_name Util
## Static helpers for building ugly-but-honest placeholder visuals from primitives.
##
## Two families of builders:
##   mat/box/sphere/...   – a FRESH mesh + material each call. Use when the
##                          part gets recoloured, tinted, or reshaped at
##                          runtime (villagers, the hand, tinted orbs).
##   shared_mat/lite_*    – POOLED, low-poly resources shared across every
##                          identical part. Use for the static wilderness
##                          clutter (trees, bushes, rocks, flowers): hundreds
##                          of them then cost a handful of meshes/materials
##                          instead of thousands, which is what kept budget
##                          phones from drowning as chunks stream in.

# Pools keyed by their defining parameters. Never mutate a resource fetched
# from here — it is shared by every part that asked for the same thing.
static var _mesh_pool := {}
static var _mat_pool := {}
static var _glow: ImageTexture = null   # the soft dot every torch is drawn with


static func mat(color: Color, emission := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = 1.5
	return m


static func mesh_node(mesh: Mesh, color: Color, pos := Vector3.ZERO, emission := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, emission)
	mi.position = pos
	return mi


static func box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return mesh_node(m, color, pos)


## The default SphereMesh is 64x32 segments — ~4,000 triangles for a marble.
## In a blocky-primitive art style that detail is invisible, but multiplied
## across every villager limb, animal, tree, and berry it was a multi-million
## triangle opening frame that timed out (TDR'd) budget GPUs like the Adreno
## 619. 16x8 reads identically at this scale for a ~16x triangle cut.
static func sphere(radius: float, color: Color, pos := Vector3.ZERO, emission := false) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	return mesh_node(m, color, pos, emission)


static func capsule(radius: float, height: float, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 4
	return mesh_node(m, color, pos)


static func cylinder(
		radius: float, height: float, color: Color,
		pos := Vector3.ZERO, emission := false) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 0
	return mesh_node(m, color, pos, emission)


static func prism(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return mesh_node(m, color, pos)


## Pooled, low-poly resources ------------------------------------------------
##
## Everything below shares meshes and materials across identical parts and
## uses a fraction of the default tessellation — a 5cm berry does not need a
## 64x32 sphere. The saving is per-CHUNK: the same 8 materials and a dozen
## meshes serve every tree, bush, rock, and flower in the world.

## A material shared by every part of this exact colour. Do NOT recolour it.
static func shared_mat(color: Color, emission := false) -> StandardMaterial3D:
	var key := "%s|%s" % [color, emission]
	var m: StandardMaterial3D = _mat_pool.get(key)
	if m == null:
		m = mat(color, emission)
		_mat_pool[key] = m
	return m


## A SPECK, for particles: two triangles that always face the camera.
##
## This exists because of a bug worth remembering. `SphereMesh.new()` defaults
## to 64 radial segments by 32 rings — 4,224 triangles — and every particle mesh
## in this project set only its radius and material, leaving those defaults in
## place. A rain cloud of 400 droplets was therefore drawing 1,689,600 triangles
## for a shower of four-centimetre specks, each of them a couple of pixels
## across. Three overlapping showers came to five million. That is many times a
## mid-range phone's entire per-frame budget, spent entirely on geometry no one
## can see.
##
## A billboarded quad is two triangles and looks better, because it always
## faces the camera and can be stretched into a streak. The mesh and its
## material are both pooled, so casting rain a hundred times allocates nothing.
static func speck_mesh(width: float, height: float, color: Color,
		emission := false) -> QuadMesh:
	var key := "speck|%.3f|%.3f|%s|%s" % [width, height, color, emission]
	var m: QuadMesh = _mesh_pool.get(key)
	if m != null:
		return m
	m = QuadMesh.new()
	m.size = Vector2(width, height)
	var skin := mat(color, emission)
	# Unshaded and billboarded: a raindrop needs no lighting, and turning to
	# face the camera is what makes two triangles read as a droplet at all.
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	skin.billboard_keep_scale = true
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin.disable_receive_shadows = true
	m.material = skin
	_mesh_pool[key] = m
	return m


## Radius is bucketed to 5cm so a spread of near-identical sizes still shares
## one mesh; segments stay low because these are always small and distant-ish.
static func _pooled_sphere_mesh(radius: float, segs: int) -> SphereMesh:
	var r := snappedf(radius, 0.05)
	var key := "sph|%.2f|%d" % [r, segs]
	var m: SphereMesh = _mesh_pool.get(key)
	if m == null:
		m = SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = segs
		m.rings = maxi(int(segs / 2.0), 3)
		_mesh_pool[key] = m
	return m


static func _pooled_cylinder_mesh(
		top: float, bottom: float, height: float, segs: int) -> CylinderMesh:
	var key := "cyl|%.2f|%.2f|%.2f|%d" % [
		snappedf(top, 0.05), snappedf(bottom, 0.05), snappedf(height, 0.1), segs]
	var m: CylinderMesh = _mesh_pool.get(key)
	if m == null:
		m = CylinderMesh.new()
		m.top_radius = snappedf(top, 0.05)
		m.bottom_radius = snappedf(bottom, 0.05)
		m.height = snappedf(height, 0.1)
		m.radial_segments = segs
		m.rings = 0
		_mesh_pool[key] = m
	return m


static func _pooled_box_mesh(size: Vector3) -> BoxMesh:
	var key := "box|%.2f|%.2f|%.2f" % [
		snappedf(size.x, 0.02), snappedf(size.y, 0.02), snappedf(size.z, 0.02)]
	var m: BoxMesh = _mesh_pool.get(key)
	if m == null:
		m = BoxMesh.new()
		m.size = Vector3(
			snappedf(size.x, 0.02), snappedf(size.y, 0.02), snappedf(size.z, 0.02))
		_mesh_pool[key] = m
	return m


## Box sharing mesh+material with every twin — no tessellation to lower, but
## same-species animals and same-shirt villagers then collapse to a handful of
## meshes/materials the renderer can batch, instead of one unique pair each.
static func lite_box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _pooled_box_mesh(size)
	mi.material_override = shared_mat(color)
	mi.position = pos
	return mi


## Low-poly sphere sharing mesh+material with every twin. For static clutter.
static func lite_sphere(radius: float, color: Color, pos := Vector3.ZERO, segs := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _pooled_sphere_mesh(radius, segs)
	mi.material_override = shared_mat(color)
	mi.position = pos
	return mi


static func _pooled_capsule_mesh(radius: float, height: float, segs: int) -> CapsuleMesh:
	var key := "cap|%.2f|%.2f|%d" % [snappedf(radius, 0.02), snappedf(height, 0.05), segs]
	var m: CapsuleMesh = _mesh_pool.get(key)
	if m == null:
		m = CapsuleMesh.new()
		m.radius = snappedf(radius, 0.02)
		m.height = snappedf(height, 0.05)
		m.radial_segments = segs
		m.rings = maxi(int(segs / 4.0), 2)
		_mesh_pool[key] = m
	return m


## Low-poly capsule sharing mesh+material — villager torsos of the same
## (quantised) shirt colour then share one mesh and one material.
static func lite_capsule(
		radius: float, height: float, color: Color, pos := Vector3.ZERO, segs := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _pooled_capsule_mesh(radius, height, segs)
	mi.material_override = shared_mat(color)
	mi.position = pos
	return mi


## Low-poly cylinder/cone (top=0 gives a cone) sharing mesh+material.
static func lite_cylinder(
		radius: float, height: float, color: Color, pos := Vector3.ZERO,
		top := -1.0, segs := 8, emission := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _pooled_cylinder_mesh(radius if top < 0.0 else top, radius, height, segs)
	mi.material_override = shared_mat(color, emission)
	mi.position = pos
	return mi


## A flower reduced to two crossed vertical quads — the classic billboard
## trick. White-vertexed so a MultiMesh's per-instance colour tints each
## bloom. Pooled: one mesh serves every flower in the world.
static func blossom_mesh() -> ArrayMesh:
	var m: ArrayMesh = _mesh_pool.get("blossom")
	if m != null:
		return m
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.11
	var h := 0.26
	for ang: float in [0.0, PI / 2.0]:
		var dx := cos(ang) * w
		var dz := sin(ang) * w
		var quad := [
			Vector3(-dx, 0.02, -dz), Vector3(dx, 0.02, dz),
			Vector3(dx, h, dz), Vector3(-dx, h, -dz)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color.WHITE)
			st.add_vertex(quad[idx])
	st.generate_normals()
	m = st.commit()
	_mesh_pool["blossom"] = m
	return m


## Shared material for billboard blossoms: double-sided (quads seen from
## both faces), matte, its white albedo modulated by each instance's colour.
static func blossom_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = _mat_pool.get("blossom")
	if m != null:
		return m
	m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	_mat_pool["blossom"] = m
	return m


## A small clinging flame for a burning creature/villager/animal: a few
## emissive cones, no light (so a whole village ablaze stays cheap on mobile).
## `top` is roughly how tall the body is.
static func small_flame(top := 1.4) -> Node3D:
	var fire := Node3D.new()
	for i in 3:
		fire.add_child(lite_cylinder(
			0.16, 0.55, Color(1.0, 0.5, 0.12),
			Vector3(randf_range(-0.14, 0.14), top * 0.35 + i * 0.22, randf_range(-0.14, 0.14)),
			0.0, 6, true))
	return fire


## DROP EVERY FREED OBJECT from a list of nodes, in place.
##
## This looks like a job for `items.filter(is_instance_valid)`, and half the
## codebase used to do exactly that. It is a TRAP: `filter()` hands back a
## plain `Array` whatever it was called on, so assigning the result back to an
## `Array[Farm]` fails — not at parse time, not in the editor, but on the frame
## that line first runs, with "Trying to assign an array of type Array to a
## variable of type Array[Farm]". It cost this project a shipped miracle that
## could not be cast, and there were seven more of it waiting.
##
## Pruning IN PLACE sidesteps the whole question: the array keeps its type
## because it is never reassigned, and nothing is allocated. Walk backwards so
## removing an element cannot skip the next one. (tools/check_calls.py rejects
## the filter() form now, so it cannot come back.)
static func prune(items: Array) -> void:
	for i in range(items.size() - 1, -1, -1):
		if not is_instance_valid(items[i]):
			items.remove_at(i)


## A FLAME, for a MultiMesh: one billboarded quad with a soft round glow on it,
## ADDITIVE so it pours light into a dark screen instead of merely being a
## bright square in it, and taking its colour per instance so every torch in a
## town can flicker on its own out of a single draw call.
##
## Shared by every torch in the world (see Village), which is why it is pooled
## and why the little texture is generated once and kept.
static func flame_mesh(width: float, height: float) -> QuadMesh:
	var key := "flame|%.3f|%.3f" % [width, height]
	var m: QuadMesh = _mesh_pool.get(key)
	if m != null:
		return m
	m = QuadMesh.new()
	m.size = Vector2(width, height)
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = _glow_texture()
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	skin.billboard_keep_scale = true
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin.disable_receive_shadows = true
	skin.vertex_color_use_as_albedo = true   # per-instance colour and flicker
	skin.no_depth_test = false
	m.material = skin
	_mesh_pool[key] = m
	return m


## A soft round glow, brightest in the middle, generated once. 32 pixels is
## plenty for something that is never more than a few pixels wide on screen.
static func _glow_texture() -> ImageTexture:
	if _glow != null:
		return _glow
	var size := 32
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var mid := (size - 1) * 0.5
	for y in size:
		for x in size:
			var u := (x - mid) / mid
			var v := (y - mid) / mid
			# Taller than it is wide, so the flame is a teardrop not a ball.
			var d := sqrt(u * u * 1.35 + v * v * 0.75)
			var a := smoothstep(1.0, 0.0, d)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	_glow = ImageTexture.create_from_image(img)
	return _glow


## Distance culling: every renderable under `root` stops drawing past
## `end_dist` metres (with a soft margin). Distance fog hides the cutoff.
## Physics and gameplay are untouched — only the GPU work goes away.
static func apply_lod(root: Node, end_dist: float) -> void:
	if end_dist <= 0.0:
		return
	# The root itself may BE the renderable (a MultiMeshInstance3D); its mesh
	# children are the renderables for the entity bodies. Cover both.
	var targets := root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		targets.append(root)
	for c in targets:
		var gi := c as GeometryInstance3D
		gi.visibility_range_end = end_dist
		gi.visibility_range_end_margin = end_dist * 0.15


## Simulation level-of-detail: how many physics frames an entity at `pos` may
## skip between full updates, by distance from the camera's focus. Keeps a big
## streamed world cheap — a crowd the player isn't looking at ticks coarsely
## (still alive, just less often), while everything nearby runs full-rate.
static func sim_stride(pos: Vector3) -> int:
	var f := GameState.camera_focus
	var dx := pos.x - f.x
	var dz := pos.z - f.z
	var d2 := dx * dx + dz * dz
	# A struggling device thins the far half of the world further still. Distant
	# villagers and beasts are the cheapest thing to slow down and the least
	# noticeable, so they take the first cut (see Quality.sim_relief).
	var relief := Quality.sim_relief()
	if d2 > 260.0 * 260.0:
		return 10 * relief
	if d2 > 130.0 * 130.0:
		return 4 * relief
	return 1 if relief == 1 else 2


## Simple billboard status label used above villagers/creature heads.
## Each is a transparent, camera-facing text quad — cheap alone, but a crowd
## of them is real overdraw on a tiled mobile GPU. So it only renders up
## close (past ~34m it stops drawing); far-off crowds cost nothing for text.
static func status_label(text := "", pixel_size := 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = pixel_size
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 48
	l.outline_size = 12
	l.modulate = Color(1, 1, 1, 0.95)
	l.visibility_range_end = 34.0
	l.visibility_range_end_margin = 6.0
	return l
