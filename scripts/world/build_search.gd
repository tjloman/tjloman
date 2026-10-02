class_name BuildSearch
extends RefCounted
## WHERE THE NEXT BUILDING GOES, ASKED A SPOT AT A TIME.
##
## Village.find_build_spot sweeps rings out from the totem, BUILD_ANGLES spots a
## ring, and each spot that is not already built over costs some forty land
## reads. A town with no room left sweeps every ring out to the edge of its reach
## and finds nothing — some fifteen thousand land reads, and the 3.6-second frame
## the meter caught as one `Village:founding` call, the last house of a town over
## the horizon looking for ground it did not have.
##
## So the sweep is an object that remembers where it got to. `run` looks at spots
## until it is told to stop and picks up there next time: a town being founded
## gives it a few milliseconds a frame (Village.FOUNDING_SLICE_USEC), and anyone
## who needs the answer now runs it to the end. Every building the town raises
## goes through this — anything new added to a founding gets the slicing by
## asking for its spot the same way.

## How many ways a sweep may be turned. See `_init`.
const TURNS := 4

## The answer, once `done`: a world position, or INF when there is no room.
var found := Vector3.INF
var done := false
## The ring it is on; past the reach when it gave up. See Village._searched.
var band: float
var own_room: float
var _village: Village
var _world: WorldGen
var _reach: float
var _turn: float
var _step := 0
var _best := Vector3.INF
var _best_room := -1.0


func _init(village: Village, world: WorldGen, room: float, from_band: float,
		reach: float) -> void:
	_village = village
	_world = world
	own_room = room
	band = from_band
	_reach = reach
	# The whole sweep is turned per search so a town does not end up with every
	# building it ever raises on the same handful of bearings — by one of TURNS
	# fixed amounts, not any amount: the spots of every search are then spots
	# some search has stood on before, and what the land said is used again.
	_turn = TAU * float(randi() % TURNS) / float(Village.BUILD_ANGLES * TURNS)
	done = band > reach


## Look at spots until `budget_usec` has gone (0: to the end). True when done.
## The budget is checked after every spot, so a slice runs over by one spot at
## most — forty-odd land reads, not a ring of them.
func run(budget_usec := 0) -> bool:
	var began := Time.get_ticks_usec()
	while not done:
		if _step >= Village.BUILD_ANGLES:
			# A RING IS FINISHED. Within it the most open spot wins, which is what
			# stops a row of buildings bunching into one arc.
			if _best != Vector3.INF:
				found = _best
				done = true
				break
			band += Village.BUILD_BAND
			_step = 0
			if band > _reach:
				done = true
				break
		_look(_turn + TAU * float(_step) / float(Village.BUILD_ANGLES))
		_step += 1
		if budget_usec > 0 and Time.get_ticks_usec() - began >= budget_usec:
			break
	return done


## ONE SPOT. Cheapest question first: is it taken (distances only, no land),
## then the land — asked of the village, which remembers what the land said
## about this spot (Village._ground_for_building) — and taken again at the
## settled height.
##
## ON A GRID OF Village.GROUND_CELL. The sweep is turned at random each time, so
## no two searches used to stand on the same spot and nothing learned about the
## ground could ever be used twice. Snapped, the next search lands on spots the
## last one already asked about, and asks the land nothing.
func _look(angle: float) -> void:
	var pos := _village.global_position + Vector3(cos(angle) * band, 0, sin(angle) * band)
	pos.x = snappedf(pos.x, Village.GROUND_CELL)
	pos.z = snappedf(pos.z, Village.GROUND_CELL)
	if _village._spot_blocked(pos, own_room):
		return
	if _world != null:
		var settled := _village._ground_for_building(_world, pos)
		if is_nan(settled):
			return
		pos.y = settled
	if _village._spot_blocked(pos, own_room):
		return
	var room := _village._room_at(pos)
	if room > _best_room:
		_best_room = room
		_best = pos
