class_name DivineHand
extends Node3D
## The player IS this hand — B&W style. It hovers over the terrain following
## the mouse, grabs the land to pan, picks up and throws physics objects and
## villagers, and draws miracle gestures while the right button is held.

signal hover_info_changed(text: String)

enum HandState { IDLE, DRAG_LAND, HOLDING, GESTURING }

const HOVER_HEIGHT := 1.4
const RAY_LENGTH := 500.0
const HIT_MASK := 1 | 2 | 4  # ground | units | props
const THROW_BOOST := 1.6     # hand velocity -> projectile velocity
const MAX_THROW_SPEED := 55.0
## A release only THROWS if the pointer was dragged this far in one unbroken
## stroke AND was still moving at the moment of release. This is what tells a
## genuine throwing flick apart from tapping/poking around the screen (each
## poke resets the stroke), which used to fling things by accident on touch.
const THROW_MIN_STROKE := 60.0      # pixels of continuous drag
const THROW_ACTIVE_WINDOW := 0.13   # seconds; must still be moving at release

## AFTERTOUCH (a Black & White throwback). The way the hand's motion CHANGES
## in the last instant of a throw — not just its speed — shapes the shot:
##   pull back  -> the throw lofts into a high, slow, floaty arc
##   jerk aside -> the projectile curves that way and spins as it flies
## It reads from the final flick (works on touch, where the finger is gone
## after release) and applies as launch loft plus a brief in-flight steer.
const AFTERTOUCH_SECONDS := 0.45    # how long the curve keeps bending the shot
const LOFT_GAIN := 0.85             # pull-back -> upward launch velocity
const SLOW_ON_LOFT := 0.05          # pull-back also slows the forward throw
const PUSH_GAIN := 0.5              # a forward shove at the end adds zip
const CURVE_GAIN := 3.2             # sideways jerk -> in-flight lateral accel
const SPIN_GAIN := 1.6              # sideways jerk -> projectile spin (rad/s)

var camera_rig: CameraRig
var miracles: MiracleManager
var trail: GestureTrail

var state := HandState.IDLE
var held_body: PhysicsBody3D = null
var hover_target: Node3D = null

## Touch "cast mode": one-finger drags draw miracle gestures instead of
## grabbing. Toggled by the on-screen button; irrelevant with a mouse.
var cast_mode := false

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

## Two-step casting: the menu opened by the first gesture, and how long it
## stays open awaiting the selector gesture.
var _armed_menu := ""
var _menu_timer := 0.0

var _hand_material: StandardMaterial3D
var _glow: OmniLight3D


func _ready() -> void:
	_build_hand_mesh()
	trail = GestureTrail.new()
	add_child(trail)


func _build_hand_mesh() -> void:
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
	_hand_material.albedo_color = c
	_glow.light_color = c


func _physics_process(delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	_update_hover(mouse_pos)

	# An armed miracle menu forgotten too long simply closes.
	if _armed_menu != "":
		_menu_timer -= delta
		if _menu_timer <= 0.0:
			_armed_menu = ""
			GameState.hint("The miracle faded, uncast.")

	# The hand rests on whatever the mouse is over; fall back to the y=0 plane.
	var target := ground_point + Vector3(0, HOVER_HEIGHT, 0)
	target.y += sin(Time.get_ticks_msec() / 400.0) * 0.08  # idle bob
	global_position = global_position.lerp(target, minf(delta * 14.0, 1.0))

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

	match state:
		HandState.DRAG_LAND:
			var plane_point := _mouse_on_plane(mouse_pos, drag_anchor.y)
			camera_rig.pan_world(drag_anchor - plane_point)
		HandState.HOLDING:
			if is_instance_valid(held_body):
				var carry := ground_point + Vector3(0, HOVER_HEIGHT - 0.6, 0)
				held_body.global_position = held_body.global_position.lerp(
					carry, minf(delta * 16.0, 1.0))
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
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Every fresh press begins a new stroke: a poke can never
				# inherit the momentum of the drag before it.
				_reset_stroke(event.position)
				if cast_mode and state == HandState.IDLE:
					state = HandState.GESTURING
					gesture_points = PackedVector2Array([event.position])
				else:
					_on_grab()
			elif state == HandState.GESTURING and cast_mode:
				_finish_gesture()
			else:
				_on_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and state == HandState.IDLE:
				state = HandState.GESTURING
				gesture_points = PackedVector2Array([event.position])
			elif not event.pressed and state == HandState.GESTURING:
				_finish_gesture()
	elif event is InputEventMouseMotion:
		if state == HandState.GESTURING:
			gesture_points.append(event.position)
		elif state == HandState.HOLDING:
			_stroke_pts.append(event.position)
			_stroke_times.append(Time.get_ticks_msec() / 1000.0)


func _on_grab() -> void:
	if state != HandState.IDLE:
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
					_begin_aftertouch(held_body, shot["curve"], shot["spin"])
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


func _throw_velocity() -> Vector3:
	if _pos_history.size() < 2:
		return Vector3.ZERO
	var oldest := _pos_history[0]
	var newest := _pos_history[_pos_history.size() - 1]
	var span := (_pos_history.size() - 1) / 60.0
	# The hand's own momentum, amplified: flick hard, throw far.
	var vel := (newest - oldest) / span * THROW_BOOST
	return vel.limit_length(MAX_THROW_SPEED)


## How the hand's motion CHANGED across the flick: late velocity minus early
## velocity. Pulling back gives a vector opposing the throw; jerking aside
## gives a sideways one. Zero for a smooth, even fling.
func _flick_whip() -> Vector3:
	var n := _pos_history.size()
	if n < 4:
		return Vector3.ZERO
	var half := int(n / 2.0)
	var dt := 1.0 / 60.0
	var v_early := (_pos_history[half] - _pos_history[0]) / maxf(half * dt, dt)
	var v_late := (_pos_history[n - 1] - _pos_history[half]) / maxf((n - 1 - half) * dt, dt)
	return v_late - v_early


## Turns the base throw plus the flick's "whip" into a shaped shot:
## { vel: launch velocity, curve: in-flight lateral accel, spin: rad/s }.
func _compute_throw() -> Dictionary:
	var base := _throw_velocity()
	var flat := Vector3(base.x, 0.0, base.z)
	if flat.length() < 0.01:
		return {"vel": base, "curve": Vector3.ZERO, "spin": 0.0}
	var fwd := flat.normalized()
	var right := Vector3.UP.cross(fwd).normalized()
	var whip := _flick_whip()

	var vel := base
	# Pull back at the end -> loft: rises higher, drifts forward slower.
	var pull := clampf(-whip.dot(fwd), 0.0, 20.0)
	vel.y += pull * LOFT_GAIN
	var slow := clampf(pull * SLOW_ON_LOFT, 0.0, 0.6)
	vel.x *= 1.0 - slow
	vel.z *= 1.0 - slow
	# A forward shove at the very end adds a little extra zip.
	vel += fwd * clampf(whip.dot(fwd), 0.0, 20.0) * PUSH_GAIN
	vel = vel.limit_length(MAX_THROW_SPEED * 1.3)

	# Sideways jerk -> a curving arc (lateral accel held through flight) and
	# a matching spin on the projectile (both clamped so a wild flick stays
	# playable, not launched into orbit).
	var side := clampf(whip.dot(right), -16.0, 16.0)
	var spin := clampf(side * SPIN_GAIN, -10.0, 10.0)
	return {"vel": vel, "curve": right * side * CURVE_GAIN, "spin": spin}


## Hand off a released body to physics — a thrown velocity for RigidBodies,
## or the object's own drop() for the custom flyers (trees, folk, beasts).
func _release_body(body: Node3D, vel: Vector3, gentle: bool) -> void:
	if body is RigidBody3D:
		var rb := body as RigidBody3D
		rb.freeze = false
		rb.linear_velocity = vel
	elif body.has_method("drop"):
		body.call("drop", vel, gentle)


## Arm the aftertouch: remember the projectile, set its spin now, and store
## the lateral acceleration the hand will feed it over the next fraction of
## a second (the curving arc).
func _begin_aftertouch(body: Node3D, curve: Vector3, spin: float) -> void:
	_apply_spin(body, spin)
	if curve.length() < 0.01:
		_steer_body = null
		_steer_time = 0.0
		return
	_steer_body = body
	_steer_accel = curve
	_steer_time = AFTERTOUCH_SECONDS


func _apply_spin(body: Node3D, spin: float) -> void:
	if absf(spin) < 0.05:
		return
	if body is RigidBody3D:
		(body as RigidBody3D).angular_velocity = Vector3(0.0, spin, 0.0)
	elif body.has_method("set_flight_spin"):
		body.call("set_flight_spin", spin)


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
	match state:
		HandState.DRAG_LAND:
			state = HandState.IDLE
		HandState.GESTURING:
			trail.points = PackedVector2Array()
			trail.queue_redraw()
			gesture_points = PackedVector2Array()
			state = HandState.IDLE


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


func _finish_gesture() -> void:
	var gesture := GestureRecognizer.classify(gesture_points)
	trail.points = PackedVector2Array()
	trail.queue_redraw()
	gesture_points = PackedVector2Array()
	state = HandState.IDLE
	if gesture == "none" or miracles == null:
		return
	# Two-step casting. First a MENU opener, then a SELECTOR within it.
	if _armed_menu == "":
		if miracles.is_menu_opener(gesture):
			_armed_menu = gesture
			_menu_timer = 5.0
			GameState.hint(miracles.menu_label(gesture) + "   (draw a selector to choose)")
		else:
			GameState.hint("Draw a spiral, reverse-spiral, or wave/S to open a miracle menu.")
	else:
		miracles.select(_armed_menu, gesture)
		_armed_menu = ""
		_menu_timer = 0.0
