class_name WeatherPanel extends Sheet
## Conditions, the next twelve hours, active warnings, and radar.
##
## Written around the assumption that the data is old. Every block says when
## it was fetched, because "80°F and clear" from four hours ago is a different
## fact from "80°F and clear" now, and on a bike that difference is a soaking.

var _map: MapView


func _init(map: MapView) -> void:
	super("Weather")
	_map = map


func _ready() -> void:
	_build()
	Wx.updated.connect(_build)
	Wx.alerts_changed.connect(_build)
	Wx.radar_changed.connect(_build)


func _build() -> void:
	clear()
	body.add_child(UI.row([
		UI.button("Refresh now", func() -> void: Wx.refresh(true), true),
		UI.spacer(),
		UI.dim(_freshness(), 12),
	]))
	if not Wx.alerts.is_empty():
		for a in Wx.alerts:
			body.add_child(_alert_card(a))
	if Wx.current.is_empty():
		body.add_child(UI.dim("No conditions fetched yet. This needs data once;"
			+ " after that the last reading stays here, marked with its age."))
	else:
		body.add_child(_current_card())
		body.add_child(_hourly_strip())
	body.add_child(UI.separator())
	body.add_child(_radar_block())


func _freshness() -> String:
	if Wx.fetched_at <= 0.0:
		return "never fetched"
	if not Net.online:
		return "offline · %s" % UI.ago(Wx.age_seconds())
	return UI.ago(Wx.age_seconds())


func _current_card() -> Control:
	var c := Wx.current
	var unit := "°C" if bool(c.get("metric", false)) else "°F"
	var wind_unit := "km/h" if bool(c.get("metric", false)) else "mph"
	var comp := Wx.wind_component()
	var comp_text := "—"
	var comp_color := UI.INK_DIM
	if absf(comp) > 1.0:
		comp_text = "%d %s %s" % [int(absf(comp)), wind_unit, "head" if comp > 0.0 else "tail"]
		comp_color = UI.WARN if comp > 0.0 else UI.GOOD
	return UI.card([
		UI.row([
			UI.stat("now", "%d%s" % [int(round(float(c["temp"]))), unit]),
			UI.stat("feels", "%d%s" % [int(round(float(c["feels"]))), unit], UI.INK_DIM),
			UI.stat("wind", "%d %s %s" % [int(float(c["wind"])), wind_unit,
				Geo.compass(float(c["wind_dir"]))]),
		], 14),
		UI.row([
			UI.stat("for you", comp_text, comp_color),
			UI.stat("gusts", "%d" % int(float(c.get("gust", 0.0))), UI.INK_DIM),
			UI.stat("sky", Wx.code_text(int(c["code"]))),
		], 14),
	])


## The next twelve hours as bars: precipitation chance behind, temperature
## in front. It is the shape of the afternoon at a glance.
func _hourly_strip() -> Control:
	var now := Time.get_unix_time_from_system()
	var rows := HBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	var shown := 0
	for h in Wx.hourly:
		var t := float(h["t"])
		if t < now - 1800.0 or shown >= 12:
			continue
		shown += 1
		var prob := int(float(h.get("precip_prob", 0.0)))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		col.add_child(UI.dim(UI.clock(t).substr(0, 5), 10))
		var bar := ColorRect.new()
		bar.color = Color(0.35, 0.6, 1.0).lerp(Color(0.2, 0.35, 0.9), prob / 100.0)
		bar.custom_minimum_size = Vector2(0, 6.0 + prob * 0.34)
		bar.size_flags_vertical = Control.SIZE_SHRINK_END
		col.add_child(bar)
		col.add_child(UI.label("%d" % int(round(float(h["temp"]))), 12,
			UI.INK, HORIZONTAL_ALIGNMENT_CENTER))
		col.add_child(UI.label("%d%%" % prob, 10,
			UI.INK_DIM if prob < 30 else UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
		rows.add_child(col)
	if shown == 0:
		return UI.dim("No forecast hours cached.")
	return UI.card([UI.dim("NEXT %d HOURS" % shown, 11), rows])


func _alert_card(a: Dictionary) -> Control:
	var sev := String(a.get("severity", ""))
	var color := UI.DANGER if sev == "Extreme" or sev == "Severe" else UI.WARN
	var head := UI.label("⚠ %s" % String(a.get("event", "Alert")), 17, color)
	var lines: Array = [head, UI.label(String(a.get("headline", "")), 14)]
	var detail := String(a.get("description", "")).strip_edges()
	if detail != "":
		var more := UI.dim(detail.substr(0, 400) + ("…" if detail.length() > 400 else ""), 13)
		more.visible = false
		var toggle := UI.button("Details", func() -> void: more.visible = not more.visible)
		lines.push_back(toggle)
		lines.push_back(more)
	return UI.card(lines, Color(0.20, 0.12, 0.12))


func _radar_block() -> Control:
	var lines: Array = [UI.dim("RADAR", 11)]
	if Wx.radar_frames.is_empty():
		lines.push_back(UI.dim("No radar frames. Needs a moment of data; the frames"
			+ " are then cached and animate offline until they go stale."))
		lines.push_back(UI.button("Fetch radar", func() -> void: Wx.refresh(true)))
		return UI.card(lines)
	var on := _map.radar_frame != ""
	lines.push_back(UI.row([
		UI.button("◀", func() -> void:
			Wx.step_radar(-1)
			_map.radar_frame = Wx.current_frame_id()
			_map.queue_redraw()),
		UI.label(Wx.frame_label(Wx.radar_index), 15),
		UI.button("▶", func() -> void:
			Wx.step_radar(1)
			_map.radar_frame = Wx.current_frame_id()
			_map.queue_redraw()),
		UI.spacer(),
		UI.button("Hide on map" if on else "Show on map", func() -> void:
			_map.radar_frame = "" if on else Wx.current_frame_id()
			_map.queue_redraw()
			_build(), not on),
	]))
	lines.push_back(UI.dim("%d frames, newest %s. Nowcast frames are RainViewer's"
		% [Wx.radar_frames.size(), Wx.frame_label(Wx.radar_frames.size() - 1)]
		+ " short-range forecast, not observation.", 12))
	return UI.card(lines)
