extends Node
## Autoload `Trip`: the conductor. It owns the live state of the ride and
## decides what actually becomes a logbook entry.
##
## The phone throws a lot at us — a fix a second, every notification, every
## call, every photo — and almost none of it should be written verbatim. This
## node applies the policy:
##
##   * A fix is kept when it is accurate enough AND far enough or old enough.
##     A stationary hour costs 30 records instead of 3,600.
##   * Standing still long enough is a pause, and moving again is a resume, so
##     "moving time" means something at the end of the day.
##   * Crossing local midnight closes the day with a summary and opens the
##     next one — that is what makes the timeline a diary rather than a stream.
##   * Calls, messages and photos are placed on the track by their timestamp,
##     which is how something that happened in a dead zone still lands in the
##     right valley.

signal stats_changed
signal paused_changed(paused: bool)
signal day_rolled(day: int)

## Notification packages that count as "messenger activity". Anything else is
## weather widgets and battery warnings, which are not diary material.
const MESSAGING_APPS := [
	"Messages", "Messenger", "Signal", "WhatsApp", "Telegram", "SMS", "MMS",
	"Instagram", "Snapchat", "Discord", "Slack", "Mastodon", "Facebook",
]

var logging := false
var paused := false
var speed_mps := 0.0            ## Smoothed; the raw value jitters too much to read.
var fix_age := INF
var last_accuracy := 0.0
var gps_ok := false

var today_meters := 0.0
var today_moving := 0.0
var today_climb := 0.0

var _last_kept_t := -1.0
var _last_kept_lat := 0.0
var _last_kept_lon := 0.0
var _still_since := -1.0
var _current_day := ""
var _last_seen := 0.0           ## Newest event timestamp we have ingested.
var _stat_timer := 0.0
var _battery_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Bridge.location_fix.connect(_on_fix)
	Bridge.call_logged.connect(_on_call)
	Bridge.notification_posted.connect(_on_notification)
	Bridge.photo_found.connect(_on_photo)
	Logbook.trip_opened.connect(_recompute_today)
	# In service mode our own append_fix is a no-op, so today's running totals
	# come off the tail of the file the service is writing instead.
	Logbook.fix_appended.connect(_on_logged_fix)
	_recompute_today()
	_current_day = Logbook.day_key(Time.get_unix_time_from_system())
	_last_seen = Logbook.end_time()
	if Cfg.get_b("gps_enabled"):
		start()


func _process(delta: float) -> void:
	var f := Logbook.last_fix()
	if not f.is_empty():
		fix_age = Time.get_unix_time_from_system() - float(f["t"])
	gps_ok = fix_age < 30.0
	_stat_timer -= delta
	if _stat_timer <= 0.0:
		_stat_timer = 1.0
		stats_changed.emit()
	_battery_timer -= delta
	if _battery_timer <= 0.0:
		_battery_timer = maxf(30.0, Cfg.get_f("ble_sample_minutes") * 60.0)
		_sample_battery()


func start() -> void:
	logging = true
	Bridge.request_permissions()
	Bridge.start_location()
	# Anything that happened while we were not running gets pulled in now and
	# placed by timestamp.
	Bridge.backfill(_last_seen if _last_seen > 0.0 else Time.get_unix_time_from_system() - 86400.0)


func stop() -> void:
	logging = false
	Bridge.stop_location()
	Logbook.flush()
	Logbook.write_snapshot()


func toggle_logging() -> void:
	if logging:
		stop()
	else:
		start()


# ------------------------------------------------------------------- fixes


func _on_fix(fix: Dictionary) -> void:
	if not logging:
		return
	var t := float(fix.get("t", Time.get_unix_time_from_system()))
	var lat := float(fix.get("lat", 0.0))
	var lon := float(fix.get("lon", 0.0))
	var acc := float(fix.get("accuracy", 0.0))
	last_accuracy = acc
	# A wild fix (cold start, reflection off a cliff) would otherwise put a
	# spike across the map and inflate the day's distance.
	if acc > Cfg.get_f("gps_max_accuracy_m") and Logbook.fix_count() > 0:
		return

	var raw_speed := float(fix.get("speed", 0.0))
	var dt := t - _last_kept_t
	var dm := 0.0
	if _last_kept_t > 0.0:
		dm = Geo.distance_m(_last_kept_lat, _last_kept_lon, lat, lon)
		if raw_speed <= 0.0 and dt > 0.0:
			raw_speed = dm / dt
	speed_mps = lerpf(speed_mps, raw_speed, 0.35)

	_check_day_roll(t)
	_check_autopause(t, raw_speed)

	if _last_kept_t > 0.0:
		if dt < Cfg.get_f("gps_min_seconds"):
			return
		if dm < Cfg.get_f("gps_min_meters") and dt < Cfg.get_f("gps_idle_seconds"):
			return

	var kept := Logbook.append_fix(t, lat, lon, float(fix.get("alt", 0.0)),
		raw_speed, float(fix.get("bearing", 0.0)), acc)
	if not kept:
		return
	if _last_kept_t > 0.0 and dm < Logbook.GAP_METERS and dt < Logbook.GAP_SECONDS:
		today_meters += dm
		if raw_speed > Cfg.get_f("autopause_mps"):
			today_moving += dt
	_last_kept_t = t
	_last_kept_lat = lat
	_last_kept_lon = lon
	_last_seen = maxf(_last_seen, t)


## A fix that reached the arrays — from our own writer or from tailing the
## service's file. Either way it is the one place the day's totals grow.
func _on_logged_fix(i: int) -> void:
	if not Logbook.service_mode or i <= 0 or i >= Logbook.fix_count():
		return
	var dt := Logbook.times[i] - Logbook.times[i - 1]
	var dm := Geo.distance_m(Logbook.lats[i - 1], Logbook.lons[i - 1],
		Logbook.lats[i], Logbook.lons[i])
	if dt <= 0.0 or dt > Logbook.GAP_SECONDS or dm > Logbook.GAP_METERS:
		return
	_check_day_roll(Logbook.times[i])
	today_meters += dm
	if dm / dt > Cfg.get_f("autopause_mps"):
		today_moving += dt
	var dz := Logbook.alts[i] - Logbook.alts[i - 1]
	if dz > 1.5:
		today_climb += dz


func _check_autopause(t: float, raw_speed: float) -> void:
	if raw_speed > Cfg.get_f("autopause_mps"):
		_still_since = -1.0
		if paused:
			paused = false
			Logbook.append_event(Ev.RESUME, {"t": t})
			paused_changed.emit(false)
		return
	if _still_since < 0.0:
		_still_since = t
	elif not paused and t - _still_since > Cfg.get_f("autopause_seconds"):
		paused = true
		Logbook.append_event(Ev.PAUSE, {"t": t})
		paused_changed.emit(true)


func _check_day_roll(t: float) -> void:
	var key := Logbook.day_key(t)
	if key == _current_day:
		return
	var day := Logbook.day_number(t) - 1
	if _current_day != "":
		Logbook.append_event(Ev.DAY_END, {
			"t": t - 1.0,
			"day": maxi(1, day),
			"summary": "%s ridden, %s moving" % [Cfg.dist(today_meters), _hms(today_moving)],
			"meters": today_meters,
			"moving": today_moving,
			"climb": today_climb,
		})
	_current_day = key
	today_meters = 0.0
	today_moving = 0.0
	today_climb = 0.0
	Logbook.append_event(Ev.DAY_START, {"t": t, "day": maxi(1, day + 1)})
	day_rolled.emit(maxi(1, day + 1))


func _recompute_today() -> void:
	today_meters = 0.0
	today_moving = 0.0
	today_climb = 0.0
	var key := Logbook.day_key(Time.get_unix_time_from_system())
	for d in Logbook.days():
		if String(d["key"]) == key:
			today_meters = float(d["meters"])
			today_moving = float(d["moving"])
			today_climb = float(d["climb"])
	var f := Logbook.last_fix()
	if not f.is_empty():
		_last_kept_t = float(f["t"])
		_last_kept_lat = float(f["lat"])
		_last_kept_lon = float(f["lon"])
	stats_changed.emit()


# -------------------------------------------------------------- phone feeds


func _on_call(c: Dictionary) -> void:
	if not Cfg.get_b("capture_calls"):
		return
	var t := float(c.get("t", Time.get_unix_time_from_system()))
	# The call log is re-read on every resume, so the same call arrives many
	# times. Its start time is a stable identity.
	var id := "call-%d" % int(t)
	if Logbook.has_event(id):
		return
	var e := c.duplicate()
	e["id"] = id
	e["t"] = t
	Logbook.append_event(Ev.CALL, e)
	_last_seen = maxf(_last_seen, t)


func _on_notification(n: Dictionary) -> void:
	if not Cfg.get_b("capture_messages"):
		return
	var app := String(n.get("app", ""))
	var known := false
	for m in MESSAGING_APPS:
		if app.containsn(String(m)):
			known = true
			break
	if not known:
		return
	var t := float(n.get("t", Time.get_unix_time_from_system()))
	var e := {
		"t": t,
		"app": app,
		"who": String(n.get("who", n.get("title", ""))),
	}
	if Cfg.get_b("capture_message_bodies"):
		e["text"] = String(n.get("text", ""))
	Logbook.append_event(Ev.MESSAGE, e)
	_last_seen = maxf(_last_seen, t)


func _on_photo(p: Dictionary) -> void:
	if not Cfg.get_b("capture_photos"):
		return
	var t := float(p.get("t", Time.get_unix_time_from_system()))
	var id := "photo-%d" % int(t)
	if Logbook.has_event(id):
		return
	var e := {"id": id, "t": t, "file": String(p.get("file", ""))}
	if p.has("width"):
		e["width"] = int(p["width"])
		e["height"] = int(p["height"])
	# EXIF position wins; otherwise the track places it, which is the whole
	# reason the track is continuous.
	if p.has("lat") and p.has("lon"):
		e["lat"] = float(p["lat"])
		e["lon"] = float(p["lon"])
	else:
		var near := Logbook.latlon_at_time(t)
		if near != Vector2.INF:
			e["lat"] = near.x
			e["lon"] = near.y
			e["placed_by_track"] = true
	Logbook.append_event(Ev.PHOTO, e)
	_last_seen = maxf(_last_seen, t)


func _sample_battery() -> void:
	# When the service is running it samples the pack on its own schedule,
	# including while the app is closed. Doing it here too would double every
	# reading for as long as the app happens to be open.
	if Logbook.service_mode:
		return
	if not Bike.connected:
		return
	var s := Bike.state
	if s.is_empty() or not s.has("soc"):
		return
	Logbook.append_event(Ev.BATTERY, {
		"soc": float(s.get("soc", 0.0)),
		"volts": float(s.get("volts", 0.0)),
		"amps": float(s.get("amps", 0.0)),
		"wh_used": float(s.get("wh_used", 0.0)),
		"temp_c": float(s.get("temp_c", 0.0)),
	})


# ------------------------------------------------------------------ derived


## Distance still to cover on the planned route from where we are now, and a
## naive ETA from the day's own average moving speed. Naive is honest: it does
## not pretend to know the hills ahead.
func remaining_on_route() -> Dictionary:
	var route: Array = Logbook.meta.get("route", [])
	var f := Logbook.last_fix()
	if route.size() < 2 or f.is_empty():
		return {}
	var here := Vector2(float(f["lat"]), float(f["lon"]))
	var best_i := 0
	var best_d := INF
	var best_t := 0.0
	for i in route.size() - 1:
		var a := Vector2(float(route[i][0]), float(route[i][1]))
		var b := Vector2(float(route[i + 1][0]), float(route[i + 1][1]))
		var r := Geo.point_segment_m(here, a, b)
		if float(r["m"]) < best_d:
			best_d = float(r["m"])
			best_i = i
			best_t = float(r["t"])
	var remaining := 0.0
	for i in range(best_i, route.size() - 1):
		var a := Vector2(float(route[i][0]), float(route[i][1]))
		var b := Vector2(float(route[i + 1][0]), float(route[i + 1][1]))
		var seg := Geo.distance_m(a.x, a.y, b.x, b.y)
		remaining += seg * (1.0 - best_t) if i == best_i else seg
	return {
		"meters": remaining,
		"off_route_m": best_d,
		"eta_seconds": remaining / maxf(1.5, average_speed()),
	}


func average_speed() -> float:
	if today_moving < 60.0:
		return maxf(speed_mps, 3.0)
	return today_meters / today_moving


func total_days() -> int:
	return maxi(1, Logbook.days().size())


static func _hms(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%dm" % (s / 60)


func format_duration(seconds: float) -> String:
	return _hms(seconds)
