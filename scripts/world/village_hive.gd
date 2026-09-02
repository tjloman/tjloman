class_name VillageHive
extends RefCounted
## THE CROWD MIND.
##
## A village is not a hundred people each independently noticing a god. That is
## both wrong about crowds and ruinously expensive: every villager scanning for
## the creature, weighing what it is doing and deciding how to feel about it, a
## hundred times a second, is the thing that stops this game holding a thousand
## of them.
##
## So the village thinks ONCE. This holds what the town as a whole has lately
## seen, what it feels about it, what it is LOOKED AT, and what it is minded to
## do — recomputed a couple of times a second for the whole settlement. Each
## villager then reads those few numbers in their own decision, which costs
## nothing, and is pulled along by the crowd in proportion to how firmly the
## crowd is gripped.
##
## THE GRIP IS NEVER TOTAL. `grip()` is the share of the village swept up in the
## mood, and each villager rolls against it privately. A crowd half-mad with awe
## still has people getting on with the harvest, and that is what keeps it
## reading as a town full of people rather than a swarm under one driver.
##
## FIVE FEELINGS, and the town's posture falls out of whichever is loudest:
##
##   AWE      the god or its creature has done something wonderful
##   TERROR   something has happened that they cannot fight
##   ANGER    something has been done to them, repeatedly, by something they can
##   JOY      the ordinary good of a fed, safe, growing town — and of a party
##   SORROW   they have buried somebody
##
## And what they are LOOKED AT — the focus — is separate from how they feel
## about it, so the same rapt attention can end in worship or in a mob.

const PERIOD := 0.55           # how often the town thinks, in seconds

## How fast each feeling drains, per second. Terror runs out fastest, because a
## village that stays terrified never gets the harvest in; anger is the slowest,
## because a grudge is a grudge.
const COOL := {
	"awe": 2.2, "terror": 3.5, "anger": 0.9, "joy": 1.4, "sorrow": 0.7,
}
const LOCK_COOL := 0.22        # how fast the crowd's attention wanders off again

## What the town is minded to do. Order matters: the first that fits wins, so
## terror beats a party and a funeral beats idle curiosity.
const STANCES := ["fleeing", "mobbing", "mourning", "joining", "adoring", "watching", "calm"]

## Thresholds for each posture, and how much of the town each one sweeps up.
const FLEE_AT := 55.0
const MOB_AT := 50.0
const MOURN_AT := 45.0
const ADORE_AT := 40.0
const WATCH_AT := 0.22         # lock needed before they even turn their heads

## An invitation — the creature dancing, praying, holding court — only carries
## while it is actually happening, and only if the town does not hate the thing
## doing it.
const INVITE_HOLD := 6.0
const INVITE_WARMTH_RATE := 6.0    # joy per second while the dance goes on

var stance := "calm"
var focus: Node3D = null       # what they are all looking at, if anything
var focus_at := Vector3.INF
var focus_kind := ""           # "creature", "god", "wonder", "threat", "grave"
var lock := 0.0                # 0..1: how firmly the crowd's eye is held

var feeling := {"awe": 0.0, "terror": 0.0, "anger": 0.0, "joy": 0.0, "sorrow": 0.0}

## What they are being invited to join in with, and for how long.
var invitation := ""           # "dance", "pray", "commune"
var invite_time := 0.0
var invite_warmth := 1.0

var _think := 0.0


## SOMETHING WANTS LOOKING AT. `pull` is how compelling it is, 0..1; the
## strongest thing in the last few seconds holds the crowd's eye.
func regard(kind: String, what: Node3D, where: Vector3, pull: float) -> void:
	var strength := clampf(pull, 0.0, 1.0)
	if strength <= lock and focus_kind != "":
		return
	lock = strength
	focus_kind = kind
	focus = what
	focus_at = where


## THE TOWN SEES SOMETHING. `weight` is 0..1 of a whole event's worth.
func witness(what: String, where: Vector3, weight := 1.0) -> void:
	var w := clampf(weight, 0.0, 2.0)
	match what:
		"wonder":
			_stir("awe", 34.0 * w)
			_stir("joy", 12.0 * w)
			regard("wonder", null, where, 0.55 + 0.35 * w)
		"horror":
			_stir("terror", 40.0 * w)
			_stir("awe", 14.0 * w)
			regard("threat", null, where, 0.8)
		"outrage":
			# Something was done TO them by something they could actually fight.
			_stir("anger", 26.0 * w)
			_stir("terror", 10.0 * w)
			regard("threat", null, where, 0.7)
		"kindness":
			_stir("awe", 12.0 * w)
			_stir("joy", 20.0 * w)
		"death":
			_stir("sorrow", 30.0 * w)
			_stir("terror", 8.0 * w)
			regard("grave", null, where, 0.5)
		"plenty":
			_stir("joy", 14.0 * w)


## COME AND JOIN IN. The creature dancing, leading prayers or holding court in
## the middle of town is an invitation, and a village that is not frightened of
## it will come and take part — which is where it learns that these things are
## worth doing, and where THEY learn it from the creature in turn.
## Callers hold an invitation open by calling this every frame for as long as
## they keep it up, so this only records that the party is ON. The good of it
## accrues in `tick`, at a rate — a longer dance warms the town more, and a
## dance held for one frame warms it not at all.
func invite(what: String, who: Node3D, where: Vector3, warmth := 1.0) -> void:
	invitation = what
	invite_warmth = clampf(warmth, 0.0, 1.5)
	invite_time = INVITE_HOLD
	regard("creature", who, where, 0.5 + 0.3 * invite_warmth)


## The town's thinking, done once for everybody. Cheap by construction: a few
## dozen arithmetic operations however many people live here.
func tick(delta: float, village: Village) -> void:
	_think += delta
	# A struggling device lets the towns think less often. Twice a second and
	# once every second and a half are indistinguishable from outside a crowd.
	if _think < PERIOD * float(Quality.sim_relief()):
		return
	var step := _think
	_think = 0.0
	for name: String in feeling:
		feeling[name] = maxf(float(feeling[name]) - float(COOL[name]) * step, 0.0)
	lock = maxf(lock - LOCK_COOL * step, 0.0)
	if invitation != "":
		# The party is still going: the town warms to it at a rate, so a long
		# dance draws people in and a moment's caper does not.
		_stir("joy", INVITE_WARMTH_RATE * invite_warmth * step)
	invite_time = maxf(invite_time - step, 0.0)
	if invite_time <= 0.0:
		invitation = ""
	if lock <= 0.01:
		focus_kind = ""
		focus = null
	elif focus != null and is_instance_valid(focus):
		focus_at = focus.global_position
	_settle(village)


## Which posture the town has settled into, and how much of it is swept up.
func _settle(village: Village) -> void:
	# The town's own standing worries feed the crowd mind, so an alarmed or
	# aggrieved village is already halfway to a mob before anything new happens.
	if village != null:
		if village.is_roused():
			_stir("terror", 5.0)
		if village.hates_creature():
			_stir("anger", 4.0)
	var frightened := float(feeling["terror"])
	var furious := float(feeling["anger"])
	var grieving := float(feeling["sorrow"])
	var rapt := float(feeling["awe"])
	var glad := float(feeling["joy"])
	if frightened > FLEE_AT:
		stance = "fleeing"
	elif furious > MOB_AT and village != null and village.hates_creature():
		stance = "mobbing"
	elif grieving > MOURN_AT:
		stance = "mourning"
	elif invitation != "" and frightened < 25.0 and furious < 30.0 and glad + rapt > 12.0:
		stance = "joining"
	elif rapt > ADORE_AT:
		stance = "adoring"
	elif lock > WATCH_AT:
		stance = "watching"
	else:
		stance = "calm"


## HOW MUCH OF THE TOWN IS SWEPT UP, 0..1. Every villager rolls against this
## privately, so a crowd is never unanimous — there is always somebody who
## carries on hoeing while everyone else gapes at the sky.
func grip() -> float:
	match stance:
		"fleeing":
			return clampf(float(feeling["terror"]) / 90.0, 0.3, 0.95)
		"mobbing":
			return clampf(float(feeling["anger"]) / 100.0, 0.25, 0.8)
		"mourning":
			return clampf(float(feeling["sorrow"]) / 130.0, 0.15, 0.6)
		"joining":
			return clampf((float(feeling["joy"]) + float(feeling["awe"])) / 110.0, 0.2, 0.75)
		"adoring":
			return clampf(float(feeling["awe"]) / 110.0, 0.2, 0.7)
		"watching":
			return clampf(lock * 0.5, 0.05, 0.4)
	return 0.0


## Where the crowd's attention is pointing, or INF if it is on nothing.
func looking_at() -> Vector3:
	return focus_at if lock > 0.05 else Vector3.INF


func _stir(name: String, amount: float) -> void:
	feeling[name] = clampf(float(feeling[name]) + amount, 0.0, 130.0)


## What the town is like right now, in plain words — for the village roster and
## the workshop panel.
func report() -> String:
	if stance == "calm" and lock < WATCH_AT:
		return "going about its business"
	var loudest := ""
	var most := 8.0
	for name: String in feeling:
		if float(feeling[name]) > most:
			most = float(feeling[name])
			loudest = name
	var mood: String = {
		"awe": "in awe", "terror": "terrified", "anger": "angry",
		"joy": "in good spirits", "sorrow": "in mourning",
	}.get(loudest, "unsettled")
	var doing: String = {
		"fleeing": "scattering", "mobbing": "taking up arms", "mourning": "at a graveside",
		"joining": "joining in with your creature", "adoring": "worshipping",
		"watching": "watching", "calm": "at work",
	}.get(stance, stance)
	return "%s, %s (%d%% of them)" % [mood, doing, int(grip() * 100.0)]


## Persistence -----------------------------------------------------------------
##
## A crowd's mood is a passing thing, but its grief and its grudges are not, so
## those ride across a save while the rest is allowed to start calm.

func to_dict() -> Dictionary:
	return {"anger": float(feeling["anger"]), "sorrow": float(feeling["sorrow"])}


func from_dict(data: Dictionary) -> void:
	feeling["anger"] = clampf(float(data.get("anger", 0.0)), 0.0, 130.0)
	feeling["sorrow"] = clampf(float(data.get("sorrow", 0.0)), 0.0, 130.0)
