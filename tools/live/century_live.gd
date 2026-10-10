extends SceneTree
## THE CENTURY: the chessboard's own rules (TownRules), run over hundreds of
## made-up towns for two centuries of game time, headless and without a world:
##
##     godot --headless --path . --script tools/live/century_live.gd [-- out.csv]
##
## Seven kinds of land, forty towns each, every number jittered: open plains,
## a fishing cove, forest, wolf country, desert, tundra — and a ruin, flattened
## to a handful of survivors. Each is stepped exactly as a town out of sight is
## stepped in the game, under the same weather, and then judged on the three
## things the board must never do:
##
##   1. DIE OUT: no town ever falls below the vestige, and none but the truly
##      barren sits at the floor for its last half-century;
##   2. BALLOON: no town ever holds more than its beds and the few it crowds in,
##      or more than MOST_SOULS;
##   3. CRASH AND CRASH AGAIN: past the first thirty years, no town loses a
##      third of itself inside a decade more than once, and every town's last
##      sixty years hold steady (variation under a fifth);
##
## and on the floor itself, leaned on by a town on land that feeds nobody; and
## on what it must be able to do: plains towns grow into towns, fishing
## towns fish, wolf country loses its young and lives on, and ruins hang on and
## some climb back. A CSV of every town's every year goes to the path given, for
## tools/board_charts.py. Exits non-zero on failure. Names no class of the
## game's (see look.gd).

const TOWNS_EACH := 40
const YEARS := 180.0
const SETTLE := 30.0
## `room` is ground a house or a field could stand on within a full-grown
## town's reach (52 m: about 130 samples where all of it is good ground).
const KINDS := {
	"plains": {"fields": 250.0, "room": 130.0, "bushes": 10.0, "wood": 15.0, "game": 120.0,
		"predators": 0.5, "biome": "grassland"},
	"fishing": {"water": 150.0, "shore": 30.0, "fields": 10.0, "room": 55.0, "bushes": 5.0,
		"wood": 8.0, "game": 30.0, "predators": 0.3, "biome": "grassland"},
	"forest": {"fields": 80.0, "room": 110.0, "bushes": 14.0, "wood": 40.0, "game": 160.0,
		"predators": 3.0, "biome": "forest"},
	"wolves": {"fields": 20.0, "room": 80.0, "bushes": 4.0, "wood": 20.0, "game": 60.0,
		"predators": 12.0, "biome": "forest"},
	"desert": {"fields": 5.0, "room": 120.0, "bushes": 0.0, "wood": 2.0, "game": 25.0,
		"predators": 1.5, "biome": "desert"},
	"tundra": {"fields": 10.0, "room": 120.0, "bushes": 0.0, "wood": 6.0, "game": 250.0,
		"predators": 8.0, "biome": "tundra"},
	"cramped": {"fields": 250.0, "room": 24.0, "bushes": 10.0, "wood": 15.0, "game": 120.0,
		"predators": 0.5, "biome": "grassland"},
	"ruin": {},
}
## Where a town may honestly do no better than hang on at the floor: land too
## poor, and ruins — a vestige waiting to be finished off is what a ruin IS,
## and only some of them learn to live again (checked below).
const BARREN := ["desert", "ruin"]

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else ""
	var rules: Script = load("res://scripts/world/board/town_rules.gd")
	var land_script: Script = load("res://scripts/world/board/town_land.gd")
	var book_script: Script = load("res://scripts/world/board/town_book.gd")
	var weather: Script = load("res://scripts/world/board/weather.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var dt: float = rules.step_years()
	var csv := PackedStringArray(["kind,town,year,children,adults,elders,food,beds,farms,stage,"
		+ "fed,morale,hardiness,leaning,born,starved,taken,aged_out,lost_young,left,ruined"])
	var by_kind := {}
	var over_ever := {}
	var overbuilt := {}
	var was_used := {}
	var t0 := Time.get_ticks_msec()
	var stepped := 0
	for kind: String in KINDS:
		by_kind[kind] = []
		for n in TOWNS_EACH:
			# A ruin can be anywhere: on any land but its own.
			var lands: Array = KINDS.keys().filter(func(k): return k != "ruin" and k != "cramped")
			var on: String = kind if kind != "ruin" else lands[n % lands.size()]
			var spec: Dictionary = (KINDS[on] as Dictionary).duplicate()
			for key: String in spec:
				if spec[key] is float:
					spec[key] = float(spec[key]) * rng.randf_range(0.6, 1.4)
			var land = land_script.made(spec)
			var book = book_script.new()
			book.id = "%s-%d" % [kind, n]
			book.pos = Vector2(rng.randf_range(-20000, 20000), rng.randf_range(-20000, 20000))
			if kind == "ruin":
				book.adults = 3.0 + rng.randi_range(0, 3)
				book.children = rng.randi_range(0, 2)
				book.ruined = true
				book.morale = 5.0
			else:
				var founders := rng.randf_range(20.0, 45.0)
				book.children = founders * 0.3
				book.adults = founders * 0.6
				book.elders = founders * 0.1
				book.food = 30.0
				book.farms = mini(2, int(land.fields / rules.SAMPLES_PER_FIELD))
				while book.beds() < founders * 0.8:
					book.houses.append(1)      # House.Size.HOUSE
			var trace := []
			var next_year := 0.0
			while book.years < YEARS:
				var day: float = book.years / 1.8
				rules.step(book, land, weather.rain(77, book.pos, day, land.biome), dt)
				stepped += 1
				if book.years >= next_year:
					next_year += 1.0
					trace.append(book.population())
					csv.append("%s,%s,%.1f,%.2f,%.2f,%.2f,%.1f,%d,%d,%d,%.3f,%.1f,%.3f,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d" % [
						kind, book.id, book.years, book.children, book.adults, book.elders,
						book.food, book.beds(), book.farms, book.stage, book.fed, book.morale,
						book.hardiness, book.leaning, book.born, book.starved, book.taken,
						book.aged_out, book.lost_young, book.left, int(book.ruined)])
					if book.population() > room_of(rules, book) * 1.1 + 2.0:
						over_ever[book.id] = true
					# Built PAST its room: more ground used than there is, and more
					# than a year ago — a town founded cramped is not the board's doing.
					var here = land.near(rules.build_reach(book.population()))
					var used: float = rules.room_used(book)
					if used > here.room + 0.01 and used > float(was_used.get(book.id, INF)):
						overbuilt[book.id] = true
					was_used[book.id] = used
			(by_kind[kind] as Array).append({"book": book, "trace": trace, "land": land})
	var ms := Time.get_ticks_msec() - t0
	print("THE CENTURY: %d towns, %.0f game years each, %d steps in %d ms (%.0f us a step)"
		% [TOWNS_EACH * KINDS.size(), YEARS, stepped, ms, ms * 1000.0 / maxf(stepped, 1)])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string("\n".join(csv))
		f.close()

	# Per kind: where they ended, and how they got there.
	var floor_at: float = rules.VESTIGE
	var settle_at := int(SETTLE)
	for kind: String in KINDS:
		var towns: Array = by_kind[kind]
		var ends := []
		var below := 0
		var stuck := 0
		var over := 0
		var crashes := 0
		var shaky := 0
		var stages := [0, 0, 0, 0, 0]
		var lost_share := 0.0
		for t: Dictionary in towns:
			var book = t["book"]
			var trace: Array = t["trace"]
			ends.append(book.population())
			stages[book.stage] += 1
			lost_share += book.lost_young / maxf(book.born, 1.0)
			var start: float = trace[0]
			for p: float in trace:
				if p < minf(floor_at, start) - 0.01:
					below += 1
					break
			var tail: Array = trace.slice(trace.size() - 50)
			if tail.all(func(p): return p <= floor_at + 1.0):
				stuck += 1
			if over_ever.has(book.id):
				over += 1
			var drops := 0
			var y := settle_at
			while y + 10 < trace.size():
				if float(trace[y + 10]) < float(trace[y]) * 0.67 and float(trace[y]) > 10.0:
					drops += 1
					y += 10
				else:
					y += 1
			if drops > 1:
				crashes += 1
			var last: Array = trace.slice(trace.size() - 60)
			var mean := 0.0
			for p: float in last:
				mean += p
			mean /= last.size()
			var spread := 0.0
			for p: float in last:
				spread += (p - mean) * (p - mean)
			if mean > 6.0 and sqrt(spread / last.size()) / mean > 0.2:
				shaky += 1
		ends.sort()
		print("  %-8s end: low %5.0f  middle %5.0f  high %5.0f   stages %s   young lost %3.0f%%" % [
			kind, ends[0], ends[ends.size() / 2], ends[-1], stages,
			100.0 * lost_share / towns.size()])
		check(below == 0, "%s: none falls below the vestige (%d did)" % [kind, below])
		if not BARREN.has(kind):
			check(stuck == 0, "%s: none sits at the floor for its last half-century (%d do)" % [kind, stuck])
		check(over == 0, "%s: none ever holds more than its beds and the few it crowds in (%d did)"
			% [kind, over])
		check(crashes == 0, "%s: none crashes twice after settling (%d do)" % [kind, crashes])
		check(shaky == 0, "%s: every one holds steady over its last sixty years (%d swing)" % [kind, shaky])

	check(overbuilt.is_empty(), "no town ever builds past the ground it has room on (%d did)" % overbuilt.size())
	var tight: Array = by_kind["cramped"]
	var grown_tight: int = tight.filter(func(t): return t["book"].stage >= 3).size()
	check(grown_tight < TOWNS_EACH / 4, "rich land with little room to build stays small (%d of %d grew)"
		% [grown_tight, TOWNS_EACH])
	# What the land should make of them.
	var plains: Array = by_kind["plains"]
	var grown := plains.filter(func(t): return t["book"].stage >= 3).size()
	check(grown >= TOWNS_EACH * 0.6, "open plains grow into towns or cities (%d of %d)" % [grown, TOWNS_EACH])
	var fishers: Array = by_kind["fishing"]
	var fishing := fishers.filter(func(t): return t["book"].leaning == "fish").size()
	check(fishing >= TOWNS_EACH * 0.6, "a cove's town lives by fishing (%d of %d)" % [fishing, TOWNS_EACH])
	var wolf_loss := 0.0
	var plain_loss := 0.0
	for t: Dictionary in by_kind["wolves"]:
		wolf_loss += t["book"].lost_young / maxf(t["book"].born, 1.0)
	for t: Dictionary in plains:
		plain_loss += t["book"].lost_young / maxf(t["book"].born, 1.0)
	check(wolf_loss > plain_loss * 2.0,
		"wolf country loses far more of its young than the plains (%.0f%% against %.0f%%)"
		% [100.0 * wolf_loss / TOWNS_EACH, 100.0 * plain_loss / TOWNS_EACH])
	var hard: int = by_kind["wolves"].filter(func(t): return t["book"].hardiness > 0.3).size()
	check(hard >= TOWNS_EACH * 0.5, "and grows hard for it (%d of %d)" % [hard, TOWNS_EACH])
	var ruins: Array = by_kind["ruin"]
	var back := ruins.filter(func(t): return not t["book"].ruined).size()
	check(back >= 1 and back < TOWNS_EACH, "some ruins climb back, not all (%d of %d)" % [back, TOWNS_EACH])
	# THE FLOOR, LEANED ON. Five people on land with nothing to eat and fifty
	# man-eaters round them, for a century: the board may take them down to a
	# vestige and no further — and the vestige is grown people, not elders.
	var bare = land_script.made({"predators": 50.0, "biome": "desert"})
	var last = book_script.new()
	last.id = "the-last"
	last.adults = 5.0
	var lowest := 5.0
	while last.years < 100.0:
		rules.step(last, bare, 0.2, dt)
		lowest = minf(lowest, last.population())
	check(lowest >= rules.VESTIGE - 0.01 and last.adults >= 2.0,
		"on land that feeds nobody, among fifty beasts, a vestige lives on (%.1f, %.1f grown)"
		% [lowest, last.adults])
	print("CENTURY LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)


## The most a town may hold: its beds and the few it crowds in — more for a
## ruin, whose survivors sleep out among the stones — and never past MOST_SOULS.
func room_of(rules: Script, book: Object) -> float:
	var crowd: float = rules.RUIN_SLEEPS_OUT if book.ruined else rules.CROWDS_IN
	return minf(rules.MOST_SOULS, book.beds() + crowd)
