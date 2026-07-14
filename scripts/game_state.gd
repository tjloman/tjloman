extends Node
## Autoload singleton: global divine resources and announcements.
## Access anywhere as `GameState`.

signal prayer_power_changed(value: float, max_value: float)
signal announcement(text: String)

var prayer_power: float = 60.0
var max_prayer_power: float = 100.0


func add_prayer_power(amount: float) -> void:
	prayer_power = clampf(prayer_power + amount, 0.0, max_prayer_power)
	prayer_power_changed.emit(prayer_power, max_prayer_power)


func try_spend(amount: float) -> bool:
	if prayer_power < amount:
		return false
	prayer_power -= amount
	prayer_power_changed.emit(prayer_power, max_prayer_power)
	return true


func set_max_prayer_power(new_max: float) -> void:
	max_prayer_power = new_max
	prayer_power = minf(prayer_power, max_prayer_power)
	prayer_power_changed.emit(prayer_power, max_prayer_power)


func announce(text: String) -> void:
	announcement.emit(text)
