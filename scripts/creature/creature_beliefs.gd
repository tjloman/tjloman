class_name CreatureBeliefs
extends RefCounted
## What the creature has come to BELIEVE about the world.
##
## The learned action-values in CreatureMind answer "is this worth doing?".
## This answers the far more interesting question: "worth doing *WHEN*?" — and
## it is what makes one creature genuinely a different person from another.
##
## Three parts work together:
##
##  1. EPISODES. Every deed is remembered with the CIRCUMSTANCES around it —
##     was it hungry, was it alone, were there armed villagers about, was its
##     god watching. Not just "I ate a villager" but "I was starving, in their
##     village, at night, and my god was nowhere near."
##
##  2. CREDIT. Consequences arrive LATE. When something then happens to the
##     creature — a mob drives it off, the god praises it, it is wounded — the
##     blame or credit is spread back over the deeds that led up to it, most to
##     the most recent (an eligibility trace). Nothing says "being chased is
##     caused by eating people": the creature works that out because being
##     chased keeps following having eaten someone.
##
##  3. CONTEXTUAL WEIGHTS. Each action carries a little linear model over the
##     circumstances. Reward teaches it not merely "eating people is bad" but
##     "eating people is bad WHEN ARMED VILLAGERS ARE NEAR" — so the same
##     creature may hunt a lone shepherd and never touch a crowd. Two creatures
##     that lived different lives end up wanting different things in the same
##     moment, which is the whole point.
##
## Beliefs are also stated in plain words (see `creed`) so the player can read
## what their creature has decided about the world.

const VERB_PHRASE := {
	"eat_kin": "eating %s", "eat": "eating %s", "smash": "striking %s",
	"throw": "hurling %s about", "gather": "fetching %s", "tend": "tending %s",
	"play": "playing with %s", "watch": "watching %s", "gift": "gifting %s",
	"rescue": "saving %s", "guard": "guarding %s", "cast": "working %s",
	"flee": "fleeing %s", "fish": "fishing %s", "rest": "resting", "wander": "wandering",
	"soothe": "sitting with %s", "dance": "dancing", "pray": "praying",
	"commune": "standing before %s", "mimic": "copying its god", "lounge": "lounging",
	"run": "running", "sulk": "sulking", "shun": "keeping away from %s",
	"depart": "walking away",
}
## When a thing tends to happen, in plain words — for the world model.
const WHEN_PHRASE := {
	"night": "after dark", "crowd": "among a crowd", "armed": "near armed men",
	"in_village": "in the village", "alone": "when it is alone",
	"hungry": "when it is hungry", "stuffed": "when it is full",
	"tired": "when it is worn out", "afraid": "when it is frightened",
	"hurt": "when it is already wretched", "bored": "when it is restless",
	"predator": "with beasts about", "god_near": "under its god's eye",
	"kin_afraid": "when the people are frightened",
	"kin_hurting": "when the people are suffering",
	"kin_glad": "when the people are glad",
}
const TAG_PHRASE := {
	"mobbed": "brings a mob down on it",
	"hurt": "ends in pain",
	"praised": "pleases its god",
	"scolded": "angers its god",
	"fed": "fills its belly",
	"cheered": "delights the people",
	"feared": "makes the people flee",
	"alone": "leaves it friendless",
	"spent": "leaves it with nothing left",
	"forgiven": "brings it home again",
}


## The circumstances the creature can notice. Keeping this list short and
## meaningful is what keeps the learning fast and the beliefs legible.
## The last three are how OTHER PEOPLE are doing, and they let a belief be
## about somebody else's state rather than only about its own — "the store is
## worth raiding when nobody is frightened yet", "dancing pays when the people
## are already glad". A creature that could only notice its own hunger and the
## hour of the day had a very thin world to be right or wrong about.
const FEATURES := [
	"hungry", "stuffed", "tired", "afraid", "hurt", "bored",
	"crowd", "armed", "predator", "god_near", "in_village", "night", "alone",
	"kin_afraid", "kin_hurting", "kin_glad",
]

## HOW MUCH LIFE IT KEEPS. Forty episodes was about two minutes: enough to
## credit a consequence to its cause and nothing else. Four hundred is most of
## an afternoon, which is the difference between a creature that reacts and one
## that can be REMINDED of something. Episodes are small (a key, sixteen
## small floats, a place and a feeling), so this is tens of kilobytes.
const MEMORY := 400         # episodes kept — its recent life
const TRACE_DECAY := 0.72   # how much less each older deed is blamed
const TRACE_MIN := 0.05     # stop assigning credit below this
const WEIGHT_LR := 0.22     # how fast circumstances reshape a belief
const WEIGHT_CLAMP := 2.5
const BELIEF_LR := 0.25     # how fast an action->consequence rule firms up
const CONFIDENT := 0.45     # a rule this strong is worth acting on / reporting
## RITUAL. How fast "doing this AFTER that went well" firms up, and how strong
## a habit of sequence can get. Kept modest: a ritual should tilt a choice, not
## railroad one, or the creature ends up locked in a loop it cannot break.
const RITUAL_LR := 0.2
const RITUAL_CLAMP := 1.0
const RITUAL_HELD := 0.35   # strong enough to steer, and to be worth reporting

## PLACES. How big a patch of ground counts as one place, and how much of what
## happens there sticks to it. Deliberately coarse: a creature should learn that
## the north woods are bad news, not that one particular square metre is.
const PLACE_SIZE := 18.0
const PLACE_LR := 0.25
const PLACE_MEMORY := 120   # patches remembered; the least-visited go first
const PLACE_HELD := 0.35    # strong enough to steer, and to be worth saying

## LORE — what the world DOES, whoever is watching. Learned separately from what
## its own deeds cause, because most of what happens to anything is not its own
## fault, and a creature that can only explain the world through its own agency
## has a very small world.
const LORE_LR := 0.12
const LORE_HELD := 0.35

## BEING REMINDED. How alike a remembered moment has to be before the present
## brings it back, and how strongly the old feeling returns.
const REMINDS_AT := 0.80
## A memory returns as a WHISPER, never as the original. Being reminded of a
## mauling should colour a moment, not re-inflict it — the shadow has to be
## small enough that standing somewhere unpleasant builds dread over half a
## minute rather than flooring the creature the instant it arrives.
const REMINDS_MOST := 0.14
const RECALL_SAMPLE := 26   # episodes actually looked at — memory stays cheap

## "verb|type" -> {feature -> weight}. The contextual half of its wants.
var weights := {}
## "verb|type>consequence" -> -1..1 confidence that the deed brings that about.
var rules := {}
## Its recent life, newest last: {key, ctx, at}
var episodes: Array = []
## RITUALS. "did this>then this" -> -1..1: how well that ORDER has gone. This
## is the whole of how habit and superstition form. Nothing decides which
## sequences are meaningful; the creature simply notices that when it fishes
## and THEN works a miracle, things tend to go well, and starts fishing first.
## It is very often wrong about why, which is exactly what a ritual is.
var sequences := {}

## A MEMORY OF GROUND. Patch of land -> {good, bad, visits}. Nothing decides
## which places matter; the creature simply notices that things keep going badly
## in the same stretch of wood, and starts giving it a wide berth.
var places := {}
## WHAT THE WORLD IS LIKE, quite apart from anything it does. "circumstance>what
## happened" -> -1..1. This is where "wolves come at night", "crowds mean
## trouble" and "the village is where I am fed" actually live — and none of them
## is written down anywhere, they are all just what kept happening.
var lore := {}

var _trace: Array = []      # recent keys awaiting a consequence, newest first
var _previous := ""         # the deed before this one, for learning sequences
var _last_step := ""        # the "prev>next" pair the next outcome will judge


## What this action is worth GIVEN the circumstances — the contextual opinion
## laid over the flat one the mind already holds.
func bias(key: String, ctx: Dictionary) -> float:
	if not weights.has(key):
		return 0.0
	var w: Dictionary = weights[key]
	var sum := 0.0
	for f: String in w:
		sum += float(w[f]) * float(ctx.get(f, 0.0))
	return clampf(sum, -3.0, 3.0)


## Remember doing something, everything that was true at the time, WHERE it was
## and HOW IT FELT. The place and the feeling are what turn a log of deeds into
## something that can be recalled: a creature standing on the spot where it was
## once mobbed, hungry and alone at night, gets a shadow of that back (see
## `reminder`), and it will never be able to say why it does not like it here.
func remember(key: String, ctx: Dictionary, where := Vector3.INF, felt := "") -> void:
	episodes.append({
		"key": key, "ctx": ctx.duplicate(), "at": Time.get_ticks_msec(),
		"place": patch(where), "felt": felt, "worth": 0.0,
	})
	if episodes.size() > MEMORY:
		episodes.pop_front()
	_trace.push_front({"key": key, "ctx": ctx.duplicate()})
	if _trace.size() > 8:
		_trace.pop_back()
	# Note the ORDER, not just the deed. Whatever happens next will judge the
	# pairing, and a pairing that keeps going well becomes a ritual.
	_last_step = (_previous + ">" + key) if _previous != "" else ""
	_previous = key


## An outcome landed. Spread it back over the deeds that led here — the most
## recent bearing most of the blame — and teach each one which CIRCUMSTANCES
## made it turn out this way.
func credit(reward: float) -> void:
	var share := 1.0
	for step: Dictionary in _trace:
		if share < TRACE_MIN:
			break
		_learn(step["key"], step["ctx"], reward * share)
		share *= TRACE_DECAY
	# The episodes that led here find out how they turned out, which is what
	# makes them worth being reminded of later.
	var back := mini(_trace.size(), episodes.size())
	for i in back:
		var ep: Dictionary = episodes[episodes.size() - 1 - i]
		ep["worth"] = clampf(float(ep.get("worth", 0.0)) + reward * pow(TRACE_DECAY, i),
			-3.0, 3.0)
	# And so does the GROUND it happened on. A creature that keeps coming off
	# badly in the same stretch of wood learns to give it a wide berth without
	# ever knowing what is wrong with the place.
	if not episodes.is_empty():
		_mark_place(episodes[episodes.size() - 1].get("place", ""), reward)
	# And the ORDER gets its share of the credit too.
	if _last_step != "":
		var held: float = float(sequences.get(_last_step, 0.0))
		sequences[_last_step] = clampf(
			held + RITUAL_LR * (clampf(reward, -1.0, 1.0) - held),
			-RITUAL_CLAMP, RITUAL_CLAMP)


## HOW RIGHT THIS FEELS RIGHT NOW, given what it just did. A creature that has
## found fishing-then-miracles rewarding will reach for a miracle after fishing
## and not otherwise — and it will never be able to tell you why. Ritual is
## also what keeps a life from flattening into whichever single deed scores
## best: the order matters, so the order gives the days a shape.
func ritual_bias(previous: String, key: String) -> float:
	if previous == "" or sequences.is_empty():
		return 0.0
	return float(sequences.get(previous + ">" + key, 0.0))


## The habits of order it has actually formed, in plain words.
func rites(limit := 2) -> Array:
	var held := []
	for step: String in sequences:
		if float(sequences[step]) < RITUAL_HELD:
			continue
		held.append({"step": step, "strength": float(sequences[step])})
	held.sort_custom(func(a, b): return a["strength"] > b["strength"])
	var said := []
	for entry: Dictionary in held.slice(0, limit):
		var pair: PackedStringArray = String(entry["step"]).split(">")
		if pair.size() == 2:
			said.append("likes to %s before it %s" % [_plain(pair[0]), _plain(pair[1])])
	return said


## "cast|heal" -> "works a heal". Just enough grammar to read as a sentence.
func _plain(key: String) -> String:
	var act := key.split("|")
	var verb: String = act[0]
	var subject: String = act[1] if act.size() > 1 else ""
	if subject == "" or subject == "none":
		return verb + "s"
	return "%ss %s" % [verb, subject]


## Something notable happened TO the creature (a mob drove it off, its god
## praised it, it was wounded). Blame the recent past for it, and firm up the
## rule "doing X brings Y about" for whatever it was lately doing.
func consequence(tag: String, reward: float) -> void:
	credit(reward)
	# WHAT THE WORLD IS LIKE. Quite apart from blaming its own deeds, it notes
	# that this sort of thing happens in this sort of moment — at night, in a
	# crowd, when the people are already frightened. Most of what happens to
	# anything is not its own fault, and this is the half of its picture of the
	# world that has nothing to do with its own agency.
	if not _trace.is_empty():
		_learn_lore(_trace[0]["ctx"], tag, reward)
	var share := 1.0
	for step: Dictionary in _trace:
		if share < TRACE_MIN:
			break
		var rule: String = String(step["key"]) + ">" + tag
		var target: float = signf(reward)
		rules[rule] = clampf(
			float(rules.get(rule, 0.0)) + BELIEF_LR * share * (target - float(rules.get(rule, 0.0))),
			-1.0, 1.0)
		share *= TRACE_DECAY


## A deed happened and the expected consequence did NOT follow: weaken the
## rule. This is how a creature UNLEARNS a superstition, and it is why beliefs
## have to be able to fade as well as firm up.
func disconfirm(key: String, tag: String) -> void:
	var rule := key + ">" + tag
	if not rules.has(rule):
		return
	rules[rule] = clampf(float(rules[rule]) * 0.82, -1.0, 1.0)
	if absf(float(rules[rule])) < 0.04:
		rules.erase(rule)


## Teach one deed which circumstances made it go well or badly.
func _learn(key: String, ctx: Dictionary, reward: float) -> void:
	if not weights.has(key):
		weights[key] = {}
	var w: Dictionary = weights[key]
	# Delta rule: push the weights of the features that were PRESENT toward the
	# reward, so the lesson attaches to the circumstances, not the deed alone.
	var predicted := bias(key, ctx)
	var error := reward - predicted
	for f: String in FEATURES:
		var present := float(ctx.get(f, 0.0))
		if present == 0.0:
			continue
		w[f] = clampf(float(w.get(f, 0.0)) + WEIGHT_LR * error * present,
			-WEIGHT_CLAMP, WEIGHT_CLAMP)


## Does it expect this deed to bring this consequence about? Used to let it act
## on its beliefs — hesitating over what it thinks will end badly.
func expects(key: String, tag: String) -> float:
	return float(rules.get(key + ">" + tag, 0.0))


## The dread this deed carries from everything it has learned to expect of it.
## Negative rules (this ends badly) pull it back; that is a belief in action.
func foreboding(key: String) -> float:
	var total := 0.0
	for rule: String in rules:
		if rule.begins_with(key + ">"):
			total += minf(float(rules[rule]), 0.0)
	return clampf(total, -2.0, 0.0)


## A MEMORY OF GROUND -----------------------------------------------------------

## Which patch of the world a spot belongs to. Coarse on purpose: a creature
## should learn that the north woods are bad news, not that one square metre is.
func patch(where: Vector3) -> String:
	if where == Vector3.INF:
		return ""
	return "%d,%d" % [floori(where.x / PLACE_SIZE), floori(where.z / PLACE_SIZE)]


func _mark_place(place: String, reward: float) -> void:
	if place == "":
		return
	if not places.has(place):
		places[place] = {"feel": 0.0, "visits": 0}
		_forget_a_place()
	var known: Dictionary = places[place]
	known["visits"] = int(known["visits"]) + 1
	known["feel"] = clampf(
		float(known["feel"]) + PLACE_LR * (clampf(reward, -1.5, 1.5) - float(known["feel"])),
		-1.5, 1.5)


## Full up: drop wherever it has been least, since a place visited once is a
## place it has barely learned anything about.
func _forget_a_place() -> void:
	if places.size() <= PLACE_MEMORY:
		return
	var dullest := ""
	var fewest := 1 << 30
	for place: String in places:
		var visits := int(places[place]["visits"])
		if visits < fewest:
			fewest = visits
			dullest = place
	if dullest != "":
		places.erase(dullest)


## HOW IT FEELS ABOUT WHERE IT IS STANDING, -1.5..+1.5. Somewhere it has come
## off badly again and again is somewhere it would rather not be, and that
## colours everything it might do here.
func place_feel(where: Vector3) -> float:
	var known: Dictionary = places.get(patch(where), {})
	if known.is_empty() or int(known.get("visits", 0)) < 3:
		return 0.0   # one bad afternoon is not knowledge of a place
	return float(known.get("feel", 0.0))


## WHAT THE WORLD IS LIKE ---------------------------------------------------------

## Note that this sort of thing happens in this sort of moment. Learned from
## whatever was true when the world last did something notable.
func _learn_lore(ctx: Dictionary, tag: String, reward: float) -> void:
	var target := signf(reward)
	for f: String in FEATURES:
		var present := float(ctx.get(f, 0.0))
		if present < 0.4:
			continue
		var key := f + ">" + tag
		lore[key] = clampf(
			float(lore.get(key, 0.0)) + LORE_LR * present * (target - float(lore.get(key, 0.0))),
			-1.0, 1.0)


## WHAT IT EXPECTS OF THE WORLD RIGHT NOW, before it has done anything at all.
## Negative means it expects this to be a bad sort of moment. This is dread and
## anticipation that belong to the SITUATION rather than to any deed — the
## difference between "eating people goes badly" and "nights go badly".
func foretaste(ctx: Dictionary) -> float:
	if lore.is_empty():
		return 0.0
	var total := 0.0
	for key: String in lore:
		var f := key.split(">")[0]
		total += float(lore[key]) * float(ctx.get(f, 0.0))
	return clampf(total * 0.35, -1.5, 1.5)


## BEING REMINDED ----------------------------------------------------------------

## Does this moment bring something back? Looks over a sample of its life for a
## strongly-felt episode whose circumstances closely match the present, and
## returns {felt, strength} if one surfaces. A creature standing where it was
## once mobbed — hungry, alone, at night — gets a shadow of that back, and it
## will never be able to say why it does not like it here.
##
## Only a sample is searched, so remembering four hundred moments costs the same
## as remembering forty.
func reminder(ctx: Dictionary, where := Vector3.INF) -> Dictionary:
	if episodes.size() < 8:
		return {}
	var here := patch(where)
	var best := {}
	var closest := REMINDS_AT
	var count := episodes.size()
	var looked := mini(RECALL_SAMPLE, count)
	for i in looked:
		# Half from the recent past, half sampled from the whole of its life, so
		# an old shock is still reachable long after the day it happened.
		@warning_ignore("integer_division")
		var idx := count - 1 - i if i < looked / 2 else randi() % count
		var ep: Dictionary = episodes[idx]
		var felt: String = String(ep.get("felt", ""))
		if felt == "" or absf(float(ep.get("worth", 0.0))) < 0.6:
			continue
		var likeness := _likeness(ctx, ep["ctx"])
		if here != "" and String(ep.get("place", "")) == here:
			likeness += 0.12   # and standing in the very spot brings it back harder
		if likeness > closest:
			closest = likeness
			best = {"felt": felt, "strength": clampf(
				(likeness - REMINDS_AT) * 3.0 * absf(float(ep["worth"])) / 3.0,
				0.01, REMINDS_MOST)}
	return best


## How alike two moments are, 0..1 — one minus the average difference across
## every circumstance it can notice.
func _likeness(a: Dictionary, b: Dictionary) -> float:
	var diff := 0.0
	for f: String in FEATURES:
		diff += absf(float(a.get(f, 0.0)) - float(b.get(f, 0.0)))
	return clampf(1.0 - diff / float(FEATURES.size()), 0.0, 1.0)


## Slow forgetting, so old convictions loosen if life stops confirming them.
func fade() -> void:
	for step: String in sequences:
		sequences[step] = move_toward(float(sequences[step]), 0.0, 0.0012)
	for key: String in lore:
		lore[key] = move_toward(float(lore[key]), 0.0, 0.0008)
	for place: String in places:
		places[place]["feel"] = move_toward(float(places[place]["feel"]), 0.0, 0.0006)
	for key: String in weights:
		var w: Dictionary = weights[key]
		for f: String in w:
			w[f] = move_toward(float(w[f]), 0.0, 0.0015)


## WHAT IT BELIEVES, in plain words — so the player can actually read the
## creature's mind. Returns the strongest convictions it currently holds.
func creed(limit := 3) -> Array:
	var held := []
	for rule: String in rules:
		var strength: float = float(rules[rule])
		if absf(strength) < CONFIDENT:
			continue
		held.append({"rule": rule, "strength": strength})
	held.sort_custom(func(a, b): return absf(a["strength"]) > absf(b["strength"]))
	var said := []
	for entry: Dictionary in held.slice(0, limit):
		said.append(_phrase(entry["rule"], entry["strength"]))
	return said


## WHAT IT EXPECTS OF THE WORLD, in plain words — the half of its picture that
## has nothing to do with its own deeds. "Expects trouble after dark." "Expects
## to be fed among the people."
func omens(limit := 2) -> Array:
	var held := []
	for key: String in lore:
		if absf(float(lore[key])) >= LORE_HELD:
			held.append({"key": key, "strength": float(lore[key])})
	held.sort_custom(func(a, b): return absf(a["strength"]) > absf(b["strength"]))
	var said := []
	for entry: Dictionary in held.slice(0, limit):
		var pair: PackedStringArray = String(entry["key"]).split(">")
		if pair.size() != 2:
			continue
		var when: String = WHEN_PHRASE.get(pair[0], "sometimes")
		var what: String = TAG_PHRASE.get(pair[1], "something happens")
		said.append("expects that %s, the world %s" % [when, what])
	return said


## THE PLACES IT HAS FEELINGS ABOUT, in plain words. It cannot name them, so
## they are described by how it feels about them and how often it has been.
func haunts(limit := 2) -> Array:
	var held := []
	for place: String in places:
		var known: Dictionary = places[place]
		if int(known["visits"]) < 3 or absf(float(known["feel"])) < PLACE_HELD:
			continue
		held.append({"place": place, "feel": float(known["feel"]), "visits": int(known["visits"])})
	held.sort_custom(func(a, b): return absf(a["feel"]) > absf(b["feel"]))
	var said := []
	for entry: Dictionary in held.slice(0, limit):
		said.append("%s a stretch of country it has crossed %d times" % [
			"loves" if float(entry["feel"]) > 0.0 else "will not go near",
			int(entry["visits"])])
	return said


## Turn "eat_kin|villager>mobbed" into something a person can read.
func _phrase(rule: String, strength: float) -> String:
	var halves := rule.split(">")
	var act := halves[0].split("|")
	var verb: String = act[0]
	var subject: String = act[1] if act.size() > 1 else "things"
	var tag: String = halves[1] if halves.size() > 1 else "trouble"
	var sure := "is sure" if absf(strength) > 0.75 else "suspects"
	# Some phrases name what was acted upon ("eating %s") and some do not
	# ("wandering"), and a verb it has learned that we never wrote a phrase for
	# falls back to the bare word. Only the ones with a slot get the subject.
	var doing: String = VERB_PHRASE.get(verb, verb + " %s")
	if doing.contains("%s"):
		doing = doing % subject
	var outcome: String = TAG_PHRASE.get(tag, "leads somewhere")
	return "%s that %s %s" % [sure, doing, outcome]


## Persistence -----------------------------------------------------------------

## Everything it has concluded about the world. The distilled knowledge
## (weights and rules) is the valuable part; the raw episode log rides along so
## a reloaded creature still "remembers" its recent life.
func to_dict() -> Dictionary:
	return {
		"weights": weights.duplicate(true),
		"rules": rules.duplicate(true),
		"sequences": sequences.duplicate(true),
		"lore": lore.duplicate(true),
		"places": places.duplicate(true),
		# Enough of its recent life to still be reminded of something by the
		# world it wakes up in. The distilled knowledge above is the valuable
		# part; this is what makes a reloaded creature feel continuous.
		"episodes": episodes.slice(maxi(episodes.size() - 80, 0)),
	}


func from_dict(data: Dictionary) -> void:
	weights = (data.get("weights", {}) as Dictionary).duplicate(true)
	rules = (data.get("rules", {}) as Dictionary).duplicate(true)
	sequences = (data.get("sequences", {}) as Dictionary).duplicate(true)
	lore = (data.get("lore", {}) as Dictionary).duplicate(true)
	places = (data.get("places", {}) as Dictionary).duplicate(true)
	episodes = (data.get("episodes", []) as Array).duplicate(true)
	_trace.clear()

