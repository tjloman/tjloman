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

## How far from the middle of a town its harbour may stand.
const SHORE_WITHIN := 75.0

## THE JETTY, in metres out from the dock's root along the bearing — and the
## reason these live HERE rather than with the mesh that draws them.
##
## A harbour is the one building in this game whose placement has to be CHECKED
## rather than computed. Everywhere else, "a flat dry spot" is the whole
## requirement and any such spot will do. A jetty has to start on land and end
## over water, and whether a given spot manages that depends on the shape of a
## shoreline nobody wrote down. So the shape of the jetty is a fact the finder
## needs, and the finder rejects any spot that cannot carry one.
##
## The deck starts just past the net rack, runs out to JETTY_TO, and everything
## from WET_FROM outward must be over water or it is not a harbour — it is a
## shed by a lake.
## HOW FAR APART A FLEET SPREADS ITSELF over the fishing, and the turn between
## one berth and the next — see `a_berth`.
const APART := 6.0
const GOLDEN := 2.39996
const JETTY_FROM := 0.6
const JETTY_TO := 7.6
const JETTY_WET_FROM := 2.5
## How far inland of the waterline the root stands, so the net rack has ground
## under it. The ONLY part of a dock that is on land.
const SHORE_FOOTING := 1.0
## How finely the waterline is found, and how finely the deck is checked.
const WATERLINE_STEP := 0.25
const DECK_STEP := 1.0

## How long a village's answer about its own water is good for. The land moves —
## an earthquake, a volcano, a deluge — so this is a memory, not a fact.
const REMEMBERS := 60.0

## village instance id -> {"shore": Vector3, "bearing": float, "when": float}.
## A shore of INF means "measured, and there is no harbour here", which is worth
## remembering exactly as much as a yes is. The BEARING is which way the water
## lies from that spot, and it is what lets a jetty be built jutting out over
## the water instead of lying on the beach pointing north.
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
	# A TOWN THAT HAS A HARBOUR DOES NOT GO LOOKING FOR ONE. Its harbour is
	# where its jetty is standing, and re-measuring could only ever disagree
	# with a building that already exists — which is how a dock came to be
	# turned to face a shore it was not standing on.
	var built := _the_dock_of(town)
	if built != null:
		var seaward: float = built.rotation.y + town.rotation.y
		_known[id] = {
			"shore": built.global_position,
			"bearing": atan2(cos(seaward), sin(seaward)),
			"when": GameState.clock,
		}
		return built.global_position
	var found := _look_for_a_shore(town.global_position, world)
	_known[id] = {
		"shore": found.get("at", Vector3.INF),
		"bearing": float(found.get("bearing", 0.0)),
		"when": GameState.clock,
	}
	return _known[id]["shore"]


## WHICH WAY THE WATER LIES from this town's harbour, in radians. Ask
## `harbour_for` first — this reads what that measured, and answers zero for a
## town that has no harbour, which is as good an answer as any for a jetty that
## is never going to be built.
static func bearing_for(town: Village, world: WorldGen) -> float:
	harbour_for(town, world)
	if town == null or not is_instance_valid(town):
		return 0.0
	return float(_known.get(town.get_instance_id(), {}).get("bearing", 0.0))


## THE JETTY THIS TOWN ALREADY HAS, or null. A harbour is a fact once it is
## standing, and everything downstream of that should be reading it rather than
## working it out again.
static func _the_dock_of(town: Village) -> Workshop:
	for w in town.workshops:
		var shop := w as Workshop
		if is_instance_valid(shop) and shop.trade == "dock":
			return shop
	return null


## Rings outward from the town until a dry spot with deep-enough water beside it
## turns up. Nearest first, so a harbour is at the end of the lane rather than
## across the parish.
static func _look_for_a_shore(from: Vector3, world: WorldGen) -> Dictionary:
	var ring := 20.0
	while ring <= SHORE_WITHIN:
		var steps := maxi(8, int(ring / 3.0))
		# THE SAME ANSWER EVERY TIME IT IS ASKED. This was `randf()`, so each
		# re-measure picked a different shore — and the memory expires, so the
		# builder chose one spot and the building read a bearing for another.
		# Seeded off the place instead: still different for two towns on one
		# lake, and never different for the same town twice.
		var turn := _turn_at(from)
		for i in steps:
			var angle := turn + TAU * float(i) / float(steps)
			var probe := from + Vector3(cos(angle), 0.0, sin(angle)) * ring
			var shore := _dock_spot(probe, world, angle)
			if shore != Vector3.INF:
				# The probe was wet and the shore is inshore of it, so the water
				# lies along `angle` from where the jetty will stand. That is
				# the whole of what a dock needs to know to point the right way.
				return {"at": shore, "bearing": angle}
		ring += STEP * 2.0
	return {}


## WHERE THIS PLACE STARTS LOOKING, in radians — a number, not a roll. Two
## towns on one lake still start at different angles because they are in
## different places; one town starts at the same angle for ever.
static func _turn_at(from: Vector3) -> float:
	var cell := Vector2i(int(floor(from.x)), int(floor(from.z)))
	return fmod(absf(float(hash(cell))), TAU)


## IS THIS PROBE A LANDING, AND WOULD A JETTY ACTUALLY REACH THE WATER FROM IT?
##
## The first version asked only the first half: wet here, big enough body, and
## then it walked back to the first dry ground and called that a harbour. Which
## is a spot NEAR water, and near water is what every other building in the
## village already is. On a shallow shore the walk-back landed metres inland,
## the jetty ran out over grass, and the boats moored on the lawn.
##
## So the waterline is found properly — bisected, not stepped — the root stands
## one metre inland of it, and then the whole deck is WALKED and every plank
## past JETTY_WET_FROM has to be over water. A spot that cannot carry a jetty is
## not a harbour and is refused, and the search goes on looking.
static func _dock_spot(probe: Vector3, world: WorldGen, angle: float) -> Vector3:
	if not world.is_underwater(probe.x, probe.z):
		return Vector3.INF
	if surface_from(world, probe) < ENOUGH:
		return Vector3.INF
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var shore := _waterline(probe, out, world)
	if shore == Vector3.INF:
		return Vector3.INF
	var root := shore - out * SHORE_FOOTING
	if world.is_underwater(root.x, root.z):
		return Vector3.INF          # nowhere to stand the net rack
	if not _deck_is_over_water(root, out, world):
		return Vector3.INF
	root.y = world.height_at(root.x, root.z)
	return root


## THE WATERLINE, between a wet point and the dry land behind it. Bisected to
## WATERLINE_STEP, so the answer is the edge itself rather than whichever of a
## handful of paces happened to be the first one on grass.
static func _waterline(wet: Vector3, out: Vector3, world: WorldGen) -> Vector3:
	# Far enough back to be sure of finding dry ground; if the whole span is
	# water this is a spot in the middle of a lake and no use for a jetty.
	var dry := wet - out * (JETTY_TO + SHORE_FOOTING * 2.0)
	if world.is_underwater(dry.x, dry.z):
		return Vector3.INF
	while wet.distance_to(dry) > WATERLINE_STEP:
		var mid := (wet + dry) * 0.5
		if world.is_underwater(mid.x, mid.z):
			wet = mid
		else:
			dry = mid
	return wet


## WOULD A JETTY STANDING HERE REACH THE WATER? Asked of the WORLD, by anybody,
## about any spot — which is the point of it being public.
##
## THE DOCK HAS BEEN BUILT ON GRASS THREE TIMES. Twice I put a guard on the door
## it comes through, and twice the guard asked the wrong question: it compared
## the spot being built on against what `harbour_for` said the harbour was, and
## agreed. Two functions agreeing is not evidence. If the finder is wrong, or
## its memory is stale, or the pond a rain miracle made has since drained, both
## sides of that comparison are wrong together and the door opens.
##
## So the door asks the ground instead. A jetty is a thing that has to be over
## water, and whether it is over water is a question with an answer that does
## not depend on anybody's bookkeeping.
static func can_carry_a_jetty(root: Vector3, bearing: float, world: WorldGen) -> bool:
	if world == null:
		return false
	return _deck_is_over_water(
		root, Vector3(cos(bearing), 0.0, sin(bearing)), world)


## HOW FAR THE DRY PART OF A DECK RUNS before the water has to start. For the
## refusal's message, so a warning says how badly it missed rather than that it
## missed.
static func dry_deck(root: Vector3, bearing: float, world: WorldGen) -> float:
	if world == null:
		return INF
	var out := Vector3(cos(bearing), 0.0, sin(bearing))
	var along := JETTY_WET_FROM
	while along <= JETTY_TO:
		if not world.is_underwater(root.x + out.x * along, root.z + out.z * along):
			return along
		along += DECK_STEP
	return 0.0


## WALK THE DECK. Every plank from JETTY_WET_FROM out to the end must be over
## water — this is the whole difference between a harbour and a shed by a lake,
## and it is a check rather than a calculation because the shape of a shoreline
## is not something anybody wrote down.
static func _deck_is_over_water(root: Vector3, out: Vector3, world: WorldGen) -> bool:
	var along := JETTY_WET_FROM
	while along <= JETTY_TO:
		var plank := root + out * along
		if not world.is_underwater(plank.x, plank.z):
			return false
		along += DECK_STEP
	return true


## IS THERE A HARBOUR HERE AT ALL — asked of a bare point rather than of a
## village, and not remembered. For the world generator, which is choosing where
## a town goes and has no village to ask about yet.
static func coast_at(at: Vector3, world: WorldGen) -> bool:
	# `is_empty` and not `!= Vector3.INF`: the search hands back a spot AND the
	# bearing to the water now, and comparing that Dictionary to a Vector3 is a
	# compile error that takes the whole game down at launch.
	return not _look_for_a_shore(at, world).is_empty()


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


## A FISHING SPOT OF ONE'S OWN, near the harbour's water but not on top of the
## last boat that asked.
##
## A harbour works out where the fishing is ONCE and hands the same spot to
## every hull it ever builds, so a fleet of three rowed out to the same square
## metre and sat inside each other — one flat slab of overlapping boats, which
## is what a village's whole fishing industry looked like from the shore.
##
## The spread is a phyllotaxis: each boat is turned by the golden angle from the
## one before and set a little further out, which is how a sunflower packs seeds
## without any of them touching and needs no knowledge of where the others
## actually are. It only has to be deterministic and it only has to spread; the
## boats keep out of each other's way while rowing on their own (see
## FishingBoat._give_way).
##
## Water is still the rule. A spot that lands on the beach is walked back in
## toward the middle until it floats, and a fleet crowded into a narrow inlet
## ends up in a line down it rather than in a heap at the end of it.
static func a_berth(world: WorldGen, centre: Vector3, which: int) -> Vector3:
	if world == null or not centre.is_finite():
		return centre
	if which <= 0:
		return centre
	var angle := float(which) * GOLDEN
	var reach := APART * sqrt(float(which))
	while reach > 1.0:
		var probe := centre + Vector3(cos(angle), 0.0, sin(angle)) * reach
		if world.is_underwater(probe.x, probe.z):
			probe.y = world.water_level_at(probe.x, probe.z)
			return probe
		reach -= STEP * 0.5
	return centre


## FORGET WHAT WAS MEASURED HERE. For the land actually changing under a town —
## a lake dug, a shore raised — where waiting out the memory is the wrong answer.
static func forget(town: Village) -> void:
	if town != null and is_instance_valid(town):
		_known.erase(town.get_instance_id())
