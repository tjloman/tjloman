class_name Stroll
extends RefCounted
## A WALK IS LEGS AND PAUSES, not a destination.
##
## Idling was one long walk to one far point. `VillageJobs.idle` picked a spot
## somewhere in the town's ring, the villager set off for it, and on arrival
## asked for a new plan — so an idle villager was a body crossing the parish in
## a straight line, and two hundred of them idling was two hundred straight
## lines converging on the middle of the town and stopping there.
##
## THAT IS NOT WHAT STROLLING LOOKS LIKE. A person at their leisure goes a few
## paces, stops, looks at something, and goes a few paces somewhere else. So a
## stroll is a handful of SHORT LEGS with a pause between each, and the
## direction is re-rolled every time — which turns a queue marching on the totem
## into a square with people milling about in it, for no more work than the
## straight line cost.
##
## Lifted out of Villager, which lives permanently on its line limit.

## HOW FAR ONE LEG GOES, and how long a body stands still between legs.
const LEG_LEAST := 5.0
const LEG_MOST := 20.0
const PAUSE_LEAST := 1.2
const PAUSE_MOST := 4.5
## How many legs before they stop and think about their life again. Enough that
## a stroll reads as a stroll; few enough that somebody idling is still
## available when the town wants them.
const LEGS_LEAST := 2
const LEGS_MOST := 5
## How far a leg may wander from where the stroll began. Without it a chain of
## random legs is a random walk, and a random walk leaves the village.
const ROAM := 26.0
## A PLAY leg is a child's, and children do not stroll. Shorter, faster, and
## with barely a pause in them.
const CHILD_LEG := 0.55
const CHILD_PAUSE := 0.35

## Where the stroll began, how many legs are left, and how long this pause has
## to run. Kept on the body as metas rather than as fields, because Villager has
## no room for three more and a stroll is not worth a line of it.
const FROM := "stroll_from"
const LEGS := "stroll_legs"
const REST := "stroll_rest"


## BEGIN ONE, from wherever they are standing. Called by whoever sets the state
## — the idler, or anything else that wants somebody to potter for a while.
static func begin(who: Villager) -> void:
	who.set_meta(FROM, who.global_position)
	who.set_meta(LEGS, randi_range(LEGS_LEAST, LEGS_MOST))
	who.set_meta(REST, 0.0)
	_next_leg(who)


## ONE FRAME OF STROLLING. True when the whole stroll is over and the caller
## should go and ask for a new plan.
static func walk(who: Villager, delta: float) -> bool:
	# A stroll nobody started — somebody dropped into WANDER directly, which
	# half the failure paths in Villager do. Start one now rather than standing
	# there, which is what a bare `_target` used to mean.
	if not who.has_meta(LEGS):
		begin(who)
	var playing := who.state == Villager.State.PLAY
	var rest := float(who.get_meta(REST, 0.0))
	if rest > 0.0:
		who.set_meta(REST, rest - delta)
		who._apply_gravity_only(delta)
		return false
	var pace: float = Villager.WALK_SPEED * (1.4 if playing else 0.6)
	if not who._move_toward(who._target, pace * who._speed_factor(), delta):
		who._action_time -= delta
		return who._action_time <= 0.0   # the watchdog, for a leg that is stuck
	var left := int(who.get_meta(LEGS, 0)) - 1
	who.set_meta(LEGS, left)
	if left <= 0:
		_forget(who)
		return true
	# Arrived. Stand a moment, then go somewhere else.
	var hold := randf_range(PAUSE_LEAST, PAUSE_MOST)
	who.set_meta(REST, hold * (CHILD_PAUSE if playing else 1.0))
	_next_leg(who)
	return false


## THE NEXT FEW PACES, in a direction of their own and never far from where the
## stroll started. Pulled gently back toward the middle when the walk has
## drifted, so a chain of legs mills about rather than emigrating.
static func _next_leg(who: Villager) -> void:
	var playing := who.state == Villager.State.PLAY
	var span := randf_range(LEG_LEAST, LEG_MOST) * (CHILD_LEG if playing else 1.0)
	var here := who.global_position
	var from: Vector3 = who.get_meta(FROM, here)
	var angle := randf() * TAU
	var step := Vector3(cos(angle), 0.0, sin(angle)) * span
	var want := here + step
	# Past the roaming limit, the next leg is aimed back rather than refused —
	# a person who has wandered too far turns round, they do not stand still.
	if want.distance_to(from) > ROAM:
		want = here.lerp(from, 0.7) + step * 0.3
	who._target = want
	# The watchdog: a leg that cannot be walked (a wall, a lake, a crowd) gives
	# up on its own rather than leaning on the village's forty-second timeout.
	who._action_time = span / maxf(Villager.WALK_SPEED * 0.4, 0.1) + 2.0


static func _forget(who: Villager) -> void:
	who.remove_meta(FROM)
	who.remove_meta(LEGS)
	who.remove_meta(REST)
