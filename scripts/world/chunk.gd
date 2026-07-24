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
