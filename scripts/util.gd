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

## Sweep the dead out of the register once it has grown by this much. Without
## it a long session walking across the world leaves a row per chunk material
## ever made, all of them empty.
const SWEEP_EVERY := 512

# Pools keyed by their defining parameters. Never mutate a resource fetched
# from here — it is shared by every part that asked for the same thing.
static var _mesh_pool := {}
static var _mat_pool := {}
static var _glow: ImageTexture = null   # the soft dot every torch is drawn with
static var _dot: ImageTexture = null    # and the round one every mark is

## CEL SHADING, AND WHY IT IS A REGISTER RATHER THAN A SWITCH.
##
## There is no one material in this game. There is water that goes opaque on a
## budget phone, foliage on scissor-cut billboards, crops coloured per vertex,
## critters that are deliberately unlit, and a hundred ordinary painted parts —
## seventeen places in all, each with settings it needs. None of them can be
## funnelled through one builder without losing what makes it itself.
##
## So every material made anywhere passes through `lit` on its way out, which
## writes down a WEAK reference to it and the modes it was born with. Turning
## cel shading on walks that register and re-marks everything alive; turning it
## off puts each material back the way IT was, rather than back to a default
## this file guessed at. Two things follow that are worth saying out loud:
##
##   THE REFERENCES ARE WEAK because terrain streams. A chunk two hundred
##   metres behind you is freed, and a register holding it by the hand would
##   keep every material of every chunk you ever walked through alive for the
##   session. It sweeps itself as it grows, and again whenever it is walked.
##
##   AND NOTHING UNLIT IS TOUCHED. A critter and a storm cloud are UNSHADED on
##   purpose; there is no lighting on them to band, and "cel shading" that
##   quietly re-lit them would be a different bug for each.
##
## WHAT IS NOT YET CONFIRMED, and must be before this is called done: whether
## the Mobile renderer this game uses honours StandardMaterial3D's built-in
## toon diffuse and specular modes at all. Forward+ does. If Mobile ignores
## them, the fix is `_cel_one` and nothing else — the register, the sweep, the
## toggle and the saving are the same either way, which is why it is built like
## this rather than around a shader that may not be needed.
static var _painted: Array = []
static var _cel := false
static var _since_sweep := 0


## EVERY MATERIAL IN THE GAME GOES THROUGH HERE on its way out — see the note
## by `_painted`. It is one line at each of the seventeen places that build one,
## and it is what makes cel shading a thing that can be turned on while you are
## looking at the world rather than a thing that waits for a reload.
static func lit(m: StandardMaterial3D) -> StandardMaterial3D:
	# What it was born as. Restoring THIS rather than a named default means a
	# part that deliberately chose its own lighting keeps it, and that this file
	# never has to be right about what the engine's defaults are called.
	_painted.append([weakref(m), m.diffuse_mode, m.specular_mode])
	_since_sweep += 1
	if _since_sweep >= SWEEP_EVERY:
		_sweep()
	if _cel:
		_cel_one(m, true, m.diffuse_mode, m.specular_mode)
	return m


## ON OR OFF, NOW, for everything alive. Dead entries go while we are walking
## the register anyway.
static func cel_shading(on: bool) -> void:
	_cel = on
	var live := []
	for row: Array in _painted:
		var m := (row[0] as WeakRef).get_ref() as StandardMaterial3D
		if m == null:
			continue
		live.append(row)
		_cel_one(m, on, row[1], row[2])
	_painted = live
	_since_sweep = 0


static func cel_is_on() -> bool:
	return _cel


## How many materials are being kept marked, for the readouts — a register that
## only ever grows is the leak this was written to avoid.
static func painted_count() -> int:
	return _painted.size()


## THE ONE PLACE THE LOOK IS DECIDED. Toon diffuse cuts the light into bands and
## toon specular does the same to the highlight; roughness is left alone on
## purpose, because it is what softens the edge of the band and the world
## already varies it from matte ground to wet stone.
static func _cel_one(m: StandardMaterial3D, on: bool, was_diffuse: int,
		was_specular: int) -> void:
	if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON if on else was_diffuse
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON if on else was_specular


static func _sweep() -> void:
	var live := []
	for row: Array in _painted:
		if (row[0] as WeakRef).get_ref() != null:
			live.append(row)
	_painted = live
	_since_sweep = 0


static func mat(color: Color, emission := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = 1.5
	return lit(m)


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
	m.material = lit(skin)
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


## Low-poly sphere sharing mesh+material with every twin. For static clutter,
## and for anything handheld whose radius is a round multiple of the 5cm bucket
## `_pooled_sphere_mesh` snaps to — off a bucket, use node scale to get the
## silhouette rather than a radius that mints a mesh nothing else will share.
static func lite_sphere(radius: float, color: Color, pos := Vector3.ZERO,
		segs := 8, emission := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _pooled_sphere_mesh(radius, segs)
	mi.material_override = shared_mat(color, emission)
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


## AN UP VECTOR THAT IS NOT THE WAY YOU ARE LOOKING.
##
## `look_at` needs an up that is not parallel to the aim, and Godot says so —
## loudly, once per call, with a stack trace. A rope drawn between the hand and
## the thing hanging under it is exactly vertical whenever the hand is directly
## above what it is carrying, which is most of the time anyone carries anything,
## so a single held object filled ten minutes of log with ninety-five identical
## warnings. Any rope, beam or bolt drawn between two arbitrary points wants
## this rather than a bare Vector3.UP.
static func steady_up(from: Vector3, to: Vector3) -> Vector3:
	var aim := to - from
	if aim.length_squared() < 0.000001:
		return Vector3.UP
	return Vector3.UP if absf(aim.normalized().dot(Vector3.UP)) < 0.999 \
		else Vector3.FORWARD


## THE ONE MATERIAL EVERY CHUNK OF GROUND IS DRAWN WITH. Vertex colour as
## albedo, fully rough, nothing else — which is to say it was identical on all
## of them already, and every chunk was building its own copy of it.
##
## That mattered little at a 7x7 ring and matters at a 17x17 one: distinct
## materials are distinct uniform sets, so two chunks with their own copies
## cannot be batched into one another's draw, and the renderer re-binds state
## between every pair. Sharing one instance is the difference between a couple
## of hundred material bindings a frame and one.
static func ground_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = _mat_pool.get("ground")
	if m != null:
		return m
	m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	_mat_pool["ground"] = lit(m)
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
	_mat_pool["blossom"] = lit(m)
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
	m.material = lit(skin)
	_mesh_pool[key] = m
	return m


## A DOT, for anything that is only ever a dot: one billboarded quad with a
## soft round edge, alpha-blended, taking its colour and its fade per instance.
##
## A bead of the sling's aiming arc used to be a SphereMesh, twenty-six of them,
## 48 triangles each and a draw call each, for a mark that is eight pixels
## across and never seen from any angle but square on. A quad that always faces
## the camera is two triangles and reads better, because its edge is soft
## instead of faceted — and through a MultiMesh the whole arc is one draw.
##
## Alpha rather than the additive blend `flame_mesh` uses: a torch pours light
## into a dark screen, an aiming mark sits on top of daylight and wants to stay
## the colour it was given.
static func dot_mesh(size: float, color := Color.WHITE) -> QuadMesh:
	var key := "dot|%.3f|%s" % [size, color]
	var m: QuadMesh = _mesh_pool.get(key)
	if m != null:
		return m
	m = QuadMesh.new()
	m.size = Vector2(size, size)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = color
	skin.albedo_texture = _dot_texture()
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	skin.billboard_keep_scale = true
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin.disable_receive_shadows = true
	skin.vertex_color_use_as_albedo = true   # per-instance colour AND fade
	m.material = lit(skin)
	_mesh_pool[key] = m
	return m


## One dot as a node, for the single marks that are not worth a MultiMesh —
## a fish's eye, a berry, anything that is a coloured full stop. Mesh and
## material are pooled by size and colour, so a granary full of fish shares
## one of each. No `material_override`: the billboarding lives in the mesh's
## own material, and overriding it is how you get a flat square.
static func dot_node(size: float, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = dot_mesh(size, color)
	mi.position = pos
	return mi


## The dot's own texture: round, unlike the flame's teardrop, and squared at
## the edge so it has a defined rim rather than fading into nothing.
static func _dot_texture() -> ImageTexture:
	if _dot != null:
		return _dot
	var size := 32
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var mid := (size - 1) * 0.5
	for y in size:
		for x in size:
			var u := (x - mid) / mid
			var v := (y - mid) / mid
			var a := smoothstep(1.0, 0.72, sqrt(u * u + v * v))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_dot = ImageTexture.create_from_image(img)
	return _dot


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


## HOW BIG A THING IS, from its middle to its edge, in metres on the flat.
##
## EVERYTHING IN THIS GAME MEASURED TO A BUILDING'S ORIGIN, and buildings are
## bigger than the reaches that were being measured. A blow reached 2.4m, a
## gout of flame 3.2m, a held furnace 2.4m — and a longhouse's far corner is
## 3.67m from its middle, a granary's rim is 3.4m, and a jetty's deck runs out
## to 7.6m from the root standing on the shore.
##
## So huts burned and took damage, and longhouses, granaries, schools and docks
## were simply immune: you hit the wall, and the wall was further from the
## middle of the building than the blow could reach. It reads exactly like "the
## damage model is broken" and every number in it was fine.
##
## Read off whatever collision shape the thing already has, so nothing had to
## grow a `footprint()` method, and kept in a meta because a building does not
## change size.
static func bulk_of(what_given: Variant) -> float:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(what_given):
		return 0.0
	var what := what_given as Node3D
	if what == null or not is_instance_valid(what):
		return 0.0
	# `has_meta` AND NOT A NULL DEFAULT. Godot's `get_meta(name, default)`
	# returns the default only when the default IS NOT NULL — passing `null` is
	# indistinguishable from passing nothing, and it pushes an error for every
	# object that has not been measured yet. Eighty-two of them in one session,
	# from a line whose whole purpose was to avoid measuring twice.
	if what.has_meta("bulk"):
		return float(what.get_meta("bulk"))
	var span := 0.0
	for child in what.get_children():
		var col := child as CollisionShape3D
		if col == null or col.shape == null:
			continue
		# `crate` and not `box`: this class has a `box()` of its own.
		var crate := col.shape as BoxShape3D
		if crate != null:
			span = maxf(span, Vector2(crate.size.x, crate.size.z).length() * 0.5)
			continue
		var tube := col.shape as CylinderShape3D
		if tube != null:
			span = maxf(span, tube.radius)
			continue
		var ball := col.shape as SphereShape3D
		if ball != null:
			span = maxf(span, ball.radius)
	what.set_meta("bulk", span)
	return span


## IS `at` WITHIN `reach` OF THIS THING'S EDGE? The question every blow, every
## flame and every furnace meant to ask and none of them did. See `bulk_of`.
static func within(what_given: Variant, at: Vector3, reach: float) -> bool:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(what_given):
		return false
	var what := what_given as Node3D
	if what == null or not is_instance_valid(what):
		return false
	return what.global_position.distance_to(at) - bulk_of(what) < reach


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
	# THE NEAR BAND COUNTS ITSELF. A city of two hundred fits inside a hundred
	# and thirty metres, so the band meant to protect the frame handed full rate
	# to every one of them precisely because they were all standing together
	# where the player was looking. See Crowd: past what a frame can carry, the
	# stride rises for everybody until the work fits, and Scheduler deals that
	# evenly across the cycle as it always has.
	Crowd.counted_near()
	return maxi(Crowd.stride(), 1 if relief == 1 else 2)


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
