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
## HOW LITTLE IT CAN THINK OF YOU AND STILL COPY YOU. Below this it is not
## taking its cues from you at all — and the one thing that gets past it is
## being made to watch, which is what tying the rope off is for.
const FAITH_FLOOR := 0.15

## HOW GOOD IT HAS GOT AT A THING, nought to nine — and the only one of the
## three kinds of learning in this file that comes from DOING.
##
## The other two answer different questions. `repertoire` is whether it can do a
## thing AT ALL, and that is picked up by watching somebody else. `q` is whether
## a thing is WORTH doing, and that is picked up from how it turned out. Neither
## of them is HOW WELL, and how well is what lets a grown creature do things a
## young one cannot reach at all. A beast that has spent its life throwing
## stones and saplings can in the end pick up a full spruce and put it through
## something like a javelin. Nothing announces that this is possible. It arrives
## because the creature kept practising and one day the tree went up.
##
## This is deliberately NOT a value: being good at throwing does not make a
## creature want to throw, and being hopeless at it does not stop it trying.
## Wanting is `q`'s job and it is trained by consequences. Skill only settles
## what happens when the attempt is made.
const SKILL_CAP := 9.0
## Practice has sharply diminishing returns, so gain is divided by the level
## already held: the first throws teach more than the thousandth. That is what
## makes a level nine creature something a player RAISED rather than something
## that merely got old.
const SKILL_STEP := 0.25
## A fumble teaches too. It simply teaches less — and a creature that only ever
## learned from its successes would never get past the things it is bad at.
const SKILL_FUMBLE := 0.3
## AND SO DOES WATCHING SOMEBODY ELSE. Worth about a third of an attempt of its
## own — you cannot learn to throw by watching a man throw, but you do not start
## from nothing either — and it is the only way a creature ever picks up a
## technique it has never tried. This is what makes the imitation REAL: your
## example used to teach it what to WANT and nothing about how to do it, so a
## beast could spend its whole life watching a god hurl oxen over the treetops
## and still throw like something that had never seen it done.
##
## It runs one way only. The creature learns from the player; the player learns
## from playing.
const WATCH_SHARE := 0.35

## CHARACTER IS A RUNNING IMPRESSION OF RECENT DEEDS, not a bank balance. The
## creature IS what it has been DOING lately: each act pulls its character a
## little toward what that act means, so a habit defines it while a single lapse
## only nudges. This is why a beast that spends its days smashing reads as a
## wrecker no matter how many kind miracles it once watched you cast — and it is
## the whole reason the readout can be trusted.
##
## What gets pulled is a SIX-AXIS compass (see CreatureEthos), not a number on a
## wire between good and evil. `temperament` survives as the one-number
## projection of it, because plenty of the game still needs one number — the
## colour of its hide, whether a village will have it about. But the character
## itself is the compass, and two creatures reading the same temperament can be
## nothing alike.
const DEED_ALPHA := 0.05        # how much one deed moves an axis (~20-deed memory)
const WITNESS_ALPHA := 0.008    # merely WATCHING its god counts for far less
## Character is measured in LIFE LIVED, not in deeds counted. A creature that
## lands ten blows in a second has not become ten times the monster — it has
## spent one second being one, and its character should move accordingly. Each
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
	"smash": {"thrill": 0.7, "effort": 0.8, "fight": 1.0},
	"throw": {"thrill": 0.7, "effort": 0.7, "fight": 0.6},
	# JUGGLING. Pure amusement with people in it, and hard work — it is the
	# most strenuous thing on this list that produces absolutely nothing. That
	# a creature does it at all is the clearest sign it has energy to spare and
	# somebody to spend it in front of.
	"juggle": {"thrill": 1.1, "social": 0.5, "effort": 0.75},
	"flee": {"escape": 1.0, "effort": 0.8},
	"tend": {"effort": 0.5, "social": 0.25},
	# HERDING. To the body, driving cattle is simply hard work with people
	# somewhere in it — the same shape as gathering. Nothing here says a herd is
	# valuable or that driving one is kind; a creature finds that out by doing it
	# and seeing what you and the village make of it.
	"shepherd": {"effort": 0.8, "social": 0.35, "thrill": 0.2},
	# And taking one for the table is work that ends in meat, which is the same
	# thing gathering is. That it happens to be a killing is a matter for its
	# conscience (see CreatureEthos), not for its appetite.
	"cull": {"feeds": 0.45, "effort": 0.6, "thrill": 0.25, "fight": 0.5},
	"gift": {"social": 0.6, "effort": 0.4},
	"guard": {"social": 0.4, "effort": 0.3, "calms": 0.2},
	"rescue": {"social": 0.7, "effort": 0.7},
	# Working a miracle IS work, and a tired body flinches from it like any
	# other effort — that much is physiology and may be innate. What is NOT
	# innate is knowing what happens when it overreaches: that it learns by
	# reaching, failing, and remembering the circumstances (see _process_cast).
	"cast": {"thrill": 0.5, "heals": 1.0, "effort": 0.5},
	"wander": {"thrill": 0.25, "calms": 0.2, "effort": 0.3},
	# GOING. Almost no effort, and it answers exactly one thing — which is why
	# it needs a trait of its own rather than borrowing "calms": a creature
	# should not decide to relieve itself because it is tired.
	"relieve": {"relieves": 1.0, "effort": 0.1},
	# The quiet life.
	"lounge": {"calms": 0.85, "social": 0.15},
	"dance": {"thrill": 0.75, "social": 0.6, "effort": 0.5},
	"pray": {"calms": 0.6, "social": 0.7},
	"commune": {"social": 1.0, "calms": 0.25, "effort": 0.2},
	# Sitting with somebody who is frightened. Company for both of them, and it
	# costs almost nothing — which is why a lazy, gentle creature reaches for it.
	"soothe": {"social": 0.9, "calms": 0.4, "effort": 0.25},
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
## HOW GOOD IT HAS GOT, by DOING. Nought to SKILL_CAP per verb. Not a want and
## not a permission — see the note on SKILL_CAP for why it is a third thing.
var skill := {}             # verb -> 0..SKILL_CAP
## HOW IT HAS BEEN TREATED. Set by the creature that owns this mind, and read in
## exactly two places: how fast a lesson lands, and which deeds appeal when
## nothing else is pressing. Both are nudges on machinery that already exists —
## welfare never picks a deed, it only makes some easier to reach for.
var welfare: CreatureWelfare = null
## ITS CHARACTER, on six axes at once — the whole of what it has become. The
## one-number `temperament` below is only this compass squinted at.
var ethos := CreatureEthos.new()
var temperament := 0.0      # -100 monstrous .. +100 angelic: emergent, follows deeds

## WHAT IT BELIEVES about the world, and in what circumstances (see
## CreatureBeliefs). This is the half of its personality that says "not now".
var beliefs := CreatureBeliefs.new()
## WHO IT KNOWS, by name — laid over everything it thinks about their KIND, so
## it can adore one shepherd and avoid another while holding no opinion at all
## about shepherds. See CreatureBonds.
var bonds := CreatureBonds.new()
## WHAT IT THINKS WOULD HAPPEN NEXT. The only part of the mind that faces
## forwards: it learns what deeds DO to a situation, imagines the situation each
## option would leave it in, and asks its own heart how a moment like that would
## feel. See CreatureForesight.
var foresight := CreatureForesight.new()

## ITS HEART, handed over by the creature at birth. The mind needs it for one
## thing only: to ask how an imagined future would FEEL (see CreatureForesight).
var heart: CreatureHeart = null

var _last_judged := 0.0     # GameState.clock at the last judgement; pacing
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
	# WHAT A LIFE LEANS IT TOWARD. A creature raised well drifts to the quiet,
	# companionable deeds; a tormented one to rage and wreckage. A tilt on the
	# ballot, never a rule — a lifetime of teaching can tilt it back.
	if welfare != null:
		v += welfare.leaning(verb)
	if not seen.has(k):
		v += NOVELTY
	v -= float(_sated.get(k, 0.0))   # sick of doing this for now
	return v


## How a deed sits with this creature's character: repellent if it runs against
## its nature, merely permitted if it runs with it (see RELISH).
##
## Now judged on all six axes at once, which is a much sharper instrument than
## the old good-and-evil line. A creature that has grown SOLITARY finds holding
## court before the village genuinely unpleasant even though nothing about it is
## cruel; a WILFUL one finds copying you distasteful without being wicked. Those
## refusals were simply not expressible before.
func conscience_of(verb: String) -> float:
	var c: float = ethos.congeniality(verb) * CONSCIENCE
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
	var pressed: float = drive.get("pressed", 0.0)  # how badly it needs to go
	# WHAT IT EXPECTS OF THIS MOMENT AND THIS GROUND, before it has done
	# anything at all — its picture of what the world does on its own, plus how
	# it feels about where it is standing. Negative is a bad sort of moment.
	var omen: float = drive.get("omen", 0.0)
	var uneasy := maxf(-omen, 0.0)
	# Appetite is hunger MINUS how full the belly already is: a stuffed creature
	# has no interest in food however long since it last ate.
	var appetite := maxf(hunger - full * 1.4, -0.45)
	var fit := 0.0
	fit += float(traits.get("feeds", 0.0)) * appetite * 2.2
	fit += float(traits.get("calms", 0.0)) * (tired * 2.4 + lazy * 1.0 + full * 0.4)
	fit += float(traits.get("thrill", 0.0)) * (bored * 1.5 + low * 0.6)
	fit += float(traits.get("social", 0.0)) * (0.2 + lonely * 1.1)
	# FRIGHT IS NOT ONLY FLIGHT, and which of the two it is was never asked.
	# Fear fed exactly one thing — the pull toward running — so every creature
	# in the game was a coward by construction, however it had been raised and
	# whatever it had grown into. A frightened animal is in a heightened state,
	# and a heightened state resolves one of two ways.
	#
	# WHICH WAY IS ITS OWN. `nerve` is its DARING, the standing it has earned on
	# one of the six stones by what it has actually done (see CreatureEthos), so
	# a creature raised bold turns and faces the thing and a creature raised
	# timid bolts — and neither is written here as a species fact. Raise it
	# differently and it behaves differently, which is the whole game.
	var nerve: float = clampf(drive.get("nerve", 0.0), -1.0, 1.0)
	fit += float(traits.get("escape", 0.0)) * (afraid * 2.4 + uneasy * 1.2) \
		* (1.0 - nerve * 0.65)
	# And the same fear, in a bold one, is what makes it dangerous. Only while
	# it is actually afraid: this is not an appetite for violence, it is what
	# being cornered does.
	fit += float(traits.get("fight", 0.0)) * afraid * maxf(nerve, 0.0) * 2.2
	# And it is less inclined to make its own excitement in a moment it already
	# expects to go badly.
	fit -= float(traits.get("thrill", 0.0)) * uneasy * 0.5
	fit += float(traits.get("heals", 0.0)) * wounded * 2.0
	# Squared, so it is genuinely ignorable while it can be held and then
	# rises past everything else — which is how holding it in actually feels.
	fit += float(traits.get("relieves", 0.0)) * pressed * pressed * 4.5
	# Effort is what a tired or heavy body flinches from — the one universal cost.
	fit -= float(traits.get("effort", 0.0)) * (lazy * 0.9 + tired * 0.6)
	return fit


## Choose among the perceived opportunities. Softmax over predicted value, so
## the best option is usually taken but a curious mind keeps trying others —
## which is how new behaviours (and quirks) are ever discovered. `options` is an
## Array of Dictionaries: {verb, type, target, pos}. Returns the chosen one.
func choose(options: Array, drive: Dictionary, ctx := {},
		where := Vector3.INF, felt := "") -> Dictionary:
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
		var key := _key(opt["verb"], opt.get("type", "none"))
		var v := value(opt["verb"], opt.get("type", "none"), drive, ctx)
		# WHO it would be dealing with, on top of WHAT they are. This is the only
		# part of the ballot that is about a particular person rather than a kind.
		v += bonds.regard_for(opt.get("target", null))
		# AND WHERE IT WOULD LEAVE IT. Everything above is memory of how the deed
		# has gone; this is the one term that looks at the situation the deed
		# would CREATE and asks the heart how a moment like that feels. It is
		# silent for anything the creature has not seen play out a few times.
		v += foresight.prospect(key, ctx, heart, beliefs) * CreatureForesight.WEIGHT
		scored.append(v)
		best_v = maxf(best_v, v)
	# Softmax sample (temperature EXPLORE), numerically stabilised by best_v.
	var total := 0.0
	var weights := []
	# A creature whose picture of the world just failed casts about more widely.
	# Surprise is the only thing that reopens a settled mind.
	var temperature := EXPLORE * (1.0 + foresight.restlessness())
	for v: float in scored:
		var w: float = exp((v - best_v) / temperature)
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
	bonds.dealing_with(chosen.get("target", null))
	# Commit to a guess about what this will do. The next decision checks it.
	foresight.expect(_last_key, ctx)
	# Remember the deed AND the circumstances, so a later consequence can be
	# traced back to it.
	beliefs.remember(_last_key, ctx, where, felt)
	return chosen


## An outcome landed: teach the last deed how it FELT (delta rule toward the
## reward), remember it was tried, and let the deed shift the creature's heart.
func reinforce(reward: float) -> void:
	if _last_key == "":
		return
	var cur: float = q.get(_last_key, 0.0)
	# HOW WELL IT CAN TAKE A LESSON AT ALL. A cherished creature learns faster
	# than food and repetition explain; a wretched or tethered one barely learns
	# at all, because it is not attending to the lesson. This is the arithmetic
	# behind the claim that cruelty is a slower road to a stupider creature.
	var rate := LR * (welfare.learning() if welfare != null else 1.0)
	q[_last_key] = clampf(cur + rate * (reward - cur), -Q_CLAMP, Q_CLAMP)
	seen[_last_key] = int(seen.get(_last_key, 0)) + 1
	_sated[_last_key] = minf(float(_sated.get(_last_key, 0.0)) + SATIATION, 2.5)
	beliefs.credit(reward)   # the circumstances get their share of the lesson
	# AND THE DEED PASSED WITHOUT THE DISASTER IT FEARED. Every dark rule hung
	# on this deed loosens a little — which is the only way a superstition ever
	# comes off a creature. Without it they were permanent: see
	# CreatureBeliefs.relieved_of. A deed that went BADLY teaches the opposite
	# through `consequence` and is left well alone here.
	if reward > -0.2:
		beliefs.relieved_of(_last_key)
	bonds.settle(reward)     # and so does whoever it was dealing with
	judge(_last_verb)


## A deed was done: let what it MEANS shape the creature's character, pulling
## every axis the deed touches toward the life such a deed implies. Bounded by
## construction — no amount of anything can push it past what its behaviour
## actually is.
##
## `paced` deeds count for the TIME they occupied (see DEED_PERIOD), so a flurry
## of quick acts weighs no more than the same conduct spread out. The god's own
## praise and scolding are NOT paced: those are discrete acts of will, and they
## should land with their full force the moment you press the key. `direction`
## of -1 pushes the opposite way, which is what a scolding does.
func judge(verb: String, strength := DEED_ALPHA, paced := true, direction := 1.0) -> void:
	shape(CreatureEthos.meaning_of(verb), strength, paced, direction)


## The same, for a moral shape assembled on the spot rather than looked up from
## a verb — used for the god's own deeds, which the creature judges as conduct
## without having a verb of its own for them.
func shape(profile: Dictionary, strength := DEED_ALPHA, paced := true,
		direction := 1.0) -> void:
	var force := clampf(strength, 0.0, 1.0)
	if paced:
		var now := GameState.clock
		var lived := DEED_PERIOD if _last_judged == 0.0 \
			else now - _last_judged
		_last_judged = now
		force *= clampf(lived / DEED_PERIOD, 0.0, 1.0)
	ethos.push(profile, force, direction)
	temperament = ethos.temperament()


## Watching its god act is a lesson, but a FAINT one next to its own conduct —
## a creature is not made saintly by spectating. What it reads off you is mercy
## and ruin: it can see whether you spare a thing or break it, and little else.
func observe_god(weight: float) -> void:
	var w := clampf(weight / 5.0, -1.0, 1.0)
	shape({"mercy": w, "order": w * 0.6}, WITNESS_ALPHA)


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
	bonds.fade(1.0)


## Something happened TO the creature. Let it work out for itself which of its
## recent deeds brought this about.
func experience(tag: String, reward: float) -> void:
	beliefs.consequence(tag, reward)


## IT DID THE THING. Whether it came off or not, the doing of it taught the
## body something — which is why a fumble still counts, only for less.
func practise(verb: String, went_well := true) -> void:
	var now: float = float(skill.get(verb, 0.0))
	var gain := SKILL_STEP * (1.0 if went_well else SKILL_FUMBLE) / (1.0 + now)
	skill[verb] = minf(now + gain, SKILL_CAP)


## TECHNIQUE, PICKED UP BY WATCHING. The same curve `practise` climbs and the
## same diminishing returns, at a fraction of the step and scaled by how far it
## trusts the hand it is watching — a beloved god is STUDIED, a feared one is
## merely observed.
func watch_technique(verb: String, faith: float) -> void:
	var now: float = float(skill.get(verb, 0.0))
	var gain := SKILL_STEP * WATCH_SHARE * clampf(faith, 0.0, 1.0) / (1.0 + now)
	skill[verb] = minf(now + gain, SKILL_CAP)


## How good it is, as a fraction of the whole climb — which is what most callers
## actually want, since they are scaling something by it.
func knack(verb: String) -> float:
	return float(skill.get(verb, 0.0)) / SKILL_CAP


## The number a player would be told, nought to nine.
func skill_level(verb: String) -> int:
	return int(floorf(float(skill.get(verb, 0.0))))


## Watching the god cast a miracle teaches it, a little, how the power feels.
## `step` is how hard it was watching. A creature tied up in front of the
## working sees it properly; one that happened to be in the field glanced at it.
func witness_miracle(miracle: String, step := MIRACLE_STEP) -> void:
	familiarity[miracle] = minf(float(familiarity.get(miracle, 0.0)) + step, 1.0)


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
## `heed` is HOW HARD IT IS WATCHING — one when it is free to look elsewhere,
## and more when it has been tied up in front of you and cannot (see
## CreatureLead.HELD_HEED). Note what it does and does not touch: being made to
## watch teaches the HOW twice as fast and gets past the point where a creature
## has stopped taking its cues from you at all, and it does nothing whatever to
## what the creature WANTS. You cannot make a thing admire you by tying it to a
## post, and a model that let you would be a worse game as well as a lie.
func witness_god_deed(verb: String, type: String, trust: float, heed := 1.0) -> void:
	var faith := clampf(trust / 100.0, 0.0, 1.0)
	if faith < FAITH_FLOOR / maxf(heed, 0.001):
		return          # it is no longer taking its cues from you
	teach(verb, type, MIMIC_REWARD * faith, MIMIC_LR * faith)
	# AND THE TECHNIQUE, not merely the appetite. `teach` writes what it WANTS;
	# this writes what it CAN. A player who spends an afternoon hurling things
	# where their creature can see is teaching it to throw, and eventually to
	# juggle — see CreatureThrowing for the ladder that knack unlocks.
	watch_technique(verb, minf(faith * heed, 1.0))
	witness_practice("mimic", PRACTICE_STEP * 0.5)
	# Copying is itself a habit: the more it watches a god worth watching, the
	# more it thinks to look in the first place.
	familiarity["_watching"] = minf(float(familiarity.get("_watching", 0.0)) + 0.02, 1.0)


## The miracles it has watched enough to attempt itself.
func known_miracles() -> Array:
	var ready := []
	for m: String in familiarity:
		# `familiarity` also carries the mind's own bookkeeping — "_watching"
		# is how often it thinks to look at you at all — and an underscore was
		# the only thing marking those apart. Nothing enforced it, so the nest
		# wall listed "_watching" among the miracles it had learned.
		if m.begins_with("_"):
			continue
		if float(familiarity[m]) >= MIRACLE_READY:
			ready.append(m)
	return ready


## WHAT IT EXPECTS OF THE WORLD, and which stretches of country it has feelings
## about — the half of its picture that is not about its own deeds at all.
func world_picture() -> Array:
	var said := foresight.expectations()
	said.append_array(beliefs.omens())
	said.append_array(beliefs.haunts())
	said.append_array(bonds.attachments())
	return said


## Its habits of ORDER, in plain words — "likes to fish before it casts heal".
func rites() -> Array:
	return beliefs.rites()


## WHAT IT HAS BECOME, named — "tender wrecker", "utterly solitary", "beloved
## of the village". Read off the compass, so it is a character rather than a
## grade.
func character() -> String:
	return ethos.reading()


## The same spelled out, one plain sentence per leaning it actually holds.
func character_account(limit := 3) -> Array:
	return ethos.account(limit)


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
		# WHAT IT HAS GOT GOOD AT, and it was never written down. A creature
		# with a hundred and fifty throws behind it came back from a save
		# unable to aim, because `skill` was the one thing here that a session
		# built and a save forgot. The arm is a thing the player GREW; it has
		# to survive putting the game down.
		"skill": skill.duplicate(true),
		"ethos": ethos.to_dict(),
		"beliefs": beliefs.to_dict(),
		"bonds": bonds.to_dict(),
		"foresight": foresight.to_dict(),
	}


func from_dict(data: Dictionary) -> void:
	q = (data.get("q", {}) as Dictionary).duplicate(true)
	seen = (data.get("seen", {}) as Dictionary).duplicate(true)
	familiarity = (data.get("familiarity", {}) as Dictionary).duplicate(true)
	repertoire = (data.get("repertoire", {}) as Dictionary).duplicate(true)
	skill = (data.get("skill", {}) as Dictionary).duplicate(true)
	# A save from before the compass existed carries one number; unfold it onto
	# the axes that number used to stand for, so an old creature keeps its soul.
	if data.has("ethos"):
		ethos.from_dict(data.get("ethos", {}))
	else:
		var old := float(data.get("temperament", 0.0)) / 100.0
		ethos.from_dict({"mercy": old, "order": old * 0.6, "bounty": old * 0.3})
	temperament = ethos.temperament()
	_sated.clear()
	beliefs.from_dict(data.get("beliefs", {}))
	bonds.from_dict(data.get("bonds", {}))
	foresight.from_dict(data.get("foresight", {}))

