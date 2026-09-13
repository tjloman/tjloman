class_name VillagerLook
extends RefCounted
## WHICH CLIP A VILLAGER IS PLAYING, and how far down it sits.
##
## Lifted out of Villager because that file lives permanently on its line cap,
## and because this is one question with one answer: what does this body look
## like it is doing right now.


## How far a body drops when it sits. Until a rig ships with a sit pose there is
## no animation to play, so the sitting is done the only way a body without one
## can do it — the whole visual drops, and the animator is asked for "sit"
## anyway. The ask costs nothing today (ModelAnimator.play keeps the current
## clip when a model has no such animation) and it is the whole point: the day a
## villager model arrives with the clip in it, this starts working with nothing
## to wire up. This is the number to turn when a real pose replaces it.
const SIT_DROP := 0.42


static func pose(who: Villager) -> String:
	# SITTING OUTRANKS THE STATE IT IS IN, because AT_SCHOOL covers a class on
	# its feet and a class on the ground alike, and only the school knows which.
	if who._seated:
		return "sit"
	match who.state:
		Villager.State.PINNED: return "fall"   # prone; no rig here has a clip for this
		Villager.State.DYING: return "dying"
		Villager.State.FALLING: return "fall"
		Villager.State.HAULING: return "carry"
		Villager.State.CIRCLING: return "play"
		Villager.State.BUILDING_NEST, Villager.State.BUILDING_SHOP, Villager.State.WORKING: return "work"
		Villager.State.GO_ARM: return "run"
		Villager.State.FIGHT: return "attack"
		Villager.State.HELD: return "idle"
		Villager.State.FLEE: return "run"
		Villager.State.SLEEPING: return "sleep"
		Villager.State.EATING: return "eat"
		Villager.State.WORSHIPPING, Villager.State.PREACHING: return "pray"
		Villager.State.PLAY: return "play"
		Villager.State.FARMING, Villager.State.CHOPPING, Villager.State.QUARRYING, Villager.State.BUILDING, \
		Villager.State.BUILDING_FARM, Villager.State.BUILDING_EDUBBA, Villager.State.BUTCHERING, \
		Villager.State.TAMING, Villager.State.HUNTING, Villager.State.FISHING, Villager.State.TEACH:
			return "work"
	# Everything else: walking if moving, otherwise idle.
	return "walk" if Vector2(who.velocity.x, who.velocity.z).length() > 0.3 else "idle"


## ARE BOTH THIS BODY AND WHERE IT IS GOING INSIDE THE TOWN?
##
## A shore probe is terrain samples — a `height_at` is five noise evaluations
## plus a walk of every scar in range — and a villager crossing its own square
## to a well, a totem, a nest ring or a workshop is walking on ground the town
## has already proved: `find_build_spot` refuses any site whose whole footprint
## is not dry and gently sloped, or whose way there crosses water. The probe can
## only ever answer "yes, fine", several times a second, for every soul in the
## town. Two squared lengths and no terrain read, which is the point of asking.
##
## The village's own influence radius rather than something wider, because that
## is the circle it builds inside. A step outside it goes back to routing, and
## the obstacle steer stays either way — trees and rocks in a village are real,
## and that one costs a grid lookup rather than the land.
static func at_home(who: Villager, target: Vector3) -> bool:
	var town := who.village
	if town == null or not is_instance_valid(town):
		return false
	var reach := town.influence_radius * town.influence_radius
	var here := town.global_position
	return Vector2(who.global_position.x - here.x, who.global_position.z - here.z) \
		.length_squared() < reach \
		and Vector2(target.x - here.x, target.z - here.z).length_squared() < reach
