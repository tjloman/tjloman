class_name Workshop
extends StaticBody3D
## A BUILDING THAT MAKES WORK, which is the thing a big village actually runs
## short of.
##
## The problem is arithmetic and it was measured before any of this was written.
## A settled village — housed, stocked, nothing urgent — has four jobs worth
## doing: farm, hunt, fish, tame. Each one saturates at three or four people,
## because the crowd penalty pushes the fifth off it. At twelve villagers that is
## fine and everyone is busy. AT FIFTY, SIXTY-FOUR PER CENT OF THE TOWN HAS
## NOTHING TO DO — which is what "they infinitely stack wheat or try to slay
## everything" actually looks like from inside the code.
##
## So the fix is not a cleverer job-picker. It is more jobs, and jobs that arrive
## by the village BUILDING something, so that a town growing bigger visibly
## grows more complicated.
##
## ADD A TRADE BY ADDING A TRADES ROW. That is the whole job — the same bargain
## Animal.SPECIES and Herd.SOCIAL make. A trade says what it costs to raise, how
## many hands it keeps busy, what it takes in and what it gives back, and what it
## looks like. Nothing else in the game needs to know the difference between a
## mill and a tannery.

## WHAT A VILLAGE CAN RAISE.
##
##  employs — how many can work here at once. This is the number that actually
##            answers the idleness problem, so it is first.
##  lumber/stone — what it costs to build.
##  takes/makes  — a standing conversion, run per SHIFT by whoever works here.
##                 Both are in store units; an empty `takes` is work that needs
##                 no materials, which is what a well and a shrine are.
##  wants   — how many of this trade a village will keep, per head of population.
##  needs   — a condition beyond population, or "" for none.
const TRADES := {
	# WATER. Costs nothing to run and makes the fields yield — the plainest
	# possible job, and the first one a growing village should reach for.
	"well": {
		"employs": 2, "lumber": 2, "stone": 6,
		"takes": {}, "makes": {},
		"wants": 1.0 / 18.0, "needs": "",
		"label": "Well", "tint": Color(0.58, 0.58, 0.62),
	},
	# GRAIN GOES FURTHER GROUND. Takes plant food and gives back more of it,
	# which is what milling is, and it gives a farming town somewhere for its
	# surplus to go besides a heap.
	# WHAT A TOWN DOES WITH A SURPLUS, and only with a surplus. A mill turns 4
	# plant into 6 — it does not GROW food, it makes food that already exists go
	# half again as far — so it is worth nothing at all to a town with none to
	# spare, and worth building only once the fields are ahead. It ran whenever
	# there were four grains in the store, which meant a hungry village put three
	# people on a millstone, and three people on a millstone are three people not
	# in the field. See `work_shift`.
	#
	# Two posts and one per forty souls, down from three and one per twenty-two:
	# a village of sixty had three mills and nine milling jobs, which is a lot of
	# a town's labour committed to a building that cannot feed it.
	"mill": {
		"employs": 2, "lumber": 8, "stone": 4,
		"takes": {"plant": 4}, "makes": {"plant": 6},
		"wants": 1.0 / 40.0, "needs": "grain",
		"label": "Mill", "tint": Color(0.74, 0.66, 0.48),
	},
	# STOCK. This is the one that changes what a village CAN BE. A pen holds
	# eight beasts; a barn holds forty more, which is the difference between
	# keeping animals and keeping a herd. Only ever raised by a town already
	# herding to the limit of its pen — see `_makes_sense`.
	"barn": {
		"employs": 3, "lumber": 10, "stone": 2,
		"takes": {"plant": 2}, "makes": {"meat": 3},
		"wants": 1.0 / 25.0, "needs": "stock",
		"label": "Barn", "tint": Color(0.55, 0.38, 0.26),
	},
	# THE SEA. The biggest timber investment a village ever makes, and the only
	# building in the game that CANNOT BE RAISED WHEREVER THE TOWN LIKES: it
	# wants real water beside it — a body you could row a boat round, not the
	# wet patch at the end of the lane — and a town that has none simply never
	# builds one however rich it gets. See Waters, which floods the shoreline to
	# find out, and `needs: "water"`, which also wants two mills standing first.
	#
	# It takes nothing and gives back four fish a shift. Fishing is the one
	# trade that makes food out of NOTHING BUT LABOUR — no seed corn, no herd,
	# no field to water — which is exactly why it costs thirty timber and two
	# mills to get to, and why a coastal village is a different kind of town
	# rather than a village with a nice view.
	"dock": {
		"employs": 3, "lumber": 30, "stone": 6,
		"takes": {}, "makes": {"meat": 4},
		"wants": 1.0 / 20.0, "needs": "water",
		"label": "Fishing dock", "tint": Color(0.42, 0.5, 0.58),
	},
	# A SECOND PLACE TO PRAY, so worship is not one queue at one totem.
	# ONE PAIR OF HANDS. A shrine takes nothing and makes nothing; what it does
	# is raise the town's belief and send prayer up, and a second person kneeling
	# beside the first does not send it up twice.
	"shrine": {
		"employs": 1, "lumber": 4, "stone": 8,
		"takes": {}, "makes": {},
		"wants": 1.0 / 30.0, "needs": "faith",
		"label": "Shrine", "tint": Color(0.8, 0.78, 0.7),
	},
}

## THE DROVE. Stock does not stand in a barn all day: it is let out in the
## morning, walked past the well to drink, put on pasture, and drawn back in at
## dusk. The whole of a barn's day is these four places in order, and it is
## worth having for exactly one reason — a village with forty beasts in it
## should LOOK like a village with forty beasts in it, twice a day, in a line.
const DROVE: Array[String] = ["out", "well", "pasture", "in"]
## How long each leg lasts, and how far pasture stands from the barn.
const LEG_SECONDS := 26.0
const PASTURE := 17.0
## How far out of line a beast walks. Nothing here is a formation: they string
## out and bunch up, which is what makes it read as animals rather than a parade.
const STRAGGLE := 3.2

## HOW MANY BEASTS STAND ABOUT AS REAL ANIMALS before the barn takes the rest
## into its books. Past this the surplus becomes a Herd — rows of numbers drawn
## as one MultiMesh, with only the nearest few ever built — which is why a barn
## can now hold whatever a village can catch. The pen's own eight are left as
## real animals because they are the ones villagers feed, ride and butcher by
## hand, and because a yard with nothing standing in it is not a yard.
const LOOSE_STOCK := 8
## ...and how many of the BOOK stand about in the yard, drawn. A dozen reads as
## a working farmyard; the other few hundred are inside. See Herd.shown.
const IN_THE_YARD := 12

## THE HARBOUR. How many mills must stand before a town will consider one — a
## dock is not the thing a hungry village needs, and asking for two mills is
## asking for a town that has already solved its grain.
const DOCK_WANTS_MILLS := 2
## What each boat costs on top of the dock, how many a harbour keeps, how long
## one stays out per shift worked, and how far off the jetty the grounds are.
const BOAT_LUMBER := 12
const BOATS_MOST := 3
const TRIP := 45.0
const GROUNDS_OUT := 28.0

## How long one turn of work takes, and how far a well's or a shrine's good
## reaches. A shift is long enough that a villager is visibly AT work rather
## than touching the building and leaving.
const SHIFT := 9.0
const REACH := 16.0


## WHAT IT TAKES TO PULL THIS DOWN BY FORCE, against a villager's hundred.
## A building is the thing that PROTECTS the villager, so it cannot be as easy
## to break as the villager is — a fireball that kills the family should not
## also flatten the house in the same instant, and a creature in a temper
## should have to work at it.
##
## Fire is charged as a fraction of this rather than as a flat number, so a
## stout building is stout against BLOWS and still burns to the ground in the
## same minute and a half as a hut. See Kindling.tick.
const MOST_HEALTH := 600.0

var village: Village
var trade := "well"
## ONE HERD PER SPECIES THIS BARN KEEPS. Village livestock beyond the loose few
## live here as numbers — see Herd, and `_take_in`.
var stock: Array[Herd] = []
## How much of it is left, and whether it is alight. See Kindling.
var health := MOST_HEALTH
var kindling := Kindling.new()
var _leg := 0
var _leg_left := 0.0
## A harbour's boats, and where they fish. Empty for every other trade.
var _fleet: Array[FishingBoat] = []
var _grounds := Vector3.INF

static func create(which: String, home: Village) -> Workshop:
	var w := Workshop.new()
	w.trade = which
	w.village = home
	return w


## WHAT TRADE A TOWN IS SHORT OF, or "" if it is content. Asked in the order the
## trades are written, so a village reaches for water before it reaches for a
## shrine — the right order for a place that has just doubled in size.
##
## This lives here rather than on Village because it is entirely a question
## ABOUT TRADES, and putting it here means adding a trade never means editing the
## village at all.
static func short_of(town: Village) -> String:
	if town.construction_site != null:
		return ""
	var have := {}
	for w in town.workshops:
		if is_instance_valid(w):
			have[w.trade] = int(have.get(w.trade, 0)) + 1
	var souls := town.population()
	for which: String in TRADES:
		var spec: Dictionary = TRADES[which]
		if int(have.get(which, 0)) >= wanted(which, souls):
			continue
		if not _makes_sense(town, String(spec["needs"])):
			continue
		if town.store.lumber < int(spec["lumber"]) \
				or town.store.stone < int(spec["stone"]):
			continue
		return which
	return ""


## The condition beyond mere numbers. A mill wants grain to grind, a barn wants
## beasts to keep, a shrine wants somebody who already believes.
static func _makes_sense(town: Village, needs: String) -> bool:
	match needs:
		"grain":
			return town.store.plant_food >= 6
		"stock":
			# A BARN IS FOR A TOWN THAT ALREADY HERDS, not one that might. It
			# wants beasts on the ground AND its pen full enough that the
			# animals are the problem — otherwise every town with one tamed
			# sheep raises a barn it will never fill.
			return town.tamed_count() >= Village.MAX_TAMED - 2
		"faith":
			return town.belief > 25.0
		"water":
			# TWO MILLS, AND THEN REAL WATER. The mills are checked first on
			# purpose: it is four comparisons, and almost every town in the
			# game fails it, so almost no town ever pays for the flood below.
			var mills := 0
			for w in town.workshops:
				if is_instance_valid(w) and (w as Workshop).trade == "mill":
					mills += 1
			if mills < DOCK_WANTS_MILLS:
				return false
			var world := town.get_tree().get_first_node_in_group("world_gen") as WorldGen
			return Waters.harbour_for(town, world) != Vector3.INF
	return true


## WHERE THIS TRADE WANTS TO STAND. Everything a village raises goes in the
## building ring round the totem — except a harbour, which goes where the water
## is, and would otherwise have been laid out in the town square like a shrine.
static func spot_for(which: String, town: Village, world: WorldGen) -> Vector3:
	if which == "dock":
		return Waters.harbour_for(town, world)
	return town.find_build_spot(world, Village.ROOM_ROUND_A_SHOP)


## A trade with room at it, counting who is already posted where.
static func with_room(town: Village, from: Vector3) -> Workshop:
	Util.prune(town.workshops)
	var taken := {}
	for v in town.my_villagers():
		var posted = v.workshop
		if posted != null and is_instance_valid(posted):
			taken[posted] = int(taken.get(posted, 0)) + 1
	var best: Workshop = null
	var closest := INF
	for w in town.workshops:
		if not is_instance_valid(w) or int(taken.get(w, 0)) >= w.employs():
			continue
		var gap := w.global_position.distance_to(from)
		if gap < closest:
			closest = gap
			best = w
	return best


## HOW MANY BEASTS THIS TOWN CAN HOLD — a pen and a prayer, or a pen and barns.
## Kept with the barn rather than on the village, which has been sitting on its
## public-method limit for some time now, and is a question about barns anyway.
## HOW MUCH STOCK THIS TOWN CAN KEEP AT ALL. See Village.HEAD_PER_KEEPER: the
## barn gives the room and the people give the hands, and it keeps whichever is
## the smaller. Building barns alone no longer grows a herd, which is what made
## the barn the strongest building in the game by a distance.
static func stalls(town: Village) -> int:
	var barns := 0
	for w in town.workshops:
		if is_instance_valid(w) and w.trade == "barn":
			barns += 1
	var built := Village.MAX_TAMED + barns * Village.BARN_STALLS
	var hands := Village.MAX_TAMED + town.population() * Village.HEAD_PER_KEEPER
	return mini(built, hands)


## IS THERE ANY MEAT ON THE HOOF AT ALL — loose in the yard or in a barn's book.
static func any_meat(town: Village) -> bool:
	if town.best_penned_meat() != null:
		return true
	return with_stock(town) != null


## A barn with something in it.
static func with_stock(town: Village) -> Workshop:
	for w in town.workshops:
		if is_instance_valid(w) and w.trade == "barn" and w.stock_held() > 0:
			return w
	return null


## SEND A BUTCHER SOMEWHERE. A loose beast is walked to and killed the old way;
## with the yard empty the butcher goes to the barn and takes from its books
## instead, which needs no animal to exist. Returns the state to enter.
static func butchery(who: Villager, quarry: Animal) -> int:
	if quarry != null:
		return Villager.State.GO_HUNT
	var barn := with_stock(who.village)
	if barn == null:
		return Villager.State.WANDER
	who.workshop = barn
	return Villager.State.GO_WORK


## EVERY POST IN THE TOWN, across all its trades. What the job-picker divides
## its crowd penalty by, so a village that has raised eight trades can actually
## staff them instead of deciding after the fourth villager that work is busy.
static func posts(town: Village) -> int:
	Util.prune(town.workshops)
	var total := 0
	for w in town.workshops:
		if is_instance_valid(w):
			total += w.employs()
	return total


## What a village of this size would like to have, in total, of one trade.
static func wanted(which: String, population: int) -> int:
	var spec: Dictionary = TRADES[which]
	return int(ceil(float(population) * float(spec["wants"])))


func _ready() -> void:
	kindling.temper = Kindling.TEMPER_TIMBER   # a timber shed full of work
	add_to_group("workshops")
	add_to_group(Affords.BURNABLE)
	var spec: Dictionary = TRADES[trade]
	set_meta("hover_name", String(spec["label"]))
	collision_layer = 4     # hoverable; villagers walk through it
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.2, 2.6, 3.2)
	col.shape = shape
	col.position = Vector3(0, 1.3, 0)
	add_child(col)
	var custom := ModelBank.instantiate(trade)
	if custom != null:
		add_child(custom)
	else:
		_build_stand_in(spec)


## A plain stand-in until art ships, distinct enough per trade to be told apart
## across a village square: a ring for the well, a tall house with a wheel for
## the mill, a long low shed for the barn, a pale stone for the shrine.
func _build_stand_in(spec: Dictionary) -> void:
	var tint: Color = spec["tint"]
	match trade:
		"well":
			add_child(Util.cylinder(1.1, 0.9, tint, Vector3(0, 0.45, 0)))
			add_child(Util.cylinder(0.85, 0.2, Color(0.2, 0.3, 0.4), Vector3(0, 0.95, 0)))
			for x: float in [-1.0, 1.0]:
				add_child(Util.box(Vector3(0.16, 1.8, 0.16), Color(0.5, 0.38, 0.24),
					Vector3(x, 1.4, 0)))
			add_child(Util.box(Vector3(2.4, 0.16, 1.0), Color(0.45, 0.33, 0.2),
				Vector3(0, 2.3, 0)))
		"mill":
			add_child(Util.box(Vector3(2.6, 3.2, 2.6), tint, Vector3(0, 1.6, 0)))
			add_child(Util.box(Vector3(2.9, 0.4, 2.9), Color(0.5, 0.4, 0.26),
				Vector3(0, 3.4, 0)))
			for turn in 4:
				var a := turn * PI / 2.0
				add_child(Util.box(Vector3(0.25, 2.2, 0.12),
					Color(0.62, 0.5, 0.34),
					Vector3(sin(a) * 1.1, 2.2 + cos(a) * 1.1, 1.45)))
		"barn":
			add_child(Util.box(Vector3(5.0, 2.2, 3.4), tint, Vector3(0, 1.1, 0)))
			add_child(Util.box(Vector3(5.4, 0.4, 3.8), Color(0.42, 0.3, 0.2),
				Vector3(0, 2.4, 0)))
			add_child(Util.box(Vector3(1.6, 1.6, 0.12), Color(0.3, 0.22, 0.14),
				Vector3(0, 0.8, 1.75)))
		"dock":
			# A JETTY: a plank walk on posts, running out over the water, with a
			# net rack and a lamp at the head of it. It is LONG rather than tall
			# on purpose — the one building in the town whose silhouette says
			# what it is from the hill, because it is the one building that is
			# not in the town.
			add_child(Util.box(Vector3(2.2, 0.28, 8.0), tint, Vector3(0, 0.6, 3.6)))
			# `pile` and not `post`: this class has a post() of its own, and a
			# loop variable by that name shadows it.
			for pile in 4:
				add_child(Util.box(Vector3(0.22, 1.6, 0.22),
					Color(0.36, 0.28, 0.2),
					Vector3(0.85, 0.0, 1.2 + float(pile) * 2.0)))
				add_child(Util.box(Vector3(0.22, 1.6, 0.22),
					Color(0.36, 0.28, 0.2),
					Vector3(-0.85, 0.0, 1.2 + float(pile) * 2.0)))
			# The net rack ashore, which is where the people actually stand.
			add_child(Util.box(Vector3(2.6, 0.16, 0.16),
				Color(0.5, 0.4, 0.26), Vector3(0, 1.9, -0.6)))
			for leg: float in [-1.2, 1.2]:
				add_child(Util.box(Vector3(0.16, 2.0, 0.16),
					Color(0.5, 0.4, 0.26), Vector3(leg, 0.95, -0.6)))
			add_child(Util.sphere(0.24, Color(1.0, 0.86, 0.5),
				Vector3(0, 1.9, 7.2), true))
		_:
			add_child(Util.box(Vector3(2.0, 0.5, 2.0), tint, Vector3(0, 0.25, 0)))
			add_child(Util.cylinder(0.5, 2.2, tint.lightened(0.1), Vector3(0, 1.6, 0)))
			add_child(Util.sphere(0.45, Color(0.95, 0.85, 0.5), Vector3(0, 2.9, 0), true))


## Where a worker stands. Just outside, so a crowd of them is not inside the
## walls of a building three metres across.
func post() -> Vector3:
	return global_position + Vector3(2.2, 0.0, 0.0)


func employs() -> int:
	return int(TRADES[trade]["employs"])


## ONE TURN OF WORK, done by a villager who has arrived and stayed.
##
## The shift clock lives on the VILLAGER, not here: two people at one mill are
## two shifts, not one, and a building holding the timer would have silently
## halved the output of every trade somebody doubled up on. This building has no
## clock of its own at all.
func work_shift() -> void:
	var spec: Dictionary = TRADES[trade]
	var store := village.store if village != null else null
	if store == null:
		return
	# A MILL EATS THE SEED CORN, and only a surplus is not seed corn. Having the
	# four grains the recipe asks for is not the same as being able to spare
	# them: a village down to its last meals put them through the mill and got
	# six back some seconds later, having been six short in the meantime, with
	# three of its people at the millstone rather than in the field.
	if trade == "mill" and not _town_has_spare():
		return
	var takes: Dictionary = spec["takes"]
	# Nothing is produced unless the whole input is there. A half-fed mill
	# simply idles, which is a truer thing for it to do than run on nothing.
	for what: String in takes:
		var have: int = store.plant_food if what == "plant" else store.meat_food
		if have < int(takes[what]):
			return
	for what: String in takes:
		store.take(FoodItem.FoodType.PLANT if what == "plant" else FoodItem.FoodType.MEAT,
			int(takes[what]))
	for what: String in spec["makes"]:
		store.add(FoodItem.FoodType.PLANT if what == "plant" else FoodItem.FoodType.MEAT,
			int(spec["makes"][what]))
	match trade:
		"well":
			_water_the_fields()
		"barn":
			# A SHIFT AT THE BARN IS BUTCHERY when the town is short. Taken from
			# the book rather than from an animal, so a barn with three hundred
			# head feeds a village without ever building one of them.
			if store.meat_food < 8:
				var got := take_meat()
				if got > 0:
					store.add(FoodItem.FoodType.MEAT, got)
		"shrine":
			if village != null:
				village.belief = minf(village.belief + 0.4, 100.0)
				GameState.add_prayer_power(1.2)
		"dock":
			# A SHIFT WORKED IS A BOAT OUT. The catch is already in the store by
			# the time this runs — `makes` did it — and this is only the part
			# you can see from the hill. See FishingBoat.
			_put_to_sea()


## Is the granary genuinely ahead — more than the meals its people are going to
## want? The same measure the job board scores food by, so "this town is fed"
## means one thing everywhere.
func _town_has_spare() -> bool:
	if village == null or not is_instance_valid(village):
		return false
	var heads := maxi(village.population(), 1)
	return float(village.store.total_food()) / float(heads) > Villager.FED_ENOUGH


## A well's whole point. Fields in reach are watered exactly as rain waters
## them, so there is one notion of a field being watered rather than two.
func _water_the_fields() -> void:
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(
				global_position) < REACH:
			farm.water(SHIFT * 2.0)


## WHERE THE STOCK SHOULD BE STANDING at this hour. The barn owns the routine,
## not the animals: they are only ever told where to go, which means a herd of
## forty costs one decision rather than forty.
func drove_spot(which: int) -> Vector3:
	var leg: String = DROVE[_leg % DROVE.size()]
	var scatter := Vector3(
		sin(float(which) * 2.399) * STRAGGLE, 0.0, cos(float(which) * 2.399) * STRAGGLE)
	match leg:
		"well":
			var well := _nearest_well()
			return (well if well != Vector3.INF else global_position) + scatter
		"pasture":
			var a := float(_leg) * 1.1
			return global_position + Vector3(cos(a), 0.0, sin(a)) * PASTURE + scatter
		"out":
			return post() + scatter
	return global_position + scatter * 0.4


## A barn drives its beasts past the well because that is where they drink, and
## because a village's animals crossing its square is the whole of what a
## working town looks like from the hill above it.
func _nearest_well() -> Vector3:
	if village == null:
		return Vector3.INF
	for w in village.workshops:
		if is_instance_valid(w) and w.trade == "well":
			return w.global_position
	return Vector3.INF


## Are they in for the night? Butchering and feeding want to know.
func stock_is_in() -> bool:
	return DROVE[_leg % DROVE.size()] == "in"


func _process(delta: float) -> void:
	_tick_fire(delta)
	if village == null or not is_instance_valid(village):
		return
	if Util.sim_stride(global_position) > 4:
		return
	if trade == "dock":
		_keep_the_fleet(delta)
		return
	if trade != "barn":
		return
	_leg_left -= delta
	if _leg_left > 0.0:
		return
	_leg_left = LEG_SECONDS
	# Night draws them in whatever leg they were on. A barn is a place animals
	# sleep, and stock still out at dusk is stock somebody has lost.
	_leg = DROVE.find("in") if GameState.is_night() else (_leg + 1) % DROVE.size()
	_take_in()
	# THE WHOLE MASS MOVES AS ONE. A herd's pasture is a single position, so
	# droving four hundred head costs exactly what droving four costs — which is
	# the entire reason the surplus is a herd and not four hundred animals.
	var spot := drove_spot(0)
	var out := 0 if stock_is_in() else IN_THE_YARD
	for h in stock:
		if is_instance_valid(h):
			# ONLY A FEW OF THEM ARE ACTUALLY OUT. The book goes on being the
			# book — they eat, breed, and are butchered out of it all the same —
			# but a barn keeping four hundred head does not put four hundred
			# animals in the street, and five barns doing it made a town you
			# could not see. None at all once they are in for the night.
			h.shown = out
			h.drive_toward(spot, 999.0)
	var n := 0
	for a in village.tamed_animals:
		var beast := a as Animal
		if is_instance_valid(beast) and not beast.has_rider():
			beast.drive_to(drove_spot(n))
			n += 1


## A HARBOUR BUYS ITS BOATS ONE AT A TIME, out of the town's spare timber, and
## only ever when the town has some to spare — a dock is already thirty timber
## and a village that put its last plank into a boat would be a village that
## could not roof anybody. On the barn's own clock, which is slow enough that a
## fleet takes a few minutes to appear and that is right: a harbour should fill
## up over a season.
func _keep_the_fleet(delta: float) -> void:
	Util.prune(_fleet)
	_leg_left -= delta
	if _leg_left > 0.0:
		return
	_leg_left = LEG_SECONDS
	if _fleet.size() >= mini(BOATS_MOST, employs()):
		return
	if village.store == null or not is_instance_valid(village.store):
		return
	if not village.store.try_spend_materials(BOAT_LUMBER, 0):
		return
	_launch()


## ONE MORE HULL, tied up a little along the jetty from the last.
func _launch() -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if _grounds == Vector3.INF:
		_grounds = Waters.off_shore(world, global_position, GROUNDS_OUT)
	var boat := FishingBoat.new()
	# Moored just off the jetty, strung along it rather than stacked on it.
	var along := TAU * float(_fleet.size()) / float(maxi(BOATS_MOST, 1))
	var tie := global_position + Vector3(cos(along), 0.0, sin(along)) * 4.0
	if world != null:
		tie.y = world.surface_at(tie.x, tie.z)
	boat.mooring = tie
	boat.grounds = _grounds if _grounds != Vector3.INF else tie
	get_parent().add_child(boat)
	boat.global_position = tie
	_fleet.append(boat)


## SEND THE FIRST BOAT THAT IS IN. Called once per shift worked, so three people
## at the dock put three boats out and one person puts out one.
func _put_to_sea() -> void:
	Util.prune(_fleet)
	for b in _fleet:
		var boat := b as FishingBoat
		if is_instance_valid(boat) and not boat.is_at_sea():
			boat.put_to_sea(TRIP)
			return


## TAKING THE SURPLUS IN. Everything past the loose few becomes numbers, sorted
## by species into whichever herd already keeps that kind. Ridden and pack beasts
## are left alone: a horse somebody is on is not inventory.
func _take_in() -> void:
	Util.prune(village.tamed_animals)
	Util.prune(stock)
	var loose := village.tamed_animals.duplicate()
	loose.reverse()          # newest in first, so the old familiar ones stay out
	for a in loose:
		if village.tamed_animals.size() <= LOOSE_STOCK:
			return
		var beast := a as Animal
		if not is_instance_valid(beast) or beast.has_rider():
			continue
		if beast.spec.get("ride", false) or beast.spec.get("guard", false):
			continue          # horses and dogs have work; they do not go in a book
		_herd_for(beast.species).absorb(beast)


## The herd of this kind, opened if the barn has never kept one before.
func _herd_for(kind: String) -> Herd:
	for h in stock:
		if is_instance_valid(h) and h.species == kind:
			return h
	var made := Herd.create(kind, 0, null)
	made.keeper = village
	made.position = Vector3(0, 0, PASTURE * 0.4)
	add_child(made)
	stock.append(made)
	return made


## EVERY HEAD THIS BARN HOLDS, promoted or not.
func stock_held() -> int:
	var n := 0
	for h in stock:
		if is_instance_valid(h):
			n += h.alive()
	return n


## MEAT, WITHOUT BUILDING THE ANIMAL. A butcher takes from the book: the biggest
## beast the barn keeps goes, and the store gets what it was worth.
func take_meat() -> int:
	var best: Herd = null
	var worth := 0
	for h in stock:
		if not is_instance_valid(h) or h.alive() <= 0:
			continue
		var w := int(Animal.SPECIES[h.species].get("meat", 0))
		if w > worth:
			worth = w
			best = h
	return best.slaughter() if best != null else 0


func hover_text() -> String:
	var spec: Dictionary = TRADES[trade]
	if trade == "barn":
		var loose: int = village.tamed_count() if village != null else 0
		return "Barn — %d head (%d in the yard), stock %s" % [
			loose + stock_held(), loose, "in" if stock_is_in() else "out"]
	return "%s — work for %d" % [String(spec["label"]), int(spec["employs"])]

## Fire ------------------------------------------------------------------------

## HEAT ON IT, from a fireball, a bolt, or the building next door. It catches
## only when it has had enough of it for what it is made of — see
## Kindling.warm, and Kindling's TEMPER_ table for why a granary takes longer
## than a hut.
func scorch(joules: float) -> void:
	kindling.warm(self, joules, 3.0)


## SET IT ALIGHT. Everything a village raises can burn now — see Kindling for
## why that had to change and what it costs a town.
func ignite() -> void:
	kindling.light(self, 3.0)


## Rain, a healing shower, or somebody with a bucket.
func extinguish() -> void:
	kindling.douse(self)


## Sudden harm — a fireball's core, a quake, a creature's boot.

## WHAT IT IS WORTH IN FULL, so a blow can be reckoned as a share of it. A
## METHOD and not the constant itself: Object.get() does not see constants, so
## anything asking `built.get("MOST_HEALTH")` gets null and quietly treats a
## granary as a hut. See Fireball._most_of.
func full_health() -> float:
	return MOST_HEALTH


func damage(amount: float) -> void:
	health -= amount
	# AND IT SHOWS. See RuinBar: a thing that can be hurt without looking
	# hurt is indistinguishable from a thing that cannot be hurt at all,
	# which is exactly what "the mill will not burn" sounds like from
	# the other side of the screen.
	RuinBar.over(self, health / MOST_HEALTH, 3.6, kindling.alight)
	if health <= 0.0:
		burn_down()


func _tick_fire(delta: float) -> void:
	# COOL OFF between blows: three fireballs in ten seconds is a fire,
	# three across an afternoon is three scorch marks. See Kindling.
	kindling.cool(delta)
	var harm := kindling.tick(self, delta, MOST_HEALTH)
	if harm > 0.0:
		damage(harm)


## GONE. The stock is loosed rather than deleted — a barn burning down is a
## barn's worth of animals in the street, which is the right consequence and a
## far better sight than a building quietly vanishing.
func burn_down() -> void:
	if village != null and is_instance_valid(village):
		village.workshops.erase(self)
	GameState.announce("The %s burns down." % String(TRADES[trade]["label"]).to_lower())
	queue_free()
