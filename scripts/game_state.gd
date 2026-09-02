extends Node
## Autoload singleton: global divine resources, game time, player alignment,
## and announcements. Access anywhere as `GameState`.

signal prayer_power_changed(value: float, max_value: float)
signal alignment_changed(value: float)
signal announcement(text: String)
## Casting guidance (which menu is open, what to draw, "held — throw it").
## Kept OUT of the announcement stream so the busy world can't overwrite the
## step you're mid-way through — the HUD gives it its own quiet corner.
signal cast_hint(text: String)

## One full day/night cycle, in real seconds. (The pace of the sun is the
## heartbeat of the game — tuned once, everything else derives from it.)
const DAY_SECONDS := 320.0

## A villager's whole life (60-85 "years") spans about this many day/night
## cycles — time enough to grow up, raise a family, and grow old.
const LIFE_DAYS := 40.0

## Derived: one in-game year of aging, in real seconds (~72.5y average life).
const YEAR_SECONDS := LIFE_DAYS * DAY_SECONDS / 72.5

## Derived: how many aging-years pass per day/night cycle.
const DAY_YEARS := DAY_SECONDS / YEAR_SECONDS

const GOOD_COLOR := Color(1.0, 0.9, 0.65)
const EVIL_COLOR := Color(0.75, 0.12, 0.1)

## WHAT A DIVINE THING BURNS LIKE IN THE DARK, and the one place that palette
## is decided — the god's hand and the creature it raises must speak the same
## visual language, or a saintly hand over a monstrous beast says nothing.
##
## Kept apart from `alignment_color()`, which lerps straight from red to gold
## and so makes a NEUTRAL soul a muddy orange. That is fine for a painted hand
## and quite wrong for a light: undecided should read as the plain cold white
## of moonlight, not as half-wicked.
const SAINT_LIGHT := Color(1.0, 0.88, 0.55)
const WICKED_LIGHT := Color(1.0, 0.22, 0.12)
const MOON_LIGHT := Color(0.72, 0.80, 1.0)

var prayer_power: float = 60.0
var max_prayer_power: float = 100.0

## Total elapsed game time, in years.
var game_years := 0.0

## Player karma: -100 (monstrous) .. +100 (saintly). Actions move it;
## the hand and influence ring recolor from gold to blood-red.
var alignment := 0.0

## The camera's ground focus, published each frame by CameraRig. Distant
## entities read it to throttle their own simulation — the farther from what
## the player is looking at, the fewer physics frames they spend.
var camera_focus := Vector3.ZERO

## WHAT THE CREATURE IS CALLED, once its god has named it. Every message in the
## game was written saying "Your creature", and rather than rewrite thirty
## strings — and every future one — the name is substituted at the moment a
## message is announced. One line, total coverage, and a message written the
## natural way keeps working.
var creature_name := ""


func _process(delta: float) -> void:
	game_years += delta / YEAR_SECONDS


## 0.0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk. Play starts mid-morning.
func day_fraction() -> float:
	return fmod(0.35 + game_years / DAY_YEARS, 1.0)


## -1 (deepest night) .. +1 (high noon).
func sun_elevation() -> float:
	return -cos(day_fraction() * TAU)


func is_night() -> bool:
	return sun_elevation() < -0.08


func add_prayer_power(amount: float) -> void:
	prayer_power = clampf(prayer_power + amount, 0.0, max_prayer_power)
	prayer_power_changed.emit(prayer_power, max_prayer_power)


func try_spend(amount: float) -> bool:
	if prayer_power < amount:
		return false
	prayer_power -= amount
	prayer_power_changed.emit(prayer_power, max_prayer_power)
	return true


func set_max_prayer_power(new_max: float) -> void:
	max_prayer_power = new_max
	prayer_power = minf(prayer_power, max_prayer_power)
	prayer_power_changed.emit(prayer_power, max_prayer_power)


func shift_alignment(amount: float) -> void:
	alignment = clampf(alignment + amount, -100.0, 100.0)
	alignment_changed.emit(alignment)


## Gold when good, blood-red when evil; used by the hand and influence ring.
func alignment_color() -> Color:
	return EVIL_COLOR.lerp(GOOD_COLOR, (alignment + 100.0) / 200.0)


## The colour a soul at `align` (-1..+1) gives off. Saintly gold one way,
## blood-red the other, and moon-white in the middle — see the palette above.
## Takes the alignment rather than reading it, because the creature's soul is
## its own and is very often not the god's. Not static: everything reaches it
## through the autoload, and calling a static function on an instance warns.
func divine_light(align: float) -> Color:
	if align > 0.0:
		return MOON_LIGHT.lerp(SAINT_LIGHT, minf(align, 1.0))
	return MOON_LIGHT.lerp(WICKED_LIGHT, minf(-align, 1.0))


## The same, for the god's own hand.
func hand_light() -> Color:
	return divine_light(alignment / 100.0)


func alignment_word() -> String:
	if alignment > 60.0:
		return "Saintly"
	if alignment > 20.0:
		return "Benevolent"
	if alignment > -20.0:
		return "Neutral"
	if alignment > -60.0:
		return "Cruel"
	return "Monstrous"


func announce(text: String) -> void:
	announcement.emit(named(text))


## Put the creature's name where the writing says "your creature".
func named(text: String) -> String:
	if creature_name == "":
		return text
	return text.replace("Your creature", creature_name).replace("your creature", creature_name)


func hint(text: String) -> void:
	cast_hint.emit(text)
