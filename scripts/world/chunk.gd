class_name Chunk
extends Node3D
## One 48m square of the endless world: terrain mesh (vertex-colored by
## biome/slope/altitude), heightmap collision, a water quad where the land
## dips below the water table, and everything scattered on it — trees, rock
## deposits, flowers, and wildlife. All deterministic from the world seed.

var world: WorldGen
var cell := Vector2i.ZERO

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
## Every bloom scattered here, in world space — read by TreeFriends so bees and
## moths can be over the flowers instead of near them.
var _blooms: PackedVector3Array = PackedVector3Array()
## Everything scattered here that has to be set back down on the new ground.
var _standing: Array[Node3D] = []


func _ready() -> void:
	_build_terrain()
	_build_water()
	_scatter()


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
	_build_water()
	_reground()


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
	var cells := world.chunk_cells
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

	# Heightmap collision (layer 1 = ground).
	var body := StaticBody3D.new()
	_body = body
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionShape3D.new()
	var hshape := HeightMapShape3D.new()
	hshape.map_width = wide
	hshape.map_depth = wide
	hshape.map_data = heights
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
	var cells := world.chunk_cells
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
	var cells := world.chunk_cells
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
	st.generate_normals()

	if _ground != null and is_instance_valid(_ground):
		_ground.queue_free()
	_ground = MeshInstance3D.new()
	_ground.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	_ground.material_override = mat
	add_child(_ground)


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
	match biome:
		"forest":
			_scatter_trees(rng, rng.randi_range(5, 8), "forest")
			_scatter_deposits(rng, rng.randi_range(0, 1))
			_scatter_bushes(rng, rng.randi_range(1, 3))
			_scatter_animals(rng, {"deer": 0.9, "bear": 0.12, "wolf": 0.12, "tiger": 0.04})
		"grassland":
			_scatter_trees(rng, rng.randi_range(1, 3), "grassland")
			_scatter_flowers(rng, rng.randi_range(6, 12))
			_scatter_deposits(rng, rng.randi_range(0, 1))
			_scatter_bushes(rng, rng.randi_range(2, 3))
			_scatter_animals(rng, {"sheep": 0.8, "horse": 0.25, "chicken": 0.3,
				"pig": 0.2, "dog": 0.1})
		"savanna":
			_scatter_trees(rng, rng.randi_range(2, 4), "savanna")
			_scatter_bushes(rng, rng.randi_range(1, 3))
			_scatter_animals(rng, {"giraffe": 0.3, "lion": 0.15, "llama": 0.3, "ox": 0.25})
		"rocky_hills":
			_scatter_trees(rng, rng.randi_range(0, 1), "forest")
			_scatter_deposits(rng, rng.randi_range(2, 4))
			_scatter_bushes(rng, rng.randi_range(0, 2))
			_scatter_animals(rng, {"llama": 0.15})
		"wetland":
			_scatter_trees(rng, rng.randi_range(1, 3), "wetland")
			_scatter_bushes(rng, rng.randi_range(2, 4))
			_scatter_animals(rng, {"frog": 1.4, "pig": 0.25})


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


func _scatter_trees(rng: RandomNumberGenerator, count: int, style: String) -> void:
	for i in count:
		var spot := _random_spot(rng)
		if not _spot_ok(spot):
			continue
		var tree := WildTree.new()
		tree.style = style
		tree.rng_seed = rng.randi()
		# A natural mixed-age stand: some saplings, some giants.
		tree.lumber = rng.randf_range(4.0, WildTree.MAX_LUMBER)
		_place(tree, spot, 0.1)
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


func _scatter_animals(rng: RandomNumberGenerator, table: Dictionary) -> void:
	var spawned := 0
	for species: String in table:
		var expected: float = table[species]
		var count := int(expected) + (1 if rng.randf() < fmod(expected, 1.0) else 0)
		for i in count:
			if spawned >= 4:
				return
			var spot := _random_spot(rng)
			if not _spot_ok(spot):
				continue
			var animal := Animal.create(species)
			_place(animal, spot, -0.4)
			spawned += 1
