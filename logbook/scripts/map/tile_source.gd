class_name TileSource
## Raster tile providers, and — just as important — which of them you are
## allowed to bulk-download from.
##
## A note that matters for this app: OpenStreetMap's public tile servers are
## donated infrastructure with an explicit usage policy that forbids bulk
## downloading. Browsing the map pulls tiles as you look at them, which is
## fine. Prefetching a 2,000-mile corridor is not, and would get you blocked
## before you left the driveway.
##
## So sources carry a `bulk` flag. Casual browsing works everywhere; the
## corridor prefetch only runs against a source that permits it — your own
## tile server, or a provider you have a key with. Set that up once before the
## trip (Settings → Map → Tile source) and the offline map is yours.

const SOURCES := {
	"osm": {
		"name": "OpenStreetMap",
		"url": "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
		"max_zoom": 19,
		"bulk": false,
		"attribution": "© OpenStreetMap contributors",
	},
	"otm": {
		"name": "OpenTopoMap",
		"url": "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
		"subdomains": ["a", "b", "c"],
		"max_zoom": 17,
		"bulk": false,
		"attribution": "© OpenStreetMap contributors, SRTM | OpenTopoMap (CC-BY-SA)",
	},
	"cyclosm": {
		"name": "CyclOSM",
		"url": "https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
		"subdomains": ["a", "b", "c"],
		"max_zoom": 18,
		"bulk": false,
		"attribution": "© OpenStreetMap contributors | CyclOSM",
	},
	"custom": {
		"name": "Custom / self-hosted",
		"url": "",              ## Set in Settings; {z}/{x}/{y}, optional {s} and {key}.
		"max_zoom": 18,
		"bulk": true,           ## Your server, your rules.
		"attribution": "",
	},
}

const DEFAULT_SOURCE := "osm"


static func get_source(id: String) -> Dictionary:
	var src: Dictionary = SOURCES.get(id, SOURCES[DEFAULT_SOURCE]).duplicate()
	if id == "custom":
		src["url"] = Cfg.get_s("tile_custom_url")
		src["attribution"] = Cfg.get_s("tile_custom_attribution")
		src["max_zoom"] = Cfg.get_i("tile_custom_max_zoom")
	return src


static func current_id() -> String:
	var id := Cfg.get_s("tile_source")
	return id if SOURCES.has(id) else DEFAULT_SOURCE


static func current() -> Dictionary:
	return get_source(current_id())


## The source used for bulk corridor prefetch: the configured one if it allows
## bulk, otherwise nothing — better to say so plainly in the UI than to
## quietly hammer a donated server.
static func bulk_source_id() -> String:
	var id := current_id()
	var src := get_source(id)
	if bool(src.get("bulk", false)) and String(src.get("url", "")) != "":
		return id
	return ""


static func url_for(source_id: String, z: int, x: int, y: int) -> String:
	# Radar frames are transient sources named after their timestamp; the URL
	# for one only exists while that frame is in the current RainViewer index.
	if source_id.begins_with("radar-"):
		var t := Wx.frame_url_template(source_id)
		if t == "":
			return ""
		return t.replace("{z}", str(z)).replace("{x}", str(x)).replace("{y}", str(y))
	var src := get_source(source_id)
	var url := String(src.get("url", ""))
	if url == "":
		return ""
	if url.contains("{s}"):
		var subs: Array = src.get("subdomains", ["a"])
		# Deterministic per tile, so a re-fetch of the same tile hits the same
		# host and its cache.
		url = url.replace("{s}", String(subs[(x + y) % subs.size()]))
	return url.replace("{z}", str(z)).replace("{x}", str(x)).replace("{y}", str(y)) \
		.replace("{key}", Cfg.get_s("tile_api_key"))


static func max_zoom(source_id: String) -> int:
	return int(get_source(source_id).get("max_zoom", 18))


static func attribution(source_id: String) -> String:
	return String(get_source(source_id).get("attribution", ""))
