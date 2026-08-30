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
}


## The circumstances the creature can notice. Keeping this list short and
## meaningful is what keeps the learning fast and the beliefs legible.
const FEATURES := [
	"hungry", "stuffed", "tired", "afraid", "hurt", "bored",
	"crowd", "armed", "predator", "god_near", "in_village", "night", "alone",
]

const MEMORY := 40          # episodes kept — its recent life
const TRACE_DECAY := 0.72   # how much less each older deed is blamed
const TRACE_MIN := 0.05     # stop assigning credit below this
const WEIGHT_LR := 0.22     # how fast circumstances reshape a belief
const WEIGHT_CLAMP := 2.5
const BELIEF_LR := 0.25     # how fast an action->consequence rule firms up
const CONFIDENT := 0.45     # a rule this strong is worth acting on / reporting

## "verb|type" -> {feature -> weight}. The contextual half of its wants.
var weights := {}
## "verb|type>consequence" -> -1..1 confidence that the deed brings that about.
var rules := {}
## Its recent life, newest last: {key, ctx, at}
var episodes: Array = []

var _trace: Array = []      # recent keys awaiting a consequence, newest first


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


## Remember doing something, and everything that was true at the time.
func remember(key: String, ctx: Dictionary) -> void:
	episodes.append({"key": key, "ctx": ctx.duplicate(), "at": Time.get_ticks_msec()})
	if episodes.size() > MEMORY:
		episodes.pop_front()
	_trace.push_front({"key": key, "ctx": ctx.duplicate()})
	if _trace.size() > 8:
		_trace.pop_back()


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


## Something notable happened TO the creature (a mob drove it off, its god
## praised it, it was wounded). Blame the recent past for it, and firm up the
## rule "doing X brings Y about" for whatever it was lately doing.
func consequence(tag: String, reward: float) -> void:
	credit(reward)
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


## Slow forgetting, so old convictions loosen if life stops confirming them.
func fade() -> void:
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
		"episodes": episodes.slice(maxi(episodes.size() - 12, 0)),
	}


func from_dict(data: Dictionary) -> void:
	weights = (data.get("weights", {}) as Dictionary).duplicate(true)
	rules = (data.get("rules", {}) as Dictionary).duplicate(true)
	episodes = (data.get("episodes", []) as Array).duplicate(true)
	_trace.clear()

