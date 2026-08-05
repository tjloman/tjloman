class_name EventSheet extends Sheet
## One entry, opened from the map, the timeline, or a day list.
##
## Every entry answers the same three questions in the same order — what,
## when, where — and then offers whatever that kind can do: play the memo,
## show the photo, edit the note, jump the map to it.

var _e: Dictionary
var _map: MapView


func _init(event: Dictionary, map: MapView) -> void:
	super(Ev.label(String(event.get("kind", ""))))
	_e = event
	_map = map


func _ready() -> void:
	var t := float(_e.get("t", 0.0))
	var kind := String(_e.get("kind", ""))
	body.add_child(UI.label(Ev.summary(_e), 18, Ev.color(kind)))
	body.add_child(UI.dim("%s · %s · day %d" % [UI.clock(t), UI.date_line(t), Logbook.day_number(t)]))

	if _e.has("lat"):
		var lat := float(_e["lat"])
		var lon := float(_e["lon"])
		var line := Geo.format_latlon(lat, lon)
		if bool(_e.get("placed_by_track", false)):
			line += "   (placed from the track)"
		body.add_child(UI.dim(line))
		body.add_child(UI.row([
			UI.button("Show on map", func() -> void:
				_map.set_follow(false)
				_map.set_center_latlon(lat, lon)
				_map.zoom = maxf(_map.zoom, 15.0)
				close()),
		]))

	match kind:
		Ev.NOTE:
			_build_note()
		Ev.PHOTO:
			_build_photo()
		Ev.AUDIO:
			body.add_child(UI.dim("Voice memo — %s" % String(_e.get("file", ""))))
		Ev.BATTERY:
			_build_battery()
		Ev.WEATHER:
			body.add_child(UI.label(String(_e.get("headline", "")), 15))
		Ev.CALL, Ev.MESSAGE, Ev.MUSIC:
			_build_simple_fields()

	body.add_child(UI.separator())
	body.add_child(UI.row([
		UI.button("Delete", _confirm_delete),
		UI.spacer(),
	]))


func _build_note() -> void:
	var edit := TextEdit.new()
	edit.text = String(_e.get("text", ""))
	edit.custom_minimum_size.y = 220
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.add_child(edit)
	body.add_child(UI.button("Save", func() -> void:
		Logbook.update_event(String(_e["id"]), {"text": edit.text})
		close(), true))


func _build_photo() -> void:
	var path := String(_e.get("file", ""))
	if path == "" or not FileAccess.file_exists(path):
		body.add_child(UI.dim("The picture lives in your camera roll; only its"
			+ " time and place are in the logbook."))
		return
	var img := Image.new()
	if img.load(path) != OK:
		body.add_child(UI.dim("Could not read %s" % path.get_file()))
		return
	# Thumbnail rather than the full 12-megapixel frame: the sheet only ever
	# shows it a few hundred pixels wide.
	var scale := minf(1.0, 900.0 / maxf(1.0, float(img.get_width())))
	img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(img)
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(rect)
	var caption := LineEdit.new()
	caption.text = String(_e.get("caption", ""))
	caption.placeholder_text = "Caption"
	caption.text_submitted.connect(func(v: String) -> void:
		Logbook.update_event(String(_e["id"]), {"caption": v}))
	body.add_child(caption)


func _build_battery() -> void:
	body.add_child(UI.row([
		UI.stat("charge", "%d%%" % int(float(_e.get("soc", 0)))),
		UI.stat("pack", "%.1f V" % float(_e.get("volts", 0.0))),
		UI.stat("current", "%.1f A" % float(_e.get("amps", 0.0))),
	], 18))


func _build_simple_fields() -> void:
	for key: String in ["who", "app", "artist", "album", "number", "direction", "text"]:
		if _e.has(key) and String(_e[key]) != "":
			body.add_child(UI.dim("%s: %s" % [key, String(_e[key])], 14))


func _confirm_delete() -> void:
	var confirm := UI.button("Really delete — this cannot be undone", func() -> void:
		Logbook.remove_event(String(_e.get("id", "")))
		close())
	confirm.add_theme_color_override("font_color", UI.DANGER)
	body.add_child(confirm)
