class_name DivineHand
extends Node3D
## The player IS this hand — B&W style. It hovers over the terrain following
## the mouse, grabs the land to pan, picks up and throws physics objects and
## villagers, and draws miracle gestures while the right button is held.

signal hover_info_changed(text: String)

enum HandState { IDLE, DRAG_LAND, HOLDING, GESTURING }

const HOVER_HEIGHT := 1.4
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
const OPEN_SLOP := 16.0      # move further than this first and you meant to pan
const IDLE_TO_CAST := 2.6    # quiet seconds that end the session
const MAX_RUNES := 5

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

# Recent hand positions, for computing throw velocity on release.
var _pos_history: Array[Vector3] = []

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
var _charging := false

## The runes drawn so far this session, and the quiet since the last stroke —
## which counts ONLY while nothing is being drawn. Letting it run mid-stroke is
## what cast a half-made miracle out of the player's hand.
var _runes: Array = []
var _idle_time := 0.0

var _hand_material: StandardMaterial3D
var _glow: OmniLight3D
var _animator: ModelAnimator = null   # non-null only for a rigged hand model

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
		# Four fingers.
		for i in 4:
			var x := -0.33 + i * 0.22
			var length := 0.55 if (i == 1 or i == 2) else 0.45
			_add_hand_part(Util.box(
				Vector3(0.16, 0.15, length), Color.WHITE,
				Vector3(x, 0.0, -0.5 - length * 0.5)))
		# Thumb.
		var thumb := Util.box(Vector3(0.16, 0.15, 0.42), Color.WHITE, Vector3(0.55, 0.0, 0.05))
		thumb.rotation_degrees.y = -40
		_add_hand_part(thumb)
	# Faint divine glow.
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.95, 0.8)
	_glow.light_energy = 0.6
	_glow.omni_range = 4.0
	_glow.position = Vector3(0, 0.5, 0)
	add_child(_glow)
	GameState.alignment_changed.connect(_on_alignment_changed)


func _add_hand_part(part: MeshInstance3D) -> void:
	part.material_override = _hand_material
	add_child(part)


func _on_alignment_changed(_value: float) -> void:
	var c := GameState.alignment_color()
	if _hand_material != null:
		_hand_material.albedo_color = c
	_glow.light_color = c


func _physics_process(delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	_update_hover(mouse_pos)

	# The hand rests on whatever the mouse is over; fall back to the y=0 plane.
	var target := ground_point + Vector3(0, HOVER_HEIGHT, 0)
	target.y += sin(Time.get_ticks_msec() / 400.0) * 0.08  # idle bob
	global_position = global_position.lerp(target, minf(delta * 14.0, 1.0))

	# Yaw-follow: the hand turns with the camera's heading (palm-down, B&W
	# style), so it reads right from any angle. Eased so it swings, not snaps.
	if camera_rig != null:
		rotation.y = lerp_angle(rotation.y, camera_rig.rotation.y, minf(delta * 8.0, 1.0))

	# A rigged hand model plays grab/cast/idle clips as the hand works.
	if _animator != null:
		_animator.play(_anim_state())

	_pos_history.append(global_position)
	if _pos_history.size() > 10:
		_pos_history.pop_front()

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

	match state:
		HandState.DRAG_LAND:
			var plane_point := _mouse_on_plane(mouse_pos, drag_anchor.y)
			camera_rig.pan_world(drag_anchor - plane_point)
		HandState.HOLDING:
			if is_instance_valid(held_body):
				var carry := ground_point + Vector3(0, HOVER_HEIGHT - 0.6, 0)
				held_body.global_position = held_body.global_position.lerp(
					carry, minf(delta * 16.0, 1.0))
				_tick_bundle_grab(delta)
			else:
				held_body = null
				state = HandState.IDLE
		HandState.GESTURING:
			trail.points = gesture_points
			trail.queue_redraw()


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
		var collider: Object = hit.collider
		if is_instance_valid(collider) and collider is Node3D \
				and not (collider as Node3D).is_in_group("ground"):
			hover_target = collider

	hover_info_changed.emit(_describe(hover_target))


func _describe(target: Node3D) -> String:
	if target == null:
		return ""
	if target.has_method("hover_text"):
		return str(target.call("hover_text"))
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
		_charging = _touch_only() and state == HandState.IDLE \
			and not _on_something_grabbable()
		if not _charging:
			_on_grab()
		return
	# Released.
	_charging = false
	if state == HandState.GESTURING:
		_end_stroke()
	elif not casting:
		_on_release()


func _on_pointer_motion(event: InputEventMouseMotion) -> void:
	if state == HandState.GESTURING:
		gesture_points.append(event.position)
	elif _charging:
		# Moved before the press matured: that was a pan, not a summons.
		if event.position.distance_to(_press_at) > OPEN_SLOP:
			_charging = false
			_on_grab()
	elif state == HandState.HOLDING:
		_stroke_pts.append(event.position)
		_stroke_times.append(Time.get_ticks_msec() / 1000.0)


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
				# A gentle release right AT the creature is a hand-off: it
				# takes the object in its claws (and learns to watch you).
				if gentle:
					var c := get_tree().get_first_node_in_group("creature") as Creature
					if c != null and held_body != c \
							and c.global_position.distance_to(global_position) < 3.0 + c.scale.x:
						c.receive_gift(held_body)
						held_body = null
						state = HandState.IDLE
						return
					_release_body(held_body, Vector3.ZERO, true)
				else:
					# Aftertouch shapes the shot from the final flick: a lofted
					# and/or curving launch, plus a lingering in-flight steer.
					var shot := _compute_throw()
					_release_body(held_body, shot["vel"], false)
					_begin_aftertouch(held_body, shot["curve"], shot["angular"])
					last_thrown = held_body
			held_body = null
			state = HandState.IDLE


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
	var last := maxi(n - 1 - FLICK_SAMPLES, 1)   # end of the sweep, before the flick
	var span := last / 60.0
	var vel := (_pos_history[last] - _pos_history[0]) / span * THROW_BOOST
	return vel.limit_length(MAX_THROW_SPEED)


## The velocity of the trailing FLICK itself (the last few frames). Its
## backward component lofts the throw, its sideways component curves it, and
## its whole deviation from the launch line spins it. A follow-through (flick
## still moving forward) shapes nothing — only a deliberate yank does.
func _flick_velocity() -> Vector3:
	var n := _pos_history.size()
	if n < FLICK_SAMPLES + 2:
		return Vector3.ZERO
	var last := n - 1 - FLICK_SAMPLES
	return (_pos_history[n - 1] - _pos_history[last]) / (FLICK_SAMPLES / 60.0)


## Turns momentum + flick into a shaped shot:
## { vel: launch velocity, curve: in-flight lateral accel, angular: rad/s vec }.
## Momentum owns power and azimuth; the flick only lofts the ANGLE and curves.
func _compute_throw() -> Dictionary:
	var momentum := _sweep_velocity()
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
	_charging = false


## Places a conjured object (e.g. a fireball) straight into the hand's grip.
## Returns false if the hand is already full.
func force_hold(body: PhysicsBody3D) -> bool:
	if state == HandState.HOLDING and is_instance_valid(held_body):
		return false
	body.global_position = global_position + Vector3(0, -0.6, 0)
	held_body = body
	state = HandState.HOLDING
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
	if not _charging:
		return
	_press_time += delta
	if _press_time >= OPEN_HOLD:
		_charging = false
		_open_casting()


## How far through the opening press we are, 0..1 — for the ring the HUD draws
## under the finger, so the player can see the summons coming.
func charge_fraction() -> float:
	return clampf(_press_time / OPEN_HOLD, 0.0, 1.0) if _charging else 0.0


func _open_casting() -> void:
	if is_instance_valid(held_body):
		return                       # not while your hand is full
	casting = true
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


func _clear_trail() -> void:
	if trail != null:
		trail.points = PackedVector2Array()
		trail.queue_redraw()


func _begin_stroke(at: Vector2) -> void:
	state = HandState.GESTURING
	gesture_points = PackedVector2Array([at])
	_idle_time = 0.0


## The stroke is finished: read it and add it to the working. The quiet clock
## starts again from here — and, crucially, does NOT run while a stroke is in
## progress, which is what used to cast a half-drawn working out of your hand.
func _end_stroke() -> void:
	var gesture := GestureRecognizer.classify(gesture_points)
	gesture_points = PackedVector2Array()
	_clear_trail()
	state = HandState.IDLE
	_idle_time = 0.0
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
	GameState.hint(Spellbook.describe(_runes))


## Quiet for long enough: cast what is on the slate, or simply let the player
## go if they drew nothing.
func _tick_casting(delta: float) -> void:
	if not casting or state == HandState.GESTURING:
		return
	_idle_time += delta
	if _idle_time >= IDLE_TO_CAST:
		_close_casting(true)


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
