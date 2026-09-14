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


## HOW LONG A WAIT IS WORTH COVERING. Most are a fifth of a second and want
## nothing done about them — covering those would have a town twitching into a
## stretch and out of it constantly. It is the storms that make a pause you can
## see: a wolf, a filled job, a miracle, everybody re-deciding at once.
const DITHER := 0.35
## And how often ANYBODY says anything out loud while they wait. A whole town
## greeting each other at once is not atmosphere, it is a riot.
##
## The rest is the WHOLE TOWN'S, not each villager's, because what wants
## controlling is how often you hear a voice — and because a cooldown a piece
## is state the Villager has no room for. The odds on top of it decide WHO:
## without them the first villager in tree order would take every turn, tree
## order never changes, and one man would do all the talking in the village
## forever.
const SPEAK_ODDS := 0.06
const SPEAK_REST := 5.0

static var _spoke_at := -99.0


## MAY THIS ONE CHOOSE NOW? Asks the spool, and if the answer is no, gives the
## body something to do with the wait.
##
## THE POINT IS THAT A PAUSE SHOULD LOOK LIKE THINKING. The spool bounds the
## frame by making decisions late, and a villager whose plan has run out has
## nothing to do until its turn comes. Standing perfectly still reads as a
## broken body. Stretching, yawning and passing the time of day with whoever is
## nearby reads as a person deciding what to do next — which is exactly what
## they are doing.
static func may_choose(who: Villager) -> bool:
	if Spool.turn_to_think(who):
		return true
	_pass_the_time(who)
	return false


## A word while they wait. Rate-limited twice over — by the odds and by a rest
## — because this fires on every frame of every wait in the town.
static func _pass_the_time(who: Villager) -> void:
	if Spool.stalled_for(who) < DITHER or not who.is_adult():
		return
	var now := GameState.clock
	if now - _spoke_at < SPEAK_REST or randf() > SPEAK_ODDS:
		return
	_spoke_at = now
	# The recorded line if somebody has recorded one, and the synthesized
	# murmur if not — so this does something from today and something better
	# the day a voice is dropped in res://voices/. See SoundBank.say.
	var hour := GameState.time_of_day()
	if not SoundBank.say("greet_" + hour, who.global_position):
		if not SoundBank.say("yawn", who.global_position):
			SoundBank.play_at("murmur", who.global_position, -12.0)


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
	if Vector2(who.velocity.x, who.velocity.z).length() > 0.3:
		return "walk"
	# STANDING STILL — AND WAITING ON A THOUGHT, if the wait has gone on long
	# enough to see. Deliberately the LAST thing asked, below every state above:
	# a villager whose decision is late while they are still mid-haul goes on
	# hauling, because the plan they are waiting to replace is the one they are
	# still carrying out. Only somebody with nothing left to do stretches.
	if Spool.stalled_for(who) >= DITHER:
		return "stretch"
	return "idle"


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
