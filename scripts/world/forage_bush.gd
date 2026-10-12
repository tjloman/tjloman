class_name ForageBush
extends StaticBody3D
## A wild berry bush. Villagers forage it when the granary runs dry;
## herbivores browse it between trips to water. Berries regrow with time,
## so the land itself is a slow, renewable larder.
##
## AND IT BURNS. A bush is the driest thing on a hillside, and nothing in the
## game could set one alight: every fire swept the trees, the fields and what a
## town built, and walked straight past the brush. A tree burning beside one
## deleted it without a flame. It is BURNABLE now (Affords), so whatever warms
## a wall warms a bush — and, being tinder, it goes at the first touch, burns
## for a few seconds, passes the fire on to the brush and wood beside it, and
## is gone.

const MAX_BERRIES := 10
const REGROW_SECONDS := 45.0
const RAIN_REGROW := 0.45   # rain shortens the regrow wait to this fraction

## Tinder: any heat that would warm a wall lights it (a burning tree gives 25).
const CATCHES := 20.0
const BURNS_FOR := 9.0
## Once, halfway through its burn, it reaches over to what stands beside it.
const SPREAD_REACH := 5.0
const SPREAD_ODDS := 0.5
## Brush this close is one thicket: it always goes.
const TOUCHING := 2.5
## What a thrown rock or a trampling takes to flatten it.
const HEALTH := 20.0

var berries := 3
var burning := false
var health := HEALTH

var _berry_meshes: Array[MeshInstance3D] = []
var _regrow_time := REGROW_SECONDS
var _rain_time := 0.0
var _burn_left := 0.0
var _spread := false
var _fire: Node3D = null


func _ready() -> void:
	add_to_group("forage")
	add_to_group(Affords.BURNABLE)
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
		# ON ITS FOOTING, whatever pivot the model was authored with — the
		# same answer, from the same place, that a beast is stood up with.
		# A model pivoted at its middle sinks to the waist without this,
		# which is what "buildings are spawning below ground" was.
		custom.position.y += ModelBank.footing("bush")
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
	Ledger.open(&"ForageBush")
	if burning:
		_burn(delta)
		return
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


## Fire ------------------------------------------------------------------------

## ALIGHT, and the berries with it. Not under water.
func ignite() -> void:
	if burning or is_queued_for_deletion():
		return
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null and world.is_underwater(global_position.x, global_position.z):
		return
	burning = true
	_burn_left = BURNS_FOR * randf_range(0.8, 1.2)
	_spread = false
	berries = 0
	_update_berries()
	_fire = Util.small_flame(1.2)
	add_child(_fire)


## Heat from something burning near it. Tinder catches at a touch.
func scorch(joules: float) -> void:
	if joules >= CATCHES:
		ignite()


## Rain on it: out, and bare, and it grows its berries again from nothing.
func extinguish() -> void:
	burning = false
	if _fire != null and is_instance_valid(_fire):
		_fire.queue_free()
	_fire = null


func full_health() -> float:
	return HEALTH


## A rock landing on it, or a beast's weight: flattened.
func damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		queue_free()


func burn_down() -> void:
	extinguish()
	queue_free()


## A few seconds of flame; halfway, the brush and wood beside it; then ash.
func _burn(delta: float) -> void:
	_burn_left -= delta
	if not _spread and _burn_left <= BURNS_FOR * 0.5:
		_spread = true
		_catch_the_neighbours()
	if _burn_left <= 0.0:
		burn_down()


func _catch_the_neighbours() -> void:
	var at := global_position
	for b in get_tree().get_nodes_in_group("forage"):
		var bush := b as ForageBush
		if bush == null or bush == self or bush.burning:
			continue
		var d := bush.global_position.distance_to(at)
		if d < TOUCHING or (d < SPREAD_REACH and randf() < SPREAD_ODDS):
			bush.ignite()
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and not tree.burning \
				and tree.global_position.distance_to(at) < SPREAD_REACH and randf() < SPREAD_ODDS * 0.5:
			tree.ignite()
	for f in get_tree().get_nodes_in_group(Affords.BURNABLE):
		var built := f as Node3D
		if built != null and not built is ForageBush and built.has_method("scorch") \
				and Util.within(built, at, SPREAD_REACH):
			built.call("scorch", CATCHES)


## EVERY BUSH IN REACH, ALIGHT — for the fires that sweep trees by name
## (lightning, lava, a firestorm) rather than warm what is BURNABLE.
static func light_near(tree: SceneTree, pos: Vector3, reach: float) -> void:
	for b in tree.get_nodes_in_group("forage"):
		var bush := b as ForageBush
		if bush != null and bush.global_position.distance_to(pos) < reach:
			bush.ignite()


func _update_berries() -> void:
	for i in _berry_meshes.size():
		_berry_meshes[i].visible = i < berries


func hover_text() -> String:
	if burning:
		return "Forage bush — burning"
	return "Forage bush — %d berries" % berries
