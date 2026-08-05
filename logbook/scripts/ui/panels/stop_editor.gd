class_name StopEditor extends Sheet
## Everything about one planned stop, including the part nobody enjoys:
## typing in the opening hours.
##
## Hours are free text per day — "07:00-21:00", "6:30-14:00,17:00-22:00",
## "24h", "closed" — because that is how they are written on the door and on
## every listing you will copy them from. A picker with seven day-of-week rows
## and two time spinners each would be twenty taps per stop.

var _stop: Dictionary
var _map: MapView
var _hour_fields := {}


func _init(stop: Dictionary, map: MapView) -> void:
	super(String(stop.get("name", "Stop")))
	_stop = stop
	_map = map


func _ready() -> void:
	var name_edit := LineEdit.new()
	name_edit.text = String(_stop.get("name", ""))
	name_edit.placeholder_text = "Name"
	name_edit.custom_minimum_size.y = UI.TOUCH
	name_edit.text_changed.connect(func(v: String) -> void: _patch({"name": v}))
	body.add_child(name_edit)

	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 4)
	for c: String in Stops.CATEGORIES:
		var b := UI.button(Stops.category_glyph(c), func() -> void:
			_patch({"category": c})
			set_title("%s %s" % [Stops.category_glyph(c), String(_stop.get("name", ""))]))
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = c
		if String(_stop.get("category", "")) == c:
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.ACCENT.darkened(0.3), 8))
		cats.add_child(b)
	body.add_child(cats)

	body.add_child(UI.separator())
	body.add_child(UI.dim("OPENING HOURS", 11))
	var hours: Dictionary = _stop.get("hours", {})
	for day: String in Stops.DAYS:
		var field := LineEdit.new()
		field.text = String(hours.get(day, ""))
		field.placeholder_text = "07:00-21:00  ·  24h  ·  closed"
		field.custom_minimum_size.y = 42
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.text_changed.connect(func(_v: String) -> void: _save_hours())
		_hour_fields[day] = field
		body.add_child(UI.row([UI.label(day.capitalize(), 14), field]))
	body.add_child(UI.row([
		UI.button("Copy Mon → all", func() -> void:
			var v: String = _hour_fields["mon"].text
			for d: String in Stops.DAYS:
				_hour_fields[d].text = v
			_save_hours()),
		UI.button("Always open", func() -> void:
			for d: String in Stops.DAYS:
				_hour_fields[d].text = "24h"
			_save_hours()),
	]))

	body.add_child(UI.separator())
	body.add_child(_verdict_card())

	body.add_child(UI.separator())
	body.add_child(UI.dim("PHOTO", 11))
	if Stops.has_photo(_stop):
		var img := Image.new()
		if img.load(Stops.photo_path(_stop)) == OK:
			var rect := TextureRect.new()
			rect.texture = ImageTexture.create_from_image(img)
			rect.custom_minimum_size.y = 200
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			body.add_child(rect)
	var url_field := LineEdit.new()
	url_field.text = String(_stop.get("photo_url", ""))
	url_field.placeholder_text = "Image URL (optional)"
	url_field.custom_minimum_size.y = UI.TOUCH
	url_field.text_changed.connect(func(v: String) -> void: _patch({"photo_url": v}))
	body.add_child(url_field)
	body.add_child(UI.row([
		UI.button("Download photo", func() -> void:
			var url := url_field.text
			if url == "":
				url = Stops.street_view_url(_stop, Cfg.get_s("google_api_key"))
			if url == "":
				body.add_child(UI.label("No URL, and no Google API key set.", 13, UI.WARN))
				return
			download_photo(_stop, url)),
		UI.button("Show on map", func() -> void:
			if _stop.has("lat"):
				_map.set_follow(false)
				_map.set_center_latlon(float(_stop["lat"]), float(_stop["lon"]))
			close()),
	]))

	var note := TextEdit.new()
	note.text = String(_stop.get("note", ""))
	note.custom_minimum_size.y = 90
	note.placeholder_text = "Notes — phone number, gate code, which side of the road"
	note.text_changed.connect(func() -> void: _patch({"note": note.text}))
	body.add_child(note)

	body.add_child(UI.button("Delete stop", func() -> void:
		Logbook.remove_event(String(_stop.get("id", "")))
		close()))


func _verdict_card() -> Control:
	var verdict := Stops.arrival_verdict(_stop)
	var now := Stops.status_at(_stop, Time.get_unix_time_from_system())
	var dist := Stops.distance_m(_stop)
	var eta := Stops.eta_seconds(_stop)
	return UI.card([
		UI.row([
			UI.stat("away", Cfg.dist(dist) if dist >= 0.0 else "—"),
			UI.stat("ride", Trip.format_duration(eta) if eta >= 0.0 else "—"),
			UI.stat("right now", String(now.get("text", "")), UI.INK_DIM),
		], 14),
		UI.label(String(verdict.get("text", "")), 15,
			UI.INK if bool(verdict.get("ok", true)) else UI.DANGER),
		UI.dim("Estimate uses today's average moving speed (%s) and adds 25%% for"
			% Cfg.speed(Trip.average_speed()) + " roads not being straight."),
	])


func _save_hours() -> void:
	var hours := {}
	for day: String in Stops.DAYS:
		var v: String = _hour_fields[day].text.strip_edges()
		if v != "":
			hours[day] = v
	_patch({"hours": hours})


func _patch(fields: Dictionary) -> void:
	_stop = Logbook.update_event(String(_stop.get("id", "")), fields)


## Fetch a stop's picture into the trip's media folder. Deliberately a USER
## priority request: you asked for it, so it goes out even on cellular — but
## it is one 40 KB image, not a map corridor.
static func download_photo(stop: Dictionary, url: String) -> void:
	var id := String(stop.get("id", ""))
	Logbook.update_event(id, {"photo_pending": url})
	Net.fetch(url, func(ok: bool, _code: int, body: PackedByteArray) -> void:
		if not ok or body.is_empty():
			Logbook.update_event(id, {"photo_pending": ""})
			return
		var file := id + ".jpg"
		var path := Logbook.media_dir().path_join(file)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return
		f.store_buffer(body)
		f = null
		Logbook.update_event(id, {"photo": file, "photo_pending": ""}),
		Net.P_USER)
