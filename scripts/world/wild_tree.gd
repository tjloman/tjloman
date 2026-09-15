class_name WildTree
extends StaticBody3D
## A living, growing tree. Saplings stand knee-high at size 1; over the days
## they grow to size 10 giants, the whole model scaling with maturity. Mature
## trees replant themselves — seedlings spring up nearby, so a forest logged with
## restraint is a forest forever. Felled trees are gone.
##
## WHAT A TREE IS WORTH is not its size but the RUNNING SUM of the Fibonacci
## sequence up to it — see TIMBER. A tree is worth everything it has been.

const MAX_LUMBER := 10.0

## WHAT SURVIVES A TREE BEING HURLED INTO THE GROUND, as a share of what it was
## worth, and over how many bundles. A wasteful way to harvest, deliberately —
## but a share of its real worth rather than of its size. See `_land`.
const SPLINTER_SHARE := 0.25
const SPLINTER_MOST := 5
## The running sum of Fibonacci, one entry per whole size: 1, 1+1, +2, +3, +5...
## Written out rather than computed because it is ten numbers that will never
## change, and a table can be read at a glance by anyone balancing the economy.
const TIMBER: Array[int] = [1, 2, 4, 7, 12, 20, 33, 54, 88, 143]
## Growth SLOWS as the tree matures: each unit of lumber takes longer than
## the last, so mature timber is genuinely worth more than a thicket of
## saplings. lumber advances by GROWTH_BASE / (1 + lumber * GROWTH_TAPER).
const GROWTH_BASE := 0.06
const GROWTH_TAPER := 0.7
const RAIN_GROWTH := 1.6    # a rain miracle also improves the growth lottery

## WATERING IS SEVERAL TURNS OF THE CRANK, not a nudge to the odds.
##
## Rain used to do nothing but multiply the growth lottery's odds for a few
## seconds, and the lottery is the whole reason a tree takes two hours: one
## success adds 0.024 of the ten lumber a tree is, and the odds go from 10% to
## 16% for the twelve seconds a rain miracle lasts. Measured, that is 0.42% of
## a sapling and 0.10% of a half-grown tree — a miracle you cannot see happen,
## which is the same as one that did not.
##
## So a watering now ADVANCES the tree directly, by a share of the growth it
## has left, spread over a few seconds so you watch it take. Sharing the
## REMAINDER rather than adding lumber means it always shows on a sapling, still
## means something to a big tree, and can never overshoot.
const SPURT_PER_SECOND := 0.25   # turns of the crank per second of blessing
const SPURTS_MOST := 8.0         # what any one blessing can be worth
const SPURT_ADVANCE := 0.06      # share of the REMAINING lumber, per turn
const SPURT_RATE := 1.2          # turns a second, so the growth is watchable
const SAPLING_SCALE := 0.15   # a knee-high seedling
const MATURE_SCALE := 5.0     # a full-grown giant towers ~30m over the land
const GROW_LERP := 5.0        # how fast the visible scale eases toward its target
const REPLANT_PERIOD := 90.0
const REPLANT_CROWDING := 3     # no seeding at all when this many trees stand close

## FORESTS MUST NOT SWALLOW THE MAP. Growth is a LOTTERY, not a certainty: each
## tick a tree only *might* put on size, and a tree hemmed in by neighbours
## competes for light and thickens slower still. Same for dropping seed — a
## crowded stand nearly stops seeding, so woods thin out at their own edges
## instead of marching across the world.
const GROW_CHANCE := 0.1        # per tick: the 1-in-10 roll to actually grow
const CROWD_RADIUS := 11.0      # neighbours this close compete with it
const CROWD_GROW_PENALTY := 0.22  # each neighbour cuts the grow roll by this much
const CROWD_SEED_PENALTY := 0.3   # ...and cuts the seeding roll harder
const NEIGHBOUR_RECHECK := 9.0  # seconds between (costly) neighbour counts

## FIRE — contained by default. A burning tree lasts a few seconds, spreads
## only to close neighbours, and can't leap a gap or reach water — so a
## blaze clears a stand of forest but burns out on its own. Rain douses it.
const BURN_SECONDS := 9.0
const SPREAD_RADIUS := 6.0
const SPREAD_CHANCE := 0.35      # per spread-tick, per near neighbour
const HARM_RADIUS := 3.5

## Sway: when the creature wades through, trees lean out of its way and spring
## back. An underdamped spring gives the little bounce as they right themselves.
const LEAN_SPRING := 60.0
const LEAN_DAMP := 9.0
const LEAN_DECAY := 3.0     # how fast the push fades once the creature has passed
const MAX_LEAN := 1.1       # radians (~63°) — a giant's shove can bend it right over

## The pull on a tree in flight. The same as everything else here falls at,
## and named so that Sling can float it for a moment after a throw.
const TREE_GRAVITY := 20.0

var style := "forest"
var rng_seed := 0
var lumber := 1.0
var burning := false

var _felled := false
var _held := false
var _flying := false
var _fly_velocity := Vector3.ZERO
var _target_scale := Vector3.ONE   # eased growth scale the tree animates toward
var _grow_anim := false            # true while the visible scale is catching up
var _base_height := 3.5
var _replant_time := REPLANT_PERIOD * randf_range(0.5, 1.5)
var _burn_time := 0.0
var _fire_tick := 0.0
var _fire_visual: Node3D = null
var _spin_ang := Vector3.ZERO   # aftertouch spin axis*rate while airborne (rad/s)
var _plant_yaw := 0.0           # the tree's random facing, restored after a throw
var _grow_accum := randf() * 0.4   # de-sync the growth tick across trees
var _rain_time := 0.0              # seconds of lingering rain-blessing
var _spurts := 0.0                 # turns of the growth crank still owed
var _neighbours := 0               # nearby trees, cached (counting them is costly)
var _neighbour_time := 0.0
var _lean := Vector3.ZERO          # current tilt as an axis*angle vector
var _lean_vel := Vector3.ZERO
var _lean_target := Vector3.ZERO   # where a push wants it; decays back to zero


func _ready() -> void:
	add_to_group("trees")
	add_to_group("pickable")  # any tree can be UPROOTED by the hand
	collision_layer = 8  # its own layer: walkers collide + steer, the creature passes through
	collision_mask = 0
	set_meta("hover_name", "Tree")

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var h := trunk_height(style, rng)
	var trunk_color := TreeArt.bark_of(style)
	var leaf_color := TreeArt.leaf_of(style)

	_base_height = h
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = h
	col.shape = shape
	col.position = Vector3(0, h * 0.5, 0)
	add_child(col)

	# A custom tree model (tree_<style> or tree) replaces trunk + canopy; it
	# still scales with growth and tumbles when uprooted.
	var custom := ModelBank.instantiate_any(["tree_" + style, "tree"])
	if custom != null:
		add_child(custom)
	else:
		# Pooled, low-poly, shared-material parts: every tree of a style draws
		# from the same handful of meshes and materials.
		add_child(Util.lite_cylinder(0.25, h, trunk_color, Vector3(0, h * 0.5, 0)))
		if style == "savanna":
			# Acacia: wide flat canopy.
			add_child(Util.lite_cylinder(2.2, 0.5, leaf_color, Vector3(0, h + 0.3, 0)))
		else:
			# Conifer cone (top radius 0).
			add_child(Util.lite_cylinder(1.6, 2.8, leaf_color, Vector3(0, h + 1.2, 0), 0.0))

	# A random facing so a stand doesn't look stamped from one mould. Seeded,
	# so the same tree faces the same way every time the world loads; kept in
	# _plant_yaw so an uprooted tree replants at its own angle, not due north.
	_plant_yaw = rng.randf() * TAU
	rotation.y = _plant_yaw

	scale = _scale_for_lumber()   # start at the right size immediately
	_target_scale = scale


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
	_update_lean(delta)
	_animate_growth(delta)
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
	if _rain_time > 0.0:
		_rain_time -= d
	if lumber < MAX_LUMBER:
		_take_spurt(d)
		_tick_neighbours(d)
		# THE GROWTH LOTTERY: most ticks nothing happens at all. Rain improves
		# the odds; crowding worsens them, so a tree in dense woods creeps.
		var odds := GROW_CHANCE
		if _rain_time > 0.0:
			odds *= RAIN_GROWTH  # a downpour quickens the timber
		odds -= _neighbours * CROWD_GROW_PENALTY * GROW_CHANCE
		var quickened := has_meta("quicken_to")
		if quickened and lumber >= float(get_meta("quicken_to")):
			remove_meta("quicken_to")
			quickened = false
		# A miracle-sown sapling races to its quickened size, ignoring the odds.
		if quickened or randf() < maxf(odds, 0.01):
			var step := GROWTH_BASE / (1.0 + lumber * GROWTH_TAPER)
			if quickened:
				step = 2.5
			lumber = minf(lumber + step * d, MAX_LUMBER)
			var target := _scale_for_lumber()
			if not target.is_equal_approx(_target_scale):
				_target_scale = target
				_grow_anim = true
	else:
		_replant_time -= d
		if _replant_time <= 0.0:
			_replant_time = REPLANT_PERIOD * randf_range(0.8, 1.6)
			_try_replant()


## Count the trees crowding this one, refreshed only every few seconds — a
## sweep of the whole forest per tree per tick would be O(n²) and pointless,
## since woods change slowly.
func _tick_neighbours(d: float) -> void:
	_neighbour_time -= d
	if _neighbour_time > 0.0:
		return
	_neighbour_time = NEIGHBOUR_RECHECK * randf_range(0.8, 1.3)
	var n := 0
	for t in get_tree().get_nodes_in_group("trees"):
		if t == self or not is_instance_valid(t):
			continue
		if (t as Node3D).global_position.distance_to(global_position) < CROWD_RADIUS:
			n += 1
			if n >= 8:
				break   # thoroughly hemmed in; no need for an exact count
	_neighbours = n


## WATERED — by rain, or by a creature that chose this spot to relieve itself.
## Buys turns of the growth crank, and sweetens the ordinary lottery besides.
func rain(duration: float) -> void:
	_rain_time = maxf(_rain_time, duration)
	_spurts = minf(_spurts + duration * SPURT_PER_SECOND, SPURTS_MOST)


## Spend what watering bought, a little at a time — the growth is meant to be
## seen happening rather than to have already happened.
func _take_spurt(d: float) -> void:
	if _spurts <= 0.0:
		return
	var turns := minf(_spurts, SPURT_RATE * d)
	_spurts -= turns
	lumber = minf(lumber + (MAX_LUMBER - lumber) * SPURT_ADVANCE * turns, MAX_LUMBER)
	var target := _scale_for_lumber()
	if not target.is_equal_approx(_target_scale):
		_target_scale = target
		_grow_anim = true


## Shoved aside by something wading past (the creature): lean the crown AWAY
## from `from_pos`, harder the closer it is. Called every frame while near; the
## lean decays and springs upright once the pushing stops.
func sway(from_pos: Vector3, amount: float) -> void:
	if _felled or _held or _flying:
		return
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() < 0.01:
		return
	away = away.normalized()
	# Tilt the top toward `away` = rotate about the perpendicular horizontal axis.
	_lean_target = Vector3(away.z, 0.0, -away.x) * clampf(amount, 0.0, MAX_LEAN)


## Advance the lean spring and write it into the tree's rotation. Costs nothing
## for the overwhelming majority of trees, which are never touched.
func _update_lean(delta: float) -> void:
	_lean_target = _lean_target.move_toward(Vector3.ZERO, LEAN_DECAY * delta)
	if _lean == Vector3.ZERO and _lean_vel == Vector3.ZERO and _lean_target == Vector3.ZERO:
		return
	var accel := (_lean_target - _lean) * LEAN_SPRING - _lean_vel * LEAN_DAMP
	_lean_vel += accel * delta
	_lean += _lean_vel * delta
	if _lean.length() < 0.001 and _lean_vel.length() < 0.005 and _lean_target == Vector3.ZERO:
		_lean = Vector3.ZERO
		_lean_vel = Vector3.ZERO
		rotation = Vector3(0.0, _plant_yaw, 0.0)
		return
	var b := Basis(Vector3.UP, _plant_yaw)
	if _lean.length() > 0.0001:
		b = Basis(_lean.normalized(), _lean.length()) * b
	rotation = b.get_euler()


## The eased growth scale for the current lumber: a knee-high sapling grows into
## a towering ~30m giant. The ramp is eased-in (t²) so young trees stay small
## and only the mature ones loom — the alternative (a straight lerp to a big
## mature scale) would make every sapling a monster the moment it sprouts.
## THE SHAPE A SEED GIVES, in one place, because two things want it now: the
## tree, and the board that stands in for it past Quality.clutter_distance. If
## those two ever disagree the wood changes size as you walk towards it, which
## is the one thing an impostor must never do.
##
## It takes the RNG rather than the seed so `_ready` can go on using the same
## stream afterwards for the plant's facing — the draws here are exactly the
## draws that were inline before, in the same order.
##
## The parameter is `kind` and not `style` because `style` is a member of this
## class, and a parameter of that name shadows it — harmless in a static
## function, which cannot reach the member anyway, and a warning at every load
## for as long as it stands.
static func trunk_height(kind: String, rng: RandomNumberGenerator) -> float:
	var h := rng.randf_range(2.5, 4.5)
	match kind:
		"savanna":
			h = rng.randf_range(3.5, 5.0)
		"wetland":
			h = rng.randf_range(2.0, 3.2)
	return h


## How wide the crown is and how far it stands above the bole, in metres at
## scale one. Read straight off what _ready actually builds: a conifer is a
## 1.6m-radius cone sitting 1.2m up and 2.8m tall; an acacia is a 2.2m plate.
static func crown(kind: String) -> Vector2:
	if kind == "savanna":
		return Vector2(4.4, 0.55)
	return Vector2(3.2, 2.6)


## THE BOARD'S SIZE IN METRES for a tree of this seed carrying this much lumber
## — width by height, pivoted at the foot. The growth curve is `_scale_for_lumber`
## written out, because a board is not a node and has no scale to read.
static func board_size(kind: String, from_seed: int, carried: float) -> Vector2:
	var t := clampf(carried / MAX_LUMBER, 0.0, 1.0)
	var grown := SAPLING_SCALE + (MATURE_SCALE - SAPLING_SCALE) * t * t
	# THE MODEL'S OWN SIZE, WHEN THERE IS A MODEL. `crown` describes the
	# PRIMITIVE — a 1.6m cone on a bole — and the moment a tree_forest.glb is
	# dropped in res://models/ that is no longer what is standing there. The
	# board went on being cut to the primitive's dimensions, so the wood on the
	# horizon was the wrong size for the wood you walk into. Measured once per
	# style and cached; see ModelBank.bounds.
	#
	# A modelled tree has no per-seed height, because there is one model — which
	# is why the seed only matters on the fallback path below.
	var box := ModelBank.bounds_any(["tree_" + kind, "tree"])
	if box.size.y > 0.0:
		# THE TOP ABOVE THE GROUND, not the height of the box. A model whose
		# base sits below its own origin — tree_savanna does, by 0.39m — has
		# that much of itself buried when it is planted, so its box is taller
		# than the tree anybody can see. The board stands ON the ground, so what
		# it needs is how far up the model reaches, which is `end.y`.
		return Vector2(maxf(box.size.x, box.size.z), maxf(box.end.y, 0.1)) * grown
	var rng := RandomNumberGenerator.new()
	rng.seed = from_seed
	var h := trunk_height(kind, rng)
	var top := crown(kind)
	return Vector2(top.x, h + top.y) * grown


## Has the axe been to it? A felled tree is still a child of its chunk for a
## few seconds while it topples, and must not be boarded in that time.
func felled() -> bool:
	return _felled


func _scale_for_lumber() -> Vector3:
	var t := lumber / MAX_LUMBER
	return Vector3.ONE * (SAPLING_SCALE + (MATURE_SCALE - SAPLING_SCALE) * t * t)


## Ease the visible scale toward the growth target a little each frame, so the
## tree swells smoothly instead of jumping a step at every 0.4s growth tick.
## Only a tree that's actively growing pays this; mature and idle trees skip it.
func _animate_growth(delta: float) -> void:
	if not _grow_anim:
		return
	scale = scale.lerp(_target_scale, minf(delta * GROW_LERP, 1.0))
	if scale.distance_to(_target_scale) < 0.0008:
		scale = _target_scale
		_grow_anim = false


## A mature tree drops a seed nearby — if the stand isn't already crowded
## and the ground is dry.
## Only a FULLY GROWN tree drops seed (this branch runs at MAX_LUMBER alone),
## and even then only if there is room and luck: each neighbour makes seeding
## markedly less likely, so a dense wood stops spreading and its edges creep
## rather than march.
func _try_replant() -> void:
	var neighbors := 0
	for t in get_tree().get_nodes_in_group("trees"):
		if t != self and is_instance_valid(t) \
				and (t as Node3D).global_position.distance_to(global_position) < CROWD_RADIUS:
			neighbors += 1
			if neighbors >= REPLANT_CROWDING:
				return   # no room at all
	if randf() > maxf(1.0 - neighbors * CROWD_SEED_PENALTY, 0.05):
		return   # room enough, but the seed did not take this time
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
		# A default end-over-end tumble; aftertouch may replace the axis.
		_spin_ang = Vector3(deg_to_rad(220.0), 0.0, 0.0)


func _fly(delta: float) -> void:
	_fly_velocity.y -= Sling.gravity_for(self, TREE_GRAVITY) * delta   # see Sling
	global_position += _fly_velocity * delta
	if _spin_ang.length() > 0.001:
		global_rotate(_spin_ang.normalized(), _spin_ang.length() * delta)
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	var ground := world.height_at(global_position.x, global_position.z)
	if global_position.y <= ground:
		_flying = false
		_spin_ang = Vector3.ZERO
		_land(_fly_velocity.length())


## Aftertouch hooks: nudge a thrown tree's flight (the curving arc) and set
## its spin axis. Ignored unless it's actually airborne.
func in_flight_push(dv: Vector3) -> void:
	if _flying:
		_fly_velocity += dv


func set_flight_spin(angular: Vector3) -> void:
	_spin_ang = angular


## Touchdown. Storehouse first; then either a rough landing (splinters
## into lumber, most of it lost — a wasteful god) or a fresh planting.
func _land(impact_speed: float) -> void:
	rotation = Vector3(0.0, _plant_yaw, 0.0)  # upright again, at its own facing
	# WHOEVER'S GROUND THIS IS JUST WATCHED A TREE FALL OUT OF THE SKY. A pine
	# coming down in the square is not a miracle and it is a very long way from
	# nothing — and one coming down ON FIRE is the other kind of belief.
	VillageWonder.landed(get_tree(), "tree", global_position, impact_speed, burning)
	# A PINE COMING DOWN ON A HOUSE IS A PINE COMING DOWN ON A HOUSE. A tree
	# does not fly on Godot's physics, so it cannot carry a Blow — but it knows
	# its own impact speed, which is the only thing a Blow wanted. Weighted by
	# what it was worth as timber, so a sapling is a thrown stick and a
	# hundred-year giant is a battering ram.
	Blow.lands(self, global_position, impact_speed,
		2.0 + float(timber()) * 0.12, has_meta("hurled_by_god"))
	for s in get_tree().get_nodes_in_group("stores"):
		var store := s as FoodStore
		if is_instance_valid(store) \
				and store.global_position.distance_to(global_position) < FoodStore.PLATFORM_RADIUS + 1.5:
			# WHAT IT IS WORTH, not how big it is. `lumber` is the tree's SIZE,
			# one to ten; `timber()` is what felling it yields, which is the
			# running Fibonacci sum of everything it has been — 88 for a size
			# nine, not 9. This path banked the size for as long as it has
			# existed, so a giant carried carefully to the storehouse paid a
			# tenth of the same giant chopped by a woodcutter.
			store.add_lumber(timber())
			var town := store.get_parent() as Village
			if town != null and is_instance_valid(town):
				town.wonder.given(town, "lumber", timber(),
					impact_speed, has_meta("hurled_by_creature"))
			queue_free()
			return
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		if world.is_underwater(global_position.x, global_position.z):
			queue_free()  # swallowed by the lake
			return
		global_position.y = world.height_at(global_position.x, global_position.z) - 0.1
	if impact_speed > 14.0:
		# SPLINTERED. A share of what the tree was worth, and the rest is lost
		# — which is the point, and was always the point. But the share has to
		# be of `timber()`: off the raw size a hurled giant burst into three
		# bundles worth three, against the eighty-eight a woodcutter would have
		# had, so the wasteful god was not being taxed, he was being robbed.
		#
		# Carried in `count`, so five physical bundles can be worth twenty-two
		# without putting twenty-two rigid bodies on the grass. FoodStore reads
		# it; so does the creature, now.
		var worth := maxi(int(float(timber()) * SPLINTER_SHARE), 1)
		var bundles := clampi(worth, 1, SPLINTER_MOST)
		var each := float(worth) / float(bundles)
		for i in bundles:
			var bundle := ResourceItem.new()
			bundle.kind = "lumber"
			# Exact split, remainder and all: this bundle's boundary less the
			# one before it, so the pieces always sum back to `worth`.
			bundle.count = int(round(each * float(i + 1))) - int(round(each * float(i)))
			get_parent().add_child(bundle)
			bundle.global_position = global_position \
				+ Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
		queue_free()
		return
	collision_layer = 8  # replanted, roots take hold, growth resumes


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
	# LOCAL height (pre-scale): the node scales this, so the already-scaled
	# current_height() would float the fire up by scale squared.
	var top := _base_height
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
				# Standing in a blaze, they catch fire (villagers/animals).
				if node.has_method("ignite") and randf() < 0.5:
					node.call("ignite")


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
	# A nearby field catches the drifting embers.
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and not farm.burning \
				and farm.global_position.distance_to(global_position) < SPREAD_RADIUS:
			if randf() < SPREAD_CHANCE * 0.5:
				farm.ignite()


## Called by a lumberjack when the chop completes. Timber!
func fell() -> int:
	if _felled:
		return 0
	_felled = true
	collision_layer = 0
	# AND THE BOARD GOES WITH IT. A chunk you logged and walked away from would
	# otherwise still show its wood standing on the horizon — the impostors are
	# drawn from the trees, so the trees have to say when they are gone.
	var ground := get_parent()
	if ground is Chunk:
		(ground as Chunk).retally_boards()
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees:x",
		88.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(2.0)
	tween.tween_callback(queue_free)
	return timber()


## WHAT A TREE IS ACTUALLY WORTH: the running sum of the Fibonacci sequence up
## to its size. A TREE IS WORTH EVERYTHING IT HAS BEEN — the sum of all the
## growth that got it there is literally what you are cutting down.
##
## It used to be worth its size flat: a sapling one, a giant ten. So ten saplings
## paid exactly as well as the tree it took a week to grow, and a village
## stripped every stick within reach the moment it wanted a hut, starting with
## the nearest, which were always the small ones.
##
## Now a sapling is one and a giant is a hundred and forty-three. Cutting the
## little ones stops being worth the walk; a wood becomes a thing a village lets
## stand and comes back to; and a well-tended forest — rained on, blessed, left
## alone — is worth enormously more than a scrubby one, which is the lever a god
## actually has over a logging town.
##
## Fibonacci rather than the square because the curve is steeper where it should
## be. The square doubles between size 7 and 10; this nearly triples, so the last
## stretch of waiting is the part that pays best, which is the whole point of
## waiting at all.
func timber() -> int:
	var size := clampf(lumber, 1.0, MAX_LUMBER)
	var low := int(floorf(size))
	var high := mini(low + 1, TIMBER.size())
	# Interpolated between whole sizes, so a tree half-way to its next size is
	# worth half-way more. Felling is not quantised to birthdays.
	return maxi(int(round(lerpf(
		float(TIMBER[low - 1]), float(TIMBER[high - 1]), size - float(low)))), 1)


func is_felled() -> bool:
	return _felled


func hover_text() -> String:
	if burning:
		return "Tree — ABLAZE"
	if lumber >= MAX_LUMBER:
		return "Tree — %d lumber, fully grown" % int(lumber)
	return "Tree — %d lumber and growing" % int(lumber)
