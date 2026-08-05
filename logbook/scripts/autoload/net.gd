extends Node
## Autoload `Net`: the only thing in the app that touches the network.
##
## Out on the road, data is the scarce resource — sometimes there is none at
## all, and when there is, it is a metered hotspot on a mountain pass. So every
## request goes through one queue that knows three things:
##
##   * whether we are online at all, and whether the link is metered;
##   * how many bytes today's cellular budget has left;
##   * whether the caller asked for this (tap a stop, refresh weather) or the
##     app decided to (bulk tile prefetch).
##
## User-initiated requests go out on any link. Bulk requests wait for wifi
## unless you say otherwise. Nothing retries forever, and nothing blocks the
## UI — the map keeps working from cache whatever the radio is doing.

signal status_changed(online: bool, metered: bool)
signal usage_changed(bytes_today: int)

## Request classes. Plain ints rather than an enum: these are used as type
## annotations from other files, and an autoload's enum is not a type there.
const P_USER := 0     ## You tapped something and are waiting for it.
const P_NORMAL := 1   ## Weather refresh, a visible tile.
const P_BULK := 2     ## Corridor prefetch. Wifi work, by default.

const USAGE_PATH := "user://data_usage.json"
const MAX_PARALLEL := 6
const MAX_QUEUE := 4000
const USER_AGENT := "TripLogbook/0.1 (personal ebike logbook; contact: local)"

var online := true
var metered := false
var link := "wifi"

var bytes_today := 0
var metered_bytes_today := 0

var _day := ""
var _queue: Array[Dictionary] = []
var _pool: Array[HTTPRequest] = []
var _busy := 0
var _poll := 0.0
var _inflight := {}          ## url -> true, so the same tile is never fetched twice
var _backoff_until := 0.0
var _fail_streak := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_usage()
	for i in MAX_PARALLEL:
		var r := HTTPRequest.new()
		r.timeout = 20.0
		r.use_threads = true
		r.accept_gzip = true
		add_child(r)
		_pool.push_back(r)
	Bridge.connectivity_changed.connect(_on_connectivity)
	_refresh_status()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 10.0
		_refresh_status()
	_pump()


func _on_connectivity(net: Dictionary) -> void:
	_apply_status(net)


func _refresh_status() -> void:
	_apply_status(Bridge.net_status())


func _apply_status(net: Dictionary) -> void:
	var was_online := online
	var was_metered := metered
	online = bool(net.get("online", online))
	link = String(net.get("kind", link))
	metered = bool(net.get("metered", link == "cell"))
	if online != was_online or metered != was_metered:
		status_changed.emit(online, metered)


# ------------------------------------------------------------------ queueing


## Queue a GET. `on_done` is called as on_done(ok: bool, code: int,
## body: PackedByteArray) on the main thread, exactly once, whatever happens —
## including when the request is dropped for being over budget, so callers
## never leak a pending state.
func fetch(url: String, on_done: Callable, priority: int = P_NORMAL,
		headers: PackedStringArray = PackedStringArray()) -> void:
	if _inflight.has(url):
		return
	if _queue.size() >= MAX_QUEUE:
		# A prefetch of a whole state can outrun the radio by hours. Drop the
		# lowest-value work rather than growing without bound.
		var dropped := false
		for i in range(_queue.size() - 1, -1, -1):
			if int(_queue[i]["priority"]) == P_BULK:
				var d: Dictionary = _queue[i]
				_queue.remove_at(i)
				_finish(d, false, 0, PackedByteArray())
				dropped = true
				break
		if not dropped:
			on_done.call(false, 0, PackedByteArray())
			return
	_inflight[url] = true
	var item := {"url": url, "cb": on_done, "priority": priority, "headers": headers, "tries": 0}
	if priority == P_USER:
		_queue.push_front(item)
	else:
		_queue.push_back(item)
	_pump()


func cancel_bulk() -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if int(_queue[i]["priority"]) == P_BULK:
			var d: Dictionary = _queue[i]
			_queue.remove_at(i)
			_finish(d, false, 0, PackedByteArray())


func queued() -> int:
	return _queue.size()


func busy() -> int:
	return _busy


## Would a request of this priority go out right now? The UI uses this to
## explain itself ("waiting for wifi") instead of just looking broken.
func allowed(priority: int) -> bool:
	if not online:
		return false
	if priority == P_USER:
		return true
	if metered:
		if not Cfg.get_b("download_on_cellular"):
			return false
		if metered_bytes_today >= Cfg.get_i("cellular_budget_mb_day") * 1024 * 1024:
			return false
	return true


func budget_left_mb() -> float:
	var cap := Cfg.get_i("cellular_budget_mb_day") * 1024 * 1024
	return maxf(0.0, float(cap - metered_bytes_today)) / (1024.0 * 1024.0)


func _pump() -> void:
	if _queue.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _backoff_until:
		return
	while _busy < MAX_PARALLEL and not _queue.is_empty():
		var idx := -1
		for i in _queue.size():
			if allowed(int(_queue[i]["priority"])):
				idx = i
				break
		if idx < 0:
			return  # everything waiting is blocked on wifi or budget
		var item: Dictionary = _queue[idx]
		_queue.remove_at(idx)
		var req := _take_request()
		if req == null:
			_queue.push_front(item)
			return
		_busy += 1
		var headers: PackedStringArray = item["headers"].duplicate()
		headers.push_back("User-Agent: " + USER_AGENT)
		var done := _on_completed.bind(req, item)
		req.request_completed.connect(done, CONNECT_ONE_SHOT)
		var err := req.request(String(item["url"]), headers)
		if err != OK:
			# Never got off the ground (bad URL, no resolver): unwind by hand,
			# the completion signal will not fire.
			req.request_completed.disconnect(done)
			_busy -= 1
			_release(req)
			_retry_or_fail(item, 0, PackedByteArray())


func _take_request() -> HTTPRequest:
	for r in _pool:
		if r.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED and not r.has_meta("busy"):
			r.set_meta("busy", true)
			return r
	return null


func _release(r: HTTPRequest) -> void:
	r.remove_meta("busy")


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		req: HTTPRequest, item: Dictionary) -> void:
	_busy -= 1
	_release(req)
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if ok:
		_fail_streak = 0
		_count_bytes(body.size())
		_finish(item, true, code, body)
	else:
		_retry_or_fail(item, code, body)
	_pump()


func _retry_or_fail(item: Dictionary, code: int, body: PackedByteArray) -> void:
	var tries := int(item["tries"]) + 1
	item["tries"] = tries
	# 404 means the tile does not exist; retrying is pure waste. 429/5xx are
	# worth another go, once the radio has had a moment.
	var retryable := code == 0 or code == 429 or code >= 500
	if retryable and tries < 3:
		_queue.push_back(item)
		_fail_streak += 1
		if _fail_streak > 8:
			# The whole link is sick (captive portal, dead zone). Stop hammering
			# it — that only costs battery.
			_backoff_until = Time.get_ticks_msec() / 1000.0 + minf(60.0, 2.0 * _fail_streak)
			_fail_streak = 0
		return
	_finish(item, false, code, body)


func _finish(item: Dictionary, ok: bool, code: int, body: PackedByteArray) -> void:
	_inflight.erase(String(item["url"]))
	var cb: Callable = item["cb"]
	if cb.is_valid():
		cb.call(ok, code, body)


# -------------------------------------------------------------------- usage


func _count_bytes(n: int) -> void:
	_roll_day()
	bytes_today += n
	if metered:
		metered_bytes_today += n
	usage_changed.emit(bytes_today)
	if bytes_today % 1048576 < n:  # roughly once a megabyte
		_save_usage()


func _roll_day() -> void:
	var key := Logbook.day_key(Time.get_unix_time_from_system())
	if key != _day:
		_day = key
		bytes_today = 0
		metered_bytes_today = 0


func _load_usage() -> void:
	_day = Logbook.day_key(Time.get_unix_time_from_system())
	if not FileAccess.file_exists(USAGE_PATH):
		return
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(USAGE_PATH))
	if typeof(v) != TYPE_DICTIONARY:
		return
	var d: Dictionary = v
	if String(d.get("day", "")) == _day:
		bytes_today = int(d.get("bytes", 0))
		metered_bytes_today = int(d.get("metered", 0))


func _save_usage() -> void:
	var f := FileAccess.open(USAGE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"day": _day, "bytes": bytes_today, "metered": metered_bytes_today}))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_save_usage()
