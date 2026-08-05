extends Node
## Autoload `Bike`: the rig's Bluetooth links and its energy ledger.
##
## This is not one battery. The rig is a Senada Saber pulling a powered cart
## with two motors, its own pack, a solar panel and regenerative braking — so
## the app tracks several devices at once, each with its own profile and its
## own state, and adds them up where it makes sense.
##
## The ledger is the part worth being careful about. Pack current is signed on
## both machines, so integrating it gives NET watt-hours: discharge counts up,
## solar and regen count back down. That single choice means the measured
## Wh/mile already includes everything the sun and the descents gave back, and
## the range estimate is a measurement rather than a guess. A long day down a
## mountain in sunshine can legitimately end with more energy aboard than it
## started with, and the numbers here will say so instead of clamping.

signal devices_changed
signal connection_changed(connected: bool)
signal state_changed(state: Dictionary)
signal explored(address: String, services: Array)

const RECONNECT_S := 20.0
const POLL_S := 4.0

## What a device is for. Only `house` is excluded from range: everything that
## can turn a wheel counts toward how far the rig gets.
const ROLE_BIKE := "bike"
const ROLE_CART := "cart"
const ROLE_HOUSE := "house"

var links := {}                     ## address -> PackLink
var found: Array[Dictionary] = []   ## Scan results.

# Today's energy ledger, in watt-hours.
var wh_out := 0.0                   ## Pulled from the packs.
var wh_regen := 0.0                 ## Returned by braking.
var wh_solar := 0.0                 ## Harvested.
var _ledger_day := ""
var _energy_start_m := 0.0

var _reconnect := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Bridge.ble_state.connect(_on_state)
	Bridge.ble_device_found.connect(_on_device_found)
	Bridge.ble_services_discovered.connect(_on_services)
	Bridge.ble_value.connect(_on_value)
	_ledger_day = Logbook.day_key(Time.get_unix_time_from_system())
	_energy_start_m = Logbook.total_m
	for entry in remembered():
		var link := _link_for(String(entry.get("address", "")))
		link.name = String(entry.get("name", ""))
		link.role = String(entry.get("role", ROLE_BIKE))
	if Cfg.get_b("ble_enabled") and not links.is_empty():
		# Remembered machines reconnect on their own. You should never have to
		# fiddle with a phone at the start of a ride.
		_reconnect = 2.0


func _process(delta: float) -> void:
	if not Cfg.get_b("ble_enabled"):
		return
	_roll_ledger()
	var any_disconnected := false
	for address: String in links.keys():
		var link: PackLink = links[address]
		if link.connected:
			link.poll_timer -= delta
			if link.poll_timer <= 0.0:
				link.poll_timer = POLL_S
				if link.profile != null:
					link.profile.poll(link)
		else:
			any_disconnected = true
	if not any_disconnected:
		return
	_reconnect -= delta
	if _reconnect <= 0.0:
		_reconnect = RECONNECT_S
		for address: String in links.keys():
			var link: PackLink = links[address]
			if not link.connected and not link.connecting:
				link.connecting = true
				Bridge.ble_connect(address)


# ------------------------------------------------------------------ control


func scan(seconds: float = 8.0) -> void:
	found.clear()
	devices_changed.emit()
	Bridge.ble_scan(seconds)


func connect_to(address: String, name: String = "", role: String = "") -> void:
	if address == "":
		return
	var link := _link_for(address)
	if name != "":
		link.name = name
	if role != "":
		link.role = role
	elif link.role == "":
		link.role = guess_role(link.name)
	link.connecting = true
	Bridge.ble_connect(address)
	remember()


## A cart announces itself. Anything else is assumed to be the bike until you
## say otherwise in the panel — one tap to fix, versus a wrong guess that
## silently keeps the cart's pack out of the range estimate.
static func guess_role(name: String) -> String:
	var n := name.to_lower()
	if n.contains("cart") or n.contains("trailer"):
		return ROLE_CART
	return ROLE_BIKE


func forget(address: String) -> void:
	if links.has(address):
		Bridge.ble_disconnect(address)
		links.erase(address)
	remember()
	devices_changed.emit()
	connection_changed.emit(any_connected())


func set_role(address: String, role: String) -> void:
	if not links.has(address):
		return
	(links[address] as PackLink).role = role
	remember()
	state_changed.emit(aggregate())


func remembered() -> Array:
	var stored: Array = Cfg.get_value("ble_devices")
	if not stored.is_empty():
		return stored
	# Carried over from the single-device version.
	var legacy := Cfg.get_s("ble_device")
	if legacy != "":
		return [{"address": legacy, "name": "", "role": ROLE_BIKE}]
	return []


func remember() -> void:
	var out: Array = []
	for address: String in links.keys():
		var link: PackLink = links[address]
		out.push_back({"address": address, "name": link.name, "role": link.role})
	Cfg.set_value("ble_devices", out)


func _link_for(address: String) -> PackLink:
	if links.has(address):
		return links[address]
	var link := PackLink.new()
	link.address = address
	links[address] = link
	return link


func any_connected() -> bool:
	for address: String in links.keys():
		if (links[address] as PackLink).connected:
			return true
	return false


func link_of_role(role: String) -> PackLink:
	for address: String in links.keys():
		var link: PackLink = links[address]
		if link.role == role:
			return link
	return null


func ordered_links() -> Array:
	var out: Array = []
	for address: String in links.keys():
		out.push_back(links[address])
	out.sort_custom(func(a: PackLink, b: PackLink) -> bool: return a.role < b.role)
	return out


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
	var address := String(s.get("address", ""))
	if address == "":
		return
	var link := _link_for(address)
	link.connecting = false
	var now_connected := bool(s.get("connected", false))
	var name := String(s.get("name", ""))
	if name != "":
		link.name = name
	if link.role == "":
		link.role = guess_role(link.name)
	if now_connected and not link.connected:
		link.connected = true
		link.poll_timer = 1.0
		Logbook.append_event(Ev.BIKE, {"text": "Connected to %s" % link.label()})
		remember()
	elif not now_connected and link.connected:
		link.connected = false
		link.profile = null
		Logbook.append_event(Ev.BIKE, {"text": "Lost link to %s" % link.label()})
	connection_changed.emit(any_connected())


func _on_services(address: String, list: Array) -> void:
	var link := _link_for(address)
	link.services = list
	explored.emit(address, list)
	link.profile = _pick_profile(list, link.role)
	if link.profile != null:
		link.profile.start(link)
		link.poll_timer = 1.0
	else:
		push_warning("Bike: nothing claimed %s — see its GATT list in the Bike panel"
			% link.label())


## Richest protocol first. The cart's own service is unmistakable; a smart BMS
## tells you far more than the standard battery byte, so it wins when both are
## present.
func _pick_profile(list: Array, role: String) -> BleProfile:
	match Cfg.get_s("ble_profile"):
		"cart":
			return CartProfile.new()
		"jbd":
			return JbdBmsProfile.new()
		"battery":
			return BatteryServiceProfile.new()
		"cycling":
			return CyclingProfile.new()
	if CartProfile.claims(list):
		return CartProfile.new()
	if JbdBmsProfile.claims(list):
		return JbdBmsProfile.new()
	if BatteryServiceProfile.claims(list):
		return BatteryServiceProfile.new()
	if CyclingProfile.claims(list):
		return CyclingProfile.new()
	if role == ROLE_CART:
		# A cart that has not learned to speak yet still gets a profile, so the
		# panel shows it as connected rather than broken.
		return CartProfile.new()
	return null


func _on_value(address: String, uuid: String, bytes: PackedByteArray) -> void:
	var link := _link_for(address)
	if link.profile == null:
		return
	var patch := link.profile.decode(uuid, bytes)
	if patch.is_empty():
		return
	for k: String in patch.keys():
		link.state[k] = patch[k]
	link.last_update = Time.get_unix_time_from_system()
	_integrate(link)
	_watch_thresholds(link)
	state_changed.emit(aggregate())


# ------------------------------------------------------------------- ledger


## Watt-hours in and out, integrated from the signed pack current. Solar and
## regen arrive as negative draw, which is what makes the day's Wh/mile a net
## figure instead of a gross one.
func _integrate(link: PackLink) -> void:
	if not link.state.has("watts"):
		return
	var now := Time.get_unix_time_from_system()
	if link.last_power_t > 0.0:
		var dt := now - link.last_power_t
		# A gap means the app or the link was asleep; we have no idea what the
		# current did in between, and inventing it would corrupt the ledger.
		if dt > 0.0 and dt < 120.0:
			var watts := float(link.state["watts"])
			var wh := absf(watts) * dt / 3600.0
			if watts < 0.0:
				link.wh_out += wh
				wh_out += wh
			else:
				link.wh_in += wh
				# Which way the energy came back is worth separating: solar is
				# a function of the sky, regen of the terrain.
				if bool(link.state.get("regenerating", false)):
					wh_regen += wh
				elif bool(link.state.get("solar_feeding", false)):
					wh_solar += wh
			link.state["wh_out"] = link.wh_out
			link.state["wh_in"] = link.wh_in
	link.last_power_t = now
	# The cart's own controller counts harvest across reboots; trust it over
	# our integration when it is offered.
	if link.state.has("solar_wh_today"):
		wh_solar = maxf(wh_solar, float(link.state["solar_wh_today"]))


func _roll_ledger() -> void:
	var key := Logbook.day_key(Time.get_unix_time_from_system())
	if key == _ledger_day:
		return
	_ledger_day = key
	wh_out = 0.0
	wh_regen = 0.0
	wh_solar = 0.0
	_energy_start_m = Logbook.total_m
	for address: String in links.keys():
		var link: PackLink = links[address]
		link.wh_out = 0.0
		link.wh_in = 0.0


func _watch_thresholds(link: PackLink) -> void:
	var fault := String(link.state.get("fault", ""))
	if fault != "" and fault != link.last_fault:
		link.last_fault = fault
		Logbook.append_event(Ev.BIKE, {"text": "%s: %s" % [link.label(), fault]})
		Bridge.notify(link.label(), fault)
	# A motor cooking on a climb is the one thing you want to hear about before
	# it derates and you wonder why the cart went heavy.
	if link.state.has("motor_temp_c"):
		var temp := float(link.state["motor_temp_c"])
		if temp > 85.0 and not link.warned_hot:
			link.warned_hot = true
			Bridge.notify("Cart motor %d °C" % int(temp), "Ease off or it will derate.")
			Logbook.append_event(Ev.BIKE, {"text": "Cart motor at %d °C" % int(temp)})
		elif temp < 75.0:
			link.warned_hot = false
	if not link.state.has("soc"):
		return
	var soc := float(link.state["soc"])
	var warn := float(Cfg.get_i("low_battery_warn_pct"))
	if soc <= warn and not link.warned_low:
		link.warned_low = true
		Bridge.notify("%s at %d%%" % [link.label(), int(soc)],
			"About %s of range left at today's rate." % Cfg.dist(range_estimate_m()))
		Logbook.append_event(Ev.BIKE, {"text": "%s down to %d%%" % [link.label(), int(soc)]})
	elif soc > warn + 5.0:
		link.warned_low = false


# ------------------------------------------------------------------ totals


## The whole rig as one dictionary: energy that can reach a wheel, the worst
## state of charge across packs, and whatever the cart is doing.
func aggregate() -> Dictionary:
	var wh_left := 0.0
	var wh_capacity := 0.0
	var worst_soc := -1.0
	var watts := 0.0
	var out := {}
	for address: String in links.keys():
		var link: PackLink = links[address]
		if not link.connected:
			continue
		if link.role != ROLE_HOUSE:
			wh_left += link.wh_remaining()
			wh_capacity += link.wh_capacity()
			watts += float(link.state.get("watts", 0.0))
			if link.state.has("soc"):
				var soc := float(link.state["soc"])
				worst_soc = soc if worst_soc < 0.0 else minf(worst_soc, soc)
		for key: String in ["solar_watts", "solar_wh_today", "solar_state",
				"motor_temp_c", "regen_level", "regenerating", "derating"]:
			if link.state.has(key):
				out[key] = link.state[key]
	out["wh_left"] = wh_left
	out["wh_capacity"] = wh_capacity
	out["watts"] = watts
	out["soc"] = maxf(0.0, worst_soc)
	out["packs"] = links.size()
	out["wh_out_today"] = wh_out
	out["wh_regen_today"] = wh_regen
	out["wh_solar_today"] = wh_solar
	return out


## Meters of range left, from measured net watt-hours per meter — which
## already has solar and regen in it. Falls back to the configured pack sizes
## and a typical draw until there is enough measured history to beat a guess.
func range_estimate_m() -> float:
	var totals := aggregate()
	var wh_left := float(totals["wh_left"])
	if wh_left <= 0.0:
		# Nothing reported capacity yet: fall back to what the rig is
		# configured to carry, scaled by whatever charge we do know about.
		var configured := Cfg.get_f("battery_wh") + Cfg.get_f("cart_battery_wh")
		wh_left = configured * maxf(0.0, float(totals["soc"])) / 100.0
	var meters := Logbook.total_m - _energy_start_m
	var net := wh_out - wh_regen - wh_solar
	if net > 20.0 and meters > 2000.0:
		return wh_left / maxf(net / meters, 0.0001)
	return wh_left / (Cfg.get_f("assumed_wh_per_mile") / Geo.METERS_PER_MILE)


## Net watt-hours per mile (or km) so far today — the number that actually
## predicts the day, and the one a loaded cart changes most.
func consumption_per_unit() -> float:
	var meters := Logbook.total_m - _energy_start_m
	if meters < 500.0:
		return 0.0
	var net := wh_out - wh_regen - wh_solar
	var unit := 1000.0 if Cfg.is_metric() else Geo.METERS_PER_MILE
	return net / (meters / unit)


## One line for the status bar: the number you glance at while riding.
func summary_line() -> String:
	if not any_connected():
		return "rig: no link"
	var totals := aggregate()
	var s := "%d%%" % int(float(totals["soc"]))
	if float(totals["wh_left"]) > 0.0:
		s += "  %d Wh" % int(float(totals["wh_left"]))
	var watts := float(totals["watts"])
	if absf(watts) > 1.0:
		s += "  %dW" % int(absf(watts))
		if watts > 0.0:
			s += "↑"   # energy coming back in
	var solar := float(totals.get("solar_watts", 0.0))
	if solar > 5.0:
		s += "  ☀%dW" % int(solar)
	return s


# --------------------------------------------------------------------- link


## One connected machine. Profiles are handed this as their "manager", so the
## read/write/subscribe calls they make are automatically scoped to the right
## device — the profile code has no idea there is more than one.
class PackLink extends RefCounted:
	var address := ""
	var name := ""
	var role := ""
	var connected := false
	var connecting := false
	var profile: BleProfile = null
	var services: Array = []
	var state := {}
	var last_update := 0.0
	var poll_timer := 0.0
	var wh_out := 0.0
	var wh_in := 0.0
	var last_power_t := 0.0
	var last_fault := ""
	var warned_low := false
	var warned_hot := false

	func label() -> String:
		if name != "":
			return name
		match role:
			"cart": return "cart"
			"house": return "house battery"
		return "bike"

	## Energy left in this pack: reported directly if the BMS knows, otherwise
	## inferred from state of charge and the configured capacity.
	func wh_remaining() -> float:
		if state.has("wh_remaining"):
			return float(state["wh_remaining"])
		return wh_capacity() * float(state.get("soc", 0.0)) / 100.0

	func wh_capacity() -> float:
		if state.has("wh_capacity"):
			return float(state["wh_capacity"])
		return Cfg.get_f("cart_battery_wh") if role == "cart" else Cfg.get_f("battery_wh")

	func subscribe(service: String, characteristic: String) -> void:
		Bridge.ble_subscribe(address, BleProfile.norm_uuid(service),
			BleProfile.norm_uuid(characteristic))

	func read(service: String, characteristic: String) -> void:
		Bridge.ble_read(address, BleProfile.norm_uuid(service),
			BleProfile.norm_uuid(characteristic))

	func write(service: String, characteristic: String, data: PackedByteArray) -> void:
		Bridge.ble_write(address, BleProfile.norm_uuid(service),
			BleProfile.norm_uuid(characteristic), data, false)
