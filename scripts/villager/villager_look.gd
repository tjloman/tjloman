class_name VillagerLook
extends RefCounted
## WHICH CLIP A VILLAGER IS PLAYING, and how far down it sits.
##
## Lifted out of Villager because that file lives permanently on its line cap,
## and because this is one question with one answer: what does this body look
## like it is doing right now.


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

## WHAT THE MEAL COSTS whoever eats a person. See `gone_to_carrion`; how a body
## looks down over one is VillagerPose.FEED.
const CARRION_COST := 25.0

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


## The clip for a rigged model. The pose itself is VillagerPose's.
static func pose(who: Villager) -> String:
	return VillagerPose.clip(who)


## IS THIS ONE DOWN OVER A BODY? Asked of what they are actually eating rather
## than of a flag, so there is nothing to keep in step and nothing to leave set.
static func eating_a_person(who: Villager) -> bool:
	if who.feeding_on != null and is_instance_valid(who.feeding_on):
		return true
	var meal := who.target_food
	return meal != null and is_instance_valid(meal) and meal.is_human_meat


## DOWN ON HANDS AND KNEES, no manners at all, the way an animal feeds.
##
## A person eating a person does not do it at a hearth and does not do it
## standing up. There is no rig with a clip for this, so it is done the way
## everything else without one is done in this file — the body drops to the
## ground and pitches forward over the meat, and the animator is asked for
## "feed" anyway, against the day a model arrives that has it.
##
## The morality and the announcement live here too rather than in the eating
## code, because they are the same event: this is what eating a person IS.
static func gone_to_carrion(who: Villager) -> void:
	who.morality = maxf(who.morality - CARRION_COST, -100.0)
	if who.village != null and who.village.is_player_home:
		GameState.announce("%s is down over a body, eating. Something in them "
			% who.villager_name + "dims.")


## AND BACK UP AFTERWARDS. Every pose in this game that puts a body on the
## ground has to be undone by somebody — a villager who ate on their knees and
## was never stood up stays face down in the grass through the rest of their
## life, which is a bug this file has shipped once already for sleep.
static func stand_up(who: Villager) -> void:
	who.sit_down(false)


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
