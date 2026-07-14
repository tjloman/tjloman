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

var camera_rig: CameraRig
var miracles: MiracleManager
var trail: GestureTrail

var state := HandState.IDLE
var held_body: PhysicsBody3D = null
var hover_target: Node3D = null
var drag_anchor := Vector3.ZERO
var gesture_points := PackedVector2Array()
var ground_point := Vector3.ZERO

# Recent hand positions, for computing throw velocity on release.
var _pos_history: Array[Vector3] = []


func _ready() -> void:
	_build_hand_mesh()
	trail = GestureTrail.new()
	add_child(trail)


func _build_hand_mesh() -> void:
	var hand_color := Color(1.0, 0.9, 0.65)
	# Palm.
	add_child(Util.box(Vector3(0.9, 0.18, 1.0), hand_color, Vector3.ZERO))
	# Four fingers.
	for i in 4:
		var x := -0.33 + i * 0.22
		var length := 0.55 if (i == 1 or i == 2) else 0.45
		add_child(Util.box(
			Vector3(0.16, 0.15, length), hand_color,
			Vector3(x, 0.0, -0.5 - length * 0.5)))
	# Thumb.
	var thumb := Util.box(Vector3(0.16, 0.15, 0.42), hand_color, Vector3(0.55, 0.0, 0.05))
	thumb.rotation_degrees.y = -40
	add_child(thumb)
	# Faint divine glow.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.95, 0.8)
	glow.light_energy = 0.6
	glow.omni_range = 4.0
	glow.position = Vector3(0, 0.5, 0)
	add_child(glow)


func _physics_process(delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	_update_hover(mouse_pos)

	# The hand rests on whatever the mouse is over; fall back to the y=0 plane.
	var target := ground_point + Vector3(0, HOVER_HEIGHT, 0)
	target.y += sin(Time.get_ticks_msec() / 400.0) * 0.08  # idle bob
	global_position = global_position.lerp(target, minf(delta * 14.0, 1.0))

	_pos_history.append(global_position)
	if _pos_history.size() > 6:
		_pos_history.pop_front()

	match state:
		HandState.DRAG_LAND:
			var plane_point := _mouse_on_plane(mouse_pos)
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
		ground_point = _mouse_on_plane(mouse_pos)
	else:
		ground_point = hit.position
		ground_point.y = maxf(ground_point.y, 0.0)
		var collider: Object = hit.collider
		if collider is Node3D and not (collider as Node3D).is_in_group("ground"):
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


func _mouse_on_plane(mouse_pos: Vector2) -> Vector3:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(mouse_pos)
	var dir := cam.project_ray_normal(mouse_pos)
	var denom := dir.y
	if absf(denom) < 0.0001:
		return ground_point
	var t := -from.y / denom
	if t < 0.0:
		return ground_point
	return from + dir * t


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_grab()
			else:
				_on_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and state == HandState.IDLE:
				state = HandState.GESTURING
				gesture_points = PackedVector2Array([event.position])
			elif not event.pressed and state == HandState.GESTURING:
				_finish_gesture()
	elif event is InputEventMouseMotion and state == HandState.GESTURING:
		gesture_points.append(event.position)


func _on_grab() -> void:
	if state != HandState.IDLE:
		return
	if hover_target != null and hover_target.is_in_group("pickable"):
		held_body = hover_target
		state = HandState.HOLDING
		if held_body is RigidBody3D:
			(held_body as RigidBody3D).freeze = true
		elif held_body.has_method("pick_up"):
			held_body.call("pick_up")
	else:
		state = HandState.DRAG_LAND
		drag_anchor = _mouse_on_plane(get_viewport().get_mouse_position())


func _on_release() -> void:
	match state:
		HandState.DRAG_LAND:
			state = HandState.IDLE
		HandState.HOLDING:
			var throw_vel := _throw_velocity()
			if is_instance_valid(held_body):
				if held_body is RigidBody3D:
					var rb := held_body as RigidBody3D
					rb.freeze = false
					rb.linear_velocity = throw_vel
				elif held_body.has_method("drop"):
					held_body.call("drop", throw_vel)
			held_body = null
			state = HandState.IDLE


func _throw_velocity() -> Vector3:
	if _pos_history.size() < 2:
		return Vector3.ZERO
	var oldest := _pos_history[0]
	var newest := _pos_history[_pos_history.size() - 1]
	# History spans ~6 physics frames.
	var vel := (newest - oldest) / (6.0 / 60.0)
	return vel.limit_length(30.0)


func _finish_gesture() -> void:
	var gesture := GestureRecognizer.classify(gesture_points)
	trail.points = PackedVector2Array()
	trail.queue_redraw()
	gesture_points = PackedVector2Array()
	state = HandState.IDLE
	if gesture != "none" and miracles != null:
		miracles.cast_gesture(gesture, ground_point)
