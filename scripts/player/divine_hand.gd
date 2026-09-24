class_name DivineHand
extends Node3D
## WALL CLOCK BY DESIGN: this times the PLAYER'S FINGER, not the world.
##
## Throw velocity is distance over elapsed time between pointer samples, and
## the reading has to survive a pause the way a resting hand does. On
## GameState.clock a stroke spanning a pause would hold two samples a hand's
## width apart with zero seconds between them, and `_stroke_is_throw` would
## find the hand still moving and hurl a rock the player merely set down. On
## the wall clock that gap reads as ten minutes, which is a hand at rest —
## which is the truth. See tools/pause_walk.py.
## The player IS this hand — B&W style. It hovers over the terrain following
## the mouse, grabs the land to pan, picks up and throws physics objects and
## villagers, and draws miracle gestures while the right button is held.

signal hover_info_changed(text: String)
## A HELD PRESS ON THE SUN OR THE MOON. The hand does not know what a temple
## is; it only knows the finger stayed on the disk. `why` is "sun" or "moon".
signal temple_asked(why: String)

enum HandState { IDLE, DRAG_LAND, HOLDING, GESTURING }

const HOVER_HEIGHT := 1.4

## THE HAND'S SPOTLIGHT (see `_build_beam`). It shines from high overhead down
## through the hand, because a lamp on a palm hovering 1.4m up lights nothing.
## At 26 degrees from 16m over the hand (so ~17.4m over the ground) that is a
## pool about SEVENTEEN METRES across — enough to work a field or find a
## villager by, without turning night into day.
const BEAM_HEIGHT := 16.0
const BEAM_ANGLE := 26.0
const BEAM_SPILL := 10.0     # how far past the ground the cone keeps reaching
const BEAM_ENERGY := 3.2
const BEAM_EASE := 1.4       # how fast it comes up at dusk and goes at dawn

const RAY_LENGTH := 500.0
## HOW FAR OFF A THING THE HAND MAY BE and still be reaching for it, in metres
## at a close camera — widened as you zoom out, because a pixel is worth more
## ground from further away. See `_nearly_under`.
const FORGIVING_PICK := 1.1
## And how many results that sweep will look at. A crowd standing on one another
## is still a bounded question.
const PICK_MOST := 12
const HIT_MASK := 1 | 2 | 4 | 8  # ground | units | props | trees
## HAND VELOCITY TO PROJECTILE VELOCITY, and the ceiling on it.
##
## SLOWED HARD, ON PURPOSE. At a boost of 1.6 into a ceiling of 55 a thrown
## thing was gone — off the top of the screen and down somewhere before you
## could turn the camera, let alone follow it, let alone get a hand under it
## again. Everything good about throwing in this game happens IN THE AIR: the
## tumble, the arc, catching your own throw, and putting a fireball through a
## pine your creature has just javelined across the valley. None of it is
## watchable at a speed that clears a valley in a second and a half.
##
## The loft in Sling does the other half — see FLOAT_SCALE and FLOAT_SECONDS,
## which hold a thrown thing up at a fraction of its weight while it travels.
## Between them a hard throw is now a thing you have time to react to.
const THROW_BOOST := 1.15
const MAX_THROW_SPEED := 38.0
## A release only THROWS if the pointer was dragged this far in one unbroken
## stroke AND was still moving at the moment of release. This is what tells a
## genuine throwing flick apart from tapping/poking around the screen (each
## poke resets the stroke), which used to fling things by accident on touch.
const THROW_MIN_STROKE := 60.0      # pixels of continuous drag
const THROW_ACTIVE_WINDOW := 0.13   # seconds; must still be moving at release

## HOW MANY HAND SAMPLES ARE KEPT, and how long a gap in the pointer's own
## reporting before the physics tick fills one in. Twenty-four is about a third
## of a second of a fast touch drag, which is the length of a throwing sweep.
const HAND_SAMPLES := 24
const QUIET_SAMPLE := 0.02
## How much of the trailing samples count as "the flick", as a SHARE of what was
## gathered rather than a fixed count — because how many samples a sweep
## produces now depends on the device, and three of eighty is not three of six.
const FLICK_SHARE := 0.3

## AFTERTOUCH (a Black & White throwback). The POWER and DIRECTION of a throw
## come from the whole sweep of the motion (the momentum); the final flick
## only SHAPES it — never overrides it, contributing about half the character
## of the arc:
##   pull back  -> raises the launch ANGLE (brief flick ~40 deg, long ~80 deg)
##   jerk aside -> curves the flight that way, spinning the projectile
## It reads from the final flick vs. the sweep, so it works on touch (where
## the finger is gone the instant you release).
const AFTERTOUCH_SECONDS := 0.45    # how long the curve keeps bending the shot
const FLICK_SAMPLES := 3            # trailing hand samples that count as "the flick"
const MAX_LOFT_DEG := 82.0          # steepest arc a hard pull-back can add
const LOFT_PER_PULL := 0.16         # radians of loft per m/s of BACKWARD flick
const CURVE_GAIN := 3.2             # sideways flick -> in-flight lateral accel
const SPIN_GAIN := 1.4              # flick deviation -> projectile spin (rad/s)
const MAX_SPIN := 11.0              # cap so a wild flick doesn't blur into a top
const BUNDLE_TOPUP := 0.06          # seconds between pulling each extra unit (hold-to-grab)
## HOW FAR A CLOSED HAND SWEEPS UP LOOSE THINGS OF ITS OWN KIND. A hand's width
## of ground and not a magnet: you gather a field of meat by dragging over it,
## which is the gesture you were going to make anyway. See `_gather_kindred`.
const GATHER_REACH := 2.6

## THE CASTING SESSION.
##
## Trying to tell drawing from dragging moment by moment does not work on a
## touchscreen — every scheme for it either steals your pans or misses your
## strokes, and the last one cast a half-finished working out from under the
## player mid-stroke. So casting is now something you deliberately ENTER.
##
## One unmistakable gesture opens it: the right button on a mouse, or a firm
## press-and-hold on bare ground under a thumb. While it is open THE WORLD IS
## LOCKED — nothing pans, nothing is picked up, and every stroke is a rune, so
## there is nothing left to disambiguate. Stop drawing for a few seconds and
## what you have drawn is cast; stop having drawn nothing, and it simply lets
## you go again.
const OPEN_HOLD := 0.45      # seconds of firm press to open casting, on touch
## And how long a press on a nest wall must be held before the stone is read.
## Longer than opening a casting: reading is a thing you settle in front of.
const READ_HOLD := 0.7
## HOW LONG A HOLD TIES THE ROPE OFF. Shorter than the stone's read, because
## tying is a thing you do repeatedly while shepherding and a long hold in the
## middle of that is the tool fighting you.
const TIE_HOLD := 0.45

## HOW A STROKE IS CAPTURED. A pointer reports every frame it moves; a rune
## does not change every frame. MIN_STEP drops points a finger has not really
## travelled to, and STROKE_CAP is the backstop. See `_add_stroke_point`.
const MIN_STEP := 3.5
const STROKE_CAP := 220
## How often the half-drawn stroke is read back, in seconds. Twelve times a
## second is faster than an eye notices and a twentieth of the work of doing it
## every frame.
const PEEK_EVERY := 0.08

const OPEN_SLOP := 16.0      # move further than this first and you meant to pan
## HOW LONG A QUIET HAND HAS BEFORE THE SESSION RESOLVES ITSELF — and there are
## two answers, because the two silences mean opposite things.
##
## BEFORE THE FIRST STROKE you are deciding what to cast, and being hurried is
## the whole problem: three seconds is thinking time. AFTER a stroke you are
## already mid-working and your finger is coming back down; the only thing the
## wait buys you there is the chance to add another rune, and every tenth of a
## second past that is a fire burning while the game waits to be told you have
## finished. Three quarters of a second is about as long as it takes to lift a
## finger and put it down again, which is exactly the gesture being waited for.
##
## IN REAL SECONDS, NOT THE WORLD'S. Casting slows time to FOCUS_TIME_SCALE, so
## the old single constant of 2.6 was really 2.6 / 0.75 = 3.5 seconds of
## wall time — the clock was slowing itself down along with everything else,
## which is most of why the wait felt so much longer than the number said. See
## `_tick_casting`, which now divides it back out the way `_tick_focus` always
## has.
const FIRST_RUNE_WAIT := 3.0
const NEXT_RUNE_WAIT := 0.75
## HOW FAR THE WORLD LEANS IN while a rune is being drawn. See `_tick_focus`.
const FOCUS_TIME_SCALE := 0.75
const FOCUS_IN := 0.30            # seconds to lean in
const FOCUS_OUT := 0.55           # and rather longer to come back out
const MAX_RUNES := 5

## THE DRUMS AND THE WHISPERS. A rune committed is a drum struck, pitched down
## and hit harder as the working grows; whispers come and go somewhere out in
## the dark for as long as the session is open.
const WHISPER_MIN := 1.6
const WHISPER_MAX := 4.2

var camera_rig: CameraRig
var miracles: MiracleManager
var trail: GestureTrail

var state := HandState.IDLE
var held_body: PhysicsBody3D = null
var hover_target: Node3D = null

## THE CASTING SESSION is open: the world is locked and every stroke is a rune.
var casting := false

## The last thing this hand threw (not placed) — the creature watches
## for it, and may catch it out of the air.
var last_thrown: Node3D = null
## THE LEAD, while it is in your hand. See LeadRope — holding it puts the hand
## in lead mode: it does not grab, a tap on earth is "go there", and a hold on
## anything ties the rope off round it.
##
## AND TYING IT OFF ENDS THAT. A tied rope is not in your hand: it works away on
## its own, the hand is a hand again, and the landscape belongs to the camera.
## Everything that asks reads `has_lead`, which is this AND `in_hand`.
var lead: LeadRope = null

var drag_anchor := Vector3.ZERO
var gesture_points := PackedVector2Array()
var ground_point := Vector3.ZERO
## WHERE THE CASTING SESSION BEGAN, on the land. Held for the whole session so
## that the reach is judged on where you planted your hand and drew, not on
## wherever the stroke wandered to. See MiracleReach.
var cast_from := Vector3.ZERO

## WHAT THE HALF-DRAWN STROKE LOOKS LIKE SO FAR — read continuously while the
## finger is down, shown by RuneReadout, and never committed to the working.
## The rune that goes on the slate is read from the finished stroke when the
## finger comes up, exactly as it always was.
var live_shape := "none"
var live_confidence := 0.0

## RECENT HAND POSITIONS, and WHEN each was seen.
##
## These used to be gathered once a physics frame and divided by a hard-coded
## sixty, which is two separate lies: the sample rate is the PHYSICS rate
## whatever the screen is doing, and the divisor is a guess at it. A touchscreen
## reports finger moves far faster than sixty a second, and on a phone that is
## dropping frames the physics tick is the slowest clock in the building — so
## the one thing a throw is made of was being measured with the coarsest ruler
## available, and then mislabelled.
##
## Now every pointer move adds a sample the moment it arrives (see _on_motion),
## the physics tick only tops up when the finger is still, and every velocity is
## measured against the clock rather than against 60.
var _pos_history: Array[Vector3] = []
var _pos_times: Array[float] = []
## The held thing lags behind the hand by its weight, and its own velocity is
## real momentum at release — see Sling.
var _held_at := Vector3.INF
var _held_vel := Vector3.ZERO
var _carried_at := 0.0
var _sling: Sling = null
## Seconds the tying hold has been down. See `_tick_tying`.
var _tying := 0.0
## How many taps in a row the last press made. See Taps.
var _taps := Taps.new()

# The current unbroken pointer stroke while HOLDING: screen positions and the
# time each was seen. Reset on every press (so a fresh poke can't inherit the
# last stroke's momentum). Used only to decide throw-vs-place.
var _stroke_pts: Array[Vector2] = []
var _stroke_times: Array[float] = []

# Aftertouch: the projectile the hand is still steering, the world-space
# lateral acceleration it's applying, and how long that lasts.
var _steer_body: Node3D = null
var _steer_accel := Vector3.ZERO
var _steer_time := 0.0

## Charging the opening press (touch only): where it began and for how long.
var _press_at := Vector2.ZERO
var _press_time := 0.0
var _reading := false
var _charging := false
## Which disk the finger came down on, or "" — see Temple.disk_at. Kept apart
## from `_charging` because it OUTRANKS it: bare sky opens the rune session
## under a thumb, and the sun is a hole cut in that.
var _on_disk := ""

## The runes drawn so far this session, and the quiet since the last stroke —
## which counts ONLY while nothing is being drawn. Letting it run mid-stroke is
## what cast a half-made miracle out of the player's hand.
var _runes: Array = []
var _idle_time := 0.0
## Has a stroke been drawn in this session at all? Keyed on the STROKE and not
## on the runes, so a scribble the recogniser could not read still puts you in
## the fast rhythm — you are plainly mid-working either way, and being given
## three seconds back because a rune failed would be a punishment dressed as
## generosity.
var _drew := false
var _peek_time := 0.0
var _whisper_time := 0.0

var _hand_material: StandardMaterial3D
var _glow: OmniLight3D
var _beam: SpotLight3D            # the column of light the hand casts at night
var _beam_energy := 0.0
var _animator: ModelAnimator = null   # non-null only for a rigged hand model
## The knuckles of the built-in hand, and its thumb — empty when a custom model
## is doing its own animating. See HandPose.
var _knuckles: Array[Node3D] = []
var _thumb_joint: Node3D = null
var _pose := HandPose.new()
## Seconds since the pointer last actually moved, which is what tells reaching
## for something apart from resting on it.
var _stirred := 99.0

# The primary pointer is still pressed (for hold-to-grab-more at a store).
var _pointer_down := false
var _bundle_time := 0.0


func _ready() -> void:
	_build_hand_mesh()
	trail = GestureTrail.new()
	add_child(trail)


func _build_hand_mesh() -> void:
	# A custom hand model replaces the palm-and-fingers; the divine glow still
	# tints with karma even when the model brings its own material.
	var custom := ModelBank.instantiate("hand")
	if custom != null:
		add_child(custom)
		_hand_material = null
		_animator = ModelAnimator.create(custom)
	else:
		# One shared material so the whole hand recolors with the player's karma.
		_hand_material = Util.mat(GameState.alignment_color())
		# Palm.
		_add_hand_part(Util.box(Vector3(0.9, 0.18, 1.0), Color.WHITE, Vector3.ZERO))
		# FOUR FINGERS, EACH ON A KNUCKLE. The box used to be a child of the
		# hand at its finished position, which is fine for a hand that never
		# moves and useless for one that has to close: rotating a box about its
		# own middle does not bend a finger, it pinwheels one. The pivot sits at
		# the palm's edge where a knuckle is, and the box hangs off it. See
		# HandPose.
		for i in 4:
			var x := -0.33 + i * 0.22
			var length := 0.55 if (i == 1 or i == 2) else 0.45
			var knuckle := Node3D.new()
			knuckle.position = Vector3(x, 0.0, -0.5)
			add_child(knuckle)
			var digit := Util.box(Vector3(0.16, 0.15, length), Color.WHITE,
				Vector3(0.0, 0.0, -length * 0.5))
			digit.material_override = _hand_material
			knuckle.add_child(digit)
			_knuckles.append(knuckle)
		# Thumb, on its own pivot for the same reason.
		_thumb_joint = Node3D.new()
		_thumb_joint.position = Vector3(0.42, 0.0, 0.05)
		_thumb_joint.rotation_degrees.y = -40
		add_child(_thumb_joint)
		var thumb := Util.box(Vector3(0.16, 0.15, 0.42), Color.WHITE,
			Vector3(0.0, 0.0, -0.21))
		thumb.material_override = _hand_material
		_thumb_joint.add_child(thumb)
	# Faint divine glow: the aura on the hand itself and whatever it is holding.
	_glow = OmniLight3D.new()
	_glow.light_color = GameState.hand_light()
	_glow.light_energy = 0.6
	_glow.omni_range = 4.0
	_glow.position = Vector3(0, 0.5, 0)
	add_child(_glow)
	_build_beam()
	GameState.alignment_changed.connect(_on_alignment_changed)


## THE SHAFT OF LIGHT FROM THE HEAVENS.
##
## The hand hovers barely a metre off the ground, so a lamp ON it lights a
## dinner plate. This is a column instead: the source sits high overhead and
## points straight down THROUGH the hand, which is both the only way to get a
## fair pool of light out of it and the right image for a god — you move your
## hand across the land and a circle of daylight moves with it.
##
## It carries the god's own alignment, so at night the whole world under your
## hand is lit gold, or red, or plain moon-white (see GameState.divine_light).
## And it is night-only, eased in with the dark: by day the sun does this job
## better, and a spotlight competing with it is a wasted light.
func _build_beam() -> void:
	_beam = SpotLight3D.new()
	_beam.position = Vector3(0, BEAM_HEIGHT, 0)
	_beam.rotation_degrees = Vector3(-90, 0, 0)   # a spot points down its own -Z
	_beam.spot_range = BEAM_HEIGHT + BEAM_SPILL
	_beam.spot_angle = BEAM_ANGLE
	_beam.spot_angle_attenuation = 1.6            # a soft edge, not a hard disc
	_beam.spot_attenuation = 0.9
	_beam.light_color = GameState.hand_light()
	_beam.light_energy = 0.0
	_beam.light_specular = 0.1
	# Never shadowed. A shadowed spot this wide, moving every frame, is the most
	# expensive thing that could possibly be added to a phone build.
	_beam.shadow_enabled = false
	_beam.visible = false
	add_child(_beam)


func _add_hand_part(part: MeshInstance3D) -> void:
	part.material_override = _hand_material
	add_child(part)


## The hand's FLESH keeps the old straight red-to-gold ramp; its LIGHT takes the
## divine palette, where an undecided god burns moon-white rather than a muddy
## half-wicked orange. See GameState.divine_light.
func _on_alignment_changed(_value: float) -> void:
	if _hand_material != null:
		_hand_material.albedo_color = GameState.alignment_color()
	var lit := GameState.hand_light()
	_glow.light_color = lit
	if _beam != null:
		_beam.light_color = lit


## How brightly the column is burning, how wide a circle it lays on the ground,
## and what colour it is — for the readouts and the smoke test.
func beam_energy() -> float:
	return _beam_energy


func beam_width() -> float:
	return 2.0 * tan(deg_to_rad(BEAM_ANGLE)) * (BEAM_HEIGHT + HOVER_HEIGHT)


func beam_color() -> Color:
	return _beam.light_color if _beam != null else Color.WHITE


## Bring the column up as the dark comes on, and put it out at dawn. Eased, so
## dusk lights the lamp rather than flicking a switch.
func _tick_beam(delta: float) -> void:
	if _beam == null:
		return
	var darkness := clampf(-GameState.sun_elevation() * 2.2, 0.0, 1.0)
	_beam_energy = move_toward(_beam_energy, BEAM_ENERGY * darkness, BEAM_EASE * delta)
	_beam.light_energy = _beam_energy
	_beam.visible = _beam_energy > 0.01


func _physics_process(delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	_update_hover(mouse_pos)

	# THE LEASH, PAID OUT WHEREVER THE HAND IS. Out past the ground you hold it
	# runs down at a metre a second for every metre beyond the edge; inside, it
	# fills back to whole in five. This is the only thing that moves the meter,
	# and it runs every frame because the meter is about WHERE YOU ARE rather
	# than about anything you did. See MiracleReach.
	MiracleReach.pay_out(get_tree(), ground_point, delta)

	# The hand rests on whatever the mouse is over; fall back to the y=0 plane.
	var target := ground_point + Vector3(0, HOVER_HEIGHT, 0)
	target.y += sin(Time.get_ticks_msec() / 400.0) * 0.08  # idle bob
	global_position = global_position.lerp(target, minf(delta * 14.0, 1.0))
	GameState.hand_at = global_position   # what the player is about to reach for

	# Yaw-follow: the hand turns with the camera's heading (palm-down, B&W
	# style), so it reads right from any angle. Eased so it swings, not snaps.
	if camera_rig != null:
		rotation.y = lerp_angle(rotation.y, camera_rig.rotation.y, minf(delta * 8.0, 1.0))

	# A rigged hand model plays grab/cast/idle clips as the hand works.
	if _animator != null:
		_animator.play(_anim_state())
	_tick_pose(delta)

	# TOP UP ONLY WHEN THE POINTER IS QUIET. While a finger is moving, _on_motion
	# is already sampling at the rate the screen reports — far faster than this
	# — and adding a duplicate here on every physics tick would flatten the
	# very velocity we are trying to read.
	if _pos_times.is_empty() \
			or Time.get_ticks_msec() / 1000.0 - _pos_times[_pos_times.size() - 1] > QUIET_SAMPLE:
		_sample_hand()
	_carry_lead()

	# Aftertouch: keep bending a freshly thrown projectile for a short window.
	if _steer_time > 0.0:
		if is_instance_valid(_steer_body):
			_steer_time -= delta
			_apply_in_flight(_steer_body, _steer_accel * delta)
		else:
			_steer_time = 0.0
			_steer_body = null

	_tick_press_charge(delta)
	_tick_casting(delta)
	_tick_beam(delta)

	match state:
		HandState.DRAG_LAND:
			var plane_point := _mouse_on_plane(mouse_pos, drag_anchor.y)
			camera_rig.pan_world(drag_anchor - plane_point)
		HandState.HOLDING:
			# The pointer already carried it if a finger moved this frame; this
			# keeps it coming when the finger is STILL and the hand is not.
			var now := Time.get_ticks_msec() / 1000.0
			_carry_held(minf(now - _carried_at, 0.1))
			_carried_at = now
			if is_instance_valid(held_body):
				_tick_bundle_grab(delta)
		HandState.GESTURING:
			trail.points = gesture_points
			trail.queue_redraw()
			_tick_peek(delta)


## ONE HAND SAMPLE, stamped with the real clock.
## THE ROPE IS IN YOUR HAND, so its near end is wherever your hand is. Written
## every frame rather than pushed on a timer: the LINE has to be live even
## though what it SAYS to the creature is not. See LeadRope.TUG_EVERY.
func _carry_lead() -> void:
	if lead == null or not is_instance_valid(lead):
		lead = null
		return
	if lead.in_hand:
		lead.hand_at = global_position + Vector3(0.0, -0.4, 0.0)
	else:
		# IT WAS TIED OFF WHILE YOU WERE HOLDING IT (see LeadRope.tie), which
		# is the end of the holding. Letting the reference go is what makes the
		# hand empty everywhere at once rather than in the one place that
		# remembered to ask — and the rope is not lost by it: it is in the
		# world, tied to the thing, and LeadRope.on finds it again.
		lead = null


## TAKE UP THE LEAD, or put it down. The one entry point, so the button and the
## key cannot come to different conclusions.
func hold_lead(rope: LeadRope) -> void:
	# AND YOUR HAND EMPTIES FIRST. You cannot hold a sheep and a rope: a hand
	# with the lead in it does not grab, and the release path returns early for
	# the lead — so taking up the rope while carrying something left that thing
	# GLUED to the hand with no way on earth to let go of it, the sling's rope
	# and aim arc drawn over it for the rest of the session, and `hands_busy`
	# stuck true, which costs the far half of the world a simulation stride.
	# Set down, gently, wherever it was: nothing is thrown by accident.
	if is_instance_valid(held_body):
		_release_body(held_body, Vector3.ZERO, true)
		held_body = null
		state = HandState.IDLE
	_stow_sling()
	lead = rope
	if rope != null:
		# AND TAKING IT UP TAKES IT OFF THE POST. A rope cannot be tied to a
		# tree and in your hand at the same time: that is the state in which a
		# tap on bare earth meant "untie it and haul the creature over here",
		# which is not what a tap on the landscape should ever mean while the
		# beast is tied up somewhere. See LeadRope.take_up.
		rope.take_up(global_position)


func let_go_of_lead() -> void:
	if lead != null and is_instance_valid(lead):
		lead.in_hand = false
	lead = null


func has_lead() -> bool:
	return lead != null and is_instance_valid(lead) and lead.in_hand


func _sample_hand() -> void:
	_pos_history.append(global_position)
	_pos_times.append(Time.get_ticks_msec() / 1000.0)
	while _pos_history.size() > HAND_SAMPLES:
		_pos_history.pop_front()
		_pos_times.pop_front()


## THE SLUNG THING, moved. Called from the physics tick AND from every pointer
## move, because INPUT LAG IS NOT ACCEPTABLE: what you are holding must answer
## the finger at the rate the finger reports, not at the rate a hot phone
## happens to be simulating. When the device is struggling the answer is less
## simulation (see Quality.report_frame), never a slower hand.
func _carry_held(delta: float) -> void:
	if not is_instance_valid(held_body):
		held_body = null
		state = HandState.IDLE
		_stow_sling()
		return
	if delta <= 0.0:
		return
	var carry := ground_point + Vector3(0, HOVER_HEIGHT - 0.6, 0)
	if _held_at == Vector3.INF:
		_held_at = held_body.global_position
	var weight := Sling.heft(held_body)
	var was := _held_at
	_held_at = Sling.follow(_held_at, carry, weight, delta)
	# ITS OWN VELOCITY, which is the momentum a wind-up builds and the plain
	# reason a swung ox goes further than a jabbed one.
	var moved := (_held_at - was) / delta
	_held_vel = _held_vel.lerp(moved, minf(delta * 12.0, 1.0))
	held_body.global_position = _held_at
	_show_sling(weight)


## THE ROPE AND THE ARC. Everything the arc draws comes out of the same
## `Sling.launch` the release uses, so what you are shown is what you get.
func _show_sling(weight: float) -> void:
	if _sling == null or not is_instance_valid(_sling):
		_sling = Sling.new()
		_sling.hand = self
		get_tree().current_scene.add_child(_sling)
	# NOTHING IN THE HAND IS NOT SOMEWHERE. `_held_at` is Vector3.INF until
	# something is actually grasped, and a rope drawn to infinity is a non-finite
	# transform the renderer complains about once a frame.
	if not _held_at.is_finite():
		_sling.hide_it()
		return
	var shot := Sling.launch(_sweep_velocity(), _held_vel - _sweep_velocity(), weight)
	_sling.show_it(global_position, _held_at, shot, weight)


## A FRESH GRIP. The rope starts where the thing is, not where the last one was
## let go of, and the sweep is measured from now — inheriting either would throw
## the new object with the old one's momentum.
func _begin_carry() -> void:
	# The far world takes a stride off so the hand can have the frames.
	Quality.hands_busy = true
	_held_at = held_body.global_position if is_instance_valid(held_body) else Vector3.INF
	_held_vel = Vector3.ZERO
	_carried_at = Time.get_ticks_msec() / 1000.0
	_pos_history.clear()
	_pos_times.clear()
	_sample_hand()


func _stow_sling() -> void:
	Quality.hands_busy = false
	_held_at = Vector3.INF
	_held_vel = Vector3.ZERO
	if is_instance_valid(_sling):
		_sling.hide_it()


func _update_hover(mouse_pos: Vector2) -> void:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)

	var query := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH, HIT_MASK)
	if is_instance_valid(held_body):
		query.exclude = [held_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	hover_target = null
	if hit.is_empty():
		if state == HandState.HOLDING and dir.y > -0.02:
			# Winding up a throw at open sky: the hand rises along the ray
			# so it can be released in a real arc. Empty-handed, the hand
			# stays on the land instead of leaping into midair.
			ground_point = from + dir * clampf(camera_rig.zoom_distance, 15.0, 45.0)
		else:
			ground_point = _mouse_on_plane(mouse_pos)
	else:
		# WHERE THE RAY LANDED, INCLUDING UNDER THE WATER.
		#
		# This clamped to y >= 0, which is the sea's surface — so a hand
		# pointed at the seabed stopped at the top of the water and everything
		# lying on the bottom became ungrabbable. A drowned animal's meat sits
		# a metre and a half down; the hand hovered over it, the forgiving pick
		# searched a sphere at the surface and found nothing, and `_gather_kindred`
		# measured its 2.6m from a hand that could not get within 2.9m of the
		# pile it was trying to join. That is the whole of "the water plane
		# prevents me from grabbing all the meat at once".
		#
		# The clamp is still right for the OTHER case, where the ray hit
		# nothing at all and the hand rests on the water rather than falling
		# through the world — and that case is `_mouse_on_plane`, which is a
		# y = 0 plane by construction and needs no clamping to stay there.
		ground_point = hit.position
		var collider = hit.collider
		if is_instance_valid(collider) and collider is Node3D \
				and not (collider as Node3D).is_in_group("ground"):
			hover_target = collider

	# AND IF THE RAY FOUND ONLY GROUND, LOOK AROUND IT.
	#
	# A villager is a capsule about half a metre across and a fingertip is
	# eleven millimetres of glass. The pick was one infinitely thin ray, so
	# taking hold of a person on a phone meant hitting a target the width of a
	# pencil line while the camera drifted — which is the whole of "grabbing
	# animals and grain is still somewhat finicky", and it is worse for the
	# things you most want to grab, because people and sheep are thin and
	# houses are not.
	#
	# The exact ray still wins wherever it lands on something. This only runs
	# when it found nothing but earth, so pointing AT a thing is unchanged and
	# pointing NEAR one now works.
	if hover_target == null:
		hover_target = _nearly_under(ground_point)

	hover_info_changed.emit(describe(hover_target))


## THE NEAREST THING WORTH TAKING HOLD OF, within a forgiving radius of where
## the hand is. Asked only when the ray hit nothing but ground — see
## `_update_hover`.
##
## Bounded by construction: one shape query against the props-and-units layers,
## and a walk over however few results come back. It does not look at the whole
## world and it does not care how many villagers the town has.
func _nearly_under(at: Vector3) -> Node3D:
	var reach := FORGIVING_PICK * clampf(camera_rig.zoom_distance / 30.0, 1.0, 2.5)
	var ball := SphereShape3D.new()
	ball.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = HIT_MASK
	if is_instance_valid(held_body):
		query.exclude = [held_body.get_rid()]
	var best: Node3D = null
	var closest := INF
	for found in get_world_3d().direct_space_state.intersect_shape(query, PICK_MOST):
		var node := found.get("collider") as Node3D
		if node == null or not is_instance_valid(node) or node.is_in_group("ground"):
			continue
		# ONLY THINGS A HAND HAS BUSINESS WITH. A forgiving pick that snapped to
		# scenery would make the ground harder to point at, not easier.
		if not (node.is_in_group(Affords.PICKABLE)
				or node.is_in_group(Affords.QUARRIED)
				or node is FoodStore):
			continue
		var gap := node.global_position.distance_to(at)
		if gap < closest:
			closest = gap
			best = node
	return best


## WHAT TO CALL THE THING UNDER THE HAND. Public because it is not only the
## hover line that has to say it: the announcement when you tie the rope off
## comes from Main, and a message reading "tied to @CharacterBody3D@114918" is
## one the player is entitled to call a bug.
func describe(target: Node3D) -> String:
	if target == null:
		return ""
	if target.has_method("hover_text"):
		return str(target.call("hover_text"))
	if target is CreatureNest:
		# THE ONE THING IN THE WORLD THAT ANSWERS A LONG PRESS WITH WORDS, and
		# nothing anywhere said so. A player who does not already know holds
		# nothing, because there is no reason to try.
		return "The Nest — hold on the stone wall to read it"
	if target.has_meta("hover_name"):
		return str(target.get_meta("hover_name"))
	return target.name


## Ray/plane intersection at a given height — used for land-dragging on
## hills (the drag plane sits at the grab point's altitude).
func _mouse_on_plane(mouse_pos: Vector2, plane_y := 0.0) -> Vector3:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var denom := dir.y
	if absf(denom) < 0.0001:
		return ground_point
	var t := (plane_y - from.y) / denom
	if t < 0.0:
		return ground_point
	return from + dir * t


func _unhandled_input(event: InputEvent) -> void:
	# While two fingers are down the camera owns the screen — ignore the
	# emulated mouse events the first finger still produces.
	if camera_rig != null and camera_rig.is_multitouching():
		return
	if event is InputEventMouseButton:
		_on_pointer_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_pointer_motion(event as InputEventMouseMotion)
	elif casting and event is InputEventKey and event.is_pressed() \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_close_casting(false)   # never trapped: escape always lets you out


func _on_pointer_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		# The spare button both OPENS the session and draws in it, so the old
		# habit — hold the right button and draw — still works exactly as it
		# did, and now each drag is simply one more rune.
		if event.pressed:
			if not casting:
				_open_casting()
			if casting:
				_begin_stroke(event.position)
		elif state == HandState.GESTURING:
			_end_stroke()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	_pointer_down = event.pressed
	if event.pressed:
		# HOW MANY TIMES IN A ROW — read first and acted on last, so everything
		# a single press already does goes on happening and the double is only
		# ever a SECOND meaning laid over it. See Taps.
		var run := _taps.pressed(event.position,
			Time.get_ticks_msec() / 1000.0)
		if run >= 2 and _tapped_twice():
			return
		# Every fresh press begins a new stroke: a poke can never inherit the
		# momentum of the drag before it.
		_reset_stroke(event.position)
		_press_at = event.position
		_press_time = 0.0
		# Inside the session there is no such thing as a grab or a pan, so this
		# is unambiguously the start of a rune.
		if casting:
			_begin_stroke(event.position)
			return
		# Bare ground, pressed and held, is what opens the session under a
		# thumb — the one place there is no second button to spare.
		# HOLDING THE STONE READS IT. The nest wall is the one thing in the world
		# that answers a long press with words rather than with a grab, which is
		# what makes walking to it worth doing.
		# THE DISK FIRST. A press on the sun is a press on the temple door and
		# is never a grab, a pan, or the casting summons — which is the whole
		# reason the doorway is the disk and not the sky it sits in.
		_on_disk = ""
		if state == HandState.IDLE and not is_instance_valid(held_body):
			_on_disk = Temple.disk_at(camera_rig.camera, event.position)
		if _on_disk != "":
			_reading = false
			_charging = false
			return
		# THE LEAD OWNS THE HAND WHILE IT IS IN IT. No grabbing, no land drag,
		# no casting summons: a hand with a rope in it is doing one thing. A
		# hold ties the far end round whatever is under it; a tap on bare earth
		# sends the creature there. See `_tick_press_charge` and `_on_release`.
		if has_lead():
			_reading = false
			_charging = false
			_tying = 0.0
			return
		_reading = hover_target is CreatureNest and state == HandState.IDLE
		_charging = _touch_only() and state == HandState.IDLE \
			and not _on_something_grabbable() and not _reading
		# NOT WHILE READING. The nest is not grabbable and not a store, so
		# _on_grab fell through to its last branch and started a LAND DRAG —
		# press the stone wall and the world swung out from under your
		# finger. On a mouse that is merely confusing; on a thumb, where the
		# drag and the hold are the same gesture, it makes the stone simply
		# unreadable. That is why it was so hard to bring up.
		if not _charging and not _reading:
			_on_grab()
		return
	# Released.
	_charging = false
	# Let go of the sun before it opened: that was a look, not a summons.
	if _on_disk != "":
		_on_disk = ""
		hover_info_changed.emit("")
		return
	if state == HandState.GESTURING:
		_end_stroke()
	elif not casting:
		_on_release()


func _on_pointer_motion(event: InputEventMouseMotion) -> void:
	_stirred = 0.0          # the hand is reaching, not resting. See `_tick_pose`.
	if state == HandState.GESTURING:
		_add_stroke_point(event.position)
	elif _on_disk != "":
		# Slid off the disk: the sky is not the sun, and a drag up there is a
		# throw being wound up or a camera being turned.
		if Temple.disk_at(camera_rig.camera, event.position) == "":
			_on_disk = ""
			hover_info_changed.emit("")
	elif _charging:
		# Moved before the press matured: that was a pan, not a summons.
		if event.position.distance_to(_press_at) > OPEN_SLOP:
			_charging = false
			_on_grab()
	elif state == HandState.HOLDING:
		_stroke_pts.append(event.position)
		_stroke_times.append(Time.get_ticks_msec() / 1000.0)
		# THE HAND ANSWERS THE FINGER HERE, not on the next physics tick.
		#
		# This is the whole of "no input delay, ever". A phone that is
		# overheating runs its physics slower, and everything that waited for
		# the physics tick got slower with it — so the hand, the thing being
		# held, and the samples a throw is measured from all lagged exactly
		# when the player could least afford it. None of them wait now: the
		# hover ray, the carry and the sample all happen on the event, at
		# whatever rate the screen reports. The device gets made to do LESS
		# (Quality.report_frame drops the graphics tier and lengthens the
		# simulation stride); it never gets to make the hand slower.
		_update_hover(event.position)
		_sample_hand()
		var now := Time.get_ticks_msec() / 1000.0
		_carry_held(minf(now - _carried_at, 0.1))
		_carried_at = now


func _on_grab() -> void:
	# THE WORLD IS HELD while casting: no panning, no picking anything up. This
	# is what makes every stroke unambiguously a rune, and it is the whole
	# reason the session exists.
	if state != HandState.IDLE or casting:
		return
	# WHAT IS ACTUALLY UNDER THE POINTER, ASKED ONCE.
	#
	# `hover_target` is written by a raycast on one frame and read by a grab on
	# a later one, and in between the thing it points at can be eaten, burned,
	# butchered, freed by a chunk unloading or thrown off the edge of the world.
	# Three of the four branches below then asked it something: `is` on a freed
	# instance is an error, and `is_in_group` on null is a crash, and only the
	# fourth branch had ever been given the guard.
	#
	# So it is settled here, once, for all of them — and a pointer over nothing
	# falls through to the land drag at the foot, which is the honest answer:
	# grabbing nothing is grabbing the ground.
	var under := hover_target if is_instance_valid(hover_target) else null
	# AND NOTHING IS TAKEN FROM GROUND YOU DO NOT HOLD.
	#
	# The reach was put on casting first and left the hand alone, on the
	# argument that an arm has no faith in it. That was wrong in play: a god who
	# cannot call down a fire on the far mountain but can reach over and pull
	# the mountain's trees up by the roots has not been limited at all — the
	# most destructive thing in the game was still anytime, anywhere, and the
	# circles only stopped the pretty half of it.
	#
	# So the whole hand works where your power works. Note what this does NOT
	# touch: dragging the land is the camera, not the hand, so a refused grab
	# falls through to it rather than doing nothing — and anything already in
	# your grip stays there. You may carry a tree out of your country; you may
	# not reach into somebody else's and take one.
	if under != null and not MiracleReach.may_act(get_tree(), ground_point):
		GameState.hint("Your reach has run out here — get back to your own ground.")
		if miracles != null and is_instance_valid(miracles) \
				and miracles.reach_ring != null \
				and is_instance_valid(miracles.reach_ring):
			miracles.reach_ring.flare()
		under = null
	# Grabbing a QUARTER of the storehouse platform withdraws that
	# resource as a physical item, straight into the grip.
	if under is FoodStore:
		var item := (under as FoodStore).withdraw_at(ground_point)
		if item != null:
			force_hold(item)
		return
	# AND A ROCK FACE GIVES UP A BOULDER. Asked of the ADVERB and not of the
	# class, so a flint outcrop and a chalk face and whatever is quarried next
	# all come through here without this file ever learning their names. See
	# Affords.QUARRIED.
	if under != null and under.is_in_group(Affords.QUARRIED):
		var rock := under.call("prise") as ResourceItem
		if rock != null:
			get_tree().current_scene.add_child(rock)
			rock.global_position = ground_point + Vector3(0.0, 0.6, 0.0)
			force_hold(rock)
		return
	if under != null and under.is_in_group(Affords.PICKABLE):
		# WHO ACTUALLY ENDS UP IN YOUR HAND. A child reached for by a cruel god
		# is not the thing that comes up — their mother is. See ChildSafety,
		# which is the whole of that rule.
		held_body = ChildSafety.in_your_hand(under) as PhysicsBody3D
		if held_body == null:
			return
		# Lifting a dying villager with a clean conscience (neutral or better)
		# cradles them back to a sliver of life.
		if held_body is Villager and (held_body as Villager).is_dying() \
				and GameState.alignment >= 0.0:
			(held_body as Villager).rescue()
		state = HandState.HOLDING
		_begin_carry()
		if held_body is RigidBody3D:
			(held_body as RigidBody3D).freeze = true
		elif held_body.has_method("pick_up"):
			held_body.call("pick_up")
	else:
		# Grabbing open sky isn't grabbing land — don't start a drag there.
		var mouse_pos := get_viewport().get_mouse_position()
		if camera_rig.camera.project_ray_normal(mouse_pos).y > -0.02:
			return
		state = HandState.DRAG_LAND
		drag_anchor = _mouse_on_plane(mouse_pos)


## Black & White's grab-more: while the pointer stays pressed and the held
## bundle hovers over the storehouse it came from, keep pulling its resource
## into the hand — an armful that swells the longer you hold. Drag off the
## platform (or let go) to stop.
func _tick_bundle_grab(delta: float) -> void:
	if not _pointer_down:
		return
	if camera_rig != null and camera_rig.is_multitouching():
		return
	_bundle_time -= delta
	if _bundle_time > 0.0:
		return
	_bundle_time = BUNDLE_TOPUP
	# OVER THE STOREHOUSE it draws from the town's own stock, which is what this
	# was written for. Anywhere else it sweeps up what is lying about.
	if hover_target is FoodStore:
		(hover_target as FoodStore).top_up(held_body)
		return
	_gather_kindred()


## SWEEPING UP A FIELD, one thing every BUNDLE_TOPUP seconds.
##
## A slain beast leaves a heap of joints and a good harvest leaves a scatter of
## sheaves, and picking them up was one grab, one carry and one walk back —
## each. The storehouse could already stack things into the hand and the
## bundle they stack into already existed; the only thing missing was that
## loose things on the ground could not join one.
##
## THE SAME GESTURE AND THE SAME RHYTHM as the storehouse top-up, deliberately:
## hold the hand closed and drag it over the pile. Nothing new to learn, no
## modifier key — and on a phone, where there IS no modifier key, that is the
## whole of why it works at all.
##
## What may join what is the item's own business — see FoodItem.absorb, which
## is where the rule lives that a joint of human flesh can never be quietly
## stacked into eleven of mutton.
func _gather_kindred() -> void:
	if not is_instance_valid(held_body):
		return
	var mine := held_body
	# THE NARROW GROUP, NOT "pickable". This runs sixteen times a second for as
	# long as a hand is closed, and "pickable" holds every tree in the streamed
	# world — hundreds of them — none of which can ever join a bundle. "food"
	# and "resource_items" are the things that actually can.
	var flock := ""
	if mine is FoodItem:
		flock = "food"
	elif mine is ResourceItem:
		flock = "resource_items"
	else:
		return
	var best: Node3D = null
	var best_gap := GATHER_REACH
	for n in get_tree().get_nodes_in_group(flock):
		var loose := n as Node3D
		if loose == null or not is_instance_valid(loose) or loose == mine:
			continue
		var gap := loose.global_position.distance_to(global_position)
		if gap < best_gap:
			best_gap = gap
			best = loose
	if best == null:
		return
	var took := false
	if mine is FoodItem:
		took = (mine as FoodItem).absorb(best as FoodItem)
	else:
		took = (mine as ResourceItem).absorb(best as ResourceItem)
	if took:
		hover_info_changed.emit(describe(mine))


func _on_release() -> void:
	# A TAP WITH THE ROPE IN YOUR HAND IS STILL "GO THERE". Only a tap: a hold
	# was a tie and has already done its work, and a drag was the camera.
	if has_lead():
		if _tying >= 0.0 and _tying < TIE_HOLD and not _stroke_is_throw():
			lead.tie(null)
			lead.hand_at = ground_point
			# POINTING AT THE GROUND IS DELIBERATE, so it hauls rather than
			# nudges — `tie(null)` has already put the rope back in your hand
			# and pulled once; this aims that pull where you actually tapped.
			lead.haul(ground_point)
		_tying = 0.0
		return
	match state:
		HandState.DRAG_LAND:
			state = HandState.IDLE
		HandState.HOLDING:
			# A deliberate drag-flick THROWS; a tap or a settled hand PLACES.
			# The stroke gate (screen-space, immune to the hand teleporting
			# between pokes) is what decides — placement is calm, no fear, no
			# fall damage, and where you place someone matters.
			var gentle := not _stroke_is_throw()
			if is_instance_valid(held_body):
				# A RELEASE INSIDE ITS REACH IS A HAND-OFF, whatever the stroke
				# did. This used to want `gentle` as well — the pointer had to
				# come to a full stop for longer than THROW_ACTIVE_WINDOW
				# before you let go — so dragging something over to the
				# creature and opening your hand in one motion THREW it, at a
				# range of two metres, for it to fumble. You cannot throw a
				# thing you are holding against its chest. Releasing it there
				# is giving it to the creature, and it reads that way now.
				var c := get_tree().get_first_node_in_group("creature") as Creature
				if c != null and held_body != c \
						and c.global_position.distance_to(global_position) < 3.0 + c.scale.x:
					# Shares the creature's own door in, so the sling, the busy
					# flag and what the beast does with the thing are decided in
					# one place however it got there. See CreatureOffer.
					give_to(c)
					return
				if gentle:
					_release_body(held_body, Vector3.ZERO, true)
					_stow_sling()
				else:
					# NOT THAT. A child goes on their feet wherever the hand is,
					# and somebody standing in a child's place wrestles and does
					# not come out of it at all. See ChildSafety.
					var refused := ChildSafety.throw_answer(held_body)
					if refused == ChildSafety.HELD_FAST:
						return        # still in your hand, and still in the way
					if refused == ChildSafety.SET_DOWN:
						_release_body(held_body, Vector3.ZERO, true)
						_stow_sling()
						held_body = null
						state = HandState.IDLE
						return
					# A SPENT LEASH LETS GO OF NOTHING AT ALL.
					#
					# Not "you may not throw it, but you may set it down" —
					# putting a thing somewhere IS influencing it, and setting
					# an orb down is outright CASTING it, since a working
					# resolves wherever it comes to rest. Out past your reach
					# with the leash run out, your hand means nothing: it
					# cannot take, it cannot place, it cannot throw. What is in
					# it stays in it until you are back on your own ground.
					if not MiracleReach.may_act(get_tree(), ground_point):
						GameState.hint("Your reach has run out — carry it back "
							+ "to your own ground.")
						return       # still in your hand, and still yours
					# Aftertouch shapes the shot from the final flick: a lofted
					# and/or curving launch, plus a lingering in-flight steer.
					var shot := _compute_throw()
					# FLOATER AIR TIME. The game's gravity is twice the world's,
					# so a thrown villager came down like a dropped brick and
					# the whole pleasure of hurling somebody — watching them
					# HANG — was missing. See Sling.gravity_for.
					Sling.loft(held_body)
					_release_body(held_body, shot["vel"], false)
					_begin_aftertouch(held_body, shot["curve"], shot["angular"])
					last_thrown = held_body
			held_body = null
			state = HandState.IDLE
			_stow_sling()


## IT TOOK IT OUT OF YOUR HAND. Called BY the creature (CreatureOffer), not by
## the player — so unlike every other way a thing leaves this hand, there was
## no release to hang the tidying off.
##
## All of which has to happen anyway: the sling's rope and arc are drawn over
## whatever is held and would otherwise stay drawn over nothing, and
## `hands_busy` would never clear, which leaves the far half of the world a
## simulation stride slow for the rest of the session. `_stow_sling` is the one
## that does both; it is the same call the set-down hand-off makes below.
func give_to(who: Creature) -> bool:
	if not is_instance_valid(held_body) or held_body == who:
		return false
	var item := held_body
	held_body = null
	state = HandState.IDLE
	_stow_sling()
	who.receive_gift(item)
	return true


func _reset_stroke(pos: Vector2) -> void:
	_stroke_pts = [pos]
	_stroke_times = [Time.get_ticks_msec() / 1000.0]


## True only for a genuine throwing flick: the pointer travelled a real
## continuous distance this stroke AND was still moving at release. A tap,
## a poke, or a drag that came to rest before letting go all read as PLACE.
func _stroke_is_throw() -> bool:
	if _stroke_pts.size() < 2:
		return false
	var dist := 0.0
	for i in range(1, _stroke_pts.size()):
		dist += _stroke_pts[i].distance_to(_stroke_pts[i - 1])
	if dist < THROW_MIN_STROKE:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	return now - _stroke_times[_stroke_times.size() - 1] <= THROW_ACTIVE_WINDOW


## The MOMENTUM of the throw: the hand's velocity over the broad sweep,
## EXCLUDING the trailing flick, boosted and capped. This sets the throw's
## power and heading — the flick never gets to override it.
func _sweep_velocity() -> Vector3:
	var n := _pos_history.size()
	if n < 2:
		return Vector3.ZERO
	var last := maxi(n - 1 - _flick_count(), 1)   # end of the sweep, before the flick
	var span := _pos_times[last] - _pos_times[0]
	if span < 0.001:
		return Vector3.ZERO
	var vel := (_pos_history[last] - _pos_history[0]) / span * THROW_BOOST
	return vel.limit_length(MAX_THROW_SPEED)


## How many trailing samples are "the flick". A share rather than a count,
## because how many samples a sweep produces is now the device's business.
func _flick_count() -> int:
	return clampi(int(_pos_history.size() * FLICK_SHARE), 1, FLICK_SAMPLES * 4)


## The velocity of the trailing FLICK itself (the last few frames). Its
## backward component lofts the throw, its sideways component curves it, and
## its whole deviation from the launch line spins it. A follow-through (flick
## still moving forward) shapes nothing — only a deliberate yank does.
func _flick_velocity() -> Vector3:
	var n := _pos_history.size()
	var back := _flick_count()
	if n < back + 2:
		return Vector3.ZERO
	var last := n - 1 - back
	var span := _pos_times[n - 1] - _pos_times[last]
	if span < 0.001:
		return Vector3.ZERO
	return (_pos_history[n - 1] - _pos_history[last]) / span


## Turns momentum + flick into a shaped shot:
## { vel: launch velocity, curve: in-flight lateral accel, angular: rad/s vec }.
## Momentum owns power and azimuth; the flick only lofts the ANGLE and curves.
func _compute_throw() -> Dictionary:
	# THE SLING FIRST. The hand's sweep and the held thing's OWN motion relative
	# to it are both real momentum, and how much of each survives depends on
	# what you are throwing — see Sling.launch. This is also exactly the shot
	# the arc has been drawing over the ground while you wound up, because it
	# is the same function; a prediction that is not the real shot is a lie.
	var weight := Sling.heft(held_body)
	var momentum := Sling.launch(_sweep_velocity(),
		_held_vel - _sweep_velocity(), weight).limit_length(MAX_THROW_SPEED)
	var speed := momentum.length()
	var flat := Vector3(momentum.x, 0.0, momentum.z)
	if speed < 0.5 or flat.length() < 0.4:
		return {"vel": momentum, "curve": Vector3.ZERO, "angular": Vector3.ZERO}
	var fwd := flat.normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	var flick := _flick_velocity()

	# LOFT: only the flick's BACKWARD (and upward) motion raises the launch
	# angle — a follow-through stays flat. Added to the momentum's own
	# elevation and clamped, so a brief yank gives ~30-45 deg and only a long,
	# hard one nears vertical. Power and heading stay the momentum's.
	var pull := maxf(-flick.dot(fwd), 0.0) + maxf(flick.y, 0.0) * 0.5
	var loft := minf(pull * LOFT_PER_PULL, deg_to_rad(MAX_LOFT_DEG))
	var base_elev := asin(clampf(momentum.y / speed, -1.0, 1.0))
	var elev := clampf(base_elev + loft, -0.25, deg_to_rad(87.0))
	var vel := (fwd * cos(elev) + Vector3.UP * sin(elev)) * speed

	# CURVE: a sideways flick bends the flight (a lingering lateral accel).
	var curve := right * flick.dot(right) * CURVE_GAIN

	# SPIN on a real 3D axis: perpendicular to the launch and the flick.
	# Sideways flick -> yaw; pull-back -> topspin; anything between -> tilted.
	var angular := Vector3.ZERO
	var axis := vel.normalized().cross(flick)
	if axis.length() > 0.05:
		angular = axis.normalized() * clampf(axis.length() * SPIN_GAIN, 0.0, MAX_SPIN)
	return {"vel": vel, "curve": curve, "angular": angular}


## Hand off a released body to physics — a thrown velocity for RigidBodies,
## or the object's own drop() for the custom flyers (trees, folk, beasts).
func _release_body(body: Node3D, vel: Vector3, gentle: bool) -> void:
	# MARKED AS YOUR OWN SHOT. If this one lands in a storehouse the creature
	# learns the trick from having watched you do it — see VillageWonder.given.
	if not gentle and is_instance_valid(body):
		body.set_meta("hurled_by_god", true)
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		rb.freeze = false
		rb.linear_velocity = vel
		# WHAT IT DOES WHERE IT COMES DOWN. Only a real throw is worth
		# watching, and the watcher frees itself the moment the flight ends —
		# see Blow, which is why nothing in a world of resting stones is
		# monitoring anything.
		if not gentle:
			Blow.ride(rb, true)
			# AND THE REST OF THE VOLLEY GOES WITH IT. The sky sigil conjures
			# ONE working into the grip however many it promised; the others
			# are born here, at the moment the hand opens, already flying. See
			# Volley — anything that cannot make another of itself simply goes
			# alone, so this line is a no-op for a thrown cow.
			Volley.fan(rb, vel)
	elif body.has_method("drop"):
		body.call("drop", vel, gentle)
	# Back on their feet and back to being an ordinary villager. See ChildSafety.
	ChildSafety.let_go(body)
	# YOUR CREATURE IS WATCHING. Setting a thing down carefully and hurling it
	# are different lessons, and it takes whichever one you just gave.
	_show_creature("gather" if gentle else "throw", body, 0.4 if gentle else -0.6)


## Tell the creature what your hand just did, if it is near enough to see. It
## decides for itself what to make of it — see `Creature.witness_god`.
func _show_creature(verb: String, subject: Node3D, valence: float) -> void:
	var creature := get_tree().get_first_node_in_group("creature") as Creature
	if creature == null or not is_instance_valid(creature) or subject == creature:
		return
	creature.witness_god(verb, CreatureEyes.kind_of(subject), valence)
	# AND A HURLED THING IS AN EVENT. Setting something down is scenery and
	# leaves the beast at its settled half-watchfulness; throwing it takes all
	# of its attention, which is also what it needs to have any hope of
	# catching the thing. See CreatureHead.startled.
	if verb == "throw":
		CreatureHead.startled(creature, subject.global_position)
	# AND A TIED CREATURE IS SHOWN IT, whichever of the two it was. It cannot
	# walk off, so its head goes round and is held there — see
	# CreatureLead.made_to_watch, which does nothing at all to a loose one.
	CreatureLead.made_to_watch(creature, subject.global_position)




## Arm the aftertouch: remember the projectile, set its spin now, and store
## the lateral acceleration the hand will feed it over the next fraction of
## a second (the curving arc).
func _begin_aftertouch(body: Node3D, curve: Vector3, angular: Vector3) -> void:
	_apply_spin(body, angular)
	if curve.length() < 0.01:
		_steer_body = null
		_steer_time = 0.0
		return
	_steer_body = body
	_steer_accel = curve
	_steer_time = AFTERTOUCH_SECONDS


## Set the projectile spinning about a real 3D axis. RigidBodies take it as
## angular velocity; the custom flyers tumble around that world axis.
func _apply_spin(body: Node3D, angular: Vector3) -> void:
	if angular.length() < 0.05:
		return
	if body is RigidBody3D:
		(body as RigidBody3D).angular_velocity = angular
	elif body.has_method("set_flight_spin"):
		body.call("set_flight_spin", angular)


func _apply_in_flight(body: Node3D, dv: Vector3) -> void:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		if not rb.freeze:
			rb.linear_velocity += dv
	elif body.has_method("in_flight_push"):
		body.call("in_flight_push", dv)


## WHAT A SECOND TAP MEANS. Returns true when it claimed the press, in which
## case the single press's own work is skipped for this one.
##
## Read in the order a player would expect to be answered: the panel in front of
## you first, then the creature you are holding by a rope, and if neither, the
## tap was just a tap and the ordinary press does its ordinary job.
func _tapped_twice() -> bool:
	# AN OPEN PANEL CLOSES. The one thing a double tap always does, because a
	# thing that opens in front of the world has to be dismissable without
	# walking away from it — which was the only way to be rid of it before.
	var hud := get_tree().get_first_node_in_group("hud") as HUD
	if hud != null and is_instance_valid(hud) and hud.stone_is_open():
		hud.shut_the_stone()
		return true
	# WITH THE ROPE IN HAND, IT POINTS. Not an order — the creature goes on
	# doing what it was doing — but its attention goes where you tapped, which
	# is how you show a beast a thing rather than send it to one. See
	# CreatureHead.startled, which is the same door being shown a thrown rock.
	if has_lead() and lead.creature != null and is_instance_valid(lead.creature):
		var what := hover_target if is_instance_valid(hover_target) else null
		var at := what.global_position if what != null else ground_point
		# ONLY IF IT COULD ACTUALLY SEE IT. `startled` refuses anything past
		# CreatureHead.STARTLE_WITHIN, so saying "your creature looks where you
		# pointed" for a spot across the valley would be the game telling the
		# player something that did not happen.
		if at.distance_to(lead.creature.global_position) > CreatureHead.STARTLE_WITHIN:
			GameState.hint("That is too far off for your creature to make out.")
			return true
		CreatureHead.startled(lead.creature, at)
		# AND THE ROPE PULLS, NOW. The double tap IS the strong tug — it is the
		# player asserting, and a deliberate pull answered a second and a half
		# later is one the player has already decided did not work. See
		# LeadRope.haul, which does not wait for the ambient beat.
		lead.haul(at)
		GameState.hint("Your creature looks where you pointed.")
		return true
	return false


## A second finger landed: the camera takes over. Abort any in-progress
## land-drag or gesture (a held object stays held — pinching while
## carrying is fine).
func cancel_touch_interaction() -> void:
	# A second finger means the camera, so the session goes too — otherwise a
	# pinch mid-cast leaves you trapped in a mode you did not mean to be in.
	if casting:
		_close_casting(false)
		return
	if state == HandState.DRAG_LAND:
		state = HandState.IDLE
	if state != HandState.HOLDING:
		_stow_sling()
	_charging = false
	# The camera claimed the gesture, so the tap after it starts clean rather
	# than completing a double with whatever happened before the pinch.
	_taps.cancel()


## Places a conjured object (e.g. a fireball) straight into the hand's grip.
## Returns false if the hand is already full.
func force_hold(body: PhysicsBody3D) -> bool:
	if state == HandState.HOLDING and is_instance_valid(held_body):
		return false
	body.global_position = global_position + Vector3(0, -0.6, 0)
	held_body = body
	state = HandState.HOLDING
	_begin_carry()
	if body is RigidBody3D:
		(body as RigidBody3D).freeze = true
	return true


## THE CASTING SESSION ----------------------------------------------------------
##
## Open it, draw runes, and stop. Nothing has to be held down, nothing has to be
## released at the right moment, and while it is open there is no such thing as
## a pan or a grab to be confused with — which is the only way this was ever
## going to be reliable under a thumb.


## Is the pointer over something the hand would pick up or open? Pressing one
## of those still grabs it — the session is only ever summoned off bare ground.
func _on_something_grabbable() -> bool:
	return is_instance_valid(hover_target) \
		and (hover_target.is_in_group(Affords.PICKABLE) or hover_target is FoodStore)


## Only a touchscreen needs the press-and-hold summons; a mouse has a button
## to spare, and turning a hesitant left-press into a gesture there would be a
## nasty surprise.
func _touch_only() -> bool:
	return DisplayServer.is_touchscreen_available()


## Charging the opening press. Touch only; a mouse has a button for this.
func _tick_press_charge(delta: float) -> void:
	if has_lead():
		_tick_tying(delta)
		return
	if _on_disk != "":
		_tick_disk(delta)
		return
	if _reading:
		if not _pointer_down or not is_instance_valid(hover_target):
			_reading = false
			hover_info_changed.emit(describe(hover_target))
			return
		_press_time += delta
		if _press_time >= READ_HOLD:
			_reading = false
			hover_info_changed.emit(describe(hover_target))
			GameState.stone_read.emit(hover_target)
			return
		# THE HOLD, FILLING. There was no feedback of any kind: you pressed the
		# wall, nothing happened for seven tenths of a second, and you let go —
		# which is exactly what everybody did. charge_fraction() was written for
		# a ring under the finger and nothing has ever drawn it, so the hover
		# line does the work instead, and it works the same on a thumb as on a
		# mouse.
		hover_info_changed.emit("Reading the stone... %d%%"
			% int(charge_fraction() * 100.0))
		return
	if not _charging:
		return
	_press_time += delta
	if _press_time >= OPEN_HOLD:
		_charging = false
		_open_casting()


## TYING THE ROPE OFF. Hold on anything and the far end goes round it; what a
## tied rope buys is SLACK, and the creature may do as it likes inside it.
##
## Holding over BARE EARTH unties instead, which is how you get the rope back
## into your own hand without having to find something to untie it from.
func _tick_tying(delta: float) -> void:
	if not _pointer_down:
		_tying = 0.0
		return
	_tying += delta
	var onto := hover_target if is_instance_valid(hover_target) else null
	var rope := lead
	if _tying < TIE_HOLD:
		hover_info_changed.emit("Tying the lead... %d%%"
			% int(clampf(_tying / TIE_HOLD, 0.0, 1.0) * 100.0))
		return
	_tying = -999.0            # once per hold, not once per frame
	# AND THE ROPE GOES OUT OF YOUR HAND WITH IT — see LeadRope.tie, which is
	# why `lead` is read into `rope` above: `_carry_lead` lets go of a rope that
	# has been tied off, and the message wants to know how long it is.
	rope.tie(onto)
	if onto == null:
		GameState.announce("The lead is loose in your hand again.")
	else:
		GameState.announce("You tie the lead round %s. %dm of rope, your hands "
			% [describe(onto), int(rope.length)]
			+ "are free — and it must watch whatever you do next.")


## HOLDING THE SUN. Unlike the casting summons this is NOT touch-only: a mouse
## has buttons to spare everywhere else in the game, but there is no second
## button on the sky and no menu bar to put this on, so the gesture is the same
## on both. See Temple.
func _tick_disk(delta: float) -> void:
	if not _pointer_down:
		_on_disk = ""
		return
	_press_time += delta
	if _press_time >= Temple.DISK_HOLD:
		var why := _on_disk
		_on_disk = ""
		hover_info_changed.emit("")
		temple_asked.emit(why)
		return
	# The same feedback the stone gets, for the same reason: without it you
	# press the sun, nothing happens for most of a second, and you let go.
	hover_info_changed.emit("The %s opens... %d%%"
		% [_on_disk, int(clampf(_press_time / Temple.DISK_HOLD, 0.0, 1.0) * 100.0)])


## How far through the opening press we are, 0..1 — for the ring the HUD draws
## under the finger, so the player can see the summons coming.
func charge_fraction() -> float:
	if _reading:
		return clampf(_press_time / READ_HOLD, 0.0, 1.0)
	return clampf(_press_time / OPEN_HOLD, 0.0, 1.0) if _charging else 0.0



func _open_casting() -> void:
	if is_instance_valid(held_body):
		return                       # not while your hand is full
	# NOR WHILE YOU ARE HOLDING THE ROPE.
	#
	# A lead loose in your hand IS your hand being full — it is the one thing
	# you are doing — and a god drawing runes one-handed while a creature hauls
	# on the other is a picture of somebody not really leading anything. Tie it
	# off and both hands are free again, which is what tying off is FOR; or let
	# the rope go and the creature keeps its last order (see LeadRope.is_tied
	# and last_order).
	if has_lead() and not lead.is_tied():
		GameState.hint("You have the lead in your hand. Tie it off, "
			+ "or drop it, before you work.")
		return
	# YOU MAY ONLY WORK ON GROUND YOU HOLD — refused HERE, before a stroke is
	# drawn, rather than after one. Finding out that a rune was wasted only once
	# it is finished is the worst possible moment to learn the rule, and it also
	# reads as the drawing having failed rather than the place.
	#
	# `cast_from` is stamped now and used for the whole session: `ground_point`
	# follows the pointer every frame, so a rune drawn across the screen would
	# otherwise be judged on wherever the stroke happened to end.
	if not MiracleReach.may_act(get_tree(), ground_point):
		GameState.hint(MiracleReach.short_hint(get_tree(), ground_point))
		SoundBank.play_at("whisper", global_position, -4.0, 0.12, 0.6)
		if miracles != null and is_instance_valid(miracles) \
				and miracles.reach_ring != null \
				and is_instance_valid(miracles.reach_ring):
			miracles.reach_ring.flare()
		return
	cast_from = ground_point
	casting = true
	_whisper_time = 0.6
	live_shape = "none"
	live_confidence = 0.0
	_runes.clear()
	_idle_time = 0.0
	_drew = false
	state = HandState.IDLE
	gesture_points = PackedVector2Array()
	_clear_trail()
	SoundBank.play_at("coo", global_position, -6.0, 0.2)
	GameState.hint("CASTING — draw a rune. The world is held while you do.")


## End the session. `cast` means "and use what was drawn"; the idle timeout
## passes true, an explicit dismissal passes false.
func _close_casting(cast: bool) -> void:
	var runes := _runes.duplicate()
	casting = false
	live_shape = "none"
	live_confidence = 0.0
	_runes.clear()
	_idle_time = 0.0
	_charging = false
	gesture_points = PackedVector2Array()
	_clear_trail()
	if state == HandState.GESTURING:
		state = HandState.IDLE
	if cast and not runes.is_empty() and miracles != null:
		miracles.cast_runes(runes)
	elif runes.is_empty():
		GameState.hint("")


## READ THE STROKE AS IT IS DRAWN. Twelve times a second, not every frame —
## and NOTHING here is committed. The reading exists so the player can see the
## shape being understood while there is still time to change it; the rune that
## lands on the slate is read from the finished stroke in `_end_stroke`.
func _tick_peek(delta: float) -> void:
	_peek_time -= delta
	if _peek_time > 0.0:
		return
	# A reading is a full match against every reference drawing — measurably the
	# most expensive thing that happens while a finger is down. So it backs off
	# with the thermal band, like the rest of the game: twelve times a second on
	# a cool device, four on a hot one. The stroke is unaffected either way; only
	# how often the picture under it refreshes.
	_peek_time = PEEK_EVERY * Quality.sim_relief()
	var reading := GestureRecognizer.peek(gesture_points)
	live_shape = String(reading["shape"])
	live_confidence = float(reading["confidence"])


## Whispers, somewhere out past the edge of what you are doing. They are placed
## around the hand rather than on it, at a distance, so they read as coming
## from the trees and the dark rather than from the player.
func _tick_whispers(delta: float) -> void:
	if not casting:
		return
	_whisper_time -= delta
	if _whisper_time > 0.0:
		return
	_whisper_time = randf_range(WHISPER_MIN, WHISPER_MAX)
	var away := randf() * TAU
	var out := randf_range(9.0, 20.0)
	SoundBank.play_at("whisper",
		global_position + Vector3(cos(away) * out, randf_range(0.5, 4.0), sin(away) * out),
		-13.0, 0.28)


func _clear_trail() -> void:
	if trail != null:
		trail.points = PackedVector2Array()
		trail.queue_redraw()


func _begin_stroke(at: Vector2) -> void:
	state = HandState.GESTURING
	gesture_points = PackedVector2Array([at])
	_idle_time = 0.0
	live_shape = "none"
	live_confidence = 0.0
	_peek_time = 0.0


## TAKE A POINT INTO THE STROKE — but only if it says something new.
##
## A pointer reports every frame it moves, so a slow, careful rune arrived as
## six hundred points where forty would have described the same shape. That is
## pure cost twice over: the recognizer resamples the whole array (inserting as
## it goes, so it is superlinear), and it does it again on every live reading.
##
## A finger that has not travelled MIN_STEP has not drawn anything, so the
## point is dropped. The cap behind it is a backstop for a genuinely enormous
## scrawl. Neither loses shape: the matcher resamples to 48 points regardless,
## so the only thing thrown away here is duplication.
func _add_stroke_point(at: Vector2) -> void:
	if gesture_points.size() >= STROKE_CAP:
		return
	if gesture_points.size() > 0 \
			and gesture_points[gesture_points.size() - 1].distance_to(at) < MIN_STEP:
		return
	gesture_points.append(at)


## The stroke is finished: read it and add it to the working. The quiet clock
## starts again from here — and, crucially, does NOT run while a stroke is in
## progress, which is what used to cast a half-drawn working out of your hand.
func _end_stroke() -> void:
	# THE COMMITTED READING. Taken from the whole finished stroke, never from
	# the live one — a half-drawn circle is honestly an arc, and casting what
	# the shape looked like on the way past would be indefensible.
	var gesture := GestureRecognizer.classify(gesture_points)
	live_shape = "none"
	live_confidence = 0.0
	gesture_points = PackedVector2Array()
	_clear_trail()
	state = HandState.IDLE
	_idle_time = 0.0
	# FROM HERE ON THE HAND IS IN A HURRY. See FIRST_RUNE_WAIT.
	_drew = true
	# NEVER MIND. A LINE STRUCK STRAIGHT ACROSS ends the session and casts
	# nothing — the gesture for striking something out, which is what it does.
	# The old sweep still works, because players who learned it should not have
	# it taken away. Both are checked BEFORE the spellbook and neither is a
	# rune, so cancelling can never end up as an ingredient in a working.
	#
	# This is the only gesture in the game that destroys work, so it has to be
	# the one nobody makes by accident. A flat stroke is the laziest thing a
	# hand produces, which is exactly why the recognizer now holds shallow S's
	# and leaned bows: without them, a tired water rune cancelled the spell a
	# third of the time. Measured after: strokes aimed at any other rune land
	# here 0% of the time on a healthy phone and 4% at the worst throttling.
	if gesture == "hline" or gesture == "sweep":
		SoundBank.play_at("pick", global_position, -8.0, 0.1)
		_close_casting(false)
		GameState.hint("Struck out.")
		return
	# The turning sigil has a working behind it now — see Spellbook.AGAIN. It
	# falls through and lands on the slate like any other rune; the manager
	# reads it as "whatever I last cast" when the session closes.
	var rune := Spellbook.rune_for(gesture) if gesture != "none" else ""
	if rune == "":
		# A botched stroke must never throw away the runes before it.
		GameState.hint("That shape means nothing — try it again." if _runes.is_empty()
			else "%s   (that shape meant nothing)" % Spellbook.describe(_runes))
		return
	if _runes.size() >= MAX_RUNES:
		GameState.hint("Your hands are full at %d runes." % MAX_RUNES)
		return
	_runes.append(rune)
	# THE DRUM. Struck once per rune, pitched down and hit harder as the working
	# grows, so a three-rune miracle is audibly heavier than a one-rune one
	# before anything has been cast at all.
	var depth := float(_runes.size() - 1) / float(maxi(MAX_RUNES - 1, 1))
	SoundBank.play_at("drum", global_position, -4.0 + depth * 5.0, 0.02)
	GameState.hint(Spellbook.describe(_runes))


## Quiet for long enough: cast what is on the slate, or simply let the player
## go if they drew nothing.
func _tick_casting(delta: float) -> void:
	_tick_whispers(delta)
	_tick_focus(delta)
	if not casting or state == HandState.GESTURING:
		return
	# UNSCALED. The world is running at FOCUS_TIME_SCALE while you draw, and a
	# clock fed the scaled delta slows down with it — so a wait written as
	# three quarters of a second would take a full one. See FIRST_RUNE_WAIT.
	_idle_time += delta / maxf(Engine.time_scale, 0.01)
	if _idle_time >= _wait_now():
		_close_casting(true)


## Which of the two waits applies right now. See FIRST_RUNE_WAIT.
func _wait_now() -> float:
	return NEXT_RUNE_WAIT if _drew else FIRST_RUNE_WAIT


## THE WORLD LEANS IN WHILE YOU DRAW.
##
## Two things move together and they are the same gesture. Time slows a little
## — not to a crawl, just enough that the drawing hand feels unhurried and the
## thrown fireball you are about to answer hangs a moment longer. And the small
## noises come forward: every critter's voice stops being intermittent and goes
## continuous (see Critter._tick_voice), so a wood that was a scatter of
## far-off chirping becomes a solid ring of it around you.
##
## The audio does NOT slow with the world — Godot's time scale does not touch
## playback — which is exactly right. The world goes quiet and slow; the small
## things get louder and keep their pitch.
##
## Timed in UNSCALED seconds, or the ramp would slow itself down as it worked.
func _tick_focus(delta: float) -> void:
	var want := 1.0 if casting else 0.0
	var real := delta / maxf(Engine.time_scale, 0.01)
	var rate := real / (FOCUS_IN if want > GameState.focus else FOCUS_OUT)
	GameState.focus = move_toward(GameState.focus, want, rate)
	Engine.time_scale = lerpf(1.0, FOCUS_TIME_SCALE, GameState.focus)


## The runes on the slate, for the readout that draws them.
func runes_drawn() -> Array:
	return _runes


## Seconds left before the session resolves itself, 0..1 — for the HUD's bar.
func casting_fraction() -> float:
	if not casting:
		return 0.0
	if state == HandState.GESTURING:
		return 1.0
	return clampf(1.0 - _idle_time / _wait_now(), 0.0, 1.0)


## What is on the slate right now, for the HUD to show as you draw.
func working_text() -> String:
	if _runes.is_empty():
		return ""
	return Spellbook.describe(_runes)


## THE HAND'S OWN SHAPE, every frame. What it is over, whether it is holding
## anything and whether it is hauling the land are all already known here; this
## is only the part where the hand admits to knowing them. See HandPose.
func _tick_pose(delta: float) -> void:
	_stirred += delta
	if _knuckles.is_empty():
		return
	_pose.ease(HandPose.shape_for(is_instance_valid(held_body),
		state == HandState.DRAG_LAND, hover_target, _stirred),
		_knuckles, _thumb_joint, delta)


## The clip a rigged hand model plays for what the hand is doing now.
func _anim_state() -> String:
	match state:
		HandState.HOLDING:
			return "grab"
		HandState.GESTURING:
			return "cast"
		HandState.DRAG_LAND:
			return "grab"
	return "idle"
