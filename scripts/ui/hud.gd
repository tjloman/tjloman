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
var _miracle_panel: PanelContainer
var _miracle_show := 0.0   # seconds the miracle panel stays up
var _cast_label: Label
var _creature_panel: PanelContainer
var _creature_label: Label
var _praise_scold: HBoxContainer
var _roster_panel: PanelContainer
var _roster_list: VBoxContainer
var _roster_button: Button
var _roster_refresh := 0.0
## The casting session's own readout: a ring that fills as you press to open
## it, and a bar that drains once you stop drawing. Without these the session
## is invisible, and an invisible mode is a worse mode than a button.
var _cast_overlay: CastOverlay


func _ready() -> void:
	layer = 5
	_build_bars()
	_build_miracle_panel()
	_build_creature_panel()
	_build_praise_scold()
	_build_hover_label()
	_build_message_label()
	_build_help_panel()
	_build_roster()
	_cast_overlay = CastOverlay.new()
	_cast_overlay.divine_hand = divine_hand
	_cast_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cast_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cast_overlay)

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
	_miracle_panel = panel
	panel.visible = false   # shown only while casting (see _process)
	panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _dim_panel_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "CASTING  —  the world is held. One stroke is one rune. Stop, and it casts."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	vbox.add_child(title)

	var ref := Label.new()
	ref.text = ("S ~ water    | force    — earth    / fire    O life\n"
		+ "spiral: air    reverse spiral: calm    zigzag: fury\n"
		+ "caret ^ : sky    bow ( : ward    (zigzag: 3-7 clear teeth)\n"
		+ "water=rain · water+water=cloudburst · water+force=thunderstorm")
	ref.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ref.add_theme_font_size_override("font_size", 13)
	ref.add_theme_color_override("font_color", Color(1, 1, 0.85, 0.85))
	vbox.add_child(ref)

	_cast_label = Label.new()
	_cast_label.text = "CASTING — draw a rune"
	_cast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_label.add_theme_font_size_override("font_size", 16)
	_cast_label.add_theme_color_override("font_color", Color(1, 0.92, 0.5))
	vbox.add_child(_cast_label)

	add_child(panel)
	# THE PANEL MUST NOT EAT THE DRAWING. Setting the panel itself to IGNORE is
	# not enough: its containers keep Control's default of STOP, so the moment
	# the guide appeared — which is the moment you finished your FIRST rune —
	# it swallowed every further motion event and you could not draw a second.
	_make_click_through(panel)


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
	_make_click_through(_creature_panel)


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


## Set a whole subtree to pass the pointer through. Anything that merely
## DISPLAYS must never be able to intercept a gesture — the world beneath it is
## the interface, and a readout appearing must not change what a drag does.
func _make_click_through(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.get_children():
		if child is Control:
			_make_click_through(child as Control)


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
	_make_click_through(_hover_label)


func _build_message_label() -> void:
	_message_label = Label.new()
	_message_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_message_label.position.y -= 80
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 18)
	_message_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_message_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(_message_label)
	_make_click_through(_message_label)


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
G .......................... LEAD your creature to where your hand points
                             (it goes there and waits; G again releases it)
V .......................... open the VILLAGES roster — snap the camera to any of yours
F1 ......................... toggle this help
F2 ......................... cycle graphics quality: Low / Medium / High
F3 ......................... the WORKSHOP: checkpoint, reload, new land
F4 ......................... skip the opening lessons
F5 ......................... the CREATURES YOU HAVE RAISED — switch, name, begin

THE OPENING LESSONS
A short course runs the first time you play: drag the land, lift a thing,
summon a casting, draw a rune, combine two, find your creature, teach it.
Every lesson is finished by DOING it — there is nothing to click past —
and a hint appears only once you have been stuck a while. F4 sets them
aside; the workshop (F3) can run them again whenever you like.

SAVING — IT LOOKS AFTER ITSELF
There is nothing to remember. The world writes itself down every couple
of minutes, whenever the game is put in the background, and when you
quit — and it puts you straight back where you were next time you play.
The land itself is never written down: every hill, shore and town site
grows back exactly from the world's seed. What is saved is what PLAY
changed: your standing, each village's faith, stocks, doctrine and
people, and your creature's whole mind, heart, beliefs and body.

THE CREATURES YOU HAVE RAISED (F5)
A creature is a long relationship, and you may want more than one — a
beast raised kindly over weeks, and a monster to let off the leash on a
wet afternoon. Each lives in its own world with its own towns, and
switching between them costs neither of them anything. Name a new one
in the field at the bottom and it begins straight away. Forgetting one
is the only thing here that cannot be undone, and it asks twice.

STARTING OVER (F3)
  New land, SAME creature — roll a fresh world and bring your creature
    into it with every habit and belief it earned. The land and its
    people are strangers; the beast at your side is not. Asks twice.

ON TOUCHSCREENS
One finger ................. everything the left mouse does (per the Mode button)
Mode button ................ toggle: MOVE (drag/pick/place/throw) or CAST (draw gestures)
Creature button ............ lock the camera onto your creature — and open its
                             dashboard (what it's doing & feeling) plus PRAISE /
                             SCOLD buttons, top-right
To throw on glass .......... drag and flick in one stroke; a tap just places
Pinch ...................... zoom
Two-finger drag ............ orbit the camera freely (yaw and tilt)

MIRACLES — OPEN THE CASTING, THEN DRAW RUNES
Casting is a thing you ENTER, so that while you are in it nothing you
draw can be mistaken for panning or picking something up.

  OPEN IT ...... hold the RIGHT mouse button (mouse)
                 press bare ground and HOLD (touch) — a ring fills
  WHILE OPEN ... the world is HELD. Every stroke is a rune.
  CLOSE IT ..... just stop. After a couple of quiet seconds what you
                 drew is cast; if you drew nothing, you are simply let
                 go. Escape leaves at once.

The bar at the bottom is the time left, and it only runs down while you
are NOT drawing — so you may take as long as you like over a rune.

ONE UNBROKEN STROKE IS ONE RUNE. Lift and draw again to add another to
the same working.

  S or ~ ....... WATER      | tall line ....... FORCE
  — flat line .. EARTH      / diagonal ....... FIRE
  O circle ..... LIFE       spiral .......... AIR
  reverse spiral  CALM      zigzag (3-7 teeth) FURY
  ^ caret ...... SKY        ( bow ............ WARD

One rune alone is its plainest form: water is rain, force is lightning,
life is food, calm is a healing.

THE SAME RUNE AGAIN MAKES IT BIGGER, not twice:
  water ............... a sprinkle of rain
  water water ......... a cloudburst
  water water water ... a deluge

TWO DIFFERENT RUNES MAKE A THIRD THING:
  water + force ............ THUNDERSTORM (rain, and strikes with it)
  water + force + force .... LIGHTNING STORM
  water + force + force + fury ... TEMPEST
  air + air ................ TORNADO
  air + air + water ........ HURRICANE (the whole sky at once)
  air + fire ............... FIRESTORM (wind spreads the burning)
  earth + life ............. forest    life + water ... thicket
  air + calm ............... flight    air + earth .... portal
  earth + ward ............. strength  life + sky ..... bird flock

AND ANYTHING ELSE STILL WORKS. A combination nobody named casts every
rune's own miracle at once, each a little weaker — so nothing you invent
is ever wasted, and some of it is worth keeping.

YOUR DOMINION IS YOUR SPELLBOOK
Villages teach you RUNES, not finished miracles — and every combination
of the runes you hold is yours for free. Learning rain and lightning
apart IS how you come to hold the storm.
  1 village .... water · life · calm
  2 villages ... earth · force · ward
  3 villages ... fire · sky
  4 villages ... air · fury

THROWING & AFTERTOUCH
Anything you hold carries your hand's momentum when released — flick
hard to hurl far. Tilt the camera above the horizon (middle mouse) and
aim at the sky to wind up high, arcing throws.
It's how you move in the LAST INSTANT that shapes the shot: pull back
as you let go to loft it into a high, slow arc; jerk to one side to
bend the throw that way, the projectile spinning as it curves. Every
throw — fireball, beast, tree, or villager — is a skill you sharpen.

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
It watches, learns, and feels. Nothing it does is scripted: its body
knows only broad needs — hunger, tiredness, boredom, loneliness, fear —
and boredom asks for STIMULATION without caring whether that turns out
to be dancing, running, showing off or smashing a house. Which one this
creature reaches for is settled by what it has learned, what it has come
to believe, and what it has watched YOU do.

Most of a life is neither kind nor cruel. It can lounge in the grass and
watch the world go by, run for the joy of running (with a tree on its
back, which is how it builds muscle), dance, lead the village's prayers,
or simply stand among the people and be looked at — which wins belief
without a drop of blood. It cannot dance or pray until it has WATCHED
someone dance or pray, so a joyful village raises a creature with a
wider life than a grim one does.

IT COPIES YOU. Everything your hand does near it is a lesson: what you
pick up, what you set down kindly, what you hurl, who you mend. There is
no list of deeds worth copying — whatever you do is what you are
teaching.

TRUST is separate from bond, and it is the valve on all of that. Praise,
gifts and healing earn it; hurting it with your own miracles spends it
fast. So does scolding it for something that was not cruel — it knows
the difference between a correction and a god being unfair. Let trust
fall and it stops copying you, then keeps its distance, and a creature
that has grown KINDER THAN YOU may simply walk away to live by its own
lights. It will not come when called. It comes home only once you have
BOTH won its trust back AND stopped doing the thing it left over — it
remembers, and every repeat starts the reckoning again.

RITUAL
It remembers the ORDER of things, not just the deeds. When one act keeps
following another and the day goes well, that pairing firms up, and it
will start doing them in that order — fishing before it works a miracle,
say. It is usually wrong about why, which is what a ritual is. Read what
it has decided in the workshop panel (F3).

Pet (P) what you like, scold (L) what you don't. Hover it to read its
mood, bond, trust and what it has learned to love. Press C if you lose
it."""
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
	_update_miracle_panel(delta)
	_update_roster(delta)

	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_message_label.text = ""


## The miracle guide is only up while you're actually casting: on touch, when
## CAST mode is on; on desktop, while the right mouse button is held. Either
## way it lingers ~5s after (and whenever a cast hint fires) so you can read
## the last step, then tucks itself away to keep the screen clean.
func _update_miracle_panel(delta: float) -> void:
	# The guide is up for exactly as long as the casting session is.
	var active := divine_hand != null and is_instance_valid(divine_hand) \
		and divine_hand.casting
	if active:
		_miracle_show = 5.0
	else:
		_miracle_show = maxf(_miracle_show - delta, 0.0)
	_miracle_panel.visible = _miracle_show > 0.0
	# THE WORKING, live: the runes on the slate and what they would become if
	# you let go now. Without this the composition system is unlearnable — you
	# would be guessing at what your own drawing meant.
	if divine_hand != null and is_instance_valid(divine_hand):
		var working := divine_hand.working_text()
		if working != "":
			_cast_label.text = working + "     (draw again, or wait to cast)"
		elif divine_hand.casting:
			_cast_label.text = "CASTING — draw a rune"


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
	# Its inner life, in plain words — including what it has LEARNED to love and
	# any miracles it has picked up by watching you.
	var learned: String = creature.mind.strongest_urge()
	# WHAT IT BELIEVES — the convictions it has drawn from its own life.
	var creed: Array = creature.mind.beliefs.creed(2)
	var believes := "nothing firmly yet" if creed.is_empty() else "\n          ".join(creed)
	# WHAT IT MAKES OF THE WORLD ITSELF — what tends to happen, and which
	# stretches of country it has come to feel something about.
	var picture: Array = creature.mind.world_picture()
	var world := "no idea yet" if picture.is_empty() else "\n          ".join(picture)
	var spells: Array = creature.mind.known_miracles()
	var magic: String = ", ".join(spells) if not spells.is_empty() else "none yet"
	# ITS CHARACTER, spelled out. The one-word nature above is the compass
	# named; these are the leanings that name actually stands for, so a player
	# can see WHY their beast is called what it is called.
	var habits: Array = creature.character_lines()
	var character := "nothing settled yet" if habits.is_empty() \
		else "\n          ".join(habits)
	_creature_label.text = ("YOUR CREATURE\n"
		+ "Doing:    %s\n"
		+ "Nature:   %s\n"
		+ "Habits:   %s\n"
		+ "Feeling:  %s\n"
		+ "Mood:     %s\n"
		+ "Bond:     %d / 100\n"
		+ "Hunger:   %d / 100\n"
		+ "Energy:   %d / 100\n"
		+ "Fear:     %d / 100\n"
		+ "Belly:    %d%% full%s\n"
		+ "Body:     %s  (fat %d · strength %d%s)\n"
		+ "Learned:  %s\n"
		+ "Believes: %s\n"
		+ "World:    %s\n"
		+ "Miracles: %s") % [
			creature.activity_word(), creature.morality_word(), character,
			" and ".join(creature.heart.account()), creature.mood_word(),
			int(creature.bond), int(creature.hunger), int(creature.energy),
			int(creature.fear),
			int(creature.body.fullness(creature.growth) * 100.0),
			"  (digesting)" if creature.body.stomach > 0.05 else "",
			creature.body.condition_word(), int(creature.body.fat),
			int(creature.body.strength), "  BOOSTED" if creature.body.is_boosted() else "",
			learned, believes, world, magic]


## Village roster ------------------------------------------------------------

## A toggleable directory of the villages that believe in you: population,
## distance, and a Go button that snaps the camera to each. Lines are kept
## roomy — more per-village readouts (belief, unrest, unlocks) will slot in
## as those systems land.
func _build_roster() -> void:
	_roster_button = Button.new()
	_roster_button.text = "Villages [V]"
	_roster_button.position = Vector2(16, 46)
	_roster_button.custom_minimum_size = Vector2(160, 34)
	_roster_button.focus_mode = Control.FOCUS_NONE
	_roster_button.add_theme_font_size_override("font_size", 15)
	_roster_button.pressed.connect(_toggle_roster)
	add_child(_roster_button)

	_roster_panel = PanelContainer.new()
	_roster_panel.visible = false
	_roster_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_roster_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_roster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_roster_panel.add_theme_stylebox_override("panel", _dim_panel_style())

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "YOUR VILLAGES"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_list = VBoxContainer.new()
	_roster_list.add_theme_constant_override("separation", 8)
	_roster_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_list)
	outer.add_child(scroll)
	_roster_panel.add_child(outer)
	add_child(_roster_panel)


func _toggle_roster() -> void:
	_roster_panel.visible = not _roster_panel.visible
	if _roster_panel.visible:
		_rebuild_roster()
		_roster_refresh = 0.5


## While open, refresh every half-second so population and distance stay live
## and newly converted villages appear.
func _update_roster(delta: float) -> void:
	if _roster_panel == null or not _roster_panel.visible:
		return
	_roster_refresh -= delta
	if _roster_refresh <= 0.0:
		_roster_refresh = 0.5
		_rebuild_roster()


func _rebuild_roster() -> void:
	for child in _roster_list.get_children():
		child.queue_free()
	var cam := camera_rig.global_position if camera_rig != null else Vector3.ZERO
	var mine: Array = []
	for v in get_tree().get_nodes_in_group("village"):
		var vil := v as Village
		if is_instance_valid(vil) and vil.converted:
			mine.append(vil)
	mine.sort_custom(func(a: Village, b: Village) -> bool:
		return a.global_position.distance_to(cam) < b.global_position.distance_to(cam))
	if mine.is_empty():
		var none := Label.new()
		none.text = "No village yet believes in you.\nConvert one with your miracles."
		none.add_theme_font_size_override("font_size", 14)
		_roster_list.add_child(none)
		return
	for vil: Village in mine:
		_roster_list.add_child(_roster_row(vil, cam))


func _roster_row(vil: Village, cam: Vector3) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(300, 60)  # roomy — future stats go here
	row.add_theme_constant_override("separation", 10)

	var go := Button.new()
	go.text = "Go"
	go.custom_minimum_size = Vector2(58, 52)
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_font_size_override("font_size", 16)
	go.pressed.connect(_snap_to_village.bind(vil))
	row.add_child(go)

	var flat := Vector2(vil.global_position.x - cam.x, vil.global_position.z - cam.z)
	var home := "  (home)" if vil.is_player_home else ""
	var label := Label.new()
	var militia: int = vil.armed_count()
	var arms := "  ·  %d armed" % militia if militia > 0 else ""
	var roused := "  ·  ROUSED" if vil.is_roused() else ""
	var way := vil.trend()
	var drift := "  ·  %s" % way if way != "" else ""
	label.text = "%s%s\nPop %d%s  ·  %d m away%s%s\n " % [
		vil.village_name, home, vil.population(), drift,
		int(round(flat.length())), arms, roused]
	label.add_theme_font_size_override("font_size", 15)
	# A town losing people goes red, so a village dying of demographics cannot
	# do it quietly while you are looking somewhere else.
	label.add_theme_color_override("font_color",
		Color(1.0, 0.6, 0.55) if way == "DWINDLING" else Color.WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return row


func _snap_to_village(vil: Village) -> void:
	if is_instance_valid(vil) and camera_rig != null:
		camera_rig.snap_to(vil.global_position)
		GameState.announce("Surveying %s." % vil.village_name)


func _on_praise() -> void:
	if is_instance_valid(creature):
		creature.praise()


func _on_scold() -> void:
	if is_instance_valid(creature):
		creature.scold()


func _on_cast_hint(text: String) -> void:
	if _cast_label != null:
		_cast_label.text = text
	_miracle_show = maxf(_miracle_show, 5.0)  # keep the guide up to read this step


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help_panel.visible = not _help_panel.visible
	elif event.is_action_pressed("toggle_villages"):
		_toggle_roster()


func _on_announcement(text: String) -> void:
	_message_label.text = text
	_message_timer = 5.0


func _on_hover_info(text: String) -> void:
	_hover_label.text = text
