class_name TownRules
extends RefCounted
## THE MOVES THE BOARD ALLOWS. One step of a town out of sight: a quarter of a
## game day, about half a year of its life. Everything a town does in numbers
## happens here, in this order, and nowhere else:
##
##   1. the weather says how the crops and the berries do today (Weather);
##   2. the hands go to the food first — fields, the water, the bushes, the
##      hunt, best return first — and the rest to timber, stone and building;
##   3. it eats what it has, puts by what it can, and some of it spoils;
##   4. the wild larders it took from refill, faster when barely touched;
##   5. people are born, grow up, grow old and die: of years, of hunger, of the
##      beasts round it, and the youngest of plain bad luck where life is poor;
##   6. a crowded or starving town sends people out on the road;
##   7. it grows harder from every hard year it lives through, and its spirits
##      follow how fed and housed it is;
##   8. and it climbs or falls a stage, only after the case has held for years.
##
## THREE THINGS IT MUST NEVER DO, and what stops each:
##   DIE OUT — nobody dies of the board below a VESTIGE of a few people. A
##     town ends only when the hand ends it.
##   BALLOON — births need room: beds plus the few a town will crowd in, and
##     never past MOST_SOULS; overflow walks away instead of packing in. And the
##     land's larders are finite — a town that out-eats its fish catches less.
##   CRASH AND CRASH AGAIN — births listen to how fed the town has been over
##     years (`fed`), not today; the granary carries a bad season; and stages
##     move only after the case has held, so a town does not flicker.
## tools/board.py runs this over hundreds of towns for two centuries and fails
## if any of the three happens. Rates are per game YEAR, multiplied by the step.

## A step is this much of a game day.
const STEP_DAYS := 0.25

## THE AGES: years a child is a child, an adult an adult, an elder an elder
## (Villager.ADULT_AGE 16, ELDER_AGE 60, a lifespan of 60 to 85).
const CHILD_YEARS := 16.0
const ADULT_YEARS := 44.0
const ELDER_YEARS := 12.5

## APPETITE, in meals a year. An adult's belly empties at a quarter a second
## awake (VillagerNeeds) and a meal is forty of it (FoodItem.NUTRITION): about a
## meal and a half a day, and a day is 1.8 years. Children eat nothing in the
## live town — they are taken out of its economy altogether — but out here a
## poor town's children are what it cannot always feed.
const EAT_ADULT := 0.8          # measured: 0.79 (tools/live/calibrate_live.gd)
const EAT_ELDER := 0.7
const EAT_CHILD := 0.35
## What a town eats a head, children, adults and elders together.
const EAT_HEAD := 0.75
## THE DIETS, as Village.Diet numbers them; and the meals a grown body makes for
## a town that eats its dead. Never a child's: there are no children's bodies
## in this game, in sight or out of it.
const DIET_VEGAN := 0
const DIET_OMNIVORE := 1
const DIET_CANNIBAL := 3
const MEALS_A_BODY := 3.0
## A ruin skips meals to make what it has last.
const RUIN_EATS := 0.6
## What the granary loses a year, and the most it holds a head.
const SPOIL := 0.08
## THE GRANARY A TOWN KEEPS: years of eating put by. A drought is a lean year,
## not a famine, for a town that keeps a couple of years in store.
const RESERVE_YEARS := 2.0
## AND THE MOST IT WILL EVER PUT BY: five years, because a drought can last.
## Short of the reserve a town works extra to fill it; past it the work for food
## falls away SHARPLY — near the cap they top up only a third of what they eat
## and live off the store — and every hand that frees goes to building, fields
## and rest. Past the cap the oldest grain has gone sour and nobody wants it: it
## is thrown out. The same for timber and stone: once there is enough for the
## next few buildings, nobody fells another tree.
const RESERVE_CAP_YEARS := 5.0
const MATERIAL_BUILDS := 3.0

## WHAT A FIELD AND A PAIR OF HANDS BRING IN A YEAR, at a full larder and a
## fair sky. MEASURED, not chosen: tools/live/calibrate_live.gd ran the home
## town for three game days, twice, and its fields brought in 55 and 61 meals a
## field-year, tended and harvested by about one farmer to every three fields —
## a live field mostly grows by itself (Farm.BASE_GROWTH_PER_SEC), and the
## hands only tend it and carry the harvest home.
const FIELD_YIELD := 58.0        # a field, worked by FIELD_HANDS
const FIELD_HANDS := 0.32
## FISHING, MEASURED THE SAME WAY in a town founded on a shore (calibrate_live
## -- cove): a cast brings home a string (VillageJobs.SHORE_CATCH), 32 and 22
## meals a hand-year over two runs. Its harbour's boats land more on top.
const FISH_PER_HAND := 27.0
const BERRIES_PER_HAND := 3.0
const HUNT_PER_HAND := 3.5
## The wild larders: meals each holds per unit of land, and how fast it refills
## (logistic: fastest half full). A little always wanders back in.
const FISH_PER_WATER := 1.0
const FISH_PER_SHORE := 3.0
const FISH_REGROW := 0.8
const BERRIES_PER_BUSH := 5.0
const BERRY_REGROW := 3.0
const GAME_REGROW := 0.35
const WANDERS_BACK := 0.02
## A LARDER IS NEVER FISHED OR HUNTED BELOW THIS SHARE: past it, only what it
## grows back is taken. A town that strips its water starves for a decade and
## does it again; one that leaves a third lives off the rest forever.
const KEEP_STOCK := 0.35
## Beasts eat the game too: meals a year each.
const BEAST_EATS := 1.5
## THE BEASTS ARE A LARDER TOO, of a kind: they come back slowly toward what
## the land holds, only as fast as there is game to keep them, and a town's
## grown and hardened hands drive them off and kill them. A strong town keeps
## its wolves to a third; a handful of survivors lives with all of them. This is
## "provided the predators are kept in check" — the only way a poor town in
## wolf country learns to live there rather than merely hang on.
const BEAST_REGROW := 0.3
const BEAST_CULL := 0.25
const CULLERS := 40.0

## FIELDS AND HOUSES. Ground samples a field takes, effort a field and a house
## take (House.SPECS effort), and the effort, timber and stone a spare pair of
## hands puts in a year.
const SAMPLES_PER_FIELD := 4.0
## ROOM, read off the ground (TownLand.room): a house takes its footprint and
## the clear ground the live town keeps round it (Village.ROOM_ROUND_A_HOUSE),
## a field its samples; and fields never take more than this share of the room,
## so the town has somewhere left to sleep.
const AROUND_A_HOUSE := 3.2
const FIELD_SHARE := 0.6
## A LIVE TOWN'S REACH: its ring of influence grows with its people
## (Village._update_influence: 10 m and 1.8 m a soul, between 14 and 65), and it
## builds within four-fifths of it (Village._build_search). The board builds
## within the same.
const INFLUENCE_BASE := 10.0
const INFLUENCE_PER_SOUL := 1.8
const INFLUENCE_LEAST := 14.0
const INFLUENCE_MOST := 65.0
const BUILDS_WITHIN := 0.8
const FIELD_EFFORT := 30.0
const EFFORT_PER_HAND := 40.0
const WOOD_PER_HAND := 8.0
## THE WOODS: the timber a tree yields on average (WildTree.TIMBER, a tree of the
## seed's stand standing between size four and ten). A wood out of sight does
## not grow back: a felled tree is dead for good, and a tree only seeds while
## somebody is there to see it (WildTree._try_replant), so what a town cuts
## while folded stays cut.
const LUMBER_A_TREE := 51.0
const STONE_PER_HAND := 4.0
## A barn's stock left unfed dies off at this share a year: a live herd unfed
## starves in under a day, and a day is nearly two years.
const HERD_THINS := 1.0
## Houses stand empty and fall when there are this many beds per soul and more.
const EMPTY_BEDS := 1.8
const FALL_RATE := 0.15

## BIRTHS: children a year per adult, before food, room and spirits have their
## say. Poor towns have more (`POOR_BREED`), as poor towns do.
const FERTILITY := 0.11
const POOR_BREED := 0.8
## How many a town crowds in past its beds before it stops having children —
## the live town's own rule (Village.at_capacity: beds plus eight).
const CROWDS_IN := 8.0
## And a ruin sleeps out in the open among its stones: more of them fit.
const RUIN_SLEEPS_OUT := 14.0
## Births aim for this share of what the land feeds in an ordinary year, so a
## dry one does not find the town already past it.
const LAND_MARGIN := 0.85
## The ceiling for a town of any size (Village.MOST_SOULS).
const MOST_SOULS := 400.0

## DEATHS, a year, at full famine: children, adults, elders.
const STARVE_CHILD := 0.9
const STARVE_ADULT := 0.35
const STARVE_ELDER := 0.6
## People a year one man-eater takes from a town that cannot keep it off, and
## who it takes.
const BEAST_TAKES := 0.12
const BEAST_CHILD := 0.55
const BEAST_ELDER := 0.25
## The youngest dying of nothing in particular, where life is poorest.
const CHILD_ILLNESS := 0.03

## THE FLOOR. Nobody dies of the board below this many: see the header.
const VESTIGE := 3.0

## THE STAGES: the people each needs, and the years the case must hold to move.
const STAGE_AT: Array[float] = [0.0, 12.0, 40.0, 120.0, 250.0]
const STAGE_HOLD := 4.0
const FED_YEARS := 3.0
const MORALE_YEARS := 2.0

## HARDINESS: how fast hard years teach a town, and how slowly it forgets.
const HARDEN := 0.25
const SOFTEN := 0.02

## LEAVING: of the overflow, the share that walks out a year; and of the adults
## in a famine.
const OVERFLOW_LEAVES := 0.3
const FAMINE_LEAVES := 0.05


## HOW FAR OUT A TOWN OF `pop` BUILDS, in metres — the live town's own reach.
static func build_reach(pop: float) -> float:
	var ring := clampf(INFLUENCE_BASE + pop * INFLUENCE_PER_SOUL, INFLUENCE_LEAST, INFLUENCE_MOST)
	return maxf(ring * BUILDS_WITHIN, 12.0)


## THE GROUND A HOUSE OF THIS SIZE TAKES, in samples: its footprint (House.
## SPECS width; a longhouse is longer than it is wide) and the clear ground
## round it.
static func house_room(size: int) -> float:
	var wide: float = House.SPECS[size]["width"]
	var deep := wide * (1.6 if size == House.Size.LONGHOUSE else 1.0)
	return (wide + 2.0 * AROUND_A_HOUSE) * (deep + 2.0 * AROUND_A_HOUSE) \
		/ (TownLand.SAMPLE * TownLand.SAMPLE)


## THE GROUND A TOWN HAS BUILT AND FARMED OVER, in samples.
static func room_used(book: TownBook) -> float:
	var used := book.farms * SAMPLES_PER_FIELD
	for size: int in book.houses:
		used += house_room(size)
	return used


## How many fields the ground can take: field ground, and no more than its
## share of the room.
static func fields_room(land: TownLand) -> int:
	return int(minf(land.fields, land.room * FIELD_SHARE) / SAMPLES_PER_FIELD)


## HOW MUCH FOOD WORK A TOWN PUTS IN, as a share of what it eats, against how
## many years of eating it has put by. Below the reserve: extra, to fill it over
## two years. From the reserve to the cap: falling away fast, to a third.
static func food_wanted(years_stored: float) -> float:
	if years_stored < RESERVE_YEARS:
		return 1.1 + (RESERVE_YEARS - years_stored) / 2.0
	var full := clampf((years_stored - RESERVE_YEARS) / (RESERVE_CAP_YEARS - RESERVE_YEARS), 0.0, 1.0)
	return lerpf(1.1, 0.33, smoothstep(0.0, 1.0, full))


static func step_years() -> float:
	return GameState.DAY_YEARS * STEP_DAYS


## CATCH A TOWN UP to `to_years` (GameState.game_years), a step at a time, with
## the weather of each day. What a town was doing while it was away is entirely
## a function of where it stands, what it had, and how long it has been.
static func catch_up(book: TownBook, land: TownLand, world_seed: int, to_years: float) -> int:
	var dt := step_years()
	var taken := 0
	while book.years + dt <= to_years:
		var day := book.years / GameState.DAY_YEARS
		step(book, land, Weather.rain(world_seed, book.pos, day, land.biome), dt)
		taken += 1
	return taken


## ONE STEP of `dt` game years under a sky of `rain` (Weather.rain).
static func step(book: TownBook, land: TownLand, rain: float, dt: float) -> void:
	book.years += dt
	book.steps += 1
	var pop := book.population()
	if pop <= 0.0:
		return                          # the hand ended it; the board does not
	land = land.near(build_reach(pop))  # where a town this size builds and farms
	# 2. THE HANDS, food first.
	var need := (book.adults * EAT_ADULT + book.elders * EAT_ELDER
		+ book.children * EAT_CHILD) * (RUIN_EATS if book.ruined else 1.0)
	var hands := book.adults + book.elders * 0.4
	var crop := clampf(0.4 + 0.6 * rain, 0.35, 1.25)
	var sources := _sources(book, land, rain, crop)
	# AND ITS STOCK EATS, so it grows food for them too (Drove.trough).
	var herd_eats := float(Drove.trough(roundi(book.kept))) / GameState.DAY_YEARS
	var want := (need + herd_eats) * food_wanted(book.food / maxf(need + herd_eats, 0.001))
	var made := 0.0
	var at_work := {}
	sources.sort_custom(func(a, b): return a[1] > b[1])
	for src: Array in sources:
		if hands <= 0.0 or made >= want:
			break
		var rate: float = src[1]
		if rate <= 0.0:
			continue
		var put := minf(minf(hands, float(src[2])), (want - made) / rate)
		at_work[src[0]] = put
		hands -= put
		made += put * rate
	book.food += _harvest(book, land, at_work, sources, dt)
	# 3. EAT, PUT BY, SPOIL.
	var meal := need * dt
	var eaten := minf(book.food, meal)
	book.food -= eaten
	var famine := 0.0 if meal <= 0.0 else 1.0 - eaten / meal
	_keep_stock(book, herd_eats, dt)
	book.food -= book.food * SPOIL * dt
	book.food = minf(book.food, need * RESERVE_CAP_YEARS + 4.0)
	var put_by := clampf(book.food / maxf(need * 0.5, 0.001), 0.0, 1.5)
	var fed_now := (1.0 - famine) * (0.8 + 0.2 * put_by)
	book.fed += (fed_now - book.fed) * (1.0 - exp(-dt / FED_YEARS))
	# 4. THE WILD LARDERS refill.
	book.fish_stock = _regrow(book.fish_stock, FISH_REGROW, dt)
	book.berry_stock = _regrow(book.berry_stock, BERRY_REGROW * clampf(rain, 0.3, 1.5), dt)
	var game_room := maxf(land.game, 1.0)
	book.game_stock = _regrow(book.game_stock, GAME_REGROW, dt)
	var beasts := land.predators * book.beast_stock
	book.game_stock = maxf(book.game_stock - beasts * BEAST_EATS * dt / game_room, 0.05)
	var cull := BEAST_CULL * _guard(book) * minf(book.adults, CULLERS) / CULLERS
	book.beast_stock = clampf(book.beast_stock + (BEAST_REGROW * book.beast_stock
		* (1.0 - book.beast_stock) * book.game_stock - cull * book.beast_stock) * dt, 0.02, 1.0)
	# The rest of the hands: timber, stone, building.
	_build(book, land, hands, dt)
	book.leaning = _busiest(at_work)
	# 5. BORN, GROWN, DIED.
	var lost := _lives(book, land, famine, dt)
	# 6. THE ROAD OUT.
	_leave(book, famine, dt)
	# 7. HARDER, AND HOW THEY FEEL.
	var losses := lost / maxf(pop, 1.0) / dt
	var hardship := clampf(famine * 1.5 + losses * 8.0, 0.0, 1.0)
	book.hardiness += (HARDEN * hardship * (1.0 - book.hardiness)
		- SOFTEN * book.hardiness * (1.0 - hardship)) * dt
	book.hardiness = clampf(book.hardiness, 0.0, 1.0)
	var housed := clampf(float(book.beds()) / maxf(book.population(), 1.0), 0.0, 1.0)
	var spirit := 30.0 + 40.0 * clampf(book.fed, 0.0, 1.0) + 20.0 * housed \
		- 30.0 * famine - 40.0 * clampf(losses * 4.0, 0.0, 1.0) + book.belief * 0.1
	if book.ruined:
		spirit = minf(spirit, 15.0)
	book.morale += (clampf(spirit, 0.0, 100.0) - book.morale) * (1.0 - exp(-dt / MORALE_YEARS))
	# 8. THE STAGE.
	_climb(book, dt)
	if famine > 0.3 and not book.marks.get("hungry", false):
		book.marks["hungry"] = true
		book.note("Hunger came, and the stores ran out.")
	elif famine < 0.05 and book.marks.get("hungry", false):
		book.marks["hungry"] = false
		book.note("There was enough to eat again.")


## THE BARN'S STOCK, out of sight: it eats from the granary after the people
## do — the live barn's trough, Drove.trough, which costs more a head the
## bigger the herd — sends a share of itself to the store as meat when it is
## fed, and dies off when it is not. It eats more than it sends: stock turns
## grain into meat, at a loss.
static func _keep_stock(book: TownBook, eats_a_year: float, dt: float) -> void:
	if book.kept < 1.0:
		book.kept = 0.0
		return
	var asks := eats_a_year * dt
	var got := minf(book.food, asks)
	book.food -= got
	book.fodder += got
	var fed := got / asks
	var meat := book.kept * Drove.TO_THE_STORE * (book.kept_meat + Drove.DRESSED_OUT) \
		/ GameState.DAY_YEARS * fed * dt
	book.food += meat
	book.herd_meat += meat
	book.kept = maxf(book.kept * (1.0 - (1.0 - fed) * HERD_THINS * dt), 0.0)


## [name, meals a year per hand right now, most hands it can use]
static func _sources(book: TownBook, land: TownLand, rain: float, crop: float) -> Array:
	var tools := 1.0 + book.stage * 0.12
	var out := []
	# WHAT ITS DIET LETS IT EAT (Village.allowed_food_types): no flesh for a
	# vegan town, nothing but flesh for a carnivore or a cannibal one.
	var grain := book.diet <= DIET_OMNIVORE
	var flesh := book.diet != DIET_VEGAN
	if grain and not book.ruined and not book.no_plough:
		out.append(["fields", FIELD_YIELD / FIELD_HANDS * crop * tools, book.farms * FIELD_HANDS])
	var fish_room := land.water * FISH_PER_WATER + land.shore * FISH_PER_SHORE
	if fish_room > 0.0 and flesh:
		out.append(["fish", FISH_PER_HAND * book.fish_stock * (0.9 + 0.1 * rain) * tools,
			land.shore * 0.5])
	if land.bushes > 0.0 and grain:
		out.append(["berries", BERRIES_PER_HAND * book.berry_stock * (0.5 + 0.5 * rain),
			land.bushes * 0.5])
	if land.game > 0.0 and flesh:
		out.append(["hunt", HUNT_PER_HAND * book.game_stock * tools, land.game / 25.0])
	return out


## What the hands brought in, and what it took out of the wild.
static func _harvest(book: TownBook, land: TownLand, at_work: Dictionary,
		sources: Array, dt: float) -> float:
	var total := 0.0
	for src: Array in sources:
		var hands: float = at_work.get(src[0], 0.0)
		if hands <= 0.0:
			continue
		var got: float = hands * float(src[1]) * dt
		match String(src[0]):
			"fish":
				var room := land.water * FISH_PER_WATER + land.shore * FISH_PER_SHORE
				got = minf(got, _spare(book.fish_stock, FISH_REGROW, room, dt))
				book.fish_stock -= got / room
			"berries":
				var room := land.bushes * BERRIES_PER_BUSH
				got = minf(got, _spare(book.berry_stock, BERRY_REGROW, room, dt))
				book.berry_stock -= got / room
			"hunt":
				var room := land.game
				got = minf(got, _spare(book.game_stock, GAME_REGROW, room, dt))
				book.game_stock -= got / room
		total += got
	return total


## What may be taken from a larder this step: whatever stands above the share it
## is left at, and what it will grow back meanwhile.
static func _spare(stock: float, rate: float, room: float, dt: float) -> float:
	return (maxf(stock - KEEP_STOCK, 0.0) + rate * stock * (1.0 - stock) * dt) * room


## HOW MANY THE LAND ROUND IT COULD FEED, year in, year out — the long run, not
## the standing larder. Every field it has room for at an ordinary sky, and each
## wild larder held at the share a town leaves it (KEEP_STOCK): what it grows
## back there, less what the beasts eat, and never more than the hands the land
## has work for could bring in. A town has a feel for this — it is what it has
## watched come in for years — and its births listen to it, which is what stops
## it growing on a full larder and then starving on the one it has left.
static func land_feeds(book: TownBook, land: TownLand) -> float:
	var tools := 1.0 + book.stage * 0.12
	var meals := 0.0
	var grain := book.diet <= DIET_OMNIVORE
	var flesh := book.diet != DIET_VEGAN
	if grain and not book.ruined and not book.no_plough:
		meals += fields_room(land) * FIELD_YIELD * tools
	var kept := KEEP_STOCK * (1.0 - KEEP_STOCK)
	var fish_room := land.water * FISH_PER_WATER + land.shore * FISH_PER_SHORE
	if flesh:
		meals += minf(fish_room * FISH_REGROW * kept, land.shore * 0.5 * FISH_PER_HAND * KEEP_STOCK * tools)
		meals += minf(maxf(land.game * GAME_REGROW * kept - land.predators * book.beast_stock * BEAST_EATS, 0.0),
			land.game / 25.0 * HUNT_PER_HAND * KEEP_STOCK * tools)
	if grain:
		meals += minf(land.bushes * BERRIES_PER_BUSH * BERRY_REGROW * kept,
			land.bushes * 0.5 * BERRIES_PER_HAND * KEEP_STOCK)
	return meals / EAT_HEAD


static func _regrow(stock: float, rate: float, dt: float) -> float:
	return clampf(stock + (rate * stock * (1.0 - stock) + WANDERS_BACK) * dt, 0.0, 1.0)


static func _busiest(at_work: Dictionary) -> String:
	var best := ""
	var most := 0.0
	for job: String in at_work:
		if float(at_work[job]) > most:
			most = at_work[job]
			best = job
	return best


## TIMBER, STONE, AND WHAT THEY RAISE. A ruin raises nothing until it has
## learned to live where it is (`_recover`).
static func _build(book: TownBook, land: TownLand, hands: float, dt: float) -> void:
	if hands <= 0.0:
		return
	var pop := book.population()
	var cramped := pop + 2.0 > book.beds() * 0.95
	var free := land.room - room_used(book)
	var more_fields := book.farms < fields_room(land) and free >= SAMPLES_PER_FIELD \
		and book.fed < 1.05 and not book.ruined
	if book.ruined and not _recover(book):
		hands *= 0.3                    # they gather; they do not raise
		cramped = false
	var gather := hands * (0.4 if cramped else 0.25)
	var trees := clampf(land.wood / 6.0, 0.1, 1.0) * clampf(book.wood_stock / 0.5, 0.0, 1.0)
	var biggest: Dictionary = House.SPECS[House.Size.LONGHOUSE]
	var wood_full := book.wood >= float(biggest["lumber"]) * MATERIAL_BUILDS
	var stone_full := book.stone >= float(biggest["stone"]) * MATERIAL_BUILDS
	if wood_full and stone_full:
		gather = 0.0
	if not wood_full:
		# FELLED FROM THE WOODS ROUND IT, as a live town's woodcutters fell: any
		# tree standing, until there are none. A logged-out valley stays logged out.
		var timber_room := land.wood * LUMBER_A_TREE
		var cut := gather * (0.65 if not stone_full else 1.0) * WOOD_PER_HAND * trees * dt
		cut = minf(cut, book.wood_stock * timber_room)
		book.wood += cut
		book.felled += cut / LUMBER_A_TREE
		if timber_room > 0.0:
			book.wood_stock = maxf(book.wood_stock - cut / timber_room, 0.0)
	if not stone_full:
		book.stone += gather * (0.35 if not wood_full else 1.0) * STONE_PER_HAND * dt
	var raise := hands - gather
	if more_fields:
		book.tilling += raise * 0.4 * EFFORT_PER_HAND * dt
		raise *= 0.6
		if book.tilling >= FIELD_EFFORT:
			book.tilling -= FIELD_EFFORT
			book.farms += 1
			free -= SAMPLES_PER_FIELD   # and that ground is not there for a house
	if cramped:
		var size := House.Size.HUT if book.stage <= TownBook.Stage.HAMLET \
			else (House.Size.HOUSE if book.stage == TownBook.Stage.VILLAGE else House.Size.LONGHOUSE)
		var spec: Dictionary = House.SPECS[size]
		book.building = minf(book.building + raise * EFFORT_PER_HAND * dt, float(spec["effort"]))
		# NO ROOM, NO HOUSE: the ground within reach is built over. The town
		# crowds in what it can and sends the rest out on the road (`_leave`).
		if book.building >= float(spec["effort"]) and book.wood >= float(spec["lumber"]) \
				and book.stone >= float(spec["stone"]) and free >= house_room(size):
			book.building = 0.0
			book.wood -= float(spec["lumber"])
			book.stone -= float(spec["stone"])
			book.houses.append(size)
	elif book.beds() > pop * EMPTY_BEDS + 6.0 and not book.houses.is_empty():
		# EMPTY HOUSES FALL — slowly, smallest first.
		book.building += FALL_RATE * dt
		if book.building >= 1.0:
			book.building = 0.0
			book.houses.sort()
			book.houses.pop_front()


## HOW WELL A TOWN KEEPS THE BEASTS OFF, 0..0.95: grown hands, its size and
## stage, and what hard years have taught it. A ruin's broken walls keep less.
static func _guard(book: TownBook) -> float:
	return clampf(0.15 + 0.6 * book.adults / (book.adults + 25.0) + 0.08 * book.stage
		+ 0.3 * book.hardiness - (0.2 if book.ruined else 0.0), 0.0, 0.95)


## A RUIN THAT HAS LEARNED TO LIVE AMONG ITS STONES starts to build again: hard
## enough, and enough of them. Until then it is a vestige.
static func _recover(book: TownBook) -> bool:
	if book.hardiness < 0.4 or book.population() < 8.0 or book.fed < 0.8:
		return false
	if book.beds() >= book.population() * 0.5:
		book.ruined = false
		book.note("The survivors have begun to build again.")
	return true


## BORN, GROWN, DIED. Returns how many died this step.
static func _lives(book: TownBook, land: TownLand, famine: float, dt: float) -> float:
	var pop := book.population()
	var poor := 1.0 - float(book.stage) / 4.0
	# Who will grow up, grow old, and die of years.
	var grow_up := book.children / CHILD_YEARS * dt
	var grow_old := book.adults / ADULT_YEARS * dt
	var aged := book.elders / ELDER_YEARS * dt
	# Hunger, softened by what hard years have taught.
	var tough := 1.0 - 0.6 * book.hardiness
	var starve_c := famine * STARVE_CHILD * book.children * dt * tough
	var starve_a := famine * STARVE_ADULT * book.adults * dt * tough
	var starve_e := famine * STARVE_ELDER * book.elders * dt * tough
	# The beasts, against what the town can do to keep them off.
	var beasts := land.predators * book.beast_stock * BEAST_TAKES * (1.0 - _guard(book)) * dt
	var prey_c := minf(beasts * BEAST_CHILD, book.children * 0.5)
	var prey_e := minf(beasts * BEAST_ELDER, book.elders * 0.5)
	var prey_a := minf(beasts * (1.0 - BEAST_CHILD - BEAST_ELDER), book.adults * 0.2)
	var ill := book.children * CHILD_ILLNESS * poor * (1.0 - book.hardiness) * dt
	var died := aged + starve_c + starve_a + starve_e + prey_c + prey_e + prey_a + ill
	# THE FLOOR: the board never takes a town below a vestige — and a vestige is
	# grown people who can still have children, not three elders who outlive
	# everything and end it anyway.
	var floor_at := minf(VESTIGE, pop)
	var scale := 1.0
	if pop - died < floor_at and died > 0.0:
		scale = maxf(pop - floor_at, 0.0) / died
	if pop <= floor_at + 1.0:
		grow_old = 0.0
	# Births: food, room, spirits — and poverty, which has more of them.
	var room := minf(MOST_SOULS, book.beds() + (RUIN_SLEEPS_OUT if book.ruined else CROWDS_IN))
	var fits := clampf((room - pop) / maxf(4.0, room * 0.15), 0.0, 1.0)
	var feeds := land_feeds(book, land) * LAND_MARGIN
	fits = minf(fits, clampf((feeds - pop) / maxf(4.0, feeds * 0.15), 0.0, 1.0))
	var eats := smoothstep(0.55, 1.0, book.fed)
	var heart := 0.6 + 0.4 * book.morale / 100.0
	var born := 0.0
	if book.adults >= 2.0:
		born = book.adults * FERTILITY * eats * fits * heart * (1.0 + POOR_BREED * poor) * dt
	book.children += born - grow_up - (starve_c + prey_c + ill) * scale
	book.adults += grow_up - grow_old - (starve_a + prey_a) * scale
	book.elders += grow_old - (aged + starve_e + prey_e) * scale
	book.children = maxf(book.children, 0.0)
	book.adults = maxf(book.adults, 0.0)
	book.elders = maxf(book.elders, 0.0)
	book.born += born
	if book.diet == DIET_CANNIBAL:
		book.food += (starve_a + starve_e + prey_a + prey_e + aged) * scale * MEALS_A_BODY
	book.starved += (starve_c + starve_a + starve_e) * scale
	book.taken += (prey_c + prey_a + prey_e) * scale
	book.aged_out += aged * scale
	book.lost_young += (starve_c + prey_c + ill) * scale
	var beast_toll := (prey_c + prey_a + prey_e) * scale
	if beast_toll / maxf(pop, 1.0) / dt > 0.04 and not book.marks.get("beasts", false):
		book.marks["beasts"] = true
		book.note("The beasts took people from the edges of the town.")
	elif beast_toll / maxf(pop, 1.0) / dt < 0.01:
		book.marks["beasts"] = false
	return died * scale


## THE ROAD OUT. A ruin does not know there is anywhere else to go.
static func _leave(book: TownBook, famine: float, dt: float) -> void:
	if book.ruined:
		return
	var room := minf(MOST_SOULS, book.beds() + CROWDS_IN)
	var over := maxf(book.population() - room, 0.0)
	var go := over * OVERFLOW_LEAVES * dt
	if book.fed < 0.45:
		go += book.adults * FAMINE_LEAVES * famine * dt
	go = minf(go, maxf(book.adults - 2.0, 0.0) * 0.5)
	go = minf(go, maxf(book.population() - VESTIGE, 0.0) * 0.5)
	if go <= 0.0:
		return
	# Families go together: the children with them, in proportion.
	var kids := minf(go * book.children / maxf(book.adults, 1.0) * 0.5, book.children)
	book.adults -= go
	book.children -= kids
	book.leaving += go + kids
	book.leaving_young += kids
	book.left += go + kids


## A STAGE UP OR DOWN, only once the case has held.
static func _climb(book: TownBook, dt: float) -> void:
	var pop := book.population()
	var up := book.stage < TownBook.Stage.CITY and pop >= STAGE_AT[book.stage + 1] \
		and book.fed >= 0.9 and not book.ruined
	var down := book.stage > TownBook.Stage.CAMP and pop < STAGE_AT[book.stage] * 0.6
	if up:
		book.stage_years = maxf(book.stage_years, 0.0) + dt
	elif down:
		book.stage_years = minf(book.stage_years, 0.0) - dt
	else:
		book.stage_years *= exp(-dt / STAGE_HOLD)
	if book.stage_years >= STAGE_HOLD:
		book.stage = (book.stage + 1) as TownBook.Stage
		book.stage_years = 0.0
		book.note("It has grown into a %s." % book.stage_name())
	elif book.stage_years <= -STAGE_HOLD * 1.5:
		book.stage = (book.stage - 1) as TownBook.Stage
		book.stage_years = 0.0
		book.note("It has dwindled to a %s." % book.stage_name())
