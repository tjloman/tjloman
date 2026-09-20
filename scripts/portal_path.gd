class_name PortalPath
extends RefCounted
## GOING THE SHORT WAY, OR MARCHING.
##
## A nest has a way through built into it and the miracle opens one for five
## minutes, so a creature on the far side of the world has two ways to answer a
## summons: walk, or step through something. This decides which, and it is
## deliberately the dullest possible answer to that question — work out what
## each way would really cost, take the cheaper one, and if nothing beats
## walking then walk.
##
##     "Check for a shorter route from portals, then if none is found, he
##      marches."
##
## IT DOES NOT GO IN THE GRAPH. The obvious implementation is to make a portal
## an extra neighbour in the A* and let the search find it, and it is wrong: the
## search is guided by `_octile`, a straight-line estimate that is only
## admissible while nothing can beat a straight line. A portal beats it. The
## estimate then over-states what is left to do, A* settles for the first thing
## it finds, and the creature walks past a hole that would have saved it three
## hundred metres — with no error, no stall, and nothing on screen to say why.
## That is the worst kind of bug this game can have, so the search stays honest
## and the comparison happens out here, between whole routes that each contain
## no portals at all.
##
## IT ALSO REACHES FURTHER THAN THE SEARCH CAN. No route is planned past
## NavField.ROUTE_REACH, which is four hundred metres — and a summons from three
## thousand is exactly the case this exists for. Two short legs are routable
## where one long one is not.
##
## AND IT PRUNES BEFORE IT SEARCHES. Routing through every portal in the world
## would cost more searches than a frame is allowed (NavField.ROUTES_PER_FRAME
## is six, and each candidate is two). So each candidate is first priced by
## straight lines, which cannot over-state what it will really cost — a lower
## bound. Any candidate whose lower bound is already worse than the best route
## known is thrown out without a search, and throwing it out cannot lose the
## best answer, because its real cost is at least its bound. That is the whole
## of the efficiency and it is the one property tools/portals.py checks hardest.

## Under this, he is close enough that stepping through anything is silly.
const MARCH_UNDER := 60.0
## What a step through one costs, in the same units a route is priced in. Not
## nothing: a creature should not take a hole to save two paces, and this is
## what stops the arithmetic being a coin toss between two equal routes.
const STEP_COST := 18.0
## And it must WIN, not tie. A portal route has to beat the walk by this much of
## it — which is also what makes ping-pong impossible: coming back out the way
## he came in can never beat the route he has already improved on.
const MUST_BEAT := 0.15
## AND A CHAIN PROMISED FROM A DISTANCE MUST CLEAR A HIGHER BAR than one taken
## standing on the spot. Counting a second hop at the same margin let him set
## off on the strength of a chain that, once he was actually standing at the far
## end, no longer cleared the margin — so he walked from there, having taken a
## hop that did not pay. Four journeys in six hundred, none of them a loop and
## all of them silly. A chain he cannot still want when he gets there is a chain
## he should not have counted.
const CHAIN_BEAT := MUST_BEAT * 2.0
## A HARD CEILING on how many candidates one decision may price properly — and
## it is a safety valve rather than the plan (see the measurement below). Candidates are tried in order of
## the least they could possibly cost, so the moment one of them cannot beat the
## best route found so far, NEITHER CAN ANY OF THE ONES BEHIND IT, and the loop
## stops knowing it has the best answer. In a five-nest network that stops after
## about one.
##
## Stopping at a fixed two instead threw away the best route in seven journeys
## in six hundred, by up to a third of its cost — a cap saves searches by
## refusing to look, and looking was the cheap part.
## Six, because measuring it: four lost the best route in two journeys of six
## hundred by up to a third, and six lost none — at the same 1.4 searches a
## decision, because the bound almost always stops the loop long before the
## ceiling does. The ceiling is for the layout where it does not.
const MOST_TRIED := 6
## And how many ways through one journey may chain. Two: a creature that steps
## out of one ring and straight into another is using the network as it was
## built, and anything beyond that is a route nobody could follow by eye.
## The inside of the chain costs nothing to price — see PortalMap.
const MOST_HOPS := 2


## THE WAY TO GO, as {"path", "via", "cost", "marched"}. `via` is the portal he
## should walk onto, or an empty dictionary if he is simply walking there.
##
## Nothing here moves him. He is given a route to the mouth and the portal does
## the rest when he steps on it, which is why no part of this has to know what
## happens on the other side: the next time he asks, he asks from there.
static func best(from: Vector3, to: Vector3, wade := 2.0, shun := {},
		skip := 0) -> Dictionary:
	NavField.portal_map.opening(wade)
	var walk := NavField.route(from, to, wade, shun)
	# `head_for` is what to steer at when the route comes back empty, which is
	# what happens whenever the far end is past the search's reach. Setting off
	# toward the mouth is the difference between a creature crossing the world
	# in hops and one walking the whole way because it could not plan the whole
	# way — and they are the same creature, one re-plan apart.
	var marching := {"path": walk, "via": {}, "cost": NavField.last_cost,
		"marched": true, "head_for": to}
	var straight := _flat(from, to)
	if straight < MARCH_UNDER:
		return marching
	var best_cost: float = NavField.last_cost
	# A goal too far to route to at all is still somewhere to set off for, and
	# the walk above came back empty. Price it by the ground it covers so a
	# portal has something to beat rather than an infinity it always beats.
	if best_cost == INF:
		best_cost = straight
	var tried := 0
	for gate: Dictionary in _worth_trying(from, to, best_cost, skip):
		# SORTED BY THE LEAST IT COULD COST, so this is the end of the list and
		# not merely the end of this one's chances.
		if float(gate["bound"]) >= best_cost * (1.0 - MUST_BEAT):
			break
		tried += 1
		if tried > MOST_TRIED:
			break
		var legs := _price(from, to, gate, wade, shun)
		if legs["cost"] >= best_cost * (1.0 - MUST_BEAT):
			continue
		best_cost = legs["cost"]
		marching = {"path": legs["path"], "via": gate, "cost": legs["cost"],
			"marched": false, "head_for": gate["mouth"]}
	return marching


## THE CANDIDATES, CHEAPEST POSSIBLE FIRST, with the hopeless ones gone.
##
## The bound is straight lines and a step, which no real route can undercut, so
## a candidate bounded above what walking really costs cannot win however the
## ground lies between here and there.
static func _worth_trying(from: Vector3, to: Vector3, beat: float,
		skip: int) -> Array:
	var live := NavField.portals_open()
	var worth := []
	for gate: Dictionary in live:
		if int(gate["id"]) == skip:
			continue           # the one he has just come out of
		var bound := _flat(from, gate["mouth"]) + STEP_COST \
			+ _least_onward(gate, to, live)
		if bound >= beat * (1.0 - MUST_BEAT):
			continue
		worth.append({"id": gate["id"], "mouth": gate["mouth"],
			"exit": gate["exit"], "until": gate["until"], "bound": bound})
	worth.sort_custom(func(a, b): return float(a["bound"]) < float(b["bound"]))
	return worth


## THE LEAST THE REST OF THE JOURNEY COULD POSSIBLY COST from where this one
## lets him out — walking it, or taking one more way through.
##
## A PORTAL JUMPS SPACE, so the triangle inequality does not hold across one:
## the walk from this exit to the goal is NOT a lower bound on what is left,
## because a short walk to another ring can put him beside the goal. Bounding
## the rest at the straight line to the goal therefore threw away candidates
## that would have won — one in four thousand worlds, and up to a quarter dearer
## when it happened. Every term here is a straight line, so this is still a
## bound; it is simply a bound that knows chains exist.
static func _least_onward(gate: Dictionary, to: Vector3, live: Array) -> float:
	var least := _flat(gate["exit"], to)
	for next_gate: Dictionary in live:
		if int(next_gate["id"]) == int(gate["id"]):
			continue
		least = minf(least, _flat(gate["exit"], next_gate["mouth"]) + STEP_COST
			+ _flat(next_gate["exit"], to))
	return least


## WHAT GOING THROUGH THIS ONE REALLY COSTS: the route to its mouth, the step,
## and the route on from where it lets him out. Either leg failing makes the
## whole candidate impossible rather than free.
## NEITHER LEG BEING PLANNABLE IS A REFUSAL. Both are priced by the ground they
## cover when the search will not reach that far, because he does not have to be
## able to plan the whole way to set off along it — he will be standing
## somewhere new when he next asks.
##
## The near leg mattered most and was got wrong first: a mouth further off than
## ROUTE_REACH could not be routed to, so the candidate was thrown away, and a
## creature with a way through nine hundred metres away marched three thousand
## on foot instead. Measured over a thousand journeys, portals were taken in
## seven of them.
static func _price(from: Vector3, to: Vector3, gate: Dictionary, wade: float,
		shun: Dictionary) -> Dictionary:
	var here := NavField.route(from, gate["mouth"], wade, shun)
	var to_mouth: float = NavField.last_cost
	if to_mouth == INF:
		to_mouth = _flat(from, gate["mouth"])
	return {"cost": to_mouth + STEP_COST + _onward(gate, to, wade, shun),
		"path": here}


## WHAT IS LEFT AFTER IT PUTS HIM DOWN: either the walk to the goal, or another
## way through if one of them turns that walk into a short one. The second hop
## costs no search at all — the leg between two rings is in the map, because
## rings do not move — so a chain is priced for what the first hop already cost.
static func _onward(gate: Dictionary, to: Vector3, wade: float,
		shun: Dictionary, hops := 1) -> float:
	NavField.route(gate["exit"], to, wade, shun)
	var walk: float = NavField.last_cost
	if walk == INF:
		walk = _flat(gate["exit"], to)
	if hops >= MOST_HOPS:
		return walk
	# A CHAIN OF REAL NUMBERS OR NO CHAIN. The leg between the two rings must
	# already have been walked out (PortalMap.known, which refuses to guess),
	# and what is left after the second one must be routable for real. Anything
	# estimated in here makes a hop look better than it is, and a creature that
	# hops on a flattering guess lands further from where it was going.
	for next_gate: Dictionary in NavField.portals_open():
		if int(next_gate["id"]) == int(gate["id"]):
			continue
		var leg: float = NavField.portal_map.known(gate, next_gate)
		if leg < 0.0 or leg + STEP_COST >= walk * (1.0 - CHAIN_BEAT):
			continue
		NavField.route(next_gate["exit"], to, wade, shun)
		var tail: float = NavField.last_cost
		if tail == INF:
			continue
		if leg + STEP_COST + tail < walk * (1.0 - CHAIN_BEAT):
			walk = leg + STEP_COST + tail
		break      # one chain is priced a decision, and it is the best-placed
	return walk


## Distance over the ground, which is what routes are priced in. Height is not
## in it: a route's cost counts the climb as a toll on the step, not as extra
## distance, and mixing the two would make the bound unsafe.
static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()
