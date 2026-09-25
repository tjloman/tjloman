class_name CreatureBonds
extends RefCounted
## WHO IT KNOWS.
##
## Everything else the creature learns is about KINDS: villagers, sheep, houses,
## water. That is the right way round for a mind that has to generalise — one
## bad sheep should teach it something about sheep — but it means the beast can
## live beside the same twenty people for an hour and never once notice that
## they are twenty particular people rather than twenty instances of "villager".
##
## A dog is not like that. A dog knows who you are. It knows which of the family
## feeds it and which one trod on its tail once, and it acts differently toward
## each of them without having any general theory about people at all.
##
## So: a small ledger of INDIVIDUALS, by name. Every dealing with somebody
## nudges its regard for THEM, on top of whatever it thinks about their kind, so
## a creature can adore one shepherd and give another a wide berth while holding
## no opinion whatever about shepherds. That difference is only visible because
## the memory is there to hold it — it is exactly what more memory buys.
##
## Bounded and honest: a few hundred people, and the ones it has barely met are
## forgotten first. It keeps names rather than object references, so the people
## it knows survive a save, a reload, and the world being streamed out from
## under them and back.

const REGARD_LR := 0.28        # how fast one dealing moves its opinion of somebody
const REGARD_CLAMP := 2.0
## A stranger is not a blank: the creature is mildly curious about somebody it
## has never dealt with, which is why it goes and finds out.
const STRANGER := 0.25
const FADE := 0.0008           # per second: people it stops seeing fade to strangers
const KNOWN := 0.5             # strong enough to steer, and to be worth saying
## How many people it can hold. Two hundred is a good deal more than any one
## village, so it can know a whole valley and still forget the drover it passed
## once on the road.
const CAPACITY := 200


## Name -> {regard, met, seen_at}. The whole of who it knows.
var folk := {}

var _last := ""                # who the next outcome is credited to


## What to call somebody, stably enough to survive a save. Only PEOPLE get
## names: to this creature a sheep is a sheep, and that is not a failing of
## its memory but a fair description of a sheep.
## Validity is checked FIRST: a ballot can carry a target that was freed between
## the creature perceiving it and choosing it, and asking a dead object what
## class it is throws.
static func name_of(who_given: Variant) -> String:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(who_given):
		return ""
	var who := who_given as Object
	if who == null or not is_instance_valid(who):
		return ""
	if who is Villager:
		return String((who as Villager).villager_name)
	return ""


## Lay eyes on somebody. Cheap enough to call for everyone in sight.
func meet(who: Object) -> void:
	var name := name_of(who)
	if name == "":
		return
	_ledger(name)["seen_at"] = GameState.clock


## WHAT IT THINKS OF THIS PARTICULAR PERSON, laid on top of what it thinks of
## their kind. Somebody it has never dealt with is mildly interesting.
func regard_for(who: Object) -> float:
	var name := name_of(who)
	if name == "":
		return 0.0
	if not folk.has(name):
		return STRANGER
	return float(folk[name]["regard"])


## About to deal with somebody: whatever happens next is on their account.
func dealing_with(who: Object) -> void:
	_last = name_of(who)
	if _last != "":
		var known := _ledger(_last)
		known["met"] = int(known["met"]) + 1
		known["seen_at"] = GameState.clock


## It went like that. Moves its opinion of whoever the dealing was with — and
## of nobody else, which is the whole point.
func settle(reward: float) -> void:
	if _last == "" or not folk.has(_last):
		return
	var known: Dictionary = folk[_last]
	known["regard"] = clampf(
		float(known["regard"]) + REGARD_LR * (clampf(reward, -2.0, 2.0) - float(known["regard"])),
		-REGARD_CLAMP, REGARD_CLAMP)
	_last = ""


## People it stops having anything to do with slowly become strangers again.
## PEOPLE HE STOPS SEEING FADE TO STRANGERS — but never quite, once he has met
## them often enough. Somebody he has dealt with twice is gone in a week of not
## seeing them; somebody he has dealt with a hundred times is a person he knows
## for the rest of his life, however long they are away. `met` is already the
## count of how often, so the floor costs nothing to keep.
func fade(share: float) -> void:
	for name: String in folk:
		var ledger: Dictionary = folk[name]
		var deep: float = maxf(float(ledger.get("deep", 0.0)),
			absf(float(ledger["regard"])))
		ledger["deep"] = deep
		var least := deep * CreatureKeeping.kept(int(ledger.get("met", 0)))
		if absf(float(ledger["regard"])) <= least:
			continue
		ledger["regard"] = move_toward(float(ledger["regard"]),
			signf(float(ledger["regard"])) * least, FADE * share)


func knows(who: Object) -> bool:
	var name := name_of(who)
	return name != "" and folk.has(name) and int(folk[name]["met"]) >= 3


func count() -> int:
	return folk.size()


## The one it thinks best of, and the one it thinks worst of — in plain words,
## by name, because that is the entire point of knowing people.
func attachments(limit := 2) -> Array:
	var ranked := folk.keys()
	ranked.sort_custom(func(a, b):
		return absf(float(folk[a]["regard"])) > absf(float(folk[b]["regard"])))
	var said := []
	for name: String in ranked:
		var regard := float(folk[name]["regard"])
		if absf(regard) < KNOWN or said.size() >= limit:
			break
		said.append("%s %s" % [
			"is fond of" if regard > 0.0 else "has no time for", name])
	return said


func _ledger(name: String) -> Dictionary:
	if not folk.has(name):
		folk[name] = {"regard": 0.0, "met": 0, "seen_at": GameState.clock}
		_forget_someone()
	return folk[name]


## Full up: forget whoever it has had least to do with, and among those the one
## it has not laid eyes on for longest. A face it barely knows goes first.
func _forget_someone() -> void:
	if folk.size() <= CAPACITY:
		return
	var faintest := ""
	var least := INF
	for name: String in folk:
		# Somebody met often and recently is worth far more than a passing face.
		var worth := float(folk[name]["met"]) * 1000.0 + float(folk[name]["seen_at"])
		if worth < least:
			least = worth
			faintest = name
	if faintest != "":
		folk.erase(faintest)


## Persistence -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return folk.duplicate(true)


## A SAVE MADE BEFORE THE CLOCK EXISTED holds `seen_at` in wall-clock
## milliseconds — numbers in the billions — so every acquaintance in it would
## read as seen far more recently than anybody met since, and the ledger would
## forget the new faces first and keep the old ones forever. Anything ahead of
## the clock is brought back to it; a legitimate value never can be.
func from_dict(data: Dictionary) -> void:
	folk = (data as Dictionary).duplicate(true)
	for name: String in folk:
		var known: Dictionary = folk[name]
		known["seen_at"] = minf(float(known.get("seen_at", 0.0)), GameState.clock)
