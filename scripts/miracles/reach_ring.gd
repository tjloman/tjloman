class_name ReachRing
extends Node3D
## THE CIRCLE THE CREATURE CARRIES, drawn on the grass.
##
## A faithful village already wears its ring (Village._build_influence_ring)
## and that ring is on the ground whether you are casting or not, because it
## is also the village's readout — its size is the population and its colour
## is belief. The creature's circle is a different thing: it MOVES, it is the
## only reach you have out in the wild, and a permanent ring following a
## fifteen-metre animal around would be scenery within a minute.
##
## So it appears when it matters and not before: the ground the beast holds
## lights up the moment you start drawing a rune, and again while a working is
## in your hand, and fades out when you are done. The reach limits where you
## may CAST FROM rather than where a throw may land, so the moment that matters
## is the moment the stroke begins — the game shows you the edge while you are
## standing on the right side of it.
##
## It also flares when a cast is refused for want of ground, so the answer
## arrives even if you were not looking at your feet.
##
## AND IT SOUNDS, which is the half that actually gets used. The leash
## (MiracleReach) runs down whenever the hand is off your ground, and a meter
## in the corner of a screen is no use to somebody whose eyes are on a tree
## they are carrying.
##
## BUT IT IS A WARNING, NOT A HUM. It began the moment you crossed the edge and
## held for as long as you stayed out, which on a long leash is a drone running
## under the whole of an expedition — and a sound that is always there is a
## sound nobody hears. It waits for HALF the leash to be gone now, and it stops
## dead at nothing left. So it is silent while you are comfortable, it speaks
## up when you are half spent, and it falls an octave over the half you can
## still do something about. Nobody has to be taught what that means.
##
## Its silence at the bottom is not an absence. You have just heard it fall; it
## going quiet is the last thing it says.

## How quickly it comes up and goes away, in ring-alpha per second. Up fast
## because you may already be winding up; down slow because it is pleasant.
const OPENS := 4.0
const CLOSES := 1.2
## How long a fizzle keeps it up on its own, in seconds.
const AFTER_A_FIZZLE := 2.5
## How far off the ground, so it never z-fights the grass on a slope.
const OFF_THE_GRASS := 0.35

## HOW MUCH OF THE LEASH MUST BE GONE before it says anything at all. Half.
## Below this is the part of a trip where the answer to "should I turn back"
## has stopped being obvious, and above it there is nothing to say.
const SOUNDS_BELOW := 0.5
## THE TONE'S RANGE, spread across the audible half rather than the whole
## leash. Top of its range the moment it speaks up, bottom as it runs out —
## so the fall the player actually hears is the whole octave and not half of
## one. Wide enough that halfway down is unmistakably halfway.
const PITCH_FULL := 1.55
const PITCH_SPENT := 0.7
## And how loud, and how fast it fades in and out. It sits under everything
## rather than over it — a thing you notice without being interrupted by.
const TONE_DB := -16.0
const TONE_FADE := 3.0

var divine_hand: DivineHand = null

var _ring: MeshInstance3D
var _skin: StandardMaterial3D
var _shown := 0.0
var _flare := 0.0
var _tone: AudioStreamPlayer
var _tone_up := 0.0


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.965
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	_skin = Util.mat(Color(1.0, 0.95, 0.7, 0.0), true)
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _skin
	_ring.visible = false
	add_child(_ring)

	# NOT AN AudioStreamPlayer3D. This is not a thing in the world making a
	# noise at a place; it is the state of your own reach, and it belongs in
	# your ear at a constant volume wherever the camera happens to be.
	_tone = AudioStreamPlayer.new()
	_tone.stream = SoundBank.voice("tone")
	_tone.volume_db = -80.0
	add_child(_tone)
	if _tone.stream != null:
		_tone.play()


## A fade on a piece of interface, run off the frame's own `delta` — which
## stops with the tree, so the ring holds its state through a paused temple
## rather than blinking out while you read a chart.
func _process(delta: float) -> void:
	var beast := get_tree().get_first_node_in_group("creature") as Creature
	if beast == null or not is_instance_valid(beast):
		_ring.visible = false
		return
	_flare = maxf(_flare - delta, 0.0)
	_sound_the_leash(delta)
	var want := 1.0 if (_holding_power() or _flare > 0.0) else 0.0
	_shown = move_toward(_shown, want, (OPENS if want > _shown else CLOSES) * delta)
	if _shown <= 0.001:
		_ring.visible = false
		return
	var span := MiracleReach.beast_reach(beast)
	global_position = Vector3(
		beast.global_position.x, beast.global_position.y + OFF_THE_GRASS,
		beast.global_position.z)
	_ring.scale = Vector3(span, 1.0, span)
	_ring.visible = true
	# It wears the god's alignment, exactly as a village ring does — one
	# vocabulary for "this ground is yours" across the whole game.
	var c := GameState.alignment_color().lerp(Color.WHITE, 0.15)
	_skin.albedo_color = Color(c.r, c.g, c.b, 0.5 * _shown)
	_skin.emission = c
	_skin.emission_energy_multiplier = 1.6 * _shown


## THE LEASH, IN THE EAR. Pitched by how much of it is left and audible only
## while the hand is actually off your ground — silence is the ordinary state,
## so the tone starting at all is the news.
func _sound_the_leash(delta: float) -> void:
	if _tone == null or _tone.stream == null:
		return
	var out := divine_hand != null and is_instance_valid(divine_hand) \
		and not MiracleReach.reaches(get_tree(), divine_hand.ground_point)
	var share := MiracleReach.share()
	# HALF GONE, AND NOT YET NOTHING. See SOUNDS_BELOW: a tone that runs for the
	# whole of a trip is a drone, and a drone is furniture.
	var warn := out and share > 0.0 and share <= SOUNDS_BELOW
	_tone_up = move_toward(_tone_up, 1.0 if warn else 0.0, TONE_FADE * delta)
	if _tone_up <= 0.001:
		_tone.volume_db = -80.0
		return
	# The pitch is spread over the audible half, so the fall anybody hears is
	# the whole of the range rather than the bottom of it.
	var through := clampf(share / maxf(SOUNDS_BELOW, 0.001), 0.0, 1.0)
	_tone.pitch_scale = lerpf(PITCH_SPENT, PITCH_FULL, through)
	_tone.volume_db = TONE_DB - (1.0 - _tone_up) * 40.0


## ONE MORE SECOND OF ANSWER. Called when a working guttered out for want of
## ground, so the player sees the edge they just missed.
func flare() -> void:
	_flare = AFTER_A_FIZZLE


func _holding_power() -> bool:
	if divine_hand == null or not is_instance_valid(divine_hand):
		return false
	# WHILE YOU ARE DRAWING, above all. The reach is a limit on where you may
	# CAST FROM, so the moment a casting session opens is the moment the answer
	# to "may I work here" matters — before a rune is drawn, not after one is
	# thrown. See MiracleReach.
	if divine_hand.casting:
		return true
	# AND WHENEVER THE LEASH IS RUNNING. Off your own ground the ring is the
	# thing you are trying to get back inside, so it had better be drawn.
	if not MiracleReach.reaches(get_tree(), divine_hand.ground_point):
		return true
	var held := divine_hand.held_body
	if held == null or not is_instance_valid(held):
		return false
	return held is MiracleOrb or held is Fireball
