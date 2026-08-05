class_name StopsPanel extends Sheet
## The plan: everything you intend to stop at, nearest first, each one
## answering "will it be open when I get there".

var _map: MapView


func _init(map: MapView) -> void:
	super("Stops")
	_map = map


func _ready() -> void:
	_build()
	Logbook.event_appended.connect(func(e: Dictionary) -> void:
		if String(e.get("kind", "")) == Ev.STOP_PLAN:
			_build())


func _build() -> void:
	clear()
	body.add_child(UI.row([
		UI.button("＋ Stop at map center", _add_at_center, true),
		UI.button("Photos", _fetch_all_photos),
	]))
	var stops := Logbook.events_of_kind(Ev.STOP_PLAN)
	if stops.is_empty():
		body.add_child(UI.dim("No stops planned. Add them before you leave, while you"
			+ " still have signal to look up hours — that is the whole point of"
			+ " planning them here rather than searching from the roadside."))
		return
	stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Stops.distance_m(a) < Stops.distance_m(b))
	for s in stops:
		body.add_child(_stop_card(s))


func _stop_card(s: Dictionary) -> Control:
	var cat := String(s.get("category", "other"))
	var name := String(s.get("name", "Unnamed stop"))
	var dist := Stops.distance_m(s)
	var verdict := Stops.arrival_verdict(s)
	var color := UI.INK
	if not bool(verdict.get("ok", true)):
		color = UI.DANGER
	elif bool(verdict.get("tight", false)):
		color = UI.WARN

	var head := UI.row([
		UI.label("%s  %s" % [Stops.category_glyph(cat), name], 17),
		UI.spacer(),
		UI.dim(Cfg.dist(dist) if dist >= 0.0 else "", 14),
	])
	var lines: Array = [head]
	if String(verdict.get("text", "")) != "":
		lines.push_back(UI.label(String(verdict["text"]), 14, color))
	var now := Stops.status_at(s, Time.get_unix_time_from_system())
	lines.push_back(UI.dim("now: %s" % String(now.get("text", "")), 13))
	if Stops.has_photo(s):
		lines.push_back(_thumb(s))
	elif String(s.get("photo_pending", "")) != "":
		lines.push_back(UI.dim("photo queued — will download on wifi", 12))
	if String(s.get("note", "")) != "":
		lines.push_back(UI.dim(String(s["note"]), 13))

	var card := UI.card(lines)
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed:
			_edit(s))
	return card


func _thumb(s: Dictionary) -> Control:
	var img := Image.new()
	if img.load(Stops.photo_path(s)) != OK:
		return UI.dim("photo unreadable", 12)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(img)
	rect.custom_minimum_size.y = 130
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return rect


func _add_at_center() -> void:
	var c := _map.center_latlon()
	var s := Logbook.append_event(Ev.STOP_PLAN, {
		"name": "New stop", "category": "food", "lat": c.x, "lon": c.y, "hours": {},
	})
	_edit(s)


## Sheets live in the app's sheet layer, one at a time. Hand the editor back
## up rather than parenting it here, or closing this panel leaves it orphaned.
func _edit(s: Dictionary) -> void:
	var app := get_parent().get_parent()
	if app != null and app.has_method("show_sheet"):
		app.show_sheet(StopEditor.new(s, _map))
	else:
		close()


## Pull every missing stop photo in one go — done at a hotel the night before,
## not on the roadside.
func _fetch_all_photos() -> void:
	var key := Cfg.get_s("google_api_key")
	var queued := 0
	for s in Logbook.events_of_kind(Ev.STOP_PLAN):
		if Stops.has_photo(s):
			continue
		var url := String(s.get("photo_url", ""))
		if url == "":
			url = Stops.street_view_url(s, key)
		if url == "":
			continue
		StopEditor.download_photo(s, url)
		queued += 1
	clear()
	_build()
	body.add_child(UI.dim("%d photo%s queued." % [queued, "" if queued == 1 else "s"]
		+ ("" if key != "" else "  Set a Google API key in Settings, or paste an"
		+ " image URL per stop, to get pictures automatically.")))
