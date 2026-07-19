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
		_add(tree.global_position, 0.45 * tree.scale.x + 0.35)
	for r in st.get_nodes_in_group("rock_deposits"):
		if is_instance_valid(r):
			_add((r as Node3D).global_position, 1.5)


func _add(pos: Vector3, radius: float) -> void:
	var cell := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append({"p": Vector2(pos.x, pos.z), "r": radius})


## Given a spot, a desired (normalized, xz) direction, and the mover's
## radius, return an adjusted direction that steers around nearby trees and
## rocks. `ignore` is a world point whose obstacle is the mover's actual
## goal (the tree it's walking to chop) — so it isn't repelled from it.
func steer(pos: Vector3, desired: Vector3, self_radius: float,
		ignore := Vector3.INF) -> Vector3:
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
