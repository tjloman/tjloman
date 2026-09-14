class_name DivineHand
extends Node3D
## The player IS this hand — B&W style. It hovers over the terrain following
## the mouse, grabs the land to pan, picks up and throws physics objects and
## villagers, and draws miracle gestures while the right button is held.

signal hover_info_changed(text: String)

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
const HIT_MASK := 1 | 2 | 4 | 8  # ground | units | props | trees
const THROW_BOOST := 1.6     # hand velocity -> projectile velocity
const MAX_THROW_SPEED := 55.0
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
const IDLE_TO_CAST := 2.6    # quiet seconds that end the session
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

var drag_anchor := Vector3.ZERO
var gesture_points := PackedVector2Array()
var ground_point := Vector3.ZERO

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

## The runes drawn so far this session, and the quiet since the last stroke —
## which counts ONLY while nothing is being drawn. Letting it run mid-stroke is
## what cast a half-made miracle out of the player's hand.
var _runes: Array = []
var _idle_time := 0.0
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
		ground_point = hit.position
		ground_point.y = maxf(ground_point.y, 0.0)
		var collider = hit.collider
		if is_instance_valid(collider) and collider is Node3D \
				and not (collider as Node3D).is_in_group("ground"):
			hover_target = collider

	hover_info_changed.emit(_describe(hover_target))


func _describe(target: Node3D) -> String:
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
	if state == HandState.GESTURING:
		_end_stroke()
	elif not casting:
		_on_release()


func _on_pointer_motion(event: InputEventMouseMotion) -> void:
	_stirred = 0.0          # the hand is reaching, not resting. See `_tick_pose`.
	if state == HandState.GESTURING:
		_add_stroke_point(event.position)
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
	# Grabbing a QUARTER of the storehouse platform withdraws that
	# resource as a physical item, straight into the grip.
	if hover_target is FoodStore:
		var item := (hover_target as FoodStore).withdraw_at(ground_point)
		if item != null:
			force_hold(item)
		return
	if is_instance_valid(hover_target) and hover_target.is_in_group("pickable"):
		held_body = hover_target
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
	if not _pointer_down or not (hover_target is FoodStore):
		return
	if camera_rig != null and camera_rig.is_multitouching():
		return
	_bundle_time -= delta
	if _bundle_time <= 0.0:
		_bundle_time = BUNDLE_TOPUP
		(hover_target as FoodStore).top_up(held_body)


func _on_release() -> void:
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
	elif body.has_method("drop"):
		body.call("drop", vel, gentle)
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
		and (hover_target.is_in_group("pickable") or hover_target is FoodStore)


## Only a touchscreen needs the press-and-hold summons; a mouse has a button
## to spare, and turning a hesitant left-press into a gesture there would be a
## nasty surprise.
func _touch_only() -> bool:
	return DisplayServer.is_touchscreen_available()


## Charging the opening press. Touch only; a mouse has a button for this.
func _tick_press_charge(delta: float) -> void:
	if _reading:
		if not _pointer_down or not is_instance_valid(hover_target):
			_reading = false
			hover_info_changed.emit(_describe(hover_target))
			return
		_press_time += delta
		if _press_time >= READ_HOLD:
			_reading = false
			hover_info_changed.emit(_describe(hover_target))
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


## How far through the opening press we are, 0..1 — for the ring the HUD draws
## under the finger, so the player can see the summons coming.
func charge_fraction() -> float:
	if _reading:
		return clampf(_press_time / READ_HOLD, 0.0, 1.0)
	return clampf(_press_time / OPEN_HOLD, 0.0, 1.0) if _charging else 0.0



func _open_casting() -> void:
	if is_instance_valid(held_body):
		return                       # not while your hand is full
	casting = true
	_whisper_time = 0.6
	live_shape = "none"
	live_confidence = 0.0
	_runes.clear()
	_idle_time = 0.0
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
	if gesture == Spellbook.UNSPOKEN:
		# A good shape with nothing behind it yet. Say so plainly rather than
		# calling it a botch — the player drew it correctly.
		GameState.hint("That sigil has no working bound to it yet.")
		return
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
	_idle_time += delta
	if _idle_time >= IDLE_TO_CAST:
		_close_casting(true)


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
	return clampf(1.0 - _idle_time / IDLE_TO_CAST, 0.0, 1.0)


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
	_pose.tick(HandPose.shape_for(is_instance_valid(held_body),
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
