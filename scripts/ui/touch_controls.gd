class_name TouchControls
extends CanvasLayer
## On-screen controls for glass: a Cast/Move mode toggle (one finger draws
## miracles vs. works the hand) and a Creature button that locks the camera
## onto your creature until you pan away. Appears only on touchscreens —
## mouse players never see it.
##
## The camera's own touch handling covers the rest: pinch to zoom,
## two-finger drag to orbit freely.

var divine_hand: DivineHand
var camera_rig: CameraRig
var creature: Creature

var _mode_button: Button
var _follow_button: Button


func _ready() -> void:
	layer = 6
	if not DisplayServer.is_touchscreen_available():
		visible = false
		set_process(false)
		return

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.add_theme_constant_override("separation", 16)
	add_child(column)

	_follow_button = _make_button("Creature")
	_follow_button.toggle_mode = true
	_follow_button.toggled.connect(_on_follow_toggled)
	column.add_child(_follow_button)

	_mode_button = _make_button("Mode: Move")
	_mode_button.toggle_mode = true
	_mode_button.toggled.connect(_on_mode_toggled)
	column.add_child(_mode_button)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(210, 72)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _process(_delta: float) -> void:
	# Panning away releases the follow — keep the button honest.
	if _follow_button.button_pressed and camera_rig.follow_target == null:
		_follow_button.set_pressed_no_signal(false)


func _on_follow_toggled(pressed: bool) -> void:
	if pressed and is_instance_valid(creature):
		camera_rig.follow_target = creature
	else:
		camera_rig.follow_target = null


func _on_mode_toggled(pressed: bool) -> void:
	divine_hand.cast_mode = pressed
	_mode_button.text = "Mode: Cast" if pressed else "Mode: Move"
	if pressed:
		GameState.announce("Casting mode: draw a miracle gesture with one finger.")
	else:
		GameState.announce("Movement mode: drag the land, pick up, place, throw.")
