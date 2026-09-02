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
## Learning a PRACTICE (dancing, praying, holding court) by watching others.
## Slower than watching a miracle: you have to see a thing done a good few times
## before you can join in.
const PRACTICE_STEP := 0.06
const PRACTICE_READY := 0.5
## Copying YOU. How hard one observed deed of yours pulls, and how much of that
## survives — both scaled by trust at the call site.
const MIMIC_REWARD := 1.6
const MIMIC_LR := 0.3
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
## Character is measured in LIFE LIVED, not in deeds counted. A creature that
## lands ten blows in a second has not become ten times the monster — it has
## spent one second being one, and its heart should move accordingly. Each
## judgement therefore counts for the TIME it represents, up to one full deed's
## worth. Without this, anything that lets deeds resolve quickly rewrites the
## creature's whole character in seconds, and the readout means nothing.
const DEED_PERIOD := 2.0        # seconds of living that one full-weight deed is

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
	# A LIFE IS MOSTLY NEITHER. Most of what anything does is morally weightless,
	# and a creature with only saintly and monstrous options on the table is
	# forced to be one or the other. These are the hours in between.
	"lounge": 0.0, "run": 0.0, "mimic": 0.0, "sulk": 0.0, "shun": 0.0,
	"depart": 0.0, "dance": 0.15, "commune": 0.3, "pray": 0.4,
}

## WHAT EACH VERB IS LIKE. Drives read these, never verb names (see `_drive_fit`).
##   effort — how physical, the cost a tired or fat body flinches from
##   social — wants people about
##   feeds  — answers hunger
##   calms  — soothes, restores, costs nothing
##   thrill — stimulation: excitement, spectacle, destruction, showing off
##   escape — puts distance between itself and what it fears
##   heals  — mends its own hurts
## Verbs with similar traits are interchangeable to the BODY; only learning,
## belief, character and your example ever tell them apart.
const VERB_TRAITS := {
	"eat": {"feeds": 1.0, "effort": 0.2, "thrill": 0.1},
	# To a BODY, a person and a sheep are both meat: identical but for the work
	# of running one down. There is deliberately no appetite for people written
	# in here — everything that makes a man-eater is learned on top of a tie.
	"eat_kin": {"feeds": 1.0, "effort": 0.55, "thrill": 0.1},
	"gather": {"feeds": 0.35, "effort": 0.6, "social": 0.1},
	"fish": {"feeds": 0.6, "effort": 0.3, "calms": 0.3},
	"rest": {"calms": 1.0},
	"play": {"thrill": 0.9, "effort": 0.6, "social": 0.3},
	"watch": {"social": 0.6, "calms": 0.3, "thrill": 0.2},
	"smash": {"thrill": 0.7, "effort": 0.8},
	"throw": {"thrill": 0.7, "effort": 0.7},
	"flee": {"escape": 1.0, "effort": 0.8},
	"tend": {"effort": 0.5, "social": 0.25},
	"gift": {"social": 0.6, "effort": 0.4},
	"guard": {"social": 0.4, "effort": 0.3, "calms": 0.2},
	"rescue": {"social": 0.7, "effort": 0.7},
	# Working a miracle IS work, and a tired body flinches from it like any
	# other effort — that much is physiology and may be innate. What is NOT
	# innate is knowing what happens when it overreaches: that it learns by
	# reaching, failing, and remembering the circumstances (see _process_cast).
	"cast": {"thrill": 0.5, "heals": 1.0, "effort": 0.5},
	"wander": {"thrill": 0.25, "calms": 0.2, "effort": 0.3},
	# The quiet life.
	"lounge": {"calms": 0.85, "social": 0.15},
	"dance": {"thrill": 0.75, "social": 0.6, "effort": 0.5},
	"pray": {"calms": 0.6, "social": 0.7},
	"commune": {"social": 1.0, "calms": 0.25, "effort": 0.2},
	"run": {"effort": 1.0, "thrill": 0.7, "calms": 0.1},
	"mimic": {"thrill": 0.4, "social": 0.5, "effort": 0.4},
	# What a creature does when it has stopped trusting you.
	"sulk": {"calms": 0.4, "escape": 0.35},
	"shun": {"escape": 0.6, "effort": 0.35},
	"depart": {"escape": 1.0, "effort": 0.9},
}

## The learned value of doing a VERB to a TYPE of thing. Starts near zero; every
## reinforced experience nudges it toward the reward it produced. THIS TABLE IS
## THE CREATURE'S PERSONALITY — two creatures never learn the same one.
var q := {}                 # "verb|type" -> float, roughly -Q_CLAMP..+Q_CLAMP
var seen := {}              # "verb|type" -> times tried (drives curiosity)
var familiarity := {}       # miracle name -> 0..1, learned by witnessing
## Practices it has picked up by WATCHING — dancing, praying, holding court.
## An empty repertoire is a creature that has never seen anyone enjoy anything.
var repertoire := {}        # verb -> 0..1 casts
var temperament := 0.0      # -100 monstrous .. +100 angelic: emergent, follows deeds

## WHAT IT BELIEVES about the world, and in what circumstances (see
## CreatureBeliefs). This is the half of its personality that says "not now".
var beliefs := CreatureBeliefs.new()

var _deed_avg := 0.0        # the running moral average that IS its character
var _last_judged := 0       # ticks (ms) of the last judgement, for pacing
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
	# RITUAL: how right this feels AFTER whatever it just did. Once a pairing
	# has paid off a few times the order itself starts to matter, and the
	# creature's days take on a shape it invented and cannot explain.
	v += beliefs.ritual_bias(_last_key, k)
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


## How much a verb answers the body's current needs.
##
## Drives pull on TRAITS, never on named verbs. This matters more than anything
## else in this file: the moment a drive says "boredom wants smashing", every
## creature ever raised is a vandal by construction, and the player is left
## nudging a thing that already knows what it wants to be. Here boredom simply
## wants STIMULATION, and smashing a house, dancing for the villagers, sprinting
## across a hill with a tree on its back and casting a miracle are all equally
## valid answers as far as the body is concerned. Which one this particular
## creature reaches for is settled entirely by what it has learned, what it
## believes, what its character makes palatable, and what YOU have shown it.
##
## Adding a verb therefore means describing what it is LIKE, not writing a new
## rule about when to do it — and two verbs that feel alike are genuinely
## interchangeable until experience separates them.
func _drive_fit(verb: String, drive: Dictionary) -> float:
	var traits: Dictionary = VERB_TRAITS.get(verb, {})
	if traits.is_empty():
		return 0.0
	var hunger: float = drive.get("hunger", 0.0) / 100.0
	var tired: float = (100.0 - drive.get("energy", 100.0)) / 100.0
	var bored: float = drive.get("boredom", 0.0) / 100.0
	var low: float = (100.0 - drive.get("mood", 50.0)) / 100.0
	var afraid: float = drive.get("fear", 0.0) / 100.0
	var wounded: float = drive.get("wounded", 0.0)
	var full: float = drive.get("full", 0.0)      # 0 empty .. 1 stuffed
	var lazy: float = drive.get("lazy", 0.0)      # how fat, and so how disinclined
	var lonely: float = drive.get("lonely", 0.0)  # nobody about
	# Appetite is hunger MINUS how full the belly already is: a stuffed creature
	# has no interest in food however long since it last ate.
	var appetite := maxf(hunger - full * 1.4, -0.45)
	var fit := 0.0
	fit += float(traits.get("feeds", 0.0)) * appetite * 2.2
	fit += float(traits.get("calms", 0.0)) * (tired * 2.4 + lazy * 1.0 + full * 0.4)
	fit += float(traits.get("thrill", 0.0)) * (bored * 1.5 + low * 0.6)
	fit += float(traits.get("social", 0.0)) * (0.2 + lonely * 1.1)
	fit += float(traits.get("escape", 0.0)) * afraid * 2.4
	fit += float(traits.get("heals", 0.0)) * wounded * 2.0
	# Effort is what a tired or heavy body flinches from — the one universal cost.
	fit -= float(traits.get("effort", 0.0)) * (lazy * 0.9 + tired * 0.6)
	return fit


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
##
## `paced` deeds count for the TIME they occupied (see DEED_PERIOD), so a flurry
## of quick acts weighs no more than the same conduct spread out. The god's own
## praise and scolding are NOT paced: those are discrete acts of will, and they
## should land with their full force the moment you press the key.
func judge(valence: float, strength := DEED_ALPHA, paced := true) -> void:
	var force := clampf(strength, 0.0, 1.0)
	if paced:
		var now := Time.get_ticks_msec()
		var lived := DEED_PERIOD if _last_judged == 0 \
			else float(now - _last_judged) / 1000.0
		_last_judged = now
		force *= clampf(lived / DEED_PERIOD, 0.0, 1.0)
	_deed_avg = clampf(_deed_avg + (valence - _deed_avg) * force, -1.5, 1.5)
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


## A creature can only do what it has SEEN DONE. Dancing, praying, standing
## before a village and being attended to — none of these are innate. It picks
## them up by watching, which is why a creature raised beside a joyful village
## grows up with a wider life than one raised beside a grim one.
func witness_practice(verb: String, step := PRACTICE_STEP) -> void:
	repertoire[verb] = minf(float(repertoire.get(verb, 0.0)) + step, 1.0)


## Does it know how to do this at all? Verbs absent from the repertoire are
## innate and always available; the ones in it must be learned first.
func knows(verb: String) -> bool:
	return float(repertoire.get(verb, 0.0)) >= PRACTICE_READY


## YOUR EXAMPLE. Everything you do with your own hand is a lesson the creature
## may take: what you pick up, what you set down gently, what you hurl, who you
## heal. It copies you in proportion to how far it TRUSTS you — a beloved god is
## imitated closely, a feared one is watched and quietly disregarded.
##
## Nothing here says which deeds are worth copying. Plant trees and it learns to
## plant trees; hurl shepherds into the sea and it learns that too. This is the
## widest channel you have into what your creature becomes, and it is entirely
## made of what you actually do.
func witness_god_deed(verb: String, type: String, trust: float) -> void:
	var faith := clampf(trust / 100.0, 0.0, 1.0)
	if faith < 0.15:
		return          # it is no longer taking its cues from you
	teach(verb, type, MIMIC_REWARD * faith, MIMIC_LR * faith)
	witness_practice("mimic", PRACTICE_STEP * 0.5)
	# Copying is itself a habit: the more it watches a god worth watching, the
	# more it thinks to look in the first place.
	familiarity["_watching"] = minf(float(familiarity.get("_watching", 0.0)) + 0.02, 1.0)


## The miracles it has watched enough to attempt itself.
func known_miracles() -> Array:
	var ready := []
	for m: String in familiarity:
		if float(familiarity[m]) >= MIRACLE_READY:
			ready.append(m)
	return ready


## Its habits of ORDER, in plain words — "likes to fish before it casts heal".
func rites() -> Array:
	return beliefs.rites()


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


## Persistence -----------------------------------------------------------------

## THE WHOLE PERSONALITY. This dictionary is what makes a creature that one
## particular creature — no two playthroughs grow the same one, so it is the
## thing most worth carrying across a save.
func to_dict() -> Dictionary:
	return {
		"q": q.duplicate(true),
		"seen": seen.duplicate(true),
		"familiarity": familiarity.duplicate(true),
		"repertoire": repertoire.duplicate(true),
		"temperament": temperament,
		"deed_avg": _deed_avg,
		"beliefs": beliefs.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	q = (data.get("q", {}) as Dictionary).duplicate(true)
	seen = (data.get("seen", {}) as Dictionary).duplicate(true)
	familiarity = (data.get("familiarity", {}) as Dictionary).duplicate(true)
	repertoire = (data.get("repertoire", {}) as Dictionary).duplicate(true)
	temperament = float(data.get("temperament", 0.0))
	_deed_avg = float(data.get("deed_avg", temperament / CHARACTER_SCALE))
	_sated.clear()
	beliefs.from_dict(data.get("beliefs", {}))

