class_name CreatureBlessings
extends RefCounted
## WHAT A GOD HAS LAID ON ITS CREATURE, and how long it lasts.
##
## Flight, footing on water — and, in time, whatever else the spellbook grows.
## These share a shape: a miracle grants one for a while, it changes how the
## beast moves, and it wears off. That shape is what this file is for; it was
## scattered through the creature itself, where every new blessing added
## another timer and another line to the movement tick.
##
## THE ONE SUBTLETY IS OVERLAP. Flight also lets the creature pass over water,
## so both blessings set `walks_on_water` — and a beast that is BOTH flying and
## blessed must not lose its footing the instant it lands. So each grant keeps
## its own clock and the shared flag is recomputed from all of them, rather than
## being switched off by whichever happens to expire first.

## How high the flight miracle holds the creature, plus a little per unit of
## size — a beast the size of a tower flies higher than a hatchling.
const FLY_HEIGHT := 9.0
const FLY_PER_SIZE := 1.5
## How fast it rises and settles, as a fraction per second.
const SETTLE := 1.6


var flight_time := 0.0
var water_walk_time := 0.0
## The shared answer the steering reads: can it cross water at a full stride?
var walks_on_water := false

var _height := 0.0        # how high flight currently holds it


func flying() -> bool:
	return flight_time > 0.0


## Lifted into the air for a while. Cast again to top up rather than restart.
func grant_flight(seconds: float) -> void:
	flight_time = maxf(flight_time, seconds)
	walks_on_water = true


## Footing on water, without the flight.
func grant_water_walking(seconds: float) -> void:
	water_walk_time = maxf(water_walk_time, seconds)
	walks_on_water = true


## Run the clocks down and move the body accordingly. Returns a word when a
## blessing has just ENDED, so the creature can announce it — this file knows
## when things expire but has no business talking to the player.
func tick(who: Creature, delta: float) -> String:
	var ended := ""
	if water_walk_time > 0.0:
		water_walk_time -= delta
		if water_walk_time <= 0.0 and flight_time <= 0.0:
			walks_on_water = false
			ended = "The water stops holding your creature up."
	var want := 0.0
	if flight_time > 0.0:
		flight_time -= delta
		want = FLY_HEIGHT + who.scale.y * FLY_PER_SIZE
		if flight_time <= 0.0:
			# Only if the blessing is not ALSO running.
			walks_on_water = water_walk_time > 0.0
			ended = "Your creature sinks back to the earth."
	_height = lerpf(_height, want, minf(delta * SETTLE, 1.0))

	var world := who.get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return ended
	if _height > 0.05:
		# Aloft: it rides above whatever is below, water and hill alike.
		var ground := maxf(
			world.height_at(who.global_position.x, who.global_position.z),
			WorldGen.WATER_LEVEL)
		who.global_position.y = ground + _height
		who.velocity.y = 0.0
		return ended
	# WALKING ON IT, not through it. Standing on the surface only reads as a
	# miracle if the beast is actually ON the surface — otherwise it strides
	# along the lake bed, which looks like a bug rather than a blessing.
	if walks_on_water \
			and world.is_underwater(who.global_position.x, who.global_position.z):
		who.global_position.y = maxf(who.global_position.y, WorldGen.WATER_LEVEL)
		if who.velocity.y < 0.0:
			who.velocity.y = 0.0
	return ended
