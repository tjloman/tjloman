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
const RUNE_OF := {
	"wave": "water",        # a flowing S
	"vline": "force",       # a bolt driven straight down
	"hline": "earth",       # the line of the ground
	"dline": "fire",        # a slash of flame
	"circle": "life",       # a seed, a womb, a gathering
	"spiral": "air",        # a whirl
	"rev_spiral": "calm",   # a whirl unwinding
	"zed": "fury",          # a sharp Z: two corners, and they survive a hot phone
	"caret": "sky",         # a peak, a wing
	"arc": "ward",          # a shelter held over something
}

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
	# Fireballs gouge craters, and a crater is a hole a creature can genuinely
	# be standing in and unable to walk out of. That is fine — it is the terrain
	# being real — but only if the way out exists by then. Fire is a tier-3
	# rune, so a fireball is castable at three villages; flight through
	# `air+calm` needs AIR, which is tier 4. For one whole tier of the game you
	# could dig a pit you could not lift your creature out of.
	#
	# `sky` is tier 3, the same as fire, and it is already the rune of a wing.
	# So calm and a rune of the heavens — either of them — means flight, and the
	# way out is never learned later than the way in. tools/rune_sheet.py
	# asserts that invariant so it cannot quietly break again.
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
}

## What a compound COSTS: the sum of its runes' base costs, times this per
## extra rune. Grand miracles should cost grandly, but not punitively — the
## whole point is that combining is worth doing.
const COMBO_MULTIPLIER := 0.8

## The rudiments, taught a tier at a time by the villages that come to believe.
## Everything castable follows from which of these you hold.
const RUNE_TIERS := [
	["water", "life", "calm"],
	["earth", "force", "ward"],
	["fire", "sky"],
	["air", "fury"],
]

## Plain names for the readout, so the player can learn the alphabet by using it.
const RUNE_LABEL := {
	"water": "water", "force": "force", "earth": "earth", "fire": "fire",
	"life": "life", "air": "air", "calm": "calm", "fury": "fury",
	"sky": "sky", "ward": "ward",
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
