class_name Farm
extends Node3D
## A field that grows food over time. Villagers tend it (speeds growth) and
## harvest it into the village store. Rain miracles multiply growth rate.

const BASE_GROWTH_PER_SEC := 0.008
const TEND_BONUS_PER_SEC := 0.03
const MAX_TENDERS := 3      # extra hands beyond this add nothing
const RAIN_MULTIPLIER := 4.0
const HARVEST_YIELD := 7

var growth := 0.4  # 0..1; harvestable at >= 0.8
var _rain_time_left := 0.0
var _tenders := 0
var _crop_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("farms")
	set_meta("hover_name", "Farm")
	# Earthen bed sunk into the slope so the field never floats.
	add_child(Util.box(Vector3(7.4, 1.2, 5.4), Color(0.4, 0.29, 0.19), Vector3(0, -0.5, 0)))
	add_child(Util.box(Vector3(7, 0.15, 5), Color(0.45, 0.32, 0.2), Vector3(0, 0.07, 0)))
	for x in 4:
		for z in 3:
			var crop := Util.box(
				Vector3(0.4, 1.0, 0.4), Color(0.35, 0.7, 0.25),
				Vector3(-2.4 + x * 1.6, 0.15, -1.5 + z * 1.5))
			add_child(crop)
			_crop_meshes.append(crop)


func _process(delta: float) -> void:
	var rate := BASE_GROWTH_PER_SEC
	if _rain_time_left > 0.0:
		_rain_time_left -= delta
		rate *= RAIN_MULTIPLIER
	# Many hands make crops grow: each tender adds their bonus, up to a cap.
	rate += TEND_BONUS_PER_SEC * mini(_tenders, MAX_TENDERS)
	growth = clampf(growth + rate * delta, 0.0, 1.0)
	_tenders = 0  # workers re-assert this every frame they work

	var height := 0.15 + growth * 1.1
	for crop in _crop_meshes:
		crop.scale.y = height
		crop.position.y = height * 0.5


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
