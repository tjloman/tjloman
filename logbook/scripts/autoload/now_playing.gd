extends Node
## Autoload `Music`: what is playing, and where you were when it played.
##
## Two jobs, both of which have to work with the phone locked in a bar bag or
## a trailer:
##
##   Control — play/pause and skip go out over Android's MediaSession, the
##     same channel the lock screen and a handlebar bluetooth remote use. No
##     Spotify account, no API key, no foreground requirement: whatever is
##     playing, this drives it.
##
##   Log — every track change becomes a `music` event pinned to your position.
##     Months later the timeline can tell you what was in your ears on the
##     climb out of the valley, which is exactly the kind of thing a vlog
##     wants and nobody ever writes down.
##
## Tracks are logged by the background service when the app is closed and by
## this node when it is open; both dedupe on the same id, so the same song
## never lands twice.

signal changed(info: Dictionary)

## Ignore a "new track" that repeats within this window — players emit
## metadata updates several times per song (art loads, duration resolves).
const DEDUPE_S := 45.0

var info := {}
var playing := false

var _last_key := ""
var _last_log_t := 0.0
var _poll := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Bridge.media_changed.connect(_on_media)


func _process(delta: float) -> void:
	# The service pushes changes; polling is only a safety net for players
	# that update their session without announcing it.
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 15.0
	var now := Bridge.now_playing()
	if not now.is_empty():
		_on_media(now)


func _on_media(m: Dictionary) -> void:
	info = m
	playing = bool(m.get("playing", false))
	changed.emit(info)
	if not Cfg.get_b("capture_music") or not playing:
		return
	var title := String(m.get("title", "")).strip_edges()
	if title == "":
		return
	var key := "%s|%s" % [String(m.get("artist", "")), title]
	var now := Time.get_unix_time_from_system()
	if key == _last_key and now - _last_log_t < DEDUPE_S:
		return
	_last_key = key
	_last_log_t = now
	Logbook.append_event(Ev.MUSIC, {
		"id": "music-%d" % int(now),
		"title": title,
		"artist": String(m.get("artist", "")),
		"album": String(m.get("album", "")),
		"app": String(m.get("app", "")),
	})


# ------------------------------------------------------------------ control


func play_pause() -> void:
	Bridge.media_play_pause()


func next_track() -> void:
	Bridge.media_next()


func prev_track() -> void:
	Bridge.media_prev()


func volume(delta: int) -> void:
	Bridge.media_volume(delta)


## Wake the player and start it. Used by the "start the ride" action so you
## can set off without unlocking anything.
func start_playback() -> void:
	Bridge.media_launch(Cfg.get_s("music_app_package"))


func title_line() -> String:
	if info.is_empty() or String(info.get("title", "")) == "":
		return "nothing playing"
	var artist := String(info.get("artist", ""))
	if artist == "":
		return String(info["title"])
	return "%s — %s" % [artist, String(info["title"])]


## How far into the track we are, 0..1, for a progress line in the HUD.
func progress() -> float:
	var dur := float(info.get("duration_ms", 0.0))
	if dur <= 0.0:
		return 0.0
	return clampf(float(info.get("position_ms", 0.0)) / dur, 0.0, 1.0)
