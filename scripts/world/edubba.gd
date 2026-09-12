class_name Edubba
extends StaticBody3D
## The Edubba — a village schoolhouse (the word is Sumerian, "tablet house").
## Once built, the village's children gather here under a teacher instead of
## trailing their mothers, which frees the mothers to bear more children.

## WHAT THE CHILDREN ARE DOING RIGHT NOW.
##
## They used to mill about within four metres of the door in a loose fog, which
## is what "children are at school" looks like when nobody has decided what a
## lesson IS. A class does not mill. It sits in a ring to be told something, it
## stands in a line and follows, it holds hands and turns, it crowds round the
## one grown-up in the yard. That is what a school looks like from across a
## village, and it is all any of this has to be.
##
## The horseshoe is the ring with a gap in it, because a story circle that
## closes has its back to the teller — and a class of five in an open arc reads
## as a `C` from the air, which is the shape a child would draw.
## TYPED, and it has to be. An untyped array literal holds Variants, so
## LESSONS[i] is a Variant and `var next := LESSONS[i]` has nothing to infer
## from — which this project builds as an error that stops every dependent
## script loading, and took the whole village down with it.
const LESSONS: Array[String] = ["circle", "horseshoe", "line", "dance", "huddle"]
const LESSON_LEAST := 14.0
const LESSON_MOST := 26.0
## How far apart the children stand in each. A ring's radius grows with the
## class so twenty children do not stand inside one another.
const SEAT_GAP := 1.25
const RING_LEAST := 2.0
const LINE_GAP := 1.4
## How fast a dance turns, in radians a second. Slow: they are small.
const DANCE_SPIN := 0.5

var village: Village

var _lesson := "circle"
var _left := 0.0
## Turns slowly under the dance, and gives the other formations a little life
## so a class is never a diagram.
var _drift := 0.0


func _ready() -> void:
	add_to_group("edubba")
	_left = randf_range(LESSON_LEAST, LESSON_MOST)
	_lesson = LESSONS[randi() % LESSONS.size()]
	set_meta("hover_name", "Edubba (school)")
	collision_layer = 4  # hoverable; villagers pass through
	collision_mask = 0

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.4, 3.0, 3.4)
	col.shape = shape
	col.position = Vector3(0, 1.5, 0)
	add_child(col)

	var custom := ModelBank.instantiate("school")
	if custom != null:
		add_child(custom)
	else:
		# A broad, low hall with a pale plastered look and a flat reed roof.
		add_child(Util.box(Vector3(4.4, 1.2, 3.4), Color(0.5, 0.47, 0.42), Vector3(0, -0.5, 0)))
		add_child(Util.box(Vector3(4.0, 2.0, 3.0), Color(0.82, 0.76, 0.62), Vector3(0, 1.0, 0)))
		add_child(Util.box(Vector3(4.4, 0.4, 3.4), Color(0.55, 0.45, 0.3), Vector3(0, 2.2, 0)))
		# A doorway and two small windows.
		add_child(Util.box(Vector3(0.7, 1.3, 0.1), Color(0.35, 0.25, 0.15), Vector3(0, 0.65, 1.5)))
		for x in [-1.1, 1.1]:
			add_child(Util.box(Vector3(0.5, 0.5, 0.08), Color(0.4, 0.55, 0.6), Vector3(x, 1.3, 1.5)))
		# A little standing tablet by the door, to read as "school".
		add_child(Util.box(Vector3(0.5, 0.7, 0.08), Color(0.72, 0.64, 0.5), Vector3(1.5, 0.9, 1.2)))


## Where children and the teacher gather — the yard just outside the door.
func yard_position() -> Vector3:
	return global_position + Vector3(0, 0, 3.0)


## The lesson under way. Changes on its own clock — see `_process`.
func lesson() -> String:
	return _lesson


## WHERE THE i-TH CHILD OF `many` STANDS. Everything is worked out from the two
## numbers a child actually knows about itself: which one it is, and how many
## there are. No child needs to be told where any other one is.
func spot_for(which: int, many: int) -> Vector3:
	var count := maxi(many, 1)
	var seat := clampi(which, 0, count - 1)
	var yard := yard_position()
	match _lesson:
		"line":
			# Follow the leader: a column facing the door, the smallest at the
			# back because that is where the smallest always ends up.
			var along := basis * Vector3(0, 0, 1)
			var across := basis * Vector3(1, 0, 0)
			return yard + along * (float(seat) * LINE_GAP) \
				+ across * (sin(float(seat) * 1.7) * 0.35)
		"huddle":
			# Round the teacher, close enough to be fussed over.
			var a := float(seat) * TAU / float(count) + _drift
			var r := 0.8 + fmod(float(seat) * 0.37, 1.0) * 1.1
			return yard + Vector3(cos(a), 0.0, sin(a)) * r
		"dance":
			var spin := _drift * DANCE_SPIN * 6.0
			var d := _ring_radius(count)
			var b := float(seat) * TAU / float(count) + spin
			return yard + Vector3(cos(b), 0.0, sin(b)) * d
		"horseshoe":
			# The ring with its mouth open toward the door, so every face is
			# turned the same way and there is a place to stand and be listened
			# to. Three quarters of a turn, not a whole one.
			var open := TAU * 0.75
			var step := open / float(maxi(count - 1, 1))
			var c := -open * 0.5 + float(seat) * step
			return yard + Vector3(sin(c), 0.0, -cos(c)) * _ring_radius(count)
	# "circle" — the plain story ring.
	var e := float(seat) * TAU / float(count) + _drift * 0.15
	return yard + Vector3(cos(e), 0.0, sin(e)) * _ring_radius(count)


## WHICH ONE OF THE CHILDREN THIS IS, in the village's own order. Stable for as
## long as the class is, which is all a formation needs — and asked once, on
## arriving, because a seat recomputed every frame is a child that swaps places
## with its neighbours forever.
## `child` is untyped on purpose. A Villager reaches its Edubba through its
## village, so naming Villager in this signature closes a circle — Edubba needs
## Villager needs Village needs Edubba — and Godot answers a circle by refusing
## to parse the class at all, which takes the whole village down with it.
func seat_of(child: Node) -> int:
	var seat := 0
	if village == null or not is_instance_valid(village):
		return seat
	for v in village.my_villagers():
		if v == child:
			return seat
		if not v.is_adult():
			seat += 1
	return seat


## A ring wide enough that everybody in it has room to sit.
func _ring_radius(count: int) -> float:
	return maxf(SEAT_GAP * float(count) / TAU, RING_LEAST)


## THE LESSON CHANGES. Long enough that a passer-by sees a class doing one
## thing rather than a crowd flickering between five.
func _process(delta: float) -> void:
	_drift += delta
	_left -= delta
	if _left > 0.0:
		return
	_left = randf_range(LESSON_LEAST, LESSON_MOST)
	var next := LESSONS[randi() % LESSONS.size()]
	if next == _lesson:
		next = LESSONS[(LESSONS.find(_lesson) + 1) % LESSONS.size()]
	_lesson = next


func hover_text() -> String:
	var n := 0
	if village != null and is_instance_valid(village):
		for v in village.my_villagers():
			if not v.is_adult():
				n += 1
	return "Edubba (school) — %d children learning" % n
