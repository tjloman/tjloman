class_name Geo
## Static geodesy and Web-Mercator tile math. Everything spatial in the app
## goes through here so there is exactly one place where a sign error can
## live.
##
## Two coordinate spaces are used throughout:
##   geographic   – latitude/longitude in degrees (WGS84), what the GPS gives.
##   normalized   – Web-Mercator, both axes in 0..1, +x east, +y SOUTH.
##                  Multiply by 2^zoom to get slippy-map tile coordinates,
##                  which is exactly what every raster tile server speaks.
## The map view works in normalized space because it is zoom-independent:
## panning and hit-testing never have to care which tile level is on screen.

## Mean Earth radius (IUGG). Good to ~0.3% anywhere, which is far better
## than a phone GPS fix.
const EARTH_RADIUS_M := 6371008.8

const MAX_LAT := 85.05112878  ## Web Mercator clamps here; the poles are at infinity.

const METERS_PER_MILE := 1609.344
const METERS_PER_FOOT := 0.3048


static func clamp_lat(lat: float) -> float:
	return clampf(lat, -MAX_LAT, MAX_LAT)


## Wrap a longitude into -180..180 so a track crossing the antimeridian
## does not fling the map into empty space.
static func wrap_lon(lon: float) -> float:
	var x := fmod(lon + 180.0, 360.0)
	if x < 0.0:
		x += 360.0
	return x - 180.0


## lat/lon (degrees) -> normalized Mercator (0..1, y down).
static func to_norm(lat: float, lon: float) -> Vector2:
	var la := deg_to_rad(clamp_lat(lat))
	var nx := (wrap_lon(lon) + 180.0) / 360.0
	var ny := (1.0 - log(tan(la) + 1.0 / cos(la)) / PI) * 0.5
	return Vector2(nx, ny)


## Normalized Mercator -> lat/lon (degrees).
static func from_norm(n: Vector2) -> Vector2:
	var lon := n.x * 360.0 - 180.0
	var t := PI * (1.0 - 2.0 * n.y)
	# GDScript has no sinh(); this is its definition.
	var lat := rad_to_deg(atan((exp(t) - exp(-t)) * 0.5))
	return Vector2(lat, lon)


## Fractional tile coordinate at a zoom level. floor() it for a tile index,
## the fraction is the position inside that tile.
static func to_tile(lat: float, lon: float, zoom: int) -> Vector2:
	return to_norm(lat, lon) * float(1 << zoom)


static func tile_to_latlon(tx: float, ty: float, zoom: int) -> Vector2:
	var scale := float(1 << zoom)
	return from_norm(Vector2(tx / scale, ty / scale))


## How many meters one normalized unit covers at this latitude. Mercator
## stretches with latitude, so scale bars and "meters -> pixels" both need it.
static func meters_per_norm(lat: float) -> float:
	return TAU * EARTH_RADIUS_M * cos(deg_to_rad(clamp_lat(lat)))


## Ground resolution in meters per screen pixel, for a map drawn with
## `tile_px`-sized tiles at a (possibly fractional) zoom.
static func meters_per_pixel(lat: float, zoom: float, tile_px: float = 256.0) -> float:
	return meters_per_norm(lat) / (tile_px * pow(2.0, zoom))


## Great-circle distance in meters.
static func distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := deg_to_rad(lat2 - lat1)
	var dl := deg_to_rad(lon2 - lon1)
	var a := sin(dp * 0.5) * sin(dp * 0.5) + cos(p1) * cos(p2) * sin(dl * 0.5) * sin(dl * 0.5)
	return 2.0 * EARTH_RADIUS_M * atan2(sqrt(a), sqrt(maxf(0.0, 1.0 - a)))


## Initial bearing in degrees clockwise from true north.
static func bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dl := deg_to_rad(lon2 - lon1)
	var y := sin(dl) * cos(p2)
	var x := cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
	return fposmod(rad_to_deg(atan2(y, x)), 360.0)


## Travel `dist_m` from a point along `bearing`, for route corridors and
## dead-reckoning a position between fixes.
static func offset_m(lat: float, lon: float, bearing: float, dist_m: float) -> Vector2:
	var ang := dist_m / EARTH_RADIUS_M
	var b := deg_to_rad(bearing)
	var p1 := deg_to_rad(lat)
	var l1 := deg_to_rad(lon)
	var p2 := asin(sin(p1) * cos(ang) + cos(p1) * sin(ang) * cos(b))
	var l2 := l1 + atan2(sin(b) * sin(ang) * cos(p1), cos(ang) - sin(p1) * sin(p2))
	return Vector2(rad_to_deg(p2), wrap_lon(rad_to_deg(l2)))


## Meters from point P to segment AB, and where along AB the closest point
## sits (0..1). Used to snap events to the planned route and to decide
## whether a fix belongs to the corridor we prefetched tiles for.
static func point_segment_m(p: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	# Work in a local equirectangular frame around A: over segment lengths
	# (kilometers at most) the distortion is far below GPS noise.
	var cos_lat := cos(deg_to_rad(clamp_lat(a.x)))
	var mdeg := EARTH_RADIUS_M * PI / 180.0
	var ax := 0.0
	var ay := 0.0
	var bx := wrap_lon(b.y - a.y) * cos_lat * mdeg
	var by := (b.x - a.x) * mdeg
	var px := wrap_lon(p.y - a.y) * cos_lat * mdeg
	var py := (p.x - a.x) * mdeg
	var vx := bx - ax
	var vy := by - ay
	var len_sq := vx * vx + vy * vy
	var t := 0.0
	if len_sq > 0.0:
		t = clampf((px * vx + py * vy) / len_sq, 0.0, 1.0)
	var dx := px - vx * t
	var dy := py - vy * t
	return {"m": sqrt(dx * dx + dy * dy), "t": t}


## Douglas-Peucker simplification on a lat/lon polyline, tolerance in meters.
## A day of riding is ~30k fixes; drawing that raw is what makes a map app
## feel like mud. Simplified once per zoom level it is a few hundred points
## that look identical.
static func simplify(points: PackedVector2Array, tol_m: float) -> PackedVector2Array:
	if points.size() <= 2 or tol_m <= 0.0:
		return points
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep.fill(0)
	keep[0] = 1
	keep[points.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var worst := -1.0
		var worst_i := -1
		for i in range(seg.x + 1, seg.y):
			var d: float = point_segment_m(points[i], points[seg.x], points[seg.y])["m"]
			if d > worst:
				worst = d
				worst_i = i
		if worst_i >= 0 and worst > tol_m:
			keep[worst_i] = 1
			stack.push_back(Vector2i(seg.x, worst_i))
			stack.push_back(Vector2i(worst_i, seg.y))
	var out := PackedVector2Array()
	for i in points.size():
		if keep[i] == 1:
			out.push_back(points[i])
	return out


# ---------------------------------------------------------------- formatting


static func format_distance(meters: float, metric: bool) -> String:
	if metric:
		if meters < 1000.0:
			return "%d m" % roundi(meters)
		return "%.1f km" % (meters / 1000.0)
	var miles := meters / METERS_PER_MILE
	if miles < 0.1:
		return "%d ft" % roundi(meters / METERS_PER_FOOT)
	return "%.1f mi" % miles


static func format_speed(mps: float, metric: bool) -> String:
	if metric:
		return "%.1f km/h" % (mps * 3.6)
	return "%.1f mph" % (mps * 3600.0 / METERS_PER_MILE)


static func format_elevation(meters: float, metric: bool) -> String:
	if metric:
		return "%d m" % roundi(meters)
	return "%d ft" % roundi(meters / METERS_PER_FOOT)


## Compass point for a bearing — easier to read at a glance than degrees.
static func compass(bearing: float) -> String:
	const NAMES := ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
		"S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
	return NAMES[int(round(fposmod(bearing, 360.0) / 22.5)) % 16]


static func format_latlon(lat: float, lon: float) -> String:
	var ns := "N" if lat >= 0.0 else "S"
	var ew := "E" if lon >= 0.0 else "W"
	return "%.5f°%s %.5f°%s" % [absf(lat), ns, absf(lon), ew]
