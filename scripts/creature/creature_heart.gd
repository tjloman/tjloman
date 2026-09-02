class_name CreatureHeart
extends RefCounted
## WHAT IT IS FEELING — and how it comes to understand feelings at all.
##
## `mood` was one number from wretched to delighted, which is enough to drive a
## face and nothing else. A number cannot be frightened AND lonely, cannot be
## ashamed while it is also proud of something, and above all cannot be READ OFF
## SOMEBODY ELSE. This holds a dozen named feelings at once, each with its own
## weight and its own rate of cooling: fury burns off in seconds, grief takes
## minutes, loneliness barely fades at all until somebody turns up.
##
## THREE THINGS FALL OUT OF THAT, and the third is the reason for the whole file.
##
##  1. IT SHOWS. The strongest feeling drives the face and the word over its
##     head, so a creature that is quietly grieving looks quietly grieving even
##     while it goes about its business. It is a great deal more communicative
##     than a mood bar.
##
##  2. IT LEARNS ITS OWN HEART. Every so often it notes which feelings it is
##     holding and which CIRCUMSTANCES are true at the time, and slowly builds
##     up an account of what being hungry, or hurt, or alone in the dark is
##     actually like — for it. Nothing is written down in advance. A creature
##     that has never gone hungry has no idea what hunger feels like.
##
##  3. AND SO IT CAN READ OTHERS. Empathy here is not a rule that says "sad
##     villagers deserve pity". It is the creature taking what it knows about
##     ITS OWN circumstances and applying it to somebody else's: it looks at a
##     starving man, recognises the circumstance, remembers what that
##     circumstance feels like, and feels a shadow of it. Which means — and this
##     is the part worth keeping — A CREATURE CANNOT PITY A HUNGER IT HAS NEVER
##     FELT. Empathy has to be paid for in experience, exactly as it is in life.
##
## The reading is imperfect on purpose. It maps other people's plights through
## its own history, so a beast that was beaten every time it went near the
## village will read a perfectly happy crowd as menacing. It is not a sensor.

## THE FEELINGS IT CAN HAVE. `face` is the expression each wears, `pleasure` is
## how good or bad it is to hold (which is what drags mood about), `cool` is how
## much of it burns off per second, and `word` is what floats over its head.
## `cool` is how much burns off per second, so 1/cool is roughly how many
## seconds one full stir of it survives. The quick feelings are gone inside half
## a minute; the heavy ones are still there twenty minutes later, which is the
## whole reason for holding them separately from a mood bar.
const FEELINGS := {
	"delight": {"face": "happy", "pleasure": 1.0, "cool": 0.033, "word": "!"},
	"contentment": {"face": "neutral", "pleasure": 0.5, "cool": 0.011, "word": "~"},
	"affection": {"face": "love", "pleasure": 0.9, "cool": 0.008, "word": "<3"},
	"pride": {"face": "happy", "pleasure": 0.8, "cool": 0.017, "word": "hah!"},
	"wonder": {"face": "curious", "pleasure": 0.4, "cool": 0.050, "word": "oh?"},
	"relief": {"face": "happy", "pleasure": 0.6, "cool": 0.022, "word": "phew"},
	# The heavy ones cool slowest. A creature should still be carrying last
	# night's grief around at noon — a quarter of an hour of game time, which at
	# this clock is most of a village afternoon.
	"loneliness": {"face": "sad", "pleasure": -0.4, "cool": 0.002, "word": "..."},
	"grief": {"face": "sad", "pleasure": -0.9, "cool": 0.0033, "word": "oh..."},
	"shame": {"face": "hurt", "pleasure": -0.7, "cool": 0.008, "word": "sorry"},
	"pity": {"face": "sad", "pleasure": -0.3, "cool": 0.017, "word": "oh no"},
	# And rage is the shortest-lived thing in here, which is why a creature that
	# wrecks a store in a temper is dancing on the ruins an hour later.
	"fury": {"face": "angry", "pleasure": -0.3, "cool": 0.050, "word": "RRR"},
	"dread": {"face": "scared", "pleasure": -0.8, "cool": 0.025, "word": "!!"},
	"pain": {"face": "hurt", "pleasure": -1.0, "cool": 0.033, "word": "ow"},
}

## Plain words for the dashboard, so a player can read the whole heart and not
## merely the loudest part of it.
const SAID := {
	"delight": "delighted", "contentment": "content", "affection": "full of love",
	"pride": "proud of itself", "wonder": "full of wonder", "relief": "relieved",
	"loneliness": "lonely", "grief": "grieving", "shame": "ashamed",
	"pity": "sorry for somebody", "fury": "furious", "dread": "frightened",
	"pain": "in pain",
}

const FELT := 0.18          # below this a feeling is not really being held
const SHOWS := 0.34         # and below this it does not show on the face
## How fast it works out what a circumstance feels like. Slow: this is a
## lifetime's self-knowledge, not a lookup.
const SELF_LR := 0.06
const SELF_CLAMP := 1.0
## EMPATHY. How much of somebody else's read-off feeling it actually catches,
## at full understanding — a shadow, never the whole thing.
const CATCH := 0.30
## Empathy is a skill, and it is earned by paying attention to people. It fades
## if it spends its life alone.
const EMPATHY_GAIN := 0.04
const EMPATHY_FADE := 0.004

## Feeling name -> 0..1, how much of it is being held right now.
var feeling := {}
## WHAT IT KNOWS ABOUT ITSELF: circumstance -> {feeling -> -1..1}. Built up from
## its own life; the only thing it has to go on when reading anyone else.
var self_knowledge := {}
## How good it has become at reading people, 0..1.
var empathy := 0.0


## Feel something. `force` is 0..1 — a whole deed's worth is about 0.6.
func stir(name: String, force: float) -> void:
	if not FEELINGS.has(name) or force <= 0.0:
		return
	feeling[name] = minf(float(feeling.get(name, 0.0)) + force, 1.0)


## Feelings cool at their own rates. Called every frame.
func settle(delta: float) -> void:
	for name: String in feeling:
		var cool: float = float(FEELINGS[name]["cool"]) * delta
		feeling[name] = maxf(float(feeling[name]) - cool, 0.0)
	empathy = maxf(empathy - EMPATHY_FADE * delta, 0.0)


## Paying attention to somebody is how empathy is learned. Called while it
## watches, communes with, or comforts anyone.
func attend(delta: float) -> void:
	empathy = minf(empathy + EMPATHY_GAIN * delta, 1.0)


func level(name: String) -> float:
	return float(feeling.get(name, 0.0))


## The feeling it is holding most of, or "" if it is basically settled.
func strongest() -> String:
	var best := ""
	var best_v := FELT
	for name: String in feeling:
		if float(feeling[name]) > best_v:
			best_v = float(feeling[name])
			best = name
	return best


## How hard it is feeling whatever it is feeling most, 0..1.
func intensity() -> float:
	var name := strongest()
	return 0.0 if name == "" else float(feeling[name])


## The face it is wearing when nothing louder is happening.
func face() -> String:
	var name := strongest()
	if name == "" or float(feeling[name]) < SHOWS:
		return "neutral"
	return String(FEELINGS[name]["face"])


## The word over its head, when it is feeling something strongly enough to say
## anything at all.
func word() -> String:
	var name := strongest()
	if name == "" or float(feeling[name]) < SHOWS:
		return ""
	return String(FEELINGS[name]["word"])


## How pleasant its heart is on the whole, -1..+1 — what drags `mood` about, so
## mood becomes a CONSEQUENCE of what it feels instead of a second bookkeeping.
func balance() -> float:
	var total := 0.0
	for name: String in feeling:
		total += float(FEELINGS[name]["pleasure"]) * float(feeling[name])
	return clampf(total, -1.0, 1.0)


## Its heart in plain words, strongest first — for the dashboard.
func account(limit := 2) -> Array:
	var held := []
	for name: String in feeling:
		if float(feeling[name]) >= FELT:
			held.append(name)
	held.sort_custom(func(a, b): return float(feeling[a]) > float(feeling[b]))
	var said := []
	for name: String in held.slice(0, limit):
		said.append(String(SAID.get(name, name)))
	return said if not said.is_empty() else ["settled"]


## LEARNING WHAT ITS OWN LIFE FEELS LIKE. Given the circumstances that are true
## right now, note what it is feeling in them. Over a life this becomes an
## account of what hunger, darkness, crowds and solitude are like — for it,
## which is the only kind of account anybody has.
func learn(ctx: Dictionary) -> void:
	for f: String in ctx:
		var present := float(ctx[f])
		if present < 0.35:
			continue
		if not self_knowledge.has(f):
			self_knowledge[f] = {}
		var known: Dictionary = self_knowledge[f]
		for name: String in FEELINGS:
			var now := float(feeling.get(name, 0.0))
			# Only circumstances that are actually happening get the credit, and
			# only in proportion to how strongly they are happening.
			known[name] = clampf(
				float(known.get(name, 0.0)) + SELF_LR * present * (now - float(known.get(name, 0.0))),
				-SELF_CLAMP, SELF_CLAMP)


## READING SOMEBODY ELSE. Take their plight — the same vocabulary of
## circumstances it understands about itself — and predict what they must be
## feeling, using nothing but its own history. Circumstances it has never been
## in itself return nothing, which is the whole point: there is no pity
## available for a suffering it has never had.
func read(plight: Dictionary) -> Dictionary:
	var guess := {}
	for f: String in plight:
		var present := float(plight[f])
		if present < 0.3 or not self_knowledge.has(f):
			continue
		var known: Dictionary = self_knowledge[f]
		for name: String in known:
			guess[name] = float(guess.get(name, 0.0)) + float(known[name]) * present
	for name: String in guess:
		guess[name] = clampf(float(guess[name]), 0.0, 1.0)
	return guess


## Catch a shadow of what somebody else is feeling. Their sorrow arrives as
## PITY rather than as sorrow — you feel FOR people, not AS them — while their
## joy simply spreads.
func sympathise(plight: Dictionary, share := 1.0) -> Dictionary:
	var theirs := read(plight)
	if theirs.is_empty() or empathy <= 0.0:
		return theirs
	var caught := CATCH * empathy * share
	for name: String in theirs:
		var strength := float(theirs[name]) * caught
		if strength < 0.01:
			continue
		if float(FEELINGS[name]["pleasure"]) < 0.0:
			stir("pity", strength)
		else:
			stir(name, strength * 0.6)
	return theirs


## Does it know this circumstance from the inside? Used to say honestly when a
## creature simply cannot understand what it is looking at.
func understands(circumstance: String) -> bool:
	if not self_knowledge.has(circumstance):
		return false
	for name: String in self_knowledge[circumstance]:
		if absf(float(self_knowledge[circumstance][name])) > 0.15:
			return true
	return false


## How wide its understanding has grown — the count of circumstances it has
## learned the feel of. A readout of a life's experience.
func wisdom() -> int:
	var count := 0
	for f: String in self_knowledge:
		if understands(f):
			count += 1
	return count


## Persistence -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"feeling": feeling.duplicate(),
		"self_knowledge": self_knowledge.duplicate(true),
		"empathy": empathy,
	}


func from_dict(data: Dictionary) -> void:
	feeling = (data.get("feeling", {}) as Dictionary).duplicate()
	self_knowledge = (data.get("self_knowledge", {}) as Dictionary).duplicate(true)
	empathy = clampf(float(data.get("empathy", 0.0)), 0.0, 1.0)
