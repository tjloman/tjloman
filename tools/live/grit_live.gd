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

	print("GRIT LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
