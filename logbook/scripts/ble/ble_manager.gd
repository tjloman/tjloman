extends Node
## Autoload `Bike`: the ebike's Bluetooth link.
##
## Scan, connect, pick a profile from what the device actually exposes, keep a
## live state dictionary, and hand periodic samples to the logbook so the trip
## has a battery curve next to its elevation curve.
##
## It also does the thing that matters on a long day: watch the energy going
## out of the pack and turn it into an honest range estimate — Wh per mile so
## far, applied to what is left, rather than the manufacturer's number.

signal devices_changed
signal connection_changed(connected: bool)
signal state_changed(state: Dictionary)
signal explored(services: Array)

const RECONNECT_S := 20.0
const POLL_S := 4.0

var connected := false
var connecting := false
var device := {}                    ## {name, address}
var state := {}                     ## Whatever the profile could decode.
var services: Array = []            ## Raw GATT table from the last discovery.
var found: Array[Dictionary] = []   ## Scan results.
var profile: BleProfile = null
var last_update := 0.0

var _poll := 0.0
var _reconnect := 0.0
var _wh_used := 0.0
var _last_power_t := 0.0
var _energy_start_m := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Bridge.ble_state.connect(_on_state)
	Bridge.ble_device_found.connect(_on_device_found)
	Bridge.ble_services_discovered.connect(_on_services)
	Bridge.ble_value.connect(_on_value)
	if Cfg.get_b("ble_enabled") and Cfg.get_s("ble_device") != "":
		# Remembered bike: reconnect without being asked. You should never have
		# to fiddle with a phone at the start of a ride.
		_reconnect = 2.0


func _process(delta: float) -> void:
	if not Cfg.get_b("ble_enabled"):
		return
	if connected:
		_poll -= delta
		if _poll <= 0.0:
			_poll = POLL_S
			if profile != null:
				profile.poll(self)
		return
	if Cfg.get_s("ble_device") != "" and not connecting:
		_reconnect -= delta
		if _reconnect <= 0.0:
			_reconnect = RECONNECT_S
			connect_to(Cfg.get_s("ble_device"), "")


# ------------------------------------------------------------------ control


func scan(seconds: float = 8.0) -> void:
	found.clear()
	devices_changed.emit()
	Bridge.ble_scan(seconds)


func connect_to(address: String, name: String = "") -> void:
	if address == "":
		return
	connecting = true
	device = {"address": address, "name": name}
	Bridge.ble_connect(address)


func forget() -> void:
	Cfg.set_value("ble_device", "")
	disconnect_bike()


func disconnect_bike() -> void:
	Bridge.ble_disconnect()
	connected = false
	connecting = false
	profile = null
	connection_changed.emit(false)


func subscribe(service: String, characteristic: String) -> void:
	Bridge.ble_subscribe(BleProfile.norm_uuid(service), BleProfile.norm_uuid(characteristic))


func read(service: String, characteristic: String) -> void:
	Bridge.ble_read(BleProfile.norm_uuid(service), BleProfile.norm_uuid(characteristic))


func write(service: String, characteristic: String, data: PackedByteArray) -> void:
	Bridge.ble_write(BleProfile.norm_uuid(service), BleProfile.norm_uuid(characteristic), data, false)


# ------------------------------------------------------------------ signals


func _on_device_found(d: Dictionary) -> void:
	for existing in found:
		if String(existing.get("address", "")) == String(d.get("address", "")):
			existing["rssi"] = int(d.get("rssi", 0))
			devices_changed.emit()
			return
	found.push_back(d)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("rssi", -999)) > int(b.get("rssi", -999)))
	devices_changed.emit()


func _on_state(s: Dictionary) -> void:
	var now_connected := bool(s.get("connected", false))
	connecting = false
	if now_connected:
		device = {
			"address": String(s.get("address", device.get("address", ""))),
			"name": String(s.get("name", device.get("name", ""))),
		}
		Cfg.set_value("ble_device", String(device["address"]))
		connected = true
		_reconnect = RECONNECT_S
		Logbook.append_event(Ev.BIKE, {"text": "Connected to %s" % device.get("name", "bike")})
	else:
		if connected:
			Logbook.append_event(Ev.BIKE, {"text": "Bluetooth link lost"})
		connected = false
		profile = null
	connection_changed.emit(connected)


func _on_services(list: Array) -> void:
	services = list
	explored.emit(list)
	profile = _pick_profile(list)
	if profile != null:
		profile.start(self)
		_poll = 1.0
	else:
		push_warning("Bike: no profile claimed this device — see the GATT list in Settings")


## First match wins, richest protocol first: a smart BMS tells you far more
## than the standard battery byte, so prefer it when both are present.
func _pick_profile(list: Array) -> BleProfile:
	var forced := Cfg.get_s("ble_profile")
	match forced:
		"jbd":
			return JbdBmsProfile.new()
		"battery":
			return BatteryServiceProfile.new()
		"cycling":
			return CyclingProfile.new()
	if JbdBmsProfile.claims(list):
		return JbdBmsProfile.new()
	if BatteryServiceProfile.claims(list):
		return BatteryServiceProfile.new()
	if CyclingProfile.claims(list):
		return CyclingProfile.new()
	return null


func _on_value(uuid: String, bytes: PackedByteArray) -> void:
	if profile == null:
		return
	var patch := profile.decode(uuid, bytes)
	if patch.is_empty():
		return
	for k: String in patch.keys():
		state[k] = patch[k]
	last_update = Time.get_unix_time_from_system()
	_integrate_energy()
	_watch_thresholds()
	state_changed.emit(state)


## Watt-hours out of the pack, integrated from the current readings. This is
## what makes "range left" mean anything: a loaded bike into a headwind pulls
## twice what the spec sheet assumes.
func _integrate_energy() -> void:
	if not state.has("watts"):
		return
	var now := Time.get_unix_time_from_system()
	if _last_power_t > 0.0:
		var dt := now - _last_power_t
		if dt > 0.0 and dt < 120.0:
			var w: float = absf(float(state["watts"]))
			_wh_used += w * dt / 3600.0
			state["wh_used"] = _wh_used
	else:
		_energy_start_m = Logbook.total_m
	_last_power_t = now


func _watch_thresholds() -> void:
	if not state.has("soc"):
		return
	var soc := float(state["soc"])
	var warn := float(Cfg.get_i("low_battery_warn_pct"))
	if soc <= warn and not bool(state.get("warned_low", false)):
		state["warned_low"] = true
		Bridge.notify("Battery %d%%" % int(soc), "About %s of range left at today's rate."
			% Cfg.dist(range_estimate_m()))
		Logbook.append_event(Ev.BIKE, {"text": "Battery down to %d%%" % int(soc)})
	elif soc > warn + 5.0:
		state["warned_low"] = false
	var fault := String(state.get("fault", ""))
	if fault != "" and fault != String(state.get("last_fault", "")):
		state["last_fault"] = fault
		Logbook.append_event(Ev.BIKE, {"text": "BMS protection: %s" % fault})
		Bridge.notify("Battery protection", fault)


## Meters of range left, from measured Wh per meter on this trip. Falls back
## to the configured pack size and a typical 12 Wh/mile when there is not
## enough measured history to be worth trusting.
func range_estimate_m() -> float:
	var soc := float(state.get("soc", 0.0)) / 100.0
	var pack_wh := Cfg.get_f("battery_wh")
	var wh_left := pack_wh * soc
	var meters := Logbook.total_m - _energy_start_m
	if _wh_used > 20.0 and meters > 2000.0:
		var wh_per_m := _wh_used / meters
		return wh_left / maxf(wh_per_m, 0.0001)
	return wh_left / (12.0 / Geo.METERS_PER_MILE)


## One line for the status bar: the number you glance at while riding.
func summary_line() -> String:
	if not connected:
		return "bike: not connected"
	if state.has("soc"):
		var s := "%d%%" % int(float(state["soc"]))
		if state.has("volts"):
			s += "  %.1fV" % float(state["volts"])
		if state.has("watts") and absf(float(state["watts"])) > 1.0:
			s += "  %dW" % int(absf(float(state["watts"])))
		return s
	return "bike: connected"
