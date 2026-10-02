class_name VillagerFeet
extends RefCounted
## HOW A VILLAGER GETS ABOUT: walking, standing, and being set on the ground.
##
## Moved out of Villager when walking stopped going through the physics engine
## (see `step_by`), which left villager.gd too near its line limit for the next
## thing a villager learns to do.

## How steep a villager will walk up, as rise per metre (about 56 degrees), and
## how often a standing one looks at the ground again. See `step_by`.
const MOST_CLIMB := 1.5
const GROUND_RECHECK := 1.5


## WALK THERE. `placed` is the caller saying "this is somewhere the town put",
## which is the only claim that earns the shortcut past the water guard.
static func walk(who: Villager, target: Vector3, speed: float, delta: float,
		arrive: float, placed: bool) -> bool:
	var to_target := target - who.global_position
	to_target.y = 0
	if to_target.length() < arrive:
		stand(who, delta)
		return true
	var dir := to_target.normalized()
	# Steer around trees and rocks (but not the one we're walking to).
	dir = NavField.steer(who.global_position, dir, 0.4, target)
	# Villagers cannot swim: route ALONG the shore around open water rather than
	# stepping in — probing as far as THIS step will carry them, since velocity
	# is scaled by `_sim_scale` and a body on a coarse clock can stride clean
	# over a fixed 1.7m probe.
	#
	# NOT INSIDE THEIR OWN VILLAGE, THOUGH — see `_both_ends_at_home`.
	#
	# AND THE SHORTCUT IS ONLY GOOD FOR GROUND THE TOWN PROVED — which is why
	# the caller has to say what it is walking to. `at_home` skips the water
	# probe on the grounds that a village builds on nothing but dry, gently
	# sloped ground with a dry way to it. That is true of a well, a workshop, a
	# granary and a build site. It is not true of an animal, a corpse, a joint
	# of meat or a person, because none of those was PLACED — they are wherever
	# they ended up, and a drowned animal ends up at the bottom of the water.
	#
	# Inside its own circle the town took the shortcut to the meat and walked
	# in after it, one soul at a time, each drowning leaving another corpse and
	# another armful of joints in the water to draw the next.
	if not placed or not VillagerLook.at_home(who, target):
		dir = NavField.water_route(who, who.global_position, dir, who._world(),
			maxf(1.7, speed * who._sim_scale * 0.05))
	if dir == Vector3.ZERO:
		stand(who, delta)
		return false
	# THE STEP IS TAKEN, NOT SIMULATED. See `step_by`. `velocity` is still set
	# because the pose reads it to tell walking from standing; nothing moves by it.
	who.velocity = Vector3(dir.x * speed, 0.0, dir.z * speed)
	if not step_by(who, dir * speed * delta):
		who.velocity = Vector3.ZERO  # too steep: stand, and let the watchdog re-decide
		return false
	# Bodies are modeled facing +Z, and look_at aims -Z — so look away
	# from the direction of travel to face it. (Yes, everyone used to moonwalk.)
	who.look_at(who.global_position - Vector3(dir.x, 0, dir.z), Vector3.UP)
	return false


## STANDING. On the ground as it is drawn — asked again only when something has
## moved them, or every GROUND_RECHECK seconds in case the ground moved instead.
static func stand(who: Villager, delta: float) -> void:
	who.velocity = Vector3.ZERO
	who._reseat_in -= delta
	if who._reseat_in <= 0.0 \
			or Vector2(who.global_position.x, who.global_position.z) != who._placed_xz:
		settle(who)


## A STEP ON FOOT, WITHOUT THE PHYSICS ENGINE. Every villager in the world asked
## the solver to slide a capsule across the heightmap on every tick — hundreds of
## shape casts a tick for people who collide with nothing but the ground they
## stand on (they pass through each other and through buildings, and steer round
## trees and water themselves). So a step is the step: across, and onto the
## ground as it is drawn, which is what the collision was cut from anyway.
##
## THE ONE THING THE SOLVER GAVE THAT IS KEPT: a wall stops you. Ground rising
## faster than MOST_CLIMB a metre — a crater's side, a bluff — is not walked up;
## false, and they stand, and the no-progress watchdog sends them elsewhere.
## A thrown or falling villager is still a physics body; see State.FALLING.
static func step_by(who: Villager, step: Vector3) -> bool:
	var world := who._world()
	var here := who.global_position
	var to := Vector3(here.x + step.x, here.y, here.z + step.z)
	var ground := world.drawn_height_at(to.x, to.z) if world != null else to.y
	var run := Vector2(step.x, step.z).length()
	if ground - here.y > run * MOST_CLIMB + 0.05:
		settle(who)
		return false
	to.y = ground
	who.global_position = to
	who._placed_xz = Vector2(to.x, to.z)
	who._reseat_in = GROUND_RECHECK
	return true


## Onto the drawn ground, where they stand.
static func settle(who: Villager) -> void:
	var world := who._world()
	if world != null:
		who.global_position.y = world.drawn_height_at(who.global_position.x, who.global_position.z)
	who._placed_xz = Vector2(who.global_position.x, who.global_position.z)
	who._reseat_in = GROUND_RECHECK
