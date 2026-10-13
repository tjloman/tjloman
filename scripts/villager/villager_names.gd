class_name VillagerNames
extends RefCounted
## A NAME FOR EVERY VILLAGER, and not one their town has given already.
##
## There were twelve names for each sex, written into the villager, so every
## town in the world was full of Pips and Lomaxes. The names live in
## data/villager_names.json now: a few thousand, from the lists in
## tools/villager_names.py, which writes the file and checks it. Add a name
## there, not here.
##
## A TOWN REMEMBERS WHAT IT HAS CALLED ITS PEOPLE (a set kept on the town node
## itself, so it goes when the town does) and draws again rather than hand out
## a name it has used. Nobody new is named after the dead, either, which is how
## a small place would have it.

## WHERE THE NAMES LIVE. Shipped by the export's "*.json" include filter.
const FILE := "res://data/villager_names.json"
## How many draws a town makes for a name it has not used before it settles for
## a repeat. A town has used a few hundred of two thousand at most, so the
## first draw nearly always does.
const TRIES := 8
## THE OLD TWELVE, for the day the file is missing (an export that dropped it):
## a villager must always be able to be named.
const FALLBACK_FEMALE: Array[String] = [
	"Bess", "Dara", "Greta", "Isolde", "Kira", "Mabel",
	"Opal", "Rosa", "Tilda", "Vera", "Yara", "Freya",
]
const FALLBACK_MALE: Array[String] = [
	"Aldo", "Cormac", "Edwin", "Fen", "Hobb", "Jarek",
	"Lomax", "Nol", "Pip", "Sten", "Ulf", "Wick",
]
const _GIVEN := &"names_given"

static var _female: Array[String] = []
static var _male: Array[String] = []
static var _read := false


## A NAME FOR SOMEBODY NEW in `town` (null for nobody's), drawn by sex so it
## reads with their model.
static func pick(female: bool, town: Variant) -> String:
	var pool := names(female)
	var given := _given(town)
	var chosen := pool[randi() % pool.size()]
	for i in TRIES:
		if not given.has(chosen):
			break
		chosen = pool[randi() % pool.size()]
	given[chosen] = true
	return chosen


## A NAME THE TOWN ALREADY HAS: somebody walking in off the road under the
## name they left with.
static func claim(town: Variant, said: String) -> void:
	_given(town)[said] = true


## SOMEBODY BROUGHT BACK from a save or from years away, under the name they
## had, in place of the `placeholder` they were given on arrival. Kept, unless
## their town has already given it to somebody else: a town saved when there
## were twelve names a sex is full of repeats, and its second Pip is named
## afresh as it comes back. The first keeps his.
static func bring_back(town: Variant, placeholder: String, said: String, female: bool) -> String:
	var given := _given(town)
	given.erase(placeholder)
	if said == "" or given.has(said):
		return pick(female, town)
	given[said] = true
	return said


## EVERY NAME A TOWN HAS GIVEN, forgotten: its people are about to be replaced
## wholesale by the roster it saved, and the founders being sent away were
## never really there.
static func forget(town: Variant) -> void:
	if town != null and is_instance_valid(town) and (town as Node).has_meta(_GIVEN):
		(town as Node).remove_meta(_GIVEN)


## Every name there is for one sex, read from the file once.
static func names(female: bool) -> Array[String]:
	if not _read:
		_read_file()
	return _female if female else _male


## The names a town has given. Untyped until it is known to be there: a freed
## town handed to a parameter typed as a class is the error, before any guard.
static func _given(town: Variant) -> Dictionary:
	if town == null or not is_instance_valid(town):
		return {}
	var place := town as Node
	if not place.has_meta(_GIVEN):
		place.set_meta(_GIVEN, {})
	return place.get_meta(_GIVEN)


static func _read_file() -> void:
	_read = true
	_female.clear()
	_male.clear()
	if FileAccess.file_exists(FILE):
		var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if read is Dictionary:
			for said: Variant in (read as Dictionary).get("female", []):
				_female.append(String(said))
			for said: Variant in (read as Dictionary).get("male", []):
				_male.append(String(said))
	if _female.is_empty() or _male.is_empty():
		push_warning("VillagerNames: no names in %s — using the old twelve." % FILE)
		_female.assign(FALLBACK_FEMALE)
		_male.assign(FALLBACK_MALE)
