extends SceneTree
## THE WOODS REMEMBER — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/woods_live.gd
##
##   1. a tree of a chunk's stand that is felled is remembered as down, once;
##   2. a save keeps it, and what a save says is down comes down from a chunk
##      already standing;
##   3. its chunk shed and built again from the seed leaves out every tree that
##      is down — and only those;
##   4. a wood a town out of sight felled (TownLand.write_back_woods) is built
##      with that many fewer trees, and a town's land reads it as cut;
##   5. a tree down longer than its REGROW_YEARS stands again, smaller.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

## Where the camera goes to shed home's chunks, and to find a far wood.
const AWAY := 2600.0

var fails := 0
var world: Node
var rig: Node3D


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var state: Node = root.get_node("/root/GameState")
	var main: Node = current_scene
	rig = main.camera_rig
	world = main.world_gen
	var chunk_script: Script = load("res://scripts/world/chunk.gd")
	var regrow: float = chunk_script.get_script_constant_map()["REGROW_YEARS"]
	var land_script: Script = load("res://scripts/world/board/town_land.gd")
	print("THE WOODS REMEMBER")
	await seconds(3.0)

	# A standing chunk near home with a stand of at least three trees.
	var chunk: Node = null
	for n in root.find_children("*", "Node3D", true, false):
		# Not where the creature stands: that ground is never let go.
		if "from_stand" in n and n.from_stand and not n.get_parent().terrain_only \
				and not world._creature_cells().has(n.get_parent().cell) \
				and _stand(n.get_parent()).size() >= 3:
			chunk = n.get_parent()
			break
	check(chunk != null, "a chunk near home has a stand of trees")
	if chunk == null:
		_done()
		return
	var cell: Vector2i = chunk.cell
	var had: Array = _stand(chunk)
	var a: Node = had[0]
	var b: Node = had[1]
	var seed_a: int = a.rng_seed
	var seed_b: int = b.rng_seed
	var lumber_a: float = a.lumber

	# 1. Felled: remembered, once.
	a.fell()
	a.fell()
	var down: Array = world.felled_at(cell).filter(func(e): return int(e.get("seed", -1)) == seed_a)
	check(down.size() == 1, "a felled tree of the stand is remembered as down, once (%d)" % down.size())

	# 2. Through a save, as JSON writes it; and what it says is down comes down.
	var saved: Array = JSON.parse_string(JSON.stringify(world.woods_to_save()))
	var row: Array = saved.filter(func(r): return Vector2i(int(r["x"]), int(r["z"])) == cell)
	check(row.size() == 1, "a save keeps the woods' gaps")
	if not row.is_empty():
		(row[0]["gone"] as Array).append({"seed": seed_b, "at": state.game_years})
	world._felled.clear()
	world.woods_from_save(saved)
	await process_frame
	await process_frame
	check(not is_instance_valid(b) and world.felled_at(cell).size() >= 2,
		"read back, a tree the save says is down comes down from a standing chunk")

	# 3. Shed and built again: the seed stands everything but what is down.
	rig.global_position = Vector3(AWAY, 0.0, AWAY)
	var chunk_id := chunk.get_instance_id()
	await _until(func(): return not is_instance_id_valid(chunk_id), 90.0)
	check(not is_instance_id_valid(chunk_id), "far away, the chunk is shed")
	# While out here: a wood a town could have felled.
	var far := _forest_near(Vector2(AWAY, AWAY))
	print("    a far wood at %.0f, %.0f: %s" % [far.x, far.y, world.biome_at(far.x, far.y)])
	rig.global_position = Vector3(far.x, 0.0, far.y)
	await _until(func(): return _built(far) != null, 90.0)
	var far_cell: Vector2i = world.cell_of(far.x, far.y)
	var far_had := _stand(_built(far)).size() if _built(far) != null else 0
	check(far_had >= 4, "a far wood stands (%d trees)" % far_had)
	rig.global_position = Vector3.ZERO
	var again: Node = await _rebuilt(cell)
	check(again != null and again.get_instance_id() != chunk_id, "home's chunk is built again from the seed")
	if again != null:
		var seeds := _stand(again).map(func(t): return t.rng_seed)
		var gaps: int = world.felled_at(cell).size()
		check(not seeds.has(seed_a) and not seeds.has(seed_b),
			"without the trees that are down")
		check(seeds.size() == had.size() - gaps,
			"and with every other tree of its stand (%d of %d, %d down)" % [seeds.size(), had.size(), gaps])

	# 4. Out of sight, a town cut half the far wood.
	await _until(func(): return _built(far) == null, 90.0)
	land_script.write_back_woods(world, far, 0.5)
	var any: int = 0
	for e: Dictionary in world.felled_at(far_cell):
		any += int(e.get("any", 0))
	check(any > 0, "a town's felling out of sight is written to the woods (%d trees)" % any)
	var read = land_script.read(world, Vector3(far.x, 0.0, far.y))
	var share: float = read.wood_now / maxf(read.wood, 0.01)
	check(absf(share - 0.5) < 0.15, "and its land reads them as cut (%.2f standing)" % share)
	# And a wood drawn far off as billboards is drawn again without them.
	var boards: Node = null
	for n in world.get_children():
		if "terrain_only" in n and n.terrain_only and not n.wooded and n._stand_known \
				and n._stand_kept.size() >= 4 and world.felled_at(n.cell).is_empty() \
				and _built_or_boarded(n.cell) == n:
			boards = n
			break
	check(boards != null, "a wood stands far off as billboards")
	if boards != null:
		var drawn: int = boards._stand_kept.size()
		var mid := (Vector2(boards.cell) + Vector2(0.5, 0.5)) * 48.0
		land_script.write_back_woods(world, mid, 0.5)
		var cut: int = 0
		for e: Dictionary in world.felled_at(boards.cell):
			cut += int(e.get("any", 0))
		check(cut > 0 and boards._stand_kept.size() == drawn - cut,
			"felled out of sight, it is drawn %d trees fewer (%d of %d)" % [cut, boards._stand_kept.size(), drawn])
	rig.global_position = Vector3(far.x, 0.0, far.y)
	await _until(func(): return _built(far) != null, 90.0)
	var far_now := _stand(_built(far)).size() if _built(far) != null else -1
	check(far_now == maxi(far_had - any, 0),
		"seen again, that wood is built that many trees fewer (%d of %d)" % [far_now, far_had])

	# 5. Long enough down, it grows back: aged past its REGROW_YEARS by half
	# as long again, it stands at about half its size.
	for e: Dictionary in world.felled_at(cell):
		if int(e.get("seed", -1)) == seed_a:
			e["at"] = float(e["at"]) - regrow * 1.5
	var grown: Node = await _rebuilt(cell)
	var back: Array = [] if grown == null else _stand(grown).filter(func(t): return t.rng_seed == seed_a)
	check(back.size() == 1, "a tree down past its regrowing years stands again")
	if back.size() == 1:
		var size: float = back[0].lumber
		check(size < lumber_a and size <= maxf(1.0, lumber_a * 0.5) + 0.01,
			"and smaller, growing back (%.1f, felled at %.1f)" % [size, lumber_a])
	_done()


## A chunk's own seed stand still standing in it.
func _stand(chunk: Node) -> Array:
	return chunk.get_children().filter(func(n): return "from_stand" in n and n.from_stand)


func _built(at: Vector2) -> Node:
	var chunk = world.chunk_at(at.x, at.y)
	if chunk == null or not is_instance_valid(chunk) or chunk.terrain_only:
		return null
	return chunk


## The chunk resident at `cell`, as anything: not one shed and waiting to be freed.
func _built_or_boarded(cell: Vector2i) -> Node:
	var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * 48.0
	return world.chunk_at(mid.x, mid.y)


## Away, so the chunk at `cell` is shed; then back, until it is built again.
func _rebuilt(cell: Vector2i) -> Node:
	var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * 48.0
	var old = world.chunk_at(mid.x, mid.y)
	if old != null:
		var old_id: int = old.get_instance_id()
		rig.global_position = Vector3(AWAY, 0.0, -AWAY)
		await _until(func(): return not is_instance_id_valid(old_id), 90.0)
	rig.global_position = Vector3(mid.x, 0.0, mid.y)
	await _until(func(): return _built(mid) != null, 90.0)
	return _built(mid)


## The middle of a chunk whose stand is a forest's: the biome a chunk grows is
## read at its middle (Chunk._tree_stand).
func _forest_near(at: Vector2) -> Vector2:
	var from: Vector2i = world.cell_of(at.x, at.y)
	for i in 900:
		var probe := (Vector2(from + Vector2i(i % 30, i / 30)) + Vector2(0.5, 0.5)) * 48.0
		if world.biome_at(probe.x, probe.y) == "forest":
			return probe
	return at


func _until(done: Callable, limit: float) -> void:
	var until := Time.get_ticks_msec() + int(limit * 1000.0)
	while Time.get_ticks_msec() < until and not done.call():
		await process_frame


func _done() -> void:
	print("WOODS LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
