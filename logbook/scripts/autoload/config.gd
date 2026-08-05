extends Node
## Autoload `Cfg`: every user-tunable knob, persisted to `user://settings.cfg`.
##
## Defaults are chosen for the actual use case — a phone on a handlebar, on a
## battery, often with no signal — rather than for a demo. Anything that costs
## power or cellular data is conservative out of the box.

signal changed(key: String)

const PATH := "user://settings.cfg"

## Defaults, and by being here also the schema: `get_value` type-checks
## against these so a corrupted settings file can never crash the app.
const DEFAULTS := {
	# -- units and display
	"metric": false,
	"clock_24h": true,
	"night_mode": false,          ## Dim, red-shifted palette for riding at dusk.
	"keep_screen_on": true,

	# -- GPS logging
	"gps_enabled": true,
	"gps_min_seconds": 3.0,       ## Never sample faster than this.
	"gps_min_meters": 8.0,        ## ...or closer together than this.
	"gps_idle_seconds": 120.0,    ## When stopped, still drop a fix this often.
	"gps_max_accuracy_m": 60.0,   ## Reject fixes worse than this (urban canyons).
	"gps_background": true,       ## Foreground service keeps logging screen-off.
	"autopause_mps": 0.6,         ## Below this for a while = stopped.
	"autopause_seconds": 90.0,

	# -- capture from the phone
	"capture_calls": true,
	"capture_messages": true,
	"capture_message_bodies": false,  ## Metadata only unless you opt in.
	"capture_photos": true,
	"capture_music": true,            ## Log what was playing, pinned to the map.
	"music_app_package": "com.spotify.music",
	"photo_match_seconds": 90.0,      ## Photo with no EXIF fix: snap to track.

	# -- map
	"tile_source": "osm",
	"tile_custom_url": "",            ## e.g. https://tiles.example.com/{z}/{x}/{y}.png?key={key}
	"tile_custom_attribution": "",
	"tile_custom_max_zoom": 18,
	"tile_api_key": "",
	"map_prefetch_zoom_min": 8,
	"map_prefetch_zoom_max": 14,
	"map_corridor_km": 6.0,           ## Half-width of the prefetched route corridor.
	"map_cache_budget_mb": 3000,
	"map_follow": true,               ## Keep the map centered on me while moving.
	"map_rotate_with_heading": false,

	# -- data discipline
	"cellular_budget_mb_day": 40,
	"download_on_cellular": false,    ## Tiles/radar wait for wifi by default.
	"weather_poll_minutes": 20,
	"radar_enabled": true,

	# -- the rig: a Senada Saber pulling a powered cart
	"ble_enabled": true,
	"ble_devices": [],                ## [{address, name, role}] — bike, cart, house.
	"ble_device": "",                 ## Legacy single-device key, migrated on load.
	"ble_profile": "auto",
	"ble_sample_minutes": 5.0,        ## How often a pack reading is logged.
	"battery_wh": 960.0,              ## Saber pack: 48 V x 20 Ah. Correct it if yours differs.
	"cart_battery_wh": 2400.0,        ## The cart carries far more than the bike.
	"cart_motor_count": 2,
	"solar_watts_peak": 400.0,
	"wheel_circumference_m": 2.36,    ## 26x4.0 fat tyre. Roll the wheel to measure yours.
	"assumed_wh_per_mile": 22.0,      ## Loaded bike + powered cart, until measured.
	"low_battery_warn_pct": 20,

	# -- stop photos
	"google_api_key": "",             ## Optional: Street View / Places stop photos.

	# -- journal
	"journal_autosave_seconds": 20.0,
	"onscreen_keyboard": true,        ## Use the in-app keyboard, not the OS one.
	"font_scale": 1.0,

	# -- trip
	"trip_id": "",                    ## Empty = create one on first run.
	"rider_name": "",
}

var _values := {}
var _file := ConfigFile.new()
var _dirty := false
var _save_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	if get_value("keep_screen_on"):
		DisplayServer.screen_set_keep_on(true)


func _process(delta: float) -> void:
	# Coalesce writes: a slider drag should not hit flash storage 60x a second.
	if _dirty:
		_save_timer -= delta
		if _save_timer <= 0.0:
			save_settings()


func load_settings() -> void:
	_values = DEFAULTS.duplicate(true)
	if _file.load(PATH) != OK:
		return
	for key: String in DEFAULTS.keys():
		if not _file.has_section_key("settings", key):
			continue
		var v: Variant = _file.get_value("settings", key)
		if typeof(v) == typeof(DEFAULTS[key]):
			_values[key] = v
		elif typeof(DEFAULTS[key]) == TYPE_FLOAT and typeof(v) == TYPE_INT:
			_values[key] = float(v)  # ConfigFile writes 3.0 back as 3


func save_settings() -> void:
	for key: String in _values.keys():
		_file.set_value("settings", key, _values[key])
	_file.save(PATH)
	_dirty = false


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func get_f(key: String) -> float:
	return float(get_value(key))


func get_i(key: String) -> int:
	return int(get_value(key))


func get_b(key: String) -> bool:
	return bool(get_value(key))


func get_s(key: String) -> String:
	return String(get_value(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Cfg: unknown setting '%s'" % key)
		return
	# Sliders hand back floats for settings that are declared as ints. Coerce
	# to the declared type or the value is rejected as corrupt on next launch.
	match typeof(DEFAULTS[key]):
		TYPE_INT:
			value = int(value)
		TYPE_FLOAT:
			value = float(value)
		TYPE_BOOL:
			value = bool(value)
	if _values.get(key) == value:
		return
	_values[key] = value
	_dirty = true
	_save_timer = 1.0
	changed.emit(key)
	if key == "keep_screen_on":
		DisplayServer.screen_set_keep_on(bool(value))


func toggle(key: String) -> void:
	set_value(key, not get_b(key))


func is_metric() -> bool:
	return get_b("metric")


## Shorthand used all over the UI.
func dist(meters: float) -> String:
	return Geo.format_distance(meters, is_metric())


func speed(mps: float) -> String:
	return Geo.format_speed(mps, is_metric())


func elev(meters: float) -> String:
	return Geo.format_elevation(meters, is_metric())
