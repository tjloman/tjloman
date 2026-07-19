class_name GestureRecognizer
## Classifies a raw mouse trail (screen-space points) into a miracle gesture.
##
## Deliberately simple heuristics — enough shapes to drive the two-step
## casting system (a MENU-OPENING gesture, then a SELECTOR gesture):
##   MENU OPENERS
##     "spiral"     – 1.5+ clockwise loops, open (not closed)
##     "rev_spiral" – 1.5+ counter-clockwise loops
##     "wave"       – an S / sine: the stroke curves one way, then back the
##                    other (one or more curvature inflections). Smooth OR
##                    sharp — a lazy S counts, not just a jagged W.
##   SELECTORS (meaning depends on the open menu)
##     "circle"     – one closed loop
##     "vline"      – tall straight stroke
##     "hline"      – wide straight stroke
##     "dline"      – diagonal slash
##   "none"         – unrecognized
##
## Because selectors are namespaced inside a menu, the same simple shape can
## mean different miracles in different menus — which sidesteps the recognizer
## confusing them.

const MIN_PATH_LENGTH := 60.0  # pixels; anything shorter is a misclick
## Radians of consistent curving before a curl "commits" to a direction.
## ~34 degrees: enough that a wobbly straight line never registers, low
## enough that a gently drawn S still does.
const INFLECT_TURN := 0.6


static func classify(points: PackedVector2Array) -> String:
	if points.size() < 4:
		return "none"

	var resampled := _resample(points, 32)
	var path_len := _path_length(resampled)
	if path_len < MIN_PATH_LENGTH:
		return "none"

	var bbox := _bounding_box(resampled)
	var total_turn := 0.0   # signed accumulated turning angle
	var reversals := 0      # sharp (>100 deg) direction changes
	# Curvature inflections: how many times the stroke stops curving one way
	# and commits to curving the other. An S has 1, a sine W has 2+, a
	# straight line or a single arc/circle/spiral has 0 — this is what makes
	# a SMOOTH wave detectable, not just a jagged one.
	var inflections := 0
	var run_turn := 0.0     # signed turn accumulated in the current curl
	var committed_sign := 0
	var prev_dir := Vector2.ZERO
	for i in range(1, resampled.size()):
		var dir := resampled[i] - resampled[i - 1]
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		if prev_dir != Vector2.ZERO:
			var step := prev_dir.angle_to(dir)
			total_turn += step
			if step != 0.0 and prev_dir.dot(dir) < -0.17:
				reversals += 1
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

	var closed := resampled[0].distance_to(resampled[resampled.size() - 1]) < path_len * 0.25
	var aspect := bbox.size.x / maxf(bbox.size.y, 1.0)

	# Spiral: 1.3+ full turns of winding. Sign tells clockwise from counter
	# (screen y is down, so positive accumulated angle winds one way).
	if absf(total_turn) > 8.0:
		return "spiral" if total_turn > 0.0 else "rev_spiral"

	# Circle: roughly one loop that closes.
	if absf(total_turn) > 4.5 and closed and aspect > 0.35 and aspect < 2.8:
		return "circle"

	# Wave / S: the stroke curved one way then back (an inflection), or was
	# scribbled with hard reversals. Forgiving — a lazy S is enough.
	if inflections >= 1 or reversals >= 2:
		return "wave"

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
