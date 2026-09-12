class_name HerdMotion
extends RefCounted
## THE HERD'S ANIMATION, WORKED OUT ONCE AND WORN BY EVERYBODY.
##
## A herd cannot animate per beast. Two hundred reindeer cannot hold two hundred
## AnimationPlayers, and they cannot each evaluate their own sine waves either —
## that is the same O(head count) trap the herd itself was built to climb out
## of, moved one layer down.
##
## So the work is done per MOTION, not per animal. There are a handful of
## motions and a fixed number of phase offsets within each, and once a tick this
## builds the whole table: every motion at every offset, POSES_PER_TICK of them
## all told. A member of the herd does not compute anything. It holds two small
## integers — which motion, which offset — and looks its pose up. Two hundred
## head and two thousand head cost exactly the same to pose, and the cost is a
## constant somebody can read off the top of this file.
##
## THE MOTIONS ARE THE SAME NAMES THE REAL ANIMATIONS USE. `idle`, `graze`,
## `walk`, `run`, `sleep`, `play` are ModelAnimator's semantic states, which is
## what the promoted beasts near the camera actually play as GLB clips. That is
## deliberate: a member grazing as a number goes on grazing as an animal when it
## is promoted, instead of visibly changing its mind at forty metres.
##
## What a far pose can express is only what a single transform can hold — how
## far up, and how it is turned. That is enough at the distance these are seen
## from, and it is all a MultiMesh instance has.

## How many distinct phase offsets exist within one motion. Twelve is enough
## that a herd never looks like it is marching in step, and small enough that
## the whole table is trivial.
const SLOTS := 12

## rate is cycles per second; the rest are amplitudes — metres for lift,
## radians for the three turns.
const MOTION := {
	"idle": {"rate": 0.55, "lift": 0.035, "pitch": 0.02, "roll": 0.015, "yaw": 0.05},
	"graze": {"rate": 0.40, "lift": 0.020, "pitch": 0.30, "roll": 0.020, "yaw": 0.12},
	"walk": {"rate": 1.60, "lift": 0.075, "pitch": 0.05, "roll": 0.050, "yaw": 0.04},
	"run": {"rate": 3.10, "lift": 0.170, "pitch": 0.12, "roll": 0.090, "yaw": 0.03},
	"sleep": {"rate": 0.22, "lift": 0.012, "pitch": 0.05, "roll": 0.400, "yaw": 0.00},
	"play": {"rate": 2.40, "lift": 0.240, "pitch": 0.22, "roll": 0.180, "yaw": 0.30},
}

## WHAT A HERD LOOKS LIKE WHEN IT IS DOING SOMETHING, as proportions.
##
## This is the part that matters for it reading as a herd rather than as a
## formation. A grazing herd is not a herd all grazing: most have their heads
## down, a few are walking to better grass, a couple are standing with their
## heads up, and one or two are lying down. Those proportions ARE the look of
## the thing. A fleeing herd is nearly all running — but not quite, because the
## one that has not noticed yet is what makes the rest look alarmed.
const MOODS := {
	"graze": {"graze": 0.62, "walk": 0.18, "idle": 0.14, "sleep": 0.06},
	"move": {"walk": 0.78, "idle": 0.12, "graze": 0.10},
	"rest": {"sleep": 0.44, "idle": 0.36, "graze": 0.20},
	"alert": {"idle": 0.72, "walk": 0.20, "graze": 0.08},
	"flee": {"run": 0.92, "idle": 0.08},
	# Cubs and calves, who do almost nothing else for their first year.
	"young": {"play": 0.58, "idle": 0.22, "graze": 0.12, "sleep": 0.08},
}

## The whole per-tick cost of animating every herd in the world, posted where
## anyone changing SLOTS or MOTION will see what they are changing.
const POSES_PER_TICK := SLOTS * 6

## motion name -> array of SLOTS poses. A pose is (lift, pitch, roll, yaw),
## packed in a Vector4 because it is four floats and Godot has a type for that.
static var _pose := {}
static var _stamp := -1.0


## Rebuild the table for this moment, if it has not been built already. Every
## herd in the world calls this and only the first one in a given tick pays;
## that is what "the same process" means here.
static func refresh(now: float) -> void:
	if absf(now - _stamp) < 0.0001:
		return
	_stamp = now
	for name: String in MOTION:
		var m: Dictionary = MOTION[name]
		var row: Array[Vector4] = []
		var rate: float = m["rate"]
		for slot in SLOTS:
			var ph := (now * rate + float(slot) / float(SLOTS)) * TAU
			row.append(Vector4(
				sin(ph) * float(m["lift"]),
				# Pitch rides a half-rate wave so a grazing beast dips and holds
				# rather than nodding like a toy.
				(0.5 - 0.5 * cos(ph * 0.5)) * float(m["pitch"]),
				sin(ph * 0.5) * float(m["roll"]),
				sin(ph * 0.37) * float(m["yaw"])))
		_pose[name] = row


## The pose for one motion at one phase offset. Falls back to a dead-still pose
## for a motion nobody has defined, rather than failing — a missing motion
## should look wrong, not stop the herd drawing.
static func pose(motion: String, slot: int) -> Vector4:
	var row: Array = _pose.get(motion, [])
	if row.is_empty():
		return Vector4.ZERO
	return row[slot % row.size()]


## Deal one member a motion, given the herd's mood. The proportions are walked
## as a cumulative range against a single random draw, so a herd of two hundred
## comes out close to the table without anybody counting.
static func draw_motion(mood: String, roll: float) -> String:
	var mix: Dictionary = MOODS.get(mood, MOODS["graze"])
	var seen := 0.0
	for name: String in mix:
		seen += float(mix[name])
		if roll < seen:
			return name
	return "idle"


## Every motion a mood can produce, so callers can check a mood is sane without
## drawing from it a thousand times.
static func motions_of(mood: String) -> Array:
	return MOODS.get(mood, {}).keys()
