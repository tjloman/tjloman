class_name Chunk
extends Node3D
## One 48m square of the endless world: terrain mesh (vertex-colored by
## biome/slope/altitude), heightmap collision, a water quad where the land
## dips below the water table, and everything scattered on it — trees, rock
## deposits, flowers, and wildlife. All deterministic from the world seed.

var world: WorldGen
var cell := Vector2i.ZERO


func _ready() -> void:
	_build_terrain()
	_build_water()
	_scatter()


func _build_terrain() -> void:
	var cells := WorldGen.CHUNK_CELLS
	var step := WorldGen.CHUNK_SIZE / cells
	var heights := PackedFloat32Array()
	heights.resize((cells + 1) * (cells + 1))

	# Sample the height grid (in world space; chunk origin is our position).
	for z in cells + 1:
		for x in cells + 1:
			heights[z * (cells + 1) + x] = world.height_at(
				position.x + x * step, position.z + z * step)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in cells:
		for x in cells:
			var x0 := x * step
			var z0 := z * step
			var corners := [
				Vector3(x0, heights[z * (cells + 1) + x], z0),
				Vector3(x0 + step, heights[z * (cells + 1) + x + 1], z0),
				Vector3(x0 + step, heights[(z + 1) * (cells + 1) + x + 1], z0 + step),
				Vector3(x0, heights[(z + 1) * (cells + 1) + x], z0 + step),
			]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = corners[idx]
				st.set_color(world.ground_color(position.x + v.x, position.z + v.z, v.y))
				st.add_vertex(v)
	st.generate_normals()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	# Heightmap collision (layer 1 = ground).
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("ground")
	var shape := CollisionShape3D.new()
	var hshape := HeightMapShape3D.new()
	hshape.map_width = cells + 1
	hshape.map_depth = cells + 1
	hshape.map_data = heights
	shape.shape = hshape
	shape.scale = Vector3(step, 1.0, step)
	shape.position = Vector3(WorldGen.CHUNK_SIZE / 2.0, 0, WorldGen.CHUNK_SIZE / 2.0)
	body.add_child(shape)
	add_child(body)


func _build_water() -> void:
	# Only bother if any corner/center of the chunk is below the water table.
	var has_water := false
	for probe in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0.5)]:
		if world.height_at(
				position.x + probe.x * WorldGen.CHUNK_SIZE,
				position.z + probe.y * WorldGen.CHUNK_SIZE) < WorldGen.WATER_LEVEL + 0.5:
			has_water = true
			break
	if not has_water:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(WorldGen.CHUNK_SIZE, WorldGen.CHUNK_SIZE)
	var water := MeshInstance3D.new()
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
			_scatter_flowers(rng, rng.randi_range(3, 6))
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


func _scatter_bushes(rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var spot := _random_spot(rng)
		if not _spot_ok(spot):
			continue
		var bush := ForageBush.new()
		bush.berries = rng.randi_range(1, ForageBush.MAX_BERRIES)
		_place(bush, spot, 0.1)


func _scatter_deposits(rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var spot := _random_spot(rng)
		if not _spot_ok(spot):
			continue
		_place(RockDeposit.new(), spot, 0.2)


## Small flowers that read as flowers: a ring of petals around a bright
## center on a short stem (no more mysterious pushpins).
func _scatter_flowers(rng: RandomNumberGenerator, count: int) -> void:
	for i in count:
		var spot := _random_spot(rng)
		if not _spot_ok(spot):
			continue
		var petal_color := Color.from_hsv(rng.randf(), 0.65, 0.95)
		var flower := Node3D.new()
		flower.add_child(Util.cylinder(0.015, 0.25, Color(0.3, 0.5, 0.25), Vector3(0, 0.12, 0)))
		flower.add_child(Util.sphere(0.045, Color(0.95, 0.85, 0.3), Vector3(0, 0.26, 0)))
		for p in 5:
			var a := TAU * p / 5.0
			flower.add_child(Util.sphere(0.05, petal_color,
				Vector3(cos(a) * 0.07, 0.26, sin(a) * 0.07)))
		_place(flower, spot, 0.02)


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
