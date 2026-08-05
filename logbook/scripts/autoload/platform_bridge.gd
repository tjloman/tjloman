extends Node
## Autoload `Bridge`: the seam between GDScript and the phone.
##
## Godot is the front end and nothing more. The part of this app that has to
## survive the screen going off, the app being swiped away, and the phone
## sitting locked on a charger in the trailer for six hours is an Android
## foreground service — Kotlin, under `android/plugin` — and it is the one
## writing the journey down. GPS, the call log, other apps' notifications,
## the ebike's Bluetooth link, and the media session all live there.
##
## This singleton is the wire between the two: it starts and configures the
## service, forwards its events for live display, and relays transport
## commands (play/pause/skip) back down. The durable path does not go through
## here at all — the service appends to the log files directly and the app
## tails them, so nothing is lost when Godot is not even running.
##
## Everything the rest of the app touches goes through this node, and this
## node works with or without the plugin:
##
##   * On a phone with the plugin installed, calls forward to Kotlin.
##   * Anywhere else — the editor, a laptop, a build without the plugin — a
##     simulator produces a plausible ride: fixes along a route, a draining
##     battery, the odd call and photo. The map, timeline, journal, and
##     weather code cannot tell the difference, which is the whole point:
##     you can develop and review the app without a bike under you.

signal location_fix(fix: Dictionary)
signal location_status(status: Dictionary)
signal call_logged(call: Dictionary)
signal notification_posted(note: Dictionary)
signal photo_found(photo: Dictionary)
signal connectivity_changed(net: Dictionary)
signal device_battery_changed(battery: Dictionary)

signal ble_state(state: Dictionary)
signal ble_device_found(device: Dictionary)
## The rig is more than one device — the bike and the powered cart are
## separate peripherals — so everything BLE is scoped by address.
signal ble_services_discovered(address: String, services: Array)
signal ble_value(address: String, uuid: String, bytes: PackedByteArray)

signal media_changed(info: Dictionary)
signal service_state(state: Dictionary)

const SINGLETON := "TripLogbook"

var native: Object = null
var simulating := false

var permissions := {
	"location": false,
	"background_location": false,
	"call_log": false,
	"notifications": false,
	"media": false,
	"bluetooth": false,
}

var _sim: RideSimulator = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton(SINGLETON):
		native = Engine.get_singleton(SINGLETON)
		_wire_native()
		# The service owns the sensor files from here on.
		Logbook.set_service_mode(true)
		configure_service()
		print("Bridge: native plugin connected")
	else:
		if OS.has_feature("mobile"):
			push_warning("Bridge: running on a phone without the TripLogbook plugin — "
				+ "background logging and Bluetooth are unavailable")
		_start_simulator()


func has_native() -> bool:
	return native != null


func _wire_native() -> void:
	var links := {
		"location_fix": _on_native_fix,
		"location_status": func(s: Dictionary) -> void: location_status.emit(s),
		"call_logged": func(c: Dictionary) -> void: call_logged.emit(c),
		"notification_posted": func(n: Dictionary) -> void: notification_posted.emit(n),
		"photo_found": func(p: Dictionary) -> void: photo_found.emit(p),
		"connectivity_changed": func(n: Dictionary) -> void: connectivity_changed.emit(n),
		"device_battery_changed": func(b: Dictionary) -> void: device_battery_changed.emit(b),
		"ble_state": _on_ble_state,
		"ble_device_found": func(d: Dictionary) -> void: ble_device_found.emit(d),
		"ble_services_discovered": func(a: String, s: Array) -> void:
			ble_services_discovered.emit(a, s),
		"ble_value": func(a: String, u: String, b: PackedByteArray) -> void:
			ble_value.emit(a, u, b),
		"media_changed": func(i: Dictionary) -> void: media_changed.emit(i),
		"service_state": func(s: Dictionary) -> void: service_state.emit(s),
		"permissions_changed": _on_permissions,
	}
	for sig: String in links.keys():
		if native.has_signal(sig):
			native.connect(sig, links[sig])


func _on_native_fix(fix: Dictionary) -> void:
	location_fix.emit(fix)


func _on_ble_state(state: Dictionary) -> void:
	ble_state.emit(state)


func _on_permissions(p: Dictionary) -> void:
	for k: String in p.keys():
		permissions[k] = bool(p[k])


# ----------------------------------------------------------------- service


## Tell the service where to write and how often to sample. Safe to call
## again whenever the trip or the sampling policy changes; the service picks
## up the new settings without restarting.
func configure_service() -> void:
	if native == null or not native.has_method("configureService"):
		return
	native.call("configureService", {
		"dir": ProjectSettings.globalize_path(Logbook.trip_dir),
		"min_seconds": Cfg.get_f("gps_min_seconds"),
		"min_meters": Cfg.get_f("gps_min_meters"),
		"idle_seconds": Cfg.get_f("gps_idle_seconds"),
		"max_accuracy_m": Cfg.get_f("gps_max_accuracy_m"),
		"capture_calls": Cfg.get_b("capture_calls"),
		"capture_messages": Cfg.get_b("capture_messages"),
		"capture_message_bodies": Cfg.get_b("capture_message_bodies"),
		"capture_photos": Cfg.get_b("capture_photos"),
		"capture_music": Cfg.get_b("capture_music"),
		"ble_addresses": _remembered_addresses(),
		"ble_sample_seconds": Cfg.get_f("ble_sample_minutes") * 60.0,
	})


## The service reconnects to every machine on the rig by itself, so it needs
## the whole list, not just the bike.
func _remembered_addresses() -> String:
	var out: Array[String] = []
	for entry in Cfg.get_value("ble_devices"):
		var address := String((entry as Dictionary).get("address", ""))
		if address != "":
			out.push_back(address)
	return ",".join(out)


func service_running() -> bool:
	if native != null and native.has_method("serviceRunning"):
		return bool(native.call("serviceRunning"))
	return _sim != null and _sim.running


# ---------------------------------------------------------------- location


## Ask for everything we need, in the order Android wants it: foreground
## location first, and only then background — asking for both at once is
## rejected outright on Android 11+.
func request_permissions() -> void:
	if native != null and native.has_method("requestPermissions"):
		native.call("requestPermissions")
		return
	for k: String in permissions.keys():
		permissions[k] = true


func start_location() -> void:
	var min_s := Cfg.get_f("gps_min_seconds")
	var min_m := Cfg.get_f("gps_min_meters")
	var bg := Cfg.get_b("gps_background")
	if native != null and native.has_method("startLocation"):
		native.call("startLocation", min_s, min_m, bg)
	elif _sim != null:
		_sim.running = true


func stop_location() -> void:
	if native != null and native.has_method("stopLocation"):
		native.call("stopLocation")
	elif _sim != null:
		_sim.running = false


## Best-effort last known position, for centering the map before the first
## real fix lands.
func last_known() -> Dictionary:
	if native != null and native.has_method("lastKnownLocation"):
		var v: Variant = native.call("lastKnownLocation")
		if typeof(v) == TYPE_DICTIONARY:
			return v
	return {}


# ------------------------------------------------------------------ device


func net_status() -> Dictionary:
	if native != null and native.has_method("netStatus"):
		var v: Variant = native.call("netStatus")
		if typeof(v) == TYPE_DICTIONARY:
			return v
	# Desktop: assume a real connection, unmetered.
	return {"online": true, "kind": "wifi", "metered": false}


func device_battery() -> Dictionary:
	if native != null and native.has_method("deviceBattery"):
		var v: Variant = native.call("deviceBattery")
		if typeof(v) == TYPE_DICTIONARY:
			return v
	return {"level": 100, "charging": true}  # desktop: pretend it is on the wall


func vibrate(ms: int) -> void:
	if native != null and native.has_method("vibrate"):
		native.call("vibrate", ms)
	else:
		Input.vibrate_handheld(ms)


## Post an Android notification (a weather alert, a low battery warning) so it
## reaches you when the phone is in a pocket.
func notify(title: String, body: String, tag: String = "logbook") -> void:
	if native != null and native.has_method("notify"):
		native.call("notify", title, body, tag)
	else:
		print("[notify] %s — %s" % [title, body])


# -------------------------------------------------------------------- feeds


## Pull anything that happened while the app was not running: calls placed
## from the lock screen, photos taken in the camera app, messages that came in
## overnight. Everything is timestamped, so the logbook can place it on the
## track after the fact.
func backfill(since_unix: float) -> void:
	if native != null:
		if Cfg.get_b("capture_calls") and native.has_method("queryCallLog"):
			native.call("queryCallLog", since_unix)
		if Cfg.get_b("capture_photos") and native.has_method("queryPhotos"):
			native.call("queryPhotos", since_unix)
		return
	if _sim != null:
		_sim.backfill(since_unix)


func open_notification_access_settings() -> void:
	if native != null and native.has_method("openNotificationAccessSettings"):
		native.call("openNotificationAccessSettings")


func take_photo() -> void:
	if native != null and native.has_method("takePhoto"):
		native.call("takePhoto")
	elif _sim != null:
		_sim.fake_photo()


func start_audio_memo(path: String) -> void:
	if native != null and native.has_method("startAudioMemo"):
		native.call("startAudioMemo", ProjectSettings.globalize_path(path))


func stop_audio_memo() -> void:
	if native != null and native.has_method("stopAudioMemo"):
		native.call("stopAudioMemo")


# -------------------------------------------------------------------- media


## Transport control through Android's MediaSession — the same interface the
## lock screen and a bluetooth remote use. It works with Spotify, or anything
## else that plays audio, without an account, an API key, or the app being in
## the foreground. That is the point: the phone can be locked in the trailer
## and this still skips the track.
func media_play_pause() -> void:
	_media("mediaPlayPause")


func media_next() -> void:
	_media("mediaNext")


func media_prev() -> void:
	_media("mediaPrev")


func media_volume(delta: int) -> void:
	if native != null and native.has_method("mediaVolume"):
		native.call("mediaVolume", delta)


## Bring a player up and start it. Starting one *specific* playlist needs that
## app's own API; this presses play on whatever it last had, which is what you
## want at the start of a ride.
func media_launch(package: String = "com.spotify.music") -> void:
	if native != null and native.has_method("mediaLaunch"):
		native.call("mediaLaunch", package)
	elif _sim != null:
		_sim.music_playing = true


func now_playing() -> Dictionary:
	if native != null and native.has_method("nowPlaying"):
		var v: Variant = native.call("nowPlaying")
		if typeof(v) == TYPE_DICTIONARY:
			return v
	if _sim != null:
		return _sim.now_playing()
	return {}


func _media(method: String) -> void:
	if native != null and native.has_method(method):
		native.call(method)
	elif _sim != null:
		_sim.media_command(method)


# ---------------------------------------------------------------------- ble


func ble_available() -> bool:
	return native != null or simulating


func ble_scan(seconds: float = 8.0) -> void:
	if native != null and native.has_method("bleScan"):
		native.call("bleScan", seconds)
	elif _sim != null:
		_sim.fake_scan()


func ble_stop_scan() -> void:
	if native != null and native.has_method("bleStopScan"):
		native.call("bleStopScan")


func ble_connect(address: String) -> void:
	if native != null and native.has_method("bleConnect"):
		native.call("bleConnect", address)
	elif _sim != null:
		_sim.fake_connect(address)


func ble_disconnect(address: String = "") -> void:
	if native != null and native.has_method("bleDisconnect"):
		native.call("bleDisconnect", address)
	elif _sim != null:
		_sim.fake_disconnect(address)


func ble_subscribe(address: String, service: String, characteristic: String) -> void:
	if native != null and native.has_method("bleSubscribe"):
		native.call("bleSubscribe", address, service, characteristic)


func ble_read(address: String, service: String, characteristic: String) -> void:
	if native != null and native.has_method("bleRead"):
		native.call("bleRead", address, service, characteristic)
	elif _sim != null:
		_sim.fake_read(address, characteristic)


func ble_write(address: String, service: String, characteristic: String,
		data: PackedByteArray, with_response: bool = false) -> void:
	if native != null and native.has_method("bleWrite"):
		native.call("bleWrite", address, service, characteristic, data, with_response)
	elif _sim != null:
		_sim.fake_write(address, characteristic, data)


# ------------------------------------------------------------------- sim


func _start_simulator() -> void:
	simulating = true
	_sim = RideSimulator.new()
	_sim.bridge = self
	add_child(_sim)
	for k: String in permissions.keys():
		permissions[k] = true


func sim() -> RideSimulator:
	return _sim


## Stands in for the phone. Rides a plausible route at a plausible speed,
## drains a plausible battery, and every so often someone calls.
class RideSimulator extends Node:
	const BIKE_ADDR := "AA:BB:CC:00:11:22"
	const CART_ADDR := "AA:BB:CC:00:44:55"
	const CART_WH := 2400          ## A cart pack is the size of several bikes'.

	const SIM_TRACKS := [
		["Talking Heads", "Road to Nowhere"],
		["Neil Young", "Long May You Run"],
		["Khruangbin", "Maria Tambien"],
		["Bill Withers", "Lovely Day"],
		["Nina Simone", "Feeling Good"],
	]

	var bridge: Node
	var running := false
	var connected := false
	var speed_mps := 6.2          ## ~14 mph, a loaded ebike on the flat.
	var lat := 45.5231
	var lon := -122.6765
	var heading := 84.0
	var alt := 15.0
	var soc := 88.0
	var volts := 51.8
	var music_playing := true
	var cart_soc := 74.0
	var solar_wh_today := 0.0
	var solar_wh_total := 41850.0
	var regen := false
	var connected := {}
	var _t := 0.0
	var _fix_accum := 0.0
	var _drift := 0.0
	var _event_accum := 0.0
	var _last_speed := 0.0
	var _track_accum := 0.0
	var _track_i := 0


	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		var seed_pos: Dictionary = Logbook.last_fix() if Logbook != null else {}
		if not seed_pos.is_empty():
			lat = float(seed_pos["lat"])
			lon = float(seed_pos["lon"])

	func _process(delta: float) -> void:
		if not running:
			return
		# The simulator runs at wall-clock speed; a long session drifts the
		# route the way a real ride does, wandering with the road.
		_t += delta
		_drift += delta
		heading += sin(_t * 0.11) * 6.0 * delta
		speed_mps = clampf(speed_mps + (randf() - 0.5) * 0.6 * delta, 3.0, 9.0)
		alt += sin(_t * 0.03) * 2.0 * delta
		var step := speed_mps * delta
		var p := Geo.offset_m(lat, lon, heading, step)
		lat = p.x
		lon = p.y
		soc = maxf(0.0, soc - delta * 0.0025)
		volts = 42.0 + (soc / 100.0) * 12.6

		# The cart brakes regeneratively on the downhills, which here means
		# whenever the simulated speed is falling.
		regen = speed_mps < _last_speed - 0.01
		_last_speed = speed_mps
		var harvest := _solar_watts() * delta / 3600.0
		solar_wh_today += harvest
		solar_wh_total += harvest
		var drawn := (0.0 if regen else 210.0) * delta / 3600.0
		var returned := harvest + (240.0 * delta / 3600.0 if regen else 0.0)
		cart_soc = clampf(cart_soc + (returned - drawn) / CART_WH * 100.0, 0.0, 100.0)

		_fix_accum += delta
		if _fix_accum >= 2.0:
			_fix_accum = 0.0
			bridge.location_fix.emit({
				"t": Time.get_unix_time_from_system(),
				"lat": lat, "lon": lon, "alt": alt,
				"speed": speed_mps, "bearing": fposmod(heading, 360.0),
				"accuracy": 4.0 + randf() * 6.0, "provider": "sim",
			})

		_event_accum += delta
		if _event_accum >= 95.0:
			_event_accum = 0.0
			_random_event()

		if music_playing:
			_track_accum += delta
			if _track_accum >= 210.0:
				_track_accum = 0.0
				_track_i = (_track_i + 1) % SIM_TRACKS.size()
				bridge.media_changed.emit(now_playing())

	func now_playing() -> Dictionary:
		var t: Array = SIM_TRACKS[_track_i]
		return {
			"artist": t[0], "title": t[1], "album": "", "app": "Spotify",
			"playing": music_playing, "position_ms": int(_track_accum * 1000.0),
			"duration_ms": 210000,
		}

	func media_command(method: String) -> void:
		match method:
			"mediaPlayPause":
				music_playing = not music_playing
			"mediaNext":
				_track_i = (_track_i + 1) % SIM_TRACKS.size()
				_track_accum = 0.0
			"mediaPrev":
				_track_i = (_track_i - 1 + SIM_TRACKS.size()) % SIM_TRACKS.size()
				_track_accum = 0.0
		bridge.media_changed.emit(now_playing())

	func _random_event() -> void:
		match randi() % 4:
			0:
				bridge.call_logged.emit({
					"t": Time.get_unix_time_from_system(),
					"who": ["Mom", "Dana", "Unknown", "Bike shop"].pick_random(),
					"number": "+15035550142",
					"direction": ["in", "out", "missed"].pick_random(),
					"seconds": randi() % 900,
				})
			1:
				bridge.notification_posted.emit({
					"t": Time.get_unix_time_from_system(),
					"app": ["Signal", "Messenger", "SMS", "WhatsApp"].pick_random(),
					"who": ["Dana", "Group: Riders", "Mom"].pick_random(),
					"title": "New message",
					"text": "",
				})
			2:
				fake_photo()
			3:
				pass

	func fake_photo() -> void:
		bridge.photo_found.emit({
			"t": Time.get_unix_time_from_system(),
			"file": "", "lat": lat, "lon": lon, "width": 4032, "height": 3024,
			"simulated": true,
		})

	func backfill(_since: float) -> void:
		pass

	## Two peripherals, because the rig is two machines: the Saber's pack and
	## the cart's controller. Both are simulated well enough to exercise the
	## real parsing paths — the cart frames below are byte-for-byte what
	## docs/cart-telemetry.md asks the firmware to send, so the profile is
	## tested long before there is a cart to test it against.
	func fake_scan() -> void:
		bridge.ble_device_found.emit({
			"name": "SENADA-BMS", "address": BIKE_ADDR, "rssi": -58,
		})
		bridge.ble_device_found.emit({
			"name": "TRAIL-CART", "address": CART_ADDR, "rssi": -49,
		})
		bridge.ble_device_found.emit({
			"name": "Wahoo CADENCE", "address": "AA:BB:CC:00:11:33", "rssi": -78,
		})

	func fake_connect(address: String) -> void:
		connected[address] = true
		if address == CART_ADDR:
			bridge.ble_state.emit({"connected": true, "address": address, "name": "TRAIL-CART"})
			bridge.ble_services_discovered.emit(address, [{
				"service": CartProfile.SERVICE,
				"characteristics": [CartProfile.PACK, CartProfile.MOTORS,
					CartProfile.SOLAR, CartProfile.COMMAND, CartProfile.INFO],
			}])
			return
		bridge.ble_state.emit({"connected": true, "address": address, "name": "SENADA-BMS"})
		bridge.ble_services_discovered.emit(address, [
			{"service": "0000ff00-0000-1000-8000-00805f9b34fb",
			"characteristics": ["0000ff01-0000-1000-8000-00805f9b34fb",
				"0000ff02-0000-1000-8000-00805f9b34fb"]},
			{"service": "0000180f-0000-1000-8000-00805f9b34fb",
			"characteristics": ["00002a19-0000-1000-8000-00805f9b34fb"]},
		])

	func fake_disconnect(address: String) -> void:
		if address == "":
			for a: String in connected.keys():
				connected[a] = false
				bridge.ble_state.emit({"connected": false, "address": a})
			return
		connected[address] = false
		bridge.ble_state.emit({"connected": false, "address": address})

	func fake_read(address: String, uuid: String) -> void:
		if address == CART_ADDR and uuid.begins_with("0000c006"):
			bridge.ble_value.emit(address, CartProfile.INFO, _cart_info())
			return
		if uuid.begins_with("00002a19"):
			bridge.ble_value.emit(address, uuid, PackedByteArray([int(soc)]))

	func fake_write(address: String, _uuid: String, data: PackedByteArray) -> void:
		if address == CART_ADDR:
			if data.size() >= 1 and data[0] == CartProfile.CMD_REPORT:
				bridge.ble_value.emit(address, CartProfile.PACK, _cart_pack())
				bridge.ble_value.emit(address, CartProfile.MOTORS, _cart_motors())
				bridge.ble_value.emit(address, CartProfile.SOLAR, _cart_solar())
			return
		_jbd_reply(address, data)

	## Answers a JBD/Xiaoxiang-style 0x03 "basic info" request with a frame the
	## real profile parser has to chew on, so the parsing path is exercised off
	## the bike too.
	func _jbd_reply(address: String, data: PackedByteArray) -> void:
		if data.size() < 4 or data[0] != 0xDD or data[2] != 0x03:
			return
		var body := PackedByteArray()
		var mv := int(volts * 100.0)
		body.append_array([(mv >> 8) & 0xFF, mv & 0xFF])    # 0  total voltage, 10 mV
		var cur := (-520 + 65536) & 0xFFFF                  # 2  -5.2 A, discharging
		body.append_array([(cur >> 8) & 0xFF, cur & 0xFF])
		body.append_array([0x0B, 0xB8, 0x11, 0x94])         # 4  residual / nominal, 10 mAh
		body.append_array([0x00, 0x2A])                     # 8  cycles
		body.append_array([0x2B, 0x21, 0x00, 0x00, 0x00, 0x00])  # 10 date, balance bits
		body.append_array([0x00, 0x00])                     # 16 protection: all clear
		body.append_array([0x18])                           # 18 firmware version
		body.append_array([int(soc)])                       # 19 state of charge, %
		body.append_array([0x03, 0x0D, 0x02])               # 20 FET / cells / probes
		body.append_array([0x0B, 0xE6, 0x0B, 0xE0])         # 23 two probes, 0.1 K
		var frame := PackedByteArray([0xDD, 0x03, 0x00, body.size()])
		frame.append_array(body)
		var sum := 0
		for i in range(2, frame.size()):
			sum += frame[i]
		var chk := (0x10000 - sum) & 0xFFFF
		frame.append_array([(chk >> 8) & 0xFF, chk & 0xFF, 0x77])
		bridge.ble_value.emit(address, "0000ff01-0000-1000-8000-00805f9b34fb", frame)

	# -- cart frames, little-endian, exactly as the contract specifies

	static func _le16(v: int) -> PackedByteArray:
		var u := int(v) & 0xFFFF
		return PackedByteArray([u & 0xFF, (u >> 8) & 0xFF])

	static func _le32(v: int) -> PackedByteArray:
		var u := int(v) & 0xFFFFFFFF
		return PackedByteArray([u & 0xFF, (u >> 8) & 0xFF, (u >> 16) & 0xFF, (u >> 24) & 0xFF])

	func _cart_pack() -> PackedByteArray:
		var solar_w := _solar_watts()
		# Net current into the pack: the two motors pulling against whatever the
		# sun and any braking are putting back.
		var draw_w := 0.0 if regen else 210.0
		var net_w := solar_w + (240.0 if regen else 0.0) - draw_w
		var volts_cart := 52.0 + (cart_soc / 100.0) * 6.0
		var status := 0x02
		if net_w > 0.0:
			status = 0x01
		if solar_w > 5.0:
			status |= 0x10
		if regen:
			status |= 0x20
		var f := PackedByteArray([1, status])
		f.append_array(_le16(int(volts_cart * 100.0)))
		f.append_array(_le16(int(net_w / volts_cart * 100.0)))
		f.append_array([int(cart_soc)])
		f.append_array(_le16(int(CART_WH * cart_soc / 100.0)))
		f.append_array(_le16(CART_WH))
		f.append_array(_le16(int(24.0 * 10.0)))
		f.append_array(_le16(37))
		f.append_array(_le16(3810))
		f.append_array([18])
		return f

	func _cart_motors() -> PackedByteArray:
		var amps := -4.1 if regen else 2.05
		var rpm := int(speed_mps * 60.0 / 2.36)
		var f := PackedByteArray([1, 2])
		for m in 2:
			f.append_array(_le16(int(amps * 100.0)))
			f.append_array(_le16(int((52.0 + m * 4.0) * 10.0)))
			f.append_array(_le16(rpm))
		f.append_array([3 if regen else 0, 0])
		return f

	func _cart_solar() -> PackedByteArray:
		var w := _solar_watts()
		var panel_v := 34.0 if w > 5.0 else 0.0
		var f := PackedByteArray([1])
		f.append_array(_le16(int(panel_v * 100.0)))
		f.append_array(_le16(int((w / maxf(panel_v, 1.0)) * 100.0)))
		f.append_array(_le16(int(w)))
		f.append_array(_le16(int(solar_wh_today)))
		f.append_array(_le32(int(solar_wh_total)))
		f.append_array([0 if w > 5.0 else 4])
		return f

	func _cart_info() -> PackedByteArray:
		var f := PackedByteArray([1, 2])
		f.append_array(_le16(CART_WH))
		f.append_array(_le16(400))
		f.append_array(_le16(2360))
		var name := "sim-0.1".to_ascii_buffer()
		name.resize(12)
		f.append_array(name)
		return f

	## A believable solar curve: nothing at night, peaking near local noon,
	## knocked down a bit for the panel never being square to the sun.
	func _solar_watts() -> float:
		var bias: int = Time.get_time_zone_from_system().get("bias", 0)
		var d := Time.get_datetime_dict_from_unix_time(
			int(Time.get_unix_time_from_system()) + bias * 60)
		var hour := float(d["hour"]) + float(d["minute"]) / 60.0
		if hour < 6.5 or hour > 19.5:
			return 0.0
		var arc := sin(PI * (hour - 6.5) / 13.0)
		return maxf(0.0, 400.0 * arc * 0.78)
