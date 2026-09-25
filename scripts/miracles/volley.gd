class_name Volley
## MORE THAN ONE OF THE SAME THING, LEAVING YOUR HAND AT ONCE.
##
## The sky sigil does not name a thing — it names a COUNT (see Spellbook, which
## is where a drawing turns into a number). What that count means has to live
## somewhere, and it cannot live in the fireball, because the player wanted it
## for tornadoes and for food as much as for fire.
##
## So it lives on the BODY, as a mark, and it is spent at the moment of the
## throw: one working is conjured into the grip, and when the hand opens, the
## rest of the volley is born alongside it already moving. Nothing is simulated
## until it is thrown, which is the whole reason it is done this way round —
## seven fireballs orbiting the hand while the player picks a target is seven
## physics bodies and seven lights doing nothing but waiting.
##
## WHAT CAN VOLLEY: anything that can make another of itself. That is the whole
## test — `another()` — so a fireball and a miracle orb come through here
## without this file knowing either of their names, and a thrown cow does not
## quietly become seven cows.

## The mark, and where the count is kept.
const MARK := "volley"

## HOW WIDE THE FAN OPENS. Degrees between one projectile and the next, off the
## line you actually aimed — and a ceiling on the whole spread, so a volley of
## seven is a wall of fire rather than a circle round the player. At 9 degrees
## a throw landing forty metres out puts its neighbours about six metres apart,
## which is a spread you can walk between and not one you can dodge.
const SPREAD_DEG := 9.0
const SPREAD_MOST := 34.0

## And a little depth, so a volley does not land along one neat arc: each rank
## out from the middle is thrown a shade harder or softer than the last.
const SPEED_SPREAD := 0.07

## How far apart they are born, as a multiple of how wide the thing IS. Two
## spheres spawned inside one another shove each other apart at whatever speed
## the solver decides on, which reads as the volley exploding in the player's
## face — and the greatest gout is nearly twice the width of the smallest, so a
## fixed gap that clears one would not clear the other. See Util.bulk_of.
const APART := 2.4
## And a floor under it, for anything that reports no shape at all.
const APART_LEAST := 1.0


## How many of this there are. One, unless something said otherwise.
static func count(what_given: Variant) -> int:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(what_given):
		return 1
	var what := what_given as Node
	if what == null or not is_instance_valid(what) or not what.has_meta(MARK):
		return 1
	return maxi(1, int(what.get_meta(MARK)))


## Say how many. Clamped to what the grammar allows, here rather than at each
## of the two call sites, because a volley of forty is a volley of forty
## whether it was drawn or caught.
static func mark(what_given: Variant, many: int) -> void:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(what_given):
		return
	var what := what_given as Node
	if what == null or not is_instance_valid(what):
		return
	what.set_meta(MARK, clampi(many, 1, Spellbook.VOLLEY_MOST))


## THE HAND OPENS AND THEY ALL GO. `first` is the one that was actually in the
## grip, already released and already moving at `vel`; this makes the rest and
## throws them alongside it. Returns the twins, for the tests.
##
## The mark is SPENT here — the first is set back to one — so a volley fans
## exactly once. A ball caught out of the air and thrown again fans whatever it
## was marked with at the catch, and never the same volley twice.
static func fan(first_given: Variant, vel: Vector3) -> Array:
	# Untyped until proved alive: a freed object handed to a typed parameter
	# is the error, raised before any check below could run. Gone is null.
	var first: Node3D = (first_given as Node3D) if is_instance_valid(first_given) else null
	var many := count(first)
	if many < 2 or not is_instance_valid(first) or not first.has_method("another"):
		return []
	var where := first.get_parent()
	if where == null or vel.length() < 0.01:
		return []
	first.set_meta(MARK, 1)
	var side := vel.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	# The fan tightens as it widens: SPREAD_DEG between neighbours until the
	# whole spread would pass SPREAD_MOST, and from there it is shared out.
	var step := minf(SPREAD_DEG, SPREAD_MOST / float(many - 1))
	var gap := maxf(APART_LEAST, Util.bulk_of(first) * APART)
	var made := []
	for i in range(1, many):
		var twin := first.call("another") as Node3D
		if twin == null:
			continue
		# LEFT, RIGHT, FURTHER LEFT, FURTHER RIGHT — so the volley grows out
		# from the shot the player actually took, and the one they aimed is
		# always the one in the middle.
		# Integer division ON PURPOSE: 1,2,3,4 become ranks 1,1,2,2 — which is
		# what "one out on each side, then two out on each side" means.
		@warning_ignore("integer_division")
		var rank := (i + 1) / 2
		var lean := float(rank) * (-1.0 if i % 2 == 1 else 1.0)
		where.add_child(twin)
		twin.global_position = first.global_position + side * (gap * lean)
		var away := vel.rotated(Vector3.UP, deg_to_rad(step * lean)) \
			* (1.0 + SPEED_SPREAD * lean)
		_hurl(twin, first, away)
		made.append(twin)
	return made


## Send one twin on its way exactly as the hand sent the first: the god's mark
## on it, the loft it was thrown with, and a Blow watching where it lands.
static func _hurl(twin: Node3D, first: Node3D, away: Vector3) -> void:
	twin.set_meta("hurled_by_god", true)
	var rb := twin as RigidBody3D
	if rb == null:
		if twin.has_method("drop"):
			twin.call("drop", away, false)
		return
	# THE SAME ARC. `Sling.loft` is stamped on the held body before the release,
	# and a twin born after it would otherwise fall twice as fast as the ball
	# beside it — which looks less like a volley than like a fault.
	if first.has_meta("loft_until"):
		rb.set_meta("loft_until", first.get_meta("loft_until"))
	rb.freeze = false
	rb.linear_velocity = away
	Blow.ride(rb, true)
