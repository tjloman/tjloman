class_name RuneReadout
extends Control
## WHAT YOU HAVE DRAWN, AND WHAT YOU ARE DRAWING.
##
## The casting session used to say what was on the slate in one line of text at
## the bottom of the screen — "water + force ▸ Thunderstorm" — which is
## accurate and completely undramatic, and worse, arrives only AFTER a stroke
## is finished. Until the finger came up you had no idea whether the game had
## understood the shape you were making.
##
## So the reading is now continuous and drawn:
##
##   THE LIVE GLYPH sits under the stroke as it is made, faint while the shape
##   is ambiguous and firming up as it resolves. A half-drawn circle honestly
##   IS an arc, and it is allowed to look undecided — watching it settle is the
##   point. Nothing here is committed; the rune is read from the finished
##   stroke when the finger lifts (see DivineHand and GestureRecognizer.peek).
##
##   THE RUNES ALREADY DRAWN stand in a row above it, glowing, each breathing
##   on its own phase so the row never pulses as one block. They brighten as
##   the working grows, and the last one added swells for a moment — the
##   visual half of the drum that strikes at the same instant.
##
## The glyphs are the RECOGNIZER'S OWN reference drawings, asked for by name
## (`GestureRecognizer.outline`). They therefore cannot drift from what the
## matcher will actually accept, which a hand-drawn set of icons certainly
## would have.

## Where the row of committed runes sits, and how big each one is.
const ROW_Y := 118.0
const ROW_SIZE := 62.0
const ROW_GAP := 16.0
## The live glyph: bigger, lower, and directly under the eye.
const LIVE_Y := 232.0
const LIVE_SIZE := 96.0

## How fast a committed rune breathes, and how far.
const PULSE_RATE := 2.1
const PULSE_DEPTH := 0.09
## How long a freshly-added rune swells for.
const LAND_SECONDS := 0.42
const LAND_SWELL := 0.34

## Below this confidence the live glyph is a suggestion; above it, a reading.
const SURE_ENOUGH := 0.55

var divine_hand: DivineHand

var _age := 0.0
var _shown := 0        # how many runes we had last frame, to catch a new one
var _landed := 0.0     # seconds left of the newest rune's swell


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if divine_hand == null or not is_instance_valid(divine_hand):
		return
	_age += delta
	_landed = maxf(_landed - delta, 0.0)
	var now: int = divine_hand.runes_drawn().size()
	if now > _shown:
		_landed = LAND_SECONDS
	_shown = now
	if divine_hand.casting:
		queue_redraw()


func _draw() -> void:
	if divine_hand == null or not is_instance_valid(divine_hand) or not divine_hand.casting:
		return
	_draw_committed(divine_hand.runes_drawn())
	_draw_live()


## The working so far: one glyph per rune, centred as a row, each breathing on
## its own phase. Brightness rises with how many are up there, so a full slate
## is visibly a heavier thing than a single rune.
func _draw_committed(runes: Array) -> void:
	if runes.is_empty():
		return
	var glow := GameState.alignment_color()
	var span := runes.size() * ROW_SIZE + (runes.size() - 1) * ROW_GAP
	var x := size.x * 0.5 - span * 0.5
	for i in runes.size():
		var shape := _shape_for(String(runes[i]))
		# Each rune breathes out of step with its neighbours; the newest one
		# also swells, easing back down over LAND_SECONDS.
		var breath := 1.0 + sin(_age * PULSE_RATE * TAU + i * 1.7) * PULSE_DEPTH
		if i == runes.size() - 1 and _landed > 0.0:
			breath += LAND_SWELL * (_landed / LAND_SECONDS)
		var heat := lerpf(0.55, 1.0, float(i + 1) / float(runes.size()))
		var at := Vector2(x + i * (ROW_SIZE + ROW_GAP) + ROW_SIZE * 0.5, ROW_Y)
		_stroke(shape, at, ROW_SIZE * breath, glow, heat)
		# A thin under-glow, wider and fainter, so the row reads as lit rather
		# than merely drawn.
		_stroke(shape, at, ROW_SIZE * breath * 1.12,
			Color(glow.r, glow.g, glow.b), heat * 0.22, 9.0)
	# The chain between them: what makes a row of marks read as one working.
	if runes.size() > 1:
		var y := ROW_Y
		var link := Color(glow.r, glow.g, glow.b, 0.22)
		draw_line(Vector2(x + ROW_SIZE * 0.5, y),
			Vector2(x + span - ROW_SIZE * 0.5, y), link, 2.0, true)


## The stroke being drawn right now, as the matcher currently reads it. Faint
## and cool while it is unsure; bright and warm once it has settled.
func _draw_live() -> void:
	var shape: String = divine_hand.live_shape
	if shape == "none":
		return
	var sure: float = divine_hand.live_confidence
	var at := Vector2(size.x * 0.5, LIVE_Y)
	var settled := sure >= SURE_ENOUGH
	var tint := GameState.alignment_color() if settled else Color(0.72, 0.80, 1.0)
	# It grows very slightly as it firms up, which reads as the shape being
	# recognised rather than merely appearing.
	var scale := LIVE_SIZE * lerpf(0.88, 1.0, sure)
	_stroke(_outline(shape), at, scale * 1.15, tint, sure * 0.20, 12.0)
	_stroke(_outline(shape), at, scale, tint, lerpf(0.22, 0.95, sure), 5.0)

	var rune := Spellbook.rune_for(shape)
	if rune != "" and settled:
		var font := ThemeDB.fallback_font
		var label := rune.to_upper()
		var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, Vector2(at.x - wide * 0.5, at.y + scale * 0.62 + 15.0),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(tint.r, tint.g, tint.b, 0.85))


## Draw one glyph, centred at `at`, `span` pixels across.
func _stroke(shape: PackedVector2Array, at: Vector2, span: float,
		tint: Color, alpha: float, width := 4.0) -> void:
	if shape.size() < 2 or alpha <= 0.01:
		return
	var pts := PackedVector2Array()
	for p in shape:
		# The outline arrives in a 100x100 box centred on 50,50.
		pts.append(at + (p - Vector2(50.0, 50.0)) / 100.0 * span)
	draw_polyline(pts, Color(tint.r, tint.g, tint.b, alpha), width, true)


func _shape_for(rune: String) -> PackedVector2Array:
	for shape: String in Spellbook.RUNE_OF:
		if Spellbook.RUNE_OF[shape] == rune:
			return _outline(shape)
	return PackedVector2Array()


func _outline(shape: String) -> PackedVector2Array:
	return GestureRecognizer.outline(shape)
