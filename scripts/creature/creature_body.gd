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
## HOW BIG THE BEAST GETS. At 1% grown it stands about twice a villager's
## height; at full growth ~38m, a clear head above the tallest ~30m trees —
## the towering B&W silhouette over the land.
##
## STANDING is its height in its OWN units, before scale. FULL_HEIGHT is the
## ~38m itself, and it is named because other things are measured against the
## creature — a volcano is capped at a multiple of how big it will ever be —
## and those should follow from the model rather than a number typed twice.
const MIN_SCALE := 1.1
const MAX_SCALE := 15.0
const STANDING := 2.55
const FULL_HEIGHT := MAX_SCALE * STANDING

const BASE_CAPACITY := 2.0
const CAPACITY_PER_GROWTH := 20.0

## Digestion, in food units per second — and it is SLOW, on purpose. A full gut
## works harder than an almost-empty one, so how long a meal takes is tied to
## how much was actually eaten rather than being a flat drip. A hatchling's
## full belly of 2.2 units takes about two and a half minutes to work through.
const BASE_DIGESTION := 0.022
const DIGESTION_PER_GROWTH := 0.07
const DIGESTION_IDLE := 0.35    # how slowly an almost-empty gut works

## STEPS OF STATURE per unit digested, easing off as the beast gets heavy: a
## fat creature puts less of its dinner into growing.
const STATURE_PER_UNIT := 26.0

## FAT IS THE RESERVE, and this is the correction at the heart of this file.
##
## It used to be the LEFTOVERS: hunger was the fuel gauge, and fat was whatever
## was digested while hunger happened to be zero. Since hunger climbed a point
## a second and one unit of food only answered twenty-six of it, the creature
## was essentially always hungry, so there was essentially never a surplus, so
## fat essentially never moved. Measured: ten meals thirty seconds apart put on
## 2.3% fat, which is exactly what force-feeding a beast ten times looked like.
##
## Turned around, everything falls out. Fat is the store: digestion fills it,
## living and working empty it. Hunger is the body ASKING about it (see
## `appetite`), which is what it was always described as.
const FAT_PER_UNIT := 3.2
const FAT_BURN := 0.10          # per second of real exertion
const FAT_IDLE_BURN := 0.0020   # per second, living costs something
const STRENGTH_DECAY := 0.05    # per second: muscle unused is muscle lost
const STRENGTH_PER_EXERTION := 3.5

## WHAT COMES OUT. Every unit digested leaves something behind, and a beast
## carrying too much fat has a good deal more of it to be rid of — which is how
## eating past what it needs teaches its own lesson.
const WASTE_PER_UNIT := 9.0
const WASTE_WHEN_FAT := 1.7
const STUFFED := 80.0           # fat past which the waste comes faster

## HOW THE BODY ASKS. Appetite is mostly about the reserve and a little about
## the belly, so a lean creature is hungry even on a full stomach (it is still
## digesting its way out of trouble) and a fat one is quiet even on an empty
## one. HUNGER_SETTLE is how fast the felt hunger follows that.
## How long it can hold it, and when it stops being fussy about where. See
## `pressed`.
const WASTE_EASY := 45.0
const WASTE_PRESSING := 88.0

const APPETITE_FROM_FAT := 0.7
const APPETITE_FROM_BELLY := 0.3
const HUNGER_SETTLE := 0.16     # share of the gap closed per second

## The Strength miracle: a giant's grip, for a while.
const BOOST_STRENGTH := 100.0

## THE ENERGY POOL. `energy` on the creature is a BAR, 0..100, and everything
## reads it that way. What grows with the beast is the pool that bar stands
## for: a hatchling's whole reserve is a hundred units, a full-grown one's is
## nearly four hundred. So the same miracle empties a small creature and barely
## dents a large one, without a single existing tuning number having to change.
const BASE_ENERGY := 100.0
const ENERGY_PER_GROWTH := 280.0

var stomach := 0.0        # food units currently being digested
var fat := 0.0            # 0..100 — sleek to obese
var waste := 0.0          # 0..100 — how badly it needs to go
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


## Work the stomach for a frame. Returns how much GROWTH this earned; fat and
## waste move as a side effect, because they are this body's own business.
##
## Nothing here consults hunger. That is the point: what food BECOMES does not
## depend on how the creature happened to feel at the moment it swallowed.
func digest(delta: float, growth: float) -> Dictionary:
	if stomach <= 0.0:
		return {"growth": 0.0, "fattened": false}
	# A full gut works harder than an almost-empty one, so a big meal takes
	# proportionally longer to get through than a small one.
	var rate := (BASE_DIGESTION + growth * DIGESTION_PER_GROWTH) \
		* lerpf(DIGESTION_IDLE, 1.0, fullness(growth))
	var used := minf(stomach, rate * delta)
	stomach -= used
	var was := fat
	fat = minf(fat + used * FAT_PER_UNIT, 100.0)
	var heavy := WASTE_WHEN_FAT if fat > STUFFED else 1.0
	waste = minf(waste + used * WASTE_PER_UNIT * heavy, 100.0)
	return {
		# A heavy beast puts less of its dinner into growing.
		"growth": used * STATURE_PER_UNIT * (1.0 - fat / 200.0),
		"fattened": fat > was + 0.01,
	}


## WHAT THE BODY IS ASKING FOR, 0..100 — mostly about the reserve, a little
## about the belly. This is what hunger settles toward; see `settle_hunger`.
func appetite(growth: float) -> float:
	return ((1.0 - fat / 100.0) * APPETITE_FROM_FAT
		+ (1.0 - fullness(growth)) * APPETITE_FROM_BELLY) * 100.0


## Hunger eases toward what the body is asking for, rather than climbing on a
## clock of its own. So an empty lean creature gets hungry, a stuffed fat one
## goes quiet, and eating quiets it only as the food actually goes down.
func settle_hunger(hunger: float, growth: float, delta: float) -> float:
	return lerpf(hunger, appetite(growth), clampf(HUNGER_SETTLE * delta, 0.0, 1.0))


## HOW BADLY IT NEEDS TO GO, 0..1. Nothing at all below WASTE_EASY: it can
## hold it, and will keep holding it while it looks for somewhere it thinks is
## right. Past WASTE_PRESSING it stops being fussy about where.
func pressed() -> float:
	return clampf((waste - WASTE_EASY) / (100.0 - WASTE_EASY), 0.0, 1.0)


func bursting() -> bool:
	return waste >= WASTE_PRESSING


## And it goes. Returns how much came out, 0..1 of a full load, which is what
## decides how much good it does the ground it lands on.
func relieve() -> float:
	var came_out := waste / 100.0
	waste = 0.0
	return came_out


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


## How deep its reserves run, in absolute units, at this size.
func energy_pool(growth: float) -> float:
	return BASE_ENERGY + growth * ENERGY_PER_GROWTH


## What an effort of this many absolute units takes OUT OF THE BAR — the only
## place the pool and the bar are reconciled.
func toll(effort: float, growth: float) -> float:
	return clampf(effort / maxf(energy_pool(growth), 1.0) * 100.0, 0.0, 100.0)


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
	if bursting():
		return "desperate"
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
	return {"stomach": stomach, "fat": fat, "waste": waste,
		"strength": strength, "boost": boost_time}


func from_dict(data: Dictionary) -> void:
	stomach = float(data.get("stomach", 0.0))
	fat = float(data.get("fat", 0.0))
	waste = float(data.get("waste", 0.0))
	strength = float(data.get("strength", 15.0))
	boost_time = float(data.get("boost", 0.0))

