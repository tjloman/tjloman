class_name VillagerNames
extends RefCounted
## A NAME FOR EVERY VILLAGER, in their town's own tongue, and not one their
## town has given already.
##
## There were twelve names for each sex, written into the villager, so every
## town in the world was full of Pips and Lomaxes. The names live in
## data/villager_names.json now: a few thousand, from the lists in
## tools/villager_names.py, which writes the file and checks it. Add a name
## there, not here.
##
## EACH TOWN NAMES ITS PEOPLE IN A TONGUE OF ITS OWN, Norse or Persian or
## Greek, chosen from its name, so the next valley over sounds like somewhere
## else; a colony keeps its mother town's. Most of a town's children are named
## in it, and the rest from anywhere, as travellers and marriages would have
## it. A big town that has used up its own tongue's names goes on in anybody's.
##
## A TOWN REMEMBERS WHAT IT HAS CALLED ITS PEOPLE (a set kept on the town node
## itself, so it goes when the town does) and draws again rather than hand out
## a name it has used. Nobody new is named after the dead, either, which is how
## a small place would have it.

## WHERE THE NAMES LIVE. Shipped by the export's "*.json" include filter.
const FILE := "res://data/villager_names.json"
## How many draws a town makes for a name it has not used before it looks
## further afield. A town has used a few hundred of two thousand at most, so
## the first draw nearly always does.
const TRIES := 8
## The share of a town's children named in its own tongue.
const OWN_SHARE := 0.85
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
## id -> {"title": String, "female": Array[String], "male": Array[String]}
static var _tongues := {}
static var _read := false


## A NAME FOR SOMEBODY NEW in `town` (null for nobody's), drawn by sex so it
## reads with their model: in the town's own tongue most of the time, and in
## anybody's when the town has none of its own left.
static func pick(female: bool, town: Variant) -> String:
	var given := _given(town)
	var chosen := ""
	var own := _own(town, female)
	if not own.is_empty() and randf() < OWN_SHARE:
		chosen = _fresh(own, given)
	if chosen == "":
		chosen = _fresh(names(female), given)
	if chosen == "":
		var pool := names(female)
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


## THE TONGUE A TOWN NAMES ITS PEOPLE IN, chosen from the first word of its
## name, so it is the same on every load and a colony ("Ashford II") speaks as
## its mother town does. Each tongue scores the name and the best one wins
## (rendezvous hashing): adding a tongue moves only the towns that would
## rather have it. "" when there are no tongues, or no town.
static func tongue_of(town: Variant) -> String:
	if not _read:
		_read_file()
	if town == null or not is_instance_valid(town) or _tongues.is_empty():
		return ""
	var place := town as Node
	var called: Variant = place.get(&"village_name")
	var root := (String(called) if called != null else String(place.name)).get_slice(" ", 0)
	var best := ""
	var top := -1
	for id: String in _tongues:
		var score := (root + "|" + id).hash()
		if score > top:
			top = score
			best = id
	return best


## What the totem calls a town's tongue: "Norse", "Persian, Armenian and
## Georgian".
static func tongue_title(town: Variant) -> String:
	var id := tongue_of(town)
	return String(_tongues[id]["title"]) if _tongues.has(id) else "anybody's"


## The names of one sex in one tongue.
static func in_tongue(id: String, female: bool) -> Array[String]:
	if not _read:
		_read_file()
	if not _tongues.has(id):
		return []
	return _tongues[id]["female" if female else "male"]


static func _own(town: Variant, female: bool) -> Array[String]:
	var id := tongue_of(town)
	if id == "":
		return []
	return in_tongue(id, female)


## A name from `pool` that is not in `given`, or "" after TRIES draws.
static func _fresh(pool: Array[String], given: Dictionary) -> String:
	for i in TRIES:
		var one := pool[randi() % pool.size()]
		if not given.has(one):
			return one
	return ""


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
	_tongues.clear()
	if FileAccess.file_exists(FILE):
		var read: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if read is Dictionary:
			for row: Variant in (read as Dictionary).get("tongues", []):
				if row is Dictionary:
					_take_tongue(row)
	if _female.is_empty() or _male.is_empty():
		push_warning("VillagerNames: no names in %s — using the old twelve." % FILE)
		_tongues.clear()
		_female.assign(FALLBACK_FEMALE)
		_male.assign(FALLBACK_MALE)


static func _take_tongue(row: Dictionary) -> void:
	var women: Array[String] = []
	var men: Array[String] = []
	for said: Variant in row.get("female", []):
		women.append(String(said))
	for said: Variant in row.get("male", []):
		men.append(String(said))
	if women.is_empty() or men.is_empty():
		return
	_tongues[String(row.get("id", ""))] = {"title": String(row.get("title", "")),
		"female": women, "male": men}
	_female.append_array(women)
	_male.append_array(men)
