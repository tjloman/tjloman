class_name CreatureBody
extends RefCounted
## The creature's BODY — appetite, digestion, fat and muscle.
##
## It is not a score that goes up when it eats. It has a stomach of a real
## size: a chicken fills a hatchling, and nothing more will go in until that
## has gone down. Food digests over time, and where it GOES depends on whether
## the body needed it — nourishment when hungry, FAT when not. Fat makes it
## heavy, slow and disinclined to exert itself, and a lazy creature only gets
## fatter. Muscle is the opposite: it comes from WORK, and work is what a fat
## creature avoids, so the two pull against each other exactly as they should.
##
## Strength decides what it can pick up. A hatchling can lift a sapling; only a
## strong, grown beast can uproot a forest giant — or a creature under the
## Strength miracle, which lends it a giant's grip for a while.

## Stomach room, in food units, from hatchling to full grown. A chicken or a
## sheaf is 1 unit; a cow is several.
const BASE_CAPACITY := 2.0
const CAPACITY_PER_GROWTH := 20.0

## Digestion, in food units per second. A big body processes more at once, but
## a full stomach still takes a good while to empty.
const BASE_DIGESTION := 0.05
const DIGESTION_PER_GROWTH := 0.16

## What a digested unit is worth, and where it goes.
const NOURISHMENT := 26.0      # hunger removed per digested unit
const GROWTH_PER_UNIT := 0.006  # a well-fed creature grows
const FAT_PER_UNIT := 7.0      # food the body did NOT need becomes fat

## Fat and muscle both drift back toward nothing when unused.
const FAT_BURN := 0.35         # per second of real exertion
const FAT_IDLE_BURN := 0.02    # per second, living costs something
const STRENGTH_DECAY := 0.05   # per second: muscle unused is muscle lost
const STRENGTH_PER_EXERTION := 3.5

## The Strength miracle: a giant's grip, for a while.
const BOOST_STRENGTH := 100.0

var stomach := 0.0        # food units currently being digested
var fat := 0.0            # 0..100 — sleek to obese
var strength := 15.0      # 0..100 — earned by exertion
var boost_time := 0.0     # seconds of miracle-granted might left


## How much this body can hold, by size.
func capacity(growth: float) -> float:
	return BASE_CAPACITY + growth * CAPACITY_PER_GROWTH


## 0..1 — how full it is right now. The creature will not eat past ~full.
func fullness(growth: float) -> float:
	return clampf(stomach / maxf(capacity(growth), 0.01), 0.0, 1.0)


## Is there room for a meal of this many units?
func has_room_for(units: float, growth: float) -> bool:
	return stomach + units <= capacity(growth) * 1.05   # a last bite may squeeze in


## Swallow a meal. Returns what actually went down — a small body simply
## cannot finish a big animal, and the rest is left.
func swallow(units: float, growth: float) -> float:
	var room := maxf(capacity(growth) - stomach, 0.0)
	var taken := minf(units, room)
	stomach += taken
	return taken


## Work the stomach for a frame. Returns how much GROWTH this earned, and moves
## hunger/fat as a side effect through the values handed back.
## `hunger` is the body's current hunger (0 sated .. 100 starving).
func digest(delta: float, growth: float, hunger: float) -> Dictionary:
	if stomach <= 0.0:
		return {"growth": 0.0, "hunger": hunger, "fattened": false}
	var rate := (BASE_DIGESTION + growth * DIGESTION_PER_GROWTH) * delta
	var used := minf(stomach, rate)
	stomach -= used
	# Where does it go? Into the body if it was WANTED; onto the waistline if
	# the creature was already sated when it ate.
	var needed := clampf(hunger / NOURISHMENT, 0.0, used)
	var surplus := used - needed
	var new_hunger := maxf(hunger - needed * NOURISHMENT, 0.0)
	if surplus > 0.0:
		fat = minf(fat + surplus * FAT_PER_UNIT, 100.0)
	return {
		"growth": used * GROWTH_PER_UNIT,
		"hunger": new_hunger,
		"fattened": surplus > 0.01,
	}


## Effort builds muscle and burns fat. Called when the creature does something
## genuinely physical — hauling, smashing, running down prey, fighting.
func exert(amount: float, delta: float) -> void:
	strength = minf(strength + STRENGTH_PER_EXERTION * amount * delta, 100.0)
	fat = maxf(fat - FAT_BURN * amount * delta, 0.0)


## The slow tick of simply being alive.
func idle(delta: float) -> void:
	fat = maxf(fat - FAT_IDLE_BURN * delta, 0.0)
	strength = maxf(strength - STRENGTH_DECAY * delta, 0.0)
	if boost_time > 0.0:
		boost_time -= delta


## Effective strength, counting the miracle.
func might() -> float:
	return BOOST_STRENGTH if boost_time > 0.0 else strength


## How heavy a thing this creature can lift, in "tree lumber" terms — so a
## sapling is light and a full-grown giant needs real muscle (or a miracle).
func lift_limit(growth: float) -> float:
	return (0.6 + growth * 6.0) * (0.4 + might() / 100.0 * 1.6)


## Fat slows you down; muscle carries you. 0.6 (obese) .. ~1.15 (lean and strong).
func speed_factor() -> float:
	return clampf(1.0 - fat / 100.0 * 0.4 + might() / 100.0 * 0.15, 0.55, 1.2)


## How disinclined it is to do anything strenuous — the couch pull, 0..1.
func laziness() -> float:
	return clampf(fat / 100.0, 0.0, 1.0)


func is_boosted() -> bool:
	return boost_time > 0.0


## A plain-words readout for the dashboard.
func condition_word() -> String:
	if fat > 70.0:
		return "obese"
	if fat > 40.0:
		return "fat"
	if strength > 70.0:
		return "powerful"
	if strength > 40.0:
		return "sturdy"
	return "lean"


## Persistence -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"stomach": stomach, "fat": fat, "strength": strength, "boost": boost_time}


func from_dict(data: Dictionary) -> void:
	stomach = float(data.get("stomach", 0.0))
	fat = float(data.get("fat", 0.0))
	strength = float(data.get("strength", 15.0))
	boost_time = float(data.get("boost", 0.0))

