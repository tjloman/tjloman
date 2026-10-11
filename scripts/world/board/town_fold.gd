class_name TownFold
extends RefCounted
## A TOWN INTO NUMBERS AND BACK AGAIN — the two doors between the live town and
## its TownBook. Both work on the town's saved RECORD (Village.to_dict), the
## same dictionary a save writes and SaveGame.recall reads, so a folded town is
## simply a town remembered: it saves, it shows on the temple's map, and it is
## taken back by position, with no second path to keep in step.
##
## FOLDING keeps what the live town knew best — who is alive and how old, what
## it has standing, what is in the store — and carries over what only the board
## keeps between visits: its hardiness, its stage, the larders round it, its
## tallies and its history.
##
## UNFOLDING is the alibi. The record is stepped up to now (TownRules), and then
## its PEOPLE are made to agree with the numbers BY NAME: everyone is older by
## the years that passed; the board's dead are taken from those it says died —
## the eldest of each age first, so the old die of age and not the young — and
## named in the town's history; the board's newborns are added as children of
## the right ages; and a town that grew has people who arrived. Nobody the
## player knew is swapped for a stranger while a living count still holds them.

## Where a ruin is told apart from a camp: no roof left standing, and few.
const RUIN_MOST := 15.0
## The most of a town's dead the history names in one visit.
const NAMED_DEAD := 4
## The dead it keeps by name while out of sight, for the telling.
const GONE_KEPT := 40
## Years of food in store past which a town's people come back fed, whatever
## the last season was like.
const FED_STORE := 0.25
## How much of the food a farming town stores as grain; the rest is meat.
const GRAIN_SHARE := 0.7


## THE NUMBERS FOR THIS RECORD, as of `now` (GameState.game_years): what the
## live town wrote down, laid over whatever the board already knew of it.
static func book_of(record: Dictionary, now: float) -> TownBook:
	var book := TownBook.from_dict(record.get("board", {}))
	book.id = String(record.get("name", "town")) + "@" + str(record.get("pos", []))
	book.name = String(record.get("name", ""))
	var at: Array = record.get("pos", [0.0, 0.0])
	book.pos = Vector2(float(at[0]), float(at[1]))
	book.home = bool(record.get("home", false))
	book.converted = bool(record.get("converted", false))
	book.belief = float(record.get("belief", 0.0))
	book.diet = int(record.get("diet", 1))
	book.no_plough = book.diet == 3 or bool(record.get("no_plough", false))
	book.children = 0.0
	book.adults = 0.0
	book.elders = 0.0
	var women := 0.0
	var folk: Array = record.get("folk", [])
	for one: Dictionary in folk:
		var age := float(one.get("age", 25.0))
		if age < TownRules.CHILD_YEARS:
			book.children += 1.0
		elif age < TownRules.CHILD_YEARS + TownRules.ADULT_YEARS:
			book.adults += 1.0
		else:
			book.elders += 1.0
		if bool(one.get("female", true)):
			women += 1.0
	book.women = women / maxf(folk.size(), 1.0) if not folk.is_empty() else 0.5
	book.houses = (record.get("houses", []) as Array).duplicate()
	book.farms = int(record.get("farms", 0))
	var store: Dictionary = record.get("store", {})
	book.food = float(store.get("plant", 0)) + float(store.get("meat", 0))
	book.wood = float(store.get("lumber", 0))
	book.stone = float(store.get("stone", 0))
	# THE BARN'S STOCK as the live town last counted it.
	var kept: Dictionary = record.get("kept", {})
	book.kept = 0.0
	var meat := 0.0
	for kind: String in kept:
		book.kept += float(kept[kind])
		meat += float(kept[kind]) * float((Animal.SPECIES.get(kind, {}) as Dictionary).get("meat", 0))
	book.kept_meat = meat / maxf(book.kept, 1.0)
	book.years = float(record.get("at_years", now))
	if not record.has("board"):
		book.stage = _stage_for(book.population()) as TownBook.Stage
	book.ruined = book.houses.is_empty() and book.population() <= RUIN_MOST
	return book


## THE ALIBI: step the record's town up to `now` and write the result back into
## the record, people and all. Returns how many steps it took.
##
## QUIET, the board's own clock stepping a town out of sight (Chessboard): who
## died is kept by name (record "gone") and nothing is written in its history —
## a step is a quarter of a day, and a line for each would bury everything else.
## Brought back into sight, it is told once, for all the years away.
static func catch_up(record: Dictionary, land: TownLand, world_seed: int, now: float,
		quiet := false) -> int:
	var book := book_of(record, now)
	var was_children := book.children
	var was_adults := book.adults
	var was_elders := book.elders
	var was_kept := book.kept
	var was_leaving := book.leaving
	var was_young := book.leaving_young
	var then := book.years
	var steps := TownRules.catch_up(book, land, world_seed, now)
	if steps == 0:
		if not quiet and record.has("seen_at"):
			_tell(book, record.get("gone", []), book.years - float(record["seen_at"]), record["seen_was"])
			_heard(record)
			record["board"] = book.to_dict()
		return 0
	var away := book.years - then
	# WHO WENT, by name: out of the town before the rest is matched to the
	# numbers, so those who walked away are not told as dead.
	var kids := roundi(book.leaving_young - was_young)
	var going := [maxi(roundi(book.leaving - was_leaving) - kids, 0), kids]
	var was := [was_children, was_adults, was_elders]
	var dead := _reconcile(record, book, away, going)
	if not record.has("seen_at"):
		record["seen_at"] = then
		record["seen_was"] = was
	var gone: Array = record.get("gone", [])
	for one: Dictionary in dead:
		if one.has("name") and gone.size() < GONE_KEPT:
			gone.append({"name": one["name"], "age": one["age"]})
	if quiet:
		record["gone"] = gone
	else:
		_tell(book, gone, book.years - float(record["seen_at"]), record["seen_was"])
		_heard(record)
	var kept: Dictionary = (record.get("kept", {}) as Dictionary).duplicate()
	for kind: String in kept:
		kept[kind] = roundi(float(kept[kind]) * book.kept / maxf(was_kept, 1.0))
	record["kept"] = kept
	record["houses"] = book.houses.duplicate()
	record["farms"] = book.farms
	var store: Dictionary = (record.get("store", {}) as Dictionary).duplicate()
	var grain := GRAIN_SHARE if book.leaning == "fields" else 1.0 - GRAIN_SHARE
	store["plant"] = int(book.food * grain)
	store["meat"] = int(book.food * (1.0 - grain))
	store["lumber"] = int(book.wood)
	store["stone"] = int(book.stone)
	record["store"] = store
	record["at_years"] = book.years
	record["board"] = book.to_dict()
	return steps


## PEOPLE TO MATCH THE NUMBERS, BY NAME. Everyone is older by `away`; then each
## age is brought to the board's count — the eldest of an age go first when it
## has too many, and newcomers of that age are added when it has too few.
static func _reconcile(record: Dictionary, book: TownBook, away: float,
		going: Array = [0, 0]) -> Array:
	var folk: Array = []
	for one: Dictionary in record.get("folk", []):
		var aged := one.duplicate()
		aged["age"] = float(one.get("age", 25.0)) + away
		folk.append(aged)
	_set_out(record, folk, int(going[0]), int(going[1]))
	var bands := [[0.0, TownRules.CHILD_YEARS],
		[TownRules.CHILD_YEARS, TownRules.CHILD_YEARS + TownRules.ADULT_YEARS],
		[TownRules.CHILD_YEARS + TownRules.ADULT_YEARS, 200.0]]
	var want := [roundi(book.children), roundi(book.adults), roundi(book.elders)]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([book.id, book.steps])
	var kept: Array = []
	var dead: Array = []
	for b in 3:
		var lo: float = bands[b][0]
		var hi: float = bands[b][1]
		var here := folk.filter(func(one): return float(one["age"]) >= lo and float(one["age"]) < hi)
		# Those past their own span first, then the eldest.
		here.sort_custom(func(x, y): return _due(x) > _due(y))
		while here.size() > int(want[b]):
			dead.append(here.pop_front())
		while here.size() < int(want[b]):
			here.append(_newcomer(rng, lo, minf(hi, lo + maxf(away, 1.0)) if b == 0 else hi,
				book.women))
		kept.append_array(here)
	for one: Dictionary in kept:
		_condition(one, book, rng)
	record["folk"] = kept
	return dead


## TOLD: what was kept for the telling is done with.
static func _heard(record: Dictionary) -> void:
	record.erase("seen_at")
	record.erase("seen_was")
	record.erase("gone")


## THOSE WHO LEAVE, taken out of `folk` by name to wait for company on the
## road (record "setting_out": Migration makes them a band): the youngest grown
## first — the young are the ones who go — and children with them.
static func _set_out(record: Dictionary, folk: Array, adults: int, children: int) -> void:
	if adults + children <= 0:
		return
	var out: Array = record.get("setting_out", [])
	var grown := []
	var young := []
	for one: Dictionary in folk:
		var age := float(one["age"])
		if age < TownRules.CHILD_YEARS:
			young.append(one)
		elif age < TownRules.CHILD_YEARS + TownRules.ADULT_YEARS:
			grown.append(one)
	grown.sort_custom(func(x, y): return float(x["age"]) < float(y["age"]))
	for one: Dictionary in grown.slice(0, adults) + young.slice(0, children):
		folk.erase(one)
		out.append(one)
	record["setting_out"] = out


## HOW EACH OF THEM IS, as their town is: fed if it has food put by or has been
## eating well, hungry and worn only if the numbers say it has gone without, and
## in the spirits it is in. Whatever they were when the town folded is years
## stale — a man who went out of sight hungry in a full town is not still
## hungry twenty years on.
static func _condition(one: Dictionary, book: TownBook, rng: RandomNumberGenerator) -> void:
	var need := book.adults * TownRules.EAT_ADULT + book.elders * TownRules.EAT_ELDER \
		+ book.children * TownRules.EAT_CHILD
	var stored := book.food / maxf(need, 0.001)
	var fed := clampf(book.fed, 0.0, 1.0)
	if stored >= FED_STORE or fed >= 0.9:
		one["hunger"] = rng.randf_range(5.0, 35.0)
		one["health"] = rng.randf_range(90.0, 100.0)
	else:
		one["hunger"] = clampf(lerpf(90.0, 40.0, fed) + rng.randf_range(-8.0, 8.0), 0.0, 95.0)
		one["health"] = clampf(lerpf(55.0, 90.0, fed / 0.9) + rng.randf_range(-5.0, 5.0), 30.0, 100.0)
	one["energy"] = rng.randf_range(60.0, 95.0)
	one["happiness"] = clampf(book.morale + rng.randf_range(-8.0, 8.0), 0.0, 100.0)


## HOW FAR PAST THEIR SPAN somebody is: the first to go when an age has too
## many. Years past it, or their age a hundred years short of it if it is not
## known, so the eldest still go first.
static func _due(one: Dictionary) -> float:
	var age := float(one["age"])
	return age - float(one["lifespan"]) if one.has("lifespan") else age - 100.0


static func _newcomer(rng: RandomNumberGenerator, youngest: float, oldest: float,
		women: float) -> Dictionary:
	return {"age": rng.randf_range(youngest, maxf(oldest - 0.01, youngest)),
		"lifespan": rng.randf_range(60.0, 85.0),
		"female": rng.randf() < women, "morality": rng.randf_range(0.0, 40.0),
		"health": 100.0, "hunger": rng.randf_range(10.0, 40.0), "energy": 80.0}


## WHAT HAPPENED WHILE NOBODY LOOKED, in the town's own history: who is gone, by
## name, and the shape of the years in one line.
static func _tell(book: TownBook, dead: Array, away: float, was: Array) -> void:
	var named := []
	for one: Dictionary in dead.slice(0, NAMED_DEAD):
		if one.has("name"):
			named.append("%s (%d)" % [one["name"], int(float(one["age"]))])
	if not named.is_empty():
		var more := dead.size() - named.size()
		book.note("Gone while you were away: %s%s." % [", ".join(named),
			(" and %d more" % more) if more > 0 else ""])
	var before := float(was[0]) + float(was[1]) + float(was[2])
	book.note("%d years passed. %d souls became %d: %s." % [roundi(away), roundi(before),
		roundi(book.population()), _gist(book, before)])


static func _gist(book: TownBook, before: float) -> String:
	var now := book.population()
	if book.ruined:
		return "still a ruin, its few keeping close to the stones"
	if now > before * 1.25:
		return "it grew"
	if now < before * 0.75:
		return "hard years thinned it"
	return "it held its own"


static func _stage_for(pop: float) -> int:
	var stage := 0
	for i in TownRules.STAGE_AT.size():
		if pop >= TownRules.STAGE_AT[i]:
			stage = i
	return stage
