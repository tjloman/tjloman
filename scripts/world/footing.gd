class_name Footing
## WHAT HEIGHT A BUILDING STANDS AT, measured against the ground that is
## actually drawn rather than against the ground the noise says is there.
##
## THE TWO ARE NOT THE SAME, and that is the whole reason this file exists.
## `WorldGen.height_at` is a continuous function — noise plus whatever scars
## have been cut into it — and it is exact at any point you care to ask about.
## The terrain you can SEE is not that function: it is a grid of samples off it,
## four metres apart, with two triangles stretched over every cell (see
## Chunk._build_terrain, which hands the same grid to the collision heightmap so
## that what you see and what you walk on cannot disagree).
##
## Between those samples the drawn ground is a FLAT PLANE through three corners,
## and in a hollow — where the land curves up away from the middle of the cell —
## that plane sits ABOVE the true surface by as much as the curvature over four
## metres, which on this terrain is the better part of a metre.
##
## So a building settled at `height_at` in a hollow is settled UNDERNEATH the
## hillside it is standing on. Its plinth is buried, its doorway is buried, and
## from above you see a roof lying in the grass. The schoolhouse is the one this
## was found on — the town raised it, it sank into the green, and the children
## gave up and went back to the totem.
##
## THE FIX IS NOT A FUDGE FACTOR. The drawn ground is piecewise linear between
## grid corners, so its highest point over any footprint is exactly the highest
## of the corners that footprint covers. Ask for that and no part of the
## building can be below the ground, ever, on any terrain — and it is nine noise
## samples for a schoolhouse, paid once, on the frame it is raised.

## A ceiling on the sweep, for anything with an enormous footprint. A jetty is
## sixteen metres of deck; nothing needs two hundred samples to stand up.
const MOST_CORNERS := 64

## The least a thing is treated as being, so something with no collision shape
## at all still settles against a cell rather than a point.
const LEAST_HALF := 0.5


## THE HIGHEST CORNER OF THE DRAWN GROUND under this footprint.
##
## `at` and `half` are in world XZ. The grid is absolute: a chunk's origin is an
## exact multiple of CHUNK_SIZE (see WorldGen._spawn_chunk) and its samples step
## evenly across it, so grid corners fall on multiples of the step in world
## space and this needs no chunk to ask.
static func under(world: WorldGen, at: Vector2, half: Vector2) -> float:
	if world == null:
		return -INF
	var step := WorldGen.CHUNK_SIZE / float(maxi(world.chunk_cells, 1))
	var x0 := floori((at.x - half.x) / step)
	var x1 := ceili((at.x + half.x) / step)
	var z0 := floori((at.y - half.y) / step)
	var z1 := ceili((at.y + half.y) / step)
	var top := -INF
	var taken := 0
	for gz in range(z0, z1 + 1):
		for gx in range(x0, x1 + 1):
			top = maxf(top, world.height_at(float(gx) * step, float(gz) * step))
			taken += 1
			if taken >= MOST_CORNERS:
				return top
	return top


## SIT THIS THING ON THE GROUND. Measured off its OWN collision shape, so the
## building's size and the height it settles at can never be two opinions — the
## same bargain `Util.within` makes with a blow's reach, and for the same
## reason: a table of footprints kept somewhere else drifts from the meshes and
## nothing says so.
##
## Called at the END of a building's own `_ready`, after its shape exists. The
## placer decides WHERE; the building decides how high, because the placer does
## not know how big it is and has guessed wrong about it for a long time.
static func settle(what_given: Variant, world: WorldGen) -> void:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(what_given):
		return
	var what := what_given as Node3D
	if what == null or not is_instance_valid(what) or not what.is_inside_tree():
		return
	var half := footprint_of(what)
	if half == Vector2.ZERO:
		return
	var here := what.global_position
	var top := under(world, Vector2(here.x, here.z), half)
	if is_finite(top):
		what.global_position.y = top


## HOW WIDE THIS THING IS ON THE GROUND, as a world-axis half-extent — the
## rectangle its collision shape occupies, turned by whatever the thing is
## turned by. A village is rotated and everything in it with it, so a footprint
## measured in local space and used in world space is the wrong rectangle.
static func footprint_of(what: Node3D) -> Vector2:
	var half := Vector2.ZERO
	for child in what.get_children():
		var col := child as CollisionShape3D
		if col == null or col.shape == null:
			continue
		var crate := col.shape as BoxShape3D
		if crate != null:
			half = half.max(Vector2(crate.size.x, crate.size.z) * 0.5)
			continue
		var tube := col.shape as CylinderShape3D
		if tube != null:
			half = half.max(Vector2(tube.radius, tube.radius))
			continue
		var ball := col.shape as SphereShape3D
		if ball != null:
			half = half.max(Vector2(ball.radius, ball.radius))
	if half == Vector2.ZERO:
		return Vector2.ZERO
	half = half.max(Vector2(LEAST_HALF, LEAST_HALF))
	# THE AABB OF THE TURNED RECTANGLE. Exact, not a circumscribed square: a
	# schoolhouse turned forty degrees covers a different set of grid corners
	# than one facing north, and rounding that up would lift every building in
	# a village a little further out of the ground than it needs to be.
	var yaw := what.global_basis.get_euler().y
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	return Vector2(half.x * c + half.y * s, half.x * s + half.y * c)
