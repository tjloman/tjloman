class_name Tutorial
extends CanvasLayer
## THE FIRST TEN MINUTES.
##
## A short course in the things a new god cannot guess: that the land is
## dragged, that the hand lifts and throws, that casting is SUMMONED by a press
## and hold, that runes COMBINE, and that the creature is taught rather than
## commanded. The author of this game forgot how to open the casting session
## during his own phone playtest, which is the whole argument for this file.
##
## Two rules keep it from being a nuisance:
##
##  1. EVERY STEP IS COMPLETED BY DOING, never by pressing OK. Each one watches
##     the game for the thing actually happening. You cannot click past a
##     lesson without having learned it, and you cannot be told to do something
##     you have already done — the opening step skips itself if you are already
##     dragging the land about.
##  2. IT NEVER BLOCKS. Nothing is disabled, nothing is modal, the world runs
##     on underneath. Wander off mid-lesson and it waits; do the next thing out
##     of order and it notices.
##
## The hint only appears once you have been stuck a while, so a player who
## needs no help is never talked down to.
##
## Steps are DATA — a prompt, a hint, and a condition — which is the seed of
## the scripted island to come. A mission is this with a location attached.

const HINT_AFTER := 9.0      # seconds stuck before the hint appears
const DONE_DWELL := 1.4      # how long a finished step sits there ticked
const FLAG_PATH := "user://hand_of_the_heavens.tutored"

var divine_hand: DivineHand
var camera_rig: CameraRig
var creature: Creature
var miracles: MiracleManager

var _steps: Array = []
var _at := -1
var _stuck := 0.0
var _dwell := 0.0
var _card: PanelContainer
var _count_label: Label
var _text_label: Label
var _hint_label: Label
var _tick: Label
var _origin := Vector3.INF
var _saw_hold := false


func _ready() -> void:
	layer = 7
	_build_card()
	_build_steps()
	if _already_tutored():
		visible = false
		set_process(false)
		return
	_advance()


## Begin again from the top — the workshop's "Replay tutorial", and how anyone
## testing a change to the opening can see it without wiping their save.
func restart() -> void:
	_at = -1
	_dwell = 0.0
	visible = true
	set_process(true)
	_advance()


func _already_tutored() -> bool:
	return FileAccess.file_exists(FLAG_PATH)


func _mark_tutored() -> void:
	var f := FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("taught")
		f.close()


## THE COURSE. Each step is a prompt, a hint held back until you are stuck, and
## a condition that watches the world. Order is deliberate: nothing is asked
## for before the thing it depends on.
func _build_steps() -> void:
	var touch := DisplayServer.is_touchscreen_available()
	_steps = [
		{
			"say": "Take hold of the world. Drag the land to move your gaze across it.",
			"hint": "Touch the ground and drag." if touch
				else "Hold the left mouse button on the ground and drag. WASD works too.",
			"done": func() -> bool:
				if _origin == Vector3.INF or not is_instance_valid(camera_rig):
					return false
				return camera_rig.global_position.distance_to(_origin) > 12.0,
		},
		{
			"say": "Your hand can lift the world's things. Pick up a villager, a sheep, "
				+ "or a tree — then set it down gently.",
			"hint": "Press and drag something that isn't the ground. A short, still "
				+ "release places it kindly; a flick throws it.",
			"done": func() -> bool: return _saw_hold,
		},
		{
			"say": "MIRACLES ARE SUMMONED. Press the bare ground and HOLD until the "
				+ "ring fills." if touch
				else "MIRACLES ARE SUMMONED. Hold the RIGHT mouse button to open casting.",
			"hint": "Find empty ground — not a villager, not a building — and keep your "
				+ "finger still until the ring closes." if touch
				else "Hold the right mouse button anywhere on the world.",
			"done": func() -> bool: return is_instance_valid(divine_hand) and divine_hand.casting,
		},
		{
			"say": "Now draw WATER: a large S, or a wave. One unbroken stroke is one rune.",
			"hint": "Draw it big and slow — the whole shape in one stroke, then lift. "
				+ "The bar only runs down while you are NOT drawing.",
			"done": func() -> bool:
				return is_instance_valid(divine_hand) and divine_hand.working_text() != "",
		},
		{
			"say": "Stop drawing, and it casts itself. Throw the orb where you want the rain.",
			"hint": "Wait a moment for the bar to run out, then drag the glowing orb "
				+ "from your hand and let go over the fields.",
			"done": func() -> bool: return is_instance_valid(miracles) and miracles.casts_made >= 1,
		},
		{
			"say": "RUNES COMBINE. Summon casting again and draw TWO waves — water and "
				+ "water — for a cloudburst.",
			"hint": "Draw one S, lift, draw another S, then stop. Two of the same rune "
				+ "makes it bigger; two different ones make a third thing entirely.",
			"done": func() -> bool:
				return is_instance_valid(miracles) and miracles.last_rune_count >= 2,
		},
		{
			"say": "You are not alone. Find your creature." if touch
				else "You are not alone. Press C to find your creature.",
			"hint": "The Creature button, bottom right." if touch
				else "Press C. Press it again to let the camera go.",
			"done": _found_creature,
		},
		{
			"say": "It learns from you and from nothing else. Watch what it does, then "
				+ "PRAISE it or SCOLD it — whichever it earned.",
			"hint": "Bring your hand near the creature and use the Praise or Scold "
				+ "buttons." if touch
				else "Bring your hand near the creature and press P to praise, L to scold.",
			"done": func() -> bool: return is_instance_valid(creature) and creature.lessons > 0,
		},
		{
			"say": "That is everything you cannot guess. The rest is yours to find out — "
				+ "press F1 at any time for the full reckoning.",
			"hint": "",
			"done": func() -> bool: return false,   # the closing card; it just times out
			"linger": 7.0,
		},
	]


## Found it either way: locked the camera on, or simply walked the view over
## to where it is. A lesson should accept any honest route to the same place.
func _found_creature() -> bool:
	if not is_instance_valid(creature) or not is_instance_valid(camera_rig):
		return false
	if camera_rig.follow_target == creature:
		return true
	return creature.global_position.distance_to(camera_rig.global_position) < 40.0


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	_card.grow_horizontal = Control.GROW_DIRECTION_END
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.82)
	style.border_color = Color(1.0, 0.86, 0.5, 0.5)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(14)
	_card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(380, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_count_label)
	_tick = Label.new()
	_tick.add_theme_font_size_override("font_size", 12)
	_tick.add_theme_color_override("font_color", Color(0.45, 0.9, 0.6))
	_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_tick)
	box.add_child(top)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(380, 0)
	_text_label.add_theme_font_size_override("font_size", 16)
	_text_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text_label)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(380, 0)
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.72, 0.79, 0.9))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = false
	box.add_child(_hint_label)

	var skip := Label.new()
	skip.text = "(F4 skips these lessons)"
	skip.add_theme_font_size_override("font_size", 11)
	skip.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	skip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(skip)

	_card.add_child(box)
	add_child(_card)


func _advance() -> void:
	_at += 1
	_stuck = 0.0
	_dwell = 0.0
	_tick.text = ""
	_hint_label.visible = false
	if _at >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_at]
	_count_label.text = "LESSON %d of %d" % [_at + 1, _steps.size() - 1] \
		if _at < _steps.size() - 1 else "DONE"
	_text_label.text = String(step["say"])
	_hint_label.text = String(step.get("hint", ""))
	# Anchor whatever the step measures against from HERE, so a step can never
	# complete on something the player did before it was asked for.
	_origin = camera_rig.global_position if is_instance_valid(camera_rig) else Vector3.INF
	_saw_hold = false
	if step.has("linger"):
		_dwell = float(step["linger"])


func _finish() -> void:
	_mark_tutored()
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _at < 0 or _at >= _steps.size():
		return
	# Watch for a lift at any time: the step that asks for it may not be the
	# current one, and a player who picks something up early has still learned.
	if is_instance_valid(divine_hand) and divine_hand.held_body != null:
		_saw_hold = true

	if _dwell > 0.0:
		_dwell -= delta
		if _dwell <= 0.0:
			_advance()
		return

	var step: Dictionary = _steps[_at]
	if (step["done"] as Callable).call():
		_tick.text = "✓"
		_dwell = DONE_DWELL
		if is_instance_valid(camera_rig):
			SoundBank.play_at("coo", camera_rig.global_position, -8.0, 0.15)
		return
	_stuck += delta
	if _stuck > HINT_AFTER and _hint_label.text != "":
		_hint_label.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skip_tutorial"):
		_finish()
		GameState.announce("Lessons set aside. Press F1 for the full reckoning.")
