class_name FishingBoat
extends Node3D
## A BOAT, WHICH IS WHAT A HARBOUR LOOKS LIKE.
##
## The barn set the precedent and said why: a village with forty beasts in it
## should LOOK like a village with forty beasts in it, twice a day, in a line.
## A fishing town is the same argument about water. The dock's catch runs
## through the same shift machinery every other trade uses — it takes nothing
## and gives back fish — and none of that is visible from the shore. The boats
## are how you know.
##
## So a boat is a readout, not a simulation. It does not carry anybody, it does
## not have a hold, and nothing it does decides what the town eats. It is
## moored at the jetty; when somebody works a shift at the dock it rows out to
## the grounds and sits there; when the shift is over it comes home. A harbour
## with three boats all out is a harbour being worked, at a glance, from the
## hill above the town — which is the entire job.
##
## IT IS STILL BOUGHT WITH TIMBER. See Workshop's BOAT_LUMBER: the dock is the
## biggest single investment a village makes and the boats are on top of it,
## which is what makes a fishing town a thing a town has to commit to rather
## than a building it happens to raise.

## How fast it rows, and how far off its mooring counts as arrived.
const ROWS_AT := 2.6
const ARRIVED := 2.0
## The swell: how far it rises and how far it leans, and how fast. Small
## numbers — a boat that pitches visibly is a boat in trouble.
const BOB := 0.14
const ROLL := 0.06
const SWELL := 1.15

## Where it is tied up, and where it fishes. Both world points, both set by the
## dock that built it.
var mooring := Vector3.INF
var grounds := Vector3.INF

var _out := 0.0
var _phase := 0.0


func _ready() -> void:
	add_to_group("boats")
	_phase = randf() * TAU
	_build_hull()


## A clinker hull, a thwart and a stub of a mast. Enough to read as a boat from
## the hill, which is the only distance it is ever seen from.
func _build_hull() -> void:
	var timber := Color(0.46, 0.34, 0.22)
	add_child(Util.lite_box(Vector3(2.9, 0.42, 1.05), timber, Vector3(0, 0.21, 0)))
	# The sheer: a narrower strake above, which is what stops it reading as a
	# crate floating on its side.
	add_child(Util.lite_box(Vector3(2.4, 0.22, 0.78),
		timber.lightened(0.12), Vector3(0, 0.5, 0)))
	add_child(Util.lite_box(Vector3(0.1, 1.5, 0.1),
		timber.darkened(0.1), Vector3(-0.2, 1.1, 0)))
	add_child(Util.lite_box(Vector3(0.7, 0.08, 0.9),
		timber.darkened(0.2), Vector3(0.5, 0.46, 0)))


## PUT TO SEA for this many seconds. Called by the dock on every shift worked,
## so a busy harbour keeps its boats out and a quiet one keeps them tied up.
func put_to_sea(seconds: float) -> void:
	_out = maxf(_out, seconds)


func is_at_sea() -> bool:
	return _out > 0.0


func _process(delta: float) -> void:
	if Util.sim_stride(global_position) > 4:
		return
	_out = maxf(_out - delta, 0.0)
	var want := grounds if _out > 0.0 else mooring
	if not want.is_finite():
		return
	var here := global_position
	var flat := Vector3(want.x - here.x, 0.0, want.z - here.z)
	if flat.length() > ARRIVED:
		var step: Vector3 = flat.normalized() * minf(ROWS_AT * delta, flat.length())
		here += step
		# Facing comes off the heading rather than look_at, which would try to
		# point the hull at a spot on the water it is already level with.
		rotation.y = atan2(step.x, step.z)
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	var sea := here.y
	if world != null:
		sea = world.surface_at(here.x, here.z)
	# THE SWELL, on GameState.clock — so a paused harbour is a still one, and a
	# fleet does not lurch a minute's worth of sea the frame the temple closes.
	var beat := GameState.clock * SWELL + _phase
	here.y = sea + sin(beat) * BOB
	global_position = here
	rotation.z = sin(beat * 0.7) * ROLL
