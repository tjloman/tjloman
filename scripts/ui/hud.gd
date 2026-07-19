class_name HUD
extends CanvasLayer
## The (mostly empty) godly dashboard. The world itself is the interface:
## belief is the COLOR of each village's ring, population its SIZE, prayer
## power the GLOW of the totem orb, ALIGNMENT is your own hand's color and
## the cast of the sky, and details live on hover. What remains here: the
## diet readout, gesture legend, hover tooltip, announcements, F1 help.

var village: Village
var divine_hand: DivineHand
var creature: Creature
var camera_rig: CameraRig

var _diet_label: Label
var _hover_label: Label
var _message_label: Label
var _message_timer := 0.0
var _help_panel: PanelContainer
var _cast_label: Label
var _creature_panel: PanelContainer
var _creature_label: Label
var _praise_scold: HBoxContainer


func _ready() -> void:
	layer = 5
	_build_bars()
	_build_miracle_panel()
	_build_creature_panel()
	_build_praise_scold()
	_build_hover_label()
	_build_message_label()
	_build_help_panel()

	GameState.announcement.connect(_on_announcement)
	GameState.cast_hint.connect(_on_cast_hint)
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


## A dim panel that owns the top of the screen: a standing reference to the
## two-step miracle gestures, plus a live cast line that persists through the
## noise of the world (world announcements go elsewhere and can't erase it).
func _build_miracle_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _dim_panel_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MIRACLES  —  draw a MENU, then a SELECTOR  (right mouse, or CAST mode on touch)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	vbox.add_child(title)

	var ref := Label.new()
	ref.text = ("spiral ▸ NATURE:  O Food · | Forest · — Thicket · \\ Rain\n"
		+ "rev-spiral ▸ WRATH:  | Lightning · O Storm · \\ Fireball · — Tornado\n"
		+ "wave / S ▸ SKY:  — Heal · O Birds · | Rain      (F1 — full controls)")
	ref.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ref.add_theme_font_size_override("font_size", 13)
	ref.add_theme_color_override("font_color", Color(1, 1, 0.85, 0.85))
	vbox.add_child(ref)

	_cast_label = Label.new()
	_cast_label.text = "Draw a spiral, reverse-spiral, or wave/S to begin a miracle."
	_cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_label.add_theme_font_size_override("font_size", 16)
	_cast_label.add_theme_color_override("font_color", Color(1, 0.92, 0.5))
	vbox.add_child(_cast_label)

	add_child(panel)


## Creature dashboard — hidden until you LOCK onto the creature (C, or the
## Creature button). While locked it reads out what he is doing and feeling,
## so on a phone you never have to hunt for a hover tooltip.
func _build_creature_panel() -> void:
	_creature_panel = PanelContainer.new()
	_creature_panel.position = Vector2(16, 92)
	_creature_panel.add_theme_stylebox_override("panel", _dim_panel_style())
	_creature_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_creature_panel.visible = false

	_creature_label = Label.new()
	_creature_label.add_theme_font_size_override("font_size", 16)
	_creature_label.add_theme_color_override("font_color", Color.WHITE)
	_creature_panel.add_child(_creature_label)
	add_child(_creature_panel)


## Praise / Scold — big touch buttons, top-right, only while locked on. They
## reinforce (or discourage) the creature's LAST deed, same as P / L.
func _build_praise_scold() -> void:
	_praise_scold = HBoxContainer.new()
	_praise_scold.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_praise_scold.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_praise_scold.add_theme_constant_override("separation", 12)
	_praise_scold.visible = false

	var praise := _big_button("Praise", Color(0.3, 0.6, 0.35))
	praise.pressed.connect(_on_praise)
	_praise_scold.add_child(praise)

	var scold := _big_button("Scold", Color(0.62, 0.3, 0.3))
	scold.pressed.connect(_on_scold)
	_praise_scold.add_child(scold)
	add_child(_praise_scold)


func _big_button(text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 64)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", style)
	return b


func _dim_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.42)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	return style


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
Left mouse (on things) ..... pick up food, sheep, villagers — even TREES (uproot!)
Tap / short move, release .. place gently — no fear, no harm
  ...a gentle tree replants where set down; on a storehouse it banks its lumber
  ...a gentle release AT your creature HANDS it the object (it learns to watch you)
Drag and FLICK, release .... throw! (hard landings hurt — and stain your soul)
  ...only a real drag-flick throws; taps and pokes always place, never fling
  ...throw TO your creature: if it's attentive (and practiced) it CATCHES

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
C .......................... LOCK the camera onto your creature (again to release)
F1 ......................... toggle this help
F2 ......................... cycle graphics quality: Low / Medium / High

ON TOUCHSCREENS
One finger ................. everything the left mouse does (per the Mode button)
Mode button ................ toggle: MOVE (drag/pick/place/throw) or CAST (draw gestures)
Creature button ............ lock the camera onto your creature — and open its
                             dashboard (what it's doing & feeling) plus PRAISE /
                             SCOLD buttons, top-right
To throw on glass .......... drag and flick in one stroke; a tap just places
Pinch ...................... zoom
Two-finger drag ............ orbit the camera freely (yaw and tilt)

MIRACLES — two gestures, held right mouse
Step 1: draw a MENU opener.   Step 2: draw a SELECTOR in that menu.
The miracle drops into your hand as an orb — THROW it where you want.

  SPIRAL — Nature:   O Food (20) · | Forest seed, 13 trees (45)
                     — Forage thicket (30) · \\ Bloom/Rain (25)
  REVERSE-SPIRAL — Wrath:  | Lightning (30) · O Lightning STORM (90)
                     \\ Fireball (25) · — Tornado (110)
  WAVE or S — Sky:  — Heal (15) · O Bird flock, an omen (40) · | Rain (25)

The grandest miracles (storm, tornado) need a wide reservoir of prayer —
convert more villages to hold and wield them, and your reach (belief +
villages) widens their fury.

THROWING
Anything you hold carries your hand's momentum when released — flick
hard to hurl far. Tilt the camera above the horizon (middle mouse) and
aim at the sky to wind up high, arcing throws.

READING THE WORLD (there are almost no bars)
Each village's ring: SIZE is its population, COLOR its belief — gray
heathens brighten toward gold; converted rings wear your alignment.
The totem orb glows with prayer power. Hover houses for the census,
farms for harvest progress, the storehouse for exact stocks.
GRAB a QUARTER of the storehouse platform to withdraw THAT resource;
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

	_update_creature_panel()

	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message_label.text = ""


## Shown only while the camera is LOCKED onto the creature. Its stats live
## here in plain words instead of a hover tooltip — the whole reason the
## lock-on exists on a phone.
func _update_creature_panel() -> void:
	var locked := camera_rig != null and is_instance_valid(creature) \
		and camera_rig.follow_target == creature
	_creature_panel.visible = locked
	_praise_scold.visible = locked
	if not locked:
		return
	_creature_label.text = ("YOUR CREATURE\n"
		+ "Doing:    %s\n"
		+ "Nature:   %s\n"
		+ "Mood:     %s\n"
		+ "Bond:     %d / 100\n"
		+ "Hunger:   %d / 100\n"
		+ "Energy:   %d / 100") % [
			creature.activity_word(), creature.morality_word(), creature.mood_word(),
			int(creature.bond), int(creature.hunger), int(creature.energy)]


func _on_praise() -> void:
	if is_instance_valid(creature):
		creature.praise()


func _on_scold() -> void:
	if is_instance_valid(creature):
		creature.scold()


func _on_cast_hint(text: String) -> void:
	if _cast_label != null:
		_cast_label.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help_panel.visible = not _help_panel.visible


func _on_announcement(text: String) -> void:
	_message_label.text = text
	_message_timer = 5.0


func _on_hover_info(text: String) -> void:
	_hover_label.text = text
