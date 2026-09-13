class_name Storyboard
extends CanvasLayer
## STORYBOARDS: scripted sequences, cinematic or interactive, written as DATA.
##
## Yes, you can hand me a storyboard. This is the format it lands in, and it is
## deliberately small — eight words, all optional — because a vocabulary you can
## hold in your head is one you will actually write in.
##
## A STORYBOARD IS AN ARRAY OF BEATS. A beat is a dictionary:
##
##   "say"    the line on the card. Omit for a silent shot.
##   "hint"   a second line, shown only once the player has been stuck a while.
##   "look"   frame the camera on this — a Node3D, a Vector3, or a Callable
##            returning either. The shot eases in; it does not snap.
##   "hold"   follow this Node3D with the camera for the length of the beat.
##   "wait"   seconds. With no "until", this alone ends the beat — which is how
##            a cinematic plays itself.
##   "until"  Callable -> bool. The player must make it true. With "wait" as
##            well, the wait is a floor: the beat cannot end sooner.
##   "do"     Callable, run once when the beat OPENS. Move things, plant
##            things, give things.
##   "then"   Callable, run once when the beat CLOSES.
##   "free"   false to take the hand away for the length of the beat. Default
##            true: the player keeps their hand, which is what makes this a
##            game rather than a film.
##
## THAT IS THE WHOLE GRAMMAR, and it covers all three of the things you asked
## about with no separate machinery for any of them:
##
##   A CINEMATIC is beats with "look" and "wait" and no "until" — it plays.
##   A TUTORIAL is beats with "say" and "until" — it waits for the player.
##   A QUEST is beats with "do" and "then" — it changes the world.
##
## Most real beats are a mix, which is the point. Nothing here knows the
## difference between a cutscene and a lesson, because there is not one.
##
## WHAT IT DELIBERATELY DOES NOT DO. No branching, no variables, no state
## machine. A storyboard is a straight line through a sequence; anything that
## needs to fork is two storyboards and a Callable that picks. That limit is
## what keeps the format writable by hand — and it is easy to lift later, once
## something actually needs it.

## How long the camera takes to ease onto a new shot, and how often a "hold"
## re-aims. Both slow: a camera that snaps reads as a bug.
const FRAME_EASE := 1.1
## How long the player must be stuck before the hint appears.
const HINT_AFTER := 9.0
## And how long a finished beat sits there ticked before the next one opens.
const BEAT_REST := 1.2


var camera_rig: CameraRig
var divine_hand: DivineHand

var beats: Array = []
var running := false

var _at := -1
var _elapsed := 0.0
var _rest := 0.0
var _card: PanelContainer
var _line: Label
var _hint: Label
var _tick: Label
var _ease := 0.0
var _aim := Vector3.INF


func _ready() -> void:
	layer = 9
	_build_card()
	visible = false


## RUN ONE. Hand it an array of beats; it plays them in order and stops.
func play(board: Array) -> void:
	beats = board
	_at = -1
	running = true
	visible = true
	set_process(true)
	_open_next()


func stop() -> void:
	running = false
	visible = false
	set_process(false)
	_release_hand()


## WHICH BEAT IS ON, for anything that wants to know (a save, a debug readout).
func at() -> int:
	return _at


func _process(delta: float) -> void:
	if not running or _at < 0 or _at >= beats.size():
		return
	_ease = minf(_ease + delta, FRAME_EASE)
	var beat: Dictionary = beats[_at]
	_hold_camera(beat)
	if _rest > 0.0:
		_rest -= delta
		if _rest <= 0.0:
			_open_next()
		return
	_elapsed += delta
	if _finished(beat):
		_close(beat)
		return
	if _elapsed > HINT_AFTER and _hint.text != "":
		_hint.visible = true


## HAS THIS BEAT RUN ITS COURSE? A wait with no condition simply elapses; a
## condition with no wait waits for the player; both together mean the beat has
## a minimum length AND something to satisfy.
func _finished(beat: Dictionary) -> bool:
	var floor_time := float(beat.get("wait", 0.0))
	if _elapsed < floor_time:
		return false
	if not beat.has("until"):
		return floor_time > 0.0
	return bool((beat["until"] as Callable).call())


func _close(beat: Dictionary) -> void:
	_tick.text = "✓" if beat.has("until") else ""
	if beat.has("then"):
		(beat["then"] as Callable).call()
	_release_hand()
	_rest = BEAT_REST


func _open_next() -> void:
	_at += 1
	_elapsed = 0.0
	_rest = 0.0
	_ease = 0.0
	_tick.text = ""
	_hint.visible = false
	if _at >= beats.size():
		stop()
		return
	var beat: Dictionary = beats[_at]
	_line.text = String(beat.get("say", ""))
	_hint.text = String(beat.get("hint", ""))
	_card.visible = _line.text != ""
	if beat.has("do"):
		(beat["do"] as Callable).call()
	if not bool(beat.get("free", true)):
		_take_hand()
	_aim = _spot_of(beat.get("look", null))
	if _aim != Vector3.INF and is_instance_valid(camera_rig):
		camera_rig.follow_target = null


## WHERE A BEAT WANTS THE CAMERA. A node, a point, or a Callable that works it
## out at the moment the beat opens — which is what you want for anything that
## has moved since you wrote the storyboard.
func _spot_of(what: Variant) -> Vector3:
	if what == null:
		return Vector3.INF
	if what is Callable:
		return _spot_of((what as Callable).call())
	if what is Vector3:
		return what
	if what is Node3D and is_instance_valid(what):
		return (what as Node3D).global_position
	return Vector3.INF


## EASE, NEVER SNAP. A shot that cuts reads as a glitch in a game where the
## camera is otherwise always under the player's own hand.
func _hold_camera(beat: Dictionary) -> void:
	if not is_instance_valid(camera_rig):
		return
	var held = beat.get("hold", null)
	if held is Node3D and is_instance_valid(held):
		camera_rig.follow_target = held
		return
	if _aim == Vector3.INF:
		return
	var t := clampf(_ease / FRAME_EASE, 0.0, 1.0)
	camera_rig.global_position = camera_rig.global_position.lerp(_aim, t * 0.08)


## TAKING THE HAND AWAY, for the length of a shot that is genuinely a film. Used
## sparingly: a player who cannot touch anything is watching, not playing.
func _take_hand() -> void:
	if is_instance_valid(divine_hand):
		divine_hand.set_process_unhandled_input(false)


func _release_hand() -> void:
	if is_instance_valid(divine_hand):
		divine_hand.set_process_unhandled_input(true)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 0.9)
	style.border_color = Color(1.0, 0.86, 0.5, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_card.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	_line = _label(18, Color(1.0, 0.94, 0.78))
	rows.add_child(_line)
	_hint = _label(13, Color(0.72, 0.76, 0.84))
	_hint.visible = false
	rows.add_child(_hint)
	_tick = _label(20, Color(0.6, 1.0, 0.65))
	_tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_tick)
	_card.add_child(rows)
	add_child(_card)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(620, 0)
	return l
