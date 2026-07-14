extends Node
## Autoload singleton: global divine resources, game time, player alignment,
## and announcements. Access anywhere as `GameState`.

signal prayer_power_changed(value: float, max_value: float)
signal alignment_changed(value: float)
signal announcement(text: String)

## One in-game year passes every this many real seconds.
## Lifespans of 60-85 years last ~20-28 minutes of play.
const YEAR_SECONDS := 20.0

## One full day/night cycle spans this many villager years (so a villager
## lives through four or five great days — time is mythic here, not literal).
const DAY_YEARS := 16.0

const GOOD_COLOR := Color(1.0, 0.9, 0.65)
const EVIL_COLOR := Color(0.75, 0.12, 0.1)

var prayer_power: float = 60.0
var max_prayer_power: float = 100.0

## Total elapsed game time, in years.
var game_years := 0.0

## Player karma: -100 (monstrous) .. +100 (saintly). Actions move it;
## the hand and influence ring recolor from gold to blood-red.
var alignment := 0.0


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
	announcement.emit(text)
