class_name VillageCharter
extends RefCounted
## WHAT EVERY VILLAGER IS DOING ON THE FIRST FRAME, decided before the game
## ever ran.
##
## A village is founded with fifty souls, none of whom has a job — so on the
## first frame all fifty ask the board what the town needs, and the board gives
## all fifty the same answer, because none of them has acted yet. They sort it
## out eventually, badly, by taking jobs and dropping them. A town of two
## hundred does it two hundred times over while the player watches.
##
## THE DECISION ENGINE IS NOT FOR THIS. It is there so that a village RESPONDS
## — to a wolf, to a fire, to a fieldful of crops going up, to the creature
## walking through the square, to a hand reaching down and picking somebody up.
## Deriving the ordinary running of a town from first principles, fifty times,
## is work nobody asked it to do and it is most of what a crowded village costs.
##
## So the ordinary running of a town is decided OFFLINE — see tools/charters.py,
## which rolls a hundred thousand ways to divide a village's hands between its
## trades, runs each through a model of the economy built out of this game's own
## constants, and keeps the hundred and twenty-eight that come out fed, housed,
## growing and steady. A founding village rolls one of those and deals it out.
## The live logic takes over from there and handles everything that happens.
##
## WHICH IS ALSO WHY EVERY TOWN HAS A CHARACTER. The winners are not all alike:
## some are tillage, some are stone, some live by the chase. A village founded
## under `husbandry` really does keep more beasts than its neighbour, for the
## whole of its life, because that is how its hands were dealt on day one.

## WHERE THE ROLLED CHARTERS LIVE.
const FILE := "res://data/village_charters.json"

## AND ONE BAKED IN, for the day the file is missing — an export that dropped
## it, a checkout that never ran the tool. A village must always be able to be
## founded. These are the shares of the best charter at the time of writing,
## and the file is what is actually used.
const FALLBACK := {
	"name": "tillage",
	"mix": {
		"farm": 0.19, "hunt": 0.22, "chop": 0.16, "quarry": 0.13,
		"build": 0.04, "build_farm": 0.08, "tame": 0.12, "rest": 0.06,
	},
}

## HOW LONG A CALLING LASTS — how many times a villager may go back to the trade
## it was dealt before it stops to reconsider the whole town. Six is most of a
## working day at this game's pace: long enough that a farmer farms rather than
## re-deciding after every harvest, short enough that a town still reshapes
## itself over an afternoon.
const CALLING_HOLDS := 6

## And the spread on their first task, in seconds. Without it a dealt village
## finishes its first jobs together and stages exactly the storm this exists to
## prevent, one shift later.
const STAGGER := 9.0

static var _rolled: Array = []
static var _looked := false


## THE CHARTERS, read once. An empty file, a missing one or a malformed one all
## come back as the single baked-in row rather than as an error: this is called
## while a village is being built, and a town that cannot be founded is a worse
## outcome than a town founded under a charter nobody tuned.
static func all() -> Array:
	if _looked:
		return _rolled
	_looked = true
	_rolled = []
	if ResourceLoader.exists(FILE) or FileAccess.file_exists(FILE):
		var text := FileAccess.get_file_as_string(FILE)
		if text != "":
			var read: Variant = JSON.parse_string(text)
			if read is Dictionary and (read as Dictionary).has("charters"):
				for row: Variant in (read as Dictionary)["charters"]:
					if row is Dictionary and (row as Dictionary).has("mix"):
						_rolled.append(row)
	if _rolled.is_empty():
		push_warning("VillageCharter: no charters in %s — using the baked-in one."
			% FILE)
		_rolled = [FALLBACK]
	return _rolled


## One of them, at random.
static func roll() -> Dictionary:
	var rows := all()
	return rows[randi() % rows.size()]


## DEAL A FOUNDING VILLAGE ITS WORK, in one pass over the roster.
##
## Everybody who can work is handed a trade in the charter's proportions and put
## straight into it — no scoring, no board, and nothing asked of the job system
## except whether a post is free. Children are left alone: school and following
## their mother are not jobs and the ordinary path handles them in one step.
##
## Returns the charter's name, for the town to remember itself by.
static func deal(town: Village) -> String:
	var charter := roll()
	var mix: Dictionary = charter.get("mix", {})
	var folk := town.my_villagers().duplicate()
	folk.shuffle()
	var adults: Array[Villager] = []
	for v in folk:
		var who := v as Villager
		if who != null and is_instance_valid(who) and who.is_adult():
			adults.append(who)
	var queue := _slots(town, mix, adults.size())
	for i in adults.size():
		var who := adults[i]
		var job: String = queue[i] if i < queue.size() else "rest"
		_put_to_work(town, who, job)
	return String(charter.get("name", "tillage"))


## THE ORDER THEY ARE DEALT IN. A list of job names, one per pair of hands,
## capped by what the town actually has room for — so a charter that asks for
## nine farmers on one field gets two, and the other seven fall to leisure
## rather than queueing for a post that does not exist.
static func _slots(town: Village, mix: Dictionary, hands: int) -> Array[String]:
	var queue: Array[String] = []
	for job: String in mix:
		if job == "rest":
			continue
		var want := int(round(float(mix[job]) * float(hands)))
		var room := VillageJobs.room_for(town, job)
		for i in mini(want, room):
			queue.append(job)
	queue.shuffle()   # so the trades are not dealt out in dictionary order
	while queue.size() < hands:
		queue.append("rest")
	return queue


## ONE PERSON, INTO ONE TRADE. `rest` goes through VillageJobs.idle, which is
## the same door an idle villager uses in play — there is no separate notion of
## "founding leisure", and there should not be.
static func _put_to_work(town: Village, who: Villager, job: String) -> void:
	who.calling = job
	who.calling_left = CALLING_HOLDS
	if job == "rest":
		VillageJobs.idle(who)
	else:
		who._start_job(job)
		# AND THE PLACE IS ONLY HELD IF THE WORK WAS ACTUALLY TAKEN UP.
		# `_start_job` gives up and wanders when what it went for is not there —
		# no tree in reach, no spot to break a field on — and a place held by
		# somebody wandering is a place nobody else can have. This is the same
		# rule `_pick_job` keeps, and claiming first broke it at founding, which
		# is the one moment every post in the town is being filled at once.
		if who.current_job() == job:
			VillageJobs.claim(town, job)
			who._held_post = job
		else:
			who.calling = ""
			who.calling_left = 0
	# AND THEY DO NOT ALL FINISH TOGETHER. A village dealt in one frame would
	# otherwise come off its first shift in one frame too, and the storm this
	# exists to prevent would simply arrive one shift late.
	who._action_time += randf() * STAGGER
