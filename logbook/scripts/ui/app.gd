extends Control
## The whole front end: a map with a status strip over it, a timeline under
## it, and a row of panels you can pull up.
##
## The map is never destroyed and never covered completely. Panels are sheets
## between the status strip and the nav bar, so a glance always finds speed,
## battery, and the weather line no matter what is open.

const NAV_H := 60.0
const RAIL_GAP := 10.0

var map: MapView
var status: StatusBar
var timeline: TimelineBar
var sheet_layer: Control
var nav: HBoxContainer
var _sheet: Sheet = null
var _toast: Label
var _toast_timer := 0.0
var _timeline_visible := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UI.build_theme()

	map = MapView.new()
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(map)
	map.event_tapped.connect(_open_event)
	map.cluster_tapped.connect(_open_cluster)
	map.map_long_pressed.connect(_quick_add_here)
	map.follow_changed.connect(func(_on: bool) -> void: _refresh_rail())

	status = StatusBar.new()
	status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	status.section_tapped.connect(_open_section)
	add_child(status)

	sheet_layer = Control.new()
	sheet_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet_layer)

	timeline = TimelineBar.new()
	timeline.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	timeline.offset_top = -(TimelineBar.HEIGHT + NAV_H)
	timeline.offset_bottom = -NAV_H
	timeline.scrubbed.connect(_on_scrub)
	timeline.event_picked.connect(_open_event)
	add_child(timeline)

	_build_nav()
	_build_rail()
	_build_toast()

	Wx.alerts_changed.connect(_on_alerts)
	Bike.connection_changed.connect(func(on: bool) -> void:
		toast(Bike.summary_line() if on else "Rig link lost"))
	Prefetch.finished.connect(func(ok: bool) -> void:
		toast("Offline map ready" if ok else "Offline map stopped"))

	# First launch: ask for what the service needs before it needs it.
	if Logbook.fix_count() == 0:
		Bridge.request_permissions()


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.visible = false


# --------------------------------------------------------------------- chrome


func _build_nav() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -NAV_H
	var style := UI.panel_style(Color(0.06, 0.07, 0.09, 0.95), 0)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)

	nav = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 2)
	bar.add_child(nav)
	var items := [
		["🗺", "map", "Map"],
		["≡", "days", "Days"],
		["✎", "journal", "Journal"],
		["⚑", "stops", "Stops"],
		["☂", "weather", "Weather"],
		["⚙", "bike", "Rig"],
		["⋯", "settings", "Settings"],
	]
	for item: Array in items:
		var b := UI.button(String(item[0]), _open_section.bind(String(item[1])))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(item[2])
		b.add_theme_font_size_override("font_size", UI.fs(19))
		nav.add_child(b)


func _build_rail() -> void:
	var rail := VBoxContainer.new()
	rail.name = "Rail"
	rail.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	rail.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rail.grow_vertical = Control.GROW_DIRECTION_BOTH
	rail.offset_right = -RAIL_GAP
	rail.add_theme_constant_override("separation", 8)
	add_child(rail)
	rail.add_child(UI.icon_button("+", _quick_add_menu, "Add an entry"))
	rail.add_child(UI.icon_button("◎", func() -> void:
		map.set_follow(not map.following), "Follow me"))
	rail.add_child(UI.icon_button("☾", func() -> void:
		Cfg.toggle("night_mode")
		_rebuild_theme(), "Night mode"))
	rail.add_child(UI.icon_button("▦", _toggle_radar, "Radar"))
	rail.add_child(UI.icon_button("⏱", _toggle_timeline, "Timeline"))
	rail.add_child(UI.icon_button("♪", func() -> void: Music.play_pause(), "Play / pause"))


func _refresh_rail() -> void:
	var rail := get_node_or_null("Rail")
	if rail == null:
		return
	var follow_button := rail.get_child(1) as Button
	follow_button.modulate = Color.WHITE if map.following else Color(0.55, 0.55, 0.6)


func _build_toast() -> void:
	_toast = UI.label("", 15)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_bottom = -(NAV_H + TimelineBar.HEIGHT + 16)
	_toast.offset_top = _toast.offset_bottom - 40
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color.WHITE)
	_toast.visible = false
	add_child(_toast)


func toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_timer = 3.0


func _rebuild_theme() -> void:
	theme = UI.build_theme()
	map.queue_redraw()


func _toggle_radar() -> void:
	if map.radar_frame == "":
		var id := Wx.current_frame_id()
		if id == "":
			toast("No radar yet — needs a moment of data")
			Wx.refresh(true)
			return
		map.radar_frame = id
	else:
		map.radar_frame = ""
	map.queue_redraw()


func _toggle_timeline() -> void:
	_timeline_visible = not _timeline_visible
	timeline.visible = _timeline_visible


# --------------------------------------------------------------------- input


## A bluetooth keyboard is a first-class input here: it is what makes writing
## a real journal entry at the end of a day bearable.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed or k.meta_pressed:
		return
	match k.keycode:
		KEY_J:
			_open_section("journal")
		KEY_M:
			_close_sheet()
		KEY_N:
			_new_note()
		KEY_W:
			_open_section("weather")
		KEY_B:
			_open_section("bike")
		KEY_D:
			_open_section("days")
		KEY_P:
			_open_section("stops")
		KEY_SPACE:
			Music.play_pause()
		KEY_BRACKETRIGHT:
			Music.next_track()
		KEY_BRACKETLEFT:
			Music.prev_track()
		KEY_ESCAPE:
			_close_sheet()
		KEY_L:
			timeline.go_live()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_scrub(t: float) -> void:
	map.highlight_time = t
	if t >= 0.0:
		var p := Logbook.latlon_at_time(t)
		if p != Vector2.INF:
			map.set_follow(false)
			map.set_center_latlon(p.x, p.y)
	map.queue_redraw()


func _on_alerts() -> void:
	var a := Wx.worst_alert()
	if not a.is_empty():
		toast("⚠ " + String(a.get("event", "Weather alert")))


# -------------------------------------------------------------------- sheets


func _open_section(which: String) -> void:
	match which:
		"map":
			_close_sheet()
		"days":
			show_sheet(DaysPanel.new(self))
		"journal":
			show_sheet(JournalPanel.new())
		"stops":
			show_sheet(StopsPanel.new(map))
		"weather":
			show_sheet(WeatherPanel.new(map))
		"bike":
			show_sheet(BikePanel.new())
		"settings":
			show_sheet(SettingsPanel.new(map))


func show_sheet(sheet: Sheet) -> void:
	_close_sheet()
	_sheet = sheet
	sheet_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_top = maxf(status.size.y, 76.0) + 6
	sheet.offset_bottom = -(NAV_H + 6)
	sheet.offset_left = 6
	sheet.offset_right = -6
	sheet.closed.connect(func() -> void:
		_sheet = null
		sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	sheet_layer.add_child(sheet)
	sheet.open()


func _close_sheet() -> void:
	if _sheet != null:
		_sheet.close()
		_sheet = null
	sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open_event(id: String) -> void:
	var e := Logbook.get_event(id)
	if e.is_empty():
		return
	show_sheet(EventSheet.new(e, map))


func _open_cluster(ids: Array, _at: Vector2) -> void:
	show_sheet(ClusterSheet.new(ids, _open_event))


# ----------------------------------------------------------------- capture


func _quick_add_menu() -> void:
	show_sheet(AddSheet.new(Vector2.INF, self))


func _quick_add_here(latlon: Vector2) -> void:
	show_sheet(AddSheet.new(latlon, self))


func _new_note() -> void:
	var panel := JournalPanel.new()
	show_sheet(panel)
	panel.new_entry()


## Create an event of `kind` at `latlon` (or here, if INF) and open whatever
## editor that kind deserves.
func add_event(kind: String, latlon: Vector2) -> void:
	var data := {}
	if latlon != Vector2.INF:
		data["lat"] = latlon.x
		data["lon"] = latlon.y
	match kind:
		Ev.NOTE:
			var panel := JournalPanel.new()
			show_sheet(panel)
			panel.new_entry(latlon)
			return
		Ev.PHOTO:
			Bridge.take_photo()
			toast("Camera…")
			_close_sheet()
			return
		Ev.AUDIO:
			var e := Logbook.append_event(Ev.AUDIO, data)
			Bridge.start_audio_memo(Logbook.media_dir().path_join(String(e["id"]) + ".m4a"))
			toast("Recording — tap again to stop")
			_close_sheet()
			return
		Ev.STOP_PLAN:
			var stop := Logbook.append_event(Ev.STOP_PLAN, data)
			show_sheet(StopEditor.new(stop, map))
			return
		_:
			data["text"] = Ev.label(kind)
			Logbook.append_event(kind, data)
			toast("%s logged" % Ev.label(kind))
			_close_sheet()
