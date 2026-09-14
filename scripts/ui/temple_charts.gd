class_name TempleCharts
extends ScrollContainer
## THE CHRONICLE ROOM: everything the reign has done to the world, drawn.
##
## All of it comes out of Chronicle, which has been sampling since the first
## second of the run. Nothing here computes anything about the present — that
## is the Reign room's job — because a chart of one moment is a number.
##
## THE AXES ARE IN DAYS, not in seconds and not in "years". A game day is 320
## real seconds and a villager lives about forty of them, so an evening's play
## is roughly a human lifetime: days are the unit in which the population
## curve, the age curve and the player's own memory of the session all agree.

## What is drawn, top to bottom: the series name Chronicle answers to, the
## title over it, the line colour, and how the vertical axis is fixed —
## "zero" grows from nought to whatever the run reached, "signed" is pinned to
## -100..100 about a centre line, "unit" is nought to one.
const PLOTS: Array[Array] = [
	["population", "Souls alive", Color(0.55, 0.85, 1.0), "zero"],
	["median_age", "Median age, in years", Color(0.95, 0.8, 0.45), "zero"],
	["alignment", "Your alignment", Color(1.0, 0.55, 0.4), "signed"],
	["faithful", "Villages holding your faith", Color(0.7, 0.95, 0.6), "zero"],
	["miracles_god", "Miracles you have worked", Color(1.0, 0.9, 0.6), "zero"],
	["miracles_beast", "Miracles the beast has worked", Color(0.85, 0.6, 1.0), "zero"],
	["growth", "How grown the creature is", Color(0.6, 0.75, 1.0), "unit"],
]

const PLOT_TALL := 118.0
const PAD_LEFT := 44.0
const PAD_RIGHT := 10.0
const PAD_TOP := 20.0
const PAD_FOOT := 16.0

var _canvas: Control


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(0.0, PLOTS.size() * PLOT_TALL + 40.0)
	_canvas.draw.connect(_paint)
	add_child(_canvas)


func _paint() -> void:
	var book := Chronicle.of(get_tree())
	var font := ThemeDB.fallback_font
	if book == null or book.depth() < 2:
		_canvas.draw_string(font, Vector2(8.0, 30.0),
			"The record is still being written. Come back in a few minutes.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
		return
	var days := _in_days(book.when())
	var y := 0.0
	for plot: Array in PLOTS:
		_one(book, font, plot, days, y)
		y += PLOT_TALL


## Game-years to game-days, which is the axis anybody can actually read.
static func _in_days(years: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for t: float in years:
		out.append(t / GameState.DAY_YEARS)
	return out


func _one(book: Chronicle, font: Font, plot: Array, days: PackedFloat32Array,
		top: float) -> void:
	var values := book.series(String(plot[0]))
	if values.size() < 2:
		return
	var title := String(plot[1])
	var tint: Color = plot[2]
	var box := Rect2(
		Vector2(PAD_LEFT, top + PAD_TOP),
		Vector2(maxf(_canvas.size.x - PAD_LEFT - PAD_RIGHT, 40.0),
			PLOT_TALL - PAD_TOP - PAD_FOOT))
	_canvas.draw_string(font, Vector2(4.0, top + 14.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))

	var lo := 0.0
	var hi := 1.0
	match String(plot[3]):
		"signed":
			lo = -100.0
			hi = 100.0
		"unit":
			lo = 0.0
			hi = 1.0
		_:
			for v: float in values:
				hi = maxf(hi, v)
			hi *= 1.08

	# The floor of the plot, the ceiling, and (for a signed axis) the nought
	# line, which is the only thing on an alignment chart that means anything.
	_canvas.draw_rect(box, Color(1, 1, 1, 0.05), true)
	_canvas.draw_line(box.position + Vector2(0.0, box.size.y),
		box.position + box.size, Color(1, 1, 1, 0.25), 1.0)
	if lo < 0.0:
		var mid := box.position.y + box.size.y * 0.5
		_canvas.draw_line(Vector2(box.position.x, mid),
			Vector2(box.end.x, mid), Color(1, 1, 1, 0.22), 1.0)
	_canvas.draw_string(font, Vector2(2.0, box.position.y + 9.0),
		_short(hi), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
	_canvas.draw_string(font, Vector2(2.0, box.end.y),
		_short(lo), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))

	var first := days[0]
	var last := maxf(days[days.size() - 1], first + 0.001)
	var line := PackedVector2Array()
	for i in values.size():
		var fx := (days[i] - first) / (last - first)
		var fy := clampf((values[i] - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
		line.append(Vector2(box.position.x + fx * box.size.x,
			box.end.y - fy * box.size.y))
	if line.size() >= 2:
		_canvas.draw_polyline(line, tint, 1.6, true)
	# Where the line ends, and what it ends at — the number a player came for.
	_canvas.draw_circle(line[line.size() - 1], 2.5, tint)
	_canvas.draw_string(font, Vector2(box.position.x, box.end.y + 12.0),
		"day %d  →  day %d" % [int(first), int(last)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
	_canvas.draw_string(font, Vector2(box.position.x, box.end.y + 12.0),
		"now: %s" % _short(values[values.size() - 1]),
		HORIZONTAL_ALIGNMENT_RIGHT, int(box.size.x), 10, tint)


## Numbers a person reads, not numbers a float prints: 1483 souls, not
## 1483.0000, and 0.42 growth rather than 0.
static func _short(v: float) -> String:
	if absf(v) < 10.0 and v != roundf(v):
		return "%.2f" % v
	return "%d" % int(roundf(v))
