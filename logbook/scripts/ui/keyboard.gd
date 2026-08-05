class_name OnscreenKeyboard extends PanelContainer
## An in-app keyboard.
##
## Godot can raise the OS keyboard, but on a phone that means the app is
## resized, the map is shoved off screen, and the layout jumps around every
## time you tap the text box. This one is part of the app: fixed height, no
## reflow, big keys, and it works in landscape with a glove on.
##
## It is also the fallback rather than the default. If a bluetooth keyboard is
## connected — the good way to write a real entry at the end of a day — the
## first physical keypress hides this one automatically.

signal typed(text: String)
signal backspace
signal newline
signal dismissed

const ROWS_LOWER := [
	"qwertyuiop",
	"asdfghjkl",
	"zxcvbnm",
]
const ROWS_SYMBOL := [
	"1234567890",
	"-/:;()$&@\"",
	".,?!'",
]

var shifted := false
var symbols := false

var _keys: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", UI.panel_style(Color(0.08, 0.09, 0.11, 0.97), 12))
	_keys = VBoxContainer.new()
	_keys.add_theme_constant_override("separation", 5)
	add_child(_keys)
	_rebuild()


func _rebuild() -> void:
	for c in _keys.get_children():
		c.queue_free()
	var rows: Array = ROWS_SYMBOL if symbols else ROWS_LOWER
	for r in rows.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		# Stagger the middle rows the way a real keyboard does, so muscle
		# memory from a phone keyboard mostly carries over.
		if not symbols and r > 0:
			row.add_child(UI.spacer(float(r) * 10.0))
		for ch in String(rows[r]):
			row.add_child(_key(ch))
		if not symbols and r > 0:
			row.add_child(UI.spacer(float(r) * 10.0))
		if r == rows.size() - 1:
			row.add_child(_special("⌫", func() -> void: backspace.emit(), 1.6))
		_keys.add_child(row)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 5)
	bottom.add_child(_special("⇧" if not symbols else "abc", func() -> void:
		if symbols:
			symbols = false
		else:
			shifted = not shifted
		_rebuild(), 1.4))
	bottom.add_child(_special("?123" if not symbols else "•", func() -> void:
		symbols = not symbols
		_rebuild(), 1.4))
	var space := _special("space", func() -> void: typed.emit(" "), 4.0)
	bottom.add_child(space)
	bottom.add_child(_special("⏎", func() -> void: newline.emit(), 1.4))
	bottom.add_child(_special("▼", func() -> void: dismissed.emit(), 1.2))
	_keys.add_child(bottom)


func _key(ch: String) -> Button:
	var text := ch.to_upper() if shifted and not symbols else ch
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", UI.fs(19))
	b.pressed.connect(func() -> void:
		typed.emit(text)
		# Shift is one-shot, like every phone keyboard since 2007.
		if shifted:
			shifted = false
			_rebuild())
	return b


func _special(text: String, action: Callable, weight: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = weight
	b.add_theme_font_size_override("font_size", UI.fs(15))
	b.add_theme_stylebox_override("normal", UI.panel_style(Color(0.17, 0.18, 0.22), 8))
	b.pressed.connect(action)
	return b


## Apply a key press to a TextEdit — the wiring every caller would otherwise
## write itself.
func attach(edit: TextEdit) -> void:
	typed.connect(func(t: String) -> void: edit.insert_text_at_caret(t))
	backspace.connect(func() -> void: edit.backspace())
	newline.connect(func() -> void: edit.insert_text_at_caret("\n"))
