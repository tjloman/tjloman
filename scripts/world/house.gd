class_name House
extends Node3D
## A dwelling with a lifespan of its own: health and age meters, capacity by
## size, decay in old age, collapse into rubble, and construction/repair by
## builders. Windows glow warm at night — unless nobody lives there.

enum Size { HUT, HOUSE, LONGHOUSE }

## capacity / lumber cost / stone cost / footprint by size
const SPECS := {
	Size.HUT: {"capacity": 2, "lumber": 4, "stone": 2, "width": 2.0},
	Size.HOUSE: {"capacity": 4, "lumber": 8, "stone": 4, "width": 2.8},
	Size.LONGHOUSE: {"capacity": 6, "lumber": 14, "stone": 8, "width": 3.6},
}

const BUILD_RATE := 14.0        # construction progress per builder-second
const DECAY_START_AGE := 30.0   # years before a house starts crumbling

var size := Size.HUT
var health := 100.0
var age := 0.0                  # years
var occupied := false           # kept current by Village._assign_housing
var under_construction := false
var progress := 0.0             # 0..100 while under construction
var village: Village

var _window_mat: StandardMaterial3D
var _night_check := 0.0


func _ready() -> void:
	add_to_group("houses")
	if under_construction:
		health = 100.0
		_build_scaffold_visuals()
	else:
		_build_visuals()


func capacity() -> int:
	return 0 if under_construction else SPECS[size]["capacity"]


func _process(delta: float) -> void:
	if under_construction:
		return
	var years := delta / GameState.YEAR_SECONDS
	age += years
	# A lived-in house is a kept house: hearth smoke, patched thatch,
	# swept steps. Only EMPTY houses crumble with age.
	if age > DECAY_START_AGE and not occupied:
		health -= (1.0 + (age - DECAY_START_AGE) * 0.16) * years
		if health <= 0.0:
			_collapse()
			return

	_night_check -= delta
	if _night_check <= 0.0:
		_night_check = 2.0
		if _window_mat != null:
			_window_mat.emission_enabled = GameState.is_night()


## Builders call this each working tick.
func advance_construction(amount: float) -> void:
	if not under_construction:
		return
	progress += amount
	if progress >= 100.0:
		under_construction = false
		age = 0.0
		health = 100.0
		_clear_visuals()
		_build_visuals()
		if village != null:
			village.on_house_completed(self)


func repair(amount: float) -> void:
	health = minf(health + amount, 100.0)


## Sudden harm (fireballs, catastrophes) — collapses outright at zero.
func damage(amount: float) -> void:
	if under_construction:
		return
	health -= amount
	if health <= 0.0:
		_collapse()


func needs_repair() -> bool:
	return not under_construction and health < 55.0


func _collapse() -> void:
	GameState.announce("A %s in %s has collapsed with age." % [
		size_name().to_lower(), village.village_name if village != null else "the wilds"])
	SoundBank.play_at("hammer", global_position, -2.0)
	_clear_visuals()
	# Rubble lingers a while, then fades.
	for i in 4:
		add_child(Util.box(
			Vector3(randf_range(0.4, 0.9), 0.3, randf_range(0.4, 0.9)),
			Color(0.5, 0.44, 0.38),
			Vector3(randf_range(-1, 1), 0.15, randf_range(-1, 1))))
	if village != null:
		village.on_house_destroyed(self)
	get_tree().create_timer(30.0).timeout.connect(queue_free)
	set_process(false)


## Visuals -------------------------------------------------------------------

func _clear_visuals() -> void:
	for child in get_children():
		child.queue_free()


func _build_visuals() -> void:
	var w: float = SPECS[size]["width"]
	var depth := w * (1.6 if size == Size.LONGHOUSE else 1.0)
	var wall := Color(0.78, 0.68, 0.52)
	var roof := Color(0.62, 0.28, 0.22)

	# A stone foundation, sunk into the earth: on sloped ground it bridges
	# the gap on the downhill side instead of leaving the house floating.
	add_child(Util.box(Vector3(w + 0.5, 1.2, depth + 0.5), Color(0.52, 0.5, 0.47),
		Vector3(0, -0.45, 0)))
	add_child(Util.box(Vector3(w, 1.9, depth), wall, Vector3(0, 0.95, 0)))
	add_child(Util.prism(Vector3(w + 0.5, 1.1, depth + 0.5), roof, Vector3(0, 2.45, 0)))
	# Door.
	add_child(Util.box(Vector3(0.5, 1.1, 0.1), Color(0.4, 0.28, 0.18),
		Vector3(0, 0.55, depth / 2.0 + 0.03)))
	# Windows, which glow at night.
	_window_mat = Util.mat(Color(1.0, 0.85, 0.5))
	_window_mat.emission = Color(1.0, 0.75, 0.35)
	_window_mat.emission_energy_multiplier = 2.0
	_window_mat.emission_enabled = false
	for x in [-w / 3.0, w / 3.0]:
		var pane := Util.box(Vector3(0.4, 0.4, 0.06), Color.WHITE, Vector3(x, 1.3, depth / 2.0 + 0.03))
		pane.material_override = _window_mat
		add_child(pane)


func _build_scaffold_visuals() -> void:
	var w: float = SPECS[size]["width"]
	# The foundation is laid first — construction sites sit on it too.
	add_child(Util.box(Vector3(w + 0.5, 1.2, w + 0.5), Color(0.52, 0.5, 0.47),
		Vector3(0, -0.45, 0)))
	# Corner posts and one beam: enough to read as "under construction".
	for corner in [Vector3(w / 2, 0, w / 2), Vector3(-w / 2, 0, w / 2),
			Vector3(w / 2, 0, -w / 2), Vector3(-w / 2, 0, -w / 2)]:
		add_child(Util.box(Vector3(0.15, 1.8, 0.15), Color(0.6, 0.45, 0.3),
			corner + Vector3(0, 0.9, 0)))
	add_child(Util.box(Vector3(w, 0.12, 0.12), Color(0.6, 0.45, 0.3), Vector3(0, 1.85, w / 2)))


func size_name() -> String:
	return ["Hut", "House", "Longhouse"][size]


func hover_text() -> String:
	var census := ""
	if village != null and is_instance_valid(village):
		census = "\n%s — population %d" % [village.village_name, village.population()]
	if under_construction:
		return "%s under construction — %d%%%s" % [size_name(), int(progress), census]
	return "%s — health %d%%, age %d years, sleeps %d%s" % [
		size_name(), int(health), int(age), capacity(), census]
