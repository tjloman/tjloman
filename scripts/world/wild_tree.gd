class_name WildTree
extends StaticBody3D
## A living, growing tree. Saplings hold 1 lumber and stand knee-high;
## over the days they grow to 30-lumber giants, the whole model scaling
## with maturity. Mature trees replant themselves — seedlings spring up
## nearby, so a forest logged with restraint is a forest forever.
## Lumberjacks fell them for their CURRENT lumber; felled trees are gone.

const MAX_LUMBER := 10.0
## Growth SLOWS as the tree matures: each unit of lumber takes longer than
## the last, so mature timber is genuinely worth more than a thicket of
## saplings. lumber advances by GROWTH_BASE / (1 + lumber * GROWTH_TAPER).
const GROWTH_BASE := 0.06
const GROWTH_TAPER := 0.7
const SAPLING_SCALE := 0.22
const REPLANT_PERIOD := 50.0
const REPLANT_CROWDING := 4     # no seeding when this many trees stand close

## FIRE — contained by default. A burning tree lasts a few seconds, spreads
## only to close neighbours, and can't leap a gap or reach water — so a
## blaze clears a stand of forest but burns out on its own. Rain douses it.
const BURN_SECONDS := 9.0
const SPREAD_RADIUS := 6.0
const SPREAD_CHANCE := 0.35      # per spread-tick, per near neighbour
const HARM_RADIUS := 3.5

var style := "forest"
var rng_seed := 0
var lumber := 1.0
var burning := false

var _felled := false
var _held := false
var _flying := false
var _fly_velocity := Vector3.ZERO
var _shown_lumber := -1
var _base_height := 3.5
var _replant_time := REPLANT_PERIOD * randf_range(0.5, 1.5)
var _burn_time := 0.0
var _fire_tick := 0.0
var _fire_visual: Node3D = null
var _grow_accum := randf() * 0.4   # de-sync the growth tick across trees


func _ready() -> void:
	add_to_group("trees")
	add_to_group("pickable")  # any tree can be UPROOTED by the hand
	collision_layer = 1
	collision_mask = 0
	set_meta("hover_name", "Tree")

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var h := rng.randf_range(2.5, 4.5)
	var trunk_color := Color(0.42, 0.3, 0.18)
	var leaf_color := Color(0.2, 0.45, 0.2)
	match style:
		"savanna":
			h = rng.randf_range(3.5, 5.0)
			leaf_color = Color(0.4, 0.5, 0.22)
		"wetland":
			h = rng.randf_range(2.0, 3.2)
			trunk_color = Color(0.35, 0.28, 0.2)
			leaf_color = Color(0.25, 0.4, 0.24)
		"grassland":
			leaf_color = Color(0.28, 0.52, 0.24)

	_base_height = h
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = h
	col.shape = shape
	col.position = Vector3(0, h * 0.5, 0)
	add_child(col)

	# Pooled, low-poly, shared-material parts: every tree of a style draws
	# from the same handful of meshes and materials.
	add_child(Util.lite_cylinder(0.25, h, trunk_color, Vector3(0, h * 0.5, 0)))
	if style == "savanna":
		# Acacia: wide flat canopy.
		add_child(Util.lite_cylinder(2.2, 0.5, leaf_color, Vector3(0, h + 0.3, 0)))
	else:
		# Conifer cone (top radius 0).
		add_child(Util.lite_cylinder(1.6, 2.8, leaf_color, Vector3(0, h + 1.2, 0), 0.0))

	_apply_growth_scale()


func _process(delta: float) -> void:
	if _felled:
		return
	# Held or in flight takes precedence — a thrown, blazing tree is a
	# firebrand that ignites wherever it lands. Fire pauses while airborne.
	if _held:
		return
	if _flying:
		_fly(delta)
		return
	if burning:
		_burn(delta)
		return
	# Trees grow slowly; there's no need to touch every one every frame.
	# Batch growth/replant into a ~0.4s tick — with hundreds of trees this
	# is most of the steady-state cost saved on a phone.
	_grow_accum += delta
	if _grow_accum < 0.4:
		return
	var d := _grow_accum
	_grow_accum = 0.0
	if lumber < MAX_LUMBER:
		var step := GROWTH_BASE / (1.0 + lumber * GROWTH_TAPER)
		# A miracle-sown sapling races to its quickened size, then slows.
		if has_meta("quicken_to"):
			if lumber < float(get_meta("quicken_to")):
				step = 2.5
			else:
				remove_meta("quicken_to")
		lumber = minf(lumber + step * d, MAX_LUMBER)
		if int(lumber) != _shown_lumber:
			_apply_growth_scale()
	else:
		_replant_time -= d
		if _replant_time <= 0.0:
			_replant_time = REPLANT_PERIOD * randf_range(0.8, 1.6)
			_try_replant()


## The whole tree scales with its stored lumber: 1 = sapling, 30 = giant.
func _apply_growth_scale() -> void:
	_shown_lumber = int(lumber)
	scale = Vector3.ONE * lerpf(SAPLING_SCALE, 1.0, lumber / MAX_LUMBER)


## A mature tree drops a seed nearby — if the stand isn't already crowded
## and the ground is dry.
func _try_replant() -> void:
	var neighbors := 0
	for t in get_tree().get_nodes_in_group("trees"):
		if t != self and is_instance_valid(t) \
				and (t as Node3D).global_position.distance_to(global_position) < 9.0:
			neighbors += 1
			if neighbors >= REPLANT_CROWDING:
				return
	var angle := randf() * TAU
	var spot := global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(3.5, 7.5)
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null or world.is_underwater(spot.x, spot.z):
		return
	var sapling := WildTree.new()
	sapling.style = style
	sapling.rng_seed = randi()
	sapling.lumber = 1.0
	var parent := get_parent() as Node3D
	spot.y = world.height_at(spot.x, spot.z) - 0.1
	sapling.position = parent.to_local(spot)
	parent.add_child(sapling)


## Uprooting: the divine hand (or a big enough creature) can pull any
## tree out of the ground, roots and all. Set down gently it replants
## where it lands; thrown hard it splinters; dropped onto a storehouse
## it banks its full lumber.

func current_height() -> float:
	return _base_height * scale.y


func pick_up() -> void:
	_held = true
	_flying = false
	collision_layer = 0


func drop(throw_velocity: Vector3, gentle := false) -> void:
	_held = false
	if gentle:
		_land(0.0)
	else:
		_flying = true
		_fly_velocity = throw_velocity


func _fly(delta: float) -> void:
	_fly_velocity.y -= 20.0 * delta
	global_position += _fly_velocity * delta
	rotation_degrees.x = wrapf(rotation_degrees.x + delta * 220.0, -180.0, 180.0)
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	var ground := world.height_at(global_position.x, global_position.z)
	if global_position.y <= ground:
		_flying = false
		_land(_fly_velocity.length())


## Touchdown. Storehouse first; then either a rough landing (splinters
## into lumber, most of it lost — a wasteful god) or a fresh planting.
func _land(impact_speed: float) -> void:
	rotation = Vector3.ZERO
	for s in get_tree().get_nodes_in_group("stores"):
		var store := s as FoodStore
		if is_instance_valid(store) \
				and store.global_position.distance_to(global_position) < FoodStore.PLATFORM_RADIUS + 1.5:
			store.add_lumber(maxi(int(lumber), 1))
			queue_free()
			return
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		if world.is_underwater(global_position.x, global_position.z):
			queue_free()  # swallowed by the lake
			return
		global_position.y = world.height_at(global_position.x, global_position.z) - 0.1
	if impact_speed > 14.0:
		for i in mini(int(lumber / 4.0) + 1, 5):
			var bundle := ResourceItem.new()
			bundle.kind = "lumber"
			get_parent().add_child(bundle)
			bundle.global_position = global_position \
				+ Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
		queue_free()
		return
	collision_layer = 1  # replanted, roots take hold, growth resumes


func is_held() -> bool:
	return _held or _flying


## Fire ------------------------------------------------------------------------

## Set the tree alight. A tree in water, felled, or already ablaze won't
## take. Fire is a tool: it clears forest that would otherwise creep.
func ignite() -> void:
	if burning or _felled or _held or _flying:
		return
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null and world.is_underwater(global_position.x, global_position.z):
		return  # wet wood won't catch
	burning = true
	_burn_time = BURN_SECONDS * randf_range(0.8, 1.2)
	_build_fire_visual()


func extinguish() -> void:
	if not burning:
		return
	burning = false
	_burn_time = 0.0
	if _fire_visual != null and is_instance_valid(_fire_visual):
		_fire_visual.queue_free()
	_fire_visual = null


func _build_fire_visual() -> void:
	_fire_visual = Node3D.new()
	var top := current_height()
	for i in 4:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.6
		cone.height = 1.6
		var flame := Util.mesh_node(cone,
			Color(1.0, randf_range(0.4, 0.7), 0.12), Vector3(0, 0, 0), true)
		flame.position = Vector3(randf_range(-0.4, 0.4), top * 0.5 + i * 0.4, randf_range(-0.4, 0.4))
		_fire_visual.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 3.0
	light.omni_range = SPREAD_RADIUS + 2.0
	light.position = Vector3(0, top * 0.6, 0)
	_fire_visual.add_child(light)
	add_child(_fire_visual)


func _burn(delta: float) -> void:
	_burn_time -= delta
	# Flicker the flames.
	if _fire_visual != null and is_instance_valid(_fire_visual):
		_fire_visual.scale.y = 1.0 + sin(Time.get_ticks_msec() / 60.0) * 0.15

	_fire_tick -= delta
	if _fire_tick <= 0.0:
		_fire_tick = 0.6
		_harm_nearby()
		_spread()
		if randf() < 0.4:
			SoundBank.play_at("boom", global_position, -14.0, 0.4)  # a soft crackle

	if _burn_time <= 0.0:
		# Consumed to ash — no lumber, and a gap the fire can't cross.
		queue_free()


## Fire scares and lightly burns whatever stands too close (it should flee),
## but leaves buildings alone — this stays a forest-clearing tool.
func _harm_nearby() -> void:
	for grp in ["villagers", "animals", "creature"]:
		for n in get_tree().get_nodes_in_group(grp):
			var node := n as Node3D
			if not is_instance_valid(node):
				continue
			if node.global_position.distance_to(global_position) < HARM_RADIUS:
				if node.has_method("scare"):
					node.call("scare", global_position)
				if node.has_method("take_damage"):
					node.call("take_damage", 4.0)


## Spread only to close neighbours, by chance — so a blaze runs through a
## dense stand but gutters out where the trees thin.
func _spread() -> void:
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if tree == self or not is_instance_valid(tree) or tree.burning:
			continue
		if tree.global_position.distance_to(global_position) < SPREAD_RADIUS:
			if randf() < SPREAD_CHANCE:
				tree.ignite()
	for b in get_tree().get_nodes_in_group("forage"):
		var bush := b as Node3D
		if is_instance_valid(bush) \
				and bush.global_position.distance_to(global_position) < SPREAD_RADIUS * 0.7:
			if randf() < SPREAD_CHANCE * 0.5:
				bush.queue_free()  # kindling gone


## Called by a lumberjack when the chop completes. Timber!
func fell() -> int:
	if _felled:
		return 0
	_felled = true
	collision_layer = 0
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees:x",
		88.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(2.0)
	tween.tween_callback(queue_free)
	return maxi(int(lumber), 1)


func is_felled() -> bool:
	return _felled


func hover_text() -> String:
	if burning:
		return "Tree — ABLAZE"
	if lumber >= MAX_LUMBER:
		return "Tree — %d lumber, fully grown" % int(lumber)
	return "Tree — %d lumber and growing" % int(lumber)
