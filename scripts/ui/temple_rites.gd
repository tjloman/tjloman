class_name TempleRites
extends ScrollContainer
## THE RITES WALL: what the game does, and what the machine does about it.
##
## Everything here was previously an F-key or nothing at all. The temple is the
## first place in this game where a setting can live without a button appearing
## on the HUD, which is the entire reason the door exists.
##
## THE ONE SETTING THAT IS NOT LIKE THE OTHERS is the population ceiling.
## Shadows, draw distance and render scale are fixed costs paid once a frame
## and turning them down buys a fixed amount back. Villagers are a cost that
## COMPOUNDS: a thriving world breeds more of them, each one thinks, walks,
## eats and is drawn, and a long session on a phone can pass a thousand souls
## without anybody noticing until the frame rate goes. It is the only knob here
## that bounds something growing.
##
## Nobody is ever culled to meet it. Births stop at the ceiling and resume
## under it, so a town that reaches it simply stops growing — which is what a
## town short of land does anyway, and reads as the world being full rather
## than as a setting having been changed.

## Kept beside the graphics override rather than in the save, because these are
## facts about the DEVICE and must not travel with a creature to a machine that
## cannot hold them.

## The ceilings offered, and what each is for. A phone wants the low end; a
## desktop that has been running four hours wants the high one.
const CEILINGS: Array[Array] = [
	[0, "No ceiling", "Let it grow. Desktop, and be ready to watch the frame."],
	[900, "900 souls", "Generous. A strong desktop over a long evening."],
	[500, "500 souls", "The default shape of a full world."],
	[260, "260 souls", "A phone or a tablet, kept cool."],
]

var _body: VBoxContainer
var _tier_row: HBoxContainer
var _cap_row: VBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	add_child(_body)
	_load()
	_fill()


## WHAT THE PLAYER CHOSE, which GameState has already read at startup — this
## screen is built when somebody walks into this room, and settings that only
## take effect when you go and LOOK at them are not settings.
func _load() -> void:
	GameState.load_settings()


func _save() -> void:
	GameState.save_settings()


func _fill() -> void:
	_heading("Graphics")
	_note("Lights, shadows, draw distance and how many pixels the world is "
		+ "drawn at. Some of it applies the moment you choose; the streaming "
		+ "radius and the water wait for the next world.")
	_tier_row = HBoxContainer.new()
	_tier_row.add_theme_constant_override("separation", 6)
	for t in Quality.Tier.values():
		var pick := Button.new()
		pick.text = "  %s  " % String(Quality.Tier.keys()[t]).capitalize()
		pick.toggle_mode = true
		pick.pressed.connect(_choose_tier.bind(t))
		_tier_row.add_child(pick)
	_body.add_child(_tier_row)
	_mark_tier()
	_line("Detected for this machine", Quality.heat_word())
	_line("Frame, as measured", "%.1f ms" % Quality.frame_ms())

	_heading("How many people the world may hold")
	_note("The only setting here that bounds something GROWING. A thriving "
		+ "world breeds more villagers and every one of them thinks, walks, "
		+ "eats and is drawn. Births stop at the ceiling and resume under it — "
		+ "nobody is ever culled to meet it.")
	_cap_row = VBoxContainer.new()
	_cap_row.add_theme_constant_override("separation", 3)
	for row: Array in CEILINGS:
		var pick := Button.new()
		pick.text = "  %s — %s" % [String(row[1]), String(row[2])]
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.toggle_mode = true
		pick.pressed.connect(_choose_cap.bind(int(row[0])))
		_cap_row.add_child(pick)
	_body.add_child(_cap_row)
	_mark_cap()
	_line("Souls alive now", str(get_tree().get_node_count_in_group("villagers")))

	_heading("Sound")
	var loud := HSlider.new()
	loud.min_value = 0.0
	loud.max_value = 1.0
	loud.step = 0.05
	loud.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	loud.custom_minimum_size = Vector2(160.0, 0.0)
	loud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loud.value_changed.connect(_set_loud)
	_body.add_child(loud)

	_heading("The lushness")
	_note("Bees, crickets, squirrels and moths in the wood around you. They "
		+ "cost a little and are worth it; switching them off empties the "
		+ "trees within a second, with no reload either way.")
	var cel := CheckBox.new()
	cel.text = "Cel shading"
	cel.button_pressed = GameState.cel_shading
	cel.toggled.connect(_set_cel)
	_body.add_child(cel)
	_note("The light cut into bands instead of falling off smoothly, the way a "
		+ "painted picture book does it. Costs nothing either way, applies the "
		+ "moment you tick it, and touches nothing that was drawn unlit on "
		+ "purpose.")
	var friends := CheckBox.new()
	friends.text = "Living wood"
	friends.button_pressed = GameState.tree_friends
	friends.toggled.connect(_set_friends)
	_body.add_child(friends)


func _choose_tier(which: int) -> void:
	Quality.choose(which as Quality.Tier)
	_mark_tier()


func _mark_tier() -> void:
	for i in _tier_row.get_child_count():
		(_tier_row.get_child(i) as Button).set_pressed_no_signal(i == Quality.tier)


func _choose_cap(to: int) -> void:
	GameState.folk_cap = to
	_mark_cap()
	_save()


func _mark_cap() -> void:
	for i in CEILINGS.size():
		var on: bool = int(CEILINGS[i][0]) == GameState.folk_cap
		(_cap_row.get_child(i) as Button).set_pressed_no_signal(on)


func _set_loud(to: float) -> void:
	# Silence is -inf decibels, which linear_to_db returns correctly and which
	# the bus takes; the clamp is only against a slider that went negative.
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(to, 0.0)))
	_save()


func _set_cel(on: bool) -> void:
	GameState.cel_shading = on
	_save()


func _set_friends(on: bool) -> void:
	GameState.tree_friends = on


func _heading(text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 8.0)
	_body.add_child(gap)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	_body.add_child(label)


func _line(what: String, value: String) -> void:
	var row := HBoxContainer.new()
	var left := Label.new()
	left.text = what
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	row.add_child(left)
	var right := Label.new()
	right.text = value
	row.add_child(right)
	_body.add_child(row)


func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_body.add_child(label)
