class_name ProfileMenu
extends CanvasLayer
## THE CREATURES YOU HAVE RAISED (F5).
##
## A creature is a long relationship, and the same player very reasonably wants
## more than one: a beloved beast raised kindly over weeks, and a monster to let
## off the leash on a wet afternoon. Neither should cost the other, and neither
## should be an hour of undoing. So each lives in its own profile, and this is
## where you pick one up and put another down.
##
## The list describes each creature by what it has BECOME rather than by a slot
## number — "Baldur, a tender wrecker, 12% grown, 1h 40m" — because that is how
## anyone actually remembers which save is which.
##
## It opens by itself the first time you ever play, with the cursor already in
## the name field, because naming the thing you are about to raise is the right
## first act of a god and a worse thing to bury in a menu.

const MAX_NAME := 24
const CONFIRM_SECONDS := 4.0

var _backdrop: ColorRect
var _panel: PanelContainer
var _list: VBoxContainer
var _name_row: HBoxContainer
var _name_field: LineEdit
var _title: Label
var _confirm := ""          # the profile id armed for deletion
var _confirm_time := 0.0
var _prompt: Label
## The profile the name field is currently RENAMING, or "" when it is naming a
## brand new one. A creature adopted from a save made before names existed comes
## through with none, and should be able to get one without starting again.
var _renaming := ""
var _begin: Button


func _ready() -> void:
	layer = 13
	_build()
	# A god with no creature is asked to name one before anything else happens.
	if SaveGame.profiles.is_empty():
		open(true)


func _build() -> void:
	# On the very first run there is nothing behind this worth touching, and a
	# player who wanders off and plays for a minute would lose that minute to
	# the reload when they finally name the thing. So the first time — and only
	# the first time — the world underneath is covered and held.
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.01, 0.01, 0.03, 0.75)
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
	style.bg_color = Color(0.03, 0.04, 0.08, 0.94)
	style.border_color = Color(1.0, 0.86, 0.5, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(520, 0)

	_title = Label.new()
	_title.text = "THE CREATURES YOU HAVE RAISED"
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	box.add_child(_title)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	box.add_child(_list)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 14)
	_prompt.add_theme_color_override("font_color", Color(0.72, 0.79, 0.9))
	box.add_child(_prompt)

	_name_row = HBoxContainer.new()
	_name_row.add_theme_constant_override("separation", 8)
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Name your creature…"
	_name_field.max_length = MAX_NAME
	_name_field.custom_minimum_size = Vector2(300, 44)
	_name_field.add_theme_font_size_override("font_size", 18)
	_name_field.text_submitted.connect(_on_named)
	_name_row.add_child(_name_field)
	_begin = Button.new()
	_begin.text = "Begin"
	_begin.custom_minimum_size = Vector2(120, 44)
	_begin.focus_mode = Control.FOCUS_NONE
	_begin.add_theme_font_size_override("font_size", 18)
	_begin.pressed.connect(func() -> void: _on_named(_name_field.text))
	_name_row.add_child(_begin)
	box.add_child(_name_row)

	var close := Button.new()
	close.text = "Back to the world  [F5]"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_menu)
	box.add_child(close)

	_panel.add_child(box)
	add_child(_panel)


## Show the menu. `naming` puts the cursor straight in the name field, which is
## what the very first run and the "raise another" button both want.
func open(naming := false) -> void:
	_refresh()
	_panel.visible = true
	var first := SaveGame.profiles.is_empty()
	_backdrop.visible = first
	_title.text = "NAME YOUR CREATURE" if first else "THE CREATURES YOU HAVE RAISED"
	_prompt.text = "What will you call it?" if first \
		else "Raise another — it begins in a world of its own, and costs these nothing."
	if naming:
		_name_field.grab_focus()


func close_menu() -> void:
	# There must always be a way back to the world — except before there is a
	# creature to go back to.
	if SaveGame.profiles.is_empty():
		return
	_panel.visible = false
	_backdrop.visible = false
	_disarm()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	if SaveGame.profiles.is_empty():
		var none := Label.new()
		none.text = "You have raised nothing yet."
		none.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		_list.add_child(none)
		return
	for entry: Dictionary in SaveGame.profiles:
		_list.add_child(_row(entry))


## One creature, described by what it has become rather than by a slot number.
func _row(entry: Dictionary) -> Control:
	var id := String(entry.get("id", ""))
	var mine := id == SaveGame.active
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	var named := String(entry.get("name", ""))
	label.text = "%s%s — %s · %d%% grown · %s played" % [
		named if named != "" else "(unnamed)",
		"   ← you are here" if mine else "",
		String(entry.get("character", "newborn")),
		int(float(entry.get("growth", 0.0)) * 100.0),
		SaveGame.spent(float(entry.get("played", 0.0)))]
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color",
		Color(1.0, 0.92, 0.7) if mine else Color(0.86, 0.9, 0.96))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if named == "":
		var christen := Button.new()
		christen.text = "Name it"
		christen.custom_minimum_size = Vector2(96, 34)
		christen.focus_mode = Control.FOCUS_NONE
		christen.pressed.connect(_on_rename.bind(id))
		row.add_child(christen)

	if not mine:
		var play := Button.new()
		play.text = "Play"
		play.custom_minimum_size = Vector2(84, 34)
		play.focus_mode = Control.FOCUS_NONE
		play.pressed.connect(func() -> void: SaveGame.switch_to(id))
		row.add_child(play)

	var drop := Button.new()
	drop.text = "Forget"
	drop.custom_minimum_size = Vector2(96, 34)
	drop.focus_mode = Control.FOCUS_NONE
	drop.add_theme_color_override("font_color", Color(1.0, 0.72, 0.66))
	drop.pressed.connect(_on_forget.bind(id, drop, named))
	row.add_child(drop)
	return row


## Forgetting a creature is the one thing here that cannot be undone, so it
## arms first and disarms itself after a few seconds.
func _on_forget(id: String, button: Button, named: String) -> void:
	if _confirm == id:
		_disarm()
		SaveGame.forget(id)
		GameState.announce("%s is forgotten." % (named if named != "" else "That creature"))
		if SaveGame.profiles.is_empty():
			open(true)
		else:
			_refresh()
		return
	_disarm()
	_confirm = id
	_confirm_time = CONFIRM_SECONDS
	button.text = "Really?"


func _disarm() -> void:
	_confirm = ""
	_confirm_time = 0.0


## Point the name field at an existing creature instead of a new one.
func _on_rename(id: String) -> void:
	_renaming = id
	_begin.text = "Name it"
	_prompt.text = "What should this one have been called?"
	_name_field.grab_focus()


func _on_named(text: String) -> void:
	var given := text.strip_edges()
	if given == "":
		return
	_name_field.text = ""
	if _renaming != "":
		# Naming a creature already alive: the profile takes the name, and so
		# does the beast itself if this is the one currently under your hand.
		var entry := SaveGame.profile(_renaming)
		var was_active := _renaming == SaveGame.active
		_renaming = ""
		_begin.text = "Begin"
		if not entry.is_empty():
			entry["name"] = given.substr(0, MAX_NAME)
			SaveGame.write_index()
		if was_active:
			var beast := get_tree().get_first_node_in_group("creature") as Creature
			if beast != null:
				beast.name_it(given)
			GameState.announce("You name your creature %s." % given)
		_refresh()
		return
	_panel.visible = false
	_backdrop.visible = false
	SaveGame.start_new(given)


func _process(delta: float) -> void:
	if _confirm_time > 0.0:
		_confirm_time -= delta
		if _confirm_time <= 0.0:
			_disarm()
			if _panel.visible:
				_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_profiles"):
		return
	if _panel.visible:
		close_menu()
	else:
		open()
	get_viewport().set_input_as_handled()
