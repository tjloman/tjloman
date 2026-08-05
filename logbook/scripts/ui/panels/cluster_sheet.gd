class_name ClusterSheet extends Sheet
## What is under one map pin when several things happened in the same place —
## which, at a lunch stop, is most of them.

var _ids: Array
var _pick: Callable


func _init(ids: Array, on_pick: Callable) -> void:
	super("%d entries here" % ids.size())
	_ids = ids
	_pick = on_pick


func _ready() -> void:
	var rows: Array[Dictionary] = []
	for id in _ids:
		var e := Logbook.get_event(String(id))
		if not e.is_empty():
			rows.push_back(e)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	for e in rows:
		var kind := String(e.get("kind", ""))
		var b := UI.button("%s  %s   %s" % [Ev.glyph(kind), UI.clock(float(e.get("t", 0.0))),
			Ev.summary(e)], func() -> void:
			close()
			_pick.call(String(e.get("id", ""))))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", Ev.color(kind))
		body.add_child(b)
