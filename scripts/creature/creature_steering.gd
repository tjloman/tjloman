class_name CreatureSteering
extends RefCounted
## HOW THE CREATURE GETS ANYWHERE.
##
## It used to walk at whatever it wanted in a straight line and lean on local
## repulsion to slide around trunks. That works beautifully in an open field and
## not at all against the shape of the land: a bay, a horseshoe ridge or a
## cliff-backed cove would hold it until a watchdog gave up and it chose
## something else to do. From the outside that reads as a stupid animal, and no
## amount of cleverness in its head fixes it.
##
## Now anything more than a short hop is ROUTED first (see NavField.route), and
## the creature walks the waypoints, still steering locally around whatever it
## meets on the way. Three things keep that honest:
##
##  1. IT REPLANS. The route goes stale on a timer, when the goal moves, and the
##     moment it gets wedged — so a route planned before a forest burned down is
##     not followed through the ashes.
##  2. IT FALLS BACK. If the search finds nothing (too far, or genuinely walled
##     in) the creature simply walks the old way. Routing can never make it
##     worse than it was.
##  3. IT REMEMBERS BAD GROUND. Every place it gets properly stuck is written
##     down, and later routes are costed to avoid there. A creature that has
##     wedged itself in the same gully twice starts going round it — which is
##     the smallest possible version of knowing a landscape, and it is learned
##     rather than baked.

const GRAVITY := 20.0
const ARRIVE := 1.0            # close enough to count as there
const DIRECT := 13.0           # under this, just walk at it; no route needed
const WAYPOINT := 2.6          # how near a waypoint counts as reached
const STALE := 5.0             # seconds before a route is replanned anyway
const GOAL_DRIFT := 6.0        # goal moved this far: the old route is wrong
const REPLAN_COOLDOWN := 0.7   # never search twice in the same breath
const WEDGE_RELAX := 0.35      # seconds of shoving before it stops shoving

## HOW BAD GROUND IS REMEMBERED. Each properly-stuck moment adds to a route
## cell's price; the memory fades, because a gully choked with fallen timber in
## the spring is walkable by autumn.
const STUCK_PRICE := 22.0
const STUCK_CEILING := 90.0
const STUCK_FADE := 0.35       # per second
const STUCK_MEMORY := 48       # cells remembered; the cheapest are forgotten first

## STUCK IN A HOLE.
##
## A fireball gouges a crater with walls a creature genuinely cannot walk up.
## That is not a bug — it is the terrain being real, and a world you can wreck
## is a world you can wreck yourself into. But a player who has not realised
## that the way out is a MIRACLE will simply watch the beast mill about down
## there, and blame the pathfinding.
##
## So the ground itself is asked. If the creature sits below every direction
## around it for long enough that it plainly cannot climb out, the heavens say
## so once and name the working that lifts it. The rune tiers guarantee the
## advice is always actionable: flight is learned no later than fireball, so
## anyone who can dig a pit can already fly out of one (see Spellbook, and
## tools/rune_sheet.py --check).
const PIT_DEPTH := 1.5         # this far below the rim, in every direction
const PIT_PATIENCE := 7.0      # seconds down there before anything is said
const PIT_QUIET := 60.0        # and never again within this many

var wedge_time := 0.0          # seconds spent shoving without advancing
var walk_phase := 0.0          # the waddle

var _path := PackedVector3Array()
var _at := 0
var _goal := Vector3.INF
var _age := 0.0
var _cooldown := 0.0
## Route cell -> how much trouble it has been. NavField costs routes with this.
var _shun := {}
var _pit_time := 0.0           # seconds spent at the bottom of a hole
var _pit_quiet := 0.0          # seconds until we may mention it again


## Walk toward `target`, returning true once it is there. This is the only way
## the creature moves under its own power.
func advance(who: Creature, target: Vector3, speed: float, delta: float) -> bool:
	_age += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_fade_trouble(delta)
	var to_target := target - who.global_position
	to_target.y = 0.0
	if to_target.length() < ARRIVE:
		_apply_gravity(who, delta)
		wedge_time = 0.0
		clear()
		return true

	var step := _next_step(who, target, to_target)
	var dir := step.normalized()
	# Steer around trees and rocks (not the one it's heading for). The avoid
	# radius tracks the creature's ACTUAL size (its collider is 0.6 * scale) so
	# a grown beast swerves wide around groves instead of ramming the trunks.
	# skip_trees: the creature wades straight THROUGH groves (shoving them
	# aside, see Creature._sway_trees), steering only around solid rock.
	dir = NavField.steer(who.global_position, dir, 0.6 * who.scale.x + 0.4, target, true)
	# The creature WADES: water is passable but slow — half speed with its legs
	# in the lake. (The Walk-on-Water miracle lifts that.)
	if not who.walks_on_water:
		var world := who.get_tree().get_first_node_in_group("world_gen") as WorldGen
		if world != null and world.is_underwater(who.global_position.x, who.global_position.z):
			speed *= 0.5

	var before := who.global_position
	who.velocity.x = dir.x * speed
	who.velocity.z = dir.z * speed
	who.velocity.y -= GRAVITY * delta
	who.move_and_slide()
	_note_progress(who, before, speed, delta)
	# Body faces +Z; look_at aims -Z. Look away from travel to face it.
	who.look_at(who.global_position - Vector3(dir.x, 0, dir.z), Vector3.UP)
	walk_phase += delta * 9.0
	# Moving under its own power is exercise — more so while carrying something.
	who.body.exert(0.25 if not who.is_laden() else 0.7, delta)
	return false


## Where to actually head this frame: the next waypoint of a planned route, or
## straight at the goal when the goal is near or no route could be found.
func _next_step(who: Creature, target: Vector3, straight: Vector3) -> Vector3:
	if straight.length() < DIRECT:
		clear()
		return straight
	if _needs_plan(target):
		_plan(who, target)
	while _at < _path.size():
		var here := _path[_at]
		var off := Vector3(here.x - who.global_position.x, 0.0, here.z - who.global_position.z)
		if off.length() > WAYPOINT:
			return off
		_at += 1
	return straight


func _needs_plan(target: Vector3) -> bool:
	if _cooldown > 0.0:
		return false
	if _at >= _path.size():
		return true
	if _age > STALE:
		return true
	return _goal == Vector3.INF or _goal.distance_to(target) > GOAL_DRIFT


func _plan(who: Creature, target: Vector3) -> void:
	_cooldown = REPLAN_COOLDOWN
	_age = 0.0
	_goal = target
	_at = 0
	# It will paddle if it must, and much further once it can walk on water.
	var wade := 12.0 if who.walks_on_water else 1.6 + who.scale.x * 0.2
	_path = NavField.route(who.global_position, target, wade, _shun)


## Wedged? If it is pushing and barely advancing, RELAX the drive so a giant
## collider stops grinding into the trunks (the source of the jank and the
## physics-contact lag) — and write the spot down, so the next route round here
## costs more and it goes another way.
func _note_progress(who: Creature, before: Vector3, speed: float, delta: float) -> void:
	var moved := Vector2(who.global_position.x - before.x,
		who.global_position.z - before.z).length()
	if who.is_on_wall() and moved < speed * delta * 0.3:
		wedge_time += delta
		if wedge_time > WEDGE_RELAX:
			who.velocity.x = 0.0   # stop shoving the trunk (kills the jank and lag)
			who.velocity.z = 0.0
		if wedge_time > 1.0:
			remember_trouble(who.global_position)
			clear()                # whatever route led here is not worth keeping
	else:
		wedge_time = 0.0


## THIS PLACE IS TROUBLE. Priced into every future route it plans.
func remember_trouble(where: Vector3) -> void:
	var cell := Vector2i(
		floori(where.x / NavField.ROUTE_CELL), floori(where.z / NavField.ROUTE_CELL))
	_shun[cell] = minf(float(_shun.get(cell, 0.0)) + STUCK_PRICE, STUCK_CEILING)
	if _shun.size() <= STUCK_MEMORY:
		return
	# Full up: forget wherever has given it the least trouble.
	var mildest: Vector2i = cell
	var least := INF
	for c: Vector2i in _shun:
		if float(_shun[c]) < least:
			least = float(_shun[c])
			mildest = c
	_shun.erase(mildest)


func _fade_trouble(delta: float) -> void:
	for cell: Vector2i in _shun.keys():
		var left := float(_shun[cell]) - STUCK_FADE * delta
		if left <= 0.0:
			_shun.erase(cell)
		else:
			_shun[cell] = left


## Drop whatever route is held; the next call plans afresh.
func clear() -> void:
	_path = PackedVector3Array()
	_at = 0
	_goal = Vector3.INF


func following() -> bool:
	return _at < _path.size()


func waypoints_left() -> int:
	return maxi(_path.size() - _at, 0)


func trouble_spots() -> int:
	return _shun.size()


## The live bad-ground map, keyed by route cell — what routes are costed
## against. (`to_dict` is the same thing flattened for JSON.)
func shunned() -> Dictionary:
	return _shun


func _apply_gravity(who: Creature, delta: float) -> void:
	who.velocity.x = 0.0
	who.velocity.z = 0.0
	who.velocity.y -= GRAVITY * delta
	who.move_and_slide()


## Persistence -----------------------------------------------------------------
##
## Only the hard-won half is worth saving: where it has learned not to go. A
## route in progress is not worth a line of JSON.

func to_dict() -> Dictionary:
	var out := {}
	for cell: Vector2i in _shun:
		out["%d,%d" % [cell.x, cell.y]] = float(_shun[cell])
	return out


func from_dict(data: Dictionary) -> void:
	_shun.clear()
	for key: String in data:
		var pair := key.split(",")
		if pair.size() == 2:
			_shun[Vector2i(int(pair[0]), int(pair[1]))] = float(data[key])


## Is the creature at the bottom of something it cannot climb out of, and has
## it been there long enough to be worth mentioning? Called every tick; the
## ring of ground samples only happens once it has been still for a while, so
## the ordinary cost of this is two floats and a comparison.
func watch_for_pit(who: Creature, delta: float) -> void:
	_pit_quiet = maxf(_pit_quiet - delta, 0.0)
	# Flying, or lifted some other way, is the answer rather than the problem.
	if who.is_flying():
		_pit_time = 0.0
		return
	var world := who.get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	var here := who.global_position
	var floor_y := world.height_at(here.x, here.z)
	# A ring a little wider than the beast is: a big creature in a small dip is
	# not trapped, and should not be told it is.
	var reach := 5.0 + who.scale.x * 1.5
	var walled := true
	for i in 8:
		var a := TAU * i / 8.0
		if world.height_at(here.x + cos(a) * reach, here.z + sin(a) * reach) \
				< floor_y + PIT_DEPTH:
			walled = false
			break
	if not walled:
		_pit_time = 0.0
		return
	_pit_time += delta
	if _pit_time < PIT_PATIENCE or _pit_quiet > 0.0:
		return
	_pit_time = 0.0
	_pit_quiet = PIT_QUIET
	GameState.announce(
		"%s is at the bottom of a pit and cannot climb out. Draw CALM and SKY to lift it."
		% who.called())
