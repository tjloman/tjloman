extends Node
## Autoload `Logbook`: the durable store. Everything the trip produces —
## every GPS fix, note, photo, call, battery reading — lands here first and is
## on disk before anything else looks at it.
##
## Design constraints that shaped this file:
##
##   * The phone will die mid-write. Battery flat, rain in the port, a crash.
##     So the format is an append-only log of one-line records: a truncated
##     final line costs you that line and nothing else. There is no moment
##     where a rewrite could lose the trip.
##   * A thousands-of-miles trip is ~500k fixes. Re-parsing half a million
##     JSON lines at every launch would make the app feel broken, so a binary
##     snapshot (`track.bin`) is folded forward and only the un-snapshotted
##     tail of the text log is parsed on open.
##   * Nothing here touches the network, ever. This is your diary.
##
## Two writers, never the same file
## ---------------------------------
## On a phone the background service — not this process — is what keeps the
## journey logged while the app is closed, the screen is off, and the phone is
## face-down on a charger in the trailer. It owns the sensor files and appends
## to them whether Godot is running or not.
##
## So each file has exactly one writer, and this node changes role per file:
##
##   track.ndjson     service writes, app TAILS      one array per line:
##                                                   [t, lat, lon, alt, spd, hdg, acc]
##   sensor.ndjson    service writes, app TAILS      calls, messages, music,
##                                                   photos — anything the OS
##                                                   handed to the service
##   events.ndjson    app writes, service never      notes, waypoints, edits
##
## Tailing is a seek to the last byte offset we read and a scan of whatever
## is new — a few hundred bytes a second, no locking, no coordination, and
## correct even if the service was writing at the instant we read.
##
## With no service (desktop, or a build without the plugin) the app writes
## track.ndjson itself. The two modes are exclusive, which is what keeps the
## file single-writer in both.
##
## On disk, under `user://trips/<trip_id>/`:
##   trip.json      metadata: name, start, planned route and stops
##   track.ndjson   the track (see above)
##   track.bin      snapshot of the first N bytes of track.ndjson, pre-parsed
##   sensor.ndjson  service-authored events
##   events.ndjson  app-authored events
##   media/         photos and audio copied in, named by event id

signal fix_appended(index: int)
signal event_appended(event: Dictionary)
signal event_changed(event: Dictionary)
signal event_removed(id: String)
signal trip_opened

const ROOT := "user://trips"
const SNAPSHOT_MAGIC := 0x314B424C  ## "LBK1"
const BLOCK := 2048                 ## Fixes per cached display block.

## A jump larger than either of these starts a new drawn segment: an
## overnight, a train, a phone reboot in a tunnel. Drawing straight through
## them would put a 200-mile ruler across the map.
const GAP_SECONDS := 900.0
const GAP_METERS := 3000.0

var trip_id := ""
var trip_dir := ""
var meta := {}

# Parallel arrays, one entry per fix. Packed arrays keep half a million fixes
# in a few tens of megabytes and let the map slice them without allocating.
var times := PackedFloat64Array()
var lats := PackedFloat64Array()
var lons := PackedFloat64Array()
var alts := PackedFloat32Array()
var spds := PackedFloat32Array()
var hdgs := PackedFloat32Array()
var accs := PackedFloat32Array()

var events: Array[Dictionary] = []

var total_m := 0.0
var moving_seconds := 0.0
var climb_m := 0.0

## True when the background service owns the sensor files. Set by the bridge
## once it knows whether the plugin is there.
var service_mode := false

var _track_file: FileAccess
var _event_file: FileAccess
var _tail_track := 0            ## Bytes of track.ndjson already tailed.
var _tail_sensor := 0           ## ...and of sensor.ndjson.
var _tail_timer := 0.0
var _snapshot_bytes := 0        ## Bytes of track.ndjson already in track.bin.
var _unflushed := 0
var _breaks := PackedInt32Array()   ## Absolute fix indices that start a segment.
var _blocks: Array = []             ## Per-block {pts: PackedVector2Array, idx: PackedInt32Array}
var _blocks_tol := -1.0
var _day_cache := {}
var _events_by_id := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ROOT)
	var want := Cfg.get_s("trip_id")
	if want != "" and DirAccess.dir_exists_absolute(ROOT.path_join(want)):
		open_trip(want)
	else:
		var found := list_trips()
		if found.is_empty():
			new_trip("My ride")
		else:
			open_trip(String(found[0]["id"]))


## Tail whatever the service wrote while we were looking elsewhere. Once a
## second is plenty: at a fix every three seconds, that is a line at a time.
func _process(delta: float) -> void:
	if not service_mode:
		return
	_tail_timer -= delta
	if _tail_timer > 0.0:
		return
	_tail_timer = 1.0
	tail_service_files()


## Hand file ownership to the background service. From here on the app stops
## writing the track itself and only reads what the service appends.
func set_service_mode(on: bool) -> void:
	if service_mode == on:
		return
	service_mode = on
	if on:
		flush()
		_track_file = null
		_tail_track = _track_bytes_loaded()
		tail_service_files()
	else:
		_open_for_append()


func _track_bytes_loaded() -> int:
	var path := trip_dir.path_join("track.ndjson")
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	return int(f.get_length()) if f != null else 0


func tail_service_files() -> void:
	var before := times.size()
	_tail_track = _tail(trip_dir.path_join("track.ndjson"), _tail_track, _ingest_track_line)
	_tail_sensor = _tail(trip_dir.path_join("sensor.ndjson"), _tail_sensor, _ingest_event_line)
	if times.size() != before:
		fix_appended.emit(times.size() - 1)


## Read whole lines added since `offset`, and return the new offset. A
## half-written final line is left for next time by only consuming up to the
## last newline — that is what makes reading a file being appended to safe.
func _tail(path: String, offset: int, handler: Callable) -> int:
	if not FileAccess.file_exists(path):
		return offset
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return offset
	var size := int(f.get_length())
	if size < offset:
		return 0     # rotated or reset behind us: start over
	if size == offset:
		return offset
	f.seek(offset)
	var chunk := f.get_buffer(size - offset).get_string_from_utf8()
	var cut := chunk.rfind("\n")
	if cut < 0:
		return offset
	var complete := chunk.substr(0, cut)
	for line in complete.split("\n", false):
		handler.call(line)
	return offset + complete.to_utf8_buffer().size() + 1


func _ingest_track_line(line: String) -> void:
	if line.length() < 8:
		return
	var v: Variant = JSON.parse_string(line)
	if typeof(v) != TYPE_ARRAY or (v as Array).size() < 7:
		return
	var a: Array = v
	_ingest_fix(float(a[0]), float(a[1]), float(a[2]), float(a[3]),
		float(a[4]), float(a[5]), float(a[6]))


func _ingest_event_line(line: String) -> void:
	if line.length() < 4:
		return
	var v: Variant = JSON.parse_string(line)
	if typeof(v) != TYPE_DICTIONARY:
		return
	var e: Dictionary = v
	if _events_by_id.has(String(e.get("id", ""))):
		return
	_insert_event(e)
	event_appended.emit(e)


func _notification(what: int) -> void:
	# Android hands us these when the user swipes away or the screen locks.
	# Whatever is buffered goes to disk right now: there may not be a later.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		flush()
		if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
			write_snapshot()


# ------------------------------------------------------------------- trips


func list_trips() -> Array:
	var out := []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return out
	for name in dir.get_directories():
		var m := _read_json(ROOT.path_join(name).path_join("trip.json"))
		if m.is_empty():
			continue
		m["id"] = name
		out.push_back(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("started", 0.0)) > float(b.get("started", 0.0)))
	return out


func new_trip(name: String) -> String:
	var now := Time.get_unix_time_from_system()
	var id := Time.get_datetime_string_from_unix_time(int(now), false).replace(":", "").replace("-", "")
	id = id.replace("T", "-").substr(0, 13)
	var path := ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(path.path_join("media"))
	var m := {
		"name": name,
		"started": now,
		"rider": Cfg.get_s("rider_name"),
		"route": [],      ## Planned polyline, [[lat, lon], ...]
		"stops": [],      ## Planned stops (see stop_planner.gd)
		"version": 1,
	}
	_write_json(path.path_join("trip.json"), m)
	open_trip(id)
	return id


func open_trip(id: String) -> void:
	flush()
	write_snapshot()
	_close_files()
	trip_id = id
	trip_dir = ROOT.path_join(id)
	DirAccess.make_dir_recursive_absolute(trip_dir.path_join("media"))
	meta = _read_json(trip_dir.path_join("trip.json"))
	if meta.is_empty():
		meta = {"name": id, "started": Time.get_unix_time_from_system(), "route": [], "stops": []}
	Cfg.set_value("trip_id", id)
	_reset_memory()
	_load_track()
	_load_events()
	if service_mode:
		_tail_track = _track_bytes_loaded()
	else:
		_open_for_append()
	trip_opened.emit()


func save_meta() -> void:
	if trip_dir != "":
		_write_json(trip_dir.path_join("trip.json"), meta)


func trip_name() -> String:
	return String(meta.get("name", "Trip"))


func media_dir() -> String:
	return trip_dir.path_join("media")


func _reset_memory() -> void:
	times = PackedFloat64Array()
	lats = PackedFloat64Array()
	lons = PackedFloat64Array()
	alts = PackedFloat32Array()
	spds = PackedFloat32Array()
	hdgs = PackedFloat32Array()
	accs = PackedFloat32Array()
	events.clear()
	_events_by_id.clear()
	_breaks = PackedInt32Array()
	_blocks.clear()
	_blocks_tol = -1.0
	_day_cache.clear()
	_tail_track = 0
	_tail_sensor = 0
	total_m = 0.0
	moving_seconds = 0.0
	climb_m = 0.0
	_snapshot_bytes = 0


# ------------------------------------------------------------------ writing


## The one entry point for a position. Returns true if the fix was kept —
## callers use that to know whether their sampling policy actually recorded
## anything.
func append_fix(t: float, lat: float, lon: float, alt: float, spd: float,
		hdg: float, acc: float) -> bool:
	if is_nan(lat) or is_nan(lon) or absf(lat) > 90.0 or absf(lon) > 180.0:
		return false
	if service_mode:
		# The service is the writer; a fix arriving here is only for the live
		# display and will reach the arrays through the tail.
		return false
	_ingest_fix(t, lat, lon, alt, spd, hdg, acc)
	if _track_file != null:
		# 6 decimals of degree is ~0.1 m — finer than any consumer GPS, and it
		# keeps a day of riding around a megabyte.
		_track_file.store_line("[%.1f,%.6f,%.6f,%.1f,%.2f,%.1f,%.1f]" % [t, lat, lon, alt, spd, hdg, acc])
		_unflushed += 1
		if _unflushed >= 20:
			flush()
	fix_appended.emit(times.size() - 1)
	return true


## Append an event. `data` supplies the kind-specific keys; position and time
## default to "here, now".
func append_event(kind: String, data: Dictionary = {}) -> Dictionary:
	var e := data.duplicate(true)
	e["kind"] = kind
	if not e.has("t"):
		e["t"] = Time.get_unix_time_from_system()
	if not e.has("lat") or not e.has("lon"):
		var p := latlon_at_time(float(e["t"]))
		if p != Vector2.INF:
			e["lat"] = snappedf(p.x, 0.000001)
			e["lon"] = snappedf(p.y, 0.000001)
	if not e.has("id"):
		e["id"] = _make_id(kind, float(e["t"]))
	_insert_event(e)
	if _event_file != null:
		_event_file.store_line(JSON.stringify(e))
		_event_file.flush()
	event_appended.emit(e)
	return e


## Events are immutable on disk; an edit appends a new record with the same
## id and the reader keeps the last one it sees. Same append-only guarantee,
## and the history is recoverable from the raw file if you ever want it.
func update_event(id: String, patch: Dictionary) -> Dictionary:
	var e: Dictionary = _events_by_id.get(id, {})
	if e.is_empty():
		return {}
	for k: String in patch.keys():
		e[k] = patch[k]
	e["edited"] = Time.get_unix_time_from_system()
	if _event_file != null:
		_event_file.store_line(JSON.stringify(e))
		_event_file.flush()
	event_changed.emit(e)
	return e


func remove_event(id: String) -> void:
	var e: Dictionary = _events_by_id.get(id, {})
	if e.is_empty():
		return
	events.erase(e)
	_events_by_id.erase(id)
	if _event_file != null:
		_event_file.store_line(JSON.stringify({"id": id, "kind": "tombstone", "t": Time.get_unix_time_from_system()}))
		_event_file.flush()
	event_removed.emit(id)


func flush() -> void:
	if _track_file != null:
		_track_file.flush()
	if _event_file != null:
		_event_file.flush()
	_unflushed = 0


func has_event(id: String) -> bool:
	return _events_by_id.has(id)


func get_event(id: String) -> Dictionary:
	return _events_by_id.get(id, {})


func _make_id(kind: String, t: float) -> String:
	return "%s-%d-%04d" % [kind, int(t), randi() % 10000]


func _insert_event(e: Dictionary) -> void:
	var id := String(e.get("id", ""))
	if _events_by_id.has(id):
		var old: Dictionary = _events_by_id[id]
		events.erase(old)
	_events_by_id[id] = e
	var t := float(e.get("t", 0.0))
	# Events arrive in time order almost always (the exception is a call log
	# backfill after the phone was off), so scan from the end.
	var i := events.size()
	while i > 0 and float(events[i - 1].get("t", 0.0)) > t:
		i -= 1
	events.insert(i, e)


# ------------------------------------------------------------------ reading


func _open_for_append() -> void:
	var tp := trip_dir.path_join("track.ndjson")
	_track_file = FileAccess.open(tp, FileAccess.READ_WRITE) if FileAccess.file_exists(tp) \
		else FileAccess.open(tp, FileAccess.WRITE)
	if _track_file != null:
		_track_file.seek_end()
	var ep := trip_dir.path_join("events.ndjson")
	_event_file = FileAccess.open(ep, FileAccess.READ_WRITE) if FileAccess.file_exists(ep) \
		else FileAccess.open(ep, FileAccess.WRITE)
	if _event_file != null:
		_event_file.seek_end()


func _close_files() -> void:
	_track_file = null
	_event_file = null


func _load_track() -> void:
	_read_snapshot()
	var path := trip_dir.path_join("track.ndjson")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	if _snapshot_bytes > 0:
		if _snapshot_bytes <= int(f.get_length()):
			f.seek(_snapshot_bytes)
		else:
			# The log got shorter than the snapshot: it was reset or truncated
			# behind our back. Trust the text log, it is the source of truth.
			_reset_memory()
	while not f.eof_reached():
		var line := f.get_line()
		if line.length() < 8:
			continue
		var v: Variant = JSON.parse_string(line)
		if typeof(v) != TYPE_ARRAY or (v as Array).size() < 7:
			continue  # torn final line from a power cut — nothing else to do
		var a: Array = v
		_ingest_fix(float(a[0]), float(a[1]), float(a[2]), float(a[3]),
			float(a[4]), float(a[5]), float(a[6]))


func _load_events() -> void:
	_tail_sensor = _read_event_file(trip_dir.path_join("sensor.ndjson"))
	_read_event_file(trip_dir.path_join("events.ndjson"))


func _read_event_file(path: String) -> int:
	var path_size := 0
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	path_size = int(f.get_length())
	var tombstones := {}
	while not f.eof_reached():
		var line := f.get_line()
		if line.length() < 4:
			continue
		var v: Variant = JSON.parse_string(line)
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = v
		var id := String(e.get("id", ""))
		if String(e.get("kind", "")) == "tombstone":
			tombstones[id] = true
			continue
		_insert_event(e)
	for id: String in tombstones.keys():
		if _events_by_id.has(id):
			events.erase(_events_by_id[id])
			_events_by_id.erase(id)
	return path_size


## Fold a fix into the in-memory arrays and the running totals. Shared by the
## live path and by loading, so a reloaded trip has byte-identical stats.
func _ingest_fix(t: float, lat: float, lon: float, alt: float, spd: float,
		hdg: float, acc: float) -> void:
	var n := times.size()
	if n > 0:
		var dt := t - times[n - 1]
		var dm := Geo.distance_m(lats[n - 1], lons[n - 1], lat, lon)
		if dt > GAP_SECONDS or dm > GAP_METERS:
			_breaks.push_back(n)
		else:
			total_m += dm
			if dt > 0.0 and dt < 60.0:
				var v := dm / dt
				if v > Cfg.get_f("autopause_mps"):
					moving_seconds += dt
				# Barometric/GPS altitude is noisy; only count a real rise.
				var dz := alt - alts[n - 1]
				if dz > 1.5:
					climb_m += dz
	times.push_back(t)
	lats.push_back(lat)
	lons.push_back(lon)
	alts.push_back(alt)
	spds.push_back(spd)
	hdgs.push_back(hdg)
	accs.push_back(acc)
	# Only the tail block changes; everything before it stays cached.
	var b := n / BLOCK
	if b < _blocks.size():
		_blocks[b] = null
	_day_cache.clear()


# ---------------------------------------------------------------- snapshot


## Fold the text log into a pre-parsed binary blob so the next launch is
## instant. Written to a temp file and renamed: a snapshot is a cache, and a
## half-written cache must never look valid.
func write_snapshot() -> void:
	if trip_dir == "" or times.is_empty():
		return
	var log_path := trip_dir.path_join("track.ndjson")
	if not FileAccess.file_exists(log_path):
		return
	var size := 0
	var probe := FileAccess.open(log_path, FileAccess.READ)
	if probe == null:
		return
	size = int(probe.get_length())
	probe = null
	if size <= _snapshot_bytes:
		return
	var tmp := trip_dir.path_join("track.bin.tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_32(SNAPSHOT_MAGIC)
	f.store_64(size)
	f.store_64(times.size())
	for i in times.size():
		f.store_double(times[i])
		f.store_double(lats[i])
		f.store_double(lons[i])
		f.store_float(alts[i])
		f.store_float(spds[i])
		f.store_float(hdgs[i])
		f.store_float(accs[i])
	f = null
	var dir := DirAccess.open(trip_dir)
	if dir != null:
		dir.remove("track.bin")
		dir.rename("track.bin.tmp", "track.bin")
	_snapshot_bytes = size


func _read_snapshot() -> void:
	var path := trip_dir.path_join("track.bin")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 20:
		return
	if f.get_32() != SNAPSHOT_MAGIC:
		return
	var bytes := int(f.get_64())
	var count := int(f.get_64())
	if count < 0 or f.get_length() < 20 + count * 40:
		return  # truncated snapshot: ignore it, the text log rebuilds everything
	for i in count:
		_ingest_fix(f.get_double(), f.get_double(), f.get_double(),
			f.get_float(), f.get_float(), f.get_float(), f.get_float())
	_snapshot_bytes = bytes


# ------------------------------------------------------------------ queries


func fix_count() -> int:
	return times.size()


func last_fix() -> Dictionary:
	var n := times.size()
	if n == 0:
		return {}
	return fix_at(n - 1)


func fix_at(i: int) -> Dictionary:
	if i < 0 or i >= times.size():
		return {}
	return {
		"i": i, "t": times[i], "lat": lats[i], "lon": lons[i],
		"alt": alts[i], "spd": spds[i], "hdg": hdgs[i], "acc": accs[i],
	}


## Index of the last fix at or before `t` (-1 if the track starts later).
func index_at_time(t: float) -> int:
	var lo := 0
	var hi := times.size() - 1
	var best := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if times[mid] <= t:
			best = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return best


## Where was I at this moment? Interpolates between the bracketing fixes and
## returns Vector2.INF when the time is outside the track.
func latlon_at_time(t: float) -> Vector2:
	var n := times.size()
	if n == 0:
		return Vector2.INF
	var i := index_at_time(t)
	if i < 0:
		return Vector2(lats[0], lons[0])
	if i >= n - 1:
		return Vector2(lats[n - 1], lons[n - 1])
	var span := times[i + 1] - times[i]
	if span <= 0.0 or span > GAP_SECONDS:
		return Vector2(lats[i], lons[i])
	var f := clampf((t - times[i]) / span, 0.0, 1.0)
	return Vector2(lerpf(lats[i], lats[i + 1], f), lerpf(lons[i], lons[i + 1], f))


func events_between(t0: float, t1: float, kinds: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		var t := float(e.get("t", 0.0))
		if t < t0 or t > t1:
			continue
		if kinds.is_empty() or kinds.has(String(e.get("kind", ""))):
			out.push_back(e)
	return out


func events_of_kind(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if String(e.get("kind", "")) == kind:
			out.push_back(e)
	return out


func latest_of_kind(kind: String) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		if String(events[i].get("kind", "")) == kind:
			return events[i]
	return {}


func start_time() -> float:
	if not times.is_empty():
		return times[0]
	return float(meta.get("started", Time.get_unix_time_from_system()))


func end_time() -> float:
	if not times.is_empty():
		return times[times.size() - 1]
	return start_time()


# --------------------------------------------------------------- day stats


## Local-day key ("2026-08-05") for a timestamp, using the phone's current
## time zone. On a trip that crosses zones the past re-keys itself when you
## move — which is what you want: "what did I do on Tuesday" should mean
## Tuesday where you are now.
static func day_key(t: float) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	return Time.get_datetime_string_from_unix_time(int(t) + int(bias) * 60, true).substr(0, 10)


## Every day the trip touched, oldest first, with its stats.
func days() -> Array:
	if _day_cache.has("days"):
		return _day_cache["days"]
	var by_key := {}
	var order: Array[String] = []
	# One dictionary lookup per fix instead of a linear scan of the break list:
	# at half a million fixes the difference is seconds.
	var break_set := {}
	for b in _breaks:
		break_set[b] = true
	for i in times.size():
		var key := day_key(times[i])
		if not by_key.has(key):
			by_key[key] = {
				"key": key, "first": i, "last": i, "t0": times[i], "t1": times[i],
				"meters": 0.0, "moving": 0.0, "climb": 0.0, "max_speed": 0.0, "events": 0,
			}
			order.push_back(key)
		var d: Dictionary = by_key[key]
		if i > 0 and not break_set.has(i):
			var dm := Geo.distance_m(lats[i - 1], lons[i - 1], lats[i], lons[i])
			var dt := times[i] - times[i - 1]
			d["meters"] = float(d["meters"]) + dm
			if dt > 0.0 and dt < 60.0:
				if dm / dt > Cfg.get_f("autopause_mps"):
					d["moving"] = float(d["moving"]) + dt
				var dz := alts[i] - alts[i - 1]
				if dz > 1.5:
					d["climb"] = float(d["climb"]) + dz
		d["last"] = i
		d["t1"] = times[i]
		d["max_speed"] = maxf(float(d["max_speed"]), spds[i])
	for e in events:
		var key := day_key(float(e.get("t", 0.0)))
		if by_key.has(key):
			by_key[key]["events"] = int(by_key[key]["events"]) + 1
	var out := []
	for key in order:
		out.push_back(by_key[key])
	_day_cache["days"] = out
	return out


func day_number(t: float) -> int:
	var key := day_key(t)
	var all := days()
	for i in all.size():
		if String(all[i]["key"]) == key:
			return i + 1
	return all.size() + 1


# --------------------------------------------------------- display polyline


## The track as drawable segments of lat/lon, simplified to `tol_m` and split
## at gaps. Cached per 2048-fix block, so a new fix only re-simplifies the
## couple of hundred points at the live end.
func track_segments(tol_m: float) -> Array:
	if not is_equal_approx(tol_m, _blocks_tol):
		_blocks.clear()
		_blocks_tol = tol_m
	var n := times.size()
	var nblocks := (n + BLOCK - 1) / BLOCK
	_blocks.resize(nblocks)
	for b in nblocks:
		if _blocks[b] == null:
			_blocks[b] = _build_block(b, tol_m)
	var segs := []
	var cur := PackedVector2Array()
	var break_set := {}
	for i in _breaks:
		break_set[i] = true
	for b in nblocks:
		var blk: Dictionary = _blocks[b]
		var pts: PackedVector2Array = blk["pts"]
		var idx: PackedInt32Array = blk["idx"]
		for k in pts.size():
			if break_set.has(idx[k]) and cur.size() > 0:
				segs.push_back(cur)
				cur = PackedVector2Array()
			cur.push_back(pts[k])
	if cur.size() > 0:
		segs.push_back(cur)
	return segs


func _build_block(b: int, tol_m: float) -> Dictionary:
	var lo := b * BLOCK
	var hi := mini(lo + BLOCK, times.size())
	# Cut the block at any segment break so simplification never draws a
	# shortcut across a discontinuity.
	var cuts: Array[int] = [lo]
	for i in _breaks:
		if i > lo and i < hi:
			cuts.push_back(i)
	cuts.push_back(hi)
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for c in cuts.size() - 1:
		var a := cuts[c]
		var z := cuts[c + 1]
		var raw := PackedVector2Array()
		for i in range(a, z):
			raw.push_back(Vector2(lats[i], lons[i]))
		var kept := Geo.simplify(raw, tol_m)
		# Map the simplified points back to absolute fix indices so segment
		# breaks can be found again after simplification.
		var j := a
		for p in kept:
			while j < z and not (is_equal_approx(lats[j], p.x) and is_equal_approx(lons[j], p.y)):
				j += 1
			pts.push_back(p)
			idx.push_back(mini(j, z - 1))
			j += 1
	return {"pts": pts, "idx": idx}


# --------------------------------------------------------------- json files


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var v: Variant = JSON.parse_string(text)
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
