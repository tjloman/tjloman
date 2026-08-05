class_name Sheet extends PanelContainer
## A panel that slides up over the map: a title bar, a scrolling body, and a
## close affordance. Every screen that is not the map is one of these.
##
## Sheets never cover the whole screen — the top strip stays visible, because
## the numbers you glance at while riding (speed, battery, next turn) should
## never disappear behind a menu.

signal closed

const SLIDE_S := 0.18

var body: VBoxContainer
var _title: Label
var _tween: Tween


## The title is a required argument on purpose. If it had a default, GDScript
## would consider this constructor callable with no arguments and run it
## implicitly before each subclass's `_init` — and then again at the explicit
## `super(...)`, building the whole panel twice.
func _init(title_text: String) -> void:
	add_theme_stylebox_override("panel", UI.panel_style(UI.bg(), 16))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)

	var bar := HBoxContainer.new()
	_title = UI.title(title_text)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	bar.add_child(UI.icon_button("✕", close, "Close"))
	outer.add_child(bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)


func set_title(text: String) -> void:
	_title.text = text


func open() -> void:
	visible = true
	modulate.a = 0.0
	var from := position + Vector2(0, 40)
	position = from
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, SLIDE_S)
	_tween.tween_property(self, "position", from - Vector2(0, 40), SLIDE_S) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	closed.emit()
	queue_free()


func clear() -> void:
	for c in body.get_children():
		c.queue_free()


## Rebuild the body from scratch. Panels that show live data call this on a
## slow timer rather than diffing widgets — a dozen labels is nothing, and the
## code stays readable.
func rebuild(builder: Callable) -> void:
	clear()
	builder.call(body)
