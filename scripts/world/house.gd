class_name House
extends StaticBody3D
## A dwelling with a lifespan of its own: health and age meters, capacity by
## size, decay in old age, collapse into rubble, and construction/repair by
## builders. Windows glow warm at night — unless nobody lives there.

enum Size { HUT, HOUSE, LONGHOUSE }

## capacity / lumber cost / stone cost / footprint / build effort by size.
## Bigger dwellings cost more AND take longer: `effort` is total
## builder-seconds of work to raise it (a hut is a weekend, a longhouse a
## season).
##
## THESE HOLD WHAT THEY LOOK LIKE THEY HOLD NOW. Two, four and six were the
## numbers of a village of eight people, and they made every roof in a town of
## fifty a rationed thing: housing was the binding constraint on everything the
## settlement did, and the seams showed everywhere — people sleeping in the dirt,
## breeding stopped at the housing cap, half the town's labour going into walls.
## A longhouse is a HALL. Twelve sleep in it, six in a house, three in a hut, at
## the same price and the same labour as before, which is the whole point: the
## town spends less of itself on shelter and more on being a town.
const SPECS := {
	Size.HUT: {"capacity": 3, "lumber": 5, "stone": 3, "width": 2.0, "effort": 45.0},
	Size.HOUSE: {"capacity": 6, "lumber": 12, "stone": 7, "width": 2.8, "effort": 95.0},
	Size.LONGHOUSE: {"capacity": 12, "lumber": 22, "stone": 14, "width": 3.6, "effort": 180.0},
}

const BUILD_RATE := 6.0         # construction progress per builder-second
const DECAY_START_AGE := 30.0   # years before a house starts crumbling
## A monster's kick knocks the whole dwelling askew, then it springs back
## upright (underdamped, for the wobble) — unless the blow was the last it took.
const KNOCK_SPRING := 45.0
const KNOCK_DAMP := 7.0


## WHAT IT TAKES TO PULL THIS DOWN BY FORCE, against a villager's hundred.
## A building is the thing that PROTECTS the villager, so it cannot be as easy
## to break as the villager is — a fireball that kills the family should not
## also flatten the house in the same instant, and a creature in a temper
## should have to work at it.
##
## Fire is charged as a fraction of this rather than as a flat number, so a
## stout building is stout against BLOWS and still burns to the ground in the
## same minute and a half as a hut. See Kindling.tick.
const MOST_HEALTH := 400.0

var size := Size.HUT
var health := MOST_HEALTH
## Whether it is alight, and for how much longer. See Kindling.
var kindling := Kindling.new()
var age := 0.0                  # years
var occupied := false           # kept current by Village._assign_housing
var under_construction := false
var progress := 0.0             # 0..100 while under construction
var village: Village

var _window_mat: StandardMaterial3D
var _night_check := 0.0
var _base_pos := Vector3.INF     # captured on the first kick, restored after
var _base_rot := Vector3.ZERO    # the house's true facing, preserved through a knock
var _knock := Vector3.ZERO       # current tilt (axis*angle, small)
var _knock_vel := Vector3.ZERO
var _shove := Vector3.ZERO        # current positional skid
var _shove_vel := Vector3.ZERO


func _ready() -> void:
	kindling.temper = Kindling.TEMPER_TIMBER   # timber and thatch
	add_to_group("houses")
	add_to_group(Affords.BURNABLE)
	# A real body, so the hand's ray can hover it (census, health, age).
	# Layer 4 = props: villagers walk through, the hand sees it.
	collision_layer = 4
	collision_mask = 0
	var w: float = SPECS[size]["width"]
	var depth := w * (1.6 if size == Size.LONGHOUSE else 1.0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w + 0.4, 3.0, depth + 0.4)
	col.shape = shape
	col.position = Vector3(0, 1.5, 0)
	add_child(col)
	if under_construction:
		# FULL HEALTH IS MOST_HEALTH, not a hundred. These were written when
		# every building in the game had exactly a hundred, and a house that
		# came out of its scaffolding at 100 of 400 was a brand-new home
		# wearing a ruin bar three-quarters empty — and falling to the first
		# thrown rock that should have taken twelve.
		health = MOST_HEALTH
		_build_scaffold_visuals()
	else:
		_build_visuals()


func capacity() -> int:
	return 0 if under_construction else SPECS[size]["capacity"]


func _process(delta: float) -> void:
	_tick_fire(delta)
	if under_construction:
		return
	_settle_knock(delta)
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
## Progress is measured against this dwelling's total effort, so a
## longhouse takes four times a hut's labour to top out at 100%.
func advance_construction(amount: float) -> void:
	if not under_construction:
		return
	progress += amount * (100.0 / SPECS[size]["effort"])
	if progress >= 100.0:
		under_construction = false
		age = 0.0
		health = MOST_HEALTH
		_clear_visuals()
		_build_visuals()
		if village != null:
			village.on_house_completed(self)


func repair(amount: float) -> void:
	health = minf(health + amount, 100.0)


## Sudden harm (fireballs, catastrophes) — collapses outright at zero.

## WHAT IT IS WORTH IN FULL, so a blow can be reckoned as a share of it. A
## METHOD and not the constant itself: Object.get() does not see constants, so
## anything asking `built.get("MOST_HEALTH")` gets null and quietly treats a
## granary as a hut. See Fireball._most_of.
func full_health() -> float:
	return MOST_HEALTH


func damage(amount: float) -> void:
	if under_construction:
		return
	health -= amount
	# AND IT SHOWS. See RuinBar: a thing that can be hurt without looking
	# hurt is indistinguishable from a thing that cannot be hurt at all,
	# which is exactly what "the mill will not burn" sounds like from
	# the other side of the screen.
	RuinBar.over(self, health / MOST_HEALTH, 3.2, kindling.alight)
	if health <= 0.0:
		_collapse()


func needs_repair() -> bool:
	return not under_construction and health < 55.0


## A monstrous creature's kick: heavy damage AND a visible knock — the whole
## dwelling leans and skids from the blow, then springs back upright (or, if
## that was the killing blow, collapses into rubble).
func kick(from_pos: Vector3, force := 1.0) -> void:
	SoundBank.play_at("boom", global_position, 0.0)
	if not under_construction:
		if _base_pos == Vector3.INF:
			_base_pos = position
			_base_rot = rotation
		var away := global_position - from_pos
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		_knock = Vector3(-away.z, 0.0, away.x) * (0.45 * force)
		_shove = away * (0.9 * force)
	damage(55.0 * force)


## Advance the kick's spring back to true. Idles for a house nobody's kicking.
func _settle_knock(delta: float) -> void:
	if _base_pos == Vector3.INF:
		return
	_knock_vel += (-_knock * KNOCK_SPRING - _knock_vel * KNOCK_DAMP) * delta
	_knock += _knock_vel * delta
	_shove_vel += (-_shove * KNOCK_SPRING - _shove_vel * KNOCK_DAMP) * delta
	_shove += _shove_vel * delta
	if _knock.length() < 0.002 and _knock_vel.length() < 0.01 and _shove.length() < 0.01:
		rotation = _base_rot
		position = _base_pos
		_base_pos = Vector3.INF
	else:
		rotation = _base_rot + _knock
		position = _base_pos + _shove


## HEAT ON IT, from a fireball, a bolt, or the building next door. It catches
## only when it has had enough of it for what it is made of — see
## Kindling.warm, and Kindling's TEMPER_ table for why a granary takes longer
## than a hut.
func scorch(joules: float) -> void:
	kindling.warm(self, joules, 2.6)


## SET IT ALIGHT. A house could always be knocked down and never set on fire.
func ignite() -> void:
	if under_construction:
		return
	kindling.light(self, 2.6)


func extinguish() -> void:
	kindling.douse(self)


func burn_down() -> void:
	_collapse()


func _tick_fire(delta: float) -> void:
	# COOL OFF between blows: three fireballs in ten seconds is a fire,
	# three across an afternoon is three scorch marks. See Kindling.
	kindling.cool(delta)
	var harm := kindling.smoulder(self, delta, MOST_HEALTH)
	if harm > 0.0:
		damage(harm)


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
		if child is CollisionShape3D:
			continue  # the hover body persists across rebuilds
		child.queue_free()


func _build_visuals() -> void:
	# A custom house model replaces the whole dwelling. It brings its own
	# windows, so the night-glow (which drives _window_mat) simply idles.
	var custom := ModelBank.instantiate("house")
	if custom != null:
		add_child(custom)
		_window_mat = null
		return

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
