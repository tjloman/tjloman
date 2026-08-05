class_name StatusBar extends PanelContainer
## The strip across the top: the handful of numbers worth reading at 15 mph.
##
## Nothing here is interactive except the tap targets that open the panel
## behind each number, and nothing animates. A bike computer that redraws
## constantly is both distracting and a battery cost; this repaints once a
## second and only the labels that changed.

signal section_tapped(which: String)

var _speed: Label
var _dist: Label
var _batt: Label
var _clock: Label
var _line2: Label
var _tick := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var style := UI.panel_style(Color(0.06, 0.07, 0.09, 0.88), 0)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_speed = UI.label("—", 26)
	_dist = UI.label("—", 20, UI.INK_DIM)
	_batt = UI.label("—", 20, UI.GOOD)
	_clock = UI.label("—", 20, UI.INK_DIM)
	top.add_child(_tap(_speed, "map"))
	top.add_child(_tap(_dist, "days"))
	top.add_child(UI.spacer())
	top.add_child(_tap(_batt, "bike"))
	top.add_child(_clock)
	col.add_child(top)

	_line2 = UI.label("", 12, UI.INK_DIM)
	_line2.clip_text = true
	col.add_child(_tap(_line2, "weather"))


func _tap(node: Control, which: String) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
			section_tapped.emit(which))
	return node


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	refresh()


func refresh() -> void:
	_speed.text = Cfg.speed(Trip.speed_mps) if Trip.gps_ok else "no fix"
	_speed.add_theme_color_override("font_color", UI.ink() if Trip.gps_ok else UI.WARN)
	_dist.text = Cfg.dist(Trip.today_meters)
	_clock.text = UI.clock(Time.get_unix_time_from_system())

	if Bike.connected and Bike.state.has("soc"):
		var soc := int(float(Bike.state["soc"]))
		_batt.text = "%d%%" % soc
		var col := UI.GOOD
		if soc <= Cfg.get_i("low_battery_warn_pct"):
			col = UI.DANGER
		elif soc <= 40:
			col = UI.WARN
		_batt.add_theme_color_override("font_color", col)
	else:
		_batt.text = "— %"
		_batt.add_theme_color_override("font_color", UI.INK_DIM)

	_line2.text = " · ".join(_status_parts())


## One line, most urgent first. It is the only place the app admits what it
## does not know: a stale weather reading says so, a dead GPS says so.
func _status_parts() -> PackedStringArray:
	var parts := PackedStringArray()
	var alert := Wx.worst_alert()
	if not alert.is_empty():
		parts.push_back("⚠ " + String(alert.get("event", "alert")))
	if not Trip.logging:
		parts.push_back("logging OFF")
	elif Trip.paused:
		parts.push_back("paused")
	if Trip.gps_ok:
		parts.push_back("gps ±%dm" % int(Trip.last_accuracy))
	else:
		parts.push_back("gps %s" % ("searching" if Trip.fix_age == INF else UI.ago(Trip.fix_age)))
	if not Wx.current.is_empty():
		parts.push_back(Wx.summary_line())
	if not Net.online:
		parts.push_back("offline")
	elif Net.metered:
		parts.push_back("cell %.0fMB left" % Net.budget_left_mb())
	if Prefetch.running:
		parts.push_back("map %d%%" % int(100.0 * Prefetch.done / maxi(1, Prefetch.total)))
	if Music.playing:
		parts.push_back("♪ " + Music.title_line())
	return parts
