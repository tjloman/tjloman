class_name CreatureEthos
extends RefCounted
## THE MORAL COMPASS — and it is not a compass with four points.
##
## Every god game before this one has run its creature down a single wire from
## GOOD to EVIL, so that every beast ever raised is somewhere on one line and
## the only interesting question is how far along it got. That line throws away
## almost everything worth knowing about a character. A beast that tends the
## fields and one that dances for the villagers and one that hauls stone home
## all read as "gentle"; a beast that eats people and one that knocks houses
## down and one that walked away from its god all read as "monstrous".
##
## Here character is a POINT IN SIX DIMENSIONS, each a running impression of
## what the creature has lately been doing:
##
##   MERCY      ↔ CRUELTY      how it treats things that can suffer
##   BOUNTY     ↔ APPETITE     whether it produces or consumes
##   ORDER      ↔ RUIN         whether it builds up or breaks down
##   FELLOWSHIP ↔ SOLITUDE     whether it seeks people or gets away from them
##   DARING     ↔ CAUTION      what it does about risk
##   DEVOTION   ↔ WILFULNESS   what it does about YOU
##
## Only the first three carry any weight of good and evil at all (see GOOD).
## The other three are pure flavour — and flavour is the point. A creature can
## be a tender wrecker, a ravenous disciple, a bold recluse, a cruel provider.
## Naming any two leanings together gives well over a hundred readings before
## the strength qualifier multiplies them again, which is the "fifty flavours
## of neutrality" this was built for: almost every creature lands somewhere
## with a name, and almost none of those names is "good" or "evil".
##
## Nothing here decides anything. The compass only reads what deeds MEAN, and
## the meaning then feeds back into the creature's conscience — so a beast that
## has spent its days breaking things finds breaking things congenial, and one
## that has spent them hauling grain finds them repugnant. That feedback is
## what makes a character stick without a single rule saying "be a wrecker".

## The six axes, in the order a reading considers them.
const AXES := ["mercy", "bounty", "order", "fellowship", "daring", "devotion"]

## WHAT EACH DEED MEANS, on every axis it touches. This is the whole of the
## game's moral scaffolding: it never chooses an action, it only says what
## having chosen one implies about you. Axes a verb does not mention are not
## neutral about it — they simply have nothing to say, and drift (see DRIFT).
const MEANING := {
	# The kind deeds. Note that none of them is kind in the same WAY.
	"rescue": {"mercy": 1.3, "fellowship": 0.5, "daring": 0.6},
	"gift": {"mercy": 0.6, "bounty": 0.9, "fellowship": 0.5},
	"tend": {"bounty": 0.8, "order": 0.6, "mercy": 0.2},
	"gather": {"bounty": 0.7, "order": 0.4},
	"guard": {"mercy": 0.5, "order": 0.6, "fellowship": 0.3, "daring": 0.3},
	"heal": {"mercy": 1.1, "fellowship": 0.3},
	# The cruel ones, likewise all cruel differently.
	"smash": {"mercy": -0.9, "order": -1.0, "daring": 0.4},
	"throw": {"mercy": -0.7, "order": -0.6, "daring": 0.3},
	"eat_kin": {"mercy": -1.2, "bounty": -0.5, "fellowship": -0.3},
	# The great middle of any life.
	"eat": {"bounty": -0.3},
	"fish": {"bounty": 0.35, "daring": -0.1},
	"watch": {"fellowship": 0.35, "daring": -0.15},
	"play": {"fellowship": 0.25, "daring": 0.35, "order": -0.1},
	"cast": {"daring": 0.4, "devotion": 0.35, "order": 0.1},
	"wander": {"fellowship": -0.25, "daring": 0.15},
	"rest": {"daring": -0.2},
	"lounge": {"daring": -0.3},
	"run": {"daring": 0.5, "fellowship": -0.1},
	"dance": {"fellowship": 0.6, "daring": 0.3, "devotion": 0.15},
	"pray": {"fellowship": 0.8, "devotion": 0.5, "order": 0.2},
	"commune": {"fellowship": 1.0, "order": 0.25, "devotion": 0.2},
	"soothe": {"mercy": 0.9, "fellowship": 0.7},
	"mimic": {"devotion": 1.0, "fellowship": 0.2},
	# And the ways a creature tells its god where to get off.
	"sulk": {"devotion": -0.3, "fellowship": -0.4, "daring": -0.4},
	"shun": {"devotion": -0.9, "fellowship": -0.7},
	"depart": {"devotion": -1.0, "fellowship": -1.0, "daring": 0.4},
	"flee": {"daring": -0.8, "fellowship": -0.2},
}

## HOW MUCH OF GOOD AND EVIL EACH AXIS CARRIES. Three of the six carry all of
## it; the rest are character, not conscience. This is the line that keeps a
## solitary, wilful, cautious creature from reading as wicked merely for being
## bad company — a distinction every previous game in this genre collapsed.
const GOOD := {"mercy": 0.55, "bounty": 0.2, "order": 0.25}
const GOOD_GAIN := 1.4     # so a wholly cruel life still reaches the extreme

## How much one deed moves an axis it names — roughly a twenty-deed memory, so
## character is the honest ratio of how the creature spends its days.
const DEED_FORCE := 0.05
## An axis the deed says NOTHING about still drifts toward neutral, slowly. A
## creature that rescued somebody once and has spent the year since breaking
## fences is not merciful, and this is why.
const DRIFT := 0.35
const AXIS_LIMIT := 1.2    # room to overshoot, so extremes are reachable

## WHAT A LEANING IS CALLED. Every axis has two poles, and every pole has an
## ADJECTIVE (used when it is the creature's strongest leaning) and a NOUN
## (used when it is the second). The reading is simply the two put together —
## "tender wrecker", "ravenous disciple" — which is how a handful of words
## covers hundreds of distinguishable characters.
const POLE_ADJ := {
	"mercy+": "tender", "mercy-": "cruel",
	"bounty+": "bountiful", "bounty-": "ravenous",
	"order+": "steady", "order-": "wrecking",
	"fellowship+": "sociable", "fellowship-": "solitary",
	"daring+": "bold", "daring-": "wary",
	"devotion+": "devout", "devotion-": "wilful",
}
const POLE_NOUN := {
	"mercy+": "shepherd", "mercy-": "tormentor",
	"bounty+": "provider", "bounty-": "glutton",
	"order+": "keeper", "order-": "wrecker",
	"fellowship+": "companion", "fellowship-": "recluse",
	"daring+": "daredevil", "daring-": "watcher",
	"devotion+": "disciple", "devotion-": "stray",
}

## A few pairings deserve a name of their own rather than the compound. These
## are the characters worth recognising on sight; everything else composes.
const PAIR_NAME := {
	"mercy+|fellowship+": "beloved of the village",
	"fellowship+|mercy+": "beloved of the village",
	"mercy-|fellowship-": "the thing in the hills",
	"fellowship-|mercy-": "the thing in the hills",
	"bounty+|devotion+": "faithful servant",
	"devotion+|bounty+": "faithful servant",
	"order-|daring+": "force of nature",
	"daring+|order-": "force of nature",
	"mercy-|devotion+": "your instrument",
	"devotion+|mercy-": "your instrument",
	"mercy+|devotion-": "better than its god",
	"devotion-|mercy+": "better than its god",
	"bounty-|mercy-": "man-eater",
	"mercy-|bounty-": "man-eater",
	"order+|fellowship+": "keeper of the peace",
	"fellowship+|order+": "keeper of the peace",
}

## The plain-sentence version of every pole, said as a habit rather than a
## label: what a player would actually notice about the beast.
const PLAIN := {
	"mercy+": "spares what it could hurt",
	"mercy-": "hurts what cannot fight back",
	"bounty+": "brings more home than it takes",
	"bounty-": "eats more than it ever fetches",
	"order+": "puts the world back as it found it",
	"order-": "leaves the world in pieces",
	"fellowship+": "wants people about it",
	"fellowship-": "would rather be left alone",
	"daring+": "goes at the world head first",
	"daring-": "keeps well out of trouble",
	"devotion+": "takes its lead from you",
	"devotion-": "has its own ideas",
}

## How strongly a leaning is held, in words.
const FAINT := 0.10        # below this an axis has nothing to say
const EARNED := 0.38       # both leanings this firm before a proper name is used
const STRENGTH_WORD := [
	[0.20, "faintly "], [0.38, "somewhat "], [0.58, ""],
	[0.80, "thoroughly "], [99.0, "utterly "],
]

## WHERE IT STANDS. Axis name -> -1..+1, all starting dead centre: a newborn
## creature has no character at all, and has to go and get one.
var axis := {}


func _init() -> void:
	for a: String in AXES:
		axis[a] = 0.0


## What one deed says about whoever did it.
static func meaning_of(verb: String) -> Dictionary:
	return MEANING.get(verb, {})


## The old single-axis kindness of a deed, derived from the three axes that
## carry moral weight rather than written down twice. Praise, scolding and the
## villagers' opinion still want one number, and this is honestly that number —
## but it is no longer what the creature's character is MADE of.
static func kindness(verb: String) -> float:
	var profile: Dictionary = MEANING.get(verb, {})
	var total := 0.0
	for a: String in GOOD:
		total += float(profile.get(a, 0.0)) * float(GOOD[a])
	return clampf(total * GOOD_GAIN, -1.4, 1.4)


## A deed was done: let it pull the character toward what such a deed implies.
## `force` is how much of a whole deed this counts for (see CreatureMind's
## pacing), and `direction` lets a scolding push the opposite way from the act.
func learn(verb: String, force := DEED_FORCE, direction := 1.0) -> void:
	push(MEANING.get(verb, {}), force, direction)


## As `learn`, but for a meaning assembled on the spot — watching its god, or
## anything else that has a moral shape without being one of its own verbs.
func push(profile: Dictionary, force := DEED_FORCE, direction := 1.0) -> void:
	var f := clampf(force, 0.0, 1.0)
	if f <= 0.0:
		return
	for a: String in AXES:
		var target := float(profile.get(a, 0.0)) * direction
		# Axes the deed says nothing about still relax toward centre, at a
		# fraction of the rate — unexercised character fades.
		var rate := f if profile.has(a) else f * DRIFT
		axis[a] = clampf(float(axis[a]) + (target - float(axis[a])) * rate,
			-AXIS_LIMIT, AXIS_LIMIT)


## HOW CONGENIAL a deed is to the creature it has become — the dot product of
## what the deed means against where it stands. A wrecker finds wrecking easy
## and mending irksome; a recluse finds holding court exhausting whether or not
## holding court is KIND. This is the whole feedback loop that makes character
## stick, and it works on all six axes, not merely on good and evil.
func congeniality(verb: String) -> float:
	var profile: Dictionary = MEANING.get(verb, {})
	if profile.is_empty():
		return 0.0
	var total := 0.0
	for a: String in profile:
		total += float(profile[a]) * float(axis.get(a, 0.0))
	return clampf(total, -1.0, 1.0)


## The good-and-evil projection, -1..+1, for everything that still needs one
## number: the colour of its hide, whether the villagers will have it about,
## whether it will consider eating one of them.
func alignment() -> float:
	var total := 0.0
	for a: String in GOOD:
		total += float(axis.get(a, 0.0)) * float(GOOD[a])
	return clampf(total * GOOD_GAIN, -1.0, 1.0)


## The same, on the -100..+100 scale the rest of the game speaks.
func temperament() -> float:
	return alignment() * 100.0


func standing(which: String) -> float:
	return float(axis.get(which, 0.0))


## The axes it leans on, strongest first.
func leanings() -> Array:
	var ranked := AXES.duplicate()
	ranked.sort_custom(func(a, b): return absf(float(axis[a])) > absf(float(axis[b])))
	return ranked


## WHAT IT IS, in two or three words. The strongest leaning supplies an
## adjective and the second a noun, so the reading names a character rather
## than a score — and a creature with no strong leaning at all is honestly
## reported as still becoming something.
func reading() -> String:
	var ranked := leanings()
	var first := float(axis[ranked[0]])
	if absf(first) < FAINT:
		return "of no fixed character"
	var lead: String = _pole(ranked[0])
	var second := float(axis[ranked[1]])
	if absf(second) < FAINT:
		return _strength(absf(first)) + POLE_ADJ[lead]
	var back: String = _pole(ranked[1])
	# A pairing with a name of its own already says how strongly it is meant —
	# "utterly man-eater" is not English, and "man-eater" needs no help. It has
	# to be EARNED, though: only a creature that holds both leanings firmly gets
	# the proper name, or it would swallow every shade of the compound one.
	if absf(first) >= EARNED and absf(second) >= EARNED \
			and PAIR_NAME.has(lead + "|" + back):
		return String(PAIR_NAME[lead + "|" + back])
	return "%s%s %s" % [_strength(absf(first)), POLE_ADJ[lead], POLE_NOUN[back]]


## Each notable leaning as a plain sentence, for anyone who wants the compass
## spelled out rather than named — the workshop panel, and the creature's own
## account of itself.
func account(limit := 3) -> Array:
	var said := []
	for a: String in leanings():
		var value := float(axis[a])
		if absf(value) < FAINT or said.size() >= limit:
			break
		said.append(_strength(absf(value)) + PLAIN[_pole(a)])
	return said


func _pole(which: String) -> String:
	return which + ("+" if float(axis.get(which, 0.0)) >= 0.0 else "-")


func _strength(magnitude: float) -> String:
	for band: Array in STRENGTH_WORD:
		if magnitude < float(band[0]):
			return String(band[1])
	return ""


## Persistence -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return axis.duplicate()


func from_dict(data: Dictionary) -> void:
	for a: String in AXES:
		axis[a] = clampf(float(data.get(a, 0.0)), -AXIS_LIMIT, AXIS_LIMIT)
