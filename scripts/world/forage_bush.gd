class_name ForageBush
extends StaticBody3D
## A wild berry bush. Villagers forage it when the granary runs dry;
## herbivores browse it between trips to water. Berries regrow with time,
## so the land itself is a slow, renewable larder.

const MAX_BERRIES := 10
const REGROW_SECONDS := 45.0
const RAIN_REGROW := 0.45   # rain shortens the regrow wait to this fraction

var berries := 3

var _berry_meshes: Array[MeshInstance3D] = []
var _regrow_time := REGROW_SECONDS
var _rain_time := 0.0


func _ready() -> void:
	add_to_group("forage")
	collision_layer = 4
	collision_mask = 0
	set_meta("hover_name", "Forage bush")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	add_child(col)

	var custom := ModelBank.instantiate("bush")
	if custom != null:
		# A custom bush carries its own berries; the pickable count still works.
		add_child(custom)
	else:
		var leaf := Color(0.18, 0.38, 0.16)
		add_child(Util.lite_sphere(0.65, leaf, Vector3(0, 0.45, 0)))
		add_child(Util.lite_sphere(0.45, leaf.lightened(0.1), Vector3(0.4, 0.35, 0.2)))
		add_child(Util.lite_sphere(0.4, leaf.lightened(0.05), Vector3(-0.35, 0.35, -0.15)))
		for i in MAX_BERRIES:
			var a := TAU * i / MAX_BERRIES + 0.5
			var berry := Util.lite_sphere(0.09, Color(0.75, 0.15, 0.25),
				Vector3(cos(a) * 0.45, 0.65 + sin(i * 2.1) * 0.15, sin(a) * 0.45))
			add_child(berry)
			_berry_meshes.append(berry)
	_update_berries()


func _process(delta: float) -> void:
	if berries >= MAX_BERRIES:
		return
	# Berries ripen over time — faster in the rain (the land's slow larder,
	# quickened by a downpour).
	var step := delta
	if _rain_time > 0.0:
		_rain_time -= delta
		step = delta / RAIN_REGROW
	_regrow_time -= step
	if _regrow_time <= 0.0:
		_regrow_time = REGROW_SECONDS
		berries += 1
		_update_berries()


## A rain miracle passing over quickens the ripening for a while.
func rain(duration: float) -> void:
	_rain_time = maxf(_rain_time, duration)


func has_berries() -> bool:
	return berries > 0


## One handful picked (by hand, hoof, or beak). False if bare. A bush picked
## to nothing is spent — it withers away (berries range 1..10; zero is death).
func take_berry() -> bool:
	if berries <= 0:
		return false
	berries -= 1
	_regrow_time = REGROW_SECONDS
	_update_berries()
	if berries <= 0:
		queue_free()
	return true


func _update_berries() -> void:
	for i in _berry_meshes.size():
		_berry_meshes[i].visible = i < berries


func hover_text() -> String:
	return "Forage bush — %d berries" % berries
