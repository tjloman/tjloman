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
	# eight beasts; a barn holds a herd, which is the difference between keeping
	# animals and keeping stock. Only ever raised by a town already herding to
	# the limit of its pen — see `_makes_sense`.
	#
	# ONE TO A TOWN, like the harbour and for a plainer reason: twelve villagers
	# were found keeping a hundred and sixty head, which is not a village with a
	# farm, it is a feedlot with twelve staff — and it crowded the town's own
	# growth out. A second barn doubled the room without doubling anything that
	# has to feed it. See `stalls`, where the hands and the ceiling are, and
	# `spawn_workshop_at`, which refuses the second one at the door.
	"barn": {
		"employs": 3, "lumber": 10, "stone": 2,
		"takes": {"plant": 2}, "makes": {"meat": 3},
		"wants": 1.0 / 25.0, "most": 1, "needs": "stock",
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
	# ONE TO A TOWN. `wants` is a share of the population everywhere else,
	# because everywhere else a second mill is simply another mill — but a town
	# has ONE waterfront, and two harbours on it would be two jetties fighting
	# over the same fifty metres of shore. `most` is the ceiling; see `wanted`.
	#
	# And the catch is split. A shift on shore is worth one fish — mending nets
	# and gutting what comes in — and the BOATS bring the rest, landing their
	# own hauls when they come home (FishingBoat.CATCH). A harbour with no boats
	# yet earns about what a barn does, which is a poor return on thirty timber,
	# and that is the point: the building is the permission, the fleet is the
	# catch. Two thirds of a fishing town's food floats on the water, where it
	# can be burnt, beached or carried off by a god.
	"dock": {
		"employs": 3, "lumber": 30, "stone": 6,
		"takes": {}, "makes": {"meat": 1},
		"wants": 1.0 / 20.0, "most": 1, "needs": "water",
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
## morning, walked down a street, past the well to drink, put on pasture, and
## drawn back in at dusk — and a village with forty beasts in it should LOOK
## like one, twice a day, in a line down its own main street.
##
## THE ROUTE ITSELF LIVES IN Drove, and it is plotted once each morning. What is
## left here is the barn's part: the clock, the yard, and the books. A leg costs
## this file one lookup and one order to each herd, whatever is in them.
##
## Drove's numbers are read where they are USED and never copied into a const
## here. A `const X := Drove.Y` has to be resolved while this file is compiling,
## which makes Workshop depend on Drove at COMPILE time in a graph that already
## runs Herd -> Workshop -> Drove -> Herd — and a cycle that Godot cannot settle
## does not fail politely. It fails as "Failed to compile depended scripts",
## fourteen times, with the game stopped on the logo screen and nothing in the
## error naming the const that did it. Once was enough.
## How far out of line a beast in the YARD walks — the loose few, who are real
## animals and are not in the column. The book's own column is laid out by
## Drove.form_up.
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
## HOW LONG A COMMITMENT TO RAISE A TRADE HOLDS THE PLACE, in seconds.
##
## `short_of` counted BUILT workshops, and `build_shop` has room for two — so
## two villagers could both be told the town wants a harbour, walk to two
## different spots, and raise two. A town has one waterfront and it had two
## jetties on it.
##
## Stamped rather than counted, so a builder who dies, is eaten or is thrown
## into a lake does not hold the place for ever. Long enough to cover the walk
## out and the eighteen seconds of hammering.
const RAISING_HOLDS := 90.0
## THE BARN'S LAMP — yellow when the herd is fed, a sullen ember when it is not.
## See `_show_the_yard`.
const LAMP_SIZE := 0.34
const LAMP_ENERGY := 2.2
const LAMP_FED := Color(1.0, 0.86, 0.28)
const LAMP_STARVED := Color(0.5, 0.31, 0.12)

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
## THE DAY'S ROUTE, one spot per leg, worked out at dawn and then only indexed.
## See Drove.plot — this is the whole of what "preprogrammed" means here.
var _route: Array[Vector3] = []
## Which day it was plotted for, so it is replotted once and not every leg.
var _plotted := -1
## A harbour's boats, and where they fish. Empty for every other trade.
var _fleet: Array[FishingBoat] = []
var _grounds := Vector3.INF
## The barn's lamp and the grain in its trough. Null for every other trade.
var _lamp: MeshInstance3D = null
var _feed: MeshInstance3D = null

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
		# Somebody is already out raising one of these. See RAISING_HOLDS.
		if being_raised(town, which):
			have[which] = int(have.get(which, 0)) + 1
		if int(have.get(which, 0)) >= wanted(which, souls):
			continue
		if not _makes_sense(town, String(spec["needs"])):
			continue
		if town.store.lumber < int(spec["lumber"]) \
				or town.store.stone < int(spec["stone"]):
			continue
		return which
	return ""


## IS SOMEBODY OUT RAISING ONE OF THESE RIGHT NOW? See RAISING_HOLDS — this is
## what stops two people being told the same town needs the same building.
static func being_raised(town: Village, which: String) -> bool:
	var when: float = town.raising.get(which, -RAISING_HOLDS * 2.0)
	return GameState.clock - when < RAISING_HOLDS


## I AM GOING TO RAISE ONE. Said by the builder when it sets off, so that the
## next villager to ask is told the town is already dealing with it.
static func claim_raising(town: Village, which: String) -> void:
	if which != "":
		town.raising[which] = GameState.clock


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


## MAY THIS TRADE STAND HERE AT ALL — the one door, for every way a building
## gets raised.
##
## THERE ARE TWO WAYS, and only one of them was ever guarded. A villager walks
## out and raises one through `Village.spawn_workshop_at`, which is where the
## dock rules were written. A village RESTORED from a save or a map file places
## its trades directly, by count, using the plain ring-round-the-totem finder —
## and so a dock that came back from a save was laid out in the town square like
## a shrine, on grass, with no harbour asked about at all.
##
## That is why destroying the bad one and letting the villagers rebuild it put
## it on the water: the rebuild went through the guarded door and the founding
## never did. Three fixes went onto that door while the other way in stood open.
##
## So the rules live here, and both callers ask. `world` may be null, in which
## case only the rules that do not need the ground are applied.
static func may_stand(which: String, town: Village, at: Vector3,
		world: WorldGen) -> bool:
	if town == null or not is_instance_valid(town) or not at.is_finite():
		return false
	# ONE TO A TOWN, for the trades that say so. `wanted` caps this by
	# population and `being_raised` stops two builders being sent, and neither
	# of them is looking when a save deals its buildings back out.
	var most := int(TRADES.get(which, {}).get("most", 0))
	if most > 0 and how_many(town, which) >= most:
		return false
	if which != "dock":
		return true
	# AND A JETTY HAS TO BE OVER WATER. Asked of the GROUND — see
	# Waters.can_carry_a_jetty, and the note on this door in
	# Village.spawn_workshop_at for why asking another function is not enough.
	if world == null:
		return false
	var harbour := Waters.harbour_for(town, world)
	if harbour == Vector3.INF or harbour.distance_to(at) > 2.0:
		return false
	return Waters.can_carry_a_jetty(at, Waters.bearing_for(town, world), world)


## HOW MANY OF THIS TRADE THE TOWN ALREADY HAS. One counter, so the ceiling and
## the save restore cannot come to different conclusions about what is standing.
static func how_many(town: Village, which: String) -> int:
	var n := 0
	for w in town.workshops:
		if is_instance_valid(w) and (w as Workshop).trade == which:
			n += 1
	return n


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
	# AND A FLAT CEILING OVER BOTH. The two numbers above are a ratio, and a
	# ratio has no top: a town that grows to two hundred souls would keep eight
	# hundred head by the same rule that gives twelve souls forty-eight. A
	# village is a village. Past this it is an industry, and the game does not
	# have one.
	return mini(mini(built, hands), Village.HEAD_AT_MOST)


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
	var want := int(ceil(float(population) * float(spec["wants"])))
	# A trade may name a hard ceiling. Only the harbour does: a town has one
	# waterfront, however many people are standing on it.
	if spec.has("most"):
		want = mini(want, int(spec["most"]))
	return want


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
	# A JETTY POINTS AT THE WATER. Everything else a village raises may stand
	# whichever way it likes; a harbour that lies along the beach is not a
	# harbour. The walkway runs out along this building's +Z, so the whole thing
	# is turned to put +Z on the bearing Waters measured. See Waters.bearing_for.
	if trade == "dock" and village != null and is_instance_valid(village):
		var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
		var out_to_sea := Waters.bearing_for(village, world)
		rotation.y = atan2(cos(out_to_sea), sin(out_to_sea)) - village.rotation.y
		return
	# AND IT SITS DOWN ON THE GROUND THAT IS DRAWN, not on the noise the placer
	# measured. See Footing — a barn is five metres across and was settled
	# against a sample four metres wide, on a surface that is a grid of flat
	# triangles rather than the smooth function it was sampled from.
	#
	# NOT THE DOCK, which is the one building in the village whose height is a
	# decision rather than a consequence: its deck stands at the waterline with
	# most of its footprint over open water, and the highest ground under that
	# footprint is the beach it is trying to get away from.
	Footing.settle(self, get_tree().get_first_node_in_group("world_gen") as WorldGen)


## THE YARD: A LAMP AND A TROUGH.
##
## The lamp sits on the ridge of the roof and it is the one thing in a village
## that says how the farm is doing from across the valley — it burns yellow when
## the herd is fed and guts down to a sullen ember when the trough has been
## empty for a few mornings. A barn is the building whose state you most want to
## read at a distance and had no way to, because a full book and an empty one
## are the same shed from outside.
##
## The trough stands where the stock actually come to eat — Drove.trough_at, the
## same answer the beasts are driven to, so the prop and the destination cannot
## drift apart.
func _build_the_yard() -> void:
	_lamp = Util.sphere(LAMP_SIZE, LAMP_FED, Vector3(0, 2.95, 0), true)
	add_child(_lamp)
	var glow := OmniLight3D.new()
	glow.light_color = LAMP_FED
	glow.light_energy = LAMP_ENERGY
	glow.omni_range = 7.0
	_lamp.add_child(glow)
	# THE TROUGH. A long low box with grain showing in it when there is any —
	# see `_show_the_yard`, which is the other half of the lamp.
	var at := Drove.trough_at(Vector3.ZERO)
	add_child(Util.box(Vector3(3.0, 0.42, 0.7), Color(0.44, 0.33, 0.21),
		at + Vector3(0, 0.21, 0)))
	_feed = Util.box(Vector3(2.7, 0.16, 0.48), Color(0.86, 0.72, 0.32),
		at + Vector3(0, 0.4, 0))
	add_child(_feed)


## WHAT THE LAMP AND THE TROUGH ARE SAYING. Called once a leg — six times a day,
## not sixty times a second — because it reports a number that only ever changes
## once a season.
func _show_the_yard() -> void:
	if _lamp == null or not is_instance_valid(_lamp):
		return
	var worst := 0.0
	for h in stock:
		if is_instance_valid(h):
			worst = maxf(worst, (h as Herd).hunger)
	var full := clampf(1.0 - worst / Herd.STARVES_ABOVE, 0.0, 1.0)
	var lit := LAMP_FED.lerp(LAMP_STARVED, 1.0 - full)
	var skin := _lamp.get_active_material(0) as StandardMaterial3D
	if skin != null:
		skin.albedo_color = lit
		skin.emission = lit
		skin.emission_energy_multiplier = lerpf(0.35, 1.6, full)
	var glow := _lamp.get_child(0) as OmniLight3D
	if glow != null:
		glow.light_color = lit
		glow.light_energy = LAMP_ENERGY * lerpf(0.25, 1.0, full)
	if _feed != null and is_instance_valid(_feed):
		# The GRAIN in it, not the trough: an empty trough is a trough with
		# nothing in it, which is a thing a player can see across a yard.
		_feed.visible = full > 0.15
		_feed.scale = Vector3(1.0, maxf(full, 0.08), 1.0)


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
			_build_the_yard()
		"dock":
			# A JETTY: a plank walk on posts, running out over the water, with a
			# net rack and a lamp at the head of it. It is LONG rather than tall
			# on purpose — the one building in the town whose silhouette says
			# what it is from the hill, because it is the one building that is
			# not in the town.
			# ONE SET OF DIMENSIONS, in Waters, where the finder checks them.
			# A deck drawn longer than the span that was verified is a deck
			# whose far end is over grass, and nothing would say so.
			var deck: float = Waters.JETTY_TO - Waters.JETTY_FROM
			add_child(Util.box(Vector3(2.2, 0.28, deck), tint,
				Vector3(0, 0.6, Waters.JETTY_FROM + deck * 0.5)))
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
	# A DOCK'S POST IS ASHORE. Two metres to the side is two metres into the
	# lake for a building that stands at the waterline, and the net rack — the
	# one part of a harbour that is on land at all — is behind the root.
	if trade == "dock":
		return global_position - global_transform.basis.z.normalized() * 2.0
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
			# A SHIFT ON SHORE IS WORTH ONE FISH, and sends a boat out. THE BOAT
			# BANKS ITS OWN CATCH when it comes home (FishingBoat.CATCH), which
			# is the only way the arithmetic works: this runs once per WORKER,
			# and a fleet that landed its haul three times because three people
			# were standing on the jetty was a harbour earning triple.
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
	var scatter := Vector3(
		sin(float(which) * 2.399) * STRAGGLE, 0.0, cos(float(which) * 2.399) * STRAGGLE)
	if _route.is_empty():
		return global_position + scatter * 0.4
	return _route[_leg % _route.size()] + scatter


## Are they in for the night? Butchering and feeding want to know.
func stock_is_in() -> bool:
	return Drove.DAY[_leg % Drove.DAY.size()] == "in"


## THE MORNING. Plotted once a day, and everything the rest of the day does is
## a lookup into what this settled. See Drove.
func _plot_the_day() -> void:
	var today := int(GameState.clock / GameState.DAY_SECONDS)
	if today == _plotted:
		return
	_plotted = today
	_route = Drove.plot(village, global_position, _nearest_well(), today)
	_fill_the_trough()
	_send_to_the_store()


## FILL THE TROUGH, out of the town's own grain. This is the barn's daily cost
## and it is the thing that was missing: stock that ate nothing could grow to
## any size the stalls allowed while the people beside them starved. A herd is
## fed or it is hungry, and a hungry herd stops calving. See Herd.hunger.
func _fill_the_trough() -> void:
	if village.store == null or not is_instance_valid(village.store):
		return
	var mouths := stock_held()
	if mouths <= 0:
		return
	var asks := maxi(int(float(mouths) * Drove.FEED_PER_HEAD), 1)
	var got := village.store.take(FoodItem.FoodType.PLANT, asks)
	if got <= 0:
		return
	# WHAT THEY ACTUALLY GOT, not what was asked for. Half a trough is half a
	# feed, so a town running out of grain watches its herd get hungry over
	# several mornings rather than being fine and then suddenly starving.
	var share := Drove.A_GOOD_FEED * float(got) / float(asks)
	for h in stock:
		if is_instance_valid(h):
			h.fed(share)


## AND THE DAY'S YIELD GOES TO THE STOREHOUSE. A share of the book, every
## morning, which is what keeping stock is FOR — the one thing a barn does that
## a pen full of loose animals does not.
func _send_to_the_store() -> void:
	if village.store == null or not is_instance_valid(village.store):
		return
	var meat := 0
	for h in stock:
		var herd := h as Herd
		if not is_instance_valid(herd):
			continue
		# NOT WHILE THEY ARE HUNGRY. A farm that went on sending beasts to the
		# store out of a herd it could not feed would empty itself, and the
		# player would never see why.
		if herd.hunger >= Herd.STARVES_ABOVE:
			continue
		for i in int(float(herd.alive()) * Drove.TO_THE_STORE):
			meat += herd.slaughter() + Drove.DRESSED_OUT
	if meat > 0:
		village.store.add(FoodItem.FoodType.MEAT, meat)


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


func _process(delta: float) -> void:
	Ledger.open(&"Workshop")
	_tick_fire(delta)
	if village == null or not is_instance_valid(village):
		return
	# THE FARM'S DAY RUNS WHEREVER THE PLAYER IS STANDING, and the parade does
	# not. Everything below the stride gate is the drove — the legs, the column,
	# who is out in the street — and none of that matters in a town nobody can
	# see. The trough is not that: a herd gets hungrier on its own clock
	# wherever it is, so a barn that only fed its stock when the camera was
	# within a couple of hundred metres would starve every herd in every village
	# the player has ever walked away from. It costs a compare a frame; the work
	# behind it happens once a day.
	if trade == "barn":
		_plot_the_day()
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
	_leg_left = Drove.LEG_SECONDS
	# Night draws them in whatever leg they were on. A barn is a place animals
	# sleep, and stock still out at dusk is stock somebody has lost.
	_leg = Drove.DAY.find("in") if GameState.is_night() \
		else (_leg + 1) % Drove.DAY.size()
	_take_in()
	_show_the_yard()
	# THE WHOLE MASS MOVES AS ONE, ON ONE ORDER. A herd's destination is a
	# single position, so droving four hundred head costs exactly what droving
	# four costs — which is the entire reason the surplus is a herd and not four
	# hundred animals. The column is laid out here too, once, and then nothing
	# in it decides anything until the next leg.
	var spot := drove_spot(0)
	var out := 0 if stock_is_in() else IN_THE_YARD
	for h in stock:
		var herd := h as Herd
		if not is_instance_valid(herd):
			continue
		# ONLY A FEW OF THEM ARE ACTUALLY OUT. The book goes on being the book —
		# they eat, breed, and are butchered out of it all the same — but a barn
		# keeping four hundred head does not put four hundred animals in the
		# street, and five barns doing it made a town you could not see. None at
		# all once they are in for the night. `shown` is now also what the herd
		# SIMULATES, so this is the number that makes a big book cheap rather
		# than merely quiet. See Herd.shown and Herd._simulated.
		herd.shown = out
		herd.drive_toward(spot, 999.0)
		herd.form_up(out, spot)
	# AND THE YARD'S OWN FEW. A share of them never leave it: heads down at the
	# trough from dawn to dusk, which is what most of a farm's animals are
	# actually doing whenever you look at one.
	var n := 0
	var eating := int(float(village.tamed_animals.size()) * Drove.AT_THE_TROUGH)
	var trough := Drove.trough_at(global_position)
	for a in village.tamed_animals:
		var beast := a as Animal
		if is_instance_valid(beast) and not beast.has_rider():
			beast.drive_to(trough + Vector3(float(n) * 0.9 - 1.2, 0.0, 0.0)
				if n < eating else drove_spot(n))
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
	_leg_left = Drove.LEG_SECONDS
	if _fleet.size() >= mini(BOATS_MOST, employs()):
		return
	if village.store == null or not is_instance_valid(village.store):
		return
	# THE MOORING IS FOUND BEFORE THE TIMBER IS SPENT. A boat with nowhere to
	# tie up is not a boat, and a village that paid twelve timber for one it
	# never got would go on paying every leg for ever.
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	var along := (float(_fleet.size()) - float(BOATS_MOST - 1) * 0.5) * 2.4
	var tie := _tie_up(world, along)
	if tie == Vector3.INF:
		return
	if not village.store.try_spend_materials(BOAT_LUMBER, 0):
		return
	_launch(world, tie)


## ONE MORE HULL, tied up a little along the jetty from the last.
func _launch(world: WorldGen, tie: Vector3) -> void:
	if _grounds == Vector3.INF:
		# From the END of the jetty, not from the dock's root — the root stands
		# on land, and open water measured from a spot on land is measured
		# through the beach.
		var deck_end := global_position \
			+ global_transform.basis.z.normalized() * Waters.JETTY_TO
		_grounds = Waters.off_shore(world, deck_end, GROUNDS_OUT)
	var boat := FishingBoat.new()
	boat.mooring = tie
	# ITS OWN WATER. The harbour works the fishing out once — that part is
	# right, it is the same bay for everybody — but handing every hull the same
	# spot put the whole fleet inside one another out there. See Waters.a_berth.
	boat.grounds = Waters.a_berth(world, _grounds, _fleet.size()) \
		if _grounds != Vector3.INF else tie
	boat.home_store = village.store if village != null else null
	get_parent().add_child(boat)
	boat.global_position = tie
	_fleet.append(boat)


## WHERE A BOAT IS TIED UP — on the WATER, off the end of the jetty, and not on
## the beach beside it. The mooring used to be a ring round the dock's own
## position, which is a spot chosen for being DRY; half the fleet was moored in
## somebody's field.
## PLUS Z, NOT MINUS. `_ready` turns the building so its +Z runs out to sea, and
## this read -Z — so every mooring was probed INLAND, found no water, fell
## through to the fallback and put the boat on the lawn behind the jetty. That
## is the whole of why no boat in the game was ever on water.
##
## And there is no fallback any more. A mooring that cannot be found is a boat
## that should not be launched; putting it "somewhere" is how a bug becomes a
## feature nobody can see the edge of. INF, and `_launch` refuses.
func _tie_up(world: WorldGen, along: float) -> Vector3:
	if world == null:
		return Vector3.INF
	var out_to_sea := global_transform.basis.z.normalized()
	var beam := Vector3(out_to_sea.z, 0.0, -out_to_sea.x)
	# From the end of the deck outward — a boat tied up alongside the planks,
	# not under them.
	for reach: float in [Waters.JETTY_TO + 1.5, Waters.JETTY_TO + 4.0,
			Waters.JETTY_TO + 7.0, Waters.JETTY_TO + 11.0]:
		var tie := global_position + out_to_sea * reach + beam * along
		if world.is_underwater(tie.x, tie.z):
			tie.y = world.water_level_at(tie.x, tie.z)
			return tie
	return Vector3.INF


## HOW MANY OF THIS HARBOUR'S BOATS ARE ACTUALLY ON THE WATER. Not moored, not
## beached, not in a god's hand, not cinders. This is the town's fishing fleet
## as far as the granary is concerned.
func boats_at_sea() -> int:
	Util.prune(_fleet)
	var out := 0
	for b in _fleet:
		var boat := b as FishingBoat
		if is_instance_valid(boat) and boat.is_fishing():
			out += 1
	return out


## SEND THE FIRST BOAT THAT IS IN. Called once per shift worked, so three people
## at the dock put three boats out and one person puts out one.
func _put_to_sea() -> void:
	Util.prune(_fleet)
	for b in _fleet:
		var boat := b as FishingBoat
		# A boat that is beached, burning or in somebody's hand refuses the
		# order itself — see FishingBoat.put_to_sea. All this has to find is one
		# that is not already out.
		if is_instance_valid(boat) and boat.is_fishing() and not boat.is_out():
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
	made.position = Vector3(0, 0, Drove.PASTURE_OUT * 0.4)
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
	var harm := kindling.smoulder(self, delta, MOST_HEALTH)
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
