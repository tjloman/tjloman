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
## HOW FAR A CARET IS ALLOWED TO LEAN and still be the caret it was aimed at.
## Four facings are ninety degrees apart, so forty-five is the most a lean can
## ever be worth; a reference drawing at twenty-two either side of upright
## covers the span without reaching into the neighbour's half.
const CARET_LEAN := deg_to_rad(22.0)
## HOW FAR A BOW IS DRAWN ROUND, from a lazy one to one nearly shut. A hand
## aiming for a C lands anywhere across this range and a little past either end.
const BOW_SPANS: Array[float] = [PI * 0.9, PI * 1.11, PI * 1.33]
## HOW NEARLY SHUT A RING IS, as a share of the whole way round. Four-fifths is
## as open as a ring gets before it is honestly a bow; a little past one is the
## overrun of a hand that did not stop on the mark.
const RING_SHUT: Array[float] = [1.0, 0.88, 0.80, 1.12]

## Built once, on first use: shape name -> array of normalised point arrays.
static var _templates := {}


## BUILD THE TEMPLATES NOW, rather than on the first stroke a player draws.
##
## Eighty-four reference drawings, each resampled and normalised, is a few
## milliseconds — nothing at all during world generation, and a visible hitch
## if it lands on the first flick of a finger instead. Called at boot.
static func warm() -> void:
	_build_templates()


## THE REFERENCE DRAWING for a shape, as points in a 100x100 box — what the
## recognizer is actually comparing against, handed back so the interface can
## DRAW it. The glyph shown on screen is therefore never a separate hand-drawn
## picture that could drift from what the matcher believes; it is the matcher's
## own idea of the shape.
static func outline(shape: String) -> PackedVector2Array:
	_build_templates()
	var out := PackedVector2Array()
	if not _templates.has(shape):
		return out
	# The first variant is the plainest one — the others are bearings and
	# tooth-counts that only exist to be forgiving.
	var pts: PackedVector2Array = _templates[shape][0]
	for p in pts:
		out.append(Vector2(50.0 + p.x * 0.22, 50.0 + p.y * 0.22))
	return out


## THE READING SO FAR, for a stroke still being drawn. Same matcher, but it
## reports how sure it is, because a half-drawn shape genuinely IS a different
## shape — a circle is an arc until the moment it closes — and the readout has
## to be able to show that it has not made its mind up yet.
##
## Nothing is ever COMMITTED from this: the rune that goes on the slate comes
## from `classify` on the finished stroke, when the finger comes up. This is
## only what the player is shown while they draw.
static func peek(points: PackedVector2Array) -> Dictionary:
	if points.size() < 6 or _path_length(points) < MIN_PATH_LENGTH:
		return {"shape": "none", "confidence": 0.0}
	_build_templates()
	var drawn := _normalize(points)
	var backwards := _reversed(drawn)
	var best := MATCH_LIMIT * 2.0
	var second := MATCH_LIMIT * 2.0
	var name := "none"
	for shape: String in _templates:
		var near := MATCH_LIMIT * 2.0
		for template: PackedVector2Array in _templates[shape]:
			near = minf(near, minf(_distance(drawn, template), _distance(backwards, template)))
		if near < best:
			second = best
			best = near
			name = shape
		elif near < second:
			second = near
	if best >= MATCH_LIMIT:
		return {"shape": "none", "confidence": 0.0}
	# Two things have to hold for a reading to look settled: it must FIT, and it
	# must fit better than whatever is second. A stroke sitting between two
	# shapes is exactly the moment to show a player that it is still undecided.
	var fit := 1.0 - best / MATCH_LIMIT
	var lead := clampf((second - best) / 22.0, 0.0, 1.0)
	return {"shape": name, "confidence": clampf(fit * 0.45 + lead * 0.55, 0.0, 1.0)}


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
	# A RING may be begun anywhere on itself, so offer it begun in four places —
	# AND NOT QUITE SHUT, AND OVERSHOT, AND SQUASHED NARROW BY A THUMB.
	#
	# Every ring here used to be a perfect one, and a perfect ring is not what a
	# hand draws. A ring lifted a quarter early was read as WATER; a ring
	# overrun by a sixth was read as CALM; and once the carets learned to lean,
	# a ring lifted a sixth early became SKY. All three are the same fault as
	# the bow's: the shape a player actually makes was missing, so it fell to
	# whichever neighbour happened to be closest. A ring is now a ring from
	# four-fifths of the way round to a little past shut, wide or narrow.
	for start in 4:
		var phase := start / 4.0
		for shut: float in RING_SHUT:
			_add("circle", func(t: float) -> Vector2:
				var a := TAU * (t * shut + phase)
				return Vector2(cos(a), sin(a)) * 100.0)
		for squash: Vector2 in [Vector2(0.5, 1.0), Vector2(1.0, 0.5)]:
			_add("circle", func(t: float) -> Vector2:
				var a := TAU * (t + phase)
				return Vector2(cos(a), sin(a)) * squash * 100.0)
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
	# FURY IS A SHARP Z NOW, not a zigzag. The zigzag was the one rune that
	# broke thermally: a five-toothed scrawl needs its teeth SAMPLED, and a
	# phone that has pulled its touch scan rate back reports a dozen points for
	# the whole stroke — at which point the teeth are gone and it reads as a
	# plain horizontal line, which is EARTH. On a hot phone earth+fury (the
	# earthquake) was quietly becoming earth+earth, which plants a wood.
	#
	# Two corners survive what five teeth cannot. Offered wide, square and tall,
	# since nobody writes a Z at one aspect ratio; both bearings come free,
	# because every stroke is tried reversed as well.
	for tall: float in [0.62, 1.0, 1.55]:
		_add("zed", func(t: float) -> Vector2:
			var run := 200.0 / maxf(tall, 0.4)
			var drop := 200.0 * tall
			if t < 1.0 / 3.0:
				return Vector2(t * 3.0 * run, 0.0)
			if t < 2.0 / 3.0:
				var k := (t - 1.0 / 3.0) * 3.0
				return Vector2(run - k * run, k * drop)
			return Vector2((t - 2.0 / 3.0) * 3.0 * run, drop))
	# CANCEL — A SWEEP, and NOT a rune. It means "never mind": the casting
	# session ends and nothing is cast (see DivineHand._end_stroke).
	# Deliberately absent from Spellbook, so it can never be an ingredient in a
	# working or turn up in the reference table as one.
	#
	# It was an X first, which was wrong for a reason worth writing down: you
	# CANNOT LIFT THE FINGER in this system, and nobody on earth draws an X
	# without lifting. Reading a retraced X perfectly is no use if no hand will
	# ever produce one — the same mistake as scoring ideal shapes against ideal
	# shapes. So it is now one unbroken motion a thumb actually makes: straight
	# down, then hooked away, like sweeping something off a table.
	#
	# A scribbling-out was the other obvious candidate and was measured and
	# rejected: many small teeth are exactly what a throttled digitizer stops
	# sampling, and it collapsed to 75%, which is the failure that took the old
	# zigzag off fury in the first place.
	for hook: float in [0.55, 0.8, 1.05]:
		_add("sweep", func(t: float) -> Vector2:
			if t < 0.62:
				return Vector2(0.0, t / 0.62 * 200.0)
			var k := (t - 0.62) / 0.38
			# The hook: a quarter turn away, never back over the stem.
			var a := -PI * 0.5 * k
			return Vector2(-sin(a * -1.0) * 95.0 * hook,
				200.0 + (1.0 - cos(a)) * 55.0 * hook))
	# And on the slant, which is how a hurried S usually comes out.
	for slant: float in [PI / 4.0, -PI / 4.0]:
		for flip: float in [1.0, -1.0]:
			_add("wave", func(t: float) -> Vector2:
				var p := Vector2(t * 200.0 - 100.0, flip * sin(t * TAU) * 70.0)
				return p.rotated(slant))
	# A CARET IS A PEAK, pointing any of four ways — AND LEANING EITHER WAY.
	#
	# The lean matters more than it looks. Without it, a `>` caret tipped twenty
	# degrees was read as the SWEEP, which throws the whole spell away: four
	# runes in, one slightly crooked stroke, and you lose the lot. Nothing else
	# in the game punishes a small mistake that hard. The cause was that the
	# alphabet held no drawing of a caret that leans, so a leaning caret fell to
	# the nearest thing that does — a stroke with a hook on the end. With the
	# leaned drawings in, every facing survives a forty degree tilt (out of the
	# forty-five it has before it truly is its neighbour), on a throttled phone
	# as well as a cold one, and the sweep still reads as itself every time.
	for quarter in 4:
		var point := quarter * PI / 2.0
		for lean: float in [0.0, -CARET_LEAN, CARET_LEAN]:
			_add("caret", func(t: float) -> Vector2:
				var p := Vector2(t * 200.0 - 100.0,
					-140.0 * (1.0 - absf(2.0 * t - 1.0)))
				return p.rotated(point + lean))
	# A BOW, opening any of four ways, AT THREE DEPTHS.
	#
	# All four bows used to sweep the same 162 degrees — shallower than a half
	# circle. The alphabet therefore held no deep bow at all, and a player
	# drawing a proper fat C found the nearest match was a caret, because the
	# caret is this alphabet's generic go-out-and-come-back shape. That is why
	# sky kept overriding ward: not a hand drawing it wrong, an alphabet with a
	# hole in it. A bow anywhere from a lazy 150 degrees to a nearly shut 260
	# now reads as ward, on every phone we model.
	for quarter in 4:
		var turn := quarter * PI / 2.0
		for span: float in BOW_SPANS:
			_add("arc", func(t: float) -> Vector2:
				var a := turn - span * 0.5 + span * t
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
