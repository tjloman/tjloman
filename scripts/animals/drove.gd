class_name Drove
## A BARN'S DAY IS PLOTTED AT DAWN AND THEN OBEYED.
##
## Village stock are not wildlife and must not cost what wildlife costs. A wild
## herd DECIDES things — where to graze, what to run from, whether to split, who
## to join — and every one of those decisions is a reason to look at the world.
## A barn's book decides nothing at all. It is let out, walked down a street,
## watered, put on grass, fed at a trough and drawn back in: six places, settled
## once each morning, and between them the whole herd takes ONE instruction.
##
## That is the whole brief, and it is worth being plain about what it buys. The
## route is six vectors worked out once a day. The marching order is laid out
## once a leg. In between, nothing per-head is decided by anybody. A barn of a
## hundred and sixty head costs what a barn of twelve costs, because a hundred
## and forty-eight of them are indoors and the twelve in the street are walking
## in a line somebody drew for them at dawn.
##
## THE DAY ALSO DIVIDES THEM. Some go to the storehouse — that is what keeping
## stock is FOR, and it is the only thing a barn does that a pen does not. Some
## stand at the trough eating the town's grain all day and never leave the yard.
## The rest walk the round. Which of the three a beast is doing is not a
## decision either: it is three numbers off the top of the book.

## THE LEGS, IN ORDER, from first light to dusk. Two turns down a street,
## because the street is the half of this the player actually watches: a town
## whose own animals cross its square twice a day is a town that is being lived
## in rather than a set of buildings with people pathing between them.
const DAY: Array[String] = ["out", "street", "well", "pasture", "street", "in"]
## How long one leg lasts. Six of these is a little under half of a day's light,
## which leaves the morning and the evening in the yard where they belong.
const LEG_SECONDS := 26.0

## HOW FAR PASTURE STANDS FROM THE BARN, and how far outside the last ring of
## houses the lane runs. Stock walk round the town, not through people's doors.
const PASTURE_OUT := 17.0
const LANE_CLEAR := 4.5
## The least a town can have for a lane, for a village whose houses are all
## still crowded round the totem on its first morning.
const LANE_LEAST := 9.0
## How far round the town one day's droving goes. Not the whole circle: a lap of
## the village is a parade, and half of one is a street.
const WALKS_ROUND := 0.42

## THE COLUMN. How many abreast, how far apart along the line and across it.
## Three abreast is a drove road; one is a procession and six is a mob.
const ABREAST := 3
const RANK_GAP := 1.9
const FILE_GAP := 2.1
## And how much each one is out of step, which is the whole difference between
## animals and a parade. Off the row's own index, so it is the same every time
## the column forms and costs nothing to reproduce.
const OUT_OF_STEP := 0.34

## WHAT EACH MORNING TAKES OUT OF THE BOOK.
##
## A share to the storehouse — the day's yield, and the reason a village keeps
## stock at all. Six in a hundred is about a beast a day for a middling farm,
## which is a real return without being a machine for turning grass into meat.
const TO_THE_STORE := 0.06
## ...and what one head is worth in the store, beyond its own species' meat.
const DRESSED_OUT := 2
## A share that never leaves the yard: the ones standing at the trough with
## their heads down from dawn to dusk. Every farm has them. Taken out of the
## LOOSE STOCK — the handful the barn keeps as real animals — because a beast
## that stands still all day in front of the player is exactly the kind that
## wants a body, and because the book has one position and cannot be in two
## places. See Workshop, which drives the yard's beasts.
const AT_THE_TROUGH := 0.4

## WHAT THE TROUGH COSTS, per head in the book, per day. Grain out of the town's
## own store — which is the point, and the answer to a barn that had grown to a
## hundred and sixty head beside twelve hungry people: stock EAT now, so a herd
## too big for its village empties the granary and then thins itself, instead of
## standing there costing nothing and crowding the town out.
const FEED_PER_HEAD := 0.09
## And what a full trough is worth against the herd's hunger — see Herd.hunger,
## which is ONE number for the whole herd and not one per beast.
##
## IT HAS TO BEAT A WHOLE DAY OF APPETITE, and the first number here did not: a
## herd gets hungrier every season and there are eight seasons in a day, so a
## trough worth half a season's hunger meant every barn in the game starved its
## stock to death in a day and a half no matter how much grain the town had. The
## floor under this is Herd.HUNGER_PER_SEASON times the seasons in a day; what
## is above that floor is the margin a well-run farm has. See tools/drove.py,
## which walks the ledger off the shipped numbers and fails the build if a
## FULLY FED herd would ever lose ground.
const A_GOOD_FEED := 1.5


## THE DAY'S ROUTE, one spot per leg of DAY. Worked out once, at dawn, and then
## simply indexed — which is what makes every leg after it a lookup.
##
## `day` turns the round. A drove that took the same line past the same six
## doors every morning for an hour is a conveyor belt; a different quarter of
## the town each day is a village. It is the DAY and not a die, so the same town
## on the same morning plots the same streets however often it is asked.
static func plot(town: Village, barn_at: Vector3, well_at: Vector3,
		day: int) -> Array[Vector3]:
	var here := town.global_position
	var lane := maxf(_built_out(town) + LANE_CLEAR, LANE_LEAST)
	var turn := _turn_for(town, day)
	var route: Array[Vector3] = []
	var streets := 0
	for leg: String in DAY:
		match leg:
			"out":
				route.append(barn_at + Vector3(2.2, 0.0, 0.0))
			"street":
				# The second street is most of a lap further round than the
				# first, so the herd comes home the other side of the town it
				# left by rather than back down its own hoofprints.
				var along := turn + TAU * WALKS_ROUND * float(streets)
				streets += 1
				route.append(here + Vector3(cos(along), 0.0, sin(along)) * lane)
			"well":
				route.append(well_at if well_at.is_finite() else barn_at)
			"pasture":
				var out := turn + PI
				route.append(here + Vector3(cos(out), 0.0, sin(out))
					* (lane + PASTURE_OUT))
			_:
				route.append(barn_at)
	return route


## WHERE THE TROUGH STANDS — beside the barn, on the yard side, and the barn's
## own prop is built at the same spot. One answer, so the thing the stock walk
## to and the thing the player sees are the same object.
static func trough_at(barn_at: Vector3) -> Vector3:
	return barn_at + Vector3(0.0, 0.0, 3.1)


## HOW FAR OUT THE TOWN IS BUILT. The lane runs outside the last of it.
static func _built_out(town: Village) -> float:
	var out := 0.0
	var here := town.global_position
	for h in town.houses:
		if is_instance_valid(h):
			out = maxf(out, Vector2(h.global_position.x - here.x,
				h.global_position.z - here.z).length())
	return out


## THE DAY'S QUARTER, and it is a hash rather than a die — see `plot`.
static func _turn_for(town: Village, day: int) -> float:
	var sown := hash("%s/%d" % [town.village_name, day])
	return float(sown % 1024) / 1024.0 * TAU


## FORM UP. The column is laid out ONCE, when the barn gives the leg's one
## order, and then nobody in it thinks again until the next one.
##
## `rows` are the herd's members and `many` is how many of them are actually in
## the street (the rest are indoors — see Herd.shown). One sine and one cosine
## for the whole column; everything after that is adds, which is the same bargain
## the rest of the herd code makes and for the same reason.
static func form_up(rows: Array, many: int, heading: float) -> void:
	var ahead := Vector2(sin(heading), cos(heading))
	var across := Vector2(ahead.y, -ahead.x)
	var walking := mini(many, rows.size())
	var ranks := maxi(int(ceil(float(walking) / float(ABREAST))), 1)
	for i in walking:
		# Centred on the herd's own heart rather than trailing behind it, or
		# `Herd._recentre` would spend the rest of the day dragging the mass
		# forward onto the column and the column back off it.
		var back := (float(i / ABREAST) - float(ranks - 1) * 0.5) * RANK_GAP
		var side := (float(i % ABREAST) - float(ABREAST - 1) * 0.5) * FILE_GAP
		# AND NOBODY IS QUITE IN LINE. Off the row's own index, so it is the
		# same lean every time this column forms — a drove, not a parade, and
		# deterministic, which means a test can say what it looks like.
		var lean := float((i * 7) % 5) - 2.0
		rows[i]["offset"] = across * (side + lean * OUT_OF_STEP) \
			- ahead * (back + lean * OUT_OF_STEP)
	# AND THE ONES WHO ARE NOT OUT ARE IN THE BARN. Their offsets were dealt on
	# the day the herd was born and have been carried ever since — which put a
	# hundred and forty invisible beasts in a thirty-metre blob around the yard,
	# and `_widest` is measured over all of them, so the barn answered the
	# player's hand from half a street away. They are indoors. Indoors is here.
	for i in range(walking, rows.size()):
		rows[i]["offset"] = Vector2.ZERO
