class_name UI
## Widget helpers and the app's one Theme, built in code.
##
## There is no .tres theme and no hand-placed scene for the panels: this app
## is used at arm's length, in sunlight, sometimes with gloves on, and the
## sizes that follow from that (44px minimum touch targets, high contrast, a
## night palette) are easier to keep honest as constants than as a tree of
## editor resources.

const RADIUS := 10
const PAD := 12
const TOUCH := 48          ## Minimum tappable height. Gloves are a real input device.

const INK := Color(0.93, 0.94, 0.96)
const INK_DIM := Color(0.66, 0.68, 0.72)
const BG := Color(0.09, 0.10, 0.12)
const BG_RAISED := Color(0.14, 0.15, 0.18)
const BG_SUNK := Color(0.06, 0.06, 0.08)
const ACCENT := Color(0.35, 0.72, 1.0)
const WARN := Color(1.0, 0.72, 0.25)
const DANGER := Color(1.0, 0.42, 0.40)
const GOOD := Color(0.45, 0.88, 0.55)

## Night mode is not a nicety on a bike: a white panel at 2am blinds you for
## the next thirty seconds of road.
const NIGHT_INK := Color(0.95, 0.72, 0.60)
const NIGHT_BG := Color(0.06, 0.03, 0.03)


static func ink() -> Color:
	return NIGHT_INK if Cfg.get_b("night_mode") else INK


static func bg() -> Color:
	return NIGHT_BG if Cfg.get_b("night_mode") else BG


static func fs(base: int) -> int:
	return int(round(base * Cfg.get_f("font_scale")))


static func panel_style(color: Color, radius: int = RADIUS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left = PAD
	s.content_margin_right = PAD
	s.content_margin_top = PAD
	s.content_margin_bottom = PAD
	return s


static func build_theme() -> Theme:
	var t := Theme.new()
	var normal := panel_style(BG_RAISED, 8)
	var hover := panel_style(BG_RAISED.lightened(0.08), 8)
	var pressed := panel_style(ACCENT.darkened(0.45), 8)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := normal
		match state:
			"hover": style = hover
			"pressed": style = pressed
			"disabled": style = panel_style(BG_RAISED.darkened(0.3), 8)
			"focus": style = panel_style(BG_RAISED, 8)
		t.set_stylebox(state, "Button", style)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", fs(16))
	t.set_constant("h_separation", "Button", 8)

	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", fs(15))

	t.set_stylebox("panel", "PanelContainer", panel_style(BG))
	t.set_stylebox("normal", "LineEdit", panel_style(BG_SUNK, 8))
	t.set_stylebox("focus", "LineEdit", panel_style(BG_SUNK.lightened(0.06), 8))
	t.set_color("font_color", "LineEdit", INK)
	t.set_font_size("font_size", "LineEdit", fs(16))
	t.set_stylebox("normal", "TextEdit", panel_style(BG_SUNK, 8))
	t.set_stylebox("focus", "TextEdit", panel_style(BG_SUNK, 8))
	t.set_color("font_color", "TextEdit", INK)
	t.set_font_size("font_size", "TextEdit", fs(17))
	t.set_color("font_color", "CheckButton", INK)
	t.set_font_size("font_size", "CheckButton", fs(15))
	t.set_font_size("font_size", "HSlider", fs(14))
	return t


# ------------------------------------------------------------------ widgets


static func label(text: String, size: int = 15, color: Color = INK,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String) -> Label:
	return label(text, 20, ink())


static func dim(text: String, size: int = 13) -> Label:
	return label(text, size, INK_DIM)


static func button(text: String, on_press: Callable = Callable(),
		accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = TOUCH
	b.add_theme_font_size_override("font_size", fs(16))
	if accent:
		b.add_theme_stylebox_override("normal", panel_style(ACCENT.darkened(0.25), 8))
		b.add_theme_stylebox_override("hover", panel_style(ACCENT.darkened(0.1), 8))
		b.add_theme_color_override("font_color", Color.WHITE)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func icon_button(glyph: String, on_press: Callable, tip: String = "") -> Button:
	var b := button(glyph, on_press)
	b.custom_minimum_size = Vector2(TOUCH, TOUCH)
	b.add_theme_font_size_override("font_size", fs(20))
	b.tooltip_text = tip
	return b


static func toggle(text: String, key: String, on_change: Callable = Callable()) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = Cfg.get_b(key)
	c.custom_minimum_size.y = TOUCH
	c.add_theme_font_size_override("font_size", fs(15))
	c.toggled.connect(func(v: bool) -> void:
		Cfg.set_value(key, v)
		if on_change.is_valid():
			on_change.call(v))
	return c


static func slider(key: String, lo: float, hi: float, step: float,
		fmt: String = "%.0f") -> Control:
	var box := VBoxContainer.new()
	var head := HBoxContainer.new()
	var name_label := label(key.capitalize(), 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := label(fmt % Cfg.get_f(key), 14, INK_DIM)
	head.add_child(name_label)
	head.add_child(value_label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = Cfg.get_f(key)
	s.custom_minimum_size.y = 34
	s.value_changed.connect(func(v: float) -> void:
		Cfg.set_value(key, v)
		value_label.text = fmt % v)
	box.add_child(head)
	box.add_child(s)
	return box


static func text_field(key: String, placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = Cfg.get_s(key)
	e.placeholder_text = placeholder
	e.custom_minimum_size.y = TOUCH
	e.text_changed.connect(func(v: String) -> void: Cfg.set_value(key, v))
	return e


static func row(children: Array, separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	for c in children:
		h.add_child(c)
	return h


static func column(children: Array, separation: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	for c in children:
		v.add_child(c)
	return v


static func spacer(min_size: float = 0.0, expand: bool = true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(min_size, min_size)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func separator() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 10)
	return s


static func card(children: Array, color: Color = BG_RAISED) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(color))
	p.add_child(column(children, 6))
	return p


## A label pair used all over the panels: a small caption above a big value.
static func stat(caption: String, value: String, color: Color = INK) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(dim(caption.to_upper(), 11))
	v.add_child(label(value, 22, color))
	return v


# -------------------------------------------------------------- formatting


static func clock(t: float) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(int(t) + bias * 60)
	if Cfg.get_b("clock_24h"):
		return "%02d:%02d" % [int(d["hour"]), int(d["minute"])]
	var h := int(d["hour"]) % 12
	if h == 0:
		h = 12
	return "%d:%02d %s" % [h, int(d["minute"]), "am" if int(d["hour"]) < 12 else "pm"]


static func date_line(t: float) -> String:
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(int(t) + bias * 60)
	return "%s %d" % [MONTHS[clampi(int(d["month"]) - 1, 0, 11)], int(d["day"])]


static func ago(seconds: float) -> String:
	if seconds < 60.0:
		return "just now"
	if seconds < 3600.0:
		return "%dm ago" % int(seconds / 60.0)
	if seconds < 86400.0:
		return "%dh ago" % int(seconds / 3600.0)
	return "%dd ago" % int(seconds / 86400.0)


static func bytes_human(n: int) -> String:
	if n < 1024:
		return "%d B" % n
	if n < 1048576:
		return "%.0f KB" % (n / 1024.0)
	if n < 1073741824:
		return "%.1f MB" % (n / 1048576.0)
	return "%.2f GB" % (n / 1073741824.0)
