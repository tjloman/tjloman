class_name GestureRecognizer
## Classifies a raw mouse trail (screen-space points) into one RUNE-shape.
##
## Each shape stands for a rune, and runes combine (see Spellbook), so the
## alphabet has to be small enough to learn and — far more importantly —
## RELIABLE. A recognizer that confuses two shapes is worse than one that
## knows fewer, because a misread rune casts the wrong miracle at full cost.
## Every shape below is separated by a different measurement, not by a
## threshold on the same one:
##
##   "spiral"     – 1.3+ full turns of winding, one way
##   "rev_spiral" – the same, winding the other way
##   "circle"     – about one turn, and it closes
##   "arc"        – a half-to-three-quarter bow: curved, open, no reversal
##   "zigzag"     – three or more SHARP reversals: a jagged scrawl
##   "caret"      – exactly one sharp corner: a ^ or a v
##   "wave"       – a smooth S: it curves one way and then the other
##   "vline"      – a tall straight stroke
##   "hline"      – a wide straight stroke
##   "dline"      – a diagonal slash
##   "none"       – too short, or nothing we can name
##
## The order of the tests below is load-bearing: the most distinctive
## measurements are consumed first, so a shape can never fall through into a
## looser test that would also have matched it.

const MIN_PATH_LENGTH := 60.0  # pixels; anything shorter is a misclick
## Radians of consistent curving before a curl "commits" to a direction.
## ~34 degrees: enough that a wobbly straight line never registers, low
## enough that a gently drawn S still does.
const INFLECT_TURN := 0.6
## A CORNER: a single step that turns this hard is a deliberate point, not a
## curve. ~72 degrees. Corners are what separate a jagged zigzag and a sharp
## caret from a smooth wave and a smooth arc.
const CORNER_TURN := 1.25


static func classify(points: PackedVector2Array) -> String:
	if points.size() < 4:
		return "none"

	# Two smoothings, because the features want different things. CORNERS are
	# sharp by nature and one pass is all they can survive; CURVATURE stats are
	# ruined by hand jitter and need three. Measuring both on one path is what
	# made arcs read as waves and carets read as nothing.
	var base := _resample(points, 48)
	var sharp := _smooth(base, 1)
	var path := _smooth(base, 3)
	var path_len := _path_length(path)
	if path_len < MIN_PATH_LENGTH:
		return "none"

	var bbox := _bounding_box(path)
	var total_turn := 0.0   # signed accumulated turning angle
	# Curvature inflections: how many times the stroke stops curving one way
	# and commits to curving the other. An S has 1, a sine W has 2+, a
	# straight line or a single arc/circle/spiral has 0 — this is what makes
	# a SMOOTH wave detectable, not just a jagged one.
	var inflections := 0
	var run_turn := 0.0     # signed turn accumulated in the current curl
	var committed_sign := 0
	var prev_dir := Vector2.ZERO
	for i in range(1, path.size()):
		var dir := path[i] - path[i - 1]
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		if prev_dir != Vector2.ZERO:
			var step := prev_dir.angle_to(dir)
			total_turn += step
			# Grow the current curl if it keeps turning the same way; if it
			# turns the other way, start a fresh curl. Once a curl exceeds the
			# commit threshold, it "sets" a direction — a later curl setting
			# the OPPOSITE direction is an inflection. (Near-straight steps are
			# ignored so a straight run mid-stroke can't reset the curl.)
			if absf(step) > 0.01:
				if run_turn == 0.0 or (step > 0.0) == (run_turn > 0.0):
					run_turn += step
				else:
					run_turn = step
				if absf(run_turn) >= INFLECT_TURN:
					var s := 1 if run_turn > 0.0 else -1
					if committed_sign != 0 and s != committed_sign:
						inflections += 1
					committed_sign = s
					run_turn = 0.0
		prev_dir = dir

	var corners := _corner_count(sharp)
	var reversals := _reversal_count(sharp)
	var closed := path[0].distance_to(path[path.size() - 1]) < path_len * 0.25
	var aspect := bbox.size.x / maxf(bbox.size.y, 1.0)
	# How much of the stroke's length actually went anywhere. 1.0 is a ruled
	# line; a circle is near 0.
	var straightness := path[0].distance_to(path[path.size() - 1]) / maxf(path_len, 1.0)
	# THE APEX: how far the first third's heading turns from the last third's.
	# Averaged over many samples, so it holds up where corner-hunting does not.
	var n := path.size()
	var lead := path[n / 3] - path[0]
	var tail := path[n - 1] - path[2 * n / 3]
	var apex := 0.0
	if lead.length() > 0.001 and tail.length() > 0.001:
		apex = absf(lead.normalized().angle_to(tail.normalized()))
	# A CARET bends all in ONE PLACE, so each half of it is itself straight. An
	# ARC bends the whole way along, so its halves are curved too. This is the
	# only measurement that reliably separates the two.
	var half := n / 2
	var limbs := minf(
		path[half].distance_to(path[0]) / maxf(_path_length(path.slice(0, half + 1)), 1.0),
		path[n - 1].distance_to(path[half]) / maxf(_path_length(path.slice(half)), 1.0))

	# Spiral: 1.3+ full turns of winding. Sign tells clockwise from counter
	# (screen y is down, so positive accumulated angle winds one way). Tested
	# first because nothing else winds this far.
	if absf(total_turn) > 8.0:
		return "spiral" if total_turn > 0.0 else "rev_spiral"

	# Circle: roughly one loop that closes.
	if absf(total_turn) > 4.5 and closed and aspect > 0.35 and aspect < 2.8:
		return "circle"

	# ZIGZAG before wave: a jagged scrawl has real CORNERS where a smooth S has
	# only curvature. This distinction is what earns fury its own rune.
	if corners >= 3 or reversals >= 3:
		return "zigzag"

	# CARET: a ^ or a v — one hard turn, straight limbs either side of it.
	if not closed and inflections <= 1 and apex > 1.05 and limbs > 0.94 \
			and straightness > 0.45:
		return "caret"

	# Wave / S: curved one way and then the other. The straightness guard stops
	# a shaky ruled line from reading as a lazy S.
	if (inflections >= 1 or reversals >= 2) and straightness < 0.93:
		return "wave"

	# ARC: a bow. Curved well past a wobble, open, never doubling back.
	if absf(total_turn) > 2.0 and absf(total_turn) <= 4.5 and not closed \
			and inflections == 0:
		return "arc"

	# Straight-ish strokes: little accumulated turning.
	if absf(total_turn) < 2.0:
		if bbox.size.y > bbox.size.x * 2.0:
			return "vline"
		if bbox.size.x > bbox.size.y * 2.0:
			return "hline"
		# Neither tall nor wide but clearly drawn: a diagonal slash.
		if bbox.size.x > 40.0 and bbox.size.y > 40.0:
			return "dline"

	return "none"


## How many genuine CORNERS the stroke has — places where it changes heading
## abruptly rather than curving round. Measured over a wide window so a long
## smooth curve (which turns just as far, but gradually) never counts as one.
static func _corner_count(points: PackedVector2Array) -> int:
	var corners := 0
	var span := 4
	for i in range(span, points.size() - span):
		var before := points[i] - points[i - span]
		var after := points[i + span] - points[i]
		if before.length() < 0.001 or after.length() < 0.001:
			continue
		if absf(before.normalized().angle_to(after.normalized())) > CORNER_TURN:
			corners += 1
	# Neighbouring samples both see the same corner, so runs collapse to one.
	return int(ceil(corners / 2.0))


## Hard about-turns: the stroke doubling back on itself.
static func _reversal_count(points: PackedVector2Array) -> int:
	var reversals := 0
	var prev := Vector2.ZERO
	for i in range(1, points.size()):
		var dir := points[i] - points[i - 1]
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		if prev != Vector2.ZERO and prev.dot(dir) < -0.17:
			reversals += 1
		prev = dir
	return reversals


## Rolls the hand's shake out of a stroke without moving where it actually
## went — a plain 1-2-1 blur, run as many times as the caller needs.
static func _smooth(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	var path := points
	for _pass in passes:
		if path.size() < 3:
			return path
		var out := PackedVector2Array([path[0]])
		for i in range(1, path.size() - 1):
			out.append((path[i - 1] + path[i] * 2.0 + path[i + 1]) * 0.25)
		out.append(path[path.size() - 1])
		path = out
	return path


static func _path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


static func _bounding_box(points: PackedVector2Array) -> Rect2:
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return rect


## Evenly respaces the trail so classification is independent of mouse speed.
static func _resample(points: PackedVector2Array, n: int) -> PackedVector2Array:
	var total := _path_length(points)
	if total <= 0.0:
		return points
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
