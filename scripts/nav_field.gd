extends Node
## Autoload `NavField`: a lightweight, periodically-rebuilt obstacle field
## for local steering around trees and rocks.
##
## A baked NavigationServer mesh is the wrong tool here — an endless,
## streaming world of trees that grow, replant, and burn away would need
## constant, expensive re-baking. This serves the same end far more
## cheaply: every REBUILD_PERIOD it snapshots the solid obstacles into a
## spatial grid, and movers ask `steer()` which way to actually go so they
## flow around the grove instead of shoving into a trunk.
##
## Only TREES and ROCKS are tracked — they're the only things on the
## collision layer that blocks walkers (buildings are pass-through), so
## avoiding them is all that's needed, and it never gets in the way of a
## villager reaching a house, store, or field.

const CELL := 8.0
const REBUILD_PERIOD := 1.2
const AVOID_RANGE := 2.2

## ROUTING ---------------------------------------------------------------------
##
## Local steering alone is a bug algorithm: it flows around a trunk beautifully
## and walks straight into a bay, a cliff or a horseshoe ridge and stays there
## until a watchdog gives up. What was missing was an actual ROUTE — a look at
## the shape of the land between here and there before setting off.
##
## This is a bounded A* over a coarse grid whose cost comes from the terrain
## itself: how deep the water is, how steep the climb, how thick the trees. The
## terrain half of that cost is CACHED FOREVER, because the land is generated
## from a seed and a hillside is the same hillside all game; only the obstacle
## half is refreshed with the field. So the hundredth route across a valley is
## nearly free, and the search is capped so no single query can ever cost a
## frame — when the cap is hit the caller simply falls back to local steering,
## which is what it had before.
const ROUTE_CELL := 6.0
## HOW FAR A THING WILL STEP DOWN without treating it as a cliff. Waist-high on
## a villager: enough that ordinary rolling country is walkable and a sheer face
## into the water is not. A beast or a creature passes its own.
const SHEER := 1.5
const ROUTE_BUDGET := 380       # cells expanded before a search gives up
## AND HOW MANY SEARCHES ONE FRAME WILL PAY FOR.
##
## Each search was capped; the number of them was not. So fifty villagers all
## re-deciding on the same frame — which is what happens when an alarm goes up,
## or a tally lands, or (until Scheduler) simply because every one of them
## counted its skipped frames from zero — asked for fifty routes at once, up to
## nineteen thousand cell expansions in a single frame, and then nothing at all
## for seconds. That is the shape that spikes a frame time, and a spiked frame
## time is what drops the graphics tier.
##
## Six a frame is three hundred and sixty a second, which is far more routing
## than a world of this size ever really wants, and it is SPREAD. A refused
## search is not a failure and is not recorded as one: the caller steers
## locally this frame, exactly as it does when a route genuinely cannot be
## found, and asks again on the next one.
const ROUTES_PER_FRAME := 6
const ROUTE_REACH := 400.0      # no route is planned further than this
## WHEN A MOVER IS ALREADY IN TROUBLE, and how it finds its way out. Deliberately
## shallower than Villager.DROWN_DEPTH (1.1) so it turns for shore while the
## water is still only unpleasant, and a wide sweep because the way out of a
## lake can be behind you.
## HOW FAR A BODY MAY WALK ON ONE ANSWER, as a share of the probe.
##
## THIS IS THE MOST EXPENSIVE QUESTION IN THE GAME AND IT WAS ASKED THE MOST
## OFTEN. A clear step is three terrain reads; a shore sweep is fourteen of
## them; a sweep that fails ends in `_least_bad`, which is sixteen more at four
## reads apiece. Every read is a walk of the scars plus five noise samples, and
## every body near water paid the whole bill on every physics tick — a sheep
## standing at a lake edge was spending several hundred noise samples a frame to
## be told the same thing thirty times a second.
##
## The probe reaches `probe` metres ahead, so its answer stays true until the
## body has used up a good part of that. Half leaves the same margin the probe
## was given to begin with. Between probes the body keeps the TURN it was given
## rather than the heading, so it goes on following the same shoreline while its
## goal drifts — and the memory is thrown away the moment it wants to go
## somewhere meaningfully different, because a remembered turn is only an answer
## to the question it was asked.
const REPROBE := 0.5
const REMEMBERS_WHILE := 0.93   # cos(~21 degrees) of the heading it was asked about
const OUT_OF_DEPTH := 0.6
const DRY_SWEEP := 16
const DRY_PROBE := 5.0
const WADE_COST := 4.0          # per metre of depth: passable, and unpleasant
const CLIMB_COST := 2.2         # per metre of rise between neighbouring cells
const THICKET_COST := 0.7       # per obstacle standing in a cell
const STEEP := 3.5              # a rise this big between cells is a wall

const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

## WHAT THE ROUTE JUST RETURNED ACTUALLY COST — the A* figure, not the length of
## the line. Only meaningful immediately after a `route` call, and INF when that
## call came back empty for any reason. PortalPath compares routes with it, and
## comparing them by how long their polylines LOOK would throw away the whole
## point of a cost that knows about hills, water and thickets.
var last_cost := INF
## EVERY WAY THROUGH THE WORLD THAT IS NOT WALKING. A nest has one for as long
## as it stands; the miracle opens one for five minutes. Kept here rather than
## found by walking the scene tree, because routing asks for them several times
## a frame and a group query per ask is a search of its own.
##
## Each is {"id", "mouth", "exit", "until"} — `until` being GameState.clock, or
## INF for one that does not expire. Nothing here moves anybody: a portal MOVES
## whatever steps on it, and this list only says where stepping on one lands.
var portals: Array = []
## THE INSIDE OF THE NETWORK, worked out once and looked up thereafter. See
## PortalMap: the legs between nests do not change, and re-pricing twenty of
## them on every decision would spend a frame's whole routing allowance on one
## creature making up its mind.
var portal_map := PortalMap.new()


var _next_portal := 1
var _grid := {}          # Vector2i cell -> Array of {p: Vector2, r: float}
var _timer := 0.0
## Vector2i route cell -> {"h": float, "wet": float}. There is no "slope" in it
## and never was: steepness is the DIFFERENCE between two cells (see
## `_step_cost`), not a property of one, and the comment claiming otherwise sent
## me looking for a cost term that does not exist.
var _terrain := {}
var _world: WorldGen = null
var _routes_asked := 0
var _routes_failed := 0
var _routes_deferred := 0
var _spent_this_frame := 0


func _process(delta: float) -> void:
	Ledger.open(&"NavField")
	_spent_this_frame = 0
	_timer -= delta
	if _timer <= 0.0:
		_timer = REBUILD_PERIOD
		_rebuild()


func _rebuild() -> void:
	_grid.clear()
	var st := get_tree()
	if st == null:
		return
	for t in st.get_nodes_in_group("trees"):
		var tree := t as WildTree
		# A LOG IS NOT AN OBSTACLE. You step over a trunk lying on the ground,
		# and routing round one as though it were still standing put a phantom
		# tree in every path a thrown pine had crossed.
		if not is_instance_valid(tree) or tree.is_felled() or tree.is_held() \
				or tree.is_down():
			continue
		_add(tree.global_position, 0.45 * tree.scale.x + 0.35, true)
	for r in st.get_nodes_in_group("rock_deposits"):
		var rock := r as RockDeposit
		if not is_instance_valid(rock) or rock.is_loose():
			continue
		# ITS OWN SIZE, not a flat metre and a half. The ladder runs from a
		# pebble to a thing the size of a hut, and routing round the pebble as
		# though it were the hut is how a path takes the long way for nothing.
		_add(rock.global_position, rock.girth() + 0.3, false)


func _add(pos: Vector3, radius: float, is_tree: bool) -> void:
	var cell := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append({"p": Vector2(pos.x, pos.z), "r": radius, "tree": is_tree})


## Given a spot, a desired (normalized, xz) direction, and the mover's
## radius, return an adjusted direction that steers around nearby trees and
## rocks. `ignore` is a world point whose obstacle is the mover's actual
## goal (the tree it's walking to chop) — so it isn't repelled from it.
func steer(pos: Vector3, desired: Vector3, self_radius: float,
		ignore := Vector3.INF, skip_trees := false) -> Vector3:
	var here := Vector2(pos.x, pos.z)
	var des2 := Vector2(desired.x, desired.z)
	if des2 == Vector2.ZERO:
		return desired
	var ignore2 := Vector2(ignore.x, ignore.z)
	var has_ignore := ignore != Vector3.INF
	var push := Vector2.ZERO
	var center := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cell := center + Vector2i(dx, dz)
			if not _grid.has(cell):
				continue
			for o: Dictionary in _grid[cell]:
				if skip_trees and o.get("tree", false):
					continue  # this mover shoves through trees, not around them
				var op: Vector2 = o["p"]
				if has_ignore and op.distance_to(ignore2) < 2.0:
					continue  # this is the goal; don't flee it
				var off := here - op
				var d := off.length()
				var reach: float = o["r"] + self_radius + AVOID_RANGE
				if d >= reach or d < 0.001:
					continue
				# Ignore obstacles behind the direction of travel.
				if des2.dot((op - here).normalized()) < -0.3:
					continue
				push += off.normalized() * ((reach - d) / reach)
	if push == Vector2.ZERO:
		return desired
	var steered := (des2 + push * 1.4).normalized()
	return Vector3(steered.x, 0, steered.y)


## Route a non-swimmer AROUND water, following the shore CONSISTENTLY. If the
## desired heading steps onto water within `probe` metres, sweep outward for the
## nearest dry heading — but bias the sweep toward the side this mover committed
## to last frame (stored as its "shore_side" metadata), so it keeps circling a
## lake the SAME way instead of flip-flopping left/right at a concave shore and
## stalling at the water's edge. The commitment is dropped the moment the way
## ahead opens up (a bug-algorithm "leave point"). Returns Vector3.ZERO only when
## boxed in by water on every side — the caller then holds still (a watchdog
## re-decides).
##
## This is what lets villagers and beasts walk right around a lakeshore to reach
## the far side, rather than stopping dead at the edge and starving.
func water_route(mover: Node, pos: Vector3, desired: Vector3, world: WorldGen,
		probe := 1.7, drop := SHEER) -> Vector3:
	if world == null or desired == Vector3.ZERO:
		return desired
	# THE ANSWER IT WAS GIVEN A MOMENT AGO, if it is still an answer to this
	# question: same ground, near enough, and the same way it wanted to go. See
	# REPROBE — this is what takes the shoreline off the per-frame bill.
	var asked: Vector3 = mover.get_meta("route_at", Vector3.INF) if mover != null \
		else Vector3.INF
	if asked.is_finite() and pos.distance_to(asked) < probe * REPROBE:
		var wanted: Vector3 = mover.get_meta("route_want", Vector3.ZERO)
		if wanted.dot(desired) >= REMEMBERS_WHILE:
			var turn := float(mover.get_meta("route_turn", 0.0))
			return desired if turn == 0.0 else desired.rotated(Vector3.UP, turn)
	# THE CLEAR CASE FIRST, AND IT COSTS NOTHING ELSE.
	#
	# The drowning check used to sit above this line, which meant every mover in
	# the world paid a `water_level_at` and a `height_at` every frame to be told
	# it was standing on dry grass. `height_at` is five noise samples plus a walk
	# of every scar in range, and there are a few hundred movers — it pegged a
	# desktop on its own.
	#
	# It does not need asking there. If the ground a stride ahead is good then
	# this body is not in trouble, and if it IS somehow standing in water while
	# the way ahead is dry, then walking ahead is already walking out. So the
	# question only gets asked once something is actually wrong.
	# THE GROUND UNDERFOOT, ONCE. It was read twice inside every `_bad_step` and
	# there are up to fourteen of those in a sweep — twenty-eight reads of the
	# one point the body is standing on, which it cannot have moved off between
	# them.
	var here := world.height_at(pos.x, pos.z)
	if not _bad_step(world, pos, desired, probe, drop, here):
		if mover != null:
			mover.set_meta("shore_side", 0)  # open water ahead cleared — drop the commit
			_remember(mover, pos, desired, 0.0)
		return desired
	# WET FEET FIRST. See `_least_bad` — if it is already standing in water deep
	# enough to kill it, there is no safe heading and the question is not which
	# way is safe but which way is OUT.
	if _depth_at(world, pos.x, pos.z) > OUT_OF_DEPTH:
		return _out_of_here(mover, pos, desired, _least_bad(world, pos, desired, here))
	var side := int(mover.get_meta("shore_side", 0)) if mover != null else 0
	# Try ever-wider turns; the side committed to last frame is tried first
	# (small to large), so the shoreline is followed in one consistent sense.
	for deg: float in _shore_sweep(side):
		var swing := deg_to_rad(deg)
		var d := desired.rotated(Vector3.UP, swing)
		if not _bad_step(world, pos, d, probe, drop, here):
			if mover != null:
				mover.set_meta("shore_side", 1 if deg > 0.0 else -1)
				_remember(mover, pos, desired, swing)
			return d
	# NOTHING WAS CLEAN — SO TAKE THE LEAST BAD ONE. This returned ZERO, and
	# every caller reads ZERO as "hold still".
	#
	# That is the one answer that is always wrong. Fourteen headings all failing
	# is not rare on a real shoreline: `_bad_step` refuses a step that is wet OR
	# that falls more than SHEER, and a cove, a spit or a steep bank fails the
	# lot. The villager stopped. The stuck watchdog re-decided it, `_decide`
	# picked the same granary, the steer returned ZERO again, and it stood on
	# the beach until it starved — which is what a row of motionless people
	# strung along one shore actually is. They were not drowning. They were
	# queued at a heading that did not exist.
	#
	# Wading is survivable and a scramble down a bank is survivable. Standing
	# still with an empty belly is not.
	return _out_of_here(mover, pos, desired, _least_bad(world, pos, desired, here))


## IS THE GROUND THAT WAY WORTH STEPPING ONTO?
##
## THIS ASKED ONLY WHETHER IT WAS WET, and that is not the question. Where the
## land meets water at a steep face the ground a stride ahead is still dry —
## it is the top of the cliff — so every villager that walked toward the sea
## walked straight off it, fell in at the bottom, and drowned. They were not
## failing to avoid the water; they were never looking down.
##
## So a step is bad if it is wet OR if it falls away. A drop is not fatal in
## itself and this is not a fear of heights: it is only ever consulted by
## something that is choosing a HEADING, and there is always another heading.
## `here` is the ground at `pos`, which the caller has already read: it is the
## same point for every heading in a sweep and cost a terrain read apiece.
func _bad_step(world: WorldGen, pos: Vector3, dir: Vector3, probe: float,
		drop: float, here: float) -> bool:
	var x := pos.x + dir.x * probe
	var z := pos.z + dir.z * probe
	if world.is_underwater(x, z):
		return true
	var there := world.height_at(x, z)
	# And what is beyond it, so a shelf one stride wide does not read as ground.
	if here - there > drop * 0.5 \
			and world.is_underwater(pos.x + dir.x * probe * 2.0,
				pos.z + dir.z * probe * 2.0):
		return true
	return here - there > drop


## KEEP THE ANSWER. `turn` is the correction applied to what the body WANTED,
## which is the part worth keeping: the heading goes stale as the goal moves,
## and the turn does not.
func _remember(mover: Node, pos: Vector3, wanted: Vector3, turn: float) -> void:
	mover.set_meta("route_at", pos)
	mover.set_meta("route_want", wanted)
	mover.set_meta("route_turn", turn)


## The same, for a heading that came out of `_least_bad` rather than the sweep —
## the turn is whatever angle it ended up being.
func _out_of_here(mover: Node, pos: Vector3, wanted: Vector3,
		out: Vector3) -> Vector3:
	if mover != null and out != Vector3.ZERO:
		_remember(mover, pos, wanted, wanted.signed_angle_to(out, Vector3.UP))
	return out


## HOW DEEP THE WATER IS OVER THE GROUND HERE — the sea, or a pond standing in a
## flooded crater, or nothing at all.
func _depth_at(world: WorldGen, x: float, z: float) -> float:
	var surface := world.water_level_at(x, z)
	if surface == -INF:
		return 0.0
	return maxf(surface - world.height_at(x, z), 0.0)


## THE LEAST BAD HEADING THERE IS — the way out of the water, and the way out of
## a corner the sweep could not solve.
##
## THE SWEEP IN `water_route` HAS NO ANSWER FOR A BODY THAT IS ALREADY IN. Every
## heading out of the middle of a lake is a bad step, so it found none, returned
## ZERO, and the caller — Villager._move_toward, Animal._move_toward — read that
## as "hold still". Standing still in deep water is drowning. So a villager that
## got in at all could not get out again: dropped there by the hand, shoved off
## a bank in a crowd, or walked in down a shelf gentle enough that the probe
## ahead still read as dry. And every one that followed did it in the same
## place, because they were all walking the same way for the same reason. A line
## of bodies along one shore is not a routing mistake repeated; it is one
## routing mistake with no way back out of it.
##
## THE WATER IS LEVEL, SO SHALLOWEST IS UPHILL IS SHOREWARD. That holds in the
## middle of a lake as well as at its edge, which is what makes this work
## without a search: minimising depth over the sweep is walking out, and it
## never returns ZERO — there is always a best heading, even when every one of
## them is still wet.
func _least_bad(world: WorldGen, pos: Vector3, desired: Vector3,
		here: float) -> Vector3:
	var want := desired.normalized()
	var best := Vector3.ZERO
	var best_score := -INF
	for i in DRY_SWEEP:
		var a := TAU * float(i) / float(DRY_SWEEP)
		var d := Vector3(cos(a), 0.0, sin(a))
		var x := pos.x + d.x * DRY_PROBE
		var z := pos.z + d.z * DRY_PROBE
		var deep := _depth_at(world, x, z)
		# Shallower wins, then flatter, and among equals it keeps going the way
		# it wanted — so wading a ford does not turn into pacing on the spot.
		var fall := maxf(here - world.height_at(x, z), 0.0)
		var score := -deep - fall * 0.25 + d.dot(want) * 0.05
		if score > best_score:
			best_score = score
			best = d
	return best


## The order of turn angles to try when hugging a shore, committed side first
## (small turns before large), then the other side as a fallback.
func _shore_sweep(side: int) -> Array:
	var mags := [25.0, 45.0, 65.0, 90.0, 115.0, 140.0, 165.0]
	var order: Array = []
	if side > 0:
		for m: float in mags:
			order.append(m)
		for m: float in mags:
			order.append(-m)
	elif side < 0:
		for m: float in mags:
			order.append(-m)
		for m: float in mags:
			order.append(m)
	else:
		for m: float in mags:
			order.append(m)
			order.append(-m)
	return order


## Stateless shore-follow (no committed side). Kept for any caller that has no
## mover node to track; movers should prefer water_route for the anti-stall bias.
func water_steer(pos: Vector3, desired: Vector3, world: WorldGen, probe := 1.7) -> Vector3:
	return water_route(null, pos, desired, world, probe)


## ROUTING ---------------------------------------------------------------------

## PLAN A WAY THERE. Returns waypoints from `from` to `to`, or an empty array if
## there is no route worth having (too far, no world yet, or the search ran out
## of budget) — in which case the caller should just steer locally as before.
##
## `wade` is how many metres of water the mover will put up with; 0 keeps it dry.
## `shun` is the mover's OWN memory of bad ground: a dictionary of route cells it
## has got itself stuck in before, which are then costly to route through. That
## is what lets a creature actually learn a landscape rather than walking into
## the same gully every afternoon.
func route(from: Vector3, to: Vector3, wade := 2.0, shun := {}) -> PackedVector3Array:
	_routes_asked += 1
	# THIS FRAME HAS DONE ENOUGH SEARCHING. Not a failure — the caller falls
	# back to steering straight at the thing, which is what it does for an
	# unroutable target anyway, and it will ask again next frame.
	if _spent_this_frame >= ROUTES_PER_FRAME:
		last_cost = INF
		_routes_deferred += 1
		return PackedVector3Array()
	_spent_this_frame += 1
	var world := _world_gen()
	var span := Vector2(to.x - from.x, to.z - from.z).length()
	if world == null or span > ROUTE_REACH:
		last_cost = INF
		_routes_failed += 1
		return PackedVector3Array()
	var start := _route_cell(from)
	var goal := _route_cell(to)
	if start == goal:
		last_cost = 0.0
		return PackedVector3Array()

	var came := {}                          # cell -> cell it was reached from
	var best := {start: 0.0}                # cell -> cheapest cost known to it
	# The frontier, kept in cost order by insertion. Re-sorting the whole thing
	# on every pop is what turns a cheap search into a frame hitch.
	var open: Array = [[_octile(start, goal), start]]
	var found := false
	var expanded := 0
	while not open.is_empty() and expanded < ROUTE_BUDGET:
		var here: Vector2i = open.pop_front()[1]
		if here == goal:
			found = true
			break
		expanded += 1
		var here_cost: float = best[here]
		for step: Vector2i in _NEIGHBOURS:
			var there: Vector2i = here + step
			var stride := ROUTE_CELL * (1.4142 if step.x != 0 and step.y != 0 else 1.0)
			var toll := _step_cost(here, there, wade)
			if toll < 0.0:
				continue                    # impassable: a cliff, or water too deep
			toll += float(shun.get(there, 0.0))
			var cost := here_cost + stride + toll
			if best.has(there) and cost >= float(best[there]):
				continue
			best[there] = cost
			came[there] = here
			_enqueue(open, cost + _octile(there, goal), there)
	if not found:
		last_cost = INF
		_routes_failed += 1
		return PackedVector3Array()
	last_cost = float(best[goal])
	return _unwind(came, start, goal, to)


## A WAY THROUGH OPENS. `seconds` of 0 or less means for as long as it stands.
## Returns the handle it is shut with.
func open_portal(mouth: Vector3, exit: Vector3, seconds := 0.0) -> int:
	var id := _next_portal
	_next_portal += 1
	portals.append({
		"id": id, "mouth": mouth, "exit": exit,
		"until": INF if seconds <= 0.0 else GameState.clock + seconds,
	})
	return id


## And shuts. Harmless if it has already gone.
func shut_portal(id: int) -> void:
	for i in portals.size():
		if int(portals[i]["id"]) == id:
			portals.remove_at(i)
			portal_map.forget(id)
			return


## THE ONES THAT ARE STILL THERE, and the sweeping-up of the ones that are not.
## A route planned through a hole that closed four minutes ago is the whole
## reason this is asked for rather than read.
func portals_open() -> Array:
	var live := []
	var gone := false
	for gate: Dictionary in portals:
		if GameState.clock <= float(gate["until"]):
			live.append(gate)
		else:
			gone = true
	if gone:
		for gate: Dictionary in portals:
			if GameState.clock > float(gate["until"]):
				portal_map.forget(int(gate["id"]))
		portals = live.duplicate()
	return live


## Slot a cell into the frontier so the cheapest is always at the front.
func _enqueue(open: Array, priority: float, cell: Vector2i) -> void:
	var lo := 0
	var hi := open.size()
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if float(open[mid][0]) < priority:
			lo = mid + 1
		else:
			hi = mid
	open.insert(lo, [priority, cell])


## How costly it is to step between two neighbouring cells, or -1 for a step
## nothing can make. Terrain is cached; thickets are read live from the field.
func _step_cost(here: Vector2i, there: Vector2i, wade: float) -> float:
	var a := _terrain_of(here)
	var b := _terrain_of(there)
	var depth: float = float(b["wet"])
	if depth > wade:
		return -1.0
	var rise: float = absf(float(b["h"]) - float(a["h"]))
	if rise > STEEP:
		return -1.0
	return depth * WADE_COST + rise * CLIMB_COST + _thicket(there) * THICKET_COST


## What the land is like in a cell. Generated terrain never changes, so this is
## remembered for the whole session — which is what makes repeated routing over
## familiar ground almost free.
func _terrain_of(cell: Vector2i) -> Dictionary:
	if _terrain.has(cell):
		return _terrain[cell]
	# A wandering giant can walk a very long way. Remembering the land costs
	# about a hundred bytes a cell, so this ceiling is a few megabytes — plenty
	# for a whole afternoon's exploring, and it forgets the lot rather than
	# growing without bound on a marathon session.
	if _terrain.size() > 60000:
		_terrain.clear()
	var world := _world_gen()
	var x := (float(cell.x) + 0.5) * ROUTE_CELL
	var z := (float(cell.y) + 0.5) * ROUTE_CELL
	var h := world.height_at(x, z) if world != null else 0.0
	# How deep the water is here, if there is any: the sea, or a pond — but not
	# a dry crater floor below sea level, which routing used to swim around.
	var surface := world.water_level_at(x, z) if world != null else -INF
	var known := {"h": h, "wet": maxf(surface - h, 0.0) if surface > -INF else 0.0}
	_terrain[cell] = known
	return known


## How much standing timber and rock is in a cell right now, from the same
## snapshot the local steering uses.
func _thicket(cell: Vector2i) -> float:
	var centre := Vector2((float(cell.x) + 0.5) * ROUTE_CELL, (float(cell.y) + 0.5) * ROUTE_CELL)
	var obstacle_cell := Vector2i(floori(centre.x / CELL), floori(centre.y / CELL))
	if not _grid.has(obstacle_cell):
		return 0.0
	var count := 0.0
	for o: Dictionary in _grid[obstacle_cell]:
		if (o["p"] as Vector2).distance_to(centre) < ROUTE_CELL * 0.75:
			count += 1.0
	return count


func _route_cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / ROUTE_CELL), floori(pos.z / ROUTE_CELL))


func _octile(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(float(a.x - b.x))
	var dy := absf(float(a.y - b.y))
	return (maxf(dx, dy) + 0.4142 * minf(dx, dy)) * ROUTE_CELL


## Walk the search back to the start, then hand it out forwards — dropping the
## middle of any straight run, so a mover following it goes in long strides
## instead of clicking through every cell of an open field.
func _unwind(came: Dictionary, start: Vector2i, goal: Vector2i,
		exact: Vector3) -> PackedVector3Array:
	var chain: Array[Vector2i] = []
	var at := goal
	while at != start:
		chain.push_front(at)
		if not came.has(at):
			return PackedVector3Array()
		at = came[at]
	var out := PackedVector3Array()
	var last_dir := Vector2i.ZERO
	for i in chain.size():
		var cell: Vector2i = chain[i]
		var dir: Vector2i = cell - (chain[i - 1] if i > 0 else start)
		if dir != last_dir or i == chain.size() - 1:
			out.append(Vector3(
				(float(cell.x) + 0.5) * ROUTE_CELL, 0.0, (float(cell.y) + 0.5) * ROUTE_CELL))
		last_dir = dir
	if out.size() > 0:
		out[out.size() - 1] = exact   # finish at the real spot, not a cell centre
	return out


func _world_gen() -> WorldGen:
	if is_instance_valid(_world):
		return _world
	var st := get_tree()
	_world = (st.get_first_node_in_group("world_gen") as WorldGen) if st != null else null
	return _world


## How the router is doing, for the workshop panel.
func routing_report() -> String:
	return "routes asked %d, unplannable %d, terrain cells remembered %d" % [
		_routes_asked, _routes_failed, _terrain.size()] \
		+ ("  (%d put off to the next frame)" % _routes_deferred if _routes_deferred > 0 else "")
