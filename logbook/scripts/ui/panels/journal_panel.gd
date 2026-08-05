class_name JournalPanel extends Sheet
## The journal: write, and read back what you wrote.
##
## Every entry is stamped with where you were when you started it, which is
## the difference between a diary and a logbook. Entries autosave — a phone
## dying mid-sentence should cost you a sentence, not an evening.

const AUTOSAVE_MARK := "  ·  saved"

var _editing := {}
var _edit: TextEdit
var _keyboard: OnscreenKeyboard
var _status: Label
var _save_timer := 0.0
var _dirty := false


func _init() -> void:
	super("Journal")


func _ready() -> void:
	_build_list()


func _process(delta: float) -> void:
	if not _dirty:
		return
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save()


## Anything typed on a real keyboard means the on-screen one is in the way.
func _input(event: InputEvent) -> void:
	if _keyboard == null or not _keyboard.visible:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and k.physical_keycode != 0 and not k.echo:
		if k.unicode > 0 or k.keycode == KEY_BACKSPACE:
			_keyboard.visible = false


# -------------------------------------------------------------------- list


func _build_list() -> void:
	set_title("Journal")
	clear()
	body.add_child(UI.button("✎   New entry", func() -> void: new_entry(), true))
	var notes := Logbook.events_of_kind(Ev.NOTE)
	if notes.is_empty():
		body.add_child(UI.dim("Nothing written yet. Entries you write here are pinned"
			+ " to wherever you were when you started them."))
		return
	var last_day := ""
	for i in range(notes.size() - 1, -1, -1):
		var e := notes[i]
		var t := float(e.get("t", 0.0))
		var day := Logbook.day_key(t)
		if day != last_day:
			last_day = day
			body.add_child(UI.dim(UI.date_line(t).to_upper(), 12))
		var text := String(e.get("text", "")).strip_edges()
		var preview := text.substr(0, 140).replace("\n", " ")
		if text.length() > 140:
			preview += "…"
		var card := UI.card([
			UI.row([UI.dim(UI.clock(t), 12), UI.spacer(),
				UI.dim("%d words" % _words(text), 12)]),
			UI.label(preview if preview != "" else "(empty)", 15),
		])
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
				_open(e))
		body.add_child(card)


static func _words(text: String) -> int:
	var n := 0
	for w in text.split(" ", false):
		if w.strip_edges() != "":
			n += 1
	return n


# ------------------------------------------------------------------ editor


## Start a new entry. `latlon` overrides where it is pinned — used when you
## long-press a spot on the map and choose "Note".
func new_entry(latlon: Vector2 = Vector2.INF) -> void:
	var data := {"text": ""}
	if latlon != Vector2.INF:
		data["lat"] = latlon.x
		data["lon"] = latlon.y
	_open(Logbook.append_event(Ev.NOTE, data))


func _open(e: Dictionary) -> void:
	_save()
	_editing = e
	clear()
	var t := float(e.get("t", 0.0))
	set_title("%s · %s" % [UI.date_line(t), UI.clock(t)])

	var place := "somewhere unlogged"
	if e.has("lat"):
		place = Geo.format_latlon(float(e["lat"]), float(e["lon"]))
	_status = UI.dim(place, 12)
	body.add_child(_status)

	_edit = TextEdit.new()
	_edit.text = String(e.get("text", ""))
	_edit.custom_minimum_size.y = 260
	_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.placeholder_text = "How was the road?"
	_edit.text_changed.connect(func() -> void:
		_dirty = true
		_save_timer = Cfg.get_f("journal_autosave_seconds"))
	body.add_child(_edit)
	_edit.grab_focus()

	body.add_child(UI.row([
		UI.button("⌨", func() -> void:
			_keyboard.visible = not _keyboard.visible),
		UI.button("Weather stamp", _stamp_weather),
		UI.spacer(),
		UI.button("Done", func() -> void:
			_save()
			_build_list()),
	]))

	_keyboard = OnscreenKeyboard.new()
	_keyboard.attach(_edit)
	_keyboard.dismissed.connect(func() -> void: _keyboard.visible = false)
	_keyboard.visible = Cfg.get_b("onscreen_keyboard")
	body.add_child(_keyboard)


## Drop the conditions into the text. Six months later "it was hot" means
## nothing; "94°F, 18 mph headwind" is the day you remember.
func _stamp_weather() -> void:
	if _edit == null:
		return
	var line := Wx.summary_line()
	if not Bike.state.is_empty():
		line += "  ·  battery " + Bike.summary_line()
	_edit.insert_text_at_caret("\n[%s — %s]\n" % [UI.clock(Time.get_unix_time_from_system()), line])
	_dirty = true
	_save_timer = 1.0


func _save() -> void:
	if not _dirty or _editing.is_empty() or _edit == null:
		return
	_dirty = false
	Logbook.update_event(String(_editing.get("id", "")), {"text": _edit.text})
	if _status != null:
		_status.text = String(_status.text).trim_suffix(AUTOSAVE_MARK) + AUTOSAVE_MARK


func close() -> void:
	_save()
	super()
