class_name Ev
## The vocabulary of the logbook: every kind of thing that can be pinned to a
## place and a moment, plus how each one looks on the map and the timeline.
##
## An event is a plain Dictionary — not a class — because it is written to
## disk as one line of JSON and read back thousands at a time. Keeping it a
## Dictionary means zero conversion cost on load and forward compatibility:
## an unknown key from a newer version survives a round trip instead of being
## silently dropped.
##
## Every event has: id, t (unix seconds), kind, lat, lon.
## Everything else is kind-specific and lives under the same flat dictionary.

const NOTE := "note"                ## A journal entry typed on the road.
const PHOTO := "photo"              ## A picture, located by EXIF or by the track.
const VIDEO := "video"
const AUDIO := "audio"              ## Voice memo — hands stay on the bars.
const CALL := "call"                ## Phone call, from the device call log.
const MUSIC := "music"              ## What was playing, and where.
const MESSAGE := "message"          ## Messenger/SMS activity, from notifications.
const WAYPOINT := "waypoint"        ## "Something happened here" pin.
const STOP_PLAN := "stop_plan"      ## A planned stop: food, camp, charge, resupply.
const STOP_ARRIVE := "stop_arrive"
const STOP_DEPART := "stop_depart"
const BATTERY := "battery"          ## Periodic ebike telemetry sample.
const BIKE := "bike"                ## Bike happening: swap, charge, repair, flat.
const WEATHER := "weather"          ## Observation or alert snapshot.
const DAY_START := "day_start"
const DAY_END := "day_end"
const PAUSE := "pause"              ## Logger paused/resumed (rest, hotel, ferry).
const RESUME := "resume"

## Kinds the user can create by hand from the "+" menu, in menu order.
const USER_KINDS := [NOTE, PHOTO, AUDIO, WAYPOINT, BIKE, STOP_PLAN]

## Kinds that arrive on their own from sensors and the OS.
const AUTO_KINDS := [CALL, MESSAGE, MUSIC, BATTERY, WEATHER, DAY_START, DAY_END, PAUSE, RESUME]


static func label(kind: String) -> String:
	match kind:
		NOTE: return "Note"
		PHOTO: return "Photo"
		VIDEO: return "Video"
		AUDIO: return "Voice memo"
		CALL: return "Call"
		MUSIC: return "Music"
		MESSAGE: return "Message"
		WAYPOINT: return "Waypoint"
		STOP_PLAN: return "Planned stop"
		STOP_ARRIVE: return "Arrived"
		STOP_DEPART: return "Departed"
		BATTERY: return "Battery"
		BIKE: return "Bike"
		WEATHER: return "Weather"
		DAY_START: return "Day start"
		DAY_END: return "Day end"
		PAUSE: return "Paused"
		RESUME: return "Resumed"
	return kind.capitalize()


## A single glyph for the map pin and the timeline pip. Deliberately from the
## common Unicode blocks — the app ships no icon atlas, and the default font
## covers these.
static func glyph(kind: String) -> String:
	match kind:
		NOTE: return "✎"
		PHOTO: return "▣"
		VIDEO: return "▶"
		AUDIO: return "◉"
		CALL: return "☎"
		MUSIC: return "♪"
		MESSAGE: return "✉"
		WAYPOINT: return "✦"
		STOP_PLAN: return "⚑"
		STOP_ARRIVE: return "▼"
		STOP_DEPART: return "▲"
		BATTERY: return "▮"
		BIKE: return "⚙"
		WEATHER: return "☂"
		DAY_START: return "☀"
		DAY_END: return "☾"
		PAUSE: return "❙❙"
		RESUME: return "▶"
	return "•"


static func color(kind: String) -> Color:
	match kind:
		NOTE: return Color(0.95, 0.83, 0.42)
		PHOTO: return Color(0.45, 0.80, 0.95)
		VIDEO: return Color(0.35, 0.70, 0.95)
		AUDIO: return Color(0.70, 0.62, 0.95)
		CALL: return Color(0.55, 0.90, 0.60)
		MUSIC: return Color(0.85, 0.55, 0.90)
		MESSAGE: return Color(0.60, 0.85, 0.75)
		WAYPOINT: return Color(1.00, 0.60, 0.35)
		STOP_PLAN: return Color(1.00, 0.45, 0.45)
		STOP_ARRIVE, STOP_DEPART: return Color(1.00, 0.55, 0.55)
		BATTERY: return Color(0.60, 0.95, 0.45)
		BIKE: return Color(0.80, 0.80, 0.85)
		WEATHER: return Color(0.50, 0.65, 1.00)
		DAY_START, DAY_END: return Color(0.85, 0.85, 0.90)
		PAUSE, RESUME: return Color(0.70, 0.70, 0.75)
	return Color(0.85, 0.85, 0.85)


## Kinds that are noise on the map at low zoom: telemetry samples land every
## few minutes and would bury the things you actually stopped for.
static func is_minor(kind: String) -> bool:
	return kind == BATTERY or kind == PAUSE or kind == RESUME


## One line of text for a list row or a map callout.
static func summary(e: Dictionary) -> String:
	match String(e.get("kind", "")):
		NOTE:
			var body := String(e.get("text", "")).strip_edges()
			var nl := body.find("\n")
			if nl > 0:
				body = body.substr(0, nl)
			return body if body.length() <= 80 else body.substr(0, 79) + "…"
		PHOTO, VIDEO:
			return String(e.get("caption", "")) if e.has("caption") else String(e.get("file", "")).get_file()
		AUDIO:
			return "Voice memo, %ds" % int(e.get("seconds", 0))
		CALL:
			var dir := String(e.get("direction", "in"))
			var who := String(e.get("who", "Unknown"))
			var secs := int(e.get("seconds", 0))
			var verb: String = {"in": "Call from", "out": "Call to",
				"missed": "Missed call from"}.get(dir, "Call")
			if secs > 0:
				return "%s %s (%d:%02d)" % [verb, who, secs / 60, secs % 60]
			return "%s %s" % [verb, who]
		MESSAGE:
			return "%s · %s" % [String(e.get("app", "?")), String(e.get("who", ""))]
		MUSIC:
			return "%s — %s" % [String(e.get("artist", "?")), String(e.get("title", ""))]
		WAYPOINT:
			return String(e.get("text", "Waypoint"))
		STOP_PLAN:
			return String(e.get("name", "Planned stop"))
		STOP_ARRIVE:
			return "Arrived: %s" % String(e.get("name", "stop"))
		STOP_DEPART:
			return "Left: %s" % String(e.get("name", "stop"))
		BATTERY:
			var pack := String(e.get("pack", "battery"))
			var line := "%s %d%%  %.1fV" % [pack, int(e.get("soc", 0)), float(e.get("volts", 0.0))]
			if float(e.get("solar_watts", 0.0)) > 5.0:
				line += "  ☀%dW" % int(float(e["solar_watts"]))
			return line
		BIKE:
			return String(e.get("text", "Bike"))
		WEATHER:
			return String(e.get("headline", "Weather"))
		DAY_START:
			return "Day %d begins" % int(e.get("day", 1))
		DAY_END:
			return "Day %d: %s" % [int(e.get("day", 1)), String(e.get("summary", ""))]
		PAUSE:
			return "Logging paused"
		RESUME:
			return "Logging resumed"
	return label(String(e.get("kind", "")))
