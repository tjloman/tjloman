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
## WHEN SCHOOL ENDS, and it is not when childhood does.
##
## It ended at ADULT_AGE, which is sixteen — so a village's young stood in the
## yard reciting their letters right up to the day they became adults, and the
## day after that they were hungry for the first time in their lives with no
## trade, no habit of working and no place at any post. They had spent every
## year they had standing about.
##
## Fourteen. Two years of working before hunger is ever a thing that happens to
## them, which is what an apprenticeship is for. They are still children in
## every other way the game means it -- they do not breed, they do not take up
## arms, they cannot starve, and a god who picks one up gets their mother.
const SCHOOL_UNTIL := 14.0

const LESSONS: Array[String] = [
	"circle", "horseshoe", "square", "line", "dance", "huddle"]
## WHICH OF THEM ARE SAT DOWN. A seated class does not drift, does not turn and
## does not spin: the children walk to their places once and then STAY there,
## which is what sitting looks like and is also the cheapest thing a crowd of
## seventy-seven can possibly be doing. Half the lessons are still on their feet
## — following, dancing, crowding the teacher — so a school still moves; it just
## does not move ALL the time.
const SEATED: Array[String] = ["circle", "horseshoe", "square"]
## ONE CLASS PER TEACHER. Seventy-seven children in a single follow-the-leader
## is not a school, it is a conga line across a village — and a school with
## three staff standing in one circle is three people doing one person's job.
## The roll is split between whoever is teaching, each class gets its own
## corner of the yard and its own lesson, and a passer-by sees a school.
const CLASSES_MOST := 3
## WHERE EACH CLASS STANDS: three fixed stations, not a computed ring — the
## yard at the door, and one along each side of the hall. A class should have a
## PLACE, so that the same teacher is found in the same corner and the school
## reads as a building with three things going on round it rather than as a
## crowd that happens to be near a door.
const STATIONS: Array[Vector3] = [
	Vector3(0.0, 0.0, 4.6),      # the yard, at the door
	Vector3(-5.4, 0.0, 0.4),     # along the west wall
	Vector3(5.4, 0.0, 0.4),      # along the east wall
]
const LESSON_LEAST := 14.0
const LESSON_MOST := 26.0
## How far apart the children stand in each. A ring's radius grows with the
## class so twenty children do not stand inside one another.
const SEAT_GAP := 1.25
const RING_LEAST := 2.0
const LINE_GAP := 1.4
## How fast a dance turns, in radians a second. Slow: they are small.
const DANCE_SPIN := 0.5


## WHAT IT TAKES TO PULL THIS DOWN BY FORCE, against a villager's hundred.
## A building is the thing that PROTECTS the villager, so it cannot be as easy
## to break as the villager is — a fireball that kills the family should not
## also flatten the house in the same instant, and a creature in a temper
## should have to work at it.
##
## Fire is charged as a fraction of this rather than as a flat number, so a
## stout building is stout against BLOWS and still burns to the ground in the
## same minute and a half as a hut. See Kindling.tick.
const MOST_HEALTH := 500.0

var village: Village
## How much of it is left, and whether it is alight. See Kindling.
var health := MOST_HEALTH
var kindling := Kindling.new()

## One per class, so the three of them are never doing the same thing at the
## same moment. Sized once, to CLASSES_MOST, and indexed by class.
var _lesson: Array[String] = []
var _left: Array[float] = []
## Turns slowly under the dance, and gives the other formations a little life
## so a class is never a diagram.
var _drift: Array[float] = []

## IS THE SCHOOL OPEN? It was never shut, so the children stood in the yard
## reciting their letters all night and the teachers stood over them doing it.
## Nobody had to decide to stay: a child's energy only ever goes UP (they gain
## four a second and spend none), so the night gate — which asks whether you
## are tired — was a question a child could never answer yes to, and school was
## what they did instead of everything, for ever.
static func in_session() -> bool:
	return not GameState.is_night()


## IS THIS ONE STILL OF AN AGE TO BE TAUGHT? The one place that answers it, so
## the school, the seating, the class sizes and the villager's own decision
## cannot come to different conclusions about who is a pupil.
static func schools(who: Villager) -> bool:
	return who.age < SCHOOL_UNTIL


func _ready() -> void:
	kindling.temper = Kindling.TEMPER_STONE   # mostly walls
	add_to_group("edubba")
	add_to_group(Affords.BURNABLE)
	add_to_group(WorldGen.SEATED)     # see WorldGen.reseat_over
	set_meta("seat_half", 2.5)
	for i in CLASSES_MOST:
		_lesson.append(LESSONS[randi() % LESSONS.size()])
		_left.append(randf_range(LESSON_LEAST, LESSON_MOST))
		_drift.append(randf() * TAU)
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
		# ON ITS FOOTING, whatever pivot the model was authored with — the
		# same answer, from the same place, that a beast is stood up with.
		# A model pivoted at its middle sinks to the waist without this,
		# which is what "buildings are spawning below ground" was.
		custom.position.y += ModelBank.footing("school")
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

	# AND THEN IT SITS DOWN ON THE GROUND THAT IS ACTUALLY DRAWN.
	#
	# This is the building it was found on: the town raised a school, the school
	# sank into the green, and the children gave up and walked back to the
	# totem. The placer settles a spot against `height_at`, which is the noise —
	# and the hillside you can see is a four-metre grid of samples off that
	# noise with flat triangles between them, so in a hollow the drawn ground
	# sits most of a metre ABOVE the number the school was given. See Footing.
	Footing.settle(self, get_tree().get_first_node_in_group("world_gen") as WorldGen)


## HOW MANY CLASSES ARE RUNNING — one per teacher actually standing in the
## yard, so an unstaffed school still gathers its children into one group
## rather than none. Reaches the village's own tally directly: it is the one
## number that says how many grown-ups are here to run a class, and wrapping it
## in another accessor would only move the same read.
func classes() -> int:
	if village == null or not is_instance_valid(village):
		return 1
	return clampi(village._teachers, 1, CLASSES_MOST)


## Where a given class gathers. One at the door; two or three spread around it,
## far enough apart that the rings do not overlap.
func yard_for(klass: int) -> Vector3:
	return global_position + basis * STATIONS[clampi(klass, 0, STATIONS.size() - 1)
		% STATIONS.size()]


## The middle of the class this child belongs to — what it turns to face.
func middle_for(which: int) -> Vector3:
	return yard_for(which % classes())


## The lesson under way for a class. Changes on its own clock — see `_process`.
func lesson(klass := 0) -> String:
	return _lesson[klass % _lesson.size()]


## WHERE THE i-TH CHILD OF `many` STANDS. Everything is worked out from the two
## numbers a child actually knows about itself: which one it is, and how many
## there are. No child needs to be told where any other one is.
func spot_for(which: int, many: int) -> Vector3:
	# DEALT ROUND LIKE CARDS. Taking every third child rather than the first
	# third keeps a class the same size as its neighbours whatever the roll is,
	# and keeps a child in the same class as the roll grows under it.
	var groups := classes()
	var klass := maxi(which, 0) % groups
	# WHOLE CHILDREN. Every division here is deliberately a floor: a class is a
	# count of people, and the remainder is handled by the modulo above rather
	# than lost. Said out loud because Godot cannot tell a rounding mistake from
	# an intended one, and an unexplained warning at startup is a warning nobody
	# reads.
	@warning_ignore("integer_division")
	var seat := maxi(which, 0) / groups
	@warning_ignore("integer_division")
	var count := maxi((maxi(many, 1) - klass + groups - 1) / groups, 1)
	seat = clampi(seat, 0, count - 1)
	var yard := yard_for(klass)
	var drift: float = _drift[klass]
	match _lesson[klass]:
		"line":
			# Follow the leader: a column facing the door, the smallest at the
			# back because that is where the smallest always ends up.
			var along := basis * Vector3(0, 0, 1)
			var across := basis * Vector3(1, 0, 0)
			return yard + along * (float(seat) * LINE_GAP) \
				+ across * (sin(float(seat) * 1.7) * 0.35)
		"huddle":
			# Round the teacher, close enough to be fussed over.
			var a := float(seat) * TAU / float(count) + drift
			var r := 0.8 + fmod(float(seat) * 0.37, 1.0) * 1.1
			return yard + Vector3(cos(a), 0.0, sin(a)) * r
		"dance":
			var spin := drift * DANCE_SPIN * 6.0
			var d := _ring_radius(count)
			var b := float(seat) * TAU / float(count) + spin
			return yard + Vector3(cos(b), 0.0, sin(b)) * d
		"square":
			# SAT ROUND FOUR SIDES, facing in. The sides fill evenly rather than
			# one at a time, so a class of nine is three, two, two and two and
			# not five and four and nobody.
			@warning_ignore("integer_division")
			var per := maxi((count + 3) / 4, 1)   # whole children, rounded up
			@warning_ignore("integer_division")
			var side := (seat / per) % 4
			var reach := maxf(SEAT_GAP * float(per) * 0.5, RING_LEAST)
			var out: Vector3 = [Vector3(0, 0, 1), Vector3(1, 0, 0),
				Vector3(0, 0, -1), Vector3(-1, 0, 0)][side]
			var run := Vector3(out.z, 0.0, -out.x)
			var along := (float(seat % per) + 0.5) / float(per) - 0.5
			return yard + basis * (out * reach + run * (along * reach * 2.0))
		"horseshoe":
			# The ring with its mouth open toward the door, so every face is
			# turned the same way and there is a place to stand and be listened
			# to. Three quarters of a turn, not a whole one.
			var open := TAU * 0.75
			var step := open / float(maxi(count - 1, 1))
			var c := -open * 0.5 + float(seat) * step
			return yard + Vector3(sin(c), 0.0, -cos(c)) * _ring_radius(count)
	# "circle" — the plain story ring, and it is one of the sat-down ones, so it
	# does not turn under them. A story circle that rotates is a carousel.
	var e := float(seat) * TAU / float(count)
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
		if schools(v):
			seat += 1
	return seat


## A ring wide enough that everybody in it has room to sit.
func _ring_radius(count: int) -> float:
	return maxf(SEAT_GAP * float(count) / TAU, RING_LEAST)


## THE LESSON CHANGES. Long enough that a passer-by sees a class doing one
## thing rather than a crowd flickering between five.
func _process(delta: float) -> void:
	Ledger.open(&"Edubba")
	_tick_fire(delta)
	for k in CLASSES_MOST:
		_drift[k] += delta
		_left[k] -= delta
		if _left[k] > 0.0:
			continue
		_left[k] = randf_range(LESSON_LEAST, LESSON_MOST)
		var next := LESSONS[randi() % LESSONS.size()]
		if next == _lesson[k]:
			next = LESSONS[(LESSONS.find(_lesson[k]) + 1) % LESSONS.size()]
		_lesson[k] = next


func hover_text() -> String:
	var n := 0
	if village != null and is_instance_valid(village):
		for v in village.my_villagers():
			if schools(v):
				n += 1
	var groups := classes()
	if n <= 0:
		return "Edubba (school) — empty"
	var doing := PackedStringArray()
	for k in groups:
		doing.append(lesson(k))
	return "Edubba (school) — %d children in %d %s (%s)" % [
		n, groups, "class" if groups == 1 else "classes", ", ".join(doing)]

## Fire ------------------------------------------------------------------------

## HEAT ON IT, from a fireball, a bolt, or the building next door. It catches
## only when it has had enough of it for what it is made of — see
## Kindling.warm, and Kindling's TEMPER_ table for why a granary takes longer
## than a hut.
func scorch(joules: float) -> void:
	kindling.warm(self, joules, 2.8)


## SET IT ALIGHT. Everything a village raises can burn now — see Kindling for
## why that had to change and what it costs a town.
func ignite() -> void:
	kindling.light(self, 2.8)


## Rain, a healing shower, or somebody with a bucket.
func extinguish() -> void:
	kindling.douse(self)


## Sudden harm — a fireball's core, a quake, a creature's boot.

## WHAT IT IS WORTH IN FULL, so a blow can be reckoned as a share of it. A
## METHOD and not the constant itself: Object.get() does not see constants, so
## anything asking `built.get("MOST_HEALTH")` gets null and quietly treats a
## granary as a hut. See Fireball._most_of.
func full_health() -> float:
	return MOST_HEALTH


func damage(amount: float) -> void:
	health -= amount
	# AND IT SHOWS. See RuinBar: a thing that can be hurt without looking
	# hurt is indistinguishable from a thing that cannot be hurt at all,
	# which is exactly what "the mill will not burn" sounds like from
	# the other side of the screen.
	RuinBar.over(self, health / MOST_HEALTH, 3.8, kindling.alight)
	if health <= 0.0:
		burn_down()


func _tick_fire(delta: float) -> void:
	# COOL OFF between blows: three fireballs in ten seconds is a fire,
	# three across an afternoon is three scorch marks. See Kindling.
	kindling.cool(delta)
	var harm := kindling.smoulder(self, delta, MOST_HEALTH)
	if harm > 0.0:
		damage(harm)


func burn_down() -> void:
	if village != null and is_instance_valid(village):
		village.edubba = null
	GameState.announce("The school burns down. The children scatter.")
	queue_free()


## ONE CHILD, ONE FRAME OF SCHOOL.
##
## Lives here rather than in Villager for two reasons: that file is permanently
## on its line cap, and where a child stands is the school's business — it is
## the only thing that knows what the class is doing.
##
## `child` is untyped for the same reason `seat_of` is: naming Villager in a
## signature here closes a parse circle that takes the whole village down.
func attend(child: Node, delta: float) -> void:
	var at: Vector3 = child.global_position
	var seat := spot_for(int(child._school_seat), maxi(village.child_count(), 1))
	var gap := Vector2(seat.x - at.x, seat.z - at.z)
	var klass := maxi(int(child._school_seat), 0) % classes()
	# DOWN ON THE DIRT once it is in its place, up again the moment the lesson
	# is one they do on their feet. See Villager.sit_down.
	var seated: bool = SEATED.has(_lesson[klass])
	child.sit_down(seated and gap.length() <= 0.5)
	if gap.length() > 0.5:
		# NO ROUTING IN A SCHOOL YARD. `_move_toward` runs the obstacle steer
		# and the shore probe for every body that uses it, every frame, and a
		# probe is terrain samples. Seventy-seven children shuffling round a
		# ring inside a village's own yard — on ground the village has already
		# built on, two metres from where they are going, with nothing in
		# between — need none of it. Straight at it instead.
		var pace: float = Villager.WALK_SPEED * child._speed_factor() * 0.8
		var step := gap.normalized() * pace * float(child._sim_scale)
		child.velocity.x = step.x
		child.velocity.z = step.y
		child.velocity.y -= Villager.GRAVITY * delta
		child.move_and_slide()
		child.look_at(at - Vector3(step.x, 0.0, step.y), Vector3.UP)
	elif seated and child.is_on_floor():
		# SAT DOWN, AND THEREFORE DOING NOTHING. `_apply_gravity_only` ends in a
		# move_and_slide, which is a physics query per body per frame — the last
		# thing a school of seventy-seven was still paying for once the routing
		# went. A child sitting on the ground in a ring is not falling and is
		# not walking, so it does not need to be asked.
		child.velocity = Vector3.ZERO
		_face_the_middle(child, at)
	else:
		child._apply_gravity_only(delta)
		# Facing the middle of its OWN class — a ring of backs is not a class.
		# Bodies are modelled facing +Z and look_at aims -Z, so this looks at
		# the point opposite, the same way _move_toward does.
		_face_the_middle(child, at)
	child.social = minf(float(child.social) + 3.0 * delta, 100.0)
	child.happiness = minf(float(child.happiness) + 0.5 * delta, 100.0)


## Turned toward its own class, wherever that class is standing. Bodies are
## modelled facing +Z and look_at aims -Z, so this looks at the point opposite.
func _face_the_middle(child: Node, at: Vector3) -> void:
	var mid := middle_for(int(child._school_seat))
	var away := at - Vector3(mid.x, 0.0, mid.z)
	if Vector2(away.x, away.z).length() > 0.05:
		child.look_at(at + Vector3(away.x, 0.0, away.z), Vector3.UP)
