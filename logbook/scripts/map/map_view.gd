class_name MapView extends Control
## The map. A slippy map drawn straight into a Control: raster tiles, the
## recorded track, event pins, the planned route, and a radar overlay.
##
## It is deliberately one `_draw()` rather than a scene full of nodes. A day's
## track is thousands of points and a trip is thousands of pins; as nodes that
## is a stuttering mess, as immediate-mode drawing it is a handful of
## milliseconds and it scrolls like a map should.
##
## The view is stored as (center in normalized Mercator, fractional zoom), so
## nothing in here has to know about tile grids except the code that actually
## asks for tiles.

signal view_changed
signal event_tapped(id: String)
signal cluster_tapped(ids: Array, at: Vector2)
signal map_tapped(latlon: Vector2)
signal map_long_pressed(latlon: Vector2)
signal follow_changed(following: bool)

const TILE_PX := 256.0
const MIN_ZOOM := 2.0
const LONG_PRESS_S := 0.55
const CLUSTER_PX := 44.0

@export var show_track := true
@export var show_events := true
@export var show_route := true
@export var interactive := true

var center := Vector2(0.5, 0.5)     ## Normalized Mercator.
var zoom := 13.0
var following := true               ## Keep me centered as fixes arrive.
var heading_up := false

var radar_frame := ""               ## Tile-source id of the radar frame to overlay, "" for none.
var radar_alpha := 0.55
var highlight_time := -1.0          ## Timeline scrub position; -1 = live.
var kind_filter: Array = []         ## Empty = show everything.

var _drag_id := -1
var _touches := {}                  ## touch index -> position
var _pinch_dist := 0.0
var _pinch_zoom := 0.0
var _velocity := Vector2.ZERO
var _last_drag_t := 0.0
var _press_pos := Vector2.ZERO
var _press_t := 0.0
var _moved := false
var _long_fired := false
var _clusters: Array = []           ## Rebuilt every draw; used for hit-testing.
var _font: Font
var _font_bold: Font


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_font = ThemeDB.fallback_font
	_font_bold = ThemeDB.fallback_font
	Tiles.tile_ready.connect(func(_k: String) -> void: queue_redraw())
	Logbook.fix_appended.connect(_on_fix)
	Logbook.event_appended.connect(func(_e: Dictionary) -> void: queue_redraw())
	Logbook.event_changed.connect(func(_e: Dictionary) -> void: queue_redraw())
	Logbook.trip_opened.connect(_center_on_track)
	Cfg.changed.connect(func(_k: String) -> void: queue_redraw())
	resized.connect(queue_redraw)
	_center_on_track()


func _process(delta: float) -> void:
	if _velocity.length_squared() > 1.0:
		_pan_pixels(_velocity * delta)
		# ~6% of the velocity survives each 60th of a second: a flick coasts
		# for about a second and stops without a visible snap.
		_velocity *= pow(0.06, delta)
		queue_redraw()
	if _drag_id != -1 and not _long_fired and not _moved:
		if Time.get_ticks_msec() / 1000.0 - _press_t > LONG_PRESS_S:
			_long_fired = true
			Bridge.vibrate(18)
			map_long_pressed.emit(screen_to_latlon(_press_pos))


func _on_fix(index: int) -> void:
	if following:
		var f := Logbook.fix_at(index)
		if not f.is_empty():
			center = Geo.to_norm(float(f["lat"]), float(f["lon"]))
	queue_redraw()


# ----------------------------------------------------------------- viewport


func _world_px() -> float:
	return TILE_PX * pow(2.0, zoom)


func norm_to_screen(n: Vector2) -> Vector2:
	return (n - center) * _world_px() + size * 0.5


func screen_to_norm(s: Vector2) -> Vector2:
	return center + (s - size * 0.5) / _world_px()


func latlon_to_screen(lat: float, lon: float) -> Vector2:
	return norm_to_screen(Geo.to_norm(lat, lon))


func screen_to_latlon(s: Vector2) -> Vector2:
	return Geo.from_norm(screen_to_norm(s))


func center_latlon() -> Vector2:
	return Geo.from_norm(center)


func set_center_latlon(lat: float, lon: float) -> void:
	center = Geo.to_norm(lat, lon)
	queue_redraw()
	view_changed.emit()


func set_follow(on: bool) -> void:
	if following == on:
		return
	following = on
	if on:
		var f := Logbook.last_fix()
		if not f.is_empty():
			set_center_latlon(float(f["lat"]), float(f["lon"]))
	follow_changed.emit(on)
	queue_redraw()


func zoom_by(delta_zoom: float, anchor: Vector2 = Vector2.INF) -> void:
	var at := anchor if anchor != Vector2.INF else size * 0.5
	var before := screen_to_norm(at)
	zoom = clampf(zoom + delta_zoom, MIN_ZOOM, float(TileSource.max_zoom(TileSource.current_id())) + 2.0)
	var after := screen_to_norm(at)
	# Keep the point under the fingers pinned where it was.
	center += before - after
	queue_redraw()
	view_changed.emit()


func fit_bounds(min_ll: Vector2, max_ll: Vector2, pad_px: float = 48.0) -> void:
	var a := Geo.to_norm(max_ll.x, min_ll.y)   # north-west
	var b := Geo.to_norm(min_ll.x, max_ll.y)   # south-east
	center = (a + b) * 0.5
	var span := (b - a).abs()
	var avail := (size - Vector2(pad_px, pad_px) * 2.0).max(Vector2(64, 64))
	var zx := log(avail.x / maxf(span.x, 1e-9) / TILE_PX) / log(2.0)
	var zy := log(avail.y / maxf(span.y, 1e-9) / TILE_PX) / log(2.0)
	zoom = clampf(minf(zx, zy), MIN_ZOOM, 18.0)
	queue_redraw()
	view_changed.emit()


func _center_on_track() -> void:
	var f := Logbook.last_fix()
	if f.is_empty():
		var known := Bridge.last_known()
		if known.has("lat"):
			center = Geo.to_norm(float(known["lat"]), float(known["lon"]))
		return
	center = Geo.to_norm(float(f["lat"]), float(f["lon"]))
	queue_redraw()


func _pan_pixels(px: Vector2) -> void:
	center -= px / _world_px()
	center.y = clampf(center.y, 0.0, 1.0)
	center.x = fposmod(center.x, 1.0)
	view_changed.emit()


# -------------------------------------------------------------------- input


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(0.35, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(-0.35, mb.position)
			accept_event()
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_on_key(event as InputEventKey)


func _on_key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_EQUAL, KEY_KP_ADD:
			zoom_by(0.5)
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_by(-0.5)
		KEY_LEFT:
			_pan_pixels(Vector2(80, 0))
		KEY_RIGHT:
			_pan_pixels(Vector2(-80, 0))
		KEY_UP:
			_pan_pixels(Vector2(0, 80))
		KEY_DOWN:
			_pan_pixels(Vector2(0, -80))
		_:
			return
	queue_redraw()


func _on_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_touches[t.index] = t.position
		if _touches.size() == 1:
			_drag_id = t.index
			_press_pos = t.position
			_press_t = Time.get_ticks_msec() / 1000.0
			_moved = false
			_long_fired = false
			_velocity = Vector2.ZERO
		elif _touches.size() == 2:
			var pts: Array = _touches.values()
			_pinch_dist = (pts[0] as Vector2).distance_to(pts[1] as Vector2)
			_pinch_zoom = zoom
	else:
		_touches.erase(t.index)
		if t.index == _drag_id:
			_drag_id = -1
			if not _moved and not _long_fired:
				_tap(t.position)
		if _touches.size() < 2:
			_pinch_dist = 0.0


func _on_drag(d: InputEventScreenDrag) -> void:
	_touches[d.index] = d.position
	if _touches.size() >= 2 and _pinch_dist > 0.0:
		var pts: Array = _touches.values()
		var now := (pts[0] as Vector2).distance_to(pts[1] as Vector2)
		if now > 8.0:
			var mid: Vector2 = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
			var want := _pinch_zoom + log(now / _pinch_dist) / log(2.0)
			zoom_by(want - zoom, mid)
		_moved = true
		return
	if d.index != _drag_id:
		return
	if d.relative.length() > 3.0:
		if not _moved and following:
			# Any real pan is a statement of intent: stop chasing the rider.
			set_follow(false)
		_moved = true
	_pan_pixels(d.relative)
	var now_t := Time.get_ticks_msec() / 1000.0
	var dt := maxf(0.001, now_t - _last_drag_t)
	_last_drag_t = now_t
	_velocity = _velocity.lerp(d.relative / dt, 0.4)
	queue_redraw()


func _tap(pos: Vector2) -> void:
	for c in _clusters:
		if (c["pos"] as Vector2).distance_to(pos) <= CLUSTER_PX * 0.5:
			var ids: Array = c["ids"]
			if ids.size() == 1:
				event_tapped.emit(String(ids[0]))
			else:
				cluster_tapped.emit(ids, c["pos"])
			return
	map_tapped.emit(screen_to_latlon(pos))


# --------------------------------------------------------------------- draw


func _draw() -> void:
	var pal := _palette()
	draw_rect(Rect2(Vector2.ZERO, size), pal["bg"])
	_draw_tiles()
	if radar_frame != "":
		_draw_radar()
	if show_route:
		_draw_planned_route(pal)
	if show_track:
		_draw_track(pal)
	if show_events:
		_draw_markers()
	_draw_position()
	_draw_scale_bar(pal)
	_draw_attribution(pal)


func _palette() -> Dictionary:
	if Cfg.get_b("night_mode"):
		return {
			"bg": Color(0.05, 0.05, 0.07),
			"tile_mod": Color(0.55, 0.45, 0.45),
			"track": Color(1.0, 0.55, 0.35),
			"track_glow": Color(1.0, 0.35, 0.2, 0.25),
			"route": Color(0.5, 0.6, 0.9, 0.75),
			"text": Color(0.9, 0.8, 0.75),
			"shadow": Color(0, 0, 0, 0.8),
		}
	return {
		"bg": Color(0.82, 0.82, 0.80),
		"tile_mod": Color(1, 1, 1),
		"track": Color(0.85, 0.15, 0.35),
		"track_glow": Color(1.0, 0.3, 0.4, 0.22),
		"route": Color(0.15, 0.35, 0.85, 0.7),
		"text": Color(0.1, 0.1, 0.12),
		"shadow": Color(1, 1, 1, 0.75),
	}


func _draw_tiles() -> void:
	var src := TileSource.current_id()
	var maxz := TileSource.max_zoom(src)
	var z := clampi(int(floor(zoom)), 0, maxz)
	var scale := pow(2.0, zoom - float(z))
	var px := TILE_PX * scale
	var span := 1 << z
	var nw := screen_to_norm(Vector2.ZERO) * float(span)
	var se := screen_to_norm(size) * float(span)
	var x0 := int(floor(nw.x)) - 1
	var x1 := int(floor(se.x)) + 1
	var y0 := maxi(0, int(floor(nw.y)) - 1)
	var y1 := mini(span - 1, int(floor(se.y)) + 1)
	# Only ask the network for tiles when we are actually online and the tile
	# is on screen; everything else comes from disk or is drawn coarser.
	var allow_net := Net.allowed(Net.P_NORMAL)
	var mod: Color = _palette()["tile_mod"]
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var wrapped := ((tx % span) + span) % span
			var origin := norm_to_screen(Vector2(float(tx) / span, float(ty) / span))
			var rect := Rect2(origin, Vector2(px, px) * 1.002)  # hairline overlap
			var tex := Tiles.request(src, z, wrapped, ty, allow_net)
			if tex != null:
				draw_texture_rect(tex, rect, false, mod)
			else:
				_draw_parent_tile(src, z, wrapped, ty, rect, mod)


## Missing tile: borrow the matching quadrant of an ancestor that is already
## decoded. That is what stops a pan into unseen territory from flashing grey.
func _draw_parent_tile(src: String, z: int, x: int, y: int, rect: Rect2, mod: Color) -> void:
	var px := x
	var py := y
	for up in range(1, 6):
		var pz := z - up
		if pz < 0:
			return
		px >>= 1
		py >>= 1
		var tex := Tiles.request(src, pz, px, py, false)
		if tex == null:
			continue
		var f := 1 << up
		var sub := TILE_PX / float(f)
		var ox := float(x - (px << up)) * sub
		var oy := float(y - (py << up)) * sub
		draw_texture_rect_region(tex, rect, Rect2(ox, oy, sub, sub), mod * Color(1, 1, 1, 0.9))
		return


func _draw_radar() -> void:
	var z := clampi(int(floor(zoom)), 0, 9)   # radar tiles are coarse by nature
	var scale := pow(2.0, zoom - float(z))
	var px := TILE_PX * scale
	var span := 1 << z
	var nw := screen_to_norm(Vector2.ZERO) * float(span)
	var se := screen_to_norm(size) * float(span)
	var mod := Color(1, 1, 1, radar_alpha)
	for ty in range(maxi(0, int(floor(nw.y))), mini(span, int(floor(se.y)) + 1)):
		for tx in range(int(floor(nw.x)), int(floor(se.x)) + 1):
			var wrapped := ((tx % span) + span) % span
			var tex := Tiles.request(radar_frame, z, wrapped, ty, Net.allowed(Net.P_NORMAL))
			if tex == null:
				continue
			var origin := norm_to_screen(Vector2(float(tx) / span, float(ty) / span))
			draw_texture_rect(tex, Rect2(origin, Vector2(px, px) * 1.002), false, mod)


func _draw_track(pal: Dictionary) -> void:
	# Simplify to roughly two pixels at the current zoom: finer than that is
	# invisible and costs draw time.
	var lat := center_latlon().x
	var tol := Geo.meters_per_pixel(lat, zoom) * 2.0
	var segs := Logbook.track_segments(tol)
	for seg in segs:
		var pts: PackedVector2Array = seg
		if pts.size() < 2:
			continue
		var screen := PackedVector2Array()
		screen.resize(pts.size())
		for i in pts.size():
			screen[i] = latlon_to_screen(pts[i].x, pts[i].y)
		if not _touches_view(screen):
			continue
		draw_polyline(screen, pal["track_glow"], 9.0, true)
		draw_polyline(screen, pal["track"], 3.5, true)


func _draw_planned_route(pal: Dictionary) -> void:
	var route: Array = Logbook.meta.get("route", [])
	if route.size() < 2:
		return
	var screen := PackedVector2Array()
	for p in route:
		var pt: Array = p
		screen.push_back(latlon_to_screen(float(pt[0]), float(pt[1])))
	if not _touches_view(screen):
		return
	# Dashed, so the plan never gets confused with where you actually went.
	for i in range(0, screen.size() - 1):
		var a := screen[i]
		var b := screen[i + 1]
		var dist := a.distance_to(b)
		var dir := (b - a).normalized()
		var walked := 0.0
		while walked < dist:
			var seg := minf(10.0, dist - walked)
			draw_line(a + dir * walked, a + dir * (walked + seg), pal["route"], 3.0, true)
			walked += 18.0


func _touches_view(pts: PackedVector2Array) -> bool:
	var view := Rect2(Vector2(-64, -64), size + Vector2(128, 128))
	for p in pts:
		if view.has_point(p):
			return true
	return false


## Pins, clustered on a pixel grid so a rest stop with forty photos is one
## badge instead of a pile you cannot tap.
func _draw_markers() -> void:
	_clusters.clear()
	var cells := {}
	var view := Rect2(Vector2(-40, -40), size + Vector2(80, 80))
	var minor_ok := zoom >= 14.0
	for e in Logbook.events:
		var kind := String(e.get("kind", ""))
		if not kind_filter.is_empty() and not kind_filter.has(kind):
			continue
		if Ev.is_minor(kind) and not minor_ok:
			continue
		if not e.has("lat"):
			continue
		var p := latlon_to_screen(float(e["lat"]), float(e["lon"]))
		if not view.has_point(p):
			continue
		var cell := Vector2i((p / CLUSTER_PX).floor())
		if not cells.has(cell):
			cells[cell] = {"pos": p, "ids": [], "kinds": {}, "sum": Vector2.ZERO}
		var c: Dictionary = cells[cell]
		c["ids"].push_back(String(e.get("id", "")))
		c["kinds"][kind] = int(c["kinds"].get(kind, 0)) + 1
		c["sum"] = (c["sum"] as Vector2) + p
	for cell: Vector2i in cells.keys():
		var c: Dictionary = cells[cell]
		var ids: Array = c["ids"]
		c["pos"] = (c["sum"] as Vector2) / float(ids.size())
		_clusters.push_back(c)
		_draw_pin(c)


func _draw_pin(c: Dictionary) -> void:
	var pos: Vector2 = c["pos"]
	var ids: Array = c["ids"]
	var kinds: Dictionary = c["kinds"]
	var top := ""
	var best := -1
	for k: String in kinds.keys():
		if int(kinds[k]) > best:
			best = int(kinds[k])
			top = k
	var col := Ev.color(top)
	var r := 13.0 if ids.size() == 1 else 17.0
	draw_circle(pos + Vector2(1, 2), r, Color(0, 0, 0, 0.35))
	draw_circle(pos, r, Color(0.12, 0.12, 0.14, 0.92))
	draw_arc(pos, r, 0, TAU, 24, col, 2.5, true)
	var text := Ev.glyph(top) if ids.size() == 1 else str(ids.size())
	var fsize := 15 if ids.size() == 1 else 13
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(_font, pos + Vector2(-w * 0.5, fsize * 0.38), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## Where I am — or, when the timeline is scrubbed, where I was.
func _draw_position() -> void:
	var f := Logbook.last_fix()
	if f.is_empty():
		return
	var lat := float(f["lat"])
	var lon := float(f["lon"])
	var hdg := float(f["hdg"])
	var live := highlight_time < 0.0
	if not live:
		var p := Logbook.latlon_at_time(highlight_time)
		if p == Vector2.INF:
			return
		lat = p.x
		lon = p.y
		var i := Logbook.index_at_time(highlight_time)
		if i >= 0:
			hdg = Logbook.hdgs[i]
	var pos := latlon_to_screen(lat, lon)
	var acc_px := float(f.get("acc", 0.0)) / maxf(0.01, Geo.meters_per_pixel(lat, zoom))
	if live and acc_px > 8.0 and acc_px < 400.0:
		draw_circle(pos, acc_px, Color(0.2, 0.5, 1.0, 0.12))
		draw_arc(pos, acc_px, 0, TAU, 32, Color(0.2, 0.5, 1.0, 0.35), 1.5, true)
	var col := Color(0.15, 0.55, 1.0) if live else Color(0.95, 0.75, 0.2)
	# A chevron rather than a dot: heading is the thing you glance for.
	var a := deg_to_rad(hdg - 90.0)
	var tip := pos + Vector2(cos(a), sin(a)) * 15.0
	var l := pos + Vector2(cos(a + 2.5), sin(a + 2.5)) * 12.0
	var r := pos + Vector2(cos(a - 2.5), sin(a - 2.5)) * 12.0
	draw_colored_polygon(PackedVector2Array([tip, l, pos, r]), col)
	draw_circle(pos, 5.0, Color(1, 1, 1, 0.95))
	draw_arc(pos, 5.0, 0, TAU, 16, col, 2.0, true)


func _draw_scale_bar(pal: Dictionary) -> void:
	var lat := center_latlon().x
	var mpp := Geo.meters_per_pixel(lat, zoom)
	var metric := Cfg.is_metric()
	var target_px := minf(160.0, size.x * 0.35)
	var meters := mpp * target_px
	var nice := _nice_distance(meters, metric)
	var px := nice / mpp
	var y := size.y - 16.0
	var x := 12.0
	draw_line(Vector2(x, y), Vector2(x + px, y), pal["shadow"], 4.0)
	draw_line(Vector2(x, y), Vector2(x + px, y), pal["text"], 2.0)
	draw_line(Vector2(x, y - 5), Vector2(x, y + 5), pal["text"], 2.0)
	draw_line(Vector2(x + px, y - 5), Vector2(x + px, y + 5), pal["text"], 2.0)
	draw_string(_font, Vector2(x + 4, y - 8), Geo.format_distance(nice, metric),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, pal["text"])


func _nice_distance(meters: float, metric: bool) -> float:
	var unit := 1.0 if metric else Geo.METERS_PER_MILE
	var v := meters / unit
	var steps := [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500]
	for s in steps:
		if v <= float(s):
			return float(s) * unit
	return 1000.0 * unit


func _draw_attribution(pal: Dictionary) -> void:
	var text := TileSource.attribution(TileSource.current_id())
	if text == "":
		return
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var pos := Vector2(size.x - w - 8, size.y - 6)
	draw_string(_font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pal["shadow"])
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pal["text"])
