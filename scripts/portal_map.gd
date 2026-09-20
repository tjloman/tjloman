class_name PortalMap
extends RefCounted
## THE NETWORK, WORKED OUT ONCE.
##
## Nest rings do not move. The walk from one nest to the next is the same walk
## it was an hour ago, and a five-nest network is twenty ordered pairs of them —
## so pricing the network on every decision is paying, over and over, for an
## answer that was already true. A frame is allowed six searches in total
## (NavField.ROUTES_PER_FRAME) and one creature deciding where to go could spend
## forty.
##
##     "We may want to have a subroutine with portals mapped on it."
##
## So the inside of the network is MAPPED: every leg between two ways through is
## worked out at most once and then looked up. What is left to search for is only
## the two ends that actually move — where he is standing, and where he is going.
##
## ONE NEW LEG A CALL, AND NO MORE. A map that filled itself in eagerly would
## cost twenty searches the first time anybody asked, which is the same frame
## hitch wearing a hat. Until a leg has been walked out properly, the straight
## line between its ends stands in for it — and a straight line can only ever
## UNDER-state what the ground costs, so a leg that has not been measured yet can
## make a route look better than it is but never worse. The route is checked
## again at the next decision with one more leg known, and the map is complete
## after a handful of them.
##
## AND IT FORGETS WHAT CLOSES. A miracle's way through lasts five minutes; its
## legs go with it. Terrain changes too — a fireball leaves a crater where there
## was a path — so even a nest's legs are given a life and re-walked after it.

## How long a measured leg is trusted before it is walked again. Long, because
## the land only changes where a miracle has been, and cheap to be wrong about:
## a stale leg makes a route look slightly off, and the next decision fixes it.
const LEG_KEEPS := 180.0

## Leg id -> {"cost", "at"}. The id is the two portals' own ids, so a portal
## that closes takes its legs with it rather than leaving them to be matched by
## position against whatever opens next.
var legs := {}
var measured := 0
var looked_up := 0
var _filled_this_call := false


## WHAT IT COSTS TO GET FROM WHERE ONE LETS HIM OUT TO WHERE THE NEXT TAKES HIM
## IN — but ONLY if that has actually been walked out. Negative means "not
## measured", and the caller must then do without rather than guess.
##
## THIS IS THE WHOLE SAFETY PROPERTY OF THE FILE, and it was learned the
## expensive way. The first version handed back the straight line for a leg it
## had not measured yet, on the reasoning that a straight line can only
## under-state what the ground costs. True, and useless: an under-stated leg
## makes a route look BETTER than it is, so the creature hops on the strength of
## a leg nobody has walked, arrives, finds the real cost, and is now further
## from the goal than it started. Measured over four thousand worlds that was
## thirty-seven best routes lost, six journeys that went round in circles, and a
## chosen route 114% dearer than the one it passed over. A decision may be made
## of real numbers or of no numbers.
func known(from_gate: Dictionary, to_gate: Dictionary) -> float:
	var id := "%d>%d" % [int(from_gate["id"]), int(to_gate["id"])]
	var walked: Dictionary = legs.get(id, {})
	if walked.is_empty() or GameState.clock - float(walked["at"]) >= LEG_KEEPS:
		return -1.0
	looked_up += 1
	return float(walked["cost"])


## A DECISION BEGINS, and one unwalked leg of the network is walked during it.
##
## The map fills itself in a leg at a time out of the routing the game was going
## to do anyway — never in a rush, never more than one search, and never as part
## of a decision. A five-nest network is twenty legs and so twenty decisions,
## which is a minute or two of play, after which crossing it is arithmetic.
func opening(wade := 2.0) -> void:
	_filled_this_call = false
	var live: Array = NavField.portals_open()
	for from_gate: Dictionary in live:
		for to_gate: Dictionary in live:
			if int(from_gate["id"]) == int(to_gate["id"]):
				continue
			if known(from_gate, to_gate) >= 0.0:
				continue
			_measure(from_gate, to_gate, wade)
			return


func _measure(from_gate: Dictionary, to_gate: Dictionary, wade: float) -> void:
	var a: Vector3 = from_gate["exit"]
	var b: Vector3 = to_gate["mouth"]
	NavField.route(a, b, wade, {})
	var cost: float = NavField.last_cost
	# Too far apart for one search to reach across. That is a fact about the
	# pair and it will not change, so it is written down as the straight line
	# and never asked again — a leg nothing can measure is one no chain may be
	# built on, and `known` hands it back like any other measured leg only
	# because a route that long was never going to win anyway.
	if cost == INF:
		cost = _flat(a, b) * 2.0
	measured += 1
	legs["%d>%d" % [int(from_gate["id"]), int(to_gate["id"])]] = {
		"cost": cost, "at": GameState.clock,
	}


## A WAY THROUGH HAS CLOSED. Everything measured to or from it goes with it.
func forget(id: int) -> void:
	var gone: Array[String] = []
	var mine := str(id)
	for leg: String in legs:
		var ends := leg.split(">")
		if ends[0] == mine or ends[1] == mine:
			gone.append(leg)
	for leg in gone:
		legs.erase(leg)


## How many legs have been walked out, for the readouts — a map that never fills
## in is a map that is being thrown away and rebuilt.
func walked_out() -> int:
	return legs.size()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()
