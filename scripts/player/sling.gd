class_name Sling
extends Node3D
## THE WEIGHT OF THE THING IN YOUR HAND, and what it is about to do.
##
## THE PROBLEM. A held object used to be glued to the hand by a constant lerp —
## the same sixteen-per-second whether it was a chicken or a full-grown spruce.
## So everything weighed the same, nothing resisted, and the only thing that
## decided a throw was how fast the pointer happened to be moving at the instant
## you let go. On a mouse that is merely flat. On a touchscreen it is worse than
## flat, because your finger IS GONE at the moment of release and there is
## nothing on screen to have told you what was about to happen.
##
## So the hand does not hold things. It SLINGS them.
##
##   THE OBJECT TRAILS THE HAND, on a spring, and how far behind it lags is its
##   weight. A hare comes along almost with you. A bison swings out to the end
##   of its rope and takes a moment to come back, and you can FEEL the moment
##   because you can see it — the rope goes slack when you slow, and snaps
##   taut when you sweep.
##
##   AND THE ROPE IS THE AFTERTOUCH. Black & White let you keep steering a shot
##   after you had thrown it, which needs a pointer that is still on the screen
##   and therefore cannot exist on a thumb. What CAN exist is the same
##   information, moved to before the release instead of after it: the line the
##   object is swinging along, drawn out in front of you as an arc, so you are
##   aiming a thing you can see rather than guessing at a flick. Sweep, watch
##   the arc come round, let go when it points where you want it.
##
##   THE ARC IS THE PROMISE. Whatever it shows is exactly what `launch()`
##   returns — the same function, integrated forward. A prediction that is not
##   the real shot is a lie, and the player will find it out in about a minute.

## THE WEIGHT SCALE. One number, 0 (a chicken) to 1 (a bison, a great spruce),
## because everything below hangs off it and two scales would drift apart.
##
## Read off what the world already knows: a RigidBody's own mass, a beast's
## body volume against the biggest here, a tree's lumber, a person as a person.
## Nothing new is stored on anything.
const HEFT_PERSON := 0.34
const HEFT_TREE_FULL := 14.0      # lumber that counts as a full-grown giant
const HEFT_BEAST_FULL := 2.6      # body diagonal (m) that counts as a bison
const HEFT_MASS_FULL := 12.0      # RigidBody mass that counts as a full load

## HOW HARD THE HAND PULLS, per second, at nothing and at full weight. A light
## thing is nearly rigid on the hand; a heavy one is a fifth of that, which is
## the lag you feel and see.
const PULL_LIGHT := 18.0
const PULL_HEAVY := 3.4
## And how much of its own motion a heavy thing keeps when the hand stops —
## the swing-through that makes it feel slung rather than dragged.
const CARRY_LIGHT := 0.0
const CARRY_HEAVY := 0.72

## THE THROW. A heavy thing leaves the hand slower than a light one at the same
## sweep — you are throwing an ox, not a stone — but it is never so slow that
## a big throw is not worth making.
const SPEED_LIGHT := 1.0
const SPEED_HEAVY := 0.62
## And the sling ADDS: the object's own velocity relative to the hand is real
## momentum, and it is the whole reason a wind-up beats a jab.
const SLING_SHARE := 0.85

## THE BALLISTA SHOT. Sweeping up the screen with the camera low is a steep
## launch, and it should be a SHOT rather than a lob — so elevation past this
## much gets a bonus on the way out. This is what sends somebody over the hill.
const STEEP_FROM := 0.6981          # 40 degrees
const STEEP_TO := 1.2217            # 70 degrees
const STEEP_BOOST := 1.45

## FLOATER AIR TIME. Everything thrown by a god's hand falls at a fraction of
## its usual weight for a while: the game's own gravity is twice the world's, so
## a thrown villager used to come down like a dropped brick, and the whole
## pleasure of hurling somebody is watching them HANG. It eases back to normal
## rather than switching, so the landing is still a landing.
const FLOAT_SCALE := 0.42
const FLOAT_SECONDS := 2.6

## THE ROPE AND THE ARC, drawn.
const ROPE_BORE := 0.09
const ARC_STEPS := 26
const ARC_STEP_TIME := 0.14
const ARC_BORE := 0.16
const ARC_FADE := 0.55            # how much dimmer the far end of the arc is
const TAUT_AT := 2.5              # metres of lag that reads as a fully taut rope

## HOW OFTEN THE ARC IS RECOMPUTED, and how many of its beads actually ask the
## ground how high it is.
##
## THIS IS THE HOTTEST THING IN THE GAME IF YOU LET IT BE. `surface_at` is not a
## lookup: it is up to five noise samples plus nine scar-bucket lookups, every
## call. The arc was recomputing all twenty-six of them on every frame AND on
## every pointer event — and a mid-range Android panel reports touch moves at
## two to four times the frame rate, so winding up a throw was asking the
## terrain thirty thousand noise samples a second, in GDScript, at precisely the
## moment the player is owed a responsive hand.
##
## The ROPE still moves on every event, because the rope is the fast feedback
## and it costs nothing. The ARC is an aiming aid — twenty a second is far more
## than the eye asks of it — and it probes the ground every third bead and
## carries that height between, which is accurate to well inside a bead.
const ARC_EVERY := 0.05
const ARC_PROBE := 3


var hand: Node3D = null

var _rope: MeshInstance3D = null
var _arc: Array[MeshInstance3D] = []
var _shown := false
var _arc_due := 0.0


## HOW HEAVY, 0..1. Every other number in this file is a lerp on this one.
static func heft(body: Node3D) -> float:
	if body == null or not is_instance_valid(body):
		return 0.0
	if body is Villager:
		return HEFT_PERSON
	if body is Animal:
		var spec: Dictionary = (body as Animal).spec
		var box: Vector3 = spec.get("body", Vector3.ONE * 0.5)
		return clampf(box.length() / HEFT_BEAST_FULL, 0.05, 1.0)
	if body is WildTree:
		return clampf((body as WildTree).lumber / HEFT_TREE_FULL, 0.08, 1.0)
	if body is RigidBody3D:
		return clampf((body as RigidBody3D).mass / HEFT_MASS_FULL, 0.02, 1.0)
	return 0.3


## How hard the hand pulls this thing toward itself, per second.
static func pull(weight: float) -> float:
	return lerpf(PULL_LIGHT, PULL_HEAVY, clampf(weight, 0.0, 1.0))


## THE CARRY. Where the held thing should be this frame, given where it is, the
## hand, and how long since last time. The spring is all of it: a light thing
## arrives, a heavy one lags and then catches up, and the lag IS the weight.
static func follow(at: Vector3, toward: Vector3, weight: float, delta: float) -> Vector3:
	return at.lerp(toward, minf(delta * pull(weight), 1.0))


## THE SHOT. `sweep` is the hand's own velocity; `slung` is the held thing's
## velocity relative to the hand, which is the momentum a wind-up built up.
## Everything the arc draws comes out of here, so the picture cannot lie.
static func launch(sweep: Vector3, slung: Vector3, weight: float) -> Vector3:
	var w := clampf(weight, 0.0, 1.0)
	var vel := sweep + slung * SLING_SHARE
	vel *= lerpf(SPEED_LIGHT, SPEED_HEAVY, w)
	# THE BALLISTA. A steep sweep is a shot, not a lob, and gets its power back
	# — which is what makes a low camera and a hard swipe at the sky send
	# somebody over the next valley.
	var speed := vel.length()
	if speed > 0.5:
		var elev := asin(clampf(vel.y / speed, -1.0, 1.0))
		if elev > STEEP_FROM:
			var into := clampf((elev - STEEP_FROM) / (STEEP_TO - STEEP_FROM), 0.0, 1.0)
			vel *= lerpf(1.0, STEEP_BOOST, into)
	return vel


## FLOATER AIR TIME, hung on the body itself so every kind of falling thing
## reads it the same way. Set at the moment of release; read every frame by
## whatever is doing the falling.
static func loft(body: Node3D) -> void:
	if body != null and is_instance_valid(body):
		body.set_meta("loft_until", Time.get_ticks_msec() / 1000.0 + FLOAT_SECONDS)


## What gravity actually is for this body right now. Eases back to full over the
## float window rather than switching, so the fall still ends like a fall.
static func gravity_for(body: Node3D, base: float) -> float:
	if body == null or not body.has_meta("loft_until"):
		return base
	var left: float = float(body.get_meta("loft_until")) - Time.get_ticks_msec() / 1000.0
	if left <= 0.0:
		body.remove_meta("loft_until")
		return base
	var into := clampf(left / FLOAT_SECONDS, 0.0, 1.0)
	return base * lerpf(1.0, FLOAT_SCALE, into)


func _ready() -> void:
	top_level = true
	var cord := BoxMesh.new()
	cord.size = Vector3(ROPE_BORE, ROPE_BORE, 1.0)
	_rope = Util.mesh_node(cord, Color(1.0, 0.9, 0.65, 0.7), Vector3.ZERO, true) as MeshInstance3D
	_rope.visible = false
	add_child(_rope)
	for i in ARC_STEPS:
		var bead := SphereMesh.new()
		bead.radius = ARC_BORE
		bead.height = ARC_BORE * 2.0
		bead.radial_segments = 6
		bead.rings = 3
		var dot := Util.mesh_node(bead, Color(1.0, 0.88, 0.55), Vector3.ZERO, true) as MeshInstance3D
		dot.visible = false
		add_child(dot)
		_arc.append(dot)


## SHOW THE PLAYER WHAT THEY ARE HOLDING AND WHERE IT WOULD GO.
func show_it(at: Vector3, held: Vector3, shot: Vector3, weight: float) -> void:
	_shown = true
	_draw_rope(at, held, weight)
	# The arc keeps its own clock; see ARC_EVERY for why it is not the hand's.
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _arc_due:
		_arc_due = now + ARC_EVERY
		_draw_arc(held, shot)


func hide_it() -> void:
	if not _shown:
		return
	_shown = false
	_arc_due = 0.0
	_rope.visible = false
	for dot in _arc:
		dot.visible = false


## THE ROPE. Slack and dim when the thing is riding with the hand, taut and
## bright when it is swinging out behind — so the wind-up is VISIBLE, which is
## the whole of what replaces an aftertouch you cannot perform on a thumb.
func _draw_rope(at: Vector3, held: Vector3, weight: float) -> void:
	var span := at.distance_to(held)
	if span < 0.25:
		_rope.visible = false
		return
	_rope.visible = true
	_rope.global_position = at.lerp(held, 0.5)
	_rope.look_at(held, Vector3.UP)
	var taut := clampf(span / TAUT_AT, 0.0, 1.0)
	_rope.scale = Vector3(1.0 + taut * 1.6, 1.0 + taut * 1.6, span)
	var heavy := clampf(weight, 0.0, 1.0)
	_rope.transparency = lerpf(0.7, 0.0, taut) * (1.0 - heavy * 0.35)


## THE ARC. The shot, integrated forward under the same floated gravity it will
## actually fall at, a bead every ARC_STEP_TIME, stopping at the ground. The
## far end is dimmer, because the far end is the part you are least sure of.
func _draw_arc(from: Vector3, shot: Vector3) -> void:
	if shot.length() < 1.0:
		for dot in _arc:
			dot.visible = false
		return
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	var at := from
	var vel := shot
	var g := Villager.GRAVITY * FLOAT_SCALE
	var landed := false
	var ground := 0.0
	for i in _arc.size():
		var dot := _arc[i]
		if landed:
			dot.visible = false
			continue
		vel.y -= g * ARC_STEP_TIME
		at += vel * ARC_STEP_TIME
		# Every third bead asks; the two between carry the last answer, which
		# over a third of a second of flight is inside the width of a bead.
		if world != null and i % ARC_PROBE == 0:
			ground = world.surface_at(at.x, at.z)
		if at.y <= ground:
			at.y = ground
			landed = true
		dot.visible = true
		dot.global_position = at
		var far := float(i) / float(maxi(_arc.size() - 1, 1))
		dot.transparency = far * ARC_FADE
		dot.scale = Vector3.ONE * lerpf(1.0, 0.55, far)
