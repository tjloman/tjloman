class_name Farm
extends Node3D
## A field of crops that grows food over time. The soil is a low mesh whose
## vertices sit on the terrain, so the field hugs every rise and dip of the
## land instead of floating on a platform (and it renders on every backend,
## unlike a Decal — which crashed some mobile GPUs). Crops are planted at
## the real ground height beneath each row. Villagers tend it (faster
## growth), rain multiplies it, harvest banks it in the store.

const BASE_GROWTH_PER_SEC := 0.008
const TEND_BONUS_PER_SEC := 0.03
const MAX_TENDERS := 3      # extra hands beyond this add nothing
const RAIN_MULTIPLIER := 4.0
const HARVEST_YIELD := 7
const HALF_X := 3.5
const HALF_Z := 2.5

var growth := 0.4  # 0..1; harvestable at >= 0.8
var _rain_time_left := 0.0
var _tenders := 0
var _crop_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("farms")
	set_meta("hover_name", "Farm")
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen

	_build_soil(world)

	# Crops planted in rows, each at the true ground height under its spot.
	# base_y = the ground the crop grows out of; it scales up from there.
	for x in 4:
		for z in 3:
			var lx := -2.4 + x * 1.6
			var lz := -1.5 + z * 1.5
			var ground_y := _local_ground(world, lx, lz)
			var crop := Util.box(Vector3(0.4, 1.0, 0.4), Color(0.35, 0.7, 0.25),
				Vector3(lx, ground_y, lz))
			crop.set_meta("base_y", ground_y)
			add_child(crop)
			_crop_meshes.append(crop)


## The terrain height at a field-local offset, in the farm's local space.
func _local_ground(world: WorldGen, lx: float, lz: float) -> float:
	if world == null:
		return -0.05
	return world.height_at(global_position.x + lx, global_position.z + lz) - global_position.y - 0.05


## A tilled-soil mesh whose vertices ride the terrain — hugging the land on
## every renderer, no Decal required.
func _build_soil(world: WorldGen) -> void:
	var cols := 7
	var rows := 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rows:
		for c in cols:
			var x0 := lerpf(-HALF_X, HALF_X, float(c) / cols)
			var x1 := lerpf(-HALF_X, HALF_X, float(c + 1) / cols)
			var z0 := lerpf(-HALF_Z, HALF_Z, float(r) / rows)
			var z1 := lerpf(-HALF_Z, HALF_Z, float(r + 1) / rows)
			var furrow := 0.04 if c % 2 == 0 else 0.0
			var soil := Color(0.36 - furrow, 0.26 - furrow, 0.16)
			var p00 := Vector3(x0, _local_ground(world, x0, z0) + 0.06, z0)
			var p10 := Vector3(x1, _local_ground(world, x1, z0) + 0.06, z0)
			var p11 := Vector3(x1, _local_ground(world, x1, z1) + 0.06, z1)
			var p01 := Vector3(x0, _local_ground(world, x0, z1) + 0.06, z1)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.set_color(soil)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)


func _process(delta: float) -> void:
	var rate := BASE_GROWTH_PER_SEC
	if _rain_time_left > 0.0:
		_rain_time_left -= delta
		rate *= RAIN_MULTIPLIER
	# Many hands make crops grow: each tender adds their bonus, up to a cap.
	rate += TEND_BONUS_PER_SEC * mini(_tenders, MAX_TENDERS)
	growth = clampf(growth + rate * delta, 0.0, 1.0)
	_tenders = 0  # workers re-assert this every frame they work

	# Crops rise straight out of the soil: bottom pinned to the ground it
	# was planted on, growing taller with maturity.
	var height := 0.15 + growth * 1.1
	for crop in _crop_meshes:
		crop.scale.y = height              # box mesh is 1m tall, so scale == metres
		crop.position.y = crop.get_meta("base_y") + height * 0.5


func tend() -> void:
	_tenders += 1


func is_harvestable() -> bool:
	return growth >= 0.8


func harvest() -> int:
	if not is_harvestable():
		return 0
	growth = 0.05
	return HARVEST_YIELD


func water(duration: float) -> void:
	_rain_time_left = maxf(_rain_time_left, duration)


func hover_text() -> String:
	return "Farm — %d%% grown%s" % [int(growth * 100), " (rain-blessed)" if _rain_time_left > 0 else ""]
