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
## HOW LONG A FELLED TRUNK LIES THERE BEFORE IT IS ONLY LUMBER, in seconds.
##
## A thrown tree used to burst into bundles the instant it stopped moving, which
## meant the best thing in the game — throw a pine, chase it, boot it down the
## hill, throw it again — lasted exactly one throw. It lies where it comes to
## rest now and stays a TREE. Touch it and the clock starts over; walk away and
## in half a minute it is firewood, which is the honest end for a trunk nobody
## came back for.
const LIES_FOR := 30.0
## And how far clear of the ground it lies, so a trunk across a slope does not
## have its crown in the hillside.
const LIES_CLEAR := 0.15
## THE BLOW AT WHICH A TRUNK IS BROKEN RATHER THAN FELLED. Below it nothing is
## wasted; at and above it only SPLINTER_SHARE of what the tree was worth
## survives, and in between it is a straight line. A god who hurls a giant into
## a cliff at forty metres a second is not harvesting it.
const SPLINTERS_ABOVE := 14.0
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

## FIRE — contained by default, and SLOW. It spreads only to close neighbours
## and cannot leap a gap or reach water, so a blaze clears a stand of forest
## and burns out on its own. Rain douses it.
##
## A TREE BURNS FOR WHAT IT IS WORTH, in seconds — see `timber` and the TIMBER
## table, which is the running Fibonacci sum this game already reckons a tree's
## value in. A sapling is gone in a second; a hundred-year giant burns for a
## hundred and forty-three of them. The same curve serves both because it is
## the same fact: a tree is everything it has been, whether you are cutting it
## down or setting fire to it.
##
## It used to be a flat nine seconds for every tree in the world. Long enough
## to clear forest, far too short to be a THING — you could not carry a burning
## tree anywhere, could not javelin one across a valley and watch it arrive,
## could not use one as a torch. And a blazing pine turning end over end is the
## best picture this game has in it.
##
## BUT THE TWO NUMBERS PULL AGAINST EACH OTHER. Every extra second of burn is
## another roll against every neighbour, so five times the burn with the same
## odds is not a longer fire, it is a firestorm that takes the map. The odds
## came down as the burn went up, and what that buys is the interesting
## behaviour: fire CREEPS. It takes about ten seconds to reach the next trunk
## instead of two, so a wood burns THROUGH over a couple of minutes rather than
## going up all at once — and it is still something a player can outwait, and
## still stops at a gap. See tools/forest_fire.py.
## What a tree of AVERAGE size comes to, kept only so tools and callers have a
## single number to reason about the spread against. The real burn is `timber()`
## seconds — see `ignite`.
const BURN_SECONDS := 45.0
const SPREAD_RADIUS := 6.0
const SPREAD_CHANCE := 0.05 # per spread-tick, per near neighbour
const HARM_RADIUS := 3.5
## What a burning tree puts into a wall it touches, per fire beat. About six
## seconds to light timber — see Kindling.TEMPER_TIMBER.
const SCORCHES_A_WALL := 25.0

## HOW A THROWN TRUNK COMES TO REST. Under SETTLE_UNDER it has stopped; above
## it, it kicks and goes over again. BOUNCE_KEEP is how much of the blow comes
## back up and BOUNCE_SLIDE how much of the run survives — a log gives up its
## height long before it gives up its direction, which is why a thrown tree
## ends up a long way from where it first touched.
const SETTLE_UNDER := 5.5
const BOUNCE_KEEP := 0.34
const BOUNCE_SLIDE := 0.72
## How fast it turns coming off a blow, per metre a second of it, and the most
## it will ever turn.
const TUMBLE_PER_SPEED := 0.09
const TUMBLE_MOST := 7.0
## AND WHAT LANDING ON THE CROWN DOES. A trunk that comes down on its top is
## levered over by its own momentum — the end that struck stops and the rest of
## the tree keeps going — so it goes over FASTER than one that landed on the
## stump. Without this a crown strike and a foot strike are the same event and
## the tumble reads as a single repeating bounce.
const CROWN_KICK := 1.35
## HOW LONG A SLICE OF FLIGHT MAY BE, whatever the frame is doing.
##
## A tumbling trunk sweeps its ends fifteen metres about its middle, so on a
## tenth-of-a-second frame an end travels two metres between one ground test and
## the next — and two metres is how far into the hillside it gets before
## anything notices. Simulated at 60 frames it is under a metre at any throwing
## speed; at nine it was 2.8, and nine is exactly where a god is most likely to
## be throwing something. So the arc is cut into slices of its own.
##
## AND THE SLICES ARE CAPPED. A frame that took a whole second would otherwise
## run forty of them for every tree in the air; past this the tree simply falls
## behind real time, which nobody can see, where a stall is the thing they
## already noticed.
const FLIGHT_STEP := 0.025
const FLIGHT_MOST := 0.2

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
## LYING ON THE GROUND AND STILL A TREE. Not `_felled`, which means the axe is
## in it and it is two seconds from being gone — this is a trunk you can pick
## back up, set alight, kick down a hill, or leave.
var _down := false
var _lying_for := 0.0
## How much of it the landing ruined, 0..1. Kept from the impact because
## `_hardest` is cleared the moment it comes to rest.
var _spoiled := 0.0
## The hardest blow it has taken this flight — what `_land` is judged on, and
## not the gentle one it happened to stop on.
var _hardest := 0.0
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
	add_to_group(Affords.PICKABLE)  # any tree can be UPROOTED by the hand
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
		# ON ITS FOOTING, whatever pivot the model was authored with — of
		# whichever of these names the bank actually had. See
		# ModelBank.footing_any.
		custom.position.y += ModelBank.footing_any(["tree_" + style, "tree"])
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
	Ledger.open(&"WildTree")
	if _felled:
		return
	if _held:
		# AND THE FIRE COMES WITH IT INTO YOUR HAND. The burn was skipped while
		# a tree was held, so a blazing pine picked up off the ground froze
		# mid-fire and — because `_spread` lives inside the burn — could be
		# carried through a forest without lighting a single thing. Carrying a
		# firebrand IS the mechanic; this was the line that forbade it.
		if burning:
			_burn(delta)
		return
	if _flying:
		# THE FIRE GOES WITH IT. A blazing tree turning end over end across a
		# valley is the picture this whole mechanic exists for, and the burn
		# used to PAUSE in flight — so it arrived unchanged, having been a
		# still image of a fire for the entire arc.
		if burning:
			_burn(delta)
		_fly(delta)
		return
	# A TRUNK ON THE GROUND DOES NOT SWAY, GROW OR SEED. It burns, and it waits
	# to see whether anybody comes back for it.
	if _down:
		if burning:
			_burn(delta)
			return
		_lying_for += delta
		if _lying_for >= LIES_FOR:
			_break_up()
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
	# A TRUNK ON THE GROUND DOES NOT LEAN — but being walked over IS being
	# played with, so the half-minute starts again. A creature nosing round a
	# log it threw keeps the log.
	if _down:
		touched()
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
	_down = false
	touched()
	collision_layer = 0


func drop(throw_velocity: Vector3, gentle := false) -> void:
	_held = false
	if gentle:
		# SET DOWN ON PURPOSE, SO IT TAKES ROOT. This is the one way left to
		# PLANT a tree, and keeping it is the whole reason `_land` is asked
		# which of the two happened rather than guessing from the speed.
		_land(0.0, true)
	else:
		_flying = true
		_fly_velocity = throw_velocity
		# A default end-over-end tumble; aftertouch may replace the axis.
		_spin_ang = Vector3(deg_to_rad(220.0), 0.0, 0.0)


## THE WHOLE ARC, in slices short enough that a swinging end cannot step over
## the ground between two of them. See FLIGHT_STEP.
func _fly(delta: float) -> void:
	var left := minf(delta, FLIGHT_MOST)
	while left > 0.0 and _flying and not is_queued_for_deletion():
		var slice := minf(left, FLIGHT_STEP)
		_fly_step(slice)
		left -= slice


func _fly_step(delta: float) -> void:
	_fly_velocity.y -= Sling.gravity_for(self, TREE_GRAVITY) * delta   # see Sling
	global_position += _fly_velocity * delta
	# ABOUT ITS MIDDLE, NOT ITS STUMP. `global_rotate` turns a body about its own
	# origin, and a tree's origin is the foot of the trunk — so a thirty-metre
	# spruce swung its crown through a thirty-metre arc while the foot rode the
	# parabola. A thrown thing turns about its middle, which halves how far
	# either end reaches and is most of why this now reads as a tumble rather
	# than as a mast being spun.
	if _spin_ang.length() > 0.001:
		_turn_about(_middle(), _spin_ang.normalized(), _spin_ang.length() * delta)
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	# BOTH ENDS OF THE TRUNK.
	#
	# A tree flew as a POINT — its own origin, the foot — so the only part of it
	# that could ever touch the ground was the stump. For half of every turn the
	# crown was inside the hillside, and no amount of bounce on the foot could
	# help, because the foot was nowhere near what should have struck. It cut
	# through the land like a knife.
	#
	# So both ends are asked, and the deeper one is the one that hit. That is
	# the whole of what makes it cartwheel ALONG a slope instead of through it.
	var tip := _crown()
	var under_foot := world.height_at(global_position.x, global_position.z) \
		- global_position.y
	var under_crown := world.height_at(tip.x, tip.z) - tip.y
	var buried := maxf(under_foot, under_crown)
	if buried < 0.0:
		return
	var speed := _fly_velocity.length()
	# THE HARDEST BLOW IS THE ONE THAT COUNTS. A tree that bounces four times
	# used to be judged on the last and gentlest of them, so anything that
	# tumbled at all came to rest and quietly replanted itself however hard it
	# had been thrown. `_land` wants to know what happened to it, not what it
	# was doing when it stopped.
	_hardest = maxf(_hardest, speed)
	if speed > SETTLE_UNDER:
		_bounce(buried, under_crown > under_foot, speed)
		return
	_flying = false
	_spin_ang = Vector3.ZERO
	# WHERE IT ACTUALLY CAME TO REST. `_land` stands the trunk up again at the
	# origin, and the origin is the foot — so a tree that stopped lying across a
	# slope would spring upright several metres from the trunk everybody just
	# watched stop. It stands where its middle ended up.
	var rest := _middle()
	global_position.x = rest.x
	global_position.z = rest.z
	_land(_hardest)
	_hardest = 0.0


## IT CAME DOWN AND IT IS NOT DONE. A trunk hitting a hillside at speed does
## not stop; it kicks, it slews, and it goes over again — and it kept that up
## until it had spent itself, which is the whole difference between a thrown
## tree and a placed one.
##
## THE SPIN CHANGES, and that is most of what reads as a bounce. A tumble that
## comes off the ground turning exactly as it went in looks like a sprite being
## teleported upward; one that slews onto a new axis looks like a tree hitting
## a hillside. The new axis is the old one bent toward the way it is sliding,
## so a trunk skidding downhill goes over sideways rather than cartwheeling on
## for ever.
func _bounce(buried: float, on_crown: bool, speed: float) -> void:
	# LIFTED BY HOWEVER DEEP THE STRUCK END WAS, so that end is the one standing
	# clear — rather than setting the ORIGIN on the ground, which put the foot on
	# the grass and left the crown as far under it as it had been.
	global_position.y += buried + 0.05
	var slide := Vector3(_fly_velocity.x, 0.0, _fly_velocity.z)
	_fly_velocity = Vector3(slide.x * BOUNCE_SLIDE,
		absf(_fly_velocity.y) * BOUNCE_KEEP, slide.z * BOUNCE_SLIDE)
	# ACROSS THE WAY IT IS GOING, AND FORWARD OVER IT. The axis was
	# `slide.cross(UP)`, which is the same line and the other SENSE: the crown
	# went over backwards, against the direction of travel, which is a thing
	# nothing thrown has ever done. `UP.cross(slide)` tips it the way it is
	# already going, which is what a tumbleweed does.
	var along := slide.normalized() if slide.length() > 0.5 else Vector3.FORWARD
	var axis := Vector3.UP.cross(along).normalized()
	if axis.length() < 0.1:
		axis = Vector3.FORWARD
	var rate := clampf(speed * TUMBLE_PER_SPEED, 0.6, TUMBLE_MOST)
	_spin_ang = axis * (rate * CROWN_KICK if on_crown else rate)
	# AND IT HURTS WHATEVER IT LANDED ON, every time, not only the last time.
	# See Blow: a burning pine cartwheeling through a street is several blows.
	Blow.lands(self, global_position, speed,
		2.0 + float(timber()) * 0.12, has_meta("hurled_by_god"))
	SoundBank.play_at("boom", global_position, -10.0, 0.4, 0.7)


## THE FAR END OF THE TRUNK, and its middle, in world space. The origin is the
## foot and local +Y runs up the trunk, so the whole tree is those two facts and
## `current_height()`.
func _crown() -> Vector3:
	return global_position + _up_the_trunk() * current_height()


func _middle() -> Vector3:
	return global_position + _up_the_trunk() * (current_height() * 0.5)


## WHICH WAY IS UP THE TRUNK — NORMALIZED, and that is not tidiness.
##
## A basis carries the node's SCALE, and a tree's scale is how big it is: the
## `basis.y` of a full-grown spruce is five units long, and `current_height()`
## is `_base_height * scale.y`, which already has that five in it. Multiplying
## the two puts the crown twenty-five times its own length up the sky, so the
## ground test would be run on a point somewhere over the next valley and the
## tumble would pivot about a spot outside the world.
func _up_the_trunk() -> Vector3:
	return global_transform.basis.y.normalized()


## TURN ABOUT A POINT THAT IS NOT THE ORIGIN. The basis turns, and the origin
## swings round the pivot with it — which is the difference between a tree
## cartwheeling and a tree spinning on its own stump. Written out rather than
## using `global_rotate`, which can only ever turn a body about itself.
func _turn_about(pivot: Vector3, axis: Vector3, radians: float) -> void:
	var turn := Basis(axis, radians)
	global_transform = Transform3D(turn * global_transform.basis,
		pivot + turn * (global_position - pivot))


## Aftertouch hooks: nudge a thrown tree's flight (the curving arc) and set
## its spin axis. Ignored unless it's actually airborne.
func in_flight_push(dv: Vector3) -> void:
	if _flying:
		_fly_velocity += dv


func set_flight_spin(angular: Vector3) -> void:
	_spin_ang = angular


## Touchdown. Storehouse first; then either a rough landing (splinters
## into lumber, most of it lost — a wasteful god) or a fresh planting.
func _land(impact_speed: float, planted := false) -> void:
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
	if world != null and world.is_underwater(global_position.x, global_position.z):
		queue_free()  # swallowed by the lake
		return
	if planted:
		rotation = Vector3(0.0, _plant_yaw, 0.0)  # upright again, at its own facing
		if world != null:
			global_position.y = world.drawn_height_at(
				global_position.x, global_position.z) - 0.1
		collision_layer = 8  # replanted, roots take hold, growth resumes
		return
	_lie_down(world, impact_speed)


## IT COMES TO REST LYING DOWN, AND IT IS STILL A TREE.
##
## It used to stand back up at the spot it stopped — roots and all, growth
## resumed — unless it had been going over fourteen metres a second, in which
## case it burst into lumber and vanished. Neither is a felled tree. A trunk you
## threw should lie there long enough to be chased, kicked, set alight, picked
## back up and thrown again, and only become firewood if nobody does any of
## that. See LIES_FOR.
##
## LAID ALONG THE WAY IT WAS POINTING, with both ends clear of the ground. The
## trunk runs up local +Y from the foot, so lying down is a basis with +Y
## horizontal — and the height is taken from the higher of the two ends, or a
## trunk across a slope buries its crown in the hillside.
func _lie_down(world: WorldGen, impact_speed: float) -> void:
	var along := _up_the_trunk()
	along.y = 0.0
	if along.length() < 0.01:
		along = Vector3(cos(_plant_yaw), 0.0, sin(_plant_yaw))
	along = along.normalized()
	var side := Vector3.UP.cross(along).normalized()
	basis = Basis(side, along, side.cross(along)).scaled(_scale_for_lumber())
	if world != null:
		var tip := global_position + along * current_height()
		global_position.y = maxf(
			world.drawn_height_at(global_position.x, global_position.z),
			world.drawn_height_at(tip.x, tip.z)) + LIES_CLEAR
	_down = true
	_lying_for = 0.0
	# HOW MUCH OF IT THE LANDING RUINED, kept now because `_hardest` is cleared
	# the moment it stops. A trunk set down whole is worth all of itself; one
	# driven into a hillside at speed is worth a quarter. See SPLINTERS_ABOVE.
	_spoiled = clampf(impact_speed / SPLINTERS_ABOVE, 0.0, 1.0)
	collision_layer = 8


## WHAT IS LEFT OF A TRUNK NOBODY CAME BACK FOR.
##
## A share of what the tree was worth, and the rest is lost — which is the
## point, and was always the point. But the share has to be of `timber()`: off
## the raw size a hurled giant burst into three bundles worth three, against the
## eighty-eight a woodcutter would have had, so the wasteful god was not being
## taxed, he was being robbed.
##
## Carried in `count`, so five physical bundles can be worth twenty-two without
## putting twenty-two rigid bodies on the grass.
func _break_up() -> void:
	var worth := maxi(int(round(
		float(timber()) * lerpf(1.0, SPLINTER_SHARE, _spoiled))), 1)
	var bundles := clampi(worth, 1, SPLINTER_MOST)
	var each := float(worth) / float(bundles)
	for i in bundles:
		var bundle := ResourceItem.new()
		bundle.kind = "lumber"
		# Exact split, remainder and all: this bundle's boundary less the one
		# before it, so the pieces always sum back to `worth`.
		bundle.count = int(round(each * float(i + 1))) - int(round(each * float(i)))
		get_parent().add_child(bundle)
		bundle.global_position = global_position \
			+ Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
	queue_free()


## LYING ON THE GROUND, still a tree and still worth picking up. Asked by
## routing (you step over a log) and by anything that wants to know whether the
## wood here is standing.
func is_down() -> bool:
	return _down


## SOMEBODY IS STILL PLAYING WITH IT. Starts the half-minute over, so a trunk
## that is being chased down a hill never turns into firewood under the chase.
func touched() -> void:
	_lying_for = 0.0


func is_held() -> bool:
	return _held or _flying


## Fire ------------------------------------------------------------------------

## Set the tree alight. A tree in water, felled, or already ablaze won't take.
## Fire is a tool: it clears forest that would otherwise creep.
##
## A TREE IN FLIGHT CAN BE LIT, and this is the best thing in the game.
## `_flying` was in the refusal below, which meant the one shot everybody
## actually wants — the creature javelins a pine across the valley and you put
## a fireball through it at the top of its arc — was the one shot the game
## specifically forbade. There was no reason for it beyond the guard being
## written as a list of "not now" states without anybody asking what a
## firebrand is.
## A TREE IN YOUR HAND CAN BE LIT TOO, and that is the other half of it. `_held`
## was in the refusal, so the thing the whole mechanic is for — pick up a pine,
## set it alight, walk it into somebody's wood — could not be started. `_felled`
## stays: an axe is in that one and it is two seconds from being gone.
func ignite() -> void:
	if burning or _felled:
		return
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null and world.is_underwater(global_position.x, global_position.z):
		return  # wet wood won't catch
	burning = true
	# HOW LONG A TREE BURNS IS WHAT A TREE IS WORTH, in seconds. See `timber`:
	# the running Fibonacci sum this game already reckons a tree's value in,
	# which turns out to be exactly the curve a burn wants. A sapling is gone
	# in a second, a size five is twelve seconds of light show, and a
	# hundred-year giant burns for a hundred and forty-three — two and a half
	# minutes of a thing you can pick up and carry somewhere.
	#
	# Nothing new had to be invented for this and that is the point: a tree is
	# worth everything it has been, and it burns for everything it has been.
	_burn_time = float(timber()) * randf_range(0.85, 1.15)
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
		_fire_tick = _fire_beat_length()
		_harm_nearby()
		_spread()
		# AND IT HEATS THE STONE IT IS LYING AGAINST. This is the whole furnace:
		# there is no furnace object, no recipe and no build menu — a tree
		# burning against a rock puts seconds into the rock, and a rock with
		# enough seconds in it catches. See RockDeposit.HOLDS_PER_STONE.
		RockDeposit.warm_near(get_tree(), global_position,
			RockDeposit.WARMS_WITHIN, RockDeposit.SOAKS * _fire_beat_length())
		if randf() < 0.4:
			SoundBank.play_at("boom", global_position, -14.0, 0.4)  # a soft crackle

	if _burn_time <= 0.0:
		# Consumed to ash — no lumber, and a gap the fire can't cross.
		queue_free()


## HOW OFTEN A BURNING TREE LOOKS AROUND IT, in seconds. Named rather than
## written twice because the stone it warms is paid in exactly these seconds —
## see RockDeposit.warm — and a beat that drifted from the payment would heat
## rocks at a rate nobody chose.
func _fire_beat_length() -> float:
	return 0.6


## Fire scares and lightly burns whatever stands too close (it should flee) —
## AND HEATS THE BUILDING IT IS LYING AGAINST. It used to leave buildings alone,
## "a forest-clearing tool", which meant a god carrying a blazing pine into a
## town could lean it on every roof in the street and light none of them. A few
## seconds against a timber wall now sets it going; stone takes much longer.
func _harm_nearby() -> void:
	for b in get_tree().get_nodes_in_group(Affords.BURNABLE):
		var built := b as Node3D
		if is_instance_valid(built) and built != self and built.has_method("scorch") \
				and Util.within(built, global_position, HARM_RADIUS):
			built.call("scorch", SCORCHES_A_WALL)
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
