extends SceneTree
## THE GROUND'S GRAIN — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/grit_live.gd
##
##   1. on the top tier the one ground material carries the grain and the
##      patches, and reads the land's colours as they were written;
##   2. every ground vertex says where it is in the WORLD, so the grain runs on
##      across a chunk border without a seam;
##   3. LOW cuts its ground with no grain at all;
##   4. the grain darkens the land a little and no more;
##   5. and making the two textures costs a few milliseconds, once.
## Whatever it changes it puts back. Exits non-zero on failure. Names no class
## of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var quality: Node = root.get_node("/root/Quality")
	var world: Node = current_scene.world_gen
	var grit: Script = load("res://scripts/world/ground_grit.gd")
	print("THE GROUND'S GRAIN (tier %d)" % quality.tier)

	# 1. The material.
	var util: Script = load("res://scripts/util.gd")
	var ground: StandardMaterial3D = util.ground_material()
	var layers: int = quality.ground_detail()
	check(layers == 2, "the top tier grains the ground in two layers")
	check(ground.albedo_texture != null and ground.detail_enabled
		and ground.detail_albedo != null, "the one ground material carries the grain and the patches")
	check(ground.vertex_color_is_srgb, "and reads the land's colours as they were written")

	# 2. Where each vertex reads it, and a border with no seam.
	var near: Node = null
	for chunk in world._chunks.values():
		if not chunk.terrain_only and chunk._ground != null:
			near = chunk
			break
	var arrays: Array = near._ground.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var off := 0.0
	for i in range(0, verts.size(), 37):
		var at := Vector2(near.position.x + verts[i].x, near.position.z + verts[i].z)
		off = maxf(off, uvs[i].distance_to(at / grit.GRIT_TILE))
		off = maxf(off, uv2s[i].distance_to(at / grit.PATCH_TILE))
	check(uvs.size() == verts.size() and uv2s.size() == verts.size() and off < 0.001,
		"every ground vertex reads the grain by its place in the world")
	var east: Node = world._chunks.get(near.cell + Vector2i(1, 0))
	var seam := INF
	if east != null and east._ground != null:
		var theirs: Array = east._ground.mesh.surface_get_arrays(0)
		var tv: PackedVector3Array = theirs[Mesh.ARRAY_VERTEX]
		var tu: PackedVector2Array = theirs[Mesh.ARRAY_TEX_UV]
		# The corner on the border, from both sides.
		for i in verts.size():
			if absf(verts[i].x - 48.0) < 0.01 and absf(verts[i].z) < 0.01:
				for j in tv.size():
					if absf(tv[j].x) < 0.01 and absf(tv[j].z) < 0.01:
						seam = uvs[i].distance_to(tu[j])
						break
				break
	check(seam < 0.0001, "the same corner reads the same grain from both chunks (%.6f)" % seam)

	# 3. LOW: no grain cut into the ground.
	var tier: int = quality.tier
	quality.tier = 0
	near.recolor()
	var plain: Array = near._ground.mesh.surface_get_arrays(0)
	check(plain[Mesh.ARRAY_TEX_UV] == null, "LOW cuts its ground with no grain at all")
	quality.tier = tier
	near.recolor()
	check(near._ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != null,
		"and back on the top tier it is cut with it again")

	# 4. A little darker, and no more.
	var kept: float = grit.kept(2)
	check(kept >= 0.55 and kept <= 0.9,
		"the grain keeps %.0f%% of the land's light: some, not most" % (kept * 100.0))

	# 5. What making them costs.
	var t := Time.get_ticks_usec()
	grit._make(grit.GRIT_SIZE, 1, 0.045, 5, grit.GRIT_DARKEST)
	grit._make(grit.PATCH_SIZE, 2, 0.03, 3, grit.PATCH_DARKEST)
	var ms := float(Time.get_ticks_usec() - t) / 1000.0
	check(ms < 250.0, "both textures made in %.0f ms, once, behind the opening screen" % ms)
	var bytes: int = 0
	for tex: ImageTexture in [grit.grit(), grit.patches()]:
		bytes += tex.get_image().get_data().size()
	check(bytes < 120 * 1024, "and they hold %.0f KB between them, mipmaps and all" % (bytes / 1024.0))

	# 6. The ground a shade darker round what stands on it.
	var tree: Node3D = null
	var home: Node = null
	for chunk in world._chunks.values():
		if chunk.terrain_only:
			continue
		for child in chunk.get_children():
			if child.get_class() == "StaticBody3D" and child.get_script() != null \
					and String(child.get_script().get_global_name()) == "WildTree":
				tree = child
				home = chunk
				break
		if tree != null:
			break
	check(tree != null, "there is a tree standing on near ground")
	if tree != null:
		var dim := darker_by(home, Vector2(tree.global_position.x, tree.global_position.z))
		check(dim > 0.08, "the ground at a tree's foot is a shade darker (%.0f%%)" % (dim * 100.0))
	var house: Node3D = null
	for h in get_nodes_in_group("houses"):
		house = h
		break
	if house == null:
		for v in get_nodes_in_group("village"):
			for b in v.find_children("*", "", true, false):
				if b.get_script() != null and String(b.get_script().get_global_name()) == "House":
					house = b
					break
			if house != null:
				break
	check(house != null, "there is a house standing")
	if house != null:
		for i in 30:
			await process_frame       # a standing chunk is cut again one a frame
		var at := Vector2(house.global_position.x, house.global_position.z)
		var dim := darker_by(world.chunk_at(at.x, at.y), at + Vector2(2.6, 0.0))
		check(dim > 0.05, "and round a house (%.0f%%)" % (dim * 100.0))
		# AND ONE BUILT LATER: forget the shade, cut the ground plain, and set the
		# house down the way a new one is set down.
		var under: Node = world.chunk_at(at.x, at.y)
		under._shade_spots.clear()
		under.recut()
		var bare := darker_by(under, at + Vector2(2.6, 0.0))
		load("res://scripts/world/footing.gd").settle(house, world)
		for i in 30:
			await process_frame
		var later := darker_by(under, at + Vector2(2.6, 0.0))
		check(bare < 0.03 and later > 0.05,
			"a house set down later darkens the ground round it (%.0f%% -> %.0f%%)"
			% [bare * 100.0, later * 100.0])

	print("GRIT LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)


## HOW MUCH DARKER the drawn ground is at the grid corner nearest `at` than the
## colour the land gives it — read off the mesh, against the chunk's own tint.
func darker_by(chunk: Node, at: Vector2) -> float:
	if chunk == null or chunk._ground == null:
		return 0.0
	var step: float = 48.0 / chunk._cells
	var wide: int = chunk._cells + 1
	var gx := clampi(roundi((at.x - chunk.position.x) / step), 0, chunk._cells)
	var gz := clampi(roundi((at.y - chunk.position.z) / step), 0, chunk._cells)
	var want := Vector3(gx * step, 0.0, gz * step)
	var arrays: Array = chunk._ground.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in verts.size():
		if absf(verts[i].x - want.x) < 0.01 and absf(verts[i].z - want.z) < 0.01:
			var plain: Color = chunk._tint[gz * wide + gx]
			return 1.0 - colours[i].get_luminance() / maxf(plain.get_luminance(), 0.001)
	return 0.0
