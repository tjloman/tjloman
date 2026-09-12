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
	"mill": {
		"employs": 3, "lumber": 8, "stone": 4,
		"takes": {"plant": 4}, "makes": {"plant": 6},
		"wants": 1.0 / 22.0, "needs": "grain",
		"label": "Mill", "tint": Color(0.74, 0.66, 0.48),
	},
	# STOCK. Keeps penned beasts fed and lets a village hold more of them, which
	# is the village end of the herd work — somewhere for driven cattle to go.
	"barn": {
		"employs": 3, "lumber": 10, "stone": 2,
		"takes": {"plant": 2}, "makes": {"meat": 3},
		"wants": 1.0 / 25.0, "needs": "stock",
		"label": "Barn", "tint": Color(0.55, 0.38, 0.26),
	},
	# A SECOND PLACE TO PRAY, so worship is not one queue at one totem.
	"shrine": {
		"employs": 2, "lumber": 4, "stone": 8,
		"takes": {}, "makes": {},
		"wants": 1.0 / 30.0, "needs": "faith",
		"label": "Shrine", "tint": Color(0.8, 0.78, 0.7),
	},
}

## How long one turn of work takes, and how far a well's or a shrine's good
## reaches. A shift is long enough that a villager is visibly AT work rather
## than touching the building and leaving.
const SHIFT := 9.0
const REACH := 16.0

var village: Village
var trade := "well"
var _shift_left := 0.0


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
static func short_of(village: Village) -> String:
	if village.construction_site != null:
		return ""
	var have := {}
	for w in village.workshops:
		if is_instance_valid(w):
			have[w.trade] = int(have.get(w.trade, 0)) + 1
	var souls := village.population()
	for which: String in TRADES:
		var spec: Dictionary = TRADES[which]
		if int(have.get(which, 0)) >= wanted(which, souls):
			continue
		if not _makes_sense(village, String(spec["needs"])):
			continue
		if village.store.lumber < int(spec["lumber"]) \
				or village.store.stone < int(spec["stone"]):
			continue
		return which
	return ""


## The condition beyond mere numbers. A mill wants grain to grind, a barn wants
## beasts to keep, a shrine wants somebody who already believes.
static func _makes_sense(village: Village, needs: String) -> bool:
	match needs:
		"grain":
			return village.store.plant_food >= 6
		"stock":
			return village.tamed_count() > 0
		"faith":
			return village.belief > 25.0
	return true


## A trade with room at it, counting who is already posted where.
static func with_room(village: Village, from: Vector3) -> Workshop:
	Util.prune(village.workshops)
	var taken := {}
	for v in village.my_villagers():
		var at: Workshop = v.workshop
		if at != null and is_instance_valid(at):
			taken[at] = int(taken.get(at, 0)) + 1
	var best: Workshop = null
	var closest := INF
	for w in village.workshops:
		if not is_instance_valid(w) or int(taken.get(w, 0)) >= w.employs():
			continue
		var gap := w.global_position.distance_to(from)
		if gap < closest:
			closest = gap
			best = w
	return best


## EVERY POST IN THE TOWN, across all its trades. What the job-picker divides
## its crowd penalty by, so a village that has raised eight trades can actually
## staff them instead of deciding after the fourth villager that work is busy.
static func posts(village: Village) -> int:
	Util.prune(village.workshops)
	var total := 0
	for w in village.workshops:
		if is_instance_valid(w):
			total += w.employs()
	return total


## What a village of this size would like to have, in total, of one trade.
static func wanted(which: String, population: int) -> int:
	var spec: Dictionary = TRADES[which]
	return int(ceil(float(population) * float(spec["wants"])))


func _ready() -> void:
	add_to_group("workshops")
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
	_shift_left = randf() * SHIFT


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


## ONE TURN OF WORK, done by a villager who has arrived and stayed. Returns a
## line to announce, or "" for the quiet trades — a well does not deserve a
## bulletin every nine seconds.
func work_shift() -> String:
	var spec: Dictionary = TRADES[trade]
	var store := village.store if village != null else null
	if store == null:
		return ""
	var takes: Dictionary = spec["takes"]
	# Nothing is produced unless the whole input is there. A half-fed mill
	# simply idles, which is a truer thing for it to do than run on nothing.
	for what: String in takes:
		var have: int = store.plant_food if what == "plant" else store.meat_food
		if have < int(takes[what]):
			return ""
	for what: String in takes:
		store.take(FoodItem.FoodType.PLANT if what == "plant" else FoodItem.FoodType.MEAT,
			int(takes[what]))
	for what: String in spec["makes"]:
		store.add(FoodItem.FoodType.PLANT if what == "plant" else FoodItem.FoodType.MEAT,
			int(spec["makes"][what]))
	match trade:
		"well":
			_water_the_fields()
		"shrine":
			if village != null:
				village.belief = minf(village.belief + 0.4, 100.0)
				GameState.add_prayer_power(1.2)
	return ""


## A well's whole point. Fields in reach are watered exactly as rain waters
## them, so there is one notion of a field being watered rather than two.
func _water_the_fields() -> void:
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(
				global_position) < REACH:
			farm.water(SHIFT * 2.0)


func hover_text() -> String:
	var spec: Dictionary = TRADES[trade]
	return "%s — work for %d" % [String(spec["label"]), int(spec["employs"])]
