class_name CameraRig
extends Node3D
## God-game camera: WASD/arrow pan, Q/E or middle-mouse-drag rotate,
## scroll-wheel zoom. The DivineHand also pans it B&W-style by grabbing land.
##
## Structure:  self (yaw) -> Pitch (x tilt) -> Camera3D (pulled back on z)

const MIN_ZOOM := 8.0
const MAX_ZOOM := 90.0
const PAN_SPEED := 22.0
const ROTATE_SPEED := 1.6

var camera: Camera3D
var pitch_node: Node3D
var zoom_distance := 35.0
var _rotating := false


func _ready() -> void:
	pitch_node = Node3D.new()
	pitch_node.rotation_degrees = Vector3(-50, 0, 0)
	add_child(pitch_node)

	camera = Camera3D.new()
	camera.position = Vector3(0, 0, zoom_distance)
	camera.far = 600.0
	pitch_node.add_child(camera)

	position = Vector3(0, 0, 8)


func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.y = Input.get_action_strength("cam_back") - Input.get_action_strength("cam_forward")
	input_dir.x = Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left")
	if input_dir != Vector2.ZERO:
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
		rotate_y(-rot * ROTATE_SPEED * delta)

	camera.position.z = lerpf(camera.position.z, zoom_distance, minf(delta * 8.0, 1.0))

	_follow_terrain(delta)


## The rig's pivot rides the landscape so hills don't swallow the camera.
func _follow_terrain(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 120.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -300.0, 0), 1)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var target_y: float = maxf(hit.position.y, 0.0)
		global_position.y = lerpf(global_position.y, target_y, minf(delta * 5.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_distance = clampf(zoom_distance * 0.9, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_distance = clampf(zoom_distance * 1.1, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = event.pressed
	elif event is InputEventMouseMotion and _rotating:
		rotate_y(-event.relative.x * 0.005)
		var new_pitch: float = clampf(
			pitch_node.rotation_degrees.x - event.relative.y * 0.25, -80.0, -20.0)
		pitch_node.rotation_degrees.x = new_pitch


## Pan by a world-space delta (used by DivineHand's grab-the-land drag).
func pan_world(delta_vec: Vector3) -> void:
	delta_vec.y = 0
	global_position += delta_vec
