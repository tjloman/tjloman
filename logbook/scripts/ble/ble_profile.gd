class_name BleProfile extends RefCounted
## Base class for "how to talk to this particular bike".
##
## Ebike electronics are a zoo. Some batteries expose a standard BLE Battery
## Service and nothing else; smart BMS boards speak their own framed protocol
## over a vendor characteristic; aftermarket sensors speak the standardized
## cycling profiles. Rather than pretend there is one answer, the manager
## sniffs the GATT table after connecting and hands it to whichever profile
## claims it.
##
## A profile turns bytes into a flat state dictionary. Recognized keys, all
## optional — the UI shows what it gets:
##
##   soc      state of charge, percent        volts    pack voltage
##   amps     current, negative = discharging  watts   instantaneous power
##   temp_c   pack temperature                 cells   Array of cell volts
##   cycles   charge cycles                    capacity_ah / remaining_ah
##   cadence  rpm                              wheel_speed_mps

## Short 16-bit UUIDs expand into the Bluetooth base UUID. Comparing
## normalized strings everywhere avoids a whole family of "why does it not
## match" bugs.
const BASE_SUFFIX := "-0000-1000-8000-00805f9b34fb"


static func norm_uuid(u: String) -> String:
	var s := u.strip_edges().to_lower()
	if s.length() == 4:
		return "0000%s%s" % [s, BASE_SUFFIX]
	if s.length() == 8:
		return "%s%s" % [s, BASE_SUFFIX]
	return s


static func short_uuid(u: String) -> String:
	var s := norm_uuid(u)
	if s.ends_with(BASE_SUFFIX) and s.begins_with("0000"):
		return s.substr(4, 4)
	return s


## Human name, shown in the connection sheet.
func profile_name() -> String:
	return "Generic"


## Does this profile recognize the connected device? `services` is the list
## the bridge discovered: [{service: uuid, characteristics: [uuid, ...]}, ...]
static func claims(_services: Array) -> bool:
	return false


## Subscribe to what you need. Called once, after discovery.
func start(_mgr: Node) -> void:
	pass


## Called on a timer for profiles that must ask rather than be told.
func poll(_mgr: Node) -> void:
	pass


## Turn a notification/read into a state patch. Return {} to ignore.
func decode(_uuid: String, _bytes: PackedByteArray) -> Dictionary:
	return {}


# ------------------------------------------------------------ byte helpers


static func u16(b: PackedByteArray, i: int) -> int:
	if i + 1 >= b.size():
		return 0
	return (b[i] << 8) | b[i + 1]


static func s16(b: PackedByteArray, i: int) -> int:
	var v := u16(b, i)
	return v - 65536 if v > 32767 else v


static func u16le(b: PackedByteArray, i: int) -> int:
	if i + 1 >= b.size():
		return 0
	return (b[i + 1] << 8) | b[i]


static func s16le(b: PackedByteArray, i: int) -> int:
	var v := u16le(b, i)
	return v - 65536 if v > 32767 else v


static func u32le(b: PackedByteArray, i: int) -> int:
	if i + 3 >= b.size():
		return 0
	return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)


static func hex(b: PackedByteArray) -> String:
	var out := ""
	for byte in b:
		out += "%02X " % byte
	return out.strip_edges()
