class_name SettingsPanel extends Sheet
## Everything else: what gets logged, what the map does offline, how much
## cellular data the app is allowed to spend, and how to get the trip out.

var _map: MapView
var _prefetch_status: Label


func _init(map: MapView) -> void:
	super("Settings")
	_map = map


func _ready() -> void:
	_build()
	Prefetch.progress.connect(func(_d: int, _t: int, _b: int) -> void: _update_prefetch())
	Tiles.offline_stats_changed.connect(_update_prefetch)


func _build() -> void:
	clear()
	_section("TRIP")
	body.add_child(UI.card([
		UI.label(Logbook.trip_name(), 18),
		UI.dim("%s · %d days · %d entries · %d fixes"
			% [Cfg.dist(Logbook.total_m), maxi(1, Logbook.days().size()),
			Logbook.events.size(), Logbook.fix_count()]),
		UI.row([
			UI.button("Export GPX + journal", _export),
			UI.button("New trip", _new_trip),
		]),
	]))
	_trip_list()

	_section("LOGGING")
	body.add_child(UI.toggle("Log my position", "gps_enabled", func(on: bool) -> void:
		if on:
			Trip.start()
		else:
			Trip.stop()))
	body.add_child(UI.toggle("Keep logging with the screen off", "gps_background",
		func(_v: bool) -> void: Bridge.configure_service()))
	body.add_child(UI.slider("gps_min_seconds", 1.0, 30.0, 1.0, "%.0f s"))
	body.add_child(UI.slider("gps_min_meters", 2.0, 100.0, 1.0, "%.0f m"))
	body.add_child(UI.slider("gps_max_accuracy_m", 10.0, 200.0, 5.0, "%.0f m"))
	body.add_child(UI.dim("A fix is kept when it is this far apart in time AND"
		+ " distance — or after " + "%.0f s" % Cfg.get_f("gps_idle_seconds")
		+ " standing still. Tighter settings cost battery and disk, not accuracy."))
	body.add_child(_service_state())

	_section("WHAT ELSE GETS LOGGED")
	body.add_child(UI.toggle("Phone calls", "capture_calls"))
	body.add_child(UI.toggle("Messenger activity", "capture_messages"))
	body.add_child(UI.toggle("...including message text", "capture_message_bodies"))
	body.add_child(UI.dim("Message text is off by default: the sender, the app, and the"
		+ " time are enough to remember a conversation, and the rest is other"
		+ " people's words. Nothing logged here ever leaves the phone."))
	body.add_child(UI.toggle("Photos taken", "capture_photos"))
	body.add_child(UI.toggle("Music", "capture_music"))
	body.add_child(UI.button("Notification access…", func() -> void:
		Bridge.open_notification_access_settings()))

	_section("MAP")
	_tile_sources()
	body.add_child(UI.toggle("Night colours", "night_mode", func(_v: bool) -> void:
		_map.queue_redraw()))
	body.add_child(UI.toggle("Miles → kilometres", "metric", func(_v: bool) -> void:
		_map.queue_redraw()))
	body.add_child(UI.slider("map_cache_budget_mb", 200.0, 20000.0, 100.0, "%.0f MB"))

	_section("OFFLINE MAP")
	_offline_block()

	_section("DATA")
	body.add_child(UI.toggle("Download on cellular", "download_on_cellular"))
	body.add_child(UI.slider("cellular_budget_mb_day", 5.0, 500.0, 5.0, "%.0f MB/day"))
	body.add_child(UI.slider("weather_poll_minutes", 5.0, 120.0, 5.0, "%.0f min"))
	body.add_child(UI.toggle("Radar", "radar_enabled"))
	body.add_child(UI.dim("Used today: %s (%s on cellular)"
		% [UI.bytes_human(Net.bytes_today), UI.bytes_human(Net.metered_bytes_today)]))

	_section("KEYS")
	body.add_child(UI.dim("Google API key — optional, for Street View stop photos", 12))
	body.add_child(UI.text_field("google_api_key", "AIza…"))
	body.add_child(UI.dim("Tile key — for a keyed tile provider ({key} in the URL)", 12))
	body.add_child(UI.text_field("tile_api_key"))

	_section("WRITING")
	body.add_child(UI.toggle("Show the on-screen keyboard", "onscreen_keyboard"))
	body.add_child(UI.slider("font_scale", 0.8, 1.6, 0.05, "%.2f×"))
	body.add_child(UI.dim("A bluetooth keyboard works everywhere in the app. Shortcuts:"
		+ " J journal · N new note · D days · P stops · W weather · B bike ·"
		+ " L live · space play/pause · [ ] skip track · esc close."))

	_section("ABOUT")
	body.add_child(UI.dim("Trip Logbook — everything is stored on this phone, in"
		+ " append-only files under the app's data directory. The only network"
		+ " traffic is map tiles, weather, and stop photos."))
	body.add_child(UI.dim("Logging back end: %s" % ("background service"
		if Bridge.has_native() else "in-app (simulated sensors)"), 12))


func _section(name: String) -> void:
	body.add_child(UI.separator())
	body.add_child(UI.dim(name, 11))


func _service_state() -> Control:
	if Bridge.has_native():
		return UI.card([
			UI.label("Background service: %s" % ("running" if Bridge.service_running()
				else "stopped"), 15, UI.GOOD if Bridge.service_running() else UI.WARN),
			UI.dim("The service keeps logging with the app closed and the phone"
				+ " locked. The app reads what it writes."),
		])
	return UI.card([
		UI.label("No background service", 15, UI.WARN),
		UI.dim("This build has no Android plugin, so sensors are simulated and"
			+ " logging only runs while the app is open. Build with"
			+ " android/plugin included to get the real thing."),
	])


func _trip_list() -> void:
	var trips := Logbook.list_trips()
	if trips.size() <= 1:
		return
	for t in trips:
		var id := String(t.get("id", ""))
		if id == Logbook.trip_id:
			continue
		body.add_child(UI.button("Open “%s”" % String(t.get("name", id)), func() -> void:
			Logbook.open_trip(id)
			Bridge.configure_service()
			_build()))


func _new_trip() -> void:
	var field := LineEdit.new()
	field.placeholder_text = "Name this trip"
	field.custom_minimum_size.y = UI.TOUCH
	body.add_child(field)
	body.add_child(UI.button("Start it", func() -> void:
		Logbook.new_trip(field.text if field.text != "" else "New trip")
		Bridge.configure_service()
		_build(), true))


func _export() -> void:
	var out := Exporter.export_all()
	body.add_child(UI.card([
		UI.label("Exported", 16, UI.GOOD),
		UI.dim(ProjectSettings.globalize_path(out), 12),
		UI.dim("track.gpx · journal.md · events.csv", 12),
	]))


func _tile_sources() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for id: String in TileSource.SOURCES.keys():
		var b := UI.button(String(TileSource.SOURCES[id]["name"]), func() -> void:
			Cfg.set_value("tile_source", id)
			_map.queue_redraw()
			_build())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if TileSource.current_id() == id:
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.ACCENT.darkened(0.3), 8))
		row.add_child(b)
	body.add_child(row)
	if TileSource.current_id() == "custom":
		body.add_child(UI.text_field("tile_custom_url",
			"https://tiles.example.com/{z}/{x}/{y}.png?key={key}"))
		body.add_child(UI.text_field("tile_custom_attribution", "Attribution line"))


func _offline_block() -> void:
	var summary := Tiles.offline_summary()
	_prefetch_status = UI.label(Prefetch.status_line(), 15)
	body.add_child(UI.card([
		_prefetch_status,
		UI.dim("Stored offline: %d tiles, %s. Browsing cache: %s"
			% [int(summary["tiles"]), UI.bytes_human(int(summary["bytes"])),
			UI.bytes_human(int(summary["cache_bytes"]))]),
	]))
	body.add_child(UI.slider("map_corridor_km", 1.0, 25.0, 0.5, "%.1f km corridor"))
	body.add_child(UI.slider("map_prefetch_zoom_max", 10.0, 17.0, 1.0, "to zoom %.0f"))
	if TileSource.bulk_source_id() == "":
		body.add_child(UI.label("The selected tile source does not allow bulk download.",
			15, UI.WARN))
		body.add_child(UI.dim("OpenStreetMap's tile servers are donated and their usage"
			+ " policy forbids downloading areas in advance — doing it anyway gets"
			+ " you blocked. Point “Custom” at your own tile server or a provider"
			+ " you have a key with, and the corridor download below works."))
		return
	body.add_child(UI.row([
		UI.button("Plan from my track", func() -> void: _plan(_track_route())),
		UI.button("Plan from route", func() -> void: _plan(Logbook.meta.get("route", []))),
	]))
	body.add_child(UI.row([
		UI.button("Start" if not Prefetch.running else "Pause", func() -> void:
			if Prefetch.running:
				Prefetch.pause()
			else:
				Prefetch.start()
			_build(), true),
		UI.button("Cancel", func() -> void:
			Prefetch.cancel()
			_build()),
		UI.button("Clear offline map", func() -> void:
			Tiles.clear_offline()
			_build()),
	]))


## Use the track you have already ridden as the route. On a there-and-back or
## a multi-day leg this is usually what you want tomorrow's map to cover.
func _track_route() -> Array:
	var route: Array = []
	var segs := Logbook.track_segments(400.0)
	for seg in segs:
		for p in seg:
			route.push_back([p.x, p.y])
	return route


func _plan(route: Array) -> void:
	var r := Prefetch.plan_route(route, Cfg.get_i("map_prefetch_zoom_min"),
		Cfg.get_i("map_prefetch_zoom_max"), Cfg.get_f("map_corridor_km"))
	if r.has("error"):
		body.add_child(UI.label(String(r["error"]), 14, UI.WARN))
		return
	body.add_child(UI.card([
		UI.label("%d tiles to fetch" % int(r["tiles"]), 16),
		UI.dim("about %s · %d already stored"
			% [UI.bytes_human(int(r["estimate_bytes"])), int(r["already_have"])]),
		UI.dim("Downloads on wifi only unless you allow cellular above."),
	]))


func _update_prefetch() -> void:
	if _prefetch_status != null and is_instance_valid(_prefetch_status):
		_prefetch_status.text = Prefetch.status_line()
