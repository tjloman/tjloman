class_name Spellbook
## THE GRAMMAR OF MIRACLES.
##
## A miracle is no longer a thing you pick off a menu. You draw RUNES — one
## stroke each, several in a breath — and what you get is whatever those runes
## MEAN TOGETHER. Water is rain. Water and force is a thunderstorm. Air, air
## and water is a hurricane.
##
## Three rules make this work, and all three matter:
##
##  1. NAMED RECIPES. A combination the world has a name for becomes that
##     miracle outright, at full strength.
##
##  2. INTENSITY BY REPETITION. The same rune drawn again does not add a second
##     effect; it makes the first one BIGGER. Water is a sprinkle, water-water
##     a cloudburst, water-water-water a deluge. This is how one rune covers a
##     whole range without a gesture for every rung of it.
##
##  3. BLENDING, for everything else. An unnamed combination is not an error —
##     it casts every rune's own miracle at once, each somewhat weakened. So
##     fire-and-life really does scatter burning food, and no combination the
##     player invents is ever a dead end. This is what makes the system feel
##     like a language rather than a longer list.
##
## RUDIMENTS COME FIRST. A compound needs every rune in it, and runes are what
## your villages teach you — so a handful of unlocks opens a combinatorial
## spellbook rather than a fixed dozen. Learning rain and lightning separately
## IS how you come to hold the storm.

## Gesture -> rune. One shape per rune, so the alphabet stays learnable while
## the vocabulary built out of it does not have to.
## A BENT STROKE MEANS WHICHEVER WAY IT BENDS, and not how sharply. `^` and a
## shallow dome are both sky; `V` and a bowl are both earth; a sharp `>` and a
## fat `)` are both ward. Sharpness used to tell two runes apart, and it was the
## one thing about their own stroke a player cannot see, so a fat C kept casting
## sky. Direction is something a hand knows it is doing.
##
## The straight line is CANCEL and therefore not in here at all — see
## DivineHand._finish_stroke. Earth moved onto `V` to make room for it.
const RUNE_OF := {
	"wave": "water",        # a flowing S
	"vline": "force",       # a bolt driven straight down
	"dline": "fire",        # a slash of flame
	"circle": "life",       # a seed, a womb, a gathering
	"spiral": "air",        # a whirl
	"rev_spiral": "calm",   # a whirl unwinding
	"zed": "fury",          # a sharp Z: two corners, and they survive a hot phone
	"bend_up": "sky",       # a peak, a wing
	"bend_down": "earth",   # a valley, the ground dipping
	"bend_right": "ward",   # a shelter held over something
	"bend_left": "again",   # a turn back the way you came
}

## THE TURNING SIGIL — the fourth direction, and the only rune that is not a
## thing in the world.
##
## It was deliberately UNSPOKEN: a real, reliable shape with nothing bound to
## it, kept empty rather than filled with something the grammar did not need.
## What the grammar needed turns out not to be a noun at all.
##
## SAY IT AGAIN. It is the back arrow — draw it alone and whatever you last
## cast is conjured into your hand a second time, at the potency you drew it
## and for the price you paid. Black & White's R key, and the reason that key
## existed: the hand is busy, the thing you want is the thing you just did, and
## redrawing five strokes to get it is five strokes of not watching.
##
## It costs what the working costs. This is a shortcut through the DRAWING,
## never through the price, and it is not a rune anybody has to be taught — a
## god who can cast a thing at all can say it again.
const AGAIN := "again"
## The shape it is drawn as. Kept as its own name because the recogniser talks
## in gestures and the spellbook talks in runes.
const UNSPOKEN := "bend_left"

## What one rune means on its own. Everything else is built from these, and an
## unnamed combination falls back to casting each of them together.
const BASE := {
	"water": "rain",
	"force": "lightning",
	"earth": "forage_thicket",
	"fire": "fireball",
	"life": "food",
	"air": "gust",
	"calm": "heal",
	"fury": "thunderclap",
	"sky": "bird_flock",
	"ward": "strength",
}

## NAMED RECIPES, keyed by the runes SORTED and joined — so the order you draw
## them in never matters, only which ones. Repeats are significant.
const RECIPES := {
	# Water, by the bucketful.
	"water+water": "cloudburst",
	"water+water+water": "deluge",
	# The storm ladder: rain and lightning learned apart, held together.
	"force+water": "thunderstorm",
	"force+force+water": "lightning_storm",
	"force+fury+water": "lightning_storm",
	"force+force+fury+water": "tempest",
	# FIRE, AND FIRE MEANT. Bare fire is a GOUT — a thrown lick of flame that
	# skids to a stop and guts out, lighting what it touched and leaving the
	# ground as it found it. That matters because setting something alight used
	# to be available only from a miracle that also cratered the field it hit,
	# so a player who wanted a fire had no way to ask for only a fire.
	#
	# Fury is the rune of violence done to a thing — it is what turns earth into
	# an earthquake and molten rock into a volcano — so fire under fury is the
	# detonation: the FIREBLAST, which is what `fire` alone used to be. Wanting
	# the ground to remember takes a second stroke now.
	"fire+fury": "fireblast",
	# Wind, and what wind becomes.
	"air+air": "tornado",
	"air+air+fury": "tornado",
	"air+air+water": "hurricane",
	"air+air+fury+water": "hurricane",
	"air+air+air+water": "hurricane",
	"air+fire": "firestorm",
	"air+fire+fury": "firestorm",
	# Growing things.
	"earth+life": "forest_seed",
	"life+water": "forage_thicket",
	"earth+earth": "forest_seed",
	# MOVING THE EARTH. Fury is the rune of violence done to a thing, so earth
	# under fury is the ground itself convulsing, and adding fire to that is the
	# ground splitting open. These are the first miracles that change the SHAPE
	# of the world rather than what is standing on it.
	"earth+fury": "earthquake",
	# MOLTEN ROCK. Earth and fire together is lava, and it is the answer to a
	# cratered landscape: where a fireball digs a bowl, a lavaball raises a
	# dome, and because scars simply add up, one thrown into the other FILLS
	# IT IN. It is also the volcano's parent — add fury and the same molten
	# rock stops being a thing you throw and becomes a mountain that erupts.
	"earth+fire": "lavaball",
	"earth+fire+fury": "volcano",
	# The kindly and the useful.
	"calm+life": "heal",
	# FLIGHT, TWICE OVER, and the second one is not decoration.
	#
	# Digging miracles gouge craters, and a crater is a hole a creature can
	# genuinely be standing in and unable to walk out of. That is fine — it is
	# the terrain being real — but only if the way out exists by then, and it
	# did not: fire is a tier-3 rune, the fireball dug, and flight through
	# `air+calm` needs AIR, which is tier 4. For one whole tier of the game you
	# could dig a pit you could not lift your creature out of.
	#
	# `sky` is tier 3, the same as fire, and it is already the rune of a wing.
	# So calm and a rune of the heavens — either of them — means flight, and the
	# way out is never learned later than the way in. tools/rune_sheet.py
	# asserts that invariant so it cannot quietly break again.
	#
	# Splitting the fire miracles has since closed the same gap from the other
	# side: what a tier-3 god can throw is a GOUT, which leaves the ground as it
	# found it, and the digging waits on fury at tier 4 along with the flight.
	"calm+sky": "flight",
	# Ward is shelter held over something; over water it is footing. Rain that
	# is also calm and life is not weather at all, it is a mercy.
	"ward+water": "water_walk",
	"calm+life+water": "healing_shower",
	"air+calm": "flight",
	"air+earth": "portal",
	"earth+ward": "strength",
	"life+sky": "bird_flock",
	"fire+force": "lightning",
	# THE FIRST FIVE-RUNE WORKING.  |  /  V  )  Z
	#
	# Earth and fire is molten rock; fury is violence done to it, and those
	# three are already the volcano. The last two are the AIMING: `force` is a
	# bolt driven straight, and `ward` is a thing held over something — held
	# ON it, kept on it. Molten rock, meant, driven in a line, and held on
	# whatever the god is pointing at.
	#
	# It grants the creature ONE use of it: six miniature volcanoes, three
	# blobs apiece, an eye at a time, each aimed wherever your hand is when it
	# fires. See EyeVolcano.
	"earth+fire+force+fury+ward": "eye_volcano",
	# AND ITS OPPOSITE, also five.  S  |  )  (whirl)  (whirl unwinding)
	#
	# Water, force and air is the thunderstorm the god already knows how to
	# call down on a place. `ward` puts it ROUND something instead — carried
	# with it — and `calm` is what keeps it up in the sky: a storm with calm in
	# it rumbles and flashes and never picks anyone out. See StormShroud.
	"air+calm+force+ward+water": "storm_shroud",
	# THE GRAMMAR OF THE SHROUDS, in one line: take a working that falls on a
	# SPOT, add `ward` — the rune of a thing held over something — and it
	# follows your creature about instead. The healing shower is calm, life and
	# water; warded, it is gold and silver light coming down round the beast
	# wherever it walks, mending what walks into it. See MercyShroud.
	"calm+life+ward+water": "healing_shroud",
	# AND THE QUIET ONE, which is the eyes read the other way round. Both are
	# the earth coming out of something alive: `life` is the body, `earth` the
	# ground under it. Where the eyes have fire, force and fury, this has calm
	# — and `ward`, which everywhere else in the book means "held on the
	# creature", here also means the plain thing it says, which is privacy.
	"calm+earth+life+ward": "blessed_relief",
}

## What a compound COSTS: the sum of its runes' base costs, times this per
## extra rune. Grand miracles should cost grandly, but not punitively — the
## whole point is that combining is worth doing.
const COMBO_MULTIPLIER := 0.8

## The rudiments, taught a tier at a time by the villages that come to believe.
## Everything castable follows from which of these you hold.
## AIR IS A RUDIMENT, NOT A REWARD.
##
## It was tier 4 — the last thing a god learned — and `air+calm` is FLIGHT, the
## one miracle that gets a creature out of a hole. A creature arrives in this
## world in a crater, and the first thing a player has to be taught is how to
## lift it out of one; that lesson cannot be gated behind three conversions.
## It is also the first TWO-RUNE miracle anybody draws, which makes it the place
## to teach that runes combine at all. `calm+sky` still reaches flight from the
## other side, so nothing about the old route is taken away.
const RUNE_TIERS: Array[Array] = [
	["water", "life", "calm", "air"],
	["earth", "force", "ward"],
	["fire", "sky"],
	["fury"],
]

## Plain names for the readout, so the player can learn the alphabet by using it.
const RUNE_LABEL := {
	"water": "water", "force": "force", "earth": "earth", "fire": "fire",
	"life": "life", "air": "air", "calm": "calm", "fury": "fury",
	"sky": "sky", "ward": "ward", "again": "again",
}


## The rune a drawn shape stands for, or "" if the shape means nothing.
static func rune_for(gesture: String) -> String:
	return RUNE_OF.get(gesture, "")


## The canonical key for a set of runes: sorted, so the ORDER YOU DRAW THEM IN
## never matters. Only which runes, and how many of each.
static func key_for(runes: Array) -> String:
	var sorted := runes.duplicate()
	sorted.sort()
	return "+".join(PackedStringArray(sorted))


## WHAT THIS DRAWING MEANS. Returns:
##   {"miracle": name, "potency": float}          — one effect, named or scaled
##   {"blend": [{miracle, potency}, ...]}         — several at once
## plus "runes" and "label" for the readout. An empty draw returns {}.
static func interpret(runes: Array) -> Dictionary:
	if runes.is_empty():
		return {}
	# THE TURNING SIGIL IS A WORD ON ITS OWN. MiracleManager intercepts a lone
	# one before this is ever called; anything it is mixed with is a sentence
	# with "again" in the middle of it, which means nothing. Refused here
	# rather than quietly dropped, or `again + water` would silently be rain.
	if runes.has(AGAIN):
		return {}
	var key := key_for(runes)
	# 1. A combination the world has a name for.
	if RECIPES.has(key):
		return {
			"miracle": RECIPES[key], "potency": 1.0,
			"runes": runes.duplicate(), "label": RECIPES[key],
		}
	# 2. All one rune: the same miracle, writ larger. Two waters is not two
	#    rains, it is a cloudburst — and beyond the named rungs it simply keeps
	#    getting heavier.
	var distinct := _distinct(runes)
	if distinct.size() == 1:
		var base: String = BASE.get(distinct[0], "")
		if base == "":
			return {}
		return {
			"miracle": base, "potency": 1.0 + (runes.size() - 1) * 0.75,
			"runes": runes.duplicate(), "label": base,
		}
	# 3. Anything else BLENDS: every rune's own miracle at once, each weakened
	#    for being one voice among several. Nothing the player draws is wasted.
	var parts := []
	var share := 1.0 / sqrt(float(distinct.size()))
	for rune: String in distinct:
		var base: String = BASE.get(rune, "")
		if base == "":
			continue
		var repeats := _count(runes, rune)
		parts.append({"miracle": base, "potency": share * (1.0 + (repeats - 1) * 0.6)})
	if parts.is_empty():
		return {}
	return {"blend": parts, "runes": runes.duplicate(), "label": "a working of your own"}


## Every rune this drawing needs — used to check you actually know them all.
static func runes_needed(runes: Array) -> Array:
	return _distinct(runes)


## A readable line for the HUD as the player draws: what is on the slate, and
## what it would become if they let go now.
static func describe(runes: Array) -> String:
	if runes.is_empty():
		return ""
	var drawn := []
	for rune: String in runes:
		drawn.append(RUNE_LABEL.get(rune, rune))
	# THE TURNING SIGIL HAS NO READING OF ITS OWN — its meaning is whatever you
	# last said, which the spellbook does not know and must not pretend to. It
	# says what it DOES instead, so the slate is never blank under it.
	if runes.size() == 1 and runes[0] == AGAIN:
		return "again  ▸  the last working, once more"
	var reading := interpret(runes)
	var name: String = reading.get("label", "")
	if name == "":
		return " + ".join(PackedStringArray(drawn))
	return "%s  ▸  %s" % [
		" + ".join(PackedStringArray(drawn)),
		name.capitalize().replace("_", " ")]


static func _distinct(runes: Array) -> Array:
	var seen := {}
	var out := []
	for rune: String in runes:
		if not seen.has(rune):
			seen[rune] = true
			out.append(rune)
	return out


static func _count(runes: Array, rune: String) -> int:
	var n := 0
	for r: String in runes:
		if r == rune:
			n += 1
	return n
