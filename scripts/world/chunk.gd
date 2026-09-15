class_name Chunk
extends Node3D
## One 48m square of the endless world: terrain mesh (vertex-colored by
## biome/slope/altitude), heightmap collision, a water quad where the land
## dips below the water table, and everything scattered on it — trees, rock
## deposits, flowers, and wildlife. All deterministic from the world seed.
##
## OR JUST THE FIRST OF THOSE. A chunk beyond the streaming ring but still
## inside the camera's far plane is built `terrain_only`: the ground mesh and
## nothing else — no collision, no water, nothing scattered, no shadow cast.
## It exists to be LOOKED AT. `flesh_out` turns one into a real place when the
## player walks up to it, and `strip_down` turns a real place back into scenery
## when they walk away, neither of which re-cuts the mesh. See
## WorldGen._stream_chunks and Quality.sight_radius.

## HOW FAR A COARSE CHUNK'S SKIRT HANGS BELOW ITS EDGE.
##
## A coarse edge is a CHORD where its fine neighbour is a curve, so between the
## two you can see sky through the floor. The textbook answer is to stitch the
## edges, which means every chunk knowing its neighbours' resolution and being
## re-cut when one of them changes. The cheap answer is a wall dropped straight
## down from the border, deeper than the gap can ever be, so there is something
## behind the crack: four sides by `cells` quads, 64 triangles at eight cells,
## and no bookkeeping at all.
##
## Only the COARSE side needs one. Where the fine terrain rises above the chord
## the fine chunk simply pokes through, which is an overlap and not a hole.
const SKIRT_DROP := 6.0

## HOW MUCH WOOD EACH BIOME CARRIES: fewest, most, and the style it grows. Was
## spelled out inside `_scatter`'s match, one line per biome; it is a table now
## because the far ring has to be able to ask the same question without
## building anything. See `_tree_stand`.
const STAND := {
	"forest": [5, 8, "forest"],
	"grassland": [1, 3, "grassland"],
	"savanna": [2, 4, "savanna"],
	"rocky_hills": [0, 1, "forest"],
	"desert": [0, 1, "savanna"],
	"tundra": [0, 2, "forest"],
	"rainforest": [7, 11, "wetland"],
	"wetland": [1, 3, "wetland"],
}

## STONE, AT EVERY SIZE IT COMES IN. Every rock in the world used to be the
## same three-hundred-stone vein, two or three to a hillside — so a riverbank
## had no pebbles on it and the only thing anybody could do with stone was
## quarry it like a mine.
##
## The small ones far outnumber the big, because that is what ground looks
## like, and because a pebble is the thing you actually want to hand: something
## to skip, to throw at a bird, to give a whelp that cannot lift anything else.
## Weighted so a scatter is mostly chips with the occasional tor in it.
##
## AND THE WATERLINE DECIDES. Stone at the water's edge is rounded and small —
## it has been rolled — and stone up a dry hillside is whatever the hill is
## made of. One check against the ground it lands on, and a riverbank shingles
## itself without anything anywhere having to know where the rivers are.
const STONE_SPREAD: Array[int] = [0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4]
const SHINGLE: Array[int] = [0, 0, 0, 1, 1, 2]
## How close to the waterline counts as a shore, in metres of height above it.
const SHORE_WITHIN := 1.6

var world: WorldGen
var cell := Vector2i.ZERO
## Set before the chunk enters the tree. See the class note above.
var terrain_only := false

## Held so the land can be RE-cut when a miracle moves the earth under it.
var _ground: MeshInstance3D = null
var _body: StaticBody3D = null
var _water: MeshInstance3D = null
## The lowest ground in this chunk, measured while the mesh is built, and where
## it is. Together with the lowest SEEDED ground — the land as it was made,
## before any miracle cut into it — this is what decides whether the sea is
## drawn here at all. See `_build_water`.
var _lowest := INF
var _lowest_seeded := INF
var _deepest := Vector2.ZERO
## The height grid this chunk was cut from, kept so `recolor` can re-tint the
## ground without re-measuring it. About 2.5 KB at a 24x24 grid, 122 KB across
## a loaded 7x7 — which buys burns that visibly cool.
var _heights := PackedFloat32Array()
## THE GRID THIS CHUNK WAS ACTUALLY CUT AT, which is no longer one number for
## the whole world. A chunk that is only ever looked at is cut coarse (see
## Quality.far_cells); one you can walk on is cut fine, because `_heights` is
## also the collision heightmap and a six-metre cell would have you floating a
## metre over the hills. Everything that reads the grid reads THIS, not
## `world.chunk_cells` — they disagree for most of the chunks in the world.
var _cells := 0
## Every bloom scattered here, in world space — read by TreeFriends so bees and
## moths can be over the flowers instead of near them.
var _blooms: PackedVector3Array = PackedVector3Array()
## Everything scattered here that has to be set back down on the new ground.
var _standing: Array[Node3D] = []
## The billboard woods, one MultiMesh a style — usually one, since a biome
## grows one kind. Kept so `strip_down` knows not to free them with everything
## else, and so they can be rebuilt when the wood changes.
var _boards: Array[MultiMeshInstance3D] = []
## WHAT STANDS HERE, once it has been decided — and it is decided once.
##
## A chunk you logged and walked away from is stripped, and later COARSENED,
## which re-cuts the ground and would have re-asked the seed what grows here.
## The seed does not know you were ever here, so the wood stood back up on the
## horizon. Keeping the answer is what makes felling permanent: `_stand_known`
## says it has been decided, and an empty `_stand_kept` beside it is a real
## answer — a clearing — rather than a question nobody has asked yet.
var _stand_kept: Array[Dictionary] = []
var _stand_known := false


func _ready() -> void:
	_build_terrain()
	if terrain_only:
		retally_boards()
		return
	_build_collider()
	_build_water()
	_scatter()
	retally_boards()


## SCENERY BECOMES A PLACE. The player has walked into the ring, so the ground
## that was only ever drawn now gets something to stand on, water to drown in,
## and everything that lives here.
##
## The point of it used to be what it did NOT do: the mesh was cut when this
## cell first came into view, possibly minutes ago, and was left exactly as it
## was, because the land must not flicker at the moment you arrive at it.
##
## That still holds for a chunk that was already cut fine. A COARSE one has to
## be re-cut, and the reason is below.
func flesh_out() -> void:
	if not terrain_only:
		return
	terrain_only = false
	# THE GROUND IS RE-CUT IF IT WAS COARSE, and this is the one place the old
	# promise — "the mesh is left exactly as it is" — has to give way. The grid
	# IS the collision heightmap, and a six-metre cell would have people walking
	# a metre above the hills and falling through the dips. What you see and
	# what you walk on cannot disagree; so if the land here is to be stood on,
	# it is measured again properly first.
	#
	# It costs (cells+1)^2 height samples on one frame — the same build every
	# near chunk pays, and rate-limited the same way, because WorldGen._make_whole
	# counts a flesh-out against CHUNKS_PER_FRAME.
	if _cells != world.chunk_cells:
		rebuild_terrain()   # re-cuts fine, and lays the collider and water with it
		_scatter()
		retally_boards()
		return
	if _ground != null and is_instance_valid(_ground):
		_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_build_collider()
	_build_water()
	_scatter()
	retally_boards()


## A PLACE BECOMES SCENERY AGAIN. The player has walked out of the ring, so
## everything that was simulated here goes — which is precisely what unloading
## the chunk used to do — but the ground stays standing and keeps being drawn.
##
## `_heights` is kept too, so a burn here still cools on schedule. The grid it
## was cut at is kept as well, which is the point of `coarse_due` below: the
## ground here is still cut for walking on, and nobody can walk here any more.
func strip_down() -> void:
	if terrain_only:
		return
	# BOARD THE WOOD AS IT ACTUALLY STANDS, before a line of it is freed —
	# while `_standing` still holds real trees and `terrain_only` is still
	# false, which is what makes this read the survivors rather than the seed.
	retally_boards()
	terrain_only = true
	if _ground != null and is_instance_valid(_ground):
		_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for node in get_children():
		# `_boards` IS A TYPED ARRAY, AND `has` ON ONE VALIDATES ITS ARGUMENT.
		# Ask an Array[MultiMeshInstance3D] whether it holds a StaticBody3D and
		# Godot does not answer false — it raises, every frame a chunk is
		# stripped with a tree standing on it. The `is` in front short-circuits
		# before `has` ever sees the wrong type. (Same family as the `filter()`
		# trap in Util.prune: a typed array is not a list, it is a list that
		# checks.)
		if node != _ground and not (node is MultiMeshInstance3D and _boards.has(node)):
			node.queue_free()
	_body = null
	_water = null
	_standing.clear()
	_blooms = PackedVector3Array()


## THE LAND HERE IS STILL CUT FOR WALKING ON, and nobody can walk here.
##
## Without the coarsening a player crossing the world leaves a widening wake of
## full-resolution chunks behind them, still drawn, all the way out to the far
## plane — which gives back most of what the far ring was for.
##
## BUT IT IS NOT DONE IN `strip_down`. Crossing one chunk boundary strips a
## whole row at once — nine of them at `unload_radius` 4 — and nine re-cuts on
## the frame you step over a line is a hitch of exactly the kind this change
## exists to remove. So stripping stays free, this says the work is owed, and
## WorldGen._shed pays it off one chunk a frame like everything else.
func coarse_due() -> bool:
	return terrain_only and _cells != Quality.far_cells()


## Pay it. 81 height samples against the 625 that cut it fine, so the cheap
## direction is the one that is allowed to wait.
func coarsen() -> void:
	rebuild_terrain()


## THE EARTH MOVED. Re-cut the mesh and the collision from the new heights, put
## the water back where it now belongs, and set everything standing here back
## down on the ground.
##
## The whole chunk is rebuilt rather than the affected vertices patched: it is
## 169 height samples and a 288-triangle surface, which is nothing beside the
## bookkeeping that tracking partial edits would cost — and a miracle only ever
## touches a handful of chunks at once.
func rebuild_terrain() -> void:
	if _ground != null and is_instance_valid(_ground):
		_ground.queue_free()
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
	if _water != null and is_instance_valid(_water):
		_water.queue_free()
		_water = null
	_build_terrain()
	if terrain_only:
		retally_boards()
		return
	_build_collider()
	_build_water()
	_reground()
	retally_boards()


## Trees, rocks and bushes do not fall when the ground drops out from under
## them — they were placed at a height that no longer exists, so they are put
## back on the surface. Living things are left alone: they have gravity and
## will find the new ground themselves, which looks far better than teleporting.
func _reground() -> void:
	var kept: Array[Node3D] = []
	for node in _standing:
		if not is_instance_valid(node):
			continue
		kept.append(node)
		node.position.y = world.height_at(
			position.x + node.position.x, position.z + node.position.z) - float(
				node.get_meta("sink", 0.0))
	_standing = kept


## CUT THE LAND. A grid of heights, a colour for each corner of it, and two
## triangles per cell — plus the same grid handed straight to the collision
## heightmap, so what you see and what you walk on cannot disagree.
##
## THE COST IS ALL IN THE COLOURS, and it used to be spent five times over.
## `ground_color` was called once per EMITTED vertex — six per quad, 864 for a
## 12x12 chunk — when the grid only has 169 distinct corners, and each call ran
## `slope_at`, which is three more `height_at`. That came to about 12,800 noise
## evaluations for one chunk, of which roughly nine tenths were the same
## question asked again.
##
## Now the colour is worked out once per grid corner and looked up six times,
## and the slope is differenced from the heights already sampled instead of
## being re-derived from the noise. About 1,000 evaluations for the same
## 12x12 chunk — which is what pays for the grid being 24x24 instead.
func _build_terrain() -> void:
	_cells = Quality.far_cells() if terrain_only else world.chunk_cells
	var cells := _cells
	var step := WorldGen.CHUNK_SIZE / cells
	var wide := cells + 1
	var heights := PackedFloat32Array()
	heights.resize(wide * wide)

	# Sample the height grid (in world space; chunk origin is our position),
	# keeping the lowest — the water pass needs it and it is free here.
	_lowest = INF
	_lowest_seeded = INF
	for z in wide:
		for x in wide:
			var wx := position.x + x * step
			var wz := position.z + z * step
			# Split rather than one `height_at` call: the seeded height is the
			# same work either way, and having it lets the water pass tell a bay
			# from a bomb crater without measuring the chunk twice.
			var seeded := world.seeded_height_at(wx, wz)
			var h := seeded + world.scars.offset_at(wx, wz)
			heights[z * wide + x] = h
			_lowest_seeded = minf(_lowest_seeded, seeded)
			if h < _lowest:
				_lowest = h
				_deepest = Vector2(wx, wz)

	var tint := _tint_grid(heights)

	_heights = heights
	_cut_mesh(tint)


## Heightmap collision (layer 1 = ground), cut from the grid `_build_terrain`
## already measured — so what you see and what you walk on cannot disagree.
##
## Separate from the mesh because the far ring wants one without the other: a
## StaticBody3D two hundred metres away is a physics island nothing will ever
## touch, and there would be a few hundred of them.
func _build_collider() -> void:
	var cells := _cells
	var wide := cells + 1
	var step := WorldGen.CHUNK_SIZE / cells
	var body := StaticBody3D.new()
	_body = body
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionShape3D.new()
	var hshape := HeightMapShape3D.new()
	hshape.map_width = wide
	hshape.map_depth = wide
	hshape.map_data = _heights
	shape.shape = hshape
	shape.scale = Vector3(step, 1.0, step)
	shape.position = Vector3(WorldGen.CHUNK_SIZE / 2.0, 0, WorldGen.CHUNK_SIZE / 2.0)
	body.add_child(shape)
	add_child(body)


## ONE COLOUR PER GRID CORNER, with the slope DIFFERENCED from the heights
## rather than sampled afresh. `ground_color` wants the rise over two metres, so
## the step difference is scaled to that — otherwise a four-metre grid reports
## half the true steepness and every cliff comes out green.
func _tint_grid(heights: PackedFloat32Array) -> PackedColorArray:
	var cells := _cells
	var wide := cells + 1
	var step := WorldGen.CHUNK_SIZE / cells
	var per_two := 2.0 / step
	var tint := PackedColorArray()
	tint.resize(wide * wide)
	for z in wide:
		for x in wide:
			var i := z * wide + x
			var h: float = heights[i]
			var ax: int = i + 1 if x < cells else i - 1
			var az: int = i + wide if z < cells else i - wide
			var slope := maxf(absf(heights[ax] - h), absf(heights[az] - h)) * per_two
			tint[i] = world.ground_color(
				position.x + x * step, position.z + z * step, h, slope)
	return tint


## Two triangles a cell, unindexed — six vertices a quad, because
## `generate_normals` without an index buffer is what gives the land its facets.
func _cut_mesh(tint: PackedColorArray) -> void:
	var cells := _cells
	var wide := cells + 1
	var step := WorldGen.CHUNK_SIZE / cells
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in cells:
		for x in cells:
			var x0 := x * step
			var z0 := z * step
			var at := [z * wide + x, z * wide + x + 1,
				(z + 1) * wide + x + 1, (z + 1) * wide + x]
			var corners := [
				Vector3(x0, _heights[at[0]], z0),
				Vector3(x0 + step, _heights[at[1]], z0),
				Vector3(x0 + step, _heights[at[2]], z0 + step),
				Vector3(x0, _heights[at[3]], z0 + step),
			]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(tint[at[idx]])
				st.add_vertex(corners[idx])
	if cells != world.chunk_cells:
		_cut_skirt(st, tint, wide, step)
	st.generate_normals()

	if _ground != null and is_instance_valid(_ground):
		_ground.queue_free()
	_ground = MeshInstance3D.new()
	_ground.mesh = st.commit()
	# ONE shared material for every chunk in the world — see Util.ground_material.
	_ground.material_override = Util.ground_material()
	# Scenery does not cast. `shadow_distance` is 70-120m and the near ring
	# reaches 144m, so nothing out here was ever in the atlas anyway; saying so
	# keeps a few hundred meshes out of the shadow pass's culling entirely.
	if terrain_only:
		_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)


## THE WALL ROUND A COARSE CHUNK. See SKIRT_DROP for why there is one.
##
## Four edges, walked in the direction that makes each wall face OUTWARD.
## Godot takes a face's normal from (v0-v2) x (v0-v1), and the pattern below
## yields Y x d for an edge walked in direction d — so the south edge is walked
## +X, the north -X, the east +Z and the west -Z. Get one backwards and it is
## invisible from the only side anyone sees it from, which is the sort of bug
## that is much easier to write down than to find.
func _cut_skirt(st: SurfaceTool, tint: PackedColorArray, wide: int, step: float) -> void:
	var cells := wide - 1
	var top := cells * wide
	for i in cells:
		_skirt_quad(st, tint, i, i + 1, wide, step)                          # S
		_skirt_quad(st, tint, top + i + 1, top + i, wide, step)              # N
		_skirt_quad(st, tint, i * wide + cells, (i + 1) * wide + cells, wide, step)   # E
		_skirt_quad(st, tint, (i + 1) * wide, i * wide, wide, step)          # W


## One panel of it: the two border corners, and the same two dropped straight
## down. The colour is the ground's own at that corner, so the wall reads as
## the underside of the land rather than as a band of something else.
func _skirt_quad(st: SurfaceTool, tint: PackedColorArray,
		a: int, b: int, wide: int, step: float) -> void:
	# Whole grid columns. `a` and `b` are indices into a wide x wide lattice,
	# so the row is the quotient and the column the remainder, exactly.
	@warning_ignore("integer_division")
	var pa := Vector3(float(a % wide) * step, _heights[a], float(a / wide) * step)
	@warning_ignore("integer_division")
	var pb := Vector3(float(b % wide) * step, _heights[b], float(b / wide) * step)
	var da := pa - Vector3(0, SKIRT_DROP, 0)
	var db := pb - Vector3(0, SKIRT_DROP, 0)
	for v: Array in [[pa, a], [da, a], [db, b], [pa, a], [db, b], [pb, b]]:
		st.set_color(tint[v[1]])
		st.add_vertex(v[0])


## THE WOOD ON THE HORIZON ------------------------------------------------
##
## Past Quality.clutter_distance a real tree stops drawing, and out here there
## are no real trees to stop. What stands instead is one painted quad a tree,
## turning to face the camera, the whole chunk's worth in a single MultiMesh:
## two triangles and no node each, against 88 triangles and a StaticBody3D that
## would lengthen every `get_nodes_in_group("trees")` scan in the game.
##
## WHERE THE TREES COME FROM depends on whether anyone has been here. Ground
## nobody has visited is boarded from the SEED, which is why the billboards and
## the real trees agree. Ground you have walked on is boarded from what actually
## survived you — otherwise a wood you logged would stand back up the moment you
## turned around.
func retally_boards() -> void:
	for old in _boards:
		if is_instance_valid(old):
			old.queue_free()
	_boards.clear()
	if not terrain_only:
		# Standing here, so the trees themselves are the answer — and they
		# overwrite whatever the seed once said, which is how logging sticks.
		_stand_kept = _standing_stand()
		_stand_known = true
	elif not _stand_known:
		_stand_kept = _tree_stand(world.chunk_rng(cell))
		_stand_known = true
	if _stand_kept.is_empty():
		return
	var stand := _stand_kept
	# One MultiMesh a style. A biome grows one kind, so this is nearly always a
	# single pass — but a tree can be carried across a border in the hand, and a
	# conifer drawn as an acacia would be a strange thing to have built.
	var by_style := {}
	for it: Dictionary in stand:
		by_style.get_or_add(String(it["style"]), []).append(it)
	for style: String in by_style:
		_board_style(style, by_style[style])


## The trees that are really here, in the shape `_tree_stand` hands back.
func _standing_stand() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in _standing:
		if not is_instance_valid(node) or not (node is WildTree):
			continue
		var tree := node as WildTree
		if tree.felled() or tree.lumber < TreeArt.LEAST_LUMBER:
			continue
		out.append({"spot": tree.position, "seed": tree.rng_seed,
			"lumber": tree.lumber, "style": tree.style})
	return out


## One style's worth, as a MultiMesh standing on the ground.
func _board_style(style: String, stand: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = TreeArt.board(style)
	mm.instance_count = stand.size()
	var leaf := TreeArt.leaf_of(style)
	var shown := 0
	for it: Dictionary in stand:
		var carried := float(it["lumber"])
		if carried < TreeArt.LEAST_LUMBER:
			continue
		var size := WildTree.board_size(style, int(it["seed"]), carried)
		var spot: Vector3 = it["spot"]
		spot.y = world.height_at(position.x + spot.x, position.z + spot.z) - 0.1
		mm.set_instance_transform(shown, Transform3D(
			Basis.IDENTITY.scaled(Vector3(size.x, size.y, 1.0)), spot))
		# A little variation in the green, off the seed, so a wood is not one
		# colour stamped four hundred times.
		var shift := float(int(it["seed"]) & 63) / 63.0
		mm.set_instance_color(shown, leaf.lightened(shift * 0.16).darkened(0.08))
		shown += 1
	mm.visible_instance_count = shown
	if shown == 0:
		return
	var view := MultiMeshInstance3D.new()
	view.multimesh = mm
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# WHERE THE BOARDS TAKE OVER: exactly where the real trees stop — but ONLY
	# on a chunk that has real trees.
	#
	# Out in the far ring there are none, and a far chunk is not necessarily
	# far: its nearest edge sits at load_radius x 48m, which is 144m, while
	# clutter_distance on a capable device is 180m. Cull those boards at 180 and
	# the nearest ring of the wood goes out — a clearing that follows the player
	# around, with a forest standing behind it.
	#
	# A visibility range is measured to the whole MultiMesh, so the handover is
	# per CHUNK rather than per tree: half a chunk of slop at the seam, which is
	# what the fade margin is for.
	if not terrain_only:
		view.visibility_range_begin = Quality.clutter_distance()
		view.visibility_range_begin_margin = Quality.clutter_distance() * 0.12
		view.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(view)
	_boards.append(view)


## THE COLOURS CHANGED, THE LAND DID NOT — a burn cooling from ember to char to
## scrub, which happens for eight minutes after every fireball.
##
## The whole point is what it does NOT do: no height sampling (the grid is the
## one already measured), no collision, no putting the trees back down. Just the
## per-corner colour and a new surface. That is about 1,250 noise evaluations
## for a 24x24 chunk against the 3,750 a full rebuild costs, and it is why the
## ground can be allowed to keep changing at all.
func recolor() -> void:
	if _heights.is_empty() or _ground == null or not is_instance_valid(_ground):
		return
	_cut_mesh(_tint_grid(_heights))


## The flowers on this chunk, in world space. Empty on anything but a meadow.
func blooms() -> PackedVector3Array:
	return _blooms


func _build_water() -> void:
	# THE LOWEST POINT OF THE MESH, not five scattered probes.
	#
	# This used to sample the four corners and the centre of a 48-metre chunk,
	# which a fireball crater falls straight between: the ground genuinely went
	# below the water table and no water was drawn at all. Everything that
	# SAMPLES a point — is_underwater, the router, the drowning check — knew
	# there was water there; only the player could not see it, so villagers
	# walked into a dry-looking pit and drowned in nothing.
	#
	# The terrain pass already measured all 169 heights to build the mesh, so
	# the true minimum is free and exact.
	if _lowest >= WorldGen.WATER_LEVEL + 0.5:
		return
	# ...AND THE SEA HAS TO BE ABLE TO GET HERE.
	#
	# Measuring the true minimum fixed one bug and uncovered a worse one. The
	# plane is 48m of ocean at y=0, and it was drawn for the whole chunk the
	# moment ANY of its ground dipped below the waterline — including a fireball
	# crater a hundred and fifty metres inland, which then filled with sea that
	# had no way of reaching it. Villagers walked into it and drowned.
	#
	# So a chunk whose land was ALWAYS above the waterline only gets the sea if
	# the hole someone dug in it actually connects to open water; the seeded
	# minimum is measured alongside the real one above, and answers that for
	# free in every ordinary case.
	if _lowest_seeded >= WorldGen.WATER_LEVEL + 0.5 \
			and not world.sea_reaches(_deepest.x, _deepest.y):
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	var water := MeshInstance3D.new()
	_water = water
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	# Transparent + reflective water is heavy overdraw on tiled mobile GPUs,
	# so only the Medium/High tiers get the pretty version; Low tiers (budget
	# phones) get opaque matte water that reads fine and actually runs.
	if Quality.water_alpha():
		mat.albedo_color = Color(0.2, 0.42, 0.65, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.1
		mat.metallic = 0.3
	else:
		mat.albedo_color = Color(0.22, 0.44, 0.62)
		mat.roughness = 0.6
	water.material_override = mat
	water.position = Vector3(WorldGen.CHUNK_SIZE / 2.0, WorldGen.WATER_LEVEL, WorldGen.CHUNK_SIZE / 2.0)
	add_child(water)


## Scatter --------------------------------------------------------------------

func _scatter() -> void:
	var rng := world.chunk_rng(cell)
	var biome := world.biome_at(
		position.x + WorldGen.CHUNK_SIZE * 0.5, position.z + WorldGen.CHUNK_SIZE * 0.5)
	# THE WOOD FIRST, AND ALWAYS FIRST. Every arm below used to open with its
	# own `_scatter_trees` line; they are one call now, made before the match,
	# which draws from `rng` in exactly the order they did. That order is load-
	# bearing: the far ring replays this same stream to decide where the
	# billboards go, and if the two ever fall out of step the trees move as you
	# walk up to them.
	_plant_stand(_tree_stand(rng))
	match biome:
		"forest":
			_scatter_deposits(rng, rng.randi_range(1, 4))
			_scatter_bushes(rng, rng.randi_range(1, 3))
			_scatter_animals(rng, {"deer": 0.22, "elk": 0.18, "bear": 0.05,
				"wolf": 0.05, "tiger": 0.02})
		"grassland":
			_scatter_flowers(rng, rng.randi_range(6, 12))
			_scatter_deposits(rng, rng.randi_range(1, 4))
			_scatter_bushes(rng, rng.randi_range(2, 3))
			_scatter_animals(rng, {"sheep": 0.12, "horse": 0.1, "chicken": 0.12,
				"pig": 0.08, "dog": 0.04, "bison": 0.12})
		"savanna":
			_scatter_bushes(rng, rng.randi_range(1, 3))
			_scatter_animals(rng, {"giraffe": 0.12, "lion": 0.06, "llama": 0.12,
				"ox": 0.05, "anteater": 0.1, "coati": 0.12})
		"rocky_hills":
			_scatter_deposits(rng, rng.randi_range(4, 9))
			_scatter_bushes(rng, rng.randi_range(0, 2))
			_scatter_animals(rng, {"caribou": 0.03, "llama": 0.12, "elk": 0.1})
		# THE HOT DRY COUNTRY. Almost nothing grows and almost nothing lives here,
		# which is the point of it — a desert should be a place you cross.
		"desert":
			_scatter_deposits(rng, rng.randi_range(2, 5))
			_scatter_animals(rng, {"llama": 0.1, "giraffe": 0.06, "lion": 0.05,
				"dog": 0.03})
		# THE FAR COLD. Open, flat and full of big grazing beasts with wolves
		# and bears working them — the meat wall at its plainest.
		"tundra":
			_scatter_deposits(rng, rng.randi_range(2, 5))
			_scatter_animals(rng, {"caribou": 0.07, "bison": 0.12, "elk": 0.14,
				"deer": 0.12, "wolf": 0.07, "bear": 0.05, "dog": 0.03})
		# WHERE WETLAND MEETS FOREST. The densest, loudest, most crowded ground
		# in the world: everything small, everything at once, and a tiger in it.
		"rainforest":
			_scatter_bushes(rng, rng.randi_range(3, 5))
			_scatter_flowers(rng, rng.randi_range(4, 8))
			_scatter_animals(rng, {"coati": 0.2, "anteater": 0.16, "deer": 0.14,
				"frog": 0.7, "tiger": 0.05, "chicken": 0.14, "pig": 0.12})
		"wetland":
			_scatter_bushes(rng, rng.randi_range(2, 4))
			_scatter_animals(rng, {"frog": 0.9, "pig": 0.12, "anteater": 0.12,
				"coati": 0.1})


func _random_spot(rng: RandomNumberGenerator) -> Vector3:
	var x := rng.randf_range(2.0, WorldGen.CHUNK_SIZE - 2.0)
	var z := rng.randf_range(2.0, WorldGen.CHUNK_SIZE - 2.0)
	return Vector3(x, 0, z)


func _spot_ok(local: Vector3) -> bool:
	var wx := position.x + local.x
	var wz := position.z + local.z
	if world.is_underwater(wx, wz):
		return false
	# Keep wilderness clutter out of the player's founding meadow.
	if Vector2(wx, wz).length() < 24.0:
		return false
	return true


func _place(node: Node3D, local: Vector3, sink := 0.0) -> void:
	local.y = world.height_at(position.x + local.x, position.z + local.z) - sink
	node.position = local
	add_child(node)
	# Remembered so it can be set back down if the ground under it ever moves.
	# The sink rides along because a tree is planted slightly INTO the earth.
	node.set_meta("sink", sink)
	_standing.append(node)


## WHAT WOOD STANDS HERE, decided by the seed and nothing else.
##
## Deliberately separate from planting it. A chunk out in the far ring is never
## built as a place and has no trees at all, but it still has to draw them — so
## it asks this, off its own deterministic RNG, and gets exactly the answer the
## chunk would give if you walked up to it. Which is the whole trick: when it is
## promoted, every real tree stands where its billboard stood.
##
## The draws have to match the old inline version exactly, including the fact
## that a rejected spot consumes no seed and no lumber.
func _tree_stand(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var biome := world.biome_at(
		position.x + WorldGen.CHUNK_SIZE * 0.5, position.z + WorldGen.CHUNK_SIZE * 0.5)
	var out: Array[Dictionary] = []
	if not STAND.has(biome):
		return out
	var spec: Array = STAND[biome]
	for i in rng.randi_range(int(spec[0]), int(spec[1])):
		var spot := _random_spot(rng)
		if not _spot_ok(spot):
			continue
		var from_seed := rng.randi()
		# A natural mixed-age stand: some saplings, some giants.
		var carried := rng.randf_range(4.0, WildTree.MAX_LUMBER)
		out.append({"spot": spot, "seed": from_seed, "lumber": carried,
			"style": String(spec[2])})
	return out


func _plant_stand(stand: Array[Dictionary]) -> void:
	for it: Dictionary in stand:
		var tree := WildTree.new()
		tree.style = it["style"]
		tree.rng_seed = it["seed"]
		tree.lumber = it["lumber"]
		_place(tree, it["spot"], 0.1)
		Util.apply_lod(tree, Quality.clutter_distance())


func _scatter_bushes(rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var spot := _random_spot(rng)
		if not _spot_ok(spot):
			continue
		var bush := ForageBush.new()
		bush.berries = rng.randi_range(1, ForageBush.MAX_BERRIES)
		_place(bush, spot, 0.1)
		bush.rotation.y = rng.randf() * TAU  # a random facing, not all alike
		Util.apply_lod(bush, Quality.clutter_distance())


func _scatter_deposits(rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var spot := _random_spot(rng)
		if not _spot_ok(spot):
			continue
		var rock := RockDeposit.new()
		var shore: bool = world != null and spot.y - WorldGen.WATER_LEVEL < SHORE_WITHIN
		var ladder: Array[int] = SHINGLE if shore else STONE_SPREAD
		rock.rung = ladder[rng.randi() % ladder.size()]
		_place(rock, spot, 0.2)
		rock.rotation.y = rng.randf() * TAU  # a random facing, not all alike
		Util.apply_lod(rock, Quality.clutter_distance())


## Flowers are pure decoration and never move — so the whole chunk's worth
## collapses into ONE MultiMesh (one draw call, one mesh, one material): a
## billboard bloom per instance, tinted by per-instance colour. The old
## version was 7 high-poly nodes EACH; a meadow of them was a big slice of
## the resource burst that backgrounded budget phones as chunks streamed in.
func _scatter_flowers(rng: RandomNumberGenerator, count: int) -> void:
	# A custom flower model (res://models/flower.glb) replaces the billboard.
	# Either way it's ONE MultiMesh (a single draw call for the chunk's meadow),
	# and every bloom is a different hue, turned a different way, and sized a
	# little differently. For the custom mesh we clone its material with
	# vertex-colour tinting ON, so each instance's hue multiplies its texture.
	var custom := ModelBank.mesh_for("flower")
	var custom_mat: StandardMaterial3D = null
	if custom != null:
		var base := custom.surface_get_material(0)
		if base is StandardMaterial3D:
			custom_mat = (base as StandardMaterial3D).duplicate()
			custom_mat.vertex_color_use_as_albedo = true
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in count:
		var spot := _random_spot(rng)
		if not _spot_ok(spot):
			continue
		spot.y = world.height_at(position.x + spot.x, position.z + spot.z) + 0.02
		# Random yaw always; the 3D model also gets a natural lean and a size.
		var bloom := Basis(Vector3.UP, rng.randf() * TAU)
		if custom != null:
			var lean_ang := rng.randf() * TAU
			var lean_axis := Vector3(cos(lean_ang), 0.0, sin(lean_ang))
			bloom = Basis(lean_axis, deg_to_rad(rng.randf_range(0.0, 18.0))) * bloom
			bloom = bloom.scaled(Vector3.ONE * rng.randf_range(2.4, 4.0))
		xforms.append(Transform3D(bloom, spot))
		colors.append(Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.85), 0.98))
		# WHERE THE FLOWERS ACTUALLY ARE. A MultiMesh has no nodes to find, so
		# the meadow would otherwise be invisible to everything but the camera —
		# and the bees have to be over real blooms rather than over grass that
		# happens to be the right biome. Kept in world space, a Vector3 each.
		_blooms.append(Vector3(position.x + spot.x, spot.y, position.z + spot.z))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = custom if custom != null else Util.blossom_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Custom: the cloned, vertex-tinted texture material. Billboard: its shared
	# white material. (If the model carried no readable material, its own one is
	# used as-is — textured, just untinted.)
	mmi.material_override = custom_mat if custom != null else Util.blossom_material()
	Util.apply_lod(mmi, Quality.clutter_distance())
	add_child(mmi)


## HERDS, NOT INDIVIDUALS. The numbers in each table are now the chance of a
## HERD being seeded here, not of one beast — so they are much smaller than they
## were and the world is much fuller, which is the whole point. A chunk used to
## scatter about one and a fifth beasts and stop at four; a single reindeer herd
## now averages a hundred and one head.
##
## What makes that affordable is that a herd draws as one MultiMesh and promotes
## only the nearest handful to real Animals — see Herd. The cap that used to sit
## here is gone because it was counting the wrong thing: what has to be bounded
## is ANIMALS, and that is bounded globally by Quality.herd_agents() rather than
## locally by how many bodies one patch of grass may hold.
func _scatter_animals(rng: RandomNumberGenerator, table: Dictionary) -> void:
	var herds := 0
	for species: String in table:
		var chance: float = table[species]
		var many := int(chance) + (1 if rng.randf() < fmod(chance, 1.0) else 0)
		for i in many:
			if herds >= 2:
				return          # two herds to a chunk; the world is wide
			var spot := _random_spot(rng)
			if not _spot_ok(spot):
				continue
			var herd := Herd.create(species, Herd.roll_for(species, rng), world)
			_place(herd, spot, 0.0)
			herds += 1
