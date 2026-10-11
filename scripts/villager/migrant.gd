class_name Migrant
extends RefCounted
## ON THE ROAD WITH A BAND. A villager setting out for another town — to live
## there, or to trade and come home — walks with the others, at the band's pace,
## and does nothing else until it arrives: no work, no meals, no bed. The band is
## a record (Migration), and it is the record that travels; the villagers are
## what it looks like while it crosses loaded land, and they keep step with it.
##
## While on the road they are on NO town's roster (Village._refresh_roster): a
## town they have left does not count them, house them or write them down when
## it folds. Their `village` still names a standing town — the one they are
## going to, or the one they came from — because everything a villager is asked
## by the hand or the creature wants a town to answer.

## How far apart a band walks: each has its own place in the crowd, by name, so
## nobody shoves for the same spot.
const KEEPS_CLOSE := 1.6
## Close enough to the band's middle to be with it.
const WITH_IT := 6.0


static func enlist(who: Villager, band: Dictionary) -> void:
	who.journey = band
	who.remove_meta("off_the_road")       # a new road; the last one is over
	who.state = Villager.State.MIGRATE
	who.velocity = Vector3.ZERO
	if who.village != null and is_instance_valid(who.village):
		who.village.my_villagers().erase(who)


## A STEP WITH THE BAND, to its place in the crowd round the band's middle.
static func walk(who: Villager, delta: float) -> void:
	var band := who.journey
	if band.is_empty():
		who.state = Villager.State.WANDER
		who._rethink()
		return
	var at: Array = band["pos"]
	var slot := place_in(band, who.villager_name)
	var target := Vector3(float(at[0]) + slot.x, who.global_position.y, float(at[1]) + slot.y)
	if who._move_toward(target, Villager.WALK_SPEED, delta, 0.5):
		who._apply_gravity_only(delta)


## Where in the crowd one walks: a ring round the middle, by their place in it.
static func place_in(band: Dictionary, name_of: String) -> Vector2:
	var many := maxi((band.get("names", []) as Array).size(), 1)
	var i := maxi((band.get("names", []) as Array).find(name_of), 0)
	var turn := TAU * float(i) / float(many) + float(i % 3)
	var out := KEEPS_CLOSE * sqrt(float(i) + 1.0)
	return Vector2(cos(turn), sin(turn)) * out


## HOME AT LAST, or somewhere new: off the road and into `town`.
static func arrive(who: Villager, town: Village) -> void:
	who.journey = {}
	if who.village != town:
		who.home = null
	who.village = town
	who.state = Villager.State.WANDER
	if not town.my_villagers().has(who):
		town.my_villagers().append(who)
	town.adopt(who)
	who._rethink()


## WHAT A VILLAGER IS, written down: the same fields a town's record keeps
## (Village.to_dict), so a band folded out of sight is the people who walked.
static func entry_of(who: Villager) -> Dictionary:
	return {"name": who.villager_name, "female": who.is_female, "age": who.age,
		"lifespan": who.lifespan, "happiness": who.happiness, "morality": who.morality,
		"health": who.health, "weapon": who.weapon, "hunger": who.hunger, "energy": who.energy}


## AND RAISED FROM IT, into `town` (whose ground they stand on to be asked
## anything) but on the road: standing at `at`, enlisted with `band`.
static func raise(entry: Dictionary, town: Village, at: Vector3, band: Dictionary) -> Villager:
	var who := Villager.new()
	who.village = town
	who.age = float(entry.get("age", 25.0))
	who.lifespan = maxf(float(entry.get("lifespan", who.lifespan)), who.age + randf_range(1.0, 8.0))
	town.add_child(who)
	who.is_female = bool(entry.get("female", true))
	if entry.has("name"):
		who.villager_name = String(entry["name"])
	who.morality = float(entry.get("morality", 20.0))
	who.health = float(entry.get("health", 100.0))
	who.weapon = String(entry.get("weapon", ""))
	who.hunger = float(entry.get("hunger", 30.0))
	who.energy = float(entry.get("energy", 80.0))
	who.happiness = float(entry.get("happiness", who.happiness))
	who.global_position = at + Vector3(0.0, 0.6, 0.0)
	enlist(who, band)
	return who
