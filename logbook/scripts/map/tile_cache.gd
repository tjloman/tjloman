extends Node
## Autoload `Tiles`: map imagery, in three tiers.
##
##   memory   a small LRU of decoded textures — what the map draws from.
##   offline  tiles deliberately downloaded before the trip. Never evicted.
##            This is the map that works in a canyon with no bars.
##   cache    tiles picked up incidentally while browsing online. Evicted
##            oldest-first once it outgrows its budget.
##
## Nothing here ever blocks. `request()` returns whatever is available right
## now — possibly nothing — and emits `tile_ready` later if it finds more. The
## map draws a coarser zoom level in the meantime, so panning is never a wall
## of grey squares.

signal tile_ready(key: String)
signal offline_stats_changed

const CACHE_ROOT := "user://tiles"
const OFFLINE_ROOT := "user://offline"
const JOURNAL := "user://tiles/journal.ndjson"

const MEM_LIMIT := 700          ## Decoded textures held at once (~0.2 KB each in VRAM terms).
const DECODES_PER_FRAME := 6    ## Decoding is the one thing that can hitch; meter it.
const MISS_TTL := 3600.0        ## Remember a 404 for an hour, then let it try again.
const ABSENT_TTL := 15.0        ## ...and "not on disk" for a few seconds.

var offline_bytes := 0
var offline_tiles := 0
var cache_bytes := 0

var _mem := {}                  ## key -> {tex: Texture2D, used: int}
var _clock := 0
var _pending := {}              ## key -> true while a disk read or fetch is out
var _decode_queue: Array[Dictionary] = []
var _missing := {}              ## key -> unix time it 404'd
var _absent := {}               ## key -> unix time we last found no file
var _journal: Array[Dictionary] = []
var _journal_dirty := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(CACHE_ROOT)
	DirAccess.make_dir_recursive_absolute(OFFLINE_ROOT)
	_load_journal()
	_load_offline_stats()


func _process(_delta: float) -> void:
	var n := 0
	while n < DECODES_PER_FRAME and not _decode_queue.is_empty():
		var job: Dictionary = _decode_queue.pop_front()
		_decode(String(job["key"]), job["bytes"])
		n += 1
	if _journal_dirty and Engine.get_process_frames() % 300 == 0:
		_save_journal()


static func key_for(source: String, z: int, x: int, y: int) -> String:
	return "%s/%d/%d/%d" % [source, z, x, y]


func _rel_path(source: String, z: int, x: int, y: int) -> String:
	return "%s/%d/%d/%d.png" % [source, z, x, y]


## The tile if we have it decoded, else null — and quietly start whatever work
## would make it available. Callers draw what they get and repaint on
## `tile_ready`.
func request(source: String, z: int, x: int, y: int, allow_net: bool = true,
		priority: int = Net.P_NORMAL) -> Texture2D:
	var span := 1 << z
	if z < 0 or x < 0 or y < 0 or x >= span or y >= span:
		return null
	var key := key_for(source, z, x, y)
	var slot: Variant = _mem.get(key)
	if slot != null:
		_clock += 1
		slot["used"] = _clock
		return slot["tex"]
	if _pending.has(key):
		return null
	var now := Time.get_unix_time_from_system()
	# Without this, a map sitting still over an unfetched area asks the
	# filesystem about the same thirty tiles sixty times a second.
	var absent_at: float = _absent.get(key, 0.0)
	if absent_at > 0.0:
		if now - absent_at < ABSENT_TTL:
			return null
		_absent.erase(key)
	var rel := _rel_path(source, z, x, y)
	var off := OFFLINE_ROOT.path_join(rel)
	var cch := CACHE_ROOT.path_join(rel)
	if FileAccess.file_exists(off):
		_queue_disk(key, off)
		return null
	if FileAccess.file_exists(cch):
		_queue_disk(key, cch)
		return null
	_absent[key] = now
	if not allow_net:
		return null
	var miss: float = _missing.get(key, 0.0)
	if miss > 0.0:
		if now - miss < MISS_TTL:
			return null
		_missing.erase(key)
	var url := TileSource.url_for(source, z, x, y)
	if url == "":
		return null
	_pending[key] = true
	Net.fetch(url, _on_fetched.bind(key, source, z, x, y), priority)
	return null


## Is this tile already on disk? The prefetch planner asks a lot, so it never
## touches the decoder.
func have_tile(source: String, z: int, x: int, y: int) -> bool:
	var rel := _rel_path(source, z, x, y)
	return FileAccess.file_exists(OFFLINE_ROOT.path_join(rel)) \
		or FileAccess.file_exists(CACHE_ROOT.path_join(rel))


func _queue_disk(key: String, path: String) -> void:
	_pending[key] = true
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		_pending.erase(key)
		return
	_decode_queue.push_back({"key": key, "bytes": bytes})


func _on_fetched(ok: bool, code: int, body: PackedByteArray, key: String,
		source: String, z: int, x: int, y: int) -> void:
	_pending.erase(key)
	if not ok or body.is_empty():
		if code == 404 or code == 403:
			_missing[key] = Time.get_unix_time_from_system()
		return
	_write_cache(source, z, x, y, body)
	_decode_queue.push_back({"key": key, "bytes": body})


func _decode(key: String, bytes: PackedByteArray) -> void:
	_pending.erase(key)
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		err = img.load_jpg_from_buffer(bytes)
	if err != OK or img.is_empty():
		return
	_put_mem(key, ImageTexture.create_from_image(img))
	tile_ready.emit(key)


func _put_mem(key: String, tex: Texture2D) -> void:
	_clock += 1
	_mem[key] = {"tex": tex, "used": _clock}
	if _mem.size() > MEM_LIMIT:
		_evict_mem()


func _evict_mem() -> void:
	# Drop the coldest quarter in one pass: cheaper than an exact LRU, and the
	# difference is invisible when the working set is one screen of tiles.
	var entries := []
	for k: String in _mem.keys():
		entries.push_back({"k": k, "u": int(_mem[k]["used"])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["u"]) < int(b["u"]))
	var drop := maxi(1, entries.size() / 4)
	for i in drop:
		_mem.erase(String(entries[i]["k"]))


# ------------------------------------------------------------------ on disk


func _write_cache(source: String, z: int, x: int, y: int, body: PackedByteArray) -> void:
	var rel := _rel_path(source, z, x, y)
	var path := CACHE_ROOT.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(body)
	f = null
	cache_bytes += body.size()
	_absent.erase(key_for(source, z, x, y))
	_journal.push_back({"k": rel, "b": body.size()})
	_journal_dirty = true
	if cache_bytes > Cfg.get_i("map_cache_budget_mb") * 1024 * 1024:
		_evict_disk()


## Prefetch writes here: pinned imagery that eviction will never touch,
## because the whole point is that it is there when there is no signal.
func store_offline(source: String, z: int, x: int, y: int, body: PackedByteArray) -> void:
	var path := OFFLINE_ROOT.path_join(_rel_path(source, z, x, y))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(body)
	f = null
	offline_bytes += body.size()
	offline_tiles += 1
	offline_stats_changed.emit()
	var key := key_for(source, z, x, y)
	_missing.erase(key)
	_absent.erase(key)
	if not _mem.has(key):
		_decode_queue.push_back({"key": key, "bytes": body})


func _evict_disk() -> void:
	var target := int(Cfg.get_i("map_cache_budget_mb") * 1024 * 1024 * 0.85)
	var dir := DirAccess.open(CACHE_ROOT)
	if dir == null:
		return
	var i := 0
	while cache_bytes > target and i < _journal.size():
		var rel := String(_journal[i]["k"])
		dir.remove(rel)
		cache_bytes -= int(_journal[i]["b"])
		_mem.erase(rel.get_basename())
		i += 1
	if i > 0:
		_journal = _journal.slice(i)
		_save_journal()


## Everything the offline map holds, so Settings can show it and offer to
## clear it before the next leg.
func offline_summary() -> Dictionary:
	return {
		"tiles": offline_tiles,
		"bytes": offline_bytes,
		"cache_bytes": cache_bytes,
	}


func clear_cache() -> void:
	_rm_tree(CACHE_ROOT)
	DirAccess.make_dir_recursive_absolute(CACHE_ROOT)
	_journal.clear()
	cache_bytes = 0
	_mem.clear()
	_save_journal()


## Throw away one whole source — used for radar frames, which are worthless
## ten minutes after they are made and would otherwise fill the cache.
func drop_source(source: String) -> void:
	_rm_tree(CACHE_ROOT.path_join(source))
	var prefix := source + "/"
	for k: String in _mem.keys():
		if k.begins_with(prefix):
			_mem.erase(k)
	for i in range(_journal.size() - 1, -1, -1):
		if String(_journal[i]["k"]).begins_with(prefix):
			cache_bytes -= int(_journal[i]["b"])
			_journal.remove_at(i)
	_journal_dirty = true


func clear_offline() -> void:
	_rm_tree(OFFLINE_ROOT)
	DirAccess.make_dir_recursive_absolute(OFFLINE_ROOT)
	offline_bytes = 0
	offline_tiles = 0
	_mem.clear()
	offline_stats_changed.emit()


func _rm_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		_rm_tree(path.path_join(d))
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---------------------------------------------------------------- bookkeeping


func _load_journal() -> void:
	if not FileAccess.file_exists(JOURNAL):
		return
	var f := FileAccess.open(JOURNAL, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line()
		if line.length() < 3:
			continue
		var v: Variant = JSON.parse_string(line)
		if typeof(v) == TYPE_DICTIONARY:
			_journal.push_back(v)
			cache_bytes += int((v as Dictionary).get("b", 0))


func _save_journal() -> void:
	var f := FileAccess.open(JOURNAL, FileAccess.WRITE)
	if f == null:
		return
	for e in _journal:
		f.store_line(JSON.stringify(e))
	_journal_dirty = false


## Counting the offline set means walking it once at startup. It is a few
## thousand files, on a background-friendly path, and it only happens once.
func _load_offline_stats() -> void:
	offline_bytes = 0
	offline_tiles = 0
	_walk_count(OFFLINE_ROOT)
	offline_stats_changed.emit()


func _walk_count(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		var fa := FileAccess.open(path.path_join(f), FileAccess.READ)
		if fa != null:
			offline_bytes += int(fa.get_length())
			offline_tiles += 1
	for d in dir.get_directories():
		_walk_count(path.path_join(d))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		if _journal_dirty:
			_save_journal()
