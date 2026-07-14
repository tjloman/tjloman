class_name HUD
extends CanvasLayer
## The godly dashboard: belief, prayer power, and alignment bars; population
## census; diet policy readout; gesture legend; hover tooltip; announcements;
## F1 help.

var village: Village
var divine_hand: DivineHand

var _belief_bar: ProgressBar
var _prayer_bar: ProgressBar
var _alignment_bar: ProgressBar
var _alignment_fill: StyleBoxFlat
var _alignment_label: Label
var _census_label: Label
var _diet_label: Label
var _hover_label: Label
var _message_label: Label
var _message_timer := 0.0
var _help_panel: PanelContainer


func _ready() -> void:
	layer = 5
	_build_bars()
	_build_legend()
	_build_hover_label()
	_build_message_label()
	_build_help_panel()

	GameState.prayer_power_changed.connect(_on_prayer_changed)
	GameState.alignment_changed.connect(_on_alignment_changed)
	GameState.announcement.connect(_on_announcement)
	if divine_hand != null:
		divine_hand.hover_info_changed.connect(_on_hover_info)


func _build_bars() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(16, 16)
	vbox.custom_minimum_size = Vector2(280, 0)
	add_child(vbox)

	vbox.add_child(_make_label("Belief"))
	_belief_bar = _make_bar(Color(1.0, 0.85, 0.3))
	vbox.add_child(_belief_bar)

	vbox.add_child(_make_label("Prayer Power"))
	_prayer_bar = _make_bar(Color(0.5, 0.7, 1.0))
	vbox.add_child(_prayer_bar)

	_alignment_label = _make_label("Alignment — Neutral")
	vbox.add_child(_alignment_label)
	_alignment_bar = _make_bar(Color(0.8, 0.8, 0.8))
	_alignment_bar.max_value = 200.0  # alignment -100..100 mapped to 0..200
	_alignment_bar.value = 100.0
	_alignment_fill = _alignment_bar.get_theme_stylebox("fill") as StyleBoxFlat
	vbox.add_child(_alignment_bar)

	_census_label = _make_label("")
	vbox.add_child(_census_label)

	_diet_label = _make_label("")
	vbox.add_child(_diet_label)


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	return l


func _make_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(280, 18)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _build_legend() -> void:
	var legend := Label.new()
	legend.text = "Hold RIGHT MOUSE and draw a gesture:   O  Food (20)" \
		+ "      /\\/\\  Rain (25)      |  Lightning (30)      —  Heal (15)"
	legend.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	legend.position.y -= 34
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_font_size_override("font_size", 15)
	legend.add_theme_color_override("font_color", Color(1, 1, 0.85, 0.9))
	add_child(legend)

	var hint := Label.new()
	hint.text = "F1 — controls"
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.position += Vector2(-120, 16)
	add_child(hint)


func _build_hover_label() -> void:
	_hover_label = Label.new()
	_hover_label.add_theme_font_size_override("font_size", 14)
	_hover_label.add_theme_color_override("font_color", Color.WHITE)
	_hover_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hover_label.add_theme_constant_override("shadow_offset_x", 1)
	_hover_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_hover_label)


func _build_message_label() -> void:
	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_message_label.position.y -= 80
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 18)
	_message_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_message_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(_message_label)


func _build_help_panel() -> void:
	_help_panel = PanelContainer.new()
	_help_panel.set_anchors_preset(Control.PRESET_CENTER)
	_help_panel.visible = false
	var help := Label.new()
	help.text = """DIVINE CONTROLS

Left mouse (on land) ....... grab & drag the world
Left mouse (on things) ..... pick up food, rocks, sheep, villagers
Release while moving ....... throw! (hard landings hurt — and stain your soul)
Right mouse (hold) ......... draw a miracle gesture
Mouse wheel ................ zoom
Middle mouse (drag) ........ rotate camera
WASD / arrows .............. pan camera
Q / E ...................... rotate camera
1 / 2 / 3 / 4 .............. village diet: Vegan / Omnivore / Carnivore / Cannibal
F1 ......................... toggle this help

MIRACLES (drawn with right mouse held)
Circle ..................... Food falls from the sky (20)
Zigzag ..................... Rain — crops grow 4x (25)
Vertical stroke ............ Lightning — LETHAL up close (30)
Horizontal stroke .......... Healing wave (15)

THE WORLD
Villagers age, marry in worship, bear children (9 months), and die.
The dead leave corpses. What happens to corpses is... policy.
Sheep are meat. Cannibal villages have other sources.
Your alignment colors your hand and the influence ring.
Your creature has its OWN morality — it learns from watching you.
A monstrous creature will eat your villagers. A gentle one farms."""
	help.add_theme_font_size_override("font_size", 15)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	margin.add_child(help)
	_help_panel.add_child(margin)
	add_child(_help_panel)


func _process(delta: float) -> void:
	if village != null:
		_belief_bar.value = village.belief
		var adults := 0
		var children := 0
		for v in get_tree().get_nodes_in_group("villagers"):
			if (v as Villager).is_adult():
				adults += 1
			else:
				children += 1
		_census_label.text = "Souls: %d adults, %d children — Year %d" \
			% [adults, children, int(GameState.game_years)]
		_diet_label.text = "Diet [1-4]: %s" % village.diet_name()
	_hover_label.position = _hover_label.get_viewport().get_mouse_position() + Vector2(18, 18)

	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message_label.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help_panel.visible = not _help_panel.visible


func _on_prayer_changed(value: float, max_value: float) -> void:
	_prayer_bar.max_value = max_value
	_prayer_bar.value = value


func _on_alignment_changed(value: float) -> void:
	_alignment_bar.value = value + 100.0
	_alignment_label.text = "Alignment — %s" % GameState.alignment_word()
	if _alignment_fill != null:
		_alignment_fill.bg_color = GameState.alignment_color()


func _on_announcement(text: String) -> void:
	_message_label.text = text
	_message_timer = 5.0


func _on_hover_info(text: String) -> void:
	_hover_label.text = text
