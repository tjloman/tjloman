class_name BikePanel extends Sheet
## The ebike: the battery, and the plumbing for getting at it.
##
## The top of this panel is what you look at on the road — charge, volts,
## amps, and honest range. The bottom is what you use once, in a driveway,
## to teach the app which Bluetooth device is the bike and what it speaks.

var _tick := 0.0


func _init() -> void:
	super("Bike")


func _ready() -> void:
	_build()
	Bike.connection_changed.connect(func(_c: bool) -> void: _build())
	Bike.explored.connect(func(_s: Array) -> void: _build())
	Bike.devices_changed.connect(_build)


func _process(delta: float) -> void:
	# Live numbers, but only four times a second: this panel is often open
	# while riding and every rebuild is a handful of allocations.
	_tick -= delta
	if _tick <= 0.0:
		_tick = 4.0
		if Bike.connected:
			_build()


func _build() -> void:
	clear()
	if Bike.connected:
		body.add_child(_battery_card())
		body.add_child(_detail_card())
	else:
		body.add_child(UI.card([
			UI.label("Not connected", 17, UI.WARN),
			UI.dim("The app reconnects on its own whenever the bike is awake and in"
				+ " range, so this is normally only needed once."),
			UI.button("Scan for the bike", func() -> void: Bike.scan(), true),
		]))
		_build_scan_list()
	body.add_child(UI.separator())
	_build_setup()


func _battery_card() -> Control:
	var s := Bike.state
	var soc := float(s.get("soc", 0.0))
	var color := UI.GOOD
	if soc <= float(Cfg.get_i("low_battery_warn_pct")):
		color = UI.DANGER
	elif soc <= 40.0:
		color = UI.WARN
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = soc
	bar.custom_minimum_size.y = 18
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", UI.panel_style(color, 6))
	bar.add_theme_stylebox_override("background", UI.panel_style(UI.BG_SUNK, 6))
	return UI.card([
		UI.row([
			UI.stat("charge", "%d%%" % int(soc), color),
			UI.stat("range left", Cfg.dist(Bike.range_estimate_m())),
			UI.stat("pack", "%.1f V" % float(s.get("volts", 0.0)), UI.INK_DIM),
		], 14),
		bar,
		UI.dim("Range is measured, not claimed: watt-hours actually pulled per mile"
			+ " on this trip, applied to what is left in the pack."),
	])


func _detail_card() -> Control:
	var s := Bike.state
	var lines: Array = [UI.dim("LIVE", 11)]
	lines.push_back(UI.row([
		UI.stat("current", "%.1f A" % float(s.get("amps", 0.0)), UI.INK_DIM),
		UI.stat("power", "%d W" % int(absf(float(s.get("watts", 0.0)))), UI.INK_DIM),
		UI.stat("used", "%.0f Wh" % float(s.get("wh_used", 0.0)), UI.INK_DIM),
	], 14))
	if s.has("temp_c"):
		var t := float(s["temp_c"])
		lines.push_back(UI.row([
			UI.stat("pack temp", "%.0f °C" % t, UI.WARN if t > 45.0 else UI.INK_DIM),
			UI.stat("cycles", str(int(s.get("cycles", 0))), UI.INK_DIM),
			UI.stat("cells", str(int(s.get("cell_count", 0))), UI.INK_DIM),
		], 14))
	if String(s.get("fault", "")) != "":
		lines.push_back(UI.label("⚠ %s" % String(s["fault"]), 15, UI.DANGER))
	if s.has("cells"):
		lines.push_back(_cell_bars(s))
	if Bike.last_update > 0.0:
		lines.push_back(UI.dim("updated %s · %s"
			% [UI.ago(Time.get_unix_time_from_system() - Bike.last_update),
			Bike.profile.profile_name() if Bike.profile != null else "no profile"], 12))
	return UI.card(lines)


## Per-cell voltages. A pack that is drifting apart shows here months before
## it strands you: one short bar among sixteen even ones.
func _cell_bars(s: Dictionary) -> Control:
	var cells: PackedFloat32Array = s["cells"]
	var lo := float(s.get("cell_min", 3.0))
	var hi := float(s.get("cell_max", 4.2))
	var spread := float(s.get("cell_spread", 0.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size.y = 60
	for v in cells:
		var col := ColorRect.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var f := 0.5 if hi <= lo else clampf((v - lo) / (hi - lo), 0.0, 1.0)
		col.color = Color(0.9, 0.35, 0.35).lerp(Color(0.4, 0.9, 0.5), f)
		col.tooltip_text = "%.3f V" % v
		row.add_child(col)
	return UI.card([
		UI.dim("CELLS  %.3f–%.3f V  ·  spread %.0f mV" % [lo, hi, spread * 1000.0], 11),
		row,
	], UI.BG_SUNK)


func _build_scan_list() -> void:
	if Bike.found.is_empty():
		return
	body.add_child(UI.dim("FOUND", 11))
	for d in Bike.found:
		var name := String(d.get("name", "(unnamed)"))
		var addr := String(d.get("address", ""))
		var b := UI.button("%s   %s   %d dBm" % [name, addr, int(d.get("rssi", 0))],
			func() -> void: Bike.connect_to(addr, name))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.add_child(b)


func _build_setup() -> void:
	body.add_child(UI.dim("SETUP", 11))
	body.add_child(UI.toggle("Bluetooth enabled", "ble_enabled"))
	body.add_child(UI.slider("battery_wh", 200.0, 2000.0, 10.0, "%.0f Wh"))
	body.add_child(UI.slider("low_battery_warn_pct", 5.0, 60.0, 1.0, "%.0f%%"))
	body.add_child(UI.slider("ble_sample_minutes", 1.0, 30.0, 1.0, "%.0f min"))

	var profiles := ["auto", "jbd", "battery", "cycling"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for p: String in profiles:
		var b := UI.button(p, func() -> void:
			Cfg.set_value("ble_profile", p)
			_build())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if Cfg.get_s("ble_profile") == p:
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.ACCENT.darkened(0.3), 8))
		row.add_child(b)
	body.add_child(UI.dim("Protocol — leave on auto unless it guesses wrong", 12))
	body.add_child(row)

	if Cfg.get_s("ble_device") != "":
		body.add_child(UI.button("Forget %s" % Cfg.get_s("ble_device"), func() -> void:
			Bike.forget()
			_build()))
	if not Bike.services.is_empty():
		body.add_child(_gatt_list())


## Everything the device exposes. When a bike speaks something none of the
## built-in profiles recognize, this is the list to send me — the UUIDs here
## are exactly what a new profile needs.
func _gatt_list() -> Control:
	var lines: Array = [UI.dim("WHAT THIS DEVICE EXPOSES", 11)]
	for s in Bike.services:
		var d: Dictionary = s
		lines.push_back(UI.label(BleProfile.short_uuid(String(d.get("service", ""))), 14, UI.ACCENT))
		for c in d.get("characteristics", []):
			lines.push_back(UI.dim("   " + BleProfile.short_uuid(String(c)), 12))
	return UI.card(lines, UI.BG_SUNK)
