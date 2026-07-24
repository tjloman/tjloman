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

var _grid := {}          # Vector2i cell -> Array of {p: Vector2, r: float}
var _timer := 0.0


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
