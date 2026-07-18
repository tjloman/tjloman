class_name CameraRig
extends Node3D
## God-game camera: WASD/arrow pan, Q/E or middle-mouse-drag rotate,
## scroll-wheel zoom. The DivineHand also pans it B&W-style by grabbing land.
##
## Structure:  self (yaw) -> Pitch (x tilt) -> Camera3D (pulled back on z)

const MIN_ZOOM := 1.2   # close enough to stand at a villager's feet
const MAX_ZOOM := 70.0
const PAN_SPEED := 22.0
const ROTATE_SPEED := 1.6

var camera: Camera3D
var pitch_node: Node3D
var zoom_distance := 35.0
var divine_hand: DivineHand = null   # wired by main; touch gestures preempt it

## When set, the rig glides after this node (e.g. the creature) until the
## player pans away manually.
var follow_target: Node3D = null

var _rotating := false
var _touches := {}        # touch index -> screen position
var _pinch_dist := 0.0
var _world_cache: WorldGen = null


func _ready() -> void:
	pitch_node = Node3D.new()
	# A low, B&W-style default gaze: the horizon sits high and the sky
	# fills a good share of the frame.
	pitch_node.rotation_degrees = Vector3(-32, 0, 0)
	add_child(pitch_node)

	camera = Camera3D.new()
	camera.position = Vector3(0, 0, zoom_distance)
	camera.far = 600.0
	pitch_node.add_child(camera)

	position = Vector3(0, 0, 8)


func _process(delta: float) -> void:
	if follow_target != null and is_instance_valid(follow_target):
		var t := follow_target.global_position
		global_position.x = lerpf(global_position.x, t.x, minf(delta * 4.0, 1.0))
		global_position.z = lerpf(global_position.z, t.z, minf(delta * 4.0, 1.0))
	elif follow_target != null:
		follow_target = null
	else:
		# Ease the lock-on aim back to the rig's natural framing.
		camera.rotation = camera.rotation.lerp(Vector3.ZERO, minf(delta * 6.0, 1.0))

	var input_dir := Vector2.ZERO
	input_dir.y = Input.get_action_strength("cam_back") - Input.get_action_strength("cam_forward")
	input_dir.x = Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left")
	if input_dir != Vector2.ZERO:
		follow_target = null  # manual panning breaks the follow
		# Pan speed scales with zoom so the world feels consistent at any height.
		var speed := PAN_SPEED * (zoom_distance / 35.0)
		var forward := -global_transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		var right := global_transform.basis.x
		right.y = 0
		right = right.normalized()
		global_position += (right * input_dir.x + forward * -input_dir.y) * speed * delta

	var rot := Input.get_action_strength("cam_rotate_right") - Input.get_action_strength("cam_rotate_left")
	if rot != 0.0:
		_yaw_around_focus(-rot * ROTATE_SPEED * delta)

	camera.position.z = lerpf(camera.position.z, zoom_distance, minf(delta * 8.0, 1.0))

	_follow_terrain(delta)
	_clamp_camera_above_ground()

	# TRUE lock-on: while following, the target sits centered in frame —
	# orbit and zoom move around it, the camera keeps looking AT it.
	if follow_target != null and is_instance_valid(follow_target):
		var aim: Vector3 = follow_target.global_position \
			+ Vector3.UP * 1.2 * follow_target.scale.y
		if camera.global_position.distance_to(aim) > 0.6:
			camera.look_at(aim, Vector3.UP)


## The rig's pivot rides the landscape so hills don't swallow the camera.
func _follow_terrain(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 120.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -300.0, 0), 1)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var target_y: float = maxf(hit.position.y, 0.0)
		global_position.y = lerpf(global_position.y, target_y, minf(delta * 5.0, 1.0))


## The land is solid, even to gods: the camera never dips beneath the
## terrain (or the water table). Checked against the pure-noise height
## field, so it holds even where no chunk is loaded.
func _clamp_camera_above_ground() -> void:
	if _world_cache == null or not is_instance_valid(_world_cache):
		_world_cache = get_tree().get_first_node_in_group("world_gen") as WorldGen
		if _world_cache == null:
			return
	var cam_pos := camera.global_position
	# The cushion shrinks as you zoom in, so a close camera can sit right
	# down at ankle height and look up — without ever entering the ground.
	var cushion := clampf(zoom_distance * 0.06, 0.3, 2.0)
	var floor_y := maxf(
		_world_cache.height_at(cam_pos.x, cam_pos.z), WorldGen.WATER_LEVEL) + cushion
	if cam_pos.y < floor_y:
		camera.global_position.y = floor_y


func _unhandled_input(event: InputEvent) -> void:
	# Multi-touch: two fingers own the camera — pinch zooms, dragging both
	# orbits freely (yaw with horizontal motion, pitch with vertical).
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 2:
				_pinch_dist = _touch_span()
				if divine_hand != null:
					divine_hand.cancel_touch_interaction()
		else:
			_touches.erase(event.index)
			_pinch_dist = 0.0
		return
	if event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var span := _touch_span()
			if _pinch_dist > 8.0:
				_zoom_toward(_pinch_dist / span)
			_pinch_dist = span
			# Each finger's drag fires its own event, so use half strength.
			_yaw_around_focus(-event.relative.x * 0.0025)
			pitch_node.rotation_degrees.x = clampf(
				pitch_node.rotation_degrees.x - event.relative.y * 0.12, -75.0, 40.0)
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_toward(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_toward(1.1)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = event.pressed
	elif event is InputEventMouseMotion and _rotating:
		_yaw_around_focus(-event.relative.x * 0.005)
		# Tilts from near-top-down to well above the horizon (+40): face
		# the sky to arc throws, or just to watch the weather of your soul.
		var new_pitch: float = clampf(
			pitch_node.rotation_degrees.x - event.relative.y * 0.25, -75.0, 40.0)
		pitch_node.rotation_degrees.x = new_pitch


## The point everything pivots around: the hand's spot on the ground.
## Zooming dollies toward it, yaw orbits around it — so the thing under
## your cursor stays put instead of the whole world swinging away. Falls
## back to the rig origin if the hand isn't ready.
func _focus_point() -> Vector3:
	if divine_hand != null and is_instance_valid(divine_hand):
		var p := divine_hand.ground_point
		return Vector3(p.x, global_position.y, p.z)
	return global_position


## Zoom by a factor, keeping the focus point fixed in frame: the rig
## origin slides toward (zoom in) or away from (zoom out) the hand by the
## same ratio as the zoom distance — standard dolly-to-cursor.
func _zoom_toward(factor: float) -> void:
	var new_zoom := clampf(zoom_distance * factor, MIN_ZOOM, MAX_ZOOM)
	var ratio := new_zoom / zoom_distance
	zoom_distance = new_zoom
	if follow_target == null and not is_equal_approx(ratio, 1.0):
		var focus := _focus_point()
		var offset := (global_position - focus) * ratio
		global_position = Vector3(focus.x + offset.x, global_position.y, focus.z + offset.z)


## Yaw the rig, orbiting around the hand's ground point rather than
## spinning in place, so the framing pivots on what you're looking at.
func _yaw_around_focus(angle: float) -> void:
	if follow_target != null:
		rotate_y(angle)  # lock-on already orbits its target
		return
	var focus := _focus_point()
	var offset := global_position - focus
	offset = offset.rotated(Vector3.UP, angle)
	rotate_y(angle)
	global_position = Vector3(focus.x + offset.x, global_position.y, focus.z + offset.z)


## Pan by a world-space delta (used by DivineHand's grab-the-land drag).
func pan_world(delta_vec: Vector3) -> void:
	follow_target = null  # grabbing the land breaks the follow
	delta_vec.y = 0
	global_position += delta_vec


func _touch_span() -> float:
	var positions := _touches.values()
	if positions.size() < 2:
		return 0.0
	return (positions[0] as Vector2).distance_to(positions[1] as Vector2)


## True while two or more fingers are on the glass (the camera owns them).
func is_multitouching() -> bool:
	return _touches.size() >= 2
