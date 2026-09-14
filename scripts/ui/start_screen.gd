class_name StartScreen
extends CanvasLayer
## WHAT A PHONE CANNOT REACH.
##
## Five things live on function keys: help (F1), the graphics tier (F2), the
## debug menu (F3), skipping the tutorial (F4) and the creature profiles (F5).
## On a keyboard that is exactly right — they are there when you want them and
## out of the way when you do not. On a thumb there is no F1, and so there is
## no help, no way to change quality, and no way to skip a tutorial you have
## already sat through four times. They were simply gone.
##
## So they are all here, once, at the start, where a player is already deciding
## what kind of session this is going to be. It is not a main menu with a New
## Game button — the world is already made and standing behind this — it is the
## moment before you begin, and everything you might want to have settled first.
##
## THE WORLD IS HELD WHILE IT IS UP, AND STILL LOADING. Nothing ages, nothing
## starves, nobody walks anywhere — a player who reads every line of the help
## should not come back to a village that lived through it.
##
## But a paused tree does not stream chunks either, and streaming is most of
## what "loading" means here; pause everything and the one thing you wanted to
## happen behind the screen is the one thing that stops. So the pause is real
## and the loader is exempt from it by name: WorldGen runs always and marks
## every chunk it spawns pausable, so while the screen is up the only thing
## happening in the world is ground arriving. See WorldGen._process.

## How much warming to do per frame. Small on purpose: this runs while somebody
## is reading, and a screen that stutters while it promises smoothness is a poor
## advertisement for itself.
const WARM_PER_FRAME := 2


var profiles: ProfileMenu = null

var _panel: PanelContainer
var _backdrop: ColorRect
var _quality_button: Button
var _progress: Label
var _waiting_to_name := false
var _begun := false
var _warm_jobs: Array[Callable] = []


func _ready() -> void:
	layer = 12          # under the profile menu, which is its own modal
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_fill_warm_jobs()
	# THE FIRST RUN NAMES THE CREATURE FIRST. ProfileMenu opens itself when
	# there are no profiles, and naming the thing you are about to raise is
	# the right first act of a god — this comes after it, not over it.
	_waiting_to_name = SaveGame.profiles.is_empty()
	if _waiting_to_name:
		_hold()          # hold the world anyway, so the naming costs nothing
	else:
		_show()


func _process(_delta: float) -> void:
	if _waiting_to_name:
		if profiles == null or not profiles.is_open():
			_waiting_to_name = false
			_show()
		return
	if not _begun:
		_warm()          # including while the first creature is being named


## THE THINGS THAT WOULD OTHERWISE HITCH LATER, done now while somebody reads.
##
## Every one of these is a cache that builds itself the first time it is asked
## for: the sound bank synthesizes twenty-four waveforms, the model bank hits
## the filesystem once per name it has never looked for, and the herd's pose
## table is built on the first frame a herd is drawn. Left alone they land on
## the first wolf, the first sheep and the first herd over the hill — which is
## to say, all in the first ten seconds, together.
func _fill_warm_jobs() -> void:
	_warm_jobs.append(func() -> bool: return SoundBank.warm_next())
	var names: Array = ModelBank.KNOWN.duplicate()
	names.append_array(Animal.SPECIES.keys())
	_warm_jobs.append(func() -> bool:
		if names.is_empty():
			return false
		ModelBank.has(names.pop_back())
		return true)
	# One pose table for the whole world, built once and then only refreshed.
	_warm_jobs.append(func() -> bool:
		HerdMotion.refresh(0.0)
		return false)


func _warm() -> void:
	for i in WARM_PER_FRAME:
		var busy := false
		for job in _warm_jobs:
			if job.call():
				busy = true
				break
		if not busy:
			_progress.text = "Ready."
			return
	# The sound bank is by far the bulk of it — twenty-four waveforms — so its
	# share is a fair reading of the whole.
	_progress.text = "Making ready... %d%%" % int(SoundBank.warmth() * 100.0)


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.01, 0.03, 0.72)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 0.95)
	style.border_color = Color(1.0, 0.86, 0.5, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.add_child(_heading("Hand of the Heavens"))
	rows.add_child(_note("The world is made and waiting. Settle these first —"
		+ " every one of them can be changed later on a keyboard."))

	_quality_button = _row("", _on_quality)
	rows.add_child(_quality_button)
	rows.add_child(_row("Your creatures  [F5]", _fire.bind("toggle_profiles")))
	# The temple's real door is holding the sun, which nobody discovers by
	# accident. One line here is what makes the gesture findable at all.
	rows.add_child(_row("The temple — or hold the sun  [F6]",
		_fire.bind("toggle_temple")))
	rows.add_child(_row("How to play  [F1]", _fire.bind("toggle_help")))
	rows.add_child(_row("Skip the tutorial  [F4]", _fire.bind("skip_tutorial")))
	rows.add_child(_row("Debug menu  [F3]", _fire.bind("toggle_debug")))

	_progress = _note("")
	rows.add_child(_progress)

	var begin := _row("Begin", _on_begin)
	begin.add_theme_font_size_override("font_size", 22)
	begin.custom_minimum_size = Vector2(280, 56)
	rows.add_child(begin)

	_panel.add_child(rows)
	add_child(_panel)
	_refresh_labels()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.62))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


## Big enough for a thumb, which is the entire reason this screen exists.
func _row(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(on_press)
	return b


func _refresh_labels() -> void:
	_quality_button.text = "Graphics: %s  [F2]" \
		% str(Quality.Tier.keys()[Quality.tier]).capitalize()


## EVERY BUTTON HERE PULLS THE SAME LEVER ITS KEY DOES. Not a second copy of
## each behaviour that happens to look alike — one of those two would quietly
## rot, and it would be the one nobody on a keyboard ever presses.
func _fire(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _on_quality() -> void:
	Quality.cycle()
	_refresh_labels()


func _on_begin() -> void:
	_begun = true
	_panel.visible = false
	_backdrop.visible = false
	get_tree().paused = false


func _show() -> void:
	_refresh_labels()
	_panel.visible = true
	_backdrop.visible = true
	_hold()


func _hold() -> void:
	get_tree().paused = true
