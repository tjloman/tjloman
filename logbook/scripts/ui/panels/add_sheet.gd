class_name AddSheet extends Sheet
## The "+" menu: what do you want to put on the map, and where.
##
## Opened either from the rail (here, now) or by holding a finger on the map
## (there, now) — the second is how you mark a spot you are riding past and
## cannot stop at.

var _latlon: Vector2
var _app


func _init(latlon: Vector2, app: Node) -> void:
	super("Add to the logbook")
	_latlon = latlon
	_app = app


func _ready() -> void:
	var where := "at your position"
	if _latlon != Vector2.INF:
		where = Geo.format_latlon(_latlon.x, _latlon.y)
		var f := Logbook.last_fix()
		if not f.is_empty():
			var d := Geo.distance_m(float(f["lat"]), float(f["lon"]), _latlon.x, _latlon.y)
			where += "  ·  %s away" % Cfg.dist(d)
	body.add_child(UI.dim(where))
	body.add_child(UI.separator())
	for kind: String in Ev.USER_KINDS:
		var b := UI.button("%s   %s" % [Ev.glyph(kind), Ev.label(kind)],
			func() -> void: _app.add_event(kind, _latlon))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.add_child(b)
	body.add_child(UI.separator())
	body.add_child(UI.dim("Holding a finger on the map drops a pin exactly there — "
		+ "handy for marking a camp spot or a water source you rode past."))
