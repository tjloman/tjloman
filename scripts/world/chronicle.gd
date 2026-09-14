class_name Chronicle
extends Node
## THE RECORD OF A REIGN.
##
## Every number the temple wants to show as a CURRENT value already exists
## somewhere — population is a walk over a group, alignment is one float on
## GameState, casts are a counter on MiracleManager. Nothing anywhere records
## what any of them were an hour ago, and a chart of a number's history cannot
## be reconstructed after the fact from the number. So this samples the world
## on a slow clock from the first second of a run, and it is the one thing in
## the whole temple that had to be built before anything could be displayed.
##
## IT NEVER RUNS OUT OF ROOM AND NEVER DROPS THE START OF THE REIGN. When the
## ring fills, it throws away every other sample and doubles the interval —
## so the chart always spans the WHOLE run, losing resolution at the old end
## rather than losing the old end. A four-hour session lands at about a sample
## every ninety seconds; a twenty-hour one at about eight minutes. Both draw a
## complete life.
##
## WHAT A DAY IS, for reading the axis: GameState.DAY_SECONDS is 320 real
## seconds and a villager lives about forty of them, so an evening's play is
## roughly one human lifetime and the population chart is a real demographic
## record rather than a squiggle.

## The ring, and the clock it fills on. FIRST_EVERY is an eighth of a game day,
## which is fine grain for the first two and a half hours and coarsens itself
## after that.
const KEEP := 600
const FIRST_EVERY := GameState.DAY_SECONDS / 8.0

## Where each number sits in a sample row. Rows are plain float arrays because
## they go through JSON into the profile, and a dictionary per sample would be
## six hundred copies of the same ten keys.
const T := 0
const POP := 1
const TOWNS := 2
const FAITHFUL := 3
const ALIGN := 4
const BELIEF := 5
const CASTS_GOD := 6
const CASTS_BEAST := 7
const AGE_MID := 8
const GROWTH := 9
const WIDE := 10

## The columns a chart can ask for by name.
const FIELDS := {
	"population": POP,
	"villages": TOWNS,
	"faithful": FAITHFUL,
	"alignment": ALIGN,
	"belief": BELIEF,
	"miracles_god": CASTS_GOD,
	"miracles_beast": CASTS_BEAST,
	"median_age": AGE_MID,
	"growth": GROWTH,
}

## HOW SOMEBODY DIED, and the order these are tested in — a man on fire who was
## also starving is recorded as burnt, because the fire is what killed him and
## because it is the one a god is answerable for.
##
## SUDDEN is the honest name for the bucket a lightning bolt lands in. An
## instant kill leaves no attacker and no burn, so nothing in the world
## distinguishes "struck by your miracle" from "fell off a cliff"; naming the
## bucket after the evidence is better than guessing at a cause. Giving
## Villager.take_damage's `by_god` flag somewhere to live would split it, and
## that file is at its line cap.
const CAUSES: Array[String] = ["age", "fire", "hunger", "beast", "war", "sudden"]

## How often the ring is written out to the profile. Writing on every sample
## would rewrite the whole index file every forty seconds for a chart nobody
## may ever open.
const SAVE_EVERY := 8

var _rows: Array = []
var _every := FIRST_EVERY
var _due := 0.0
var _since_save := 0
## Cause -> [how many, how many years they had between them]. Two numbers is
## the whole ledger: it answers "what kills people here" and "how long do they
## get" without keeping a row per corpse.
var _graves: Dictionary = {}


## The one door in, matching MiracleManager.of — this is a node in the tree,
## not an autoload, and calling an instance method through the class name is a
## build failure. See tools/check_calls.py.
static func of(tree: SceneTree) -> Chronicle:
	if tree == null:
		return null
	return tree.get_first_node_in_group("chronicle") as Chronicle


func _ready() -> void:
	add_to_group("chronicle")
	var saved: Variant = SaveGame.active_profile().get("chronicle", {})
	if saved is Dictionary:
		from_dict(saved as Dictionary)
	# A RUN THAT LOADS A SAVE STILL WANTS A POINT AT ITS OWN START. Without
	# this the first sample is one interval late, which on a fresh world is a
	# chart that begins forty seconds after the beginning.
	if _rows.is_empty():
		_take()


func _process(delta: float) -> void:
	_due -= delta
	if _due > 0.0:
		return
	_due = _every
	_take()


## SAMPLE THE WORLD. One walk over the villagers, one over the villages, and
## everything else is a field read.
func _take() -> void:
	var row := PackedFloat32Array()
	row.resize(WIDE)
	row[T] = GameState.game_years
	var ages := PackedFloat32Array()
	for v in get_tree().get_nodes_in_group("villagers"):
		var soul := v as Villager
		if soul == null or not is_instance_valid(soul):
			continue
		ages.append(soul.age)
	row[POP] = float(ages.size())
	row[AGE_MID] = _middle(ages)
	var belief := 0.0
	var towns := 0
	var faithful := 0
	for v in get_tree().get_nodes_in_group("village"):
		var town := v as Village
		if town == null or not is_instance_valid(town):
			continue
		towns += 1
		belief += town.belief
		if town.converted:
			faithful += 1
	row[TOWNS] = float(towns)
	row[FAITHFUL] = float(faithful)
	row[BELIEF] = belief / float(maxi(towns, 1))
	row[ALIGN] = GameState.alignment
	var wonders := MiracleManager.of(get_tree())
	if wonders != null:
		row[CASTS_GOD] = float(wonders.casts_made)
		row[CASTS_BEAST] = float(wonders.creature_casts)
	var beast := get_tree().get_first_node_in_group("creature") as Creature
	if beast != null and is_instance_valid(beast):
		row[GROWTH] = beast.growth
	_rows.append(row)
	if _rows.size() > KEEP:
		_thin()
	_since_save += 1
	if _since_save >= SAVE_EVERY:
		_since_save = 0
		save()


## THE RING IS FULL. Keep every other sample and halve the resolution rather
## than dropping the oldest, so the chart keeps spanning the entire reign.
func _thin() -> void:
	var kept: Array = []
	for i in range(0, _rows.size(), 2):
		kept.append(_rows[i])
	_rows = kept
	_every *= 2.0


## The median, which is the honest middle for ages — a mean is dragged around
## by the newborns a good harvest produces in a batch.
static func _middle(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var half := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[half]
	return (sorted[half - 1] + sorted[half]) * 0.5


## A BURIAL. Called from VillagerNeeds.mourn, which is already the one place
## that decides what a death means.
func inter(cause: String, years: float) -> void:
	var grave: Array = _graves.get(cause, [0.0, 0.0])
	grave[0] += 1.0
	grave[1] += years
	_graves[cause] = grave


## How many died of each cause, and the mean age they reached doing it.
## `[count, mean_age]` per cause, only for causes that have claimed somebody.
func burials() -> Dictionary:
	var out := {}
	for cause: String in _graves:
		var grave: Array = _graves[cause]
		if grave[0] <= 0.0:
			continue
		out[cause] = [int(grave[0]), grave[1] / grave[0]]
	return out


## LIFE EXPECTANCY AS OBSERVED, which is a different and far more interesting
## number than the one the world is built from. Villager.lifespan is rolled at
## birth from 60..85, so the average of THAT is about 72.5 in every game ever
## played, however well or badly you rule. This is the average age people
## actually reach, wolves and lightning and famine included, and a cruel reign
## drives it into the thirties.
func life_expectancy() -> float:
	var souls := 0.0
	var years := 0.0
	for cause: String in _graves:
		var grave: Array = _graves[cause]
		souls += grave[0]
		years += grave[1]
	if souls <= 0.0:
		return 0.0
	return years / souls


## How many have died at all, which is what tells a chart whether the
## expectancy above is worth printing yet.
func buried() -> int:
	var souls := 0
	for cause: String in _graves:
		souls += int((_graves[cause] as Array)[0])
	return souls


## ONE COLUMN, for a chart to draw. Named rather than indexed because the
## charts are built from a table of titles and a caller that passes 4 where it
## meant 5 draws a plausible and completely wrong line.
func series(field: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not FIELDS.has(field):
		push_warning("Chronicle has no series named '%s'" % field)
		return out
	var col: int = FIELDS[field]
	for row: PackedFloat32Array in _rows:
		out.append(row[col])
	return out


## The game-years each sample was taken at — the x axis for everything above.
func when() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for row: PackedFloat32Array in _rows:
		out.append(row[T])
	return out


## How many samples there are, for a caller deciding whether a chart is worth
## drawing at all. Two points is a line segment, not a history.
func depth() -> int:
	return _rows.size()


## PERSISTENCE, onto the PROFILE rather than into the world file: this is the
## history of a creature's reign, and it must survive the land being reloaded
## under it. Rows go out as plain arrays because the profile index is JSON.
func save() -> void:
	SaveGame.remember("chronicle", to_dict())


func to_dict() -> Dictionary:
	var flat: Array = []
	for row: PackedFloat32Array in _rows:
		flat.append(Array(row))
	return {"every": _every, "rows": flat, "graves": _graves}


func from_dict(data: Dictionary) -> void:
	_every = float(data.get("every", FIRST_EVERY))
	_due = _every
	_rows = []
	for entry: Variant in data.get("rows", []):
		if not entry is Array:
			continue
		var row := PackedFloat32Array()
		row.resize(WIDE)
		var raw := entry as Array
		for i in mini(raw.size(), WIDE):
			row[i] = float(raw[i])
		_rows.append(row)
	_graves = {}
	var saved: Variant = data.get("graves", {})
	if saved is Dictionary:
		for cause: Variant in saved as Dictionary:
			var grave: Variant = (saved as Dictionary)[cause]
			if grave is Array and (grave as Array).size() >= 2:
				_graves[str(cause)] = [
					float((grave as Array)[0]), float((grave as Array)[1])]
