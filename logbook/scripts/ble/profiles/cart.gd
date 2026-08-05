class_name CartProfile extends BleProfile
## The custom cart: two motors, its own pack, solar, and regenerative braking.
##
## This implements the contract in `docs/cart-telemetry.md`, which was written
## before the cart existed so the firmware has something fixed to build
## against. Three small notify characteristics, every frame inside the 20-byte
## payload of a default-MTU notification, all fields little-endian — a packed
## struct memcpy'd out of an ESP32 is a valid frame.
##
## What makes the cart different from any stock ebike protocol: energy flows
## both ways. Pack current is signed, so solar income and regen braking come
## back through the same number that discharge does, and the app's measured
## watt-hours per mile is a NET figure. A long descent can genuinely end with
## more in the pack than it started with, and the range estimate should say so.

const SERVICE := "0000c001-6361-7274-8000-00805f9b34fb"
const PACK := "0000c002-6361-7274-8000-00805f9b34fb"
const MOTORS := "0000c003-6361-7274-8000-00805f9b34fb"
const SOLAR := "0000c004-6361-7274-8000-00805f9b34fb"
const COMMAND := "0000c005-6361-7274-8000-00805f9b34fb"
const INFO := "0000c006-6361-7274-8000-00805f9b34fb"

const CMD_LIGHTS := 0x01
const CMD_REGEN := 0x02
const CMD_ASSIST := 0x03
const CMD_CHARGE_BIKE := 0x04
const CMD_REPORT := 0x05

const MPPT_STATES := ["tracking", "bulk", "absorption", "float", "off"]


func profile_name() -> String:
	return "Cart"


static func claims(services: Array) -> bool:
	for s in services:
		if norm_uuid(String((s as Dictionary).get("service", ""))) == norm_uuid(SERVICE):
			return true
	return false


func start(mgr: Node) -> void:
	mgr.subscribe(SERVICE, PACK)
	mgr.subscribe(SERVICE, MOTORS)
	mgr.subscribe(SERVICE, SOLAR)
	mgr.read(SERVICE, INFO)
	# Ask for one of everything rather than waiting up to a second for the
	# first notify: the panel should be populated by the time you look at it.
	command(mgr, CMD_REPORT, 0)


func poll(mgr: Node) -> void:
	command(mgr, CMD_REPORT, 0)


static func command(mgr: Node, opcode: int, value: int) -> void:
	mgr.write(SERVICE, COMMAND, PackedByteArray([opcode, clampi(value, 0, 255)]))


func decode(uuid: String, bytes: PackedByteArray) -> Dictionary:
	# An if-chain rather than a match: match patterns want constants, and these
	# have to go through uuid normalization first.
	var u := norm_uuid(uuid)
	if u == norm_uuid(PACK):
		return _pack(bytes)
	if u == norm_uuid(MOTORS):
		return _motors(bytes)
	if u == norm_uuid(SOLAR):
		return _solar(bytes)
	if u == norm_uuid(INFO):
		return _info(bytes)
	return {}


func _pack(b: PackedByteArray) -> Dictionary:
	if b.size() < 18 or b[0] != 1:
		return {}
	var status := int(b[1])
	var volts := u16le(b, 2) * 0.01
	# Positive is INTO the pack. The rest of the app uses the ebike convention
	# (negative = discharging), so the sign flips here, once, rather than in
	# five places that display it.
	var amps := -s16le(b, 4) * 0.01
	var out := {
		"volts": volts,
		"amps": amps,
		"watts": volts * amps,
		"soc": float(b[6]),
		"wh_remaining": float(u16le(b, 7)),
		"wh_capacity": float(u16le(b, 9)),
		"temp_c": s16le(b, 11) * 0.1,
		"cycles": u16le(b, 13),
		"cell_min": u16le(b, 15) * 0.001,
		"cell_spread": float(b[17]) * 0.001,
		"charging": (status & 0x01) != 0,
		"balancing": (status & 0x04) != 0,
		"solar_feeding": (status & 0x10) != 0,
		"regen_feeding": (status & 0x20) != 0,
	}
	if (status & 0x08) != 0:
		out["fault"] = "cart BMS protection"
	return out


func _motors(b: PackedByteArray) -> Dictionary:
	if b.size() < 16 or b[0] != 1:
		return {}
	var count := mini(int(b[1]), 2)
	var motors: Array = []
	var hottest := -273.0
	var regenerating := false
	for i in count:
		var base := 2 + i * 6
		var amps := s16le(b, base) * 0.01
		var temp := s16le(b, base + 2) * 0.1
		motors.push_back({"amps": amps, "temp_c": temp, "rpm": u16le(b, base + 4)})
		hottest = maxf(hottest, temp)
		if amps < -0.2:
			regenerating = true
	var out := {
		"motors": motors,
		"motor_temp_c": hottest,
		"regen_level": int(b[14]),
		"regenerating": regenerating,
		"derating": (int(b[15]) & 0x01) != 0,
	}
	if (int(b[15]) & 0x02) != 0:
		out["fault"] = "cart motor controller fault"
	return out


func _solar(b: PackedByteArray) -> Dictionary:
	if b.size() < 14 or b[0] != 1:
		return {}
	var state := int(b[13])
	return {
		"solar_volts": u16le(b, 1) * 0.01,
		"solar_amps": u16le(b, 3) * 0.01,
		"solar_watts": float(s16le(b, 5)),
		"solar_wh_today": float(u16le(b, 7)),
		"solar_wh_total": float(u32le(b, 9)),
		"solar_state": MPPT_STATES[state] if state < MPPT_STATES.size() else "?",
	}


func _info(b: PackedByteArray) -> Dictionary:
	if b.size() < 8 or b[0] != 1:
		return {}
	var firmware := ""
	if b.size() >= 20:
		firmware = b.slice(8, 20).get_string_from_ascii().strip_edges()
	return {
		"motor_count": int(b[1]),
		"wh_capacity": float(u16le(b, 2)),
		"solar_watts_peak": float(u16le(b, 4)),
		"wheel_mm": float(u16le(b, 6)),
		"firmware": firmware,
	}
