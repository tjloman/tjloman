extends Node
## Autoload `Prefetch`: downloads the map you will need before you are
## somewhere you cannot download it.
##
## Given a route, it works out every tile within a corridor around it and
## pulls them into the pinned offline store. The corridor narrows as the zoom
## goes up — you want the whole county at z9 for context and only a few miles
## either side of the road at z14, because that is where the tile count
## explodes. A 2,000-mile route is a few hundred megabytes done this way, and
## tens of gigabytes done naively.
##
## It survives being closed and reopened: the plan is a flat list of tile
## coordinates on disk plus a cursor, so an interrupted download resumes
## exactly where the radio dropped instead of starting over.

signal progress(done: int, total: int, bytes: int)
signal finished(completed: bool)
signal plan_changed

const PLAN_PATH := "user://prefetch.bin"
const STATE_PATH := "user://prefetch.json"
const BYTES_PER_TILE := 18000     ## Rough average for raster street tiles.
const IN_FLIGHT := 8

var running := false
var source := ""
var total := 0
var done := 0
var bytes := 0
var failed := 0

var _plan := PackedInt32Array()    ## Flat z,x,y triples.
var _cursor := 0
var _outstanding := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_state()


func _process(_delta: float) -> void:
	if running:
		_pump()


# -------------------------------------------------------------------- plan


## Enumerate the tiles for a route. `route` is [[lat, lon], ...] — the planned
## line, or the track you already rode if you want the map behind you too.
func plan_route(route: Array, zmin: int, zmax: int, corridor_km: float) -> Dictionary:
	var src := TileSource.bulk_source_id()
	if src == "":
		return {"error": "The current tile source does not allow bulk download. "
			+ "Set a self-hosted or keyed source in Settings → Map."}
	if route.size() < 2:
		return {"error": "No route to prefetch. Draw or import one first."}
	var sink := {}
	for z in range(maxi(0, zmin), mini(zmax, TileSource.max_zoom(src)) + 1):
		_collect_zoom(route, z, _corridor_for(z, corridor_km), sink)
	var flat := PackedInt32Array()
	var have := 0
	for key: String in sink.keys():
		var t: Vector3i = sink[key]
		if Tiles.have_tile(src, t.x, t.y, t.z):
			have += 1
			continue
		flat.push_back(t.x)
		flat.push_back(t.y)
		flat.push_back(t.z)
	source = src
	_plan = flat
	_cursor = 0
	total = flat.size() / 3
	done = 0
	bytes = 0
	failed = 0
	_save_plan()
	_save_state()
	plan_changed.emit()
	return {
		"tiles": total,
		"already_have": have,
		"estimate_bytes": total * BYTES_PER_TILE,
		"source": src,
	}


## Wide at low zoom, tight at high zoom. Doubling the zoom quadruples the
## tiles, so the corridor has to halve just to keep the count sane.
func _corridor_for(z: int, base_km: float) -> float:
	return clampf(base_km * pow(2.0, 13.0 - float(z)), base_km * 0.5, 60.0)


func _collect_zoom(route: Array, z: int, corridor_km: float, sink: Dictionary) -> void:
	var radius_m := corridor_km * 1000.0
	for i in route.size() - 1:
		var a := Vector2(float(route[i][0]), float(route[i][1]))
		var b := Vector2(float(route[i + 1][0]), float(route[i + 1][1]))
		var seg := Geo.distance_m(a.x, a.y, b.x, b.y)
		if seg <= 0.0:
			continue
		# One sample per half-corridor keeps the discs overlapping, so the
		# covered strip has no gaps between samples.
		var step := maxf(radius_m * 0.5, 200.0)
		var n := maxi(1, int(ceil(seg / step)))
		for k in n + 1:
			var f := float(k) / float(n)
			var p := a.lerp(b, f)
			_disc(p.x, p.y, z, radius_m, sink)


func _disc(lat: float, lon: float, z: int, radius_m: float, sink: Dictionary) -> void:
	var tile_m := Geo.meters_per_norm(lat) / float(1 << z)
	if tile_m <= 0.0:
		return
	var r := int(ceil(radius_m / tile_m))
	var c := Geo.to_tile(lat, lon, z)
	var cx := int(floor(c.x))
	var cy := int(floor(c.y))
	var span := 1 << z
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r + r:
				continue   # round corridor, not a square one
			var x := cx + dx
			var y := cy + dy
			if y < 0 or y >= span:
				continue
			x = ((x % span) + span) % span
			sink["%d/%d/%d" % [z, x, y]] = Vector3i(z, x, y)


func estimate_only(route: Array, zmin: int, zmax: int, corridor_km: float) -> Dictionary:
	var saved_plan := _plan
	var saved_cursor := _cursor
	var saved_total := total
	var r := plan_route(route, zmin, zmax, corridor_km)
	if r.has("error"):
		_plan = saved_plan
		_cursor = saved_cursor
		total = saved_total
	return r


# ------------------------------------------------------------------ running


func start() -> void:
	if total <= 0 or _cursor >= _plan.size():
		return
	running = true
	_save_state()


func pause() -> void:
	running = false
	Net.cancel_bulk()
	_save_state()


func cancel() -> void:
	running = false
	Net.cancel_bulk()
	_plan = PackedInt32Array()
	_cursor = 0
	total = 0
	done = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAN_PATH))
	_save_state()
	plan_changed.emit()
	finished.emit(false)


func remaining() -> int:
	return maxi(0, (_plan.size() - _cursor) / 3)


func _pump() -> void:
	if not Net.allowed(Net.P_BULK):
		return   # waiting for wifi, or the day's budget is spent
	while _outstanding < IN_FLIGHT and _cursor + 2 < _plan.size():
		var z := _plan[_cursor]
		var x := _plan[_cursor + 1]
		var y := _plan[_cursor + 2]
		_cursor += 3
		if Tiles.have_tile(source, z, x, y):
			done += 1
			continue
		var url := TileSource.url_for(source, z, x, y)
		if url == "":
			done += 1
			continue
		_outstanding += 1
		Net.fetch(url, _on_tile.bind(z, x, y), Net.P_BULK)
	if _cursor >= _plan.size() and _outstanding == 0:
		running = false
		_save_state()
		finished.emit(failed == 0)


func _on_tile(ok: bool, _code: int, body: PackedByteArray, z: int, x: int, y: int) -> void:
	_outstanding -= 1
	done += 1
	if ok and not body.is_empty():
		Tiles.store_offline(source, z, x, y, body)
		bytes += body.size()
	else:
		failed += 1
	if done % 25 == 0:
		_save_state()
	progress.emit(done, total, bytes)


# --------------------------------------------------------------- persistence


func _save_plan() -> void:
	var f := FileAccess.open(PLAN_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_32(_plan.size())
	for v in _plan:
		f.store_32(v)


func _load_plan() -> void:
	if not FileAccess.file_exists(PLAN_PATH):
		return
	var f := FileAccess.open(PLAN_PATH, FileAccess.READ)
	if f == null:
		return
	var n := f.get_32()
	if n <= 0 or n > 40_000_000:
		return
	_plan = PackedInt32Array()
	_plan.resize(n)
	for i in n:
		_plan[i] = f.get_32()


func _save_state() -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"source": source, "cursor": _cursor, "total": total,
		"done": done, "bytes": bytes, "failed": failed, "running": running,
	}))


func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if typeof(v) != TYPE_DICTIONARY:
		return
	var d: Dictionary = v
	source = String(d.get("source", ""))
	_cursor = int(d.get("cursor", 0))
	total = int(d.get("total", 0))
	done = int(d.get("done", 0))
	bytes = int(d.get("bytes", 0))
	failed = int(d.get("failed", 0))
	if total > 0:
		_load_plan()
	# Deliberately not auto-resuming: coming back to the app on a cell link
	# should not silently start pulling a gigabyte. The button says "Resume".
	running = false


func status_line() -> String:
	if total <= 0:
		return "No offline map planned"
	if running:
		if not Net.allowed(Net.P_BULK):
			return "Paused — waiting for wifi (%d of %d tiles)" % [done, total]
		return "Downloading %d of %d — %.0f MB" % [done, total, bytes / 1048576.0]
	if done >= total:
		return "Offline map complete — %d tiles, %.0f MB" % [total, bytes / 1048576.0]
	return "Paused at %d of %d tiles" % [done, total]
