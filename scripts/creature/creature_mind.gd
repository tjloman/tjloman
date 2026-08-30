class_name CreatureMind
extends RefCounted
## The creature's LEARNING brain — a lightweight online-learning agent in the
## Black & White lineage: small learned models over a fixed motor repertoire,
## NOT a scripted list of behaviours. Each decision, the creature perceives the
## world as a set of (VERB, THING) opportunities, PREDICTS how each would feel
## from what it has learned, picks one (with curiosity-driven exploration),
## then updates its learned values from the actual outcome.
##
## Beliefs, aversions, cruelty, rituals, and courage EMERGE from experience.
## Nothing here hard-codes "be evil" or "fear people": if it learns that
## smashing animals feels good, it will smash animals — and become a monster
## because that is what monsters do, not because a rule said so.

const LR := 0.2             # learning rate: how fast an outcome reshapes a value
const NOVELTY := 0.7        # curiosity: the pull of a (verb,type) never tried
const EXPLORE := 0.55       # softmax temperature — higher means more experimenting
const Q_CLAMP := 4.0
const FORGET := 0.004       # values drift gently back toward zero (slow forgetting)
const MIRACLE_STEP := 0.05  # familiarity gained per witnessed cast
const MIRACLE_READY := 0.6  # familiarity needed before it can cast on its own
## CONSCIENCE: how strongly the creature's own character colours what it WANTS
## to do. A saintly beast finds cruelty repellent; a monstrous one finds it
## delicious. This is what makes an angelic creature refuse to eat people
## without any rule forbidding it.
const CONSCIENCE := 4.0
## Conscience is ASYMMETRIC. Acting against your nature is fully repellent, but
## acting WITH it only licenses the deed — it does not compel. Symmetric relish
## made a wicked creature do one thing and nothing else forever.
const RELISH := 0.45
## Your praise and scolding are the loudest teacher in its world — they move a
## belief far harder than merely doing the thing does.
const TEACH_LR := 0.75

## CHARACTER IS A RUNNING IMPRESSION OF RECENT DEEDS, not a bank balance. The
## creature IS what it has been DOING lately: each act pulls its heart a little
## toward what that act means, so a habit defines it while a single lapse only
## nudges. This is why a beast that spends its days smashing reads as monstrous
## no matter how many kind miracles it once watched you cast — and it is the
## whole reason the readout can be trusted.
## Its heart is the RUNNING AVERAGE of the moral weight of its recent deeds —
## roughly its last twenty acts. So character is the honest ratio of how it
## spends its days: a creature that mostly tends fields stays kind even if it
## sometimes lashes out, and one that mostly smashes is a monster however many
## good deeds it can point to. A plain average also keeps the two directions
## symmetric, so it cannot slide into cruelty faster than it can climb out.
const DEED_ALPHA := 0.05        # how much one deed moves the average (~20-deed memory)
const WITNESS_ALPHA := 0.008    # merely WATCHING its god counts for far less
const CHARACTER_SCALE := 90.0   # deed-average -1..+1 mapped onto the -100..100 heart

## SATIATION — you can have too much of anything. Doing the same thing again
## and again palls, and the appetite for it returns only after a rest. Without
## this, whichever deed a creature first found rewarding would become the ONLY
## thing it ever did (violence especially, since a wicked heart relishes it and
## so keeps feeding its own habit). This is what keeps a life varied.
const SATIATION := 0.25         # how much a deed palls each time it is done
const SATIATION_FADE := 0.12    # how fast the appetite comes back, per decision

## How KIND (+) or CRUEL (-) each verb is. This is the ONLY moral scaffolding,
## and it does NOT choose actions — it only reads what a chosen deed MEANS, so
## the emergent temperament tracks how the creature actually behaves.
const VERB_VALENCE := {
	"tend": 0.6, "gather": 0.5, "gift": 0.9, "rescue": 1.3, "guard": 0.4,
	"watch": 0.1, "play": 0.2, "fish": 0.1, "cast": 0.25,
	"smash": -1.0, "throw": -0.7, "eat_kin": -1.2, "eat": -0.1,
	"flee": 0.0, "wander": 0.0, "rest": 0.0,
}

## The learned value of doing a VERB to a TYPE of thing. Starts near zero; every
## reinforced experience nudges it toward the reward it produced. THIS TABLE IS
## THE CREATURE'S PERSONALITY — two creatures never learn the same one.
var q := {}                 # "verb|type" -> float, roughly -Q_CLAMP..+Q_CLAMP
var seen := {}              # "verb|type" -> times tried (drives curiosity)
var familiarity := {}       # miracle name -> 0..1, learned by witnessing casts
var temperament := 0.0      # -100 monstrous .. +100 angelic: emergent, follows deeds

## WHAT IT BELIEVES about the world, and in what circumstances (see
## CreatureBeliefs). This is the half of its personality that says "not now".
var beliefs := CreatureBeliefs.new()

var _deed_avg := 0.0        # the running moral average that IS its character
var _sated := {}            # "verb|type" -> how thoroughly sick of it it is
var _last_key := ""         # the (verb,type) the next outcome is credited to
var _last_verb := ""


func _key(verb: String, type: String) -> String:
	return verb + "|" + type


## The predicted worth of an opportunity RIGHT NOW: what it has learned this
## deed is worth, plus how well it serves a pressing drive, plus curiosity.
func value(verb: String, type: String, drive: Dictionary, ctx := {}) -> float:
	var k := _key(verb, type)
	var v: float = q.get(k, 0.0)
	v += _drive_fit(verb, drive)
	# What it has learned about doing this IN THESE CIRCUMSTANCES, plus the
	# dread carried by anything it expects to end badly. This is why a creature
	# that was once mobbed for it will hunt a lone shepherd but not a crowd.
	v += beliefs.bias(k, ctx)
	v += beliefs.foreboding(k)
	# Its conscience: a deed that runs against its character repels it, and one
	# that suits it appeals. An angelic creature simply does not want to eat
	# people; a monstrous one is drawn to it.
	v += conscience_of(verb)
	if not seen.has(k):
		v += NOVELTY
	v -= float(_sated.get(k, 0.0))   # sick of doing this for now
	return v


## How a deed sits with this creature's character: repellent if it runs against
## its nature, merely permitted if it runs with it (see RELISH).
func conscience_of(verb: String) -> float:
	var c: float = VERB_VALENCE.get(verb, 0.0) * (temperament / 100.0) * CONSCIENCE
	return c * RELISH if c > 0.0 else c


## How much a verb answers the body's current needs. Keeps a starving or
## exhausted creature sensible without scripting the choice — the pull is just
## one more term the learned values compete with.
func _drive_fit(verb: String, drive: Dictionary) -> float:
	var hunger: float = drive.get("hunger", 0.0) / 100.0
	var tired: float = (100.0 - drive.get("energy", 100.0)) / 100.0
	var bored: float = drive.get("boredom", 0.0) / 100.0
	var low: float = (100.0 - drive.get("mood", 50.0)) / 100.0
	var afraid: float = drive.get("fear", 0.0) / 100.0
	var wounded: float = drive.get("wounded", 0.0)
	var full: float = drive.get("full", 0.0)    # 0 empty .. 1 stuffed
	var lazy: float = drive.get("lazy", 0.0)    # how fat, and so how disinclined
	match verb:
		# Appetite is hunger MINUS how full the belly already is. A stuffed
		# creature has no interest in food however long since it last ate.
		"eat", "eat_kin": return maxf(hunger * 2.2 - full * 3.0, -1.0)
		"gather": return maxf(hunger * 0.8 - full * 0.8, 0.0) + 0.1 - lazy * 0.4
		"fish": return hunger * 0.7 + bored * 0.3
		# A fat creature is a lazy one: sprawling always looks inviting.
		"rest": return tired * 2.6 + lazy * 1.1 + full * 0.6
		# PLAY is what boredom actually wants — chasing, romping, showing off.
		"play": return bored * 1.7 - lazy * 0.9   # too heavy to romp
		"watch": return bored * 0.9
		# Violence is what FRUSTRATION wants, not mere idleness. Left as a
		# boredom cure it simply became every creature's favourite pastime.
		"smash", "throw": return low * 1.0 + bored * 0.15 - lazy * 0.5
		"flee": return afraid * 2.4
		"tend", "gift", "guard", "rescue": return 0.15 - lazy * 0.4  # work is effort
		"cast": return bored * 0.3 + wounded * 2.0 + 0.15
		"wander": return 0.3
	return 0.0


## Choose among the perceived opportunities. Softmax over predicted value, so
## the best option is usually taken but a curious mind keeps trying others —
## which is how new behaviours (and quirks) are ever discovered. `options` is an
## Array of Dictionaries: {verb, type, target, pos}. Returns the chosen one.
func choose(options: Array, drive: Dictionary, ctx := {}) -> Dictionary:
	if options.is_empty():
		_last_key = ""
		_last_verb = ""
		return {"verb": "wander", "type": "none", "target": null}
	# Appetites recover a little with every decision made.
	for k: String in _sated:
		_sated[k] = maxf(float(_sated[k]) - SATIATION_FADE, 0.0)
	var best_v := -INF
	var scored := []
	for opt: Dictionary in options:
		var v := value(opt["verb"], opt.get("type", "none"), drive, ctx)
		scored.append(v)
		best_v = maxf(best_v, v)
	# Softmax sample (temperature EXPLORE), numerically stabilised by best_v.
	var total := 0.0
	var weights := []
	for v: float in scored:
		var w: float = exp((v - best_v) / EXPLORE)
		weights.append(w)
		total += w
	var roll := randf() * total
	var pick := 0
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			pick = i
			break
	var chosen: Dictionary = options[pick]
	_last_verb = chosen["verb"]
	_last_key = _key(chosen["verb"], chosen.get("type", "none"))
	# Remember the deed AND the circumstances, so a later consequence can be
	# traced back to it.
	beliefs.remember(_last_key, ctx)
	return chosen


## An outcome landed: teach the last deed how it FELT (delta rule toward the
## reward), remember it was tried, and let the deed shift the creature's heart.
func reinforce(reward: float) -> void:
	if _last_key == "":
		return
	var cur: float = q.get(_last_key, 0.0)
	q[_last_key] = clampf(cur + LR * (reward - cur), -Q_CLAMP, Q_CLAMP)
	seen[_last_key] = int(seen.get(_last_key, 0)) + 1
	_sated[_last_key] = minf(float(_sated.get(_last_key, 0.0)) + SATIATION, 2.5)
	beliefs.credit(reward)   # the circumstances get their share of the lesson
	judge(VERB_VALENCE.get(_last_verb, 0.0))


## Let a deed of moral weight `valence` (-1 cruel .. +1 kind) shape the heart,
## pulling it toward the character such a life implies. Bounded by construction:
## no amount of anything can push it past what its behaviour actually is.
func judge(valence: float, strength := DEED_ALPHA) -> void:
	_deed_avg = clampf(_deed_avg + (valence - _deed_avg) * clampf(strength, 0.0, 1.0),
		-1.5, 1.5)
	temperament = clampf(_deed_avg * CHARACTER_SCALE, -100.0, 100.0)


## Watching its god act is a lesson, but a FAINT one next to its own conduct —
## a creature is not made saintly by spectating.
func observe_god(weight: float) -> void:
	judge(clampf(weight / 5.0, -1.0, 1.0), WITNESS_ALPHA)


## Teach a specific (verb,type) directly — used when the world reinforces
## something the mind didn't just choose (a taste, a wound, the god's praise).
func teach(verb: String, type: String, reward: float, strength := TEACH_LR) -> void:
	var k := _key(verb, type)
	var cur: float = q.get(k, 0.0)
	q[k] = clampf(cur + strength * (reward - cur), -Q_CLAMP, Q_CLAMP)
	seen[k] = int(seen.get(k, 0)) + 1


## Slow forgetting: unrehearsed opinions drift back toward neutral, so a
## creature's character reflects what it does OFTEN, not one wild afternoon.
func decay() -> void:
	for k: String in q:
		q[k] = move_toward(q[k], 0.0, FORGET)
	beliefs.fade()


## Something happened TO the creature. Let it work out for itself which of its
## recent deeds brought this about.
func experience(tag: String, reward: float) -> void:
	beliefs.consequence(tag, reward)


## Watching the god cast a miracle teaches it, a little, how the power feels.
func witness_miracle(miracle: String) -> void:
	familiarity[miracle] = minf(float(familiarity.get(miracle, 0.0)) + MIRACLE_STEP, 1.0)


## The miracles it has watched enough to attempt itself.
func known_miracles() -> Array:
	var ready := []
	for m: String in familiarity:
		if float(familiarity[m]) >= MIRACLE_READY:
			ready.append(m)
	return ready


## A short, human-readable peek at the strongest thing it has learned — for the
## hover/dashboard, so its inner life is legible.
func strongest_urge() -> String:
	var best_k := ""
	var best_v := 0.35   # ignore near-zero noise
	for k: String in q:
		if q[k] > best_v:
			best_v = q[k]
			best_k = k
	if best_k == "":
		return "still figuring the world out"
	var parts := best_k.split("|")
	return "has learned to love %s %s" % [parts[0], parts[1]]
