class_name CreatureForesight
extends RefCounted
## LOOKING ONE MOVE AHEAD.
##
## Everything else the creature has answers "how did that go?". This is the only
## part that asks "how would that go?" before doing it — and the difference is
## the difference between an animal that learns and an animal that PLANS.
##
## It works by learning what deeds DO to a situation. Not what they are worth:
## what they CHANGE. Eating leaves it less hungry and more full. Smashing a
## house leaves the people frightened and, shortly, armed. Holding court leaves
## it in a crowd. None of that is written down anywhere; each is the running
## average of what actually followed, feature by feature, over the sixteen
## circumstances it can notice.
##
## Then — and this is the part worth keeping — it does not score the imagined
## moment with some separate table of good and bad situations. IT ASKS ITS OWN
## HEART. `CreatureHeart.read` already knows what being hungry, or hurt, or
## alone in the dark FEELS like, because it learned that from living through
## them, and it uses exactly that to guess how other people feel. Pointed at an
## imagined future instead of at a villager, the same faculty tells the creature
## how a moment like that would feel TO IT.
##
## So foresight is empathy aimed forwards, and it costs the same thing: a life.
## A creature that has never been mobbed cannot picture being mobbed and will
## walk into it. A creature that has cannot help picturing it.
##
## THREE HONEST LIMITS, on purpose:
##
##  1. ONE MOVE. There is no search tree. A tree is where a mobile budget goes
##     to die, and it is not needed: the situation it imagines is scored partly
##     by `CreatureBeliefs.foretaste`, which was itself learned from what
##     happened LATER — so consequences further out are already folded into the
##     one step, without ever expanding a node.
##  2. IT ONLY LOOKS WHERE IT HAS BEEN. A deed tried a couple of times predicts
##     nothing, and the prospect is scaled by how much of the deed it has
##     actually seen. Confident nonsense is worse than no opinion.
##  3. IT IS OFTEN WRONG, AND NOTICES. Every prediction is checked against what
##     really happened. The error is SURPRISE, which stirs wonder, sharpens
##     learning, and makes it curious again — a creature whose model of the
##     world just failed should go and look.

## The circumstances it models. Shared with the beliefs so a prediction can be
## fed straight back into everything else that reads a situation.
const FEATURES := CreatureBeliefs.FEATURES

const EFFECT_LR := 0.18       # how fast one outcome reshapes "what this deed does"
const EFFECT_CLAMP := 1.0
## How many times a deed must have been seen before its prediction is worth
## anything, and where the prediction is fully trusted.
const GLIMPSED := 2.0
const LEARNED := 8.0
## How much the imagined future is allowed to sway a choice. Deliberately modest:
## foresight should tip a decision, never replace the wanting.
const WEIGHT := 1.1
## How much the situation's own learned reputation counts next to how it feels.
const OMEN_SHARE := 0.5

## SURPRISE. How wrong the last prediction was, 0..1, and how fast that fades.
const SURPRISE_COOL := 0.35
## A world that keeps confounding it is a world worth poking at.
const CURIOUS_ON_SURPRISE := 0.8

## What a circumstance going UP means, and what it going DOWN means, in words.
const LEAVES_MORE := {
	"hungry": "it hungrier", "stuffed": "its belly full", "tired": "it worn out",
	"afraid": "it frightened", "hurt": "it wretched", "bored": "it restless",
	"crowd": "a crowd about it", "armed": "armed men about",
	"predator": "beasts drawn in", "god_near": "its god close by",
	"in_village": "it among the houses", "night": "the dark come on",
	"alone": "it by itself", "kin_afraid": "the people frightened",
	"kin_hurting": "the people suffering", "kin_glad": "the people glad",
}
const LEAVES_LESS := {
	"hungry": "it fed", "stuffed": "room in its belly", "tired": "it rested",
	"afraid": "its fear behind it", "hurt": "it easier", "bored": "it settled",
	"crowd": "the place emptier", "armed": "the weapons put away",
	"predator": "the beasts driven off", "god_near": "its god far away",
	"in_village": "the houses behind it", "night": "the day come round",
	"alone": "company about", "kin_afraid": "the people calm",
	"kin_hurting": "the people mended", "kin_glad": "the people out of sorts",
}

## "verb|type" -> {feature -> average change it makes}. The whole model.
var effect := {}
## "verb|type" -> how many times it has actually watched that deed play out.
var tried := {}
## How badly the world just wrong-footed it, 0..1.
var surprise := 0.0

var _pending := ""            # the deed whose outcome is still owed
var _before := {}             # the situation it was done in
var _guess := {}              # what it thought would happen


## WHAT IT THINKS THE WORLD WOULD LOOK LIKE afterwards. Base situation plus
## whatever this deed has tended to change, clamped back into 0..1.
func imagine(key: String, ctx: Dictionary) -> Dictionary:
	var next := ctx.duplicate()
	var change: Dictionary = effect.get(key, {})
	if change.is_empty():
		return next
	var trust := confidence(key)
	for f: String in change:
		next[f] = clampf(float(next.get(f, 0.0)) + float(change[f]) * trust, 0.0, 1.0)
	return next


## How much of this deed it has actually seen play out, 0..1.
func confidence(key: String) -> float:
	var times: float = float(tried.get(key, 0.0))
	if times < GLIMPSED:
		return 0.0
	return clampf((times - GLIMPSED) / (LEARNED - GLIMPSED), 0.0, 1.0)


## HOW A MOMENT LIKE THAT WOULD FEEL. The imagined situation is handed to the
## creature's own heart, which knows what such circumstances have felt like from
## having lived through them, and to its beliefs, which know how such moments
## have tended to turn out. A creature with neither has no foresight at all, and
## this returns zero — which is correct, not a gap.
func prospect(key: String, ctx: Dictionary, heart: CreatureHeart,
		beliefs: CreatureBeliefs) -> float:
	var trust := confidence(key)
	if trust <= 0.0 or heart == null:
		return 0.0
	var next := imagine(key, ctx)
	var felt := heart.read(next)
	var score := 0.0
	for name: String in felt:
		score += float(CreatureHeart.FEELINGS[name]["pleasure"]) * float(felt[name])
	if beliefs != null:
		score += beliefs.foretaste(next) * OMEN_SHARE
	return clampf(score, -1.5, 1.5) * trust


## About to do this, here. Whatever the situation looks like next is this deed's
## doing, as far as the model is concerned.
func expect(key: String, ctx: Dictionary) -> void:
	_pending = key
	_before = ctx.duplicate()
	_guess = imagine(key, ctx)


## The world moved on. Learn what the deed actually changed, and find out how
## badly the guess missed. Returns the surprise, 0..1.
func settle(now: Dictionary) -> float:
	if _pending == "":
		return 0.0
	var key := _pending
	_pending = ""
	tried[key] = float(tried.get(key, 0.0)) + 1.0
	if not effect.has(key):
		effect[key] = {}
	var change: Dictionary = effect[key]
	var missed := 0.0
	var counted := 0.0
	for f: String in FEATURES:
		var actual := float(now.get(f, 0.0)) - float(_before.get(f, 0.0))
		var held: float = float(change.get(f, 0.0))
		change[f] = clampf(held + EFFECT_LR * (actual - held), -EFFECT_CLAMP, EFFECT_CLAMP)
		missed += absf(float(now.get(f, 0.0)) - float(_guess.get(f, 0.0)))
		counted += 1.0
	var missed_by := clampf(missed / maxf(counted, 1.0) * 3.0, 0.0, 1.0)
	# Only a deed it thought it understood can surprise it. Being wrong about
	# something you have never seen is not surprise, it is ignorance.
	surprise = maxf(surprise, missed_by * confidence(key))
	return surprise


## Surprise fades, like everything else.
func cool(delta: float) -> void:
	surprise = maxf(surprise - SURPRISE_COOL * delta, 0.0)


## How much wider it should cast about, given how badly the world has just
## confounded it. Feeds the exploration temperature: a creature whose model just
## failed goes and looks at things.
func restlessness() -> float:
	return surprise * CURIOUS_ON_SURPRISE


## How much of the world it can see coming — the share of the deeds it knows
## that it can also predict. A plain readout of how far ahead it thinks.
func reach() -> float:
	if tried.is_empty():
		return 0.0
	var sure := 0.0
	for key: String in tried:
		sure += confidence(key)
	return sure / float(tried.size())


## WHAT IT EXPECTS ITS OWN DEEDS TO DO, in plain words — the only part of its
## mind that is about the future rather than the past.
func expectations(limit := 2) -> Array:
	var claims := []
	for key: String in effect:
		if confidence(key) < 0.5:
			continue
		var change: Dictionary = effect[key]
		for f: String in change:
			if absf(float(change[f])) < 0.28:
				continue
			claims.append({"key": key, "feature": f, "size": float(change[f])})
	claims.sort_custom(func(a, b): return absf(a["size"]) > absf(b["size"]))
	var said := []
	for claim: Dictionary in claims.slice(0, limit):
		var act: PackedStringArray = String(claim["key"]).split("|")
		var doing: String = CreatureBeliefs.VERB_PHRASE.get(act[0], act[0] + " %s")
		if doing.contains("%s"):
			doing = doing % (act[1] if act.size() > 1 else "things")
		var result: String = (LEAVES_MORE if float(claim["size"]) > 0.0 else LEAVES_LESS) \
			.get(claim["feature"], "changes things")
		said.append("expects %s to leave %s" % [doing, result])
	return said


## Persistence -----------------------------------------------------------------
##
## Hard-won and small: a few dozen deeds by sixteen features. This is the part
## of the mind that makes a creature seem to know what it is doing.

func to_dict() -> Dictionary:
	return {"effect": effect.duplicate(true), "tried": tried.duplicate()}


func from_dict(data: Dictionary) -> void:
	effect = (data.get("effect", {}) as Dictionary).duplicate(true)
	tried = (data.get("tried", {}) as Dictionary).duplicate()
	_pending = ""
