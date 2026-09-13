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

var alight := false
var _left := 0.0
var _spread_in := 0.0
var _fire: Node3D = null


## SET IT ALIGHT. Refused on a thing already burning, and on anything standing
## in water — the same rule wet wood has always had.
func light(who: Node3D, flame_high := 2.4) -> bool:
	if alight or not is_instance_valid(who):
		return false
	var world := who.get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null and world.is_underwater(who.global_position.x, who.global_position.z):
		return false
	alight = true
	_left = BURN_SECONDS * randf_range(0.8, 1.2)
	_spread_in = SPREAD_EVERY
	_fire = Util.small_flame(flame_high)
	who.add_child(_fire)
	SoundBank.play_at("boom", who.global_position, -9.0, 0.3)
	return true


## ONE FRAME OF BURNING. Returns the harm to do this frame — zero when it is
## not alight — so the building goes on owning its own health and its own end.
func tick(who: Node3D, delta: float) -> float:
	if not alight:
		return 0.0
	_left -= delta
	_spread_in -= delta
	if _spread_in <= 0.0:
		_spread_in = SPREAD_EVERY
		_catch_the_neighbours(who)
	if _left <= 0.0:
		douse(who)
		return 100.0        # whatever is left of it, all at once
	return 100.0 / BURN_SECONDS * delta


## Rain, a healing shower, or the last of the fuel.
func douse(who: Node3D) -> void:
	alight = false
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
	for n in who.get_tree().get_nodes_in_group("burnable"):
		var near := n as Node3D
		if near == who or not is_instance_valid(near):
			continue
		if near.global_position.distance_to(who.global_position) > SPREAD_REACH:
			continue
		if randf() > SPREAD_ODDS:
			continue
		if near.has_method("ignite"):
			near.call("ignite")
