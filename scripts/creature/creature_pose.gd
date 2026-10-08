class_name CreaturePose
extends RefCounted
## ONE POSE AT A TIME, BY NUMBER — for the creature. See VillagerPose for why.
##
## The beast's body was posed from six places: the waddle as it walked, a chew
## squash while eating, a bob while fishing, a bounce at play, a pulse while
## dancing, and the roll onto its side for sleep — each writing its own part of
## the body and each with its own way back to rest, or none (a dance cut short
## left it squashed; a sleep broken by anything but waking left it on its side).
##
## Now it is one byte, worked out every frame from what it is doing, and the
## body is written whole from the table every frame: a fixed lean, and a motion
## on top. One creature, so every frame is nothing; and with every part written
## every frame, a pose cannot outlast the thing it was for. Changes are EASED —
## it rolls onto its side and back rather than snapping — and the rest of the
## body (its girth, which CreatureLook.wear owns, and its head, which
## CreatureHead turns) is not this file's.
##
## THE CODES, high nibble the band:
##   0x0_  ON ITS FEET   00 idle  01 walk  02 run  03 work  04 carry  05 play
##                       06 dance  07 eat  08 fish  09 guard  0A attack
##   0x2_  LYING         20 sleep

const IDLE := 0x00
const WALK := 0x01
const RUN := 0x02
const WORK := 0x03
const CARRY := 0x04
const PLAY := 0x05
const DANCE := 0x06
const EAT := 0x07
const FISH := 0x08
const GUARD := 0x09
const ATTACK := 0x0A
const SLEEP := 0x20

## How far a sleeping creature tips onto its side, and roughly how thick it is
## lying down as a share of its standing half-height.
const LIE_ROLL := 80.0
const LIE_THICK := 0.30
## How much of the way to a held pose (still, or lying) the body goes each
## frame, at 60 a second.
const EASE := 0.2

## CODE -> motion. The motions are below, in `_motion`.
const LOOK := {
	IDLE: "still", WALK: "waddle", RUN: "waddle", WORK: "still", CARRY: "still",
	PLAY: "bounce", DANCE: "pulse", EAT: "chew", FISH: "bob", GUARD: "still",
	ATTACK: "still", SLEEP: "lie",
}


static func of(who: Creature) -> int:
	match who.state:
		Creature.State.SLEEPING: return SLEEP
		Creature.State.EATING: return EAT
		Creature.State.FISHING: return FISH
		Creature.State.DANCE: return DANCE
	var moving := Vector2(who.velocity.x, who.velocity.z).length() > 0.5
	if moving:
		match who.state:
			Creature.State.FLEE, Creature.State.RUN, Creature.State.CATCH, \
			Creature.State.SHUN, Creature.State.DEPART:
				return RUN
		return WALK
	match who.state:
		Creature.State.PLAY, Creature.State.JUGGLE: return PLAY
		Creature.State.TENDING, Creature.State.CAST: return WORK
		Creature.State.CARRYING: return CARRY
		Creature.State.GUARD, Creature.State.COMMUNE: return GUARD
		Creature.State.SMASH: return ATTACK
	return IDLE


## Every frame: the code, and the body put in it. A rigged model's clips own its
## body; it is only told which (CreatureLook.anim_for, as it always was).
static func apply(who: Creature, delta: float) -> void:
	who.pose_code = of(who)
	if who._animator != null:
		who._animator.play(CreatureLook.anim_for(
			who.state_name(), Vector2(who.velocity.x, who.velocity.z).length() > 0.3))
		return
	if who._body == null:
		return
	var motion := String(LOOK[who.pose_code])
	var aim := _motion(who, motion)
	# A HELD POSE IS EASED INTO — onto its side, back to its feet; a rhythm is
	# not, or the waddle would lag its own step and shrink.
	var k := minf(EASE * delta * 60.0, 1.0) if motion in ["still", "lie"] else 1.0
	var at: Vector3 = aim[0]
	var lean: Vector3 = aim[1]
	who._body.position = _settle(who._body.position.lerp(at, k), at)
	who._body.rotation_degrees = _settle(who._body.rotation_degrees.lerp(lean, k), lean)
	who._body.scale.y = lerpf(who._body.scale.y, float(aim[2]), k) \
		if absf(who._body.scale.y - float(aim[2])) > 0.001 else float(aim[2])


## WHERE EACH PART OF THE BODY IS GOING: [position, rotation in degrees,
## squash]. Everything not named is at rest — which is the whole point.
static func _motion(who: Creature, motion: String) -> Array:
	# The GAME's clock, in milliseconds: held, a chew stops mid-chew.
	var t := GameState.clock * 1000.0
	var phase: float = who.steering.walk_phase
	match motion:
		"waddle":
			return [Vector3(0, absf(sin(phase)) * 0.15, 0), Vector3(0, 0, sin(phase) * 6.0), 1.0]
		"bounce":
			return [Vector3(0, absf(sin(phase)) * 0.3, 0), Vector3.ZERO, 1.0]
		"pulse":
			return [Vector3.ZERO, Vector3.ZERO, 1.0 + sin(t / 120.0) * 0.12]
		"chew":
			return [Vector3.ZERO, Vector3.ZERO, 1.0 + sin(t / 60.0) * 0.08]
		"bob":
			return [Vector3.ZERO, Vector3(sin(t / 300.0) * 10.0, 0, 0), 1.0]
		"lie":
			# ON ITS SIDE, AND STILL WHERE IT WAS STANDING. The body's origin is
			# at its feet, so a roll alone swings it out sideways by nearly its
			# own height — eighteen metres, full grown, off the bed and onto the
			# grass. The roll is paid for: pushed back along its own X by what
			# the tip took, and dropped to about the thickness of a lying beast.
			var a := deg_to_rad(LIE_ROLL)
			var mid := CreatureBody.STANDING * 0.5
			return [Vector3(mid * sin(a), mid * (LIE_THICK - cos(a)), 0.0),
				Vector3(0, 0, LIE_ROLL), 1.0]
	return [Vector3.ZERO, Vector3.ZERO, 1.0]


## Snap the last hair onto the mark, so "at rest" is exactly at rest.
static func _settle(now: Vector3, aim: Vector3) -> Vector3:
	return aim if now.distance_to(aim) < 0.001 else now
