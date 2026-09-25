class_name Firefight
extends RefCounted
## WHEN THE TOWN IS ON FIRE, WHO RUNS AT IT AND WHO RUNS AWAY.
##
## Buildings have always been able to burn — see Kindling — but a fire in a
## village was something that happened TO it. Nobody came. A house went up,
## took the house next door, and the whole street watched it go from the square.
## Black & White had the villagers beat fires out, and that is what makes
## torching a town a contest rather than a demolition: the god sets it alight,
## the town fights back, and whether a street is lost depends on how fast the
## flames get ahead of the people beating them.
##
## WHO FIGHTS IT: grown men, and grown women who are not carrying a child.
## Everyone else — children, the pregnant — clears out of the way when a
## building catches, and does not come back to watch.

## HOW LONG IT TAKES TO BEAT A FIRE OUT, in beater-seconds. One pair of hands
## takes twenty-four seconds; four take six. A building burns for about ninety
## (Kindling.BURN_SECONDS) and takes harm the whole time, so a town that turns
## out at once saves the house and a town that is slow saves the frame of it.
const BEATEN_OUT_AFTER := 24.0
## How far the ones who cannot fight it run from it.
const FLEE_REACH := 14.0
## THE PRICE OF STANDING IN IT: the chance a second that a beater's own clothes
## catch. Low, and real — a fire you can beat without risk is a chore.
const BEATER_CATCHES := 0.01
## Where they stand to beat it: this far out from its middle, on the side they
## came from.
const BEAT_FROM := 3.2


static func can_beat(who: Villager) -> bool:
	return who.is_adult() and not who.pregnant


## IS IT BURNING? Buildings keep their fire in a Kindling; a field keeps its own.
##
## UNTYPED ON PURPOSE, and this is the line that crashed the game: a house burned
## to the ground while a beater was still running to it, and handing what was
## left of it to a parameter typed `Node` is the error, raised at the call before
## the validity check below could say "it is gone". See tools/check_calls.py.
static func ablaze(thing: Variant) -> bool:
	if not is_instance_valid(thing):
		return false
	var fire: Variant = thing.get("kindling")
	if fire is Kindling:
		return (fire as Kindling).alight
	return bool(thing.get("burning"))


## THIS MANY SECONDS OF BEATING. True when that was enough and it is out. The
## beating is kept on the thing, not on the beater, so a dozen of them working
## the same fire add up.
static func beat(thing: Node3D, seconds: float) -> bool:
	if not ablaze(thing):
		thing.remove_meta("beaten")
		return true
	var done := float(thing.get_meta("beaten", 0.0)) + seconds
	if done < BEATEN_OUT_AFTER:
		thing.set_meta("beaten", done)
		return false
	thing.remove_meta("beaten")
	thing.call("extinguish")
	return true


## Where a beater stands: at the edge, on their own side of it.
static func stand_for(who: Villager, thing: Node3D) -> Vector3:
	var away := who.global_position - thing.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	return thing.global_position + away.normalized() * BEAT_FROM


## O(N) BY DESIGN: at the moment a building catches and on the fire's spread
## beat (every Kindling.SPREAD_EVERY seconds), never on anybody's frame.
## EVERYBODY WHO CANNOT FIGHT IT, OUT OF THE WAY.
static func clear_the_way(tree: SceneTree, at: Vector3) -> void:
	for v in tree.get_nodes_in_group("villagers"):
		var soul := v as Villager
		if soul == null or not is_instance_valid(soul) or can_beat(soul):
			continue
		if soul.global_position.distance_to(at) < FLEE_REACH:
			soul.scare(at)


## ONE FRAME OF RUNNING TO IT. True when there is no longer anything to run to.
static func approach(who: Villager, delta: float) -> bool:
	if not ablaze(who._target_blaze):
		return true
	# Not `placed`: the spot beside a dockside fire can be in the lake.
	if who._move_toward(who._target, Villager.FLEE_SPEED, delta):
		who.state = Villager.State.BEATING
	return false


## ONE FRAME OF BEATING IT. True when it is out, or gone.
static func work(who: Villager, delta: float) -> bool:
	who._apply_gravity_only(delta)
	who._work_noise("pick", 0.6, delta)
	# THE PRICE OF STANDING IN IT. See BEATER_CATCHES.
	if randf() < BEATER_CATCHES * delta:
		who.ignite()
	return not is_instance_valid(who._target_blaze) or beat(who._target_blaze, delta)
