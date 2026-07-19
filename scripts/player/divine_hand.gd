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
	if _pos_history.size() > 6:
		_pos_history.pop_front()

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
			var throw_vel := Vector3.ZERO if gentle else _throw_velocity()
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
				if held_body is RigidBody3D:
					var rb := held_body as RigidBody3D
					rb.freeze = false
					rb.linear_velocity = throw_vel
				elif held_body.has_method("drop"):
					held_body.call("drop", throw_vel, gentle)
				if not gentle:
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
