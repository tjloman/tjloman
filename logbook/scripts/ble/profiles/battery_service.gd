class_name BatteryServiceProfile extends BleProfile
## The standard Bluetooth Battery Service (0x180F / 0x2A19): one byte, the
## charge percentage.
##
## It is the least you can get, and a surprising number of ebike controllers
## and BMS dongles expose it even when their real protocol is proprietary. It
## is the fallback: if nothing better claims the device, this at least keeps a
## battery curve in the logbook.

const SERVICE := "180f"
const LEVEL := "2a19"


func profile_name() -> String:
	return "Battery Service"


static func claims(services: Array) -> bool:
	for s in services:
		if norm_uuid(String((s as Dictionary).get("service", ""))) == norm_uuid(SERVICE):
			return true
	return false


func start(mgr: Node) -> void:
	mgr.subscribe(SERVICE, LEVEL)
	mgr.read(SERVICE, LEVEL)


func poll(mgr: Node) -> void:
	# Some devices never send a notification until the level changes, which on
	# a big pack can be twenty minutes. Ask anyway.
	mgr.read(SERVICE, LEVEL)


func decode(uuid: String, bytes: PackedByteArray) -> Dictionary:
	if short_uuid(uuid) != LEVEL or bytes.is_empty():
		return {}
	return {"soc": float(bytes[0])}
