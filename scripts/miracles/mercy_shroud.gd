class_name MercyShroud
extends Node3D
## THE MERCY, WORN.
##
##   S  (rev)  O  )      water + calm + life + ward
##
## Water, calm and life is already the healing shower: a green rain over a spot
## that puts fires out and mends what is hurt. `ward` is the rune of a thing
## held OVER something, and adding it does here exactly what it does in the
## storm — it stops being a place and starts being a thing the creature WEARS.
##
## That is the whole grammar of the shrouds, and it is one rune long: cast a
## working at a spot, add `ward`, and it follows your beast about instead.
##
## It does not look like rain. Gentle waves of light come down out of the sky
## around the creature, gold and a soft silvery grey, spreading outward at its
## feet and going out — and everything that walks into them stops burning and
## starts mending. Including the creature. ESPECIALLY the creature: this is the
## one thing in the spellbook that answers a beast which has been hurt and is a
## long way from anybody who could help it.

## How long it holds, and how much longer a strong working keeps it.
const SECONDS := 30.0
const SECONDS_PER_POTENCY := 14.0
const GRANTED_WITHIN := 60.0

## How wide the kindness reaches round the beast, plus a share of its own size.
const SHROUD := 9.0
const SHROUD_PER_SIZE := 0.45

## How often the mercy actually lands. The same half-second beat the healing
## shower keeps, so walking somebody INTO it saves them at the same rate
## whichever of the two is falling on them.
const WORK_EVERY := 0.5

## THE WAVES. One every so often, rising from the ground and spreading out as it
## fades — and they alternate, because the two colours arriving together is a
## glow and the two arriving in turn is a rhythm.
const WAVE_EVERY := 0.85
const WAVE_LIVES := 2.1
const WAVE_RISE := 2.6
const GOLD := Color(1.0, 0.88, 0.55)
const SILVER := Color(0.82, 0.86, 0.9)

## The column of light standing over it, and the motes drifting down inside it.
const SHAFT_HIGH := 26.0
const MOTES := 90

## How often the village is moved by the sight of it.
const AWE_EVERY := 10.0
const AWE_PAY := 3.0


var creature: Creature = null
var left := 0.0

var _shaft: MeshInstance3D = null
var _motes: CPUParticles3D = null
var _lamp: OmniLight3D = null
var _until_work := 0.0
var _until_wave := 0.0
var _until_awe := AWE_EVERY
var _silvered := false


## PUT IT ON. Cast again to hold it longer rather than to wear two.
static func grant(who: Creature, seconds: float) -> MercyShroud:
	var worn := holding(who)
	if worn != null:
		worn.left = maxf(worn.left, seconds)
		return worn
	var shroud := MercyShroud.new()
	shroud.creature = who
	shroud.left = seconds
	who.add_child(shroud)
	return shroud


static func holding(who: Creature) -> MercyShroud:
	for child in who.get_children():
		if child is MercyShroud:
			return child as MercyShroud
	return null


func _ready() -> void:
	# TOP LEVEL for the same reason the storm is: the creature grows to fifteen
	# times its own size and Godot scales a child along with its parent, so a
	# shroud inside that transform would be a candle on a hatchling and a
	# lighthouse on a grown beast, from one set of numbers.
	top_level = true
	_build()


func _build() -> void:
	# A soft column standing over it — the light coming DOWN, which is the half
	# of this that says where it is from.
	var pillar := CylinderMesh.new()
	pillar.top_radius = SHROUD * 0.9
	pillar.bottom_radius = SHROUD * 0.55
	pillar.height = SHAFT_HIGH
	_shaft = Util.mesh_node(pillar, Color(1.0, 0.93, 0.7, 0.10), Vector3.ZERO, true) as MeshInstance3D
	add_child(_shaft)

	_motes = CPUParticles3D.new()
	_motes.amount = Quality.particles(MOTES)
	_motes.lifetime = 3.2
	_motes.mesh = Util.speck_mesh(0.12, 0.12, GOLD, true)
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(SHROUD, 0.5, SHROUD)
	_motes.direction = Vector3.DOWN
	_motes.initial_velocity_min = 1.2
	_motes.initial_velocity_max = 2.6
	_motes.gravity = Vector3(0, -0.8, 0)
	add_child(_motes)

	_lamp = OmniLight3D.new()
	_lamp.light_color = GOLD
	_lamp.light_energy = 2.2
	_lamp.omni_range = SHROUD * 2.4
	_lamp.shadow_enabled = false
	add_child(_lamp)


func _physics_process(delta: float) -> void:
	Ledger.open(&"MercyShroud")
	if creature == null or not is_instance_valid(creature):
		queue_free()
		return
	left -= delta
	if left <= 0.0:
		GameState.announce("The light round your creature fades out of the air.")
		queue_free()
		return
	_follow()
	_tick_waves(delta)
	_tick_work(delta)
	_tick_awe(delta)


func _follow() -> void:
	var here := creature.global_position
	global_position = here
	var span := _reach()
	if is_instance_valid(_shaft):
		_shaft.global_position = here + Vector3.UP * (SHAFT_HIGH * 0.5)
		_shaft.scale = Vector3(span / SHROUD, 1.0, span / SHROUD)
	if is_instance_valid(_motes):
		_motes.global_position = here + Vector3.UP * (SHAFT_HIGH * 0.45)
		_motes.emission_box_extents = Vector3(span, 0.5, span)
	if is_instance_valid(_lamp):
		_lamp.global_position = here + Vector3.UP * 2.0
		_lamp.omni_range = span * 2.4
		# It breathes rather than burns steady, which is the difference between
		# a blessing and a floodlight.
		_lamp.light_energy = 2.0 + sin(float(Time.get_ticks_msec()) / 620.0) * 0.5


func _reach() -> float:
	return SHROUD + creature.scale.x * SHROUD_PER_SIZE


## ONE WAVE. A ring at the creature's feet that widens, lifts a little and
## fades — gold, then silver, then gold, so it reads as something arriving
## again and again rather than as a lamp that happens to be on.
func _tick_waves(delta: float) -> void:
	_until_wave -= delta
	if _until_wave > 0.0:
		return
	_until_wave = WAVE_EVERY
	_silvered = not _silvered
	var here := creature.global_position
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	var wave := Util.mesh_node(ring, SILVER if _silvered else GOLD,
		here + Vector3.UP * 0.3, true)
	get_tree().current_scene.add_child(wave)
	wave.global_position = here + Vector3.UP * 0.3
	var span := _reach()
	var sweep := create_tween()
	sweep.tween_property(wave, "scale", Vector3(span, 1.0, span), WAVE_LIVES)
	sweep.parallel().tween_property(wave, "global_position",
		here + Vector3.UP * WAVE_RISE, WAVE_LIVES)
	sweep.parallel().tween_property(wave, "transparency", 1.0, WAVE_LIVES)
	sweep.tween_callback(wave.queue_free)


## AND IT IS THE SAME MERCY. Through the manager's own door, so what it douses
## and mends is exactly what the healing shower douses and mends — the herd
## mass included, which is where nearly all the animals in the world are.
func _tick_work(delta: float) -> void:
	_until_work -= delta
	if _until_work > 0.0:
		return
	_until_work = WORK_EVERY
	var manager := MiracleManager.of(get_tree())
	if manager != null:
		manager.mercy_upon(creature.global_position, _reach())


func _tick_awe(delta: float) -> void:
	_until_awe -= delta
	if _until_awe > 0.0:
		return
	_until_awe = AWE_EVERY
	VillageWonder.spectacle(get_tree(), "blessed", "wonder", creature.global_position,
		AWE_PAY, "Light is falling on your creature out of a clear sky.", creature)
	creature.heart.stir("relief", 0.2)
