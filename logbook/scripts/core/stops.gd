class_name Stops
## Planned stops: opening hours, arrival estimates, and the one photo that
## makes a stop recognizable from the road.
##
## The question this exists to answer is not "where is the diner" — any map
## does that — but "will it still be open when I get there, at the speed I am
## actually going". That is a function of hours, distance along the route, and
## the average moving speed of the day so far, and it is worth being exact
## about because getting it wrong means a closed door at dusk.

const DAYS := ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
const CATEGORIES := ["food", "water", "charge", "camp", "lodging", "resupply",
	"bike shop", "viewpoint", "other"]


static func category_glyph(cat: String) -> String:
	match cat:
		"food": return "🍽"
		"water": return "💧"
		"charge": return "⚡"
		"camp": return "⛺"
		"lodging": return "🛏"
		"resupply": return "🛒"
		"bike shop": return "🔧"
		"viewpoint": return "★"
	return "⚑"


## Parse a day's hours. Accepts "07:00-21:00", "6:30-14:00,17:00-22:00",
## "24h", "closed", or "" (unknown).
static func parse_day(text: String) -> Array:
	var t := text.strip_edges().to_lower()
	if t == "" or t == "?" or t == "unknown":
		return []
	if t == "24h" or t == "24" or t == "open":
		return [[0, 1440]]
	if t == "closed" or t == "x":
		return [[-1, -1]]
	var out: Array = []
	for part in t.split(",", false):
		var halves: PackedStringArray = String(part).split("-", false)
		if halves.size() != 2:
			continue
		var a := _minutes(halves[0])
		var b := _minutes(halves[1])
		if a < 0 or b < 0:
			continue
		# A close time before the open time means past midnight ("18:00-02:00").
		if b <= a:
			b += 1440
		out.push_back([a, b])
	return out


static func _minutes(text: String) -> int:
	var s := text.strip_edges()
	var bits: PackedStringArray = s.split(":", false)
	if bits.is_empty():
		return -1
	var h := int(bits[0])
	var m := int(bits[1]) if bits.size() > 1 else 0
	if h < 0 or h > 24 or m < 0 or m > 59:
		return -1
	return h * 60 + m


static func format_minutes(m: int) -> String:
	var mm := m % 1440
	if Cfg.get_b("clock_24h"):
		return "%02d:%02d" % [mm / 60, mm % 60]
	var h := (mm / 60) % 12
	if h == 0:
		h = 12
	return "%d:%02d%s" % [h, mm % 60, "am" if mm < 720 else "pm"]


## Local weekday index (0 = Monday) and minute-of-day for a timestamp.
static func local_parts(t: float) -> Array:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(int(t) + int(bias) * 60)
	# Godot's weekday is 0 = Sunday; ours is 0 = Monday, like the strings.
	var weekday := (int(d["weekday"]) + 6) % 7
	return [weekday, int(d["hour"]) * 60 + int(d["minute"])]


## Is the stop open at `t`? Returns {known, open, closes_in_min, opens_in_min,
## text} — `text` is the one line the list shows.
static func status_at(stop: Dictionary, t: float) -> Dictionary:
	var hours: Dictionary = stop.get("hours", {})
	if hours.is_empty():
		return {"known": false, "open": false, "text": "hours unknown"}
	var parts := local_parts(t)
	var weekday: int = parts[0]
	var minute: int = parts[1]
	# Yesterday's late-night ranges can still cover this morning.
	for back in [1, 0]:
		var day_index := (weekday - back + 7) % 7
		var ranges := parse_day(String(hours.get(DAYS[day_index], "")))
		var offset := back * 1440
		for r: Array in ranges:
			if int(r[0]) < 0:
				continue
			var open_at := int(r[0]) - offset
			var close_at := int(r[1]) - offset
			if minute >= open_at and minute < close_at:
				return {
					"known": true, "open": true,
					"closes_in_min": close_at - minute,
					"text": "open until %s" % format_minutes(int(r[1])),
				}
	# Not open now: find the next opening within a week.
	for ahead in range(0, 8):
		var day_index := (weekday + ahead) % 7
		var ranges := parse_day(String(hours.get(DAYS[day_index], "")))
		for r: Array in ranges:
			if int(r[0]) < 0:
				continue
			var when := ahead * 1440 + int(r[0])
			if when > minute:
				var wait := when - minute
				var label := "opens %s" % format_minutes(int(r[0]))
				if ahead > 0:
					label += " %s" % DAYS[day_index]
				return {"known": true, "open": false, "opens_in_min": wait, "text": label}
	return {"known": true, "open": false, "text": "closed"}


## Seconds until you get there, from your position and today's real pace.
## Straight-line distance is deliberately inflated a little: roads are not
## straight, and an optimistic ETA is the one that leaves you outside a locked
## door.
static func eta_seconds(stop: Dictionary) -> float:
	var f := Logbook.last_fix()
	if f.is_empty() or not stop.has("lat"):
		return -1.0
	var straight := Geo.distance_m(float(f["lat"]), float(f["lon"]),
		float(stop["lat"]), float(stop["lon"]))
	var road := straight * 1.25
	return road / maxf(2.0, Trip.average_speed())


static func distance_m(stop: Dictionary) -> float:
	var f := Logbook.last_fix()
	if f.is_empty() or not stop.has("lat"):
		return -1.0
	return Geo.distance_m(float(f["lat"]), float(f["lon"]),
		float(stop["lat"]), float(stop["lon"]))


## Will it be open when you actually arrive? This is the line the panel leads
## with, because it is the only one that changes a decision.
static func arrival_verdict(stop: Dictionary) -> Dictionary:
	var eta := eta_seconds(stop)
	if eta < 0.0:
		return {"text": "", "ok": true}
	var at := Time.get_unix_time_from_system() + eta
	var st := status_at(stop, at)
	if not bool(st.get("known", false)):
		return {"text": "arrive %s · hours unknown" % UI.clock(at), "ok": true}
	if bool(st["open"]):
		var margin := int(st.get("closes_in_min", 0))
		if margin < 45:
			return {"text": "arrive %s · %d min before closing" % [UI.clock(at), margin],
				"ok": true, "tight": true}
		return {"text": "arrive %s · open" % UI.clock(at), "ok": true}
	return {"text": "arrive %s · CLOSED (%s)" % [UI.clock(at), String(st.get("text", ""))],
		"ok": false}


# ------------------------------------------------------------------- photo


## Street View Static gives one recognizable picture of a place from the road,
## which is exactly what you want when hunting for a driveway at dusk. It
## needs a Google API key; without one, paste any image URL instead.
##
## Note their terms: Street View imagery may be cached only as long as needed
## for the app to work. Downloading a photo per stop for a trip is squarely
## inside that; mirroring their imagery is not.
static func street_view_url(stop: Dictionary, key: String) -> String:
	if key == "" or not stop.has("lat"):
		return ""
	return "https://maps.googleapis.com/maps/api/streetview?size=640x400&location=%f,%f&fov=80&key=%s" \
		% [float(stop["lat"]), float(stop["lon"]), key]


static func photo_path(stop: Dictionary) -> String:
	var file := String(stop.get("photo", ""))
	if file == "":
		return ""
	return Logbook.media_dir().path_join(file)


static func has_photo(stop: Dictionary) -> bool:
	var p := photo_path(stop)
	return p != "" and FileAccess.file_exists(p)
