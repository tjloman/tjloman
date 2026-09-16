class_name HandPose
extends RefCounted
## WHAT THE HAND IS DOING WITH ITSELF.
##
## The hand was a palm and five boxes welded rigid. It had exactly one shape,
## and it wore that shape whether it was hovering over open grass, poised over a
## sheep it could pick up, squeezing a villager, or dragging the whole world
## sideways. A god's hand is the cursor in this game — it is the only thing on
## screen that is always there and always yours — and it was saying nothing.
##
## So it has four shapes and eases between them:
##
##   OPEN    nothing under it. Fingers loose, barely curled, drifting.
##   POINT   something liftable under the cursor and the cursor still moving.
##           The index reaches for it and the rest fold away. This is the whole
##           of the answer to "can I pick that up", and it is answered BEFORE
##           you press rather than after.
##   FIST    holding something. Everything clutched in hard.
##   ANCHOR  dragging the land. Fingers splayed and hooked DOWN into the
##           ground, so panning reads as the world being pulled past a hand
##           that has taken hold of it rather than as the camera sliding.
##
## Every number here is a curl in radians at the knuckle, which is why the
## fingers had to be re-hung on pivots — a box rotated about its own middle
## does not bend, it pinwheels.

## Curl per finger, index first, then the thumb — and how wide they splay.
const OPEN := {"curl": [0.18, 0.2, 0.2, 0.22], "thumb": 0.15, "splay": 0.0}
const POINT := {"curl": [-0.12, 1.5, 1.6, 1.7], "thumb": 1.1, "splay": -0.04}
const FIST := {"curl": [1.75, 1.85, 1.85, 1.8], "thumb": 1.35, "splay": -0.09}
const ANCHOR := {"curl": [1.0, 1.05, 1.05, 1.0], "thumb": 0.8, "splay": 0.22}

## How fast a shape is taken up, per second. Quick enough to feel like an
## answer, slow enough to read as a hand rather than as a sprite swap.
const EASE := 13.0
## How much idle drift an open hand has, and how fast it breathes.
const DRIFT := 0.055
const DRIFT_RATE := 1.7
## How long after the pointer last moved the hand still counts as reaching. A
## hand that keeps pointing at something you have parked on is a hand stuck in
## a pose; a hand that drops it the instant you stop is a twitch.
const REACHING := 0.45

var _curl := [0.18, 0.2, 0.2, 0.22]
var _thumb := 0.15
var _splay := 0.0
var _drift := 0.0


## Take up `shape` and write it onto the knuckles. `knuckles` are the four
## finger pivots in order, `thumb` the thumb's pivot; either may be empty, which
## is the case for a rigged custom hand model that animates itself.
func ease(shape: Dictionary, knuckles: Array, thumb: Node3D, delta: float) -> void:
	var take := clampf(1.0 - exp(-EASE * delta), 0.0, 1.0)
	var want: Array = shape["curl"]
	for i in mini(_curl.size(), want.size()):
		_curl[i] = lerpf(float(_curl[i]), float(want[i]), take)
	_thumb = lerpf(_thumb, float(shape["thumb"]), take)
	_splay = lerpf(_splay, float(shape["splay"]), take)
	# THE BREATH. An idle hand that is perfectly still is a prop; this is a
	# hair of movement, out of phase per finger so it never pulses as one.
	_drift += delta * DRIFT_RATE
	var loose := clampf(1.0 - float(_curl[0]), 0.0, 1.0)
	for i in knuckles.size():
		var joint := knuckles[i] as Node3D
		if joint == null or not is_instance_valid(joint):
			continue
		joint.rotation.x = float(_curl[i]) \
			+ sin(_drift + float(i) * 1.3) * DRIFT * loose
		joint.rotation.y = _splay * (float(i) - 1.5)
	if thumb != null and is_instance_valid(thumb):
		thumb.rotation.x = _thumb


## WHICH SHAPE THIS MOMENT CALLS FOR. `holding` and `dragging` come straight off
## the hand's state; `over` is whatever the cursor is on; `stirred` is how long
## since the pointer last moved.
static func shape_for(holding: bool, dragging: bool, over: Node3D,
		stirred: float) -> Dictionary:
	if holding:
		return FIST
	if dragging:
		return ANCHOR
	# Pointing is for things you could actually TAKE. The ground is not one, and
	# neither is a thing you are only sweeping past — a hand that snaps to a
	# point at every blade of grass the cursor crosses is noise.
	if over != null and is_instance_valid(over) and stirred < REACHING \
			and not over.is_in_group("ground"):
		return POINT
	return OPEN
