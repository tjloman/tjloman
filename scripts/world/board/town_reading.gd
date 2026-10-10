class_name TownReading
extends RefCounted
## WHAT HOLDING A TOTEM TELLS YOU — a town, read: what it is and what it lives
## by, its people by age and sex, what each of them is doing, and its ALIBI —
## what happened while it was out of sight, in its own words (the history the
## chessboard keeps for it: TownBook.chronicle), and the tallies of those years.
##
## Laid out for the stone panel the nest wall already opens (HUD._fill_stone):
## blocks of two-column rows, rebuilt each time it is read.

## The ages a town's people are counted in.
const AGES: Array = [[0.0, 16.0, "children, 0–15"], [16.0, 30.0, "16–29"],
	[30.0, 45.0, "30–44"], [45.0, 60.0, "45–59"], [60.0, 999.0, "60 and over"]]
## Words for the work a villager can be at (Villager.current_job).
const WORK := {
	"farm": "in the fields", "fish": "fishing", "hunt": "hunting",
	"chop": "felling timber", "quarry": "quarrying", "build": "building",
	"build_farm": "breaking a field", "build_shop": "raising a workshop",
	"build_edubba": "raising the school", "build_nest": "raising the nest",
	"work": "at a trade", "feed": "feeding the beasts", "preach": "preaching",
	"circle": "dancing at the fire", "expedition": "on an expedition",
	"butcher": "butchering", "skin": "skinning", "beat": "fighting a fire",
	"mourn": "mourning", "tame": "taming", "plant": "hauling grain",
	"meat": "hauling meat", "lumber": "hauling timber", "stone": "hauling stone",
}
const STAGE_WORDS: Array[String] = ["a camp", "a hamlet", "a village", "a town", "a city"]
## The four diets in the god's order, 1 to 4 (Village.Diet), and what each eats.
const DIET_CHOICES: Array[String] = ["1 Vegan", "2 Omnivore", "3 Carnivore", "4 Cannibal"]
const DIET_EATS: Array[String] = ["grain and berries — no flesh", "whatever the land gives",
	"meat alone", "meat, and their own dead"]


static func of(town_given: Variant) -> Dictionary:
	if not is_instance_valid(town_given):
		return {}
	var town: Village = town_given
	var folk := town.my_villagers()
	return {"title": town.village_name, "blocks": [
		{"head": "THE TOWN", "rows": _town(town, folk)},
		{"head": "ITS PEOPLE", "rows": _people(folk)},
		{"head": "WHAT THEY ARE DOING", "rows": _doing(folk)},
		{"head": "WHAT THEY EAT", "rows": _eats(town)},
		{"head": "WHILE YOU WERE AWAY", "rows": _alibi(town.board)},
		{"head": "ITS YEARS OUT OF SIGHT", "rows": _tallies(town.board)},
	], "choice": _diet_choice(town)}


## WHAT THEY LIVE ON: their diet, what it lets them eat, and what is in the
## store of each.
static func _eats(town: Village) -> Array:
	var rows := [["Diet", "%d — %s" % [int(town.diet) + 1, town.diet_name()]]]
	rows.append(["Eats", String(DIET_EATS[int(town.diet)])])
	if is_instance_valid(town.store):
		rows.append(["In store", "%d grain, %d meat" % [town.store.plant_food, town.store.meat_food]])
	if town.agriculture_abandoned():
		rows.append(["The plough", "given up: fallen too far to farm"])
	return rows


## THE GOD'S SAY IN IT: four choices, the one they keep marked, and whether they
## listen at all — home always, a town that believes in you, and nobody else.
static func _diet_choice(town: Village) -> Dictionary:
	var listens := town.is_player_home or town.converted
	return {"head": "THEIR DIET — YOURS TO SAY", "options": DIET_CHOICES, "chosen": int(town.diet),
		"enabled": listens, "pick": func(i: int): town.set_diet(i as Village.Diet),
		"note": "" if listens else "They do not listen to you yet: their faith is %d of %d." % [
			roundi(town.belief), roundi(Village.CONVERT_BELIEF)]}


static func _town(town: Village, folk: Array) -> Array:
	var souls := folk.size()
	var stage := TownFold._stage_for(float(souls))
	var rows := [["Size", "%s of %d souls" % [STAGE_WORDS[stage], souls]]]
	if town.converted:
		rows.append(["Faith", "believes in you (%d)" % roundi(town.belief)])
	else:
		rows.append(["Faith", "believes in nothing yet (%d of %d)"
			% [roundi(town.belief), roundi(Village.CONVERT_BELIEF)]])
	var beds := town.housing_capacity()
	var rough := town.homeless_count()
	rows.append(["Roofs", "%d houses, %d beds%s" % [town.houses.size(), beds,
		(", %d sleep in the open" % rough) if rough > 0 else ""]])
	var need := 0.0
	for one: Villager in folk:
		need += TownRules.EAT_ADULT if one.is_adult() else TownRules.EAT_CHILD
	var meals := town.store.total_food() if is_instance_valid(town.store) else 0
	var lasts := "" if need <= 0.0 else " (about %.1f years)" % (meals / need)
	rows.append(["In store", "%d meals%s, %d timber, %d stone" % [meals, lasts,
		town.store.lumber if is_instance_valid(town.store) else 0,
		town.store.stone if is_instance_valid(town.store) else 0]])
	var book: Dictionary = town.board
	if not book.is_empty():
		rows.append(["Hardened", "%d%% by hard years" % roundi(float(book.get("hardiness", 0.0)) * 100.0)])
	return rows


static func _people(folk: Array) -> Array:
	var rows := []
	var women := 0
	for band: Array in AGES:
		var w := 0
		var m := 0
		for one: Villager in folk:
			if one.age >= float(band[0]) and one.age < float(band[1]):
				if one.is_female:
					w += 1
				else:
					m += 1
		women += w
		rows.append([String(band[2]), "%d — %d women, %d men" % [w + m, w, m]])
	rows.append(["All", "%d — %d women, %d men" % [folk.size(), women, folk.size() - women]])
	return rows


static func _doing(folk: Array) -> Array:
	var counts := {}
	for one: Villager in folk:
		var what := _what(one)
		counts[what] = int(counts.get(what, 0)) + 1
	var names := counts.keys()
	names.sort_custom(func(a, b): return counts[a] > counts[b])
	var rows := []
	for what: String in names:
		rows.append([what, str(counts[what])])
	return rows


static func _what(one: Villager) -> String:
	var job := one.current_job()
	if job != "":
		return String(WORK.get(job, job))
	if not one.is_adult():
		return "children at play or school"
	match one.state:
		Villager.State.SLEEPING, Villager.State.GO_SLEEP:
			return "asleep"
		Villager.State.EATING, Villager.State.GO_EAT:
			return "eating"
		Villager.State.WORSHIPPING:
			return "at prayer"
		Villager.State.FLEE, Villager.State.HIDE:
			return "afraid"
	return "at leisure"


## THE ALIBI: the town's own history from the board, newest first, dated by how
## long ago it was.
static func _alibi(book: Dictionary) -> Array:
	var lines: Array = book.get("chronicle", [])
	if lines.is_empty():
		return [["—", "It has not been out of your sight."]]
	var rows := []
	for i in range(lines.size() - 1, -1, -1):
		var entry: Array = lines[i]
		var ago := maxf(GameState.game_years - float(entry[0]), 0.0)
		rows.append(["%d years ago" % roundi(ago) if ago >= 1.0 else "lately", String(entry[1])])
	return rows


static func _tallies(book: Dictionary) -> Array:
	if book.is_empty():
		return [["—", "None yet."]]
	return [
		["Born", str(roundi(float(book.get("born", 0.0))))],
		["Died of their years", str(roundi(float(book.get("aged_out", 0.0))))],
		["Starved", str(roundi(float(book.get("starved", 0.0))))],
		["Taken by beasts", str(roundi(float(book.get("taken", 0.0))))],
		["Children lost", str(roundi(float(book.get("lost_young", 0.0))))],
		["Left for elsewhere", str(roundi(float(book.get("left", 0.0))))],
	]
