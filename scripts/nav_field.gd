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
const ROUTE_BUDGET := 380       # cells expanded before a search gives up
const ROUTE_REACH := 400.0      # no route is planned further than this
const WADE_COST := 4.0          # per metre of depth: passable, and unpleasant
const CLIMB_COST := 2.2         # per metre of rise between neighbouring cells
const THICKET_COST := 0.7       # per obstacle standing in a cell
const STEEP := 3.5              # a rise this big between cells is a wall

const _NEIGHBOURS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var _grid := {}          # Vector2i cell -> Array of {p: Vector2, r: float}
var _timer := 0.0
var _terrain := {}       # Vector2i route cell -> {"h": float, "wet": float, "slope": float}
var _world: WorldGen = null
var _routes_asked := 0
var _routes_failed := 0


func _process(delta: float) -> void:
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
		if not is_instance_valid(tree) or tree.is_felled() or tree.is_held():
			continue
		_add(tree.global_position, 0.45 * tree.scale.x + 0.35, true)
	for r in st.get_nodes_in_group("rock_deposits"):
		if is_instance_valid(r):
			_add((r as Node3D).global_position, 1.5, false)


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
		probe := 1.7) -> Vector3:
	if world == null or desired == Vector3.ZERO:
		return desired
	if not world.is_underwater(pos.x + desired.x * probe, pos.z + desired.z * probe):
		if mover != null:
			mover.set_meta("shore_side", 0)  # open water ahead cleared — drop the commit
		return desired
	var side := int(mover.get_meta("shore_side", 0)) if mover != null else 0
	# Try ever-wider turns; the side committed to last frame is tried first
	# (small to large), so the shoreline is followed in one consistent sense.
	for deg: float in _shore_sweep(side):
		var d := desired.rotated(Vector3.UP, deg_to_rad(deg))
		if not world.is_underwater(pos.x + d.x * probe, pos.z + d.z * probe):
			if mover != null:
				mover.set_meta("shore_side", 1 if deg > 0.0 else -1)
			return d
	return Vector3.ZERO


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
	var world := _world_gen()
	var span := Vector2(to.x - from.x, to.z - from.z).length()
	if world == null or span > ROUTE_REACH:
		_routes_failed += 1
		return PackedVector3Array()
	var start := _route_cell(from)
	var goal := _route_cell(to)
	if start == goal:
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
		_routes_failed += 1
		return PackedVector3Array()
	return _unwind(came, start, goal, to)


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
		_routes_asked, _routes_failed, _terrain.size()]
