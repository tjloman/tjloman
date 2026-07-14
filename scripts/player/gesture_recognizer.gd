class_name GestureRecognizer
## Classifies a raw mouse trail (screen-space points) into a miracle gesture.
##
## Deliberately simple heuristics for the PoC — the seam to replace later with
## a proper $1/$Q recognizer when we have dozens of miracles:
##   "circle"    – closed loop, high total turning angle        -> Food
##   "zigzag"    – several sharp direction reversals            -> Rain
##   "vline"     – tall, straight stroke                        -> Lightning
##   "hline"     – wide, straight stroke                        -> Heal
##   "none"      – unrecognized

const MIN_PATH_LENGTH := 60.0  # pixels; anything shorter is a misclick


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
	var prev_dir := Vector2.ZERO
	for i in range(1, resampled.size()):
		var dir := resampled[i] - resampled[i - 1]
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		if prev_dir != Vector2.ZERO:
			total_turn += prev_dir.angle_to(dir)
			if prev_dir.angle_to(dir) != 0.0 and prev_dir.dot(dir) < -0.17:
				reversals += 1
		prev_dir = dir

	var closed := resampled[0].distance_to(resampled[resampled.size() - 1]) < path_len * 0.25
	var aspect := bbox.size.x / maxf(bbox.size.y, 1.0)

	# Circle: loops around at least ~270 degrees and roughly closes.
	if absf(total_turn) > 4.5 and closed and aspect > 0.35 and aspect < 2.8:
		return "circle"

	# Zigzag: multiple hard reversals (a W / lightning-bolt scribble).
	if reversals >= 2:
		return "zigzag"

	# Straight-ish strokes: little accumulated turning.
	if absf(total_turn) < 2.0:
		if bbox.size.y > bbox.size.x * 2.0:
			return "vline"
		if bbox.size.x > bbox.size.y * 2.0:
			return "hline"

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
