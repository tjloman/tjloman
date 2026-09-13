class_name HUD
extends CanvasLayer
## The (mostly empty) godly dashboard. The world itself is the interface:
## belief is the COLOR of each village's ring, population its SIZE, prayer
## power the GLOW of the totem orb, ALIGNMENT is your own hand's color and
## the cast of the sky, and details live on hover. What remains here: the
## diet readout, gesture legend, hover tooltip, announcements, F1 help.

## HOW WIDE THE CREATURE PANEL MAY GET, as a share of the screen, and how many
## characters of a value fit on one line inside it.
##
## It had no width at all: a Label in a PanelContainer sizes to its longest
## line, and the miracle list is one comma-joined string that grows every time
## the beast watches you cast something new. One line eventually covered the
## screen.
##
## The cap is enforced in CHARACTERS ONLY. The first attempt also forced a pixel
## width onto the panel and turned autowrap on, which meant a container that
## wanted to size itself to its label was being told a size at the same time as
## the label was refusing to name one until it had been given a width — and on a
## CanvasLayer there is no parent to arbitrate between them. The whole readout
## went off the screen. Characters need no arbitration: the longest line is
## known before the label is ever measured. How many characters fit is asked of
## the real font each update, in `_wrap_width`, so a narrow phone still gets its
## third of the screen rather than a number that only suited a desktop.
const PANEL_SHARE := 1.0 / 3.0
const WRAP_AT := 46          # the most characters of a value on one line
const WRAP_LEAST := 24       # ...and the fewest, on a narrow phone
const LABEL_PAD := "          "   # the hanging indent, matching "Miracles: "


## WHAT IT HAS LEARNED TO CAST, which is the line that used to run off the
## screen. Wrapped like everything else, and capped: past a dozen the list
## stops being a thing you read and becomes a count.
## How long the chronicle stays up while you are still at the nest, and how
## quickly it clears once you have left it.
const STONE_HOLD := 14.0
const STONE_LEAVE := 1.6
## How wide the speech-bubble tail is where it leaves the panel, how far the
## panel floats off the stone, and the tint they share.
## How wide the scrollbar is for anyone who aims at it rather than swiping.
const STONE_BAR := 22.0
const TAIL_WIDE := 13.0
const STONE_LIFT := 118.0
const TAIL_COLOR := Color(0.09, 0.1, 0.09, 0.82)
## ROOM LEFT EITHER SIDE FOR THE LAND. A panel that can reach the screen edge
## on a phone leaves nowhere to put a thumb down on the world, and the world is
## the game. This much of the width stays clear on both sides, always.
const STONE_SIDE := 0.13
## And the most of the screen's height it may take before it starts scrolling
## instead of growing, with a ceiling in pixels so a desk monitor does not get
## a single column half a metre long.
const STONE_TALL := 0.62
const STONE_WIDE_MOST := 640.0
## The heading column of a key/value block, as a share of the panel's width.
const KEY_SHARE := 0.32

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
## THE ONE WAY TO REACH THE CREATURE ON A PHONE. C does it on a keyboard and
## there is no C on a thumb — Praise and Scold only appear once you are already
## locked on, so until now a phone could not get locked on at all.
var _creature_button: Button
var _roster_refresh := 0.0
## The casting session's own readout: a ring that fills as you press to open
## it, and a bar that drains once you stop drawing. Without these the session
## is invisible, and an invisible mode is a worse mode than a button.
var _cast_overlay: CastOverlay
## What the nest wall says, when somebody has held a press on it. Dismissed by
## the next press anywhere, because a thing you read on a wall is not a menu.
var _stone_panel: PanelContainer
var _stone_label: Label
var _stone_time := 0.0
## Where the wall that was read is standing, and where its WRITING is — the
## first decides when the panel goes away, the second where it points. See
## `_tick_stone`.
var _stone_at := Vector3.INF
var _stone_on: Vector3 = Vector3.INF
## That writing, in screen space, or INF when it is off screen or behind you.
var _stone_mark := Vector2.INF
var _stone_tail: Control
var _stone_scroll: ScrollContainer
## TRUE between pressing on the wall and letting go, so a mouse can drag it the
## way a thumb does. See `_drag_the_stone`.
var _stone_dragging := false
var _stone_rows: VBoxContainer


func _ready() -> void:
	# AWAKE WHILE THE WORLD IS HELD. The opening screen pauses the tree, and a
	# paused node is offered no input — so without this the buttons that open
	# this very menu would be shouting at something asleep.
	process_mode = Node.PROCESS_MODE_ALWAYS

	layer = 5
	_build_bars()
	_build_miracle_panel()
	_build_creature_panel()
	_build_praise_scold()
	_build_creature_button()
	_build_hover_label()
	_build_message_label()
	_build_help_panel()
	_build_roster()
	_cast_overlay = CastOverlay.new()
	_cast_overlay.divine_hand = divine_hand
	_cast_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cast_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cast_overlay)

	_build_stone_panel()
	GameState.stone_read.connect(_on_stone_read)
	GameState.announcement.connect(_on_announcement)
	GameState.cast_hint.connect(_on_cast_hint)
	if divine_hand != null:
		divine_hand.hover_info_changed.connect(_on_hover_info)


## THE STONE, READ. Same hand-wrapping and no autowrap as the creature panel,
## for the same reason — this sits on a CanvasLayer too.
func _build_stone_panel() -> void:
	_stone_panel = PanelContainer.new()
	_stone_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 16)
	_stone_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stone_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_stone_panel.add_theme_stylebox_override("panel", _dim_panel_style())
	# NOT CLICK-THROUGH ANY MORE, because it has to be SCROLLABLE. A wall that
	# is taller than a phone is a wall with a bottom nobody has ever seen — the
	# six stones were off the end of the screen with no way to reach them.
	_stone_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_stone_panel.visible = false
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	_stone_panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	pad.add_child(column)
	_stone_label = Label.new()
	_stone_label.text = "SCRATCHED INTO THE STONE"
	_stone_label.add_theme_font_size_override("font_size", 15)
	_stone_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	column.add_child(_stone_label)
	_stone_scroll = ScrollContainer.new()
	_stone_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stone_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# DRAG THE TEXT, NOT THE BAR. A scrollbar is a four-pixel target, and this
	# panel is meant to be read on a phone — a thumb has no business hunting for
	# the edge of a wall of text to move it. The whole panel takes a swipe, the
	# same way every page anybody has ever read on a phone does, and the bar is
	# widened to a thumb as well for anyone who reaches for it anyway.
	_stone_scroll.gui_input.connect(_drag_the_stone)
	var bar := _stone_scroll.get_v_scroll_bar()
	if bar != null:
		bar.custom_minimum_size = Vector2(STONE_BAR, 0)
	column.add_child(_stone_scroll)
	_stone_rows = VBoxContainer.new()
	_stone_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stone_rows.add_theme_constant_override("separation", 10)
	_stone_scroll.add_child(_stone_rows)
	# THE TAIL IS DRAWN FIRST so the panel sits on top of where it joins.
	_stone_tail = Control.new()
	_stone_tail.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stone_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stone_tail.draw.connect(_draw_stone_tail)
	add_child(_stone_tail)
	add_child(_stone_panel)


## A FINGER OR A MOUSE, DRAGGING THE WALL ITSELF. Godot's ScrollContainer takes
## a touch drag on a touchscreen and nothing at all from a mouse, so this covers
## both with the same code and keeps the two feeling alike.
func _drag_the_stone(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_stone_scroll.scroll_vertical -= int((event as InputEventScreenDrag).relative.y)
		_stone_scroll.accept_event()
	elif event is InputEventMouseButton:
		var press := event as InputEventMouseButton
		if press.button_index == MOUSE_BUTTON_LEFT:
			_stone_dragging = press.pressed
	elif event is InputEventMouseMotion and _stone_dragging:
		_stone_scroll.scroll_vertical -= int((event as InputEventMouseMotion).relative.y)
		_stone_scroll.accept_event()


## THE POINTER. A speech-bubble tail from the panel down to the writing it came
## off, so there is never a question of what is being talked about — and so that
## a panel which follows the stone around the screen still reads as belonging to
## it rather than as having come loose.
func _draw_stone_tail() -> void:
	if not _stone_panel.visible or _stone_mark == Vector2.INF:
		return
	var box := _stone_panel.get_global_rect()
	var from := box.get_center()
	var out := (_stone_mark - from)
	if out.length() < 1.0:
		return
	# The base of the tail sits across the panel edge, square to the line out.
	var side := Vector2(-out.y, out.x).normalized() * TAIL_WIDE
	var edge := from + out.normalized() * _edge_span(box, out)
	_stone_tail.draw_colored_polygon(
		PackedVector2Array([edge + side, edge - side, _stone_mark]), TAIL_COLOR)


## How far the panel's own edge is along a heading — so the tail starts AT the
## rim rather than at the middle, whichever side it leaves from.
func _edge_span(box: Rect2, out: Vector2) -> float:
	var d := out.normalized()
	var half := box.size * 0.5
	var span := INF
	if absf(d.x) > 0.0001:
		span = minf(span, half.x / absf(d.x))
	if absf(d.y) > 0.0001:
		span = minf(span, half.y / absf(d.y))
	return span if span < INF else 0.0


func _on_stone_read(nest: Node) -> void:
	var wall := nest as CreatureNest
	if wall == null or not is_instance_valid(wall):
		return
	_fill_stone(wall.reading())
	_stone_panel.visible = true
	_stone_time = STONE_HOLD
	_stone_at = wall.global_position
	_stone_on = wall.tablet_point()
	# Off the screen's middle and free to move: from here on it follows the
	# stone rather than sitting where the last one sat.
	_stone_panel.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)


## LAY THE WALL OUT — in real controls, sized to the screen it is on.
##
## Rebuilt per reading rather than kept: a wall is read for a few seconds at a
## time and the alternative is a dozen labels held live against a creature that
## is changing under them.
func _fill_stone(part: Dictionary) -> void:
	for old_row in _stone_rows.get_children():
		old_row.queue_free()
	if part.is_empty():
		return
	var screen := get_viewport().get_visible_rect().size
	var wide := minf(screen.x * (1.0 - STONE_SIDE * 2.0), STONE_WIDE_MOST)
	_stone_scroll.custom_minimum_size = Vector2(wide, screen.y * STONE_TALL)
	# HALF EACH, AND THEY STAY HALF EACH. The two columns are the whole point
	# of the header — what he holds against what is so — and a column whose
	# width depends on what happens to be in it is not a column.
	var half := (wide - 26.0) * 0.5
	var head := _stone_grid(2)
	head.add_child(_stone_cell("WHAT HE HOLDS", half, true))
	head.add_child(_stone_cell("WHAT IS SO", half, true))
	for pair: Array in part.get("pairs", []):
		head.add_child(_stone_cell(String(pair[0]), half))
		head.add_child(_stone_cell(String(pair[1]), half))
	_stone_rows.add_child(head)
	for block: Dictionary in part.get("blocks", []):
		_stone_rows.add_child(_stone_cell(String(block["head"]), wide, true))
		var keyw := wide * KEY_SHARE
		var grid := _stone_grid(2)
		for row: Array in block["rows"]:
			grid.add_child(_stone_cell(String(row[0]), keyw))
			grid.add_child(_stone_cell(String(row[1]), wide - keyw - 22.0))
		_stone_rows.add_child(grid)
	_fill_stones(part.get("stones", []), wide)


## THE SIX STONES, which nobody could read because they were off the bottom of
## the screen and there was no bar to hold onto. They are the creature's ETHOS —
## the standing it has earned on each of six counts by what it has actually
## done — and since a player has no way of knowing that from six words and a row
## of pipes, the section now says so.
func _fill_stones(stones: Array, wide: float) -> void:
	if stones.is_empty():
		return
	_stone_rows.add_child(_stone_cell("CUT INTO THE SIX STONES", wide, true))
	_stone_rows.add_child(_stone_cell(
		"what he has made of himself, by what he has done", wide))
	var keyw := wide * KEY_SHARE
	var grid := _stone_grid(2)
	for stone: Array in stones:
		var how := clampf(float(stone[1]), -1.0, 1.0)
		var filled := int(absf(how) * 9.0)
		var bar := ""
		for i in 9:
			bar += "|" if i < filled else "·"
		var word := ""
		if absf(how) >= 0.12:
			word = "  much" if how > 0.0 else "  against"
		grid.add_child(_stone_cell(String(stone[0]), keyw))
		grid.add_child(_stone_cell(bar + word, wide - keyw - 22.0))
	_stone_rows.add_child(grid)


## A grid to hang cells in. The widths themselves live on the CELLS, as minimum
## sizes — a GridContainer sizes a column to its widest child, so fixing the
## children is what fixes the column.
func _stone_grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


## One cell. Wrapping, not truncating: the left column used to be cut at 33
## characters to keep it out of the right column's way, and the interesting
## half of every pair was the half being cut off.
func _stone_cell(text: String, wide: float, heading := false) -> Label:
	var cell := Label.new()
	cell.text = text
	cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.custom_minimum_size = Vector2(wide, 0)
	cell.size_flags_horizontal = Control.SIZE_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_theme_font_size_override("font_size", 15 if heading else 14)
	cell.add_theme_color_override("font_color",
		Color(0.96, 0.93, 0.82) if heading else Color(0.86, 0.84, 0.76))
	return cell


## THE STONE GOES OFF THE SCREEN WHEN YOU WALK AWAY FROM THE STONE.
##
## It was a flat fourteen seconds wherever you went, which is a long time to
## carry a wall of text across a valley — and the one thing the player is
## certain to do after reading a nest is leave it. So the timer is now a
## backstop rather than the rule: past the nest's own grounds it fades in
## STONE_LEAVE seconds instead, and while you are still standing there the hold
## keeps being renewed and it stays up as long as you want it.
func _tick_stone(delta: float) -> void:
	if _stone_time <= 0.0:
		return
	if _stone_at != Vector3.INF:
		var gap := _stone_at.distance_to(GameState.camera_focus)
		if gap <= CreatureNest.GROUNDS:
			_stone_time = STONE_HOLD          # still at the wall: it keeps
		elif _stone_time > STONE_LEAVE:
			_stone_time = STONE_LEAVE         # walked off: it goes, shortly
	_stone_time -= delta
	if _stone_time <= 0.0:
		_stone_panel.visible = false
		return
	_follow_stone()


## WHERE THE PANEL SITS — over the writing, wherever the writing is on screen.
##
## It was pinned to the centre of the VIEWPORT, which is the one place it is
## certainly not: a wall of text about a wall, floating in the sky, while the
## wall itself is off to the left behind a tree. Anchoring it to the stone is
## what makes the tail below mean anything.
##
## The panel is nudged to stay wholly on screen, because a bubble half off the
## edge is worse than one slightly out of line — and the TAIL keeps pointing at
## the true spot either way, which is exactly what a tail is for.
func _follow_stone() -> void:
	var cam := camera_rig.camera if camera_rig != null else null
	if cam == null or not is_instance_valid(cam) or _stone_on == Vector3.INF:
		_stone_mark = Vector2.INF
		_stone_tail.queue_redraw()
		return
	if cam.is_position_behind(_stone_on):
		# Turned away from it entirely: nothing to point at, so nothing to say.
		_stone_panel.visible = false
		_stone_mark = Vector2.INF
		_stone_tail.queue_redraw()
		return
	_stone_mark = cam.unproject_position(_stone_on)
	var screen := _stone_tail.size
	var box := _stone_panel.size
	var at := _stone_mark - Vector2(box.x * 0.5, box.y + STONE_LIFT)
	at.x = clampf(at.x, 12.0, maxf(screen.x - box.x - 12.0, 12.0))
	at.y = clampf(at.y, 12.0, maxf(screen.y - box.y - 12.0, 12.0))
	_stone_panel.position = at
	_stone_tail.queue_redraw()


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
	# The bent strokes get their own line and their own sentence, because the
	# thing players most need told is the thing that is no longer true: how
	# round you draw it does not matter any more, only which way it bends.
	ref.text = ("S ~ water    | force    / fire    O life    Z fury\n"
		+ "spiral: air    reverse spiral: calm\n"
		+ "^ sky   V earth   > ward   < unspoken   (sharp or round alike)\n"
		+ "— straight across strikes it all out  ·  water+force = thunderstorm")
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
	# NO AUTOWRAP, deliberately. Every value is already broken to a fixed number
	# of characters by `_field`, so the label's size is a plain function of its
	# text. Autowrap makes it a NEGOTIATION instead: the label reports a minimum
	# width of nothing and a height that depends on the width it is eventually
	# handed, and a PanelContainer sitting straight on a CanvasLayer — which is
	# what this HUD is — has no layout parent to settle that against. It is the
	# same shape of bug as the runes drawing at x=0, and it took the whole
	# readout off the screen. Hand-wrapping was already doing the real work;
	# autowrap was only ever the backstop, and `_field` now covers that case
	# itself by breaking a word too long to fit.
	_creature_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_creature_panel.add_child(_creature_label)
	add_child(_creature_panel)
	_make_click_through(_creature_panel)


## One "Label:   value" row, wrapped to `wrap` characters with every line after
## the first indented under the value rather than under the label.
func _field(label: String, value: String, room: int) -> String:
	var lines: Array[String] = []
	for para: String in value.split("\n"):
		var line := ""
		for raw: String in para.split(" "):
			if raw == "":
				continue
			var word := raw
			# A WORD TOO LONG FOR THE LINE is broken across lines rather than
			# left to run off the edge. This is the one case autoroom used to
			# cover, and covering it here is what lets autoroom stay off — with
			# it off, the label's size follows from its text and nothing has to
			# be negotiated with a container that has no parent to ask.
			while word.length() > room:
				if line != "":
					lines.append(line)
					line = ""
				lines.append(word.substr(0, room))
				word = word.substr(room)
			if word == "":
				continue
			if line == "":
				line = word
			elif line.length() + 1 + word.length() <= room:
				line += " " + word
			else:
				lines.append(line)
				line = word
		lines.append(line)
	if lines.is_empty():
		lines.append("")
	var out := "%-9s %s" % [label + ":", lines[0]]
	for i in range(1, lines.size()):
		out += "\n" + LABEL_PAD + lines[i]
	return out


## HOW MANY CHARACTERS FIT in a third of THIS screen, measured against the font
## the panel is actually using rather than assumed. Average lowercase width is
## the right yardstick for prose — measuring an "M" would cramp every line to
## suit a letter that barely appears.
func _wrap_width() -> int:
	var font := _creature_label.get_theme_font("font")
	var size := _creature_label.get_theme_font_size("font_size")
	if font == null or size <= 0:
		return WRAP_AT
	var alphabet := "abcdefghijklmnopqrstuvwxyz"
	var em := font.get_string_size(
		alphabet, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / float(alphabet.length())
	var cap := get_viewport().get_visible_rect().size.x * PANEL_SHARE
	# The label column is spent before any of the value is: every rendered line
	# is the wrap plus the ten characters of "Miracles: " or of the hanging
	# indent under it. Budgeting without that made the panel a fifth wider than
	# the third it is supposed to keep to.
	var room := int(cap / maxf(em, 1.0)) - LABEL_PAD.length()
	return clampi(room, WRAP_LEAST, WRAP_AT)


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


## Under the villages button, in the same plain style, because it is the same
## kind of thing: somewhere to go.
func _build_creature_button() -> void:
	_creature_button = Button.new()
	_creature_button.text = "Creature [C]"
	_creature_button.position = Vector2(16, 84)
	_creature_button.custom_minimum_size = Vector2(160, 34)
	_creature_button.focus_mode = Control.FOCUS_NONE
	_creature_button.add_theme_font_size_override("font_size", 15)
	_creature_button.pressed.connect(_on_find_creature)
	add_child(_creature_button)


## EXACTLY WHAT C DOES, and by the same road — the key and the button must not
## be two behaviours that happen to look alike, or one of them will quietly rot.
func _on_find_creature() -> void:
	var ev := InputEventAction.new()
	ev.action = "find_creature"
	ev.pressed = true
	Input.parse_input_event(ev)


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

WHEN THE DEVICE GETS HOT
There is no thermal sensor on any platform Godot runs on, so instead the
game watches its own frame times. Slow frames held for several seconds
mean the chip has pulled its clocks back (or there is simply too much
going on), and the world quietly does less: shadows, glow and MSAA go,
draw distances pull in, distant villages think less often — all through
the same paths that already existed for a budget phone.

And your creature STOPS AND LOOKS UP AT YOU. Its own miracles are by a
long way the most expensive thing in the game, so they are the first to
go, and a creature that halts and turns to face you is not a glitch —
it is the most legible thing on screen. It goes back to what it was
doing the moment the frames recover. A single stutter never triggers
any of this; the condition has to hold.

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
  O circle ..... LIFE       / diagonal ....... FIRE
  spiral ....... AIR        reverse spiral ... CALM
  Z sharp Z .... FURY       (two corners, drawn any size)

A STROKE THAT BENDS MEANS WHICHEVER WAY IT BENDS, and it does not matter
in the least how sharply. A pointed ^ and a shallow dome are the same
rune. So are V and a bowl; so are > and a fat ).

  ^ or dome .... SKY        V or bowl ........ EARTH
  > or ) ....... WARD       < or C ........... nothing yet

That last one is a real sigil with no working bound to it — kept empty
on purpose, waiting for something worth putting there.

  — straight across ....... STRIKE THE WHOLE WORKING OUT

Struck out, everything you had drawn is thrown away and nothing is cast.
The old sweep — down and hooked away — still does the same, so if that is
what your hand already knows, keep it.

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
throw — fire, beast, tree, or villager — is a skill you sharpen.

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
	_tick_stone(delta)
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
	# LOCKED ON, or holding the composed shot of him at his nest. Both are the
	# player saying "him, now" — and losing Praise and Scold at the exact moment
	# you are sitting in front of him watching him lie down would be perverse.
	var locked := camera_rig != null and is_instance_valid(creature) \
		and (camera_rig.follow_target == creature
			or (camera_rig.framed and CreatureNest.holding(creature) != null))
	_creature_panel.visible = locked
	_praise_scold.visible = locked
	if not locked:
		return
	# THREE LINES, AND THEY ARE THE THREE YOU ACT ON.
	#
	# This was eighteen rows deep — nature, habits, feeling, mood, bond, fear,
	# belly, build, stature, welfare, what it had learned, what it believed,
	# what it made of the world, and every miracle it had ever watched. All of
	# that is worth knowing and none of it is worth reading while you are
	# steering a creature around a field. A panel you have to STUDY is a panel
	# you stop looking at, and it was covering a third of the screen to do it.
	#
	# So the readout split by what it is FOR. Is he hungry, is he tired, what is
	# he doing — that is a glance, and it stays out here where he is. Everything
	# slow went onto the nest wall (CreatureNest.chronicle), which is somewhere
	# you walk to and stand still in front of on purpose.
	var room := _wrap_width()
	var rows: Array[String] = [
		"YOUR CREATURE",
		_field("Doing", creature.activity_word(), room),
		_field("Hunger", "%d / 100" % int(creature.hunger), room),
		_field("Energy", "%d / 100" % int(creature.energy), room),
	]
	_creature_label.text = "\n".join(rows)


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
	# Inward from the left edge. Right by luck until now — the default grows
	# END, which from the LEFT edge happens to point onto the screen; the same
	# omission on a right-anchored panel put the workshop drawer off it.
	_roster_panel.grow_horizontal = Control.GROW_DIRECTION_END
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
