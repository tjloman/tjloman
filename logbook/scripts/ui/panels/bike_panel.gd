class_name BikePanel extends Sheet
## The rig: a Senada Saber and the powered cart behind it.
##
## The top of this panel is what you look at on the road — total energy left,
## honest range, what the sun is giving you, whether a motor is cooking. The
## bottom is what you use once, in a driveway, to teach the app which
## Bluetooth device is which machine.
##
## Every pack gets its own card. Averaging a small bike battery against a large
## cart battery would hide the one that runs out first, which is the only one
## that matters.

var _tick := 0.0


func _init() -> void:
	super("Rig")


func _ready() -> void:
	_build()
	Bike.connection_changed.connect(func(_c: bool) -> void: _build())
	Bike.explored.connect(func(_a: String, _s: Array) -> void: _build())
	Bike.devices_changed.connect(_build)


func _process(delta: float) -> void:
	# Live numbers, but only every four seconds: this panel is often open while
	# riding and every rebuild is a handful of allocations.
	_tick -= delta
	if _tick <= 0.0:
		_tick = 4.0
		if Bike.any_connected():
			_build()


func _build() -> void:
	clear()
	if Bike.any_connected():
		body.add_child(_rig_card())
		body.add_child(_energy_card())
		for link in Bike.ordered_links():
			if link.connected:
				body.add_child(_pack_card(link))
	else:
		body.add_child(UI.card([
			UI.label("Nothing connected", 17, UI.WARN),
			UI.dim("The app reconnects to remembered machines on its own whenever"
				+ " they are awake and in range, so this is normally a one-time job."),
			UI.button("Scan", func() -> void: Bike.scan(), true),
		]))
	_build_scan_list()
	body.add_child(UI.separator())
	_build_setup()


## The whole rig as one line of numbers: what is left, and how far it goes.
func _rig_card() -> Control:
	var rig := Bike.aggregate()
	var soc := float(rig["soc"])
	var color := UI.GOOD
	if soc <= float(Cfg.get_i("low_battery_warn_pct")):
		color = UI.DANGER
	elif soc <= 40.0:
		color = UI.WARN
	var per_unit := Bike.consumption_per_unit()
	var unit := "km" if Cfg.is_metric() else "mi"
	return UI.card([
		UI.row([
			UI.stat("charge", "%d%%" % int(soc), color),
			UI.stat("energy", "%d Wh" % int(float(rig["wh_left"]))),
			UI.stat("range", Cfg.dist(Bike.range_estimate_m())),
		], 14),
		UI.row([
			UI.stat("draw", "%d W" % int(absf(float(rig["watts"]))), UI.INK_DIM),
			UI.stat("per %s" % unit,
				"%.1f Wh" % per_unit if per_unit > 0.0 else "—", UI.INK_DIM),
			UI.stat("packs", "%d" % int(rig["packs"]), UI.INK_DIM),
		], 14),
		UI.dim("Range is measured, not claimed: net watt-hours per %s so far —"
			% unit + " solar and regen already subtracted — applied to what is"
			+ " left in every pack that can turn a wheel."),
	])


## The day as an energy ledger. On a good day down a mountain in sunshine the
## returns can outrun the draw, and this is where you see that.
func _energy_card() -> Control:
	var rig := Bike.aggregate()
	var lines: Array = [
		UI.dim("TODAY", 11),
		UI.row([
			UI.stat("used", "%d Wh" % int(Bike.wh_out)),
			UI.stat("solar", "%d Wh" % int(Bike.wh_solar), UI.GOOD),
			UI.stat("regen", "%d Wh" % int(Bike.wh_regen), UI.GOOD),
		], 14),
	]
	var solar_w := float(rig.get("solar_watts", 0.0))
	if rig.has("solar_watts"):
		var state := String(rig.get("solar_state", ""))
		lines.push_back(UI.label("☀ %d W now%s" % [int(solar_w),
			("  ·  " + state) if state != "" else ""], 15,
			UI.GOOD if solar_w > 20.0 else UI.INK_DIM))
	if bool(rig.get("regenerating", false)):
		lines.push_back(UI.label("↻ regenerating — level %d"
			% int(rig.get("regen_level", 0)), 15, UI.GOOD))
	var net := Bike.wh_out - Bike.wh_regen - Bike.wh_solar
	if net < 0.0:
		lines.push_back(UI.label("Net gain today: %d Wh more aboard than you started with"
			% int(-net), 14, UI.GOOD))
	return UI.card(lines)


func _pack_card(link) -> Control:
	var s: Dictionary = link.state
	var soc := float(s.get("soc", 0.0))
	var color := UI.GOOD
	if soc <= float(Cfg.get_i("low_battery_warn_pct")):
		color = UI.DANGER
	elif soc <= 40.0:
		color = UI.WARN
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = soc
	bar.custom_minimum_size.y = 16
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", UI.panel_style(color, 6))
	bar.add_theme_stylebox_override("background", UI.panel_style(UI.BG_SUNK, 6))

	var lines: Array = [
		UI.row([
			UI.label("%s  ·  %s" % [link.label(), link.role], 16),
			UI.spacer(),
			UI.dim("%d%%  %.0f Wh" % [int(soc), link.wh_remaining()], 13),
		]),
		bar,
		UI.row([
			UI.stat("volts", "%.1f V" % float(s.get("volts", 0.0)), UI.INK_DIM),
			UI.stat("amps", "%.1f A" % float(s.get("amps", 0.0)), UI.INK_DIM),
			UI.stat("watts", "%d W" % int(absf(float(s.get("watts", 0.0)))), UI.INK_DIM),
		], 14),
	]
	if s.has("motors"):
		lines.push_back(_motor_row(s))
	if s.has("temp_c"):
		var t := float(s["temp_c"])
		lines.push_back(UI.row([
			UI.stat("pack temp", "%.0f °C" % t, UI.WARN if t > 45.0 else UI.INK_DIM),
			UI.stat("cycles", str(int(s.get("cycles", 0))), UI.INK_DIM),
			UI.stat("in / out", "%d / %d Wh" % [int(link.wh_in), int(link.wh_out)], UI.INK_DIM),
		], 14))
	if String(s.get("fault", "")) != "":
		lines.push_back(UI.label("⚠ %s" % String(s["fault"]), 15, UI.DANGER))
	if s.has("cells"):
		lines.push_back(_cell_bars(s))
	if link.role == Bike.ROLE_CART:
		lines.push_back(_cart_controls(link))
	lines.push_back(UI.dim("%s · updated %s" % [
		link.profile.profile_name() if link.profile != null else "no profile",
		UI.ago(Time.get_unix_time_from_system() - link.last_update)], 12))
	return UI.card(lines)


## Two motors, side by side. Seeing one run hotter than the other is the
## earliest sign of a dragging brake or a wheel that is not tracking straight.
func _motor_row(s: Dictionary) -> Control:
	var motors: Array = s["motors"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	for i in motors.size():
		var m: Dictionary = motors[i]
		var temp := float(m.get("temp_c", 0.0))
		var color := UI.INK_DIM
		if temp > 85.0:
			color = UI.DANGER
		elif temp > 70.0:
			color = UI.WARN
		var amps := float(m.get("amps", 0.0))
		row.add_child(UI.stat("motor %d" % (i + 1),
			"%.1f A  %d°" % [amps, int(temp)], color))
	if bool(s.get("derating", false)):
		row.add_child(UI.stat("", "derating", UI.WARN))
	return row


func _cart_controls(link) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.button("Lights", func() -> void:
		CartProfile.command(link, CartProfile.CMD_LIGHTS, 1)))
	for level in [0, 3, 5]:
		var b := UI.button("regen %d" % level, func() -> void:
			CartProfile.command(link, CartProfile.CMD_REGEN, level))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return row


## Per-cell voltages. A pack drifting apart shows here months before it
## strands you: one short bar among sixteen even ones.
func _cell_bars(s: Dictionary) -> Control:
	var cells: PackedFloat32Array = s["cells"]
	var lo := float(s.get("cell_min", 3.0))
	var hi := float(s.get("cell_max", 4.2))
	var spread := float(s.get("cell_spread", 0.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size.y = 54
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
		var role := Bike.guess_role(name)
		var b := UI.button("%s   %s   %d dBm   → %s" % [name, addr,
			int(d.get("rssi", 0)), role], func() -> void: Bike.connect_to(addr, name, role))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.add_child(b)


func _build_setup() -> void:
	body.add_child(UI.dim("SETUP", 11))
	body.add_child(UI.toggle("Bluetooth enabled", "ble_enabled"))
	for link in Bike.ordered_links():
		body.add_child(_link_setup(link))
	body.add_child(UI.slider("battery_wh", 200.0, 2000.0, 10.0, "%.0f Wh"))
	body.add_child(UI.slider("cart_battery_wh", 200.0, 8000.0, 50.0, "%.0f Wh"))
	body.add_child(UI.slider("solar_watts_peak", 50.0, 2000.0, 10.0, "%.0f W"))
	body.add_child(UI.slider("assumed_wh_per_mile", 5.0, 60.0, 0.5, "%.1f Wh"))
	body.add_child(UI.slider("low_battery_warn_pct", 5.0, 60.0, 1.0, "%.0f%%"))
	body.add_child(UI.slider("ble_sample_minutes", 1.0, 30.0, 1.0, "%.0f min"))
	body.add_child(UI.dim("Pack sizes are only used until the packs report their own"
		+ " capacity, and as the fallback when one does not."))
	for link in Bike.ordered_links():
		if not link.services.is_empty():
			body.add_child(_gatt_list(link))


func _link_setup(link) -> Control:
	var roles := [Bike.ROLE_BIKE, Bike.ROLE_CART, Bike.ROLE_HOUSE]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for r: String in roles:
		var b := UI.button(r, func() -> void:
			Bike.set_role(link.address, r)
			_build())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if link.role == r:
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.ACCENT.darkened(0.3), 8))
		row.add_child(b)
	return UI.card([
		UI.row([
			UI.label(link.label(), 15),
			UI.spacer(),
			UI.dim(link.address, 11),
		]),
		row,
		UI.dim("A house battery is excluded from range: it powers the phone and the"
			+ " lights, not the wheels.", 12),
		UI.button("Forget", func() -> void:
			Bike.forget(link.address)
			_build()),
	], UI.BG_SUNK)


## Everything a device exposes. When a machine speaks something none of the
## built-in profiles recognize, this is the list a new profile needs.
func _gatt_list(link) -> Control:
	var lines: Array = [UI.dim("WHAT %s EXPOSES" % link.label().to_upper(), 11)]
	for s in link.services:
		var d: Dictionary = s
		lines.push_back(UI.label(BleProfile.short_uuid(String(d.get("service", ""))), 14, UI.ACCENT))
		for c in d.get("characteristics", []):
			lines.push_back(UI.dim("   " + BleProfile.short_uuid(String(c)), 12))
	return UI.card(lines, UI.BG_SUNK)
