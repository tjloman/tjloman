extends SceneTree
## A TALL THING'S SHADOW LIES ON THE HILL, NOT IN IT — checked in a real engine,
## headless, with the baked-shadow library built:
##
##     godot --headless --path . --script tools/live/shadow_ground_live.gd
##
## Trees standing on slopes have their shadows laid on the drawn ground here
## exactly as baked_shadow.gdshader lays them (each corner flattened along a low
## sun and set down on the ground under it, LIFT above), once with the hull as
## the library bakes it and once cut finer as Shade does for anything TALL
## (Shade._fine). Then every triangle is sampled across its face:
##   1. cut finer, far less of the shadow lies under the ground — the patches
##      that went missing on a hillside (at most OF_BEFORE as much, and under
##      BURIED), read with the shader's own LIFT, PULL and LONGEST;
##   2. it is the same shadow: the same area on the ground, to a percent;
##   3. and it is whole: every edge meets exactly one other, so no seam gaps
##      or doubles darker where the cuts meet;
##   4. and it costs what it says: no more than MOST_CUTS squared the triangles.
## Passes, and says so, where the library is not built: there are no baked
## shadows to lie anywhere. Names no class of the game's (see look.gd).

const SUN := Vector3(0.75, -0.42, 0.5)
## At most this share of a shadow lost under a hill, and at most this share of
## what was lost before it was cut finer.
const BURIED := 0.08
const OF_BEFORE := 0.25

var lift := 0.0
var pull := 0.0
var longest := 0.0

var fails := 0
var world: Node


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
	for i in 120:
		await process_frame
	var shade: Script = load("res://scripts/shade.gd")
	world = current_scene.world_gen
	# The shader's own numbers, read off the shader, so the two cannot drift.
	var code: String = (load("res://shaders/baked_shadow.gdshader") as Shader).code
	lift = _const_in(code, "LIFT")
	pull = _const_in(code, "PULL")
	longest = _const_in(code, "LONGEST")
	print("A SHADOW ON A HILL")
	if not shade.on():
		print("  the baked-shadow library is not built here: nothing to check")
		print("SHADOW GROUND LIVE: all pass")
		quit(0)
		return
	var sun := SUN.normalized()
	var slopes := []
	for t in get_nodes_in_group("trees"):
		if is_instance_valid(t) and world.slope_at(t.global_position.x, t.global_position.z) > 0.25:
			slopes.append(t)
		if slopes.size() >= 12:
			break
	check(slopes.size() >= 4, "trees standing on slopes to throw shadows (%d)" % slopes.size())
	var raw_under := 0.0
	var fine_under := 0.0
	var raw_area := 0.0
	var fine_area := 0.0
	var whole := true
	var raw_tris := 0
	var fine_tris := 0
	for tree in slopes:
		var raw: ArrayMesh = shade._baker.call(&"bake_points", shade._points_under(tree))
		var fine: ArrayMesh = shade._fine(raw)
		var a := _lay(raw, tree, sun)
		var b := _lay(fine, tree, sun)
		raw_under += a[0]
		raw_area += a[1]
		fine_under += b[0]
		fine_area += b[1]
		raw_tris += _corners(raw).size() / 3
		fine_tris += _corners(fine).size() / 3
		whole = whole and _watertight(_corners(fine))
	var was := raw_under / maxf(raw_area, 0.001)
	var now := fine_under / maxf(fine_area, 0.001)
	check(now <= was * OF_BEFORE and now < BURIED,
		"cut finer, %.1f%% of the shadow lies under the hill (was %.1f%%)" % [now * 100.0, was * 100.0])
	check(absf(fine_area - raw_area) <= raw_area * 0.01,
		"the same shadow: %.0f m2 on the ground, as it was %.0f" % [fine_area, raw_area])
	check(whole, "and whole: every edge of the cut shadow meets exactly one other")
	var cuts: int = shade.MOST_CUTS
	check(fine_tris <= raw_tris * cuts * cuts,
		"%d triangles for these shadows, from %d" % [fine_tris, raw_tris])
	print("SHADOW GROUND LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)


## The shadow laid as the shader lays it: [area under the ground, area in all],
## sampled over every triangle's face.
func _lay(mesh: ArrayMesh, tree: Node3D, sun: Vector3) -> Array:
	var origin := tree.global_position
	var flat := PackedVector3Array()
	for v in _corners(mesh):
		var w := tree.global_transform * v
		var h := maxf(w.y - origin.y, 0.0)
		var off := Vector2(sun.x, sun.z) / maxf(-sun.y, 1.0 / longest) * h
		w.x += off.x
		w.z += off.y
		w.y = world.drawn_height_at(w.x, w.z) + lift
		flat.append(w)
	var under := 0.0
	var all := 0.0
	for t in range(0, flat.size() - 2, 3):
		var p := flat[t]
		var q := flat[t + 1]
		var r := flat[t + 2]
		var area := 0.5 * absf((q.x - p.x) * (r.z - p.z) - (r.x - p.x) * (q.z - p.z))
		if area < 0.0001:
			continue
		var n := 6
		var lost := 0
		var asked := 0
		for i in n:
			for j in n - i:
				var u := (float(i) + 0.33) / float(n)
				var v := (float(j) + 0.33) / float(n)
				var at := p + (q - p) * u + (r - p) * v
				asked += 1
				# Lost where the ground stands over it by more than the pull
				# toward the eye can make up.
				if at.y < world.drawn_height_at(at.x, at.z) - (pull + 0.02):
					lost += 1
		under += area * float(lost) / float(asked)
		all += area
	return [under, all]


func _const_in(code: String, named: String) -> float:
	var found := RegEx.create_from_string("const float %s = ([0-9.]+);" % named).search(code)
	return float(found.get_string(1)) if found != null else NAN


func _corners(mesh: ArrayMesh) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var order: Variant = arrays[Mesh.ARRAY_INDEX]
	if order is PackedInt32Array and not (order as PackedInt32Array).is_empty():
		var out := PackedVector3Array()
		for i: int in order:
			out.append(points[i])
		return out
	return points


## Every edge shared by exactly two triangles: no T-junctions, no seams.
func _watertight(corners: PackedVector3Array) -> bool:
	var seen := {}
	for t in range(0, corners.size() - 2, 3):
		for e in 3:
			var a := corners[t + e]
			var b := corners[t + (e + 1) % 3]
			# Exactly: a point on an edge is the same to the bit from either side.
			var ka := var_to_str(a)
			var kb := var_to_str(b)
			var key := ka + "|" + kb if ka < kb else kb + "|" + ka
			seen[key] = int(seen.get(key, 0)) + 1
	for key in seen:
		if int(seen[key]) != 2:
			return false
	return true
