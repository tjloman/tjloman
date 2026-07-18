class_name HUD
extends CanvasLayer
## The (mostly empty) godly dashboard. The world itself is the interface:
## belief is the COLOR of each village's ring, population its SIZE, prayer
## power the GLOW of the totem orb, ALIGNMENT is your own hand's color and
## the cast of the sky, and details live on hover. What remains here: the
## diet readout, gesture legend, hover tooltip, announcements, F1 help.

var village: Village
var divine_hand: DivineHand

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

	GameState.announcement.connect(_on_announcement)
	if divine_hand != null:
		divine_hand.hover_info_changed.connect(_on_hover_info)


func _build_bars() -> void:
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(16, 16)
	vbox.custom_minimum_size = Vector2(280, 0)
	add_child(vbox)

	_diet_label = _make_label("")
	vbox.add_child(_diet_label)


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	return l


func _build_legend() -> void:
	var legend := Label.new()
	legend.text = "Hold RIGHT MOUSE and draw a gesture:   O  Food (20)" \
		+ "      /\\/\\  Rain (25)      |  Lightning (30)      —  Heal (15)" \
		+ "      \\  Fireball (25)"
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
Release while STILL ........ place gently — no fear, no harm
Release while moving ....... throw! (hard landings hurt — and stain your soul)

PLACING VILLAGERS IS POLICY
Set a villager down in a village of the faith and they will JOIN it —
steal hands for your towns, or shuttle your faithful between them.
Set one of YOUR believers down in a heathen village and they become a
MISSIONARY, preaching at its totem until belief takes root.
Right mouse (hold) ......... draw a miracle gesture
Mouse wheel ................ zoom
Middle mouse (drag) ........ rotate camera
WASD / arrows .............. pan camera
Q / E ...................... rotate camera
1 / 2 / 3 / 4 .............. village diet: Vegan / Omnivore / Carnivore / Cannibal
P / L (hand near creature) . PET (reward) / SCOLD (discourage) its last deed
C .......................... jump the camera to your creature
F1 ......................... toggle this help

ON TOUCHSCREENS
One finger ................. everything the left mouse does (per the Mode button)
Mode button ................ toggle: MOVE (drag/pick/place/throw) or CAST (draw gestures)
Creature button ............ camera locks to and follows your creature
Pinch ...................... zoom
Two-finger drag ............ orbit the camera freely (yaw and tilt)

MIRACLES (drawn with right mouse held)
Circle ..................... Food falls from the sky (20)
Zigzag ..................... Rain — crops grow 4x (25)
Vertical stroke ............ Lightning — LETHAL up close (30)
Horizontal stroke .......... Healing wave (15)
Diagonal slash ............. FIREBALL — lands in your hand; throw it (25)

THROWING
Anything you hold carries your hand's momentum when released — flick
hard to hurl far. Tilt the camera above the horizon (middle mouse) and
aim at the sky to wind up high, arcing throws.

READING THE WORLD (there are almost no bars)
Each village's ring: SIZE is its population, COLOR its belief — gray
heathens brighten toward gold; converted rings wear your alignment.
The totem orb glows with prayer power. Hover houses for the census,
farms for harvest progress, the storehouse for exact stocks.
GRAB the storehouse platform to withdraw goods as physical items;
drop food, lumber, or stone onto any storehouse to store it there.

THE WORLD
The world is endless: drag the land and keep going. Other villages are
out there — they believe in nothing until your miracles convince them.
Water is a wall to villagers and beasts — but the shore feeds them:
they fish. Your creature wades at half speed, and fishes too.
Villagers age, bear children, and die. The dead leave corpses, and what
happens to corpses is... policy. Villagers pick whatever job the village
needs: farming, hunting, felling timber, quarrying stone, building.
Houses have health and age; they crumble, and the homeless sleep rough.
One day/night cycle passes every 16 villager years — nights are for
sleeping, and for wolves, who prefer wicked villages.
Benevolent souls tame horses (to ride), oxen and llamas (to haul), and
dogs (to guard). Monstrous villages abandon the plough and pen what
they catch. Listen: the world bleats, saws, hammers, croaks, and howls.

YOUR CREATURE
It watches, learns, and feels. It observes villagers working and grows
curious about their jobs; it plays when bored, guards the village at
night when good, sulks when scolded, and makes mischief when idle and
mean. Pet (P) what you like, scold (L) what you don't — it learns what
YOU reward, so praising cruelty raises a monster. Hover it to read its
mood, bond, and what it currently loves doing. Press C if you lose it."""
	help.add_theme_font_size_override("font_size", 15)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 20)
	margin.add_child(help)
	_help_panel.add_child(margin)
	add_child(_help_panel)


func _process(delta: float) -> void:
	if village != null:
		_diet_label.text = "Diet [1-4]: %s" % village.diet_name()
	_hover_label.position = _hover_label.get_viewport().get_mouse_position() + Vector2(18, 18)

	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message_label.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help_panel.visible = not _help_panel.visible


func _on_announcement(text: String) -> void:
	_message_label.text = text
	_message_timer = 5.0


func _on_hover_info(text: String) -> void:
	_hover_label.text = text
