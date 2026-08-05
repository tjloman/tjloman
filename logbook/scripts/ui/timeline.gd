class_name TimelineBar extends Control
## The scrubber: a strip of time with the day's speed drawn behind it and
## every logged event as a pip along it.
##
## Dragging it moves a playhead, and the map follows — which is the whole
## point of logging position continuously. "Where was I when Dana called?" is
## a drag, not a query.

signal scrubbed(t: float)
signal released
signal event_picked(id: String)

const HEIGHT := 76.0
const PIP_ROW := 14.0

var range_start := 0.0
var range_end := 0.0
var playhead := -1.0        ## -1 = live, pinned to the right edge.

var _drag := false
var _pips: Array = []       ## [{x, id, kind}] rebuilt each draw for hit-testing.
var _font: Font


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font


func _ready() -> void:
	show_today()
	Logbook.fix_appended.connect(func(_i: int) -> void: _live_follow())
	Logbook.event_appended.connect(func(_e: Dictionary) -> void: queue_redraw())
	Logbook.trip_opened.connect(show_today)


func _live_follow() -> void:
	if playhead < 0.0 and range_end > 0.0:
		var now := Time.get_unix_time_from_system()
		if now > range_end:
			var span := range_end - range_start
			range_end = now
			range_start = now - span
	queue_redraw()


func show_today() -> void:
	var now := Time.get_unix_time_from_system()
	set_range(now - 8.0 * 3600.0, now)


func show_day(key: String) -> void:
	for d in Logbook.days():
		if String(d["key"]) == key:
			set_range(float(d["t0"]) - 600.0, float(d["t1"]) + 600.0)
			return


func show_trip() -> void:
	set_range(Logbook.start_time(), maxf(Logbook.end_time(), Logbook.start_time() + 3600.0))


func set_range(t0: float, t1: float) -> void:
	range_start = t0
	range_end = maxf(t1, t0 + 60.0)
	queue_redraw()


func zoom_time(factor: float) -> void:
	var mid := playhead if playhead > 0.0 else (range_start + range_end) * 0.5
	var half := (range_end - range_start) * 0.5 * factor
	set_range(mid - half, mid + half)


func _t_at(x: float) -> float:
	return lerpf(range_start, range_end, clampf(x / maxf(1.0, size.x), 0.0, 1.0))


func _x_at(t: float) -> float:
	var span := range_end - range_start
	if span <= 0.0:
		return 0.0
	return (t - range_start) / span * size.x


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			# A tap on a pip opens that entry; a tap anywhere else scrubs.
			for p in _pips:
				if absf(float(p["x"]) - t.position.x) < 10.0 and t.position.y > size.y - PIP_ROW * 2.0:
					event_picked.emit(String(p["id"]))
					return
			_drag = true
			_scrub(t.position.x)
		else:
			_drag = false
			released.emit()
	elif event is InputEventScreenDrag and _drag:
		_scrub((event as InputEventScreenDrag).position.x)


func _scrub(x: float) -> void:
	playhead = _t_at(x)
	scrubbed.emit(playhead)
	queue_redraw()


func go_live() -> void:
	playhead = -1.0
	show_today()
	scrubbed.emit(-1.0)


# --------------------------------------------------------------------- draw


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09, 0.9))
	_draw_days()
	_draw_speed()
	_draw_pips()
	_draw_playhead()
	draw_line(Vector2(0, 0), Vector2(w, 0), Color(1, 1, 1, 0.08), 1.0)
	draw_line(Vector2(0, h - 1), Vector2(w, h - 1), Color(1, 1, 1, 0.05), 1.0)


func _draw_days() -> void:
	var span := range_end - range_start
	# Pick a tick that leaves labels readable: hours for a day, days for a trip.
	var step := 3600.0
	if span > 3.0 * 86400.0:
		step = 86400.0
	elif span > 12.0 * 3600.0:
		step = 6.0 * 3600.0
	elif span < 2.0 * 3600.0:
		step = 900.0
	var t := ceilf(range_start / step) * step
	while t < range_end:
		var x := _x_at(t)
		draw_line(Vector2(x, 12), Vector2(x, size.y), Color(1, 1, 1, 0.08), 1.0)
		var caption := UI.clock(t) if step < 86400.0 else UI.date_line(t)
		draw_string(_font, Vector2(x + 4, 12), caption, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UI.fs(10), Color(0.65, 0.67, 0.72))
		t += step


## The day's speed as a filled sparkline. It is the shape of the ride: the
## flat stretch, the climb, the long lunch.
func _draw_speed() -> void:
	var n := Logbook.fix_count()
	if n < 2:
		return
	var top := 18.0
	var bottom := size.y - PIP_ROW - 4.0
	var i0 := maxi(0, Logbook.index_at_time(range_start))
	var i1 := Logbook.index_at_time(range_end)
	if i1 <= i0:
		return
	var columns := int(size.x / 2.0)
	if columns < 2:
		return
	var stride := maxi(1, (i1 - i0) / columns)
	var peak := 1.0
	var pts := PackedVector2Array()
	var i := i0
	while i <= i1:
		peak = maxf(peak, Logbook.spds[i])
		i += stride
	i = i0
	while i <= i1:
		var x := _x_at(Logbook.times[i])
		var v := clampf(Logbook.spds[i] / peak, 0.0, 1.0)
		pts.push_back(Vector2(x, lerpf(bottom, top, v)))
		i += stride
	if pts.size() < 2:
		return
	var fill := PackedVector2Array(pts)
	fill.push_back(Vector2(pts[pts.size() - 1].x, bottom))
	fill.push_back(Vector2(pts[0].x, bottom))
	draw_colored_polygon(fill, Color(0.35, 0.72, 1.0, 0.16))
	draw_polyline(pts, Color(0.45, 0.78, 1.0, 0.75), 1.5, true)


func _draw_pips() -> void:
	_pips.clear()
	var y := size.y - PIP_ROW * 0.5 - 2.0
	var used := {}
	for e in Logbook.events:
		var t := float(e.get("t", 0.0))
		if t < range_start or t > range_end:
			continue
		var kind := String(e.get("kind", ""))
		var x := _x_at(t)
		# One pip per kind per 6px column: a hundred battery samples in an hour
		# should be one mark, not a smear.
		var slot := "%d/%s" % [int(x / 6.0), kind]
		if used.has(slot):
			continue
		used[slot] = true
		var col := Ev.color(kind)
		draw_rect(Rect2(x - 1.5, y - PIP_ROW * 0.5, 3.0, PIP_ROW), col)
		_pips.push_back({"x": x, "id": String(e.get("id", "")), "kind": kind})


func _draw_playhead() -> void:
	var t := playhead
	var live := t < 0.0
	if live:
		t = Logbook.end_time()
	var x := clampf(_x_at(t), 0.0, size.x)
	var col := UI.WARN if not live else Color(0.35, 0.72, 1.0)
	draw_line(Vector2(x, 0), Vector2(x, size.y), col, 2.0)
	draw_circle(Vector2(x, 10), 5.0, col)
	var caption := UI.clock(t)
	if not live:
		caption += "  " + UI.date_line(t)
	var tw := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(11)).x
	var tx := clampf(x - tw * 0.5, 2.0, size.x - tw - 2.0)
	draw_string(_font, Vector2(tx, size.y - 2), caption, HORIZONTAL_ALIGNMENT_LEFT, -1,
		UI.fs(11), col)
