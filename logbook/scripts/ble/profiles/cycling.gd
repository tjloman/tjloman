class_name CyclingProfile extends BleProfile
## The standardized cycling sensors: Cycling Power (0x1818) and Cycling Speed
## and Cadence (0x1816).
##
## Not a battery profile — this is for the sensors an ebike or a bolt-on
## computer already broadcasts. Cadence and wheel-derived speed are worth
## logging next to the GPS trace: wheel speed keeps working under a bridge,
## and cadence is what tells you, months later, whether that slow hour was a
## headwind or a long lunch.

const CSC_SERVICE := "1816"
const CSC_MEASURE := "2a5b"
const CPS_SERVICE := "1818"
const CPS_MEASURE := "2a63"

## Default 700x40C. Configurable later; a 3% error here is a 3% error in
## wheel-speed, which is still better than nothing in a tunnel.
var wheel_circumference_m := 2.168

var _last_wheel_revs := -1
var _last_wheel_time := -1
var _last_crank_revs := -1
var _last_crank_time := -1


func profile_name() -> String:
	return "Cycling sensors"


static func claims(services: Array) -> bool:
	for s in services:
		var u := norm_uuid(String((s as Dictionary).get("service", "")))
		if u == norm_uuid(CSC_SERVICE) or u == norm_uuid(CPS_SERVICE):
			return true
	return false


func start(mgr: Node) -> void:
	mgr.subscribe(CSC_SERVICE, CSC_MEASURE)
	mgr.subscribe(CPS_SERVICE, CPS_MEASURE)


func decode(uuid: String, bytes: PackedByteArray) -> Dictionary:
	match short_uuid(uuid):
		CSC_MEASURE:
			return _decode_csc(bytes)
		CPS_MEASURE:
			return _decode_power(bytes)
	return {}


## CSC: a flags byte, then optionally a cumulative wheel revolution count with
## a 1/1024 s timestamp, then optionally the same for the crank. Speed and
## cadence are differences between consecutive packets, and the timestamps
## wrap every 64 seconds.
func _decode_csc(b: PackedByteArray) -> Dictionary:
	if b.is_empty():
		return {}
	var flags := b[0]
	var i := 1
	var out := {}
	if flags & 0x01 and b.size() >= i + 6:
		var revs := u32le(b, i)
		var t := u16le(b, i + 4)
		i += 6
		if _last_wheel_time >= 0 and t != _last_wheel_time:
			var dt := float((t - _last_wheel_time + 65536) % 65536) / 1024.0
			var dr := (revs - _last_wheel_revs + 4294967296) % 4294967296
			if dt > 0.0 and dt < 30.0:
				out["wheel_speed_mps"] = float(dr) * wheel_circumference_m / dt
				out["wheel_distance_m"] = float(revs) * wheel_circumference_m
		_last_wheel_revs = revs
		_last_wheel_time = t
	if flags & 0x02 and b.size() >= i + 4:
		var crevs := u16le(b, i)
		var ct := u16le(b, i + 2)
		if _last_crank_time >= 0 and ct != _last_crank_time:
			var dt := float((ct - _last_crank_time + 65536) % 65536) / 1024.0
			var dr := (crevs - _last_crank_revs + 65536) % 65536
			if dt > 0.0 and dt < 30.0:
				out["cadence"] = float(dr) * 60.0 / dt
		_last_crank_revs = crevs
		_last_crank_time = ct
	return out


func _decode_power(b: PackedByteArray) -> Dictionary:
	if b.size() < 4:
		return {}
	return {"rider_watts": float(s16le(b, 2))}
