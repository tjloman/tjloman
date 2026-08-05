class_name DaysPanel extends Sheet
## The trip as a stack of days, newest first: distance, moving time, climb,
## and what happened. Tapping one puts the map and the timeline on that day.
##
## This is the view that turns a continuous GPS log into something a vlog can
## be cut from — every day is already a chapter with its own numbers.

## Untyped on purpose: the app root has no class_name, and typing this as
## Node would make `_app.map` a compile error.
var _app


func _init(app: Node) -> void:
	super(Logbook.trip_name())
	_app = app


func _ready() -> void:
	var days := Logbook.days()
	body.add_child(_totals(days))
	body.add_child(UI.separator())
	if days.is_empty():
		body.add_child(UI.dim("No track yet. Once the logger has a fix, days appear here."))
		return
	for i in range(days.size() - 1, -1, -1):
		body.add_child(_day_card(days[i], i + 1))


func _totals(days: Array) -> Control:
	return UI.card([
		UI.row([
			UI.stat("total", Cfg.dist(Logbook.total_m)),
			UI.stat("days", str(maxi(1, days.size()))),
			UI.stat("moving", Trip.format_duration(Logbook.moving_seconds)),
		], 16),
		UI.row([
			UI.stat("climb", Cfg.elev(Logbook.climb_m), UI.INK_DIM),
			UI.stat("entries", str(Logbook.events.size()), UI.INK_DIM),
			UI.stat("fixes", str(Logbook.fix_count()), UI.INK_DIM),
		], 16),
	])


func _day_card(d: Dictionary, number: int) -> Control:
	var t0 := float(d["t0"])
	var counts := {}
	for e in Logbook.events_between(t0, float(d["t1"])):
		var k := String(e.get("kind", ""))
		counts[k] = int(counts.get(k, 0)) + 1
	var glyphs := ""
	for k: String in counts.keys():
		if not Ev.is_minor(k):
			glyphs += "%s%d  " % [Ev.glyph(k), int(counts[k])]

	var head := UI.row([
		UI.label("Day %d" % number, 18),
		UI.spacer(),
		UI.dim(UI.date_line(t0), 14),
	])
	var stats := UI.row([
		UI.stat("ridden", Cfg.dist(float(d["meters"]))),
		UI.stat("moving", Trip.format_duration(float(d["moving"]))),
		UI.stat("climb", Cfg.elev(float(d["climb"])), UI.INK_DIM),
	], 14)
	var card := UI.card([head, stats, UI.dim(glyphs.strip_edges(), 15)])
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
			_focus_day(d))
	return card


## Put the whole day on screen: the timeline zooms to it, the map fits its
## bounding box, and the playhead parks at its start.
func _focus_day(d: Dictionary) -> void:
	var i0 := int(d["first"])
	var i1 := int(d["last"])
	var min_ll := Vector2(90.0, 180.0)
	var max_ll := Vector2(-90.0, -180.0)
	for i in range(i0, i1 + 1):
		min_ll.x = minf(min_ll.x, Logbook.lats[i])
		min_ll.y = minf(min_ll.y, Logbook.lons[i])
		max_ll.x = maxf(max_ll.x, Logbook.lats[i])
		max_ll.y = maxf(max_ll.y, Logbook.lons[i])
	_app.map.set_follow(false)
	_app.map.fit_bounds(min_ll, max_ll)
	_app.timeline.show_day(String(d["key"]))
	_app.timeline.playhead = float(d["t0"])
	_app.map.highlight_time = float(d["t0"])
	close()
