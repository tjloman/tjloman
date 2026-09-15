class_name Waters
extends RefCounted
## HOW MUCH WATER IS ACTUALLY THERE.
##
## Everything in the game that has ever asked about water asked a POINT
## question — is this spot underwater, what is the surface here, does the sea
## reach this hollow. That is the right question for drowning a villager and
## the wrong one for a harbour. A fishing town wants to know about a BODY of
## water: whether the wet patch at the end of the lane is a puddle, a pond you
## could row a boat round, or the sea.
##
## So this floods. From a wet probe it walks outward on a lattice, counting
## connected water, and stops the moment it has counted enough — which is the
## only reason this is affordable at all. A dock wants about two and a half
## thousand square metres and finds it in a couple of hundred probes; a village
## standing beside a duckpond fails in a dozen and never pays for the rest.
##
## AND IT REMEMBERS. `short_of` is asked whenever any villager stops to think,
## so a town with two mills and no dock would run this flood several times a
## second forever. The answer is cached per village against GameState.clock and
## re-measured now and then, because the land is not fixed: an earthquake or a
## volcano can make a lake, and a town that could not fish last year can now.

## HOW FINE THE LATTICE IS, in metres, and how much connected surface a working
## harbour wants. Five metres is a boat's length -- water that reads as a body
## at that spacing is water you could put a boat on -- and two and a half
## thousand square metres is roughly a fifty-metre pond.
const STEP := 5.0
const ENOUGH := 2400.0
## A HARD CEILING on the flood, whatever it has found. The sea is unbounded and
## this must never walk it: the early exit at ENOUGH is what normally stops it,
## and this is what stops it when somebody raises ENOUGH and forgets.
const PROBES_MOST := 700

## How far from the middle of a town its harbour may stand, and how close to the
## water's edge the dock itself sits.
const SHORE_WITHIN := 75.0
const DOCK_OFF_THE_WATER := 3.0

## How long a village's answer about its own water is good for. The land moves —
## an earthquake, a volcano, a deluge — so this is a memory, not a fact.
const REMEMBERS := 60.0

## village instance id -> {"shore": Vector3, "when": float}. A shore of INF means
## "measured, and there is no harbour here", which is worth remembering exactly
## as much as a yes is.
static var _known := {}


## HOW MUCH CONNECTED WATER TOUCHES THIS SPOT, in square metres, counted no
## further than `enough`. The answer is a floor rather than a total: past the
## early exit it stops looking, so "2400" means "at least 2400".
static func surface_from(world: WorldGen, at: Vector3, enough := ENOUGH) -> float:
	if world == null or not world.is_underwater(at.x, at.z):
		return 0.0
	var per_cell := STEP * STEP
	var seen := {}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	seen[queue[0]] = true
	var wet := 0
	var probed := 0
	while not queue.is_empty() and probed < PROBES_MOST:
		var cell: Vector2i = queue.pop_front()
		probed += 1
		var x := at.x + float(cell.x) * STEP
		var z := at.z + float(cell.y) * STEP
		if not world.is_underwater(x, z):
			continue
		wet += 1
		if float(wet) * per_cell >= enough:
			return float(wet) * per_cell
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return float(wet) * per_cell


## WHERE THIS TOWN'S HARBOUR WOULD STAND, or INF if it has no water worth one.
## Dry ground at the edge of a body big enough to row on, as near the town as
## such a spot can be found. Remembered — see the header.
static func harbour_for(town: Village, world: WorldGen) -> Vector3:
	if town == null or not is_instance_valid(town) or world == null:
		return Vector3.INF
	var id := town.get_instance_id()
	var held: Dictionary = _known.get(id, {})
	if not held.is_empty() and GameState.clock - float(held["when"]) < REMEMBERS:
		return held["shore"]
	var found := _look_for_a_shore(town.global_position, world)
	_known[id] = {"shore": found, "when": GameState.clock}
	return found


## Rings outward from the town until a dry spot with deep-enough water beside it
## turns up. Nearest first, so a harbour is at the end of the lane rather than
## across the parish.
static func _look_for_a_shore(from: Vector3, world: WorldGen) -> Vector3:
	var ring := 20.0
	while ring <= SHORE_WITHIN:
		var steps := maxi(8, int(ring / 3.0))
		var turn := randf() * TAU     # so two towns on one lake do not stack
		for i in steps:
			var angle := turn + TAU * float(i) / float(steps)
			var probe := from + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var shore := _dock_spot(probe, world, angle)
			if shore != Vector3.INF:
				return shore
		ring += STEP * 2.0
	return Vector3.INF


## IS THIS PROBE A LANDING? It has to be wet, on a body big enough to matter,
## and to have dry ground just inshore of it to stand the dock on.
static func _dock_spot(probe: Vector3, world: WorldGen, angle: float) -> Vector3:
	if not world.is_underwater(probe.x, probe.z):
		return Vector3.INF
	if surface_from(world, probe) < ENOUGH:
		return Vector3.INF
	# Walk back toward the town until the ground comes up, and stand there.
	var back := -Vector3(cos(angle), 0.0, sin(angle))
	for i in range(1, 7):
		var at := probe + back * (DOCK_OFF_THE_WATER * float(i) * 0.5)
		if not world.is_underwater(at.x, at.z):
			at.y = world.height_at(at.x, at.z)
			return at
	return Vector3.INF


## IS THERE A HARBOUR HERE AT ALL — asked of a bare point rather than of a
## village, and not remembered. For the world generator, which is choosing where
## a town goes and has no village to ask about yet.
static func coast_at(at: Vector3, world: WorldGen) -> bool:
	return _look_for_a_shore(at, world) != Vector3.INF


## OPEN WATER OFF A LANDING, as far out as `reach` and as far out as it can
## get — where a boat goes when it puts to sea. Farthest first, because a boat
## rowing twenty metres out reads as fishing and one rowing three reads as
## having come adrift.
static func off_shore(world: WorldGen, from: Vector3, reach: float) -> Vector3:
	if world == null:
		return Vector3.INF
	var out := reach
	while out >= STEP:
		var turn := randf() * TAU
		for i in 12:
			var angle := turn + TAU * float(i) / 12.0
			var probe := from + Vector3(cos(angle), 0.0, sin(angle)) * out
			if world.is_underwater(probe.x, probe.z):
				probe.y = world.water_level_at(probe.x, probe.z)
				return probe
		out -= STEP
	return Vector3.INF


## FORGET WHAT WAS MEASURED HERE. For the land actually changing under a town —
## a lake dug, a shore raised — where waiting out the memory is the wrong answer.
static func forget(town: Village) -> void:
	if town != null and is_instance_valid(town):
		_known.erase(town.get_instance_id())
