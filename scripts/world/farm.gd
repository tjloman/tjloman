class_name Farm
extends Node3D
## A field of crops that grows food over time. The soil is a DECAL projected
## straight down onto the terrain, so the field follows the contours of the
## land instead of floating on a platform; the crops are planted at the real
## ground height beneath each row. Villagers tend it (faster growth), rain
## multiplies it, harvest banks it in the store.

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

	# The soil, painted onto the land: a decal projects down onto whatever
	# terrain lies beneath, hugging every rise and dip.
	var decal := Decal.new()
	decal.texture_albedo = _soil_texture()
	decal.size = Vector3(HALF_X * 2.0 + 0.6, 8.0, HALF_Z * 2.0 + 0.6)
	decal.position = Vector3(0, 0, 0)
	add_child(decal)

	# Crops planted in rows, each at the true ground height under its spot.
	# base_y = the ground the crop grows out of; it scales up from there.
	for x in 4:
		for z in 3:
			var lx := -2.4 + x * 1.6
			var lz := -1.5 + z * 1.5
			var ground_y := -0.05
			if world != null:
				ground_y = world.height_at(global_position.x + lx, global_position.z + lz) \
					- global_position.y - 0.05
			var crop := Util.box(Vector3(0.4, 1.0, 0.4), Color(0.35, 0.7, 0.25),
				Vector3(lx, ground_y, lz))
			crop.set_meta("base_y", ground_y)
			add_child(crop)
			_crop_meshes.append(crop)


## A simple tilled-soil texture: brown with darker furrow stripes.
func _soil_texture() -> ImageTexture:
	var img := Image.create(48, 48, false, Image.FORMAT_RGB8)
	for y in 48:
		for x in 48:
			var furrow := 0.0 if (x / 4) % 2 == 0 else 0.08
			var n := (sin(x * 1.7) * cos(y * 2.1)) * 0.03
			img.set_pixel(x, y, Color(0.36 - furrow + n, 0.26 - furrow + n, 0.16 + n))
	return ImageTexture.create_from_image(img)


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
