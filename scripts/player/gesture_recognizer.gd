class_name GestureRecognizer
## Classifies a drawn stroke into one RUNE-shape, by TEMPLATE MATCHING.
##
## This began as a pile of heuristics — count the turning, count the corners,
## measure the straightness — and each new shape needed another measurement
## that did not quite collide with the last. It failed in play for a reason
## worth recording: those measurements survive *uncorrelated* noise, which is
## what a test harness produces, but a real hand does not shake randomly. It
## WOBBLES, slowly and smoothly, and a slow wobble reads as genuine curvature
## no matter how much you smooth it. Carets were coming out as waves — which
## is water, which is rain — about half the time.
##
## So strokes are now compared against reference drawings, in the manner of the
## $1 recognizer. Resample every stroke to the same number of points, centre
## it, scale it, and measure the average distance to each template. The nearest
## template wins, if it is near enough at all; otherwise the stroke means
## nothing. Under simulated hand tremor this reads every shape correctly where
## the heuristics managed barely half.
##
## Two deliberate departures from the published algorithm, both because our
## gestures are not abstract symbols:
##
##  * NO ROTATION NORMALISATION. $1 rotates each stroke to a canonical angle,
##    which makes it blind to orientation — and a vertical line and a
##    horizontal line are DIFFERENT RUNES here. Orientation is meaning.
##  * UNIFORM SCALING, not into a square. Squashing every stroke to a box
##    would likewise make a tall line and a wide line identical.
##
## Adding a gesture is now adding a template. That is the point of the rewrite:
## no new measurement, and no new threshold to collide with the old ones.

## Points every stroke is resampled to before comparison. Enough to hold the
## shape of a spiral; few enough that matching every template is trivial work.
const SAMPLES := 48
## The size every stroke is scaled to, in arbitrary units.
const REF_SIZE := 200.0
## Average per-point distance beyond which a stroke matches nothing at all.
## Tuned so a genuine scribble is rejected while a sloppy shape still lands.
const MATCH_LIMIT := 68.0
## Shorter than this and it was a poke, not a drawing.
const MIN_PATH_LENGTH := 60.0

## Built once, on first use: shape name -> array of normalised point arrays.
static var _templates := {}


## The rune-shape this stroke most resembles, or "none".
static func classify(points: PackedVector2Array) -> String:
	if points.size() < 6 or _path_length(points) < MIN_PATH_LENGTH:
		return "none"
	_build_templates()
	var drawn := _normalize(points)
	# People draw the same shape in either direction — a line from the top or
	# from the bottom is the same line — so each stroke is tried both ways.
	var backwards := _reversed(drawn)
	var best_name := "none"
	var best_dist := MATCH_LIMIT
	for name: String in _templates:
		for template: PackedVector2Array in _templates[name]:
			var d := minf(_distance(drawn, template), _distance(backwards, template))
			if d < best_dist:
				best_dist = d
				best_name = name
	return best_name


## Resample to a fixed count, centre on the origin, and scale UNIFORMLY so the
## longer side reaches the reference size. Aspect is preserved on purpose: it
## is the only thing separating a tall line from a wide one.
static func _normalize(points: PackedVector2Array) -> PackedVector2Array:
	var path := _resample(points, SAMPLES)
	var lo := path[0]
	var hi := path[0]
	var centre := Vector2.ZERO
	for p in path:
		lo = lo.min(p)
		hi = hi.max(p)
		centre += p
	centre /= float(path.size())
	var span := REF_SIZE / maxf(maxf(hi.x - lo.x, hi.y - lo.y), 0.001)
	var out := PackedVector2Array()
	for p in path:
		out.append((p - centre) * span)
	return out


## Mean point-to-point distance between two normalised strokes.
static func _distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var total := 0.0
	for i in a.size():
		total += a[i].distance_to(b[i])
	return total / float(a.size())


static func _reversed(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(path.size() - 1, -1, -1):
		out.append(path[i])
	return out


## THE REFERENCE DRAWINGS. Several per shape, because a person's idea of a
## spiral (how many times round?) or an arc (opening which way?) varies far
## more than their idea of a straight line. Variants are cheap — each is 48
## points and a few dozen sums — and they are what makes the matcher forgiving
## without making it vague.
static func _build_templates() -> void:
	if not _templates.is_empty():
		return
	_add("vline", func(t: float) -> Vector2: return Vector2(0.0, t * 200.0))
	_add("hline", func(t: float) -> Vector2: return Vector2(t * 200.0, 0.0))
	_add("dline", func(t: float) -> Vector2: return Vector2(t * 200.0, t * 200.0))
	_add("dline", func(t: float) -> Vector2: return Vector2(t * 200.0, 200.0 - t * 200.0))
	# A ring may be begun anywhere on itself, so offer it begun in four places.
	for start in 4:
		var phase := start / 4.0
		_add("circle", func(t: float) -> Vector2:
			var a := TAU * (t + phase)
			return Vector2(cos(a), sin(a)) * 100.0)
	# How many times a person winds a spiral is anyone's guess, and point-wise
	# distance is very sensitive to it — so offer the whole reasonable range
	# rather than one opinion. Without this, spirals matched nothing at all.
	for turns: float in [1.5, 2.0, 2.5, 3.0]:
		for start: float in [0.0, 0.5]:
			_add("spiral", func(t: float) -> Vector2:
				var a := TAU * (t * turns + start)
				return Vector2(cos(a), sin(a)) * (18.0 + t * 112.0))
			_add("rev_spiral", func(t: float) -> Vector2:
				var a := -TAU * (t * turns + start)
				return Vector2(cos(a), sin(a)) * (18.0 + t * 112.0))
	# WAVES AND ZIGZAGS IN EVERY BEARING. Without rotation invariance each
	# orientation has to be offered outright, and having only the lying-down
	# ones meant an S written the way people actually write the letter S — tall,
	# or on the slant — read as a diagonal slash. Which is FIRE. Which is why
	# water could not be cast at all.
	for flip: float in [1.0, -1.0]:
		_add("wave", func(t: float) -> Vector2:
			return Vector2(t * 200.0, flip * sin(t * TAU) * 70.0))
		_add("wave", func(t: float) -> Vector2:
			return Vector2(flip * sin(t * TAU) * 70.0, t * 200.0))
		_add("wave", func(t: float) -> Vector2:
			return Vector2(t * 200.0, flip * sin(t * TAU) * 80.0))
		_add("wave", func(t: float) -> Vector2:
			return Vector2(flip * sin(t * TAU) * 80.0, t * 200.0))
		_add("zigzag", func(t: float) -> Vector2:
			var teeth := t * 5.0
			var up := 1.0 if int(teeth) % 2 == 1 else -1.0
			return Vector2(t * 200.0, flip * up * absf(fmod(teeth, 1.0) * 2.0 - 1.0) * 60.0))
		_add("zigzag", func(t: float) -> Vector2:
			var teeth := t * 5.0
			var up := 1.0 if int(teeth) % 2 == 1 else -1.0
			return Vector2(flip * up * absf(fmod(teeth, 1.0) * 2.0 - 1.0) * 60.0, t * 200.0))
	# And on the slant, which is how a hurried S usually comes out.
	for slant: float in [PI / 4.0, -PI / 4.0]:
		for flip: float in [1.0, -1.0]:
			_add("wave", func(t: float) -> Vector2:
				var p := Vector2(t * 200.0 - 100.0, flip * sin(t * TAU) * 70.0)
				return p.rotated(slant))
	# A caret is a peak, pointing any of four ways.
	_add("caret", func(t: float) -> Vector2:
		return Vector2(t * 200.0, -140.0 * (1.0 - absf(2.0 * t - 1.0))))
	_add("caret", func(t: float) -> Vector2:
		return Vector2(t * 200.0, 140.0 * (1.0 - absf(2.0 * t - 1.0))))
	_add("caret", func(t: float) -> Vector2:
		return Vector2(-140.0 * (1.0 - absf(2.0 * t - 1.0)), t * 200.0))
	_add("caret", func(t: float) -> Vector2:
		return Vector2(140.0 * (1.0 - absf(2.0 * t - 1.0)), t * 200.0))
	# A bow, opening any of four ways.
	for quarter in 4:
		var turn := quarter * PI / 2.0
		_add("arc", func(t: float) -> Vector2:
			var a := -PI / 2.0 - PI * 0.45 + PI * 0.9 * t + turn
			return Vector2(cos(a), sin(a)) * 110.0)


static func _add(name: String, shape: Callable) -> void:
	var raw := PackedVector2Array()
	for i in SAMPLES:
		raw.append(shape.call(float(i) / float(SAMPLES - 1)))
	if not _templates.has(name):
		_templates[name] = []
	_templates[name].append(_normalize(raw))


static func _path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## Evenly respaces the trail so classification is independent of drawing speed:
## a stroke dashed off in ten samples and one laboured over in three hundred
## become the same forty-eight points.
static func _resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	var total := _path_length(points)
	if total <= 0.0:
		var flat := PackedVector2Array()
		for _i in n:
			flat.append(points[0])
		return flat
	var interval := total / float(n - 1)
	var result := PackedVector2Array([points[0]])
	var dist_accum := 0.0
	var i := 1
	var pts := points.duplicate()
	while i < pts.size():
		var seg := pts[i - 1].distance_to(pts[i])
		if dist_accum + seg >= interval and seg > 0.0:
			var t := (interval - dist_accum) / seg
			var new_point := pts[i - 1].lerp(pts[i], t)
			result.append(new_point)
			pts.insert(i, new_point)
			dist_accum = 0.0
		else:
			dist_accum += seg
		i += 1
	while result.size() < n:
		result.append(pts[pts.size() - 1])
	return result
