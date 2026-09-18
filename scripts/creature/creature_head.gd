class_name CreatureHead
extends RefCounted
## THE HEAD IS NOT THE HANDS.
##
## Everything the creature did, it did with its whole body. "Looking at" a thing
## meant pivoting fifteen metres of animal to point at it (`Creature._face`
## turns `rotation.y` and nothing else exists), and "watching" was a STATE —
## which meant being watchful competed on the ballot with carrying, casting and
## eating, and lost to all of them. A beast hauling a tree to the granary could
## not glance at you. A beast holding three villagers in the air could not look
## at the villagers.
##
## So it has a neck now, and a voice, and both run on their own clocks whatever
## the hands are busy with. That is the whole of this file:
##
##   IT LOOKS. The head turns to whatever most deserves it — your hand above
##   all, then whatever just hurt or startled it, then its own work, then the
##   nearest living thing, then whatever the village has stopped to stare at —
##   clamped to a real neck and eased, so it reads as attention rather than as
##   a turret. The body carries on doing exactly what it was doing.
##
##   AND WHAT IT LOOKS AT IS WHAT IT LEARNS FROM. The gaze is not decoration:
##   CreatureWatching reads `subject`, so a creature that is looking AT somebody
##   attends to them particularly, rather than averaging everything within
##   sixteen metres the way it used to. Being watchful and being taught are the
##   same act now, which is what they always should have been.
##
##   IT SOUNDS. A roar of its own — see SoundBank._make_roar — pitched by how
##   big it has grown and sounded by whatever its heart is holding. A furious
##   creature roars while it carries. A frightened one calls out while it runs.
##   None of it interrupts anything, because a voice is not a deed.

## How far a neck actually goes, in radians, and how fast it gets there. Past
## the yaw limit it simply stops: the head has turned as far as a head turns,
## and if you want it to look behind itself the BODY has to come round.
const NECK_YAW := 1.35
const NECK_PITCH := 0.55
const TURN := 3.6

## How far off a thing can be and still be worth a look, and the longer reach
## for the one thing it always wants to keep an eye on.
const LOOK_WITHIN := 34.0
const HAND_WATCH := 55.0
## Where a hand merely BEING there settles the attention stat, and how fast it
## is drawn to that level. A LEVEL, NOT A CEILING — pulled toward from either
## side, so a creature that was ignoring you looks up, and one that was rapt
## goes back to its own business. See the ATTENTION section at the foot.
const HAND_CALM := 50.0
const HAND_PULL := 12.0
## How far off a DEED of yours still takes the whole of it. Wider than the reach
## a merely present hand works at, because a thunderclap carries further than a
## palm does. See `startled`.
const STARTLE_WITHIN := 60.0
## How long it holds a subject before considering another. Without this the head
## snaps between two villagers standing near each other, forever.
const HOLD_LOOK := 1.7

## THE VOICE. How often it may sound at all, how strongly the heart must be
## holding something before it does, and what size does to the pitch: a whelp is
## half again as high as the waveform, a full-grown beast is well under it.
const VOICE_LEAST := 8.0
const VOICE_MOST := 26.0
const SPEAKS := 0.34
const PITCH_WHELP := 1.55
const PITCH_GIANT := 0.6
## Which feelings have something to say, and how loud. Anything not here is felt
## in silence, which is most of them — a creature that voiced every passing mood
## would be unbearable within a minute.
const SAYS := {

	"fury": {"loud": 4.0, "pitch": 0.92},
	"dread": {"loud": -2.0, "pitch": 1.18},
	"pain": {"loud": 1.0, "pitch": 1.1},
	"delight": {"loud": -1.0, "pitch": 1.06},
	"pride": {"loud": 0.0, "pitch": 0.98},
	"grief": {"loud": -5.0, "pitch": 0.88},
	"loneliness": {"loud": -7.0, "pitch": 1.02},
}


## What the head is on, and where it is pointing. Both public: CreatureWatching
## reads the first, and anything that wants to know where the beast is actually
## looking reads the second.
var subject: Node3D = null
var at := Vector3.INF

var _yaw := 0.0
var _pitch := 0.0
var _choose_in := 0.0
var _voice_in := 0.0


## EVERY FRAME, WHATEVER THE HANDS ARE DOING. Called from the creature's own
## tick rather than from any state, which is the entire point.
func aim(who: Creature, delta: float) -> void:
	# A SLEEPING CREATURE DOES NOT LOOK AT THINGS. The head runs on every tick
	# of every state on purpose — being watchful is not a thing it stops to do
	# — but "every state" quietly included the one state where it has its eyes
	# shut, so a beast lying on its side in its bed went on tracking villagers
	# across the meadow all night. It keeps whatever it was looking at, so it
	# wakes facing what it dozed off at rather than snapping to centre.
	if who.state == Creature.State.SLEEPING:
		return
	_choose_in -= delta
	if _choose_in <= 0.0 or not _still_worth_it(who):
		_choose_in = HOLD_LOOK
		_pick(who)
	_turn(who, delta)
	_speak(who, delta)


## MADE TO LOOK. Not a preference and not a subject it chose: the head goes to
## this spot now and stays on it for `seconds`, which is what a creature tied up
## in front of its god is doing whether it likes it or not. Without the hold
## `_pick` has it back on your hand or a passing sheep within HOLD_LOOK, and the
## whole of being SHOWN something is that you do not get to look away.
func look_here(where: Vector3, seconds := HOLD_LOOK) -> void:
	subject = null
	at = where
	_choose_in = maxf(_choose_in, seconds)


## Has what it was looking at gone, died, or wandered out of range?
func _still_worth_it(who: Creature) -> bool:
	if subject == null:
		return at != Vector3.INF
	if not is_instance_valid(subject) or subject.is_queued_for_deletion():
		return false
	return subject.global_position.distance_to(who.global_position) < HAND_WATCH


## WHAT DESERVES THE HEAD. In order, and the order is the character of the
## thing: it watches its god before it watches its work, and its work before it
## watches the neighbours.
func _pick(who: Creature) -> void:
	subject = null
	at = Vector3.INF
	# 1. YOUR HAND. A creature raised well spends its life half-watching you,
	#    and this is where that actually happens — no state, no decision, no
	#    interruption to whatever it is carrying.
	var hand := who.divine_hand
	if hand != null and is_instance_valid(hand) \
			and hand.global_position.distance_to(who.global_position) < HAND_WATCH:
		# Unless it has stopped taking its cues from you altogether.
		if who.trust > 12.0 or who.fear > 40.0:
			subject = hand
			return
	# 2. WHATEVER IT IS HOLDING OR ABOUT TO THROW. It looks at its own work.
	var work := who.held_thing()
	if work != null:
		subject = work
		return
	# 3. WHOEVER IT HAS BEEN ATTENDING TO — the villager it went to soothe, the
	#    one it is watching learn.
	if who.watch_subject() != null:
		subject = who.watch_subject()
		return
	# 4. THE NEAREST LIVING THING worth the trouble.
	var near := _nearest_alive(who)
	if near != null:
		subject = near
		return
	# 5. WHATEVER THE TOWN HAS STOPPED TO STARE AT. A creature standing in a
	#    village whose people are all looking one way looks that way too, which
	#    costs nothing and is the oldest trick there is.
	var town := CreatureEyes.home_village(who.get_tree())
	if town != null and is_instance_valid(town):
		var focus: Vector3 = town.hive.looking_at()
		if focus != Vector3.INF \
				and focus.distance_to(who.global_position) < LOOK_WITHIN * 2.0:
			at = focus


func _nearest_alive(who: Creature) -> Node3D:
	var best: Node3D = null
	var best_d := LOOK_WITHIN
	for group in ["villagers", "animals"]:
		for n in who.get_tree().get_nodes_in_group(group):
			var node := n as Node3D
			if not is_instance_valid(node) or node == who:
				continue
			var d := node.global_position.distance_to(who.global_position)
			if d < best_d:
				best_d = d
				best = node
	return best


## TURN THE NECK, not the animal. Yaw is measured against whichever way the body
## happens to be facing, so the head keeps its subject through a walk, a turn
## and a throw — and gives up when the subject goes behind it, as a head does.
func _turn(who: Creature, delta: float) -> void:
	var head := who.head_node()
	if head == null:
		return
	var want_yaw := 0.0
	var want_pitch := 0.0
	var spot := at
	if subject != null and is_instance_valid(subject):
		spot = subject.global_position
	if spot != Vector3.INF:
		var eyes := who.global_position + Vector3.UP * (2.1 * who.scale.y)
		var to := spot - eyes
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > 0.2:
			want_yaw = wrapf(atan2(flat.x, flat.z) - who.rotation.y, -PI, PI)
			want_pitch = atan2(to.y, flat.length())
		# Past the neck's reach it simply does not get there.
		want_yaw = clampf(want_yaw, -NECK_YAW, NECK_YAW)
		want_pitch = clampf(want_pitch, -NECK_PITCH, NECK_PITCH)
	var step := TURN * delta
	_yaw = move_toward(_yaw, want_yaw, step)
	_pitch = move_toward(_pitch, want_pitch, step)
	head.rotation.y = _yaw
	head.rotation.x = -_pitch


## THE VOICE, on its own clock. It does not interrupt anything and cannot be
## interrupted: a voice is not a deed.
func _speak(who: Creature, delta: float) -> void:
	_voice_in -= delta
	if _voice_in > 0.0:
		return
	_voice_in = randf_range(VOICE_LEAST, VOICE_MOST)
	var felt := who.heart.strongest()
	if felt == "" or not SAYS.has(felt):
		return
	if who.heart.intensity() < SPEAKS:
		return
	sound(who, felt, 0.0)


## SOUND OFF, deliberately — for a deed that ought to be heard whether or not
## the heart happened to be holding anything at that moment. `extra` is decibels
## on top of what the feeling is worth.
func sound(who: Creature, felt: String, extra := 0.0) -> void:
	var row: Dictionary = SAYS.get(felt, {"loud": 0.0, "pitch": 1.0})
	# HOW BIG IT IS, in its own voice. One waveform, and the whole growth arc of
	# the creature audible in it.
	var size := lerpf(PITCH_WHELP, PITCH_GIANT, clampf(who.growth, 0.0, 1.0))
	SoundBank.play_at("roar", who.global_position,
		float(row["loud"]) + extra, 0.09, size * float(row["pitch"]))
	_voice_in = maxf(_voice_in, VOICE_LEAST)


## ATTENTION ------------------------------------------------------------------
##
## HOW CLOSELY IT IS WATCHING YOU, which is a different question from where its
## head is pointed and lives here for the same reason the head does: it was
## competing with the creature's whole life and beating it.
##
## A HAND NEARBY USED TO PIN IT AT 100. The old rule added twelve a second up to
## a ceiling of a hundred for as long as the hand was in reach, so a creature
## with its god standing over it dropped whatever it was doing and watched —
## for the whole session. That is not a companion, it is a dog staring at a
## treat, and it is most of why the beast never got on with anything while
## anybody was looking.
##
## So a hand being THERE settles it at half; a hand DOING something takes all of
## it. Presence is scenery, and an event is an event.

## The hand is within reach. Settle toward watchfulness, from whichever side.
static func watching(who: Creature, delta: float) -> void:
	who.attention = move_toward(who.attention, HAND_CALM, HAND_PULL * delta)


## SOMETHING JUST HAPPENED AND IT IS WATCHING YOU NOW. A miracle conjured, a
## miracle landing, a thing hurled. Straight to the top rather than a ramp,
## because catching a thrown object needs attention over 35 on the very next
## frame and a ramp would miss it — and because the whole point of an event is
## that it interrupts.
##
## `where` is not optional on purpose: a wonder on the far side of the map is
## not an event in this creature's life, and every caller knows where its own
## deed happened.
static func startled(who: Creature, where: Vector3) -> void:
	if not is_instance_valid(who):
		return
	if where.distance_to(who.global_position) > STARTLE_WITHIN:
		return
	who.attention = 100.0
