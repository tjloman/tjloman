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

var _follow_button: Button
var _leash_button: Button


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

	_leash_button = _make_button("Lead")
	_leash_button.pressed.connect(_on_leash_pressed)
	column.add_child(_leash_button)



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
	_process_lead_label()


func _on_follow_toggled(pressed: bool) -> void:
	if pressed and is_instance_valid(creature):
		camera_rig.follow_target = creature
	else:
		camera_rig.follow_target = null


## THE SAME DOOR THE KEY USES, and it has to be: the button and the key were
## two copies of the lead's behaviour, and a rewrite of one of them would have
## left the other doing the old thing on the machine where it matters most.
##
## Main._take_the_lead is the whole of it now — this fires the action and lets
## that decide, exactly as the Creature button does.
func _on_leash_pressed() -> void:
	var ev := InputEventAction.new()
	ev.action = "leash_creature"
	ev.pressed = true
	Input.parse_input_event(ev)


## WHAT THE BUTTON WILL DO IF YOU PRESS IT — three states, because there are
## three. A tied rope is not in your hand (see LeadRope.tie), and labelling that
## "Lead" as though there were no rope at all would hide the one thing the
## player wants to know: that the rope is out there, and that this is the way
## back to holding it.
func _process_lead_label() -> void:
	if not is_instance_valid(divine_hand):
		return
	if divine_hand.has_lead():
		_leash_button.text = "Drop lead"
	elif is_instance_valid(creature) \
			and LeadRope.on(creature, get_tree()) != null:
		_leash_button.text = "Take up"
	else:
		_leash_button.text = "Lead"
