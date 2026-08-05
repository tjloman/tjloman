extends Node
## Autoload `Wx`: weather, written for a rider who often has no signal.
##
## Three sources, all keyless so there is nothing to expire mid-trip:
##
##   Open-Meteo    conditions and an hourly forecast, worldwide.
##   NWS           active watches/warnings for a point (United States).
##   RainViewer    radar tiles, past frames plus a short nowcast.
##
## Everything fetched is kept and timestamped. When the data drops out — which
## it will, for hours at a time — the panel keeps showing the last thing it
## knew with an honest "2h 14m old" on it. Stale weather you can reason about
## beats a spinner.

signal updated
signal alerts_changed
signal radar_changed

const OPEN_METEO := "https://api.open-meteo.com/v1/forecast"
const NWS_ALERTS := "https://api.weather.gov/alerts/active"
const RAINVIEWER_INDEX := "https://api.rainviewer.com/public/weather-maps.json"
const CACHE_PATH := "user://weather.json"

var current := {}                 ## Latest conditions.
var hourly: Array = []            ## [{t, temp, precip_prob, precip, wind, code}, ...]
var alerts: Array = []            ## Active NWS alerts, most severe first.
var fetched_at := 0.0
var alerts_at := 0.0

var radar_host := ""
var radar_frames: Array = []      ## [{t, path, nowcast}] oldest first.
var radar_index := -1
var radar_at := 0.0

var _poll := 5.0
var _last_point := Vector2.INF
var _seen_alerts := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_cache()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = maxf(60.0, Cfg.get_f("weather_poll_minutes") * 60.0)
	refresh()


## Fetch whatever is due. Called on a timer and by the refresh button; the
## button passes `force` so a deliberate tap goes out even on cellular.
func refresh(force: bool = false) -> void:
	var f := Logbook.last_fix()
	if f.is_empty():
		return
	var lat := float(f["lat"])
	var lon := float(f["lon"])
	var pri := Net.P_USER if force else Net.P_NORMAL
	if not Net.allowed(pri):
		return
	_last_point = Vector2(lat, lon)
	_fetch_conditions(lat, lon, pri)
	_fetch_alerts(lat, lon, pri)
	if Cfg.get_b("radar_enabled"):
		_fetch_radar_index(pri)


func age_seconds() -> float:
	if fetched_at <= 0.0:
		return INF
	return Time.get_unix_time_from_system() - fetched_at


func is_stale() -> bool:
	return age_seconds() > 3600.0


# ------------------------------------------------------------- conditions


func _fetch_conditions(lat: float, lon: float, pri: int) -> void:
	var metric := Cfg.is_metric()
	var url := "%s?latitude=%.4f&longitude=%.4f" % [OPEN_METEO, lat, lon]
	url += "&current=temperature_2m,apparent_temperature,precipitation,weather_code,"
	url += "wind_speed_10m,wind_gusts_10m,wind_direction_10m,relative_humidity_2m"
	url += "&hourly=temperature_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m"
	url += "&forecast_days=2&timeformat=unixtime&timezone=auto"
	if not metric:
		url += "&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch"
	Net.fetch(url, _on_conditions, pri)


func _on_conditions(ok: bool, _code: int, body: PackedByteArray) -> void:
	if not ok:
		return
	var v: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(v) != TYPE_DICTIONARY:
		return
	var d: Dictionary = v
	var c: Dictionary = d.get("current", {})
	if c.is_empty():
		return
	current = {
		"temp": float(c.get("temperature_2m", 0.0)),
		"feels": float(c.get("apparent_temperature", 0.0)),
		"humidity": float(c.get("relative_humidity_2m", 0.0)),
		"precip": float(c.get("precipitation", 0.0)),
		"code": int(c.get("weather_code", 0)),
		"wind": float(c.get("wind_speed_10m", 0.0)),
		"gust": float(c.get("wind_gusts_10m", 0.0)),
		"wind_dir": float(c.get("wind_direction_10m", 0.0)),
		"metric": Cfg.is_metric(),
	}
	hourly.clear()
	var h: Dictionary = d.get("hourly", {})
	var times: Array = h.get("time", [])
	for i in times.size():
		hourly.push_back({
			"t": float(times[i]),
			"temp": _at(h, "temperature_2m", i),
			"precip_prob": _at(h, "precipitation_probability", i),
			"precip": _at(h, "precipitation", i),
			"wind": _at(h, "wind_speed_10m", i),
			"code": int(_at(h, "weather_code", i)),
		})
	fetched_at = Time.get_unix_time_from_system()
	_save_cache()
	updated.emit()


static func _at(h: Dictionary, key: String, i: int) -> float:
	var arr: Array = h.get(key, [])
	if i < arr.size() and arr[i] != null:
		return float(arr[i])
	return 0.0


## Headwind component in the direction of travel: negative is a push. The one
## weather number that changes how a day actually feels on a bike.
func wind_component() -> float:
	if current.is_empty():
		return 0.0
	var f := Logbook.last_fix()
	if f.is_empty():
		return 0.0
	# Meteorological wind direction is where it comes FROM.
	var from := float(current.get("wind_dir", 0.0))
	var travel := float(f["hdg"])
	return float(current.get("wind", 0.0)) * cos(deg_to_rad(from - travel))


# ----------------------------------------------------------------- alerts


func _fetch_alerts(lat: float, lon: float, pri: int) -> void:
	var url := "%s?point=%.4f,%.4f" % [NWS_ALERTS, lat, lon]
	var headers := PackedStringArray(["Accept: application/geo+json"])
	Net.fetch(url, _on_alerts, pri, headers)


func _on_alerts(ok: bool, code: int, body: PackedByteArray) -> void:
	if not ok:
		# Outside the United States this 404s forever. Not an error worth
		# shouting about — there simply are no NWS alerts there.
		if code == 404:
			alerts_at = Time.get_unix_time_from_system()
		return
	var v: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(v) != TYPE_DICTIONARY:
		return
	var features: Array = (v as Dictionary).get("features", [])
	var fresh: Array = []
	for feat in features:
		var p: Dictionary = (feat as Dictionary).get("properties", {})
		var a := {
			"id": String(p.get("id", "")),
			"event": String(p.get("event", "Alert")),
			"severity": String(p.get("severity", "Unknown")),
			"urgency": String(p.get("urgency", "")),
			"headline": String(p.get("headline", p.get("event", ""))),
			"description": String(p.get("description", "")),
			"instruction": String(p.get("instruction", "")),
			"ends": String(p.get("ends", p.get("expires", ""))),
		}
		fresh.push_back(a)
		if not _seen_alerts.has(a["id"]):
			_seen_alerts[a["id"]] = true
			_announce(a)
	fresh.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return _severity_rank(String(x["severity"])) > _severity_rank(String(y["severity"])))
	alerts = fresh
	alerts_at = Time.get_unix_time_from_system()
	_save_cache()
	alerts_changed.emit()


## A new warning is one of the few things worth interrupting a ride for: it
## goes into the logbook *and* onto the lock screen, and buzzes.
func _announce(a: Dictionary) -> void:
	Logbook.append_event(Ev.WEATHER, {
		"headline": String(a["headline"]),
		"event": String(a["event"]),
		"severity": String(a["severity"]),
		"alert_id": String(a["id"]),
	})
	if _severity_rank(String(a["severity"])) >= 3:
		Bridge.notify(String(a["event"]), String(a["headline"]))
		Bridge.vibrate(600)


static func _severity_rank(s: String) -> int:
	match s:
		"Extreme": return 4
		"Severe": return 3
		"Moderate": return 2
		"Minor": return 1
	return 0


func worst_alert() -> Dictionary:
	return alerts[0] if not alerts.is_empty() else {}


# ------------------------------------------------------------------ radar


func _fetch_radar_index(pri: int) -> void:
	Net.fetch(RAINVIEWER_INDEX, _on_radar_index, pri)


func _on_radar_index(ok: bool, _code: int, body: PackedByteArray) -> void:
	if not ok:
		return
	var v: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(v) != TYPE_DICTIONARY:
		return
	var d: Dictionary = v
	radar_host = String(d.get("host", "https://tilecache.rainviewer.com"))
	var radar: Dictionary = d.get("radar", {})
	var frames: Array = []
	for f in radar.get("past", []):
		frames.push_back({"t": float((f as Dictionary).get("time", 0)),
			"path": String((f as Dictionary).get("path", "")), "nowcast": false})
	for f in radar.get("nowcast", []):
		frames.push_back({"t": float((f as Dictionary).get("time", 0)),
			"path": String((f as Dictionary).get("path", "")), "nowcast": true})
	if frames.is_empty():
		return
	# Old frames are dead weight in the tile cache within the hour.
	for old in radar_frames:
		var still_live := false
		for f in frames:
			if float(f["t"]) == float(old["t"]):
				still_live = true
				break
		if not still_live:
			Tiles.drop_source(frame_source_id(float(old["t"])))
	radar_frames = frames
	radar_index = _latest_past_index()
	radar_at = Time.get_unix_time_from_system()
	radar_changed.emit()


func _latest_past_index() -> int:
	for i in range(radar_frames.size() - 1, -1, -1):
		if not bool(radar_frames[i]["nowcast"]):
			return i
	return radar_frames.size() - 1


## Tile-source id for a radar frame. It doubles as the cache directory name,
## so it has to be filesystem-safe — hence the timestamp rather than the path.
static func frame_source_id(t: float) -> String:
	return "radar-%d" % int(t)


func frame_url_template(source_id: String) -> String:
	for f in radar_frames:
		if frame_source_id(float(f["t"])) == source_id:
			# color scheme 2 (universal blue), smoothed, with snow shown
			return "%s%s/256/{z}/{x}/{y}/2/1_1.png" % [radar_host, String(f["path"])]
	return ""


func current_frame_id() -> String:
	if radar_index < 0 or radar_index >= radar_frames.size():
		return ""
	return frame_source_id(float(radar_frames[radar_index]["t"]))


func frame_label(i: int) -> String:
	if i < 0 or i >= radar_frames.size():
		return ""
	var f: Dictionary = radar_frames[i]
	var mins := int((Time.get_unix_time_from_system() - float(f["t"])) / 60.0)
	if bool(f["nowcast"]):
		return "+%dm forecast" % maxi(0, -mins)
	if mins <= 1:
		return "now"
	return "-%dm" % mins


func step_radar(delta: int) -> void:
	if radar_frames.is_empty():
		return
	radar_index = wrapi(radar_index + delta, 0, radar_frames.size())
	radar_changed.emit()


# ------------------------------------------------------------------ display


## WMO weather codes, as used by Open-Meteo.
static func code_text(code: int) -> String:
	match code:
		0: return "Clear"
		1: return "Mostly clear"
		2: return "Partly cloudy"
		3: return "Overcast"
		45, 48: return "Fog"
		51, 53, 55: return "Drizzle"
		56, 57: return "Freezing drizzle"
		61: return "Light rain"
		63: return "Rain"
		65: return "Heavy rain"
		66, 67: return "Freezing rain"
		71: return "Light snow"
		73: return "Snow"
		75: return "Heavy snow"
		77: return "Snow grains"
		80, 81: return "Rain showers"
		82: return "Violent showers"
		85, 86: return "Snow showers"
		95: return "Thunderstorm"
		96, 99: return "Thunderstorm, hail"
	return "—"


func summary_line() -> String:
	if current.is_empty():
		return "weather: no data yet"
	var unit := "°C" if bool(current.get("metric", false)) else "°F"
	var s := "%d%s  %s" % [int(round(float(current["temp"]))), unit, code_text(int(current["code"]))]
	var comp := wind_component()
	if absf(comp) > 3.0:
		s += "  %s %d" % ["headwind" if comp > 0.0 else "tailwind", int(absf(comp))]
	if is_stale():
		s += "  (%s old)" % Trip.format_duration(age_seconds())
	return s


# ------------------------------------------------------------------- cache


func _save_cache() -> void:
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"current": current, "hourly": hourly, "alerts": alerts,
		"fetched_at": fetched_at, "alerts_at": alerts_at,
		"point": [_last_point.x, _last_point.y],
	}))


func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if typeof(v) != TYPE_DICTIONARY:
		return
	var d: Dictionary = v
	current = d.get("current", {})
	hourly = d.get("hourly", [])
	alerts = d.get("alerts", [])
	fetched_at = float(d.get("fetched_at", 0.0))
	alerts_at = float(d.get("alerts_at", 0.0))
	for a in alerts:
		_seen_alerts[String((a as Dictionary).get("id", ""))] = true
