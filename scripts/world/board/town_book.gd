class_name TownBook
extends RefCounted
## A TOWN, AS NUMBERS. What a village is while nobody is looking: no people,
## no houses on the ground, no paths walked — counts and stocks, stepped by
## TownRules a quarter-day at a time. Folded from a live town when it passes
## out of the loaded land, and unfolded back into one when the land comes back,
## with whatever happened in between written up as its alibi (`chronicle`).
##
## People are kept in three ages and as FRACTIONS. A fortieth of a person is not
## a person, but a town of nine losing a tenth of a child a step is a town that
## loses one child in ten steps, and rounding every step would lose all of them
## or none. They are only ever rounded at the door: unfolding, and the readout.

## The stages a town climbs and falls through — the moves the board allows.
enum Stage { CAMP, HAMLET, VILLAGE, TOWN, CITY }
const STAGE_NAMES: Array[String] = ["camp", "hamlet", "village", "town", "city"]
## How many lines of its own history a town keeps.
const CHRONICLE_LINES := 16
## What is written down when it folds, and read back when it unfolds.
const _KEPT: Array[String] = ["id", "name", "home", "converted", "belief", "diet", "no_plough",
	"children", "adults", "elders", "women", "food", "wood", "stone", "houses", "farms",
	"building", "tilling", "fish_stock", "game_stock", "berry_stock", "beast_stock", "wood_stock",
	"felled", "kept", "kept_meat", "fodder", "herd_meat", "fed",
	"morale", "hardiness", "stage", "stage_years", "ruined", "years", "steps",
	"leaning", "born", "starved", "taken", "aged_out", "lost_young", "left",
	"arrived", "chronicle", "leaving", "marks"]

var id := ""
var name := ""
var pos := Vector2.ZERO
var home := false
var converted := false
var belief := 0.0
## WHAT IT EATS (Village.Diet: vegan, omnivore, carnivore, cannibal), and
## whether it has fallen too far to farm (Village.agriculture_abandoned).
var diet := 1
var no_plough := false

var children := 0.0
var adults := 0.0
var elders := 0.0
var women := 0.5        # the share of them who are women

var food := 0.0         # grain, fish, meat and berries, in meals (FoodItem)
var wood := 0.0
var stone := 0.0

var houses: Array = []  # sizes (House.Size), the way Village.to_dict keeps them
var farms := 0
var building := 0.0     # effort put into the next house so far
var tilling := 0.0      # and into the next field

var fish_stock := 1.0   # each wild larder as a share of what the land holds
var game_stock := 1.0
var berry_stock := 1.0
var beast_stock := 1.0  # the man-eaters, as a share of what the land holds
var wood_stock := 1.0   # the trees standing, as a share of what the land grew: it only falls
var kept := 0.0         # head its barns keep (Workshop.stock_kinds)
var kept_meat := 0.0    # and a head's meat, on average over its kinds

var fed := 1.0          # food against need, smoothed: what births listen to
var morale := 60.0      # 0..100
var hardiness := 0.0    # 0..1: learned survival, earned by hard years
var stage := Stage.CAMP
var stage_years := 0.0  # how long the case for the next move has held
var ruined := false     # flattened by the hand: a vestige among the stones

var years := 0.0        # GameState.game_years it has been stepped to
var steps := 0          # how many steps ever: the dice are seeded by it
var leaning := ""       # the work most of its hands are at

## Running tallies, for the charts and the alibi.
var born := 0.0
var starved := 0.0
var taken := 0.0        # by beasts
var aged_out := 0.0
var lost_young := 0.0   # children who did not live to grow up, of any cause
var felled := 0.0       # trees cut down
var fodder := 0.0       # grain its stock ate
var herd_meat := 0.0    # and the meat its stock sent the store
var left := 0.0         # walked away to somewhere else
var arrived := 0.0
var chronicle: Array = []   # [[year, line], ...], newest last
## Who is on the road out, waiting to be a band (Chessboard takes them).
var leaving := 0.0
## What it has already said about itself, so a famine is written down once.
var marks := {}


func population() -> float:
	return children + adults + elders


func beds() -> int:
	var total := 0
	for size: int in houses:
		total += int(House.SPECS[size]["capacity"])
	return total


func stage_name() -> String:
	return STAGE_NAMES[stage]


## A LINE OF ITS OWN HISTORY, dated in game years.
func note(line: String) -> void:
	chronicle.append([snappedf(years, 0.1), line])
	if chronicle.size() > CHRONICLE_LINES:
		chronicle.pop_front()


func to_dict() -> Dictionary:
	var out := {}
	for key: String in _KEPT:
		out[key] = get(key)
	out["pos"] = [pos.x, pos.y]
	return out


static func from_dict(data: Dictionary) -> TownBook:
	var book := TownBook.new()
	for key: String in _KEPT:
		if data.has(key):
			book.set(key, data[key])
	var at: Array = data.get("pos", [0.0, 0.0])
	book.pos = Vector2(float(at[0]), float(at[1]))
	book.houses = (data.get("houses", []) as Array).duplicate()
	book.chronicle = (data.get("chronicle", []) as Array).duplicate(true)
	book.marks = (data.get("marks", {}) as Dictionary).duplicate()
	return book

