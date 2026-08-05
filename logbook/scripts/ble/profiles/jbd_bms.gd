class_name JbdBmsProfile extends BleProfile
## JBD / Xiaoxiang / "smart BMS" — the board inside a very large share of
## aftermarket and OEM ebike batteries, and the one worth supporting first
## because it reports everything: pack voltage, current, per-cell voltages,
## temperature, cycles, and the protection state that tells you *why* the bike
## just cut out on a climb.
##
## Protocol: framed messages over a vendor service (0xFF00), write to 0xFF02,
## notifications on 0xFF01.
##
##   request   DD A5 <cmd> 00 FF <chk_hi> <chk_lo> 77
##   response  DD <cmd> <status> <len> <payload...> <chk_hi> <chk_lo> 77
##
## The checksum is 0x10000 minus the sum of everything between the command
## byte and the checksum. Frames arrive split across BLE notifications, so
## incoming bytes are accumulated until a whole one is present.

const SERVICE := "ff00"
const NOTIFY := "ff01"
const WRITE := "ff02"

const CMD_BASIC := 0x03
const CMD_CELLS := 0x04

var _rx := PackedByteArray()
var _want_cells := true


func profile_name() -> String:
	return "Smart BMS (JBD)"


static func claims(services: Array) -> bool:
	for s in services:
		var d: Dictionary = s
		if norm_uuid(String(d.get("service", ""))) != norm_uuid(SERVICE):
			continue
		var chars: Array = d.get("characteristics", [])
		var has_notify := false
		var has_write := false
		for c in chars:
			var u := short_uuid(String(c))
			has_notify = has_notify or u == NOTIFY
			has_write = has_write or u == WRITE
		if has_notify and has_write:
			return true
	return false


func start(mgr: Node) -> void:
	mgr.subscribe(SERVICE, NOTIFY)
	poll(mgr)


func poll(mgr: Node) -> void:
	mgr.write(SERVICE, WRITE, _request(CMD_BASIC))
	if _want_cells:
		mgr.write(SERVICE, WRITE, _request(CMD_CELLS))


static func _request(cmd: int) -> PackedByteArray:
	var sum := cmd + 0x00
	var chk := (0x10000 - sum) & 0xFFFF
	return PackedByteArray([0xDD, 0xA5, cmd, 0x00, (chk >> 8) & 0xFF, chk & 0xFF, 0x77])


func decode(uuid: String, bytes: PackedByteArray) -> Dictionary:
	if short_uuid(uuid) != NOTIFY:
		return {}
	_rx.append_array(bytes)
	# Resync: if the buffer does not start with a header, throw away noise
	# until it does. Cheaper than failing every frame after one glitch.
	while _rx.size() > 0 and _rx[0] != 0xDD:
		_rx = _rx.slice(1)
	if _rx.size() < 7:
		return {}
	var length := _rx[3]
	var total := length + 7
	if _rx.size() < total:
		return {}
	var frame := _rx.slice(0, total)
	_rx = _rx.slice(total)
	if frame[total - 1] != 0x77:
		return {}
	var sum := 0
	for i in range(2, total - 3):
		sum += frame[i]
	if ((0x10000 - sum) & 0xFFFF) != u16(frame, total - 3):
		return {}
	var payload := frame.slice(4, 4 + length)
	match frame[1]:
		CMD_BASIC:
			return _decode_basic(payload)
		CMD_CELLS:
			return _decode_cells(payload)
	return {}


func _decode_basic(p: PackedByteArray) -> Dictionary:
	if p.size() < 23:
		return {}
	var volts := u16(p, 0) * 0.01
	var amps := s16(p, 2) * 0.01
	var out := {
		"volts": volts,
		"amps": amps,
		"watts": volts * amps,
		"remaining_ah": u16(p, 4) * 0.01,
		"capacity_ah": u16(p, 6) * 0.01,
		"cycles": u16(p, 8),
		"protection": u16(p, 16),
		"soc": float(p[19]),
		"cell_count": p[21],
	}
	var ntc := int(p[22])
	if ntc > 0 and p.size() >= 23 + ntc * 2:
		var hottest := -273.0
		for i in ntc:
			# Tenths of a Kelvin, offset by 273.1 K.
			var c := (u16(p, 23 + i * 2) - 2731) * 0.1
			hottest = maxf(hottest, c)
		out["temp_c"] = hottest
	out["fault"] = _fault_text(int(out["protection"]))
	return out


func _decode_cells(p: PackedByteArray) -> Dictionary:
	var n := p.size() / 2
	if n < 3:
		_want_cells = false   # not a pack that reports cells; stop asking
		return {}
	var cells := PackedFloat32Array()
	for i in n:
		cells.push_back(u16(p, i * 2) * 0.001)
	var lo := INF
	var hi := -INF
	for v in cells:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return {"cells": cells, "cell_min": lo, "cell_max": hi, "cell_spread": hi - lo}


## The protection bitfield is the single most useful thing a BMS tells you,
## because it explains a cut-out that otherwise looks like a broken bike.
static func _fault_text(bits: int) -> String:
	if bits == 0:
		return ""
	const FAULTS := [
		"cell overvoltage", "cell undervoltage", "pack overvoltage", "pack undervoltage",
		"charge over-temp", "charge under-temp", "discharge over-temp", "discharge under-temp",
		"charge overcurrent", "discharge overcurrent", "short circuit",
		"front-end error", "software lock",
	]
	var out: Array[String] = []
	for i in FAULTS.size():
		if bits & (1 << i):
			out.push_back(FAULTS[i])
	return ", ".join(out)
