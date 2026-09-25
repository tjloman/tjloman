class_name Kindling
extends RefCounted
## ANYTHING THE TOWN BUILT, ON FIRE.
##
## HOUSES WERE THE ONLY THING IN A VILLAGE THAT COULD BE HARMED AT ALL. Every
## fire miracle walked the "houses" group and nothing else, so a town could be
## burned to the ground and keep its mill, its well, its barn, its school and
## its granary standing in the ashes — and every building added since the
## houses arrived was, in effect, indestructible. A god who cannot burn a
## granary has no quarrel to press with the people who filled it.
##
## So there is one group, "burnable", and one clock. A building that catches
## takes about a minute and a half to go, which is long enough to run to with a
## bucket of rain and short enough that the decision to let it burn is a
## decision. It spreads, which is what makes a fire a fire rather than a
## targeted demolition: a mill alight beside a barn is a barn's problem.
##
## THE HOST KEEPS ITS OWN HEALTH AND ITS OWN DEATH. `tick` hands back the harm
## rather than reaching into whatever field the building happens to use, and
## the building does what collapsing means for a building of its kind — rubble
## and a roll of the roof for a house, a scattered stock for a barn. Every one
## of them already knew how to be destroyed; none of them could catch.

## How long a building burns before it is gone, and the spread.
const BURN_SECONDS := 95.0
const SPREAD_EVERY := 7.0
const SPREAD_REACH := 11.0
const SPREAD_ODDS := 0.45

## WHAT IT TAKES TO SET A THING ALIGHT — thermal mass, in heat.
##
## Nothing caught fire before; things WERE SET on fire. `light` was called and
## the thing was burning, first touch, every time, whether it was a stack of
## thatch or a stone granary. So one fireball lit a street and the material a
## building was made of meant nothing at all — which is the same flatness that
## had a flat hundred points of health standing in for every building in the
## game.
##
## Heat accumulates and BLEEDS AWAY. That is the whole mechanism and it is what
## makes the difference between a nuisance and a siege: one fireball on a house
## is a scorch mark that cools off, three in quick succession is a house on
## fire, and against the nest you had better keep throwing. It also makes
## spreading honest — a barn burning next door warms you for as long as it
## burns, and whether you catch depends on how well you are built.
##
## The scale is arbitrary and internal; HEAT_OF_A_BLAZE is the unit. A fireball
## core is one. See tools/kindle.py, which prints how many it takes for each
## thing in the game and whether a fire can still cross a lane.
const HEAT_OF_A_BLAZE := 100.0
## How fast a warmed thing sheds it again, per second.
const COOLING := 5.0
## What a burning neighbour gives you each time it reaches over.
##
## HALF AGAIN WHAT A FIREBALL IS, which looks wrong and is not: a core arrives
## once and this arrives every SPREAD_EVERY seconds at SPREAD_ODDS, against
## COOLING running the whole time in between. At a hundred and five the
## arithmetic came out NEGATIVE over a burn — the wall shed heat faster than
## the barn beside it delivered — and fire stopped crossing a lane at all,
## silently, while every other number still looked sensible.
##
## tools/kindle.py is what said so, and it fails the build if it happens again.
## A burning house should take the house next door with it in about
## three-quarters of a minute, and should never take the school.
const HEAT_FROM_NEXT_DOOR := 150.0

## WHAT THINGS ARE MADE OF. A default of timber, because most of what a village
## raises is; the ones that are not say so.
const TEMPER_TINDER := 45.0    ## dry crops, thatch — a spark will do it
const TEMPER_TIMBER := 210.0   ## a house, a workshop
const TEMPER_STORES := 300.0   ## a granary: timber, but packed and damp inside
const TEMPER_STONE := 520.0    ## a school, mostly walls
const TEMPER_MENHIR := 900.0   ## the nest, which is a rock with a fire in it

var alight := false
## How hot this thing has got, and how hot it has to get. `temper` is set by
## whatever owns this Kindling — see the TEMPER_ table above.
var heat := 0.0
var temper := TEMPER_TIMBER
var _left := 0.0
var _spread_in := 0.0
var _fire: Node3D = null


## PUT HEAT INTO IT, and light it if that was enough. This is the door every
## fire in the game comes through now: a fireball, a bolt, a neighbour burning.
## Returns true only on the frame it actually catches.
##
## `into` is what the thing is standing in — a wet thing sheds heat as fast as
## it takes it, which is the old "cannot light in water" rule expressed as a
## quantity instead of as a refusal.
func warm(who_given: Variant, joules: float, flame_high := 2.4) -> bool:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(who_given):
		return false
	var who := who_given as Node3D
	if alight or not is_instance_valid(who):
		return false
	heat += joules
	if heat < temper:
		return false
	return light(who, flame_high)


## COOL OFF. A thing that was warmed and then left alone forgets about it, which
## is what makes three fireballs in ten seconds different from three across an
## afternoon.
func cool(delta: float) -> void:
	if alight or heat <= 0.0:
		return
	heat = maxf(heat - COOLING * delta, 0.0)


## SET IT ALIGHT OUTRIGHT, with no regard for what it is made of. Kept public
## because some things are not a question — a building the player has chosen to
## burn with a miracle meant for burning buildings, a test, a story beat — but
## everything ordinary should be going through `warm`.
##
## Refused on a thing already burning, and on anything standing in water — the
## same rule wet wood has always had.
func light(who_given: Variant, flame_high := 2.4) -> bool:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(who_given):
		return false
	var who := who_given as Node3D
	if alight or not is_instance_valid(who):
		return false
	var world := who.get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null and world.is_underwater(who.global_position.x, who.global_position.z):
		return false
	alight = true
	heat = 0.0
	_left = BURN_SECONDS * randf_range(0.8, 1.2)
	_spread_in = SPREAD_EVERY
	_fire = Util.small_flame(flame_high)
	who.add_child(_fire)
	SoundBank.play_at("boom", who.global_position, -9.0, 0.3)
	# The children and the pregnant run from it; the rest come to fight it.
	Firefight.clear_the_way(who.get_tree(), who.global_position)
	return true


## ONE FRAME OF BURNING. Returns the harm to do this frame — zero when it is
## not alight — so the building goes on owning its own health and its own end.
## `most` is the building's FULL health, and passing it is what keeps a stout
## building stout without making it fireproof.
##
## This used to deal a flat hundred points over the burn, from back when every
## building in the game had exactly a hundred health. The moment a granary is
## worth seven hundred — which is the whole point of a granary — a flat hundred
## stops being a fire and becomes a scorch mark: the thing stands there blazing
## for its full minute and a half and then goes out, six sevenths intact.
##
## FIRE IS NOT AN IMPACT. A stone barn should shrug off a thrown rock and still
## burn to the ground in the same minute and a half as a hut, because what
## resists a rock is mass and what resists a fire is not being made of wood.
## Health is what a building has against BLOWS; the burn is a fraction of
## whatever that is, so the two cannot fight each other.
func smoulder(who: Node3D, delta: float, most := 100.0) -> float:
	if not alight:
		return 0.0
	_left -= delta
	_spread_in -= delta
	if _spread_in <= 0.0:
		_spread_in = SPREAD_EVERY
		_catch_the_neighbours(who)
		Firefight.clear_the_way(who.get_tree(), who.global_position)
	if _left <= 0.0:
		douse(who)
		return most        # whatever is left of it, all at once
	return most / BURN_SECONDS * delta


## Rain, a healing shower, or the last of the fuel.
func douse(who_given: Variant) -> void:
	# Untyped until proved alive: a freed object handed to a typed parameter
	# is the error, raised before any check below could run. Gone is null.
	var who: Node3D = (who_given as Node3D) if is_instance_valid(who_given) else null
	alight = false
	# AND IT IS COLD AGAIN. Rain that puts a fire out and leaves the thing one
	# spark from catching is not rain.
	heat = 0.0
	_left = 0.0
	if _fire != null and is_instance_valid(_fire):
		_fire.queue_free()
	_fire = null
	if is_instance_valid(who):
		SoundBank.play_at("whisper", who.global_position, -12.0, 0.3)


## WHAT STANDS NEXT TO IT. A fire that cannot cross a lane is not a fire, it is
## a demolition — and a village builds close enough together that one going up
## SHOULD worry the next. Rolled rather than certain, so a town can lose a mill
## without always losing the street.
func _catch_the_neighbours(who: Node3D) -> void:
	for n in who.get_tree().get_nodes_in_group(Affords.BURNABLE):
		var near := n as Node3D
		if near == who or not is_instance_valid(near):
			continue
		if near.global_position.distance_to(who.global_position) > SPREAD_REACH:
			continue
		if randf() > SPREAD_ODDS:
			continue
		# IT WARMS THEM, it does not light them. A barn burning across the lane
		# heats your wall for as long as it burns, and whether you catch is a
		# question about what you are made of. Thatch goes at once; the school
		# usually does not go at all.
		if near.has_method("scorch"):
			near.call("scorch", HEAT_FROM_NEXT_DOOR)
