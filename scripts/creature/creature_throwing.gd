class_name CreatureThrowing
extends RefCounted
## THE ARM, AND WHAT A LIFETIME OF USING IT COMES TO.
##
## Throwing was one function: a random direction, a random speed between
## fourteen and twenty-two, and a lesson that the creature was getting better at
## something with nothing on the other end of the getting better. A beast that
## had thrown ten thousand things threw them exactly as badly as a hatchling,
## only heavier.
##
## So there is a LADDER now, and every rung is visible from outside:
##
##   0-1  A HEAVE. It picks the thing up and gets rid of it. Where it goes is
##        not a question the creature is asking.
##   2    THE LOB. A slow high arc, AIMED — which is the rung that turns
##        vandalism into provision, because an arc can be aimed at a granary.
##   3    THE FASTBALL. Flat, hard and quick. It gives up range for arrival:
##        the same arm sends it about half as far and it gets there like a
##        thrown rock, which is the difference between putting something
##        somewhere and hitting something with it.
##   4    JUGGLING — see below.
##   6    Three in the air. And, for a creature that has grown monstrous, fire.
##   8    Four.
##
## HOW FAR, at every rung, is size times strength times practice: a hatchling
## can put a chicken about five metres, and a full-grown beast with a lifetime
## of practice behind it can throw an ox across a valley. Two of those three
## terms are things the player grows deliberately — hauling builds strength
## (CreatureBody.exert), throwing builds the knack — and that is the whole
## reason the arm is worth having as a skill rather than a constant.
##
## JUGGLING IS PLAY, AND IT IS NOT A GOOD OR AN EVIL THING. Two sheep, three
## villagers, a sapling and a pig — anything the claws can close on goes up. The
## village stops and watches, and belief comes of it whoever is doing it,
## because a thing throwing men at the sky and catching them is a thing nobody
## in that village is going to stop talking about.
##
## WHAT IT DOES AT THE END is where its character finally shows, and only there:
##
##   A KIND ONE sets them down — or, if it has the arm and the granary is in
##   sight, finishes with a jump shot and puts the last one in the storehouse.
##   THE MIDDLE simply drops them and wanders off.
##   A CRUEL ONE eats one and throws the rest away. A MONSTROUS one was never
##   juggling sheep; it was juggling fire, over a village, for the look on
##   their faces.
##
## And if it is interrupted — frightened, struck, called away — everything in
## the air comes down. That is not a penalty bolted on. It is what happens when
## somebody juggling people stops juggling.

## THE RUNGS, in skill levels (Creature minds count 0..9 — see MindSKILL_CAP).
const LOB_AT := 2
const PITCH_AT := 3
const JUGGLE_AT := 4
const THREE_AT := 6
const FOUR_AT := 8
## And the rung fire needs, for a creature cruel enough to want it.
const FIRE_AT := 6
const FIRE_HEART := -40.0

## HOW FAR IT CAN SEND SOMETHING. Base metres, times what the body is (arm from
## size, thew from strength) and what the life has taught (the knack).
const BASE_REACH := 14.0
const ARM_LEAST := 0.6
const ARM_GROWTH := 1.4
const THEW_LEAST := 0.5
const THEW_MIGHT := 1.0

## The pull on a loose body, which is the ENGINE's, not the creature's GRAVITY.
## Everything it throws lands by the world's rules; getting this wrong is the
## difference between a shot that lands and one that always falls short.
const LOB_GRAVITY := 9.8
## Launch angles. Forty-five carries furthest; the fastball trades that away for
## a flat, fast line, which is why the same arm pitches barely half as far.
const LOB_ANGLE := 0.7854          # 45 degrees
const PITCH_ANGLE := 0.3142        # 18 degrees
const HEAVE_SHARE := 0.4           # what an untaught heave manages, of the reach
const OVER := 1.06                 # aim a touch long: platforms stand off the ground
const WOBBLE := 0.26               # the cone of what it has not learned yet

## THE CASCADE. One item's whole flight, and how high above the hands it goes.
const CYCLE := 1.15
const APEX := 3.2
const APEX_GROWTH := 1.6
## How long a show runs before it finishes of its own accord, and how often the
## watching village is impressed all over again while it does.
## SHOW_MOST plus GATHER_PATIENCE must stay UNDER Creature.STUCK_SECONDS, or
## the watchdog trips mid-cascade and every long juggle ends in a dropped
## villager — which would look exactly like a bug and read exactly like one.
const SHOW_LEAST := 11.0
const SHOW_MOST := 17.0
const SHOW_EVERY := 4.0
const SHOW_PAY := 2.6
## How far it will walk to collect the next thing to throw, and how near it has
## to be to scoop it.
const GATHER_WITHIN := 20.0
const SCOOP := 2.2
## A juggle that cannot be assembled inside this is abandoned rather than
## chased forever — things wander off, and a creature standing in a field
## failing to catch a fourth sheep is not a show.
const GATHER_PATIENCE := 10.0


## The cascade, while there is one.
var aloft: Array[Node3D] = []
var fire := false

var _phase := 0.0
var _left := 0.0
var _since_pay := 0.0
var _gathering := 0.0
var _want := 0
## WHAT IT IS WALKING TOWARD. Held between frames on purpose: finding it means
## scanning six groups, and doing that every frame while a giant crosses a field
## is the kind of cost that only shows up when there are forty creatures.
var _scooping: Node3D = null


## WHAT IT CAN DO, as a number a player is shown.
static func level(who: Creature) -> int:
	return who.mind.skill_level("throw")


## HOW FAR, in metres, at full stretch. Size, strength and practice, multiplied
## — so the arm is a thing the player GREW, by feeding it, working it and
## playing catch with it, rather than a constant with the creature's name on it.
static func reach(who: Creature) -> float:
	var arm := ARM_LEAST + who.growth * ARM_GROWTH
	var thew := THEW_LEAST + who.body.might() / 100.0 * THEW_MIGHT
	var taught := 1.0 + who.mind.knack("throw") * Creature.THROW_MASTERY
	return BASE_REACH * arm * thew * taught


## Which throw this creature has in it. A beast that knows the fastball still
## lobs when a lob is what the shot wants; this is only the ceiling.
static func best_style(who: Creature) -> String:
	var rung := level(who)
	if rung >= PITCH_AT:
		return "pitch"
	if rung >= LOB_AT:
		return "lob"
	return "heave"


## THE VELOCITY THAT PUTS IT THERE. A ballistic arc carries v^2*sin(2a)/g, so
## the speed for a wanted distance falls straight out of the angle — which is
## also why the flat throw gives up range: sin(36 degrees) is a little over half
## of sin(90).
##
## Returns ZERO when the shot is beyond the arm, so a caller can ask "could I?"
## by asking for the throw and getting nothing back.
static func arc_to(who: Creature, spot: Vector3, style: String) -> Vector3:
	var to := spot - who.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var d := flat.length()
	if d < 0.5:
		return Vector3.ZERO
	var angle := PITCH_ANGLE if style == "pitch" else LOB_ANGLE
	var carry := reach(who) * sin(2.0 * angle)
	if d > carry:
		return Vector3.ZERO     # beyond the arm; it knows better than to try
	var speed := sqrt(d * LOB_GRAVITY / sin(2.0 * angle)) * OVER
	var aim := flat.normalized() * cos(angle) + Vector3.UP * sin(angle)
	# What it has not learned yet, as a cone that closes with practice.
	var slop := (1.0 - who.mind.knack("throw")) * WOBBLE
	aim += Vector3(randf_range(-slop, slop), randf_range(-slop, slop) * 0.5,
		randf_range(-slop, slop))
	return aim.normalized() * speed


## NO AIM AT ALL — the throw of a creature that has not learned there is
## anything to aim at.
static func heave(who: Creature) -> Vector3:
	var dir := Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)).normalized()
	return dir * maxf(reach(who) * HEAVE_SHARE, 8.0)


## LET GO OF IT. Rigid bodies take a velocity; animals, people and trees have
## their own falling to do and are told to drop.
static func send(thing: Node3D, v: Vector3, gently := false) -> void:
	if thing == null or not is_instance_valid(thing):
		return
	# NOT A CHILD, NOT EVER, and the creature's hand is no different from the
	# god's. Every way this beast lets go of anything comes through here, so
	# one line covers the heave, the aimed shot, the juggle and the fumble
	# alike. They go down on their feet. See ChildSafety.
	if ChildSafety.throw_answer(thing) != "":
		v = Vector3.ZERO
		gently = true
	if thing is RigidBody3D:
		(thing as RigidBody3D).freeze = false
		(thing as RigidBody3D).linear_velocity = v
	elif thing.has_method("drop"):
		thing.call("drop", v, gently)


## THE SHOT AT THE GRANARY, or ZERO if it is not going to try. Only the things
## a storehouse actually takes — throwing a villager at the barn is not
## provision — and only from a beast that has the rung for an aimed throw at
## all. What makes it a LEARNED behaviour is the roll: a quarter of the time
## cold, nearly always once the knack is grown.
static func at_the_larder(who: Creature, thing: Node3D) -> Vector3:
	if not (thing is FoodItem or thing is ResourceItem or thing is WildTree):
		return Vector3.ZERO
	if level(who) < LOB_AT:
		return Vector3.ZERO
	var store := CreatureEyes.nearest_store(who.get_tree(), who.global_position)
	if store == null:
		return Vector3.ZERO
	if randf() > 0.25 + who.mind.knack("larder") * 0.7:
		return Vector3.ZERO
	var shot := arc_to(who, store.global_position, "lob")
	if shot != Vector3.ZERO:
		thing.set_meta("hurled_by_creature", true)
		who.mind.practise("throw", true)
	return shot


## How many it can keep up at once, or nought if it cannot juggle at all.
static func hands(who: Creature) -> int:
	var rung := level(who)
	if rung >= FOUR_AT:
		return 4
	if rung >= THREE_AT:
		return 3
	if rung >= JUGGLE_AT:
		return 2
	return 0


## Would this one juggle FIRE? Only a beast with the rung for it and a heart
## dark enough to want it — and then it needs nothing to throw but itself.
static func would_juggle_fire(who: Creature) -> bool:
	return level(who) >= FIRE_AT and who.morality <= FIRE_HEART


## THE BALLOT ENTRY. Offered when the arm is there and there is either enough
## lying about to make a show of, or a temper that supplies its own.
static func offer(who: Creature, opts: Dictionary) -> void:
	if hands(who) == 0 or who.throwing.busy():
		return
	if would_juggle_fire(who):
		who.offer_option(opts, "juggle", "fire", null)
		return
	var found := _liftable_near(who, hands(who))
	if found.size() >= hands(who):
		who.offer_option(opts, "juggle", who._type_of(found[0]), found[0])


static func _liftable_near(who: Creature, want: int) -> Array:
	var found := []
	for node in who._things_around(GATHER_WITHIN):
		if node is House or node is RockDeposit:
			continue
		if not who.can_lift(node, true):
			continue
		found.append(node)
		if found.size() >= want:
			break
	return found


func busy() -> bool:
	return not aloft.is_empty() or _gathering > 0.0


## START ONE. Nothing goes up yet: it has to collect them first, and watching a
## giant walk round a field picking up sheep one at a time is half the show.
func begin(who: Creature) -> void:
	spill(who)
	fire = CreatureThrowing.would_juggle_fire(who)
	_want = CreatureThrowing.hands(who)
	_phase = 0.0
	_since_pay = 0.0
	_left = randf_range(SHOW_LEAST, SHOW_MOST)
	_gathering = GATHER_PATIENCE
	who.state = Creature.State.JUGGLE


## Runs every physics frame while the creature is juggling.
func tick(who: Creature, delta: float) -> void:
	_forget_the_lost()
	if aloft.size() < _want and _gathering > 0.0:
		_collect(who, delta)
		return
	if aloft.size() < 2:
		# It never got a second one in hand. Not a show; put it down and go.
		spill(who, true)
		who._finish_choice(-0.2)
		return
	who._apply_gravity_only(delta)
	_gathering = 0.0
	_phase = fmod(_phase + delta / CYCLE, 1.0)
	_carry_the_arc(who)
	_left -= delta
	_since_pay += delta
	if _since_pay >= SHOW_EVERY:
		_since_pay = 0.0
		_impress(who)
	if _left <= 0.0:
		finish(who)


## WALK OVER AND SCOOP THE NEXT ONE UP. Fire needs no collecting — it makes its
## own, out of nothing, which is exactly why a monstrous creature prefers it.
func _collect(who: Creature, delta: float) -> void:
	_gathering -= delta
	if fire:
		aloft.append(_conjure(who))
		return
	if _scooping == null or not is_instance_valid(_scooping) \
			or _scooping.is_queued_for_deletion() or aloft.has(_scooping):
		_scooping = _next_to_scoop(who)
	var next := _scooping
	if next == null:
		_gathering = 0.0
		return
	if who.global_position.distance_to(next.global_position) > SCOOP + who.scale.x:
		who._move_toward(next.global_position, who._run_speed(), delta)
		# WHAT IT ALREADY HAS RIDES ALONG. Without this the first sheep stands
		# frozen in the grass, mid-air, while the giant walks off to get the
		# second one.
		_carry_the_arc(who)
		return
	if next is RigidBody3D:
		(next as RigidBody3D).freeze = true
	elif next.has_method("pick_up"):
		next.call("pick_up")
	aloft.append(next)
	_scooping = null


func _next_to_scoop(who: Creature) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for node in who._things_around(GATHER_WITHIN):
		if node is House or node is RockDeposit or aloft.has(node):
			continue
		if not who.can_lift(node, true):
			continue
		var d := who.global_position.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best


## A GOUT OUT OF NOTHING. The cheap fire — the one that skids and gutters
## rather than cratering — because the point of this is the sight of it.
func _conjure(who: Creature) -> Node3D:
	var flame := Fireball.new()
	flame.kind = "fireball"
	flame.freeze = true
	who.get_parent().add_child(flame)
	flame.global_position = who.global_position + Vector3.UP * (1.5 * who.scale.y)
	who.heart.stir("fury", 0.12)
	return flame


## WHERE EVERYTHING IS THIS FRAME. Each one rides the same arch a third of a
## turn behind the last: up out of one hand, over, and down into the other.
func _carry_the_arc(who: Creature) -> void:
	var many := aloft.size()
	var hands_at := who.global_position + Vector3.UP * (1.3 * who.scale.y)
	var across := who.global_transform.basis.x * (0.7 * who.scale.x + 0.5)
	var apex := (APEX + who.growth * APEX_GROWTH * 6.0) \
		* (0.6 + who.mind.knack("throw") * 0.8)
	for i in many:
		var thing := aloft[i] as Node3D
		if thing == null or not is_instance_valid(thing):
			continue
		var p := fmod(_phase + float(i) / float(many), 1.0)
		var spot := hands_at + across * (1.0 - 2.0 * p)
		spot.y += apex * sin(PI * p)
		thing.global_position = spot


## THE VILLAGE STOPS AND LOOKS. Belief either way: a creature throwing sheep at
## the sky is a wonder, a creature throwing FIRE over the rooftops is not, and
## both of them are proof that something enormous is up there.
func _impress(who: Creature) -> void:
	who.mind.practise("throw", true)
	who.boredom = maxf(who.boredom - 8.0, 0.0)
	who.heart.stir("delight" if not fire else "fury", 0.18)
	var count := aloft.size()
	VillageWonder.spectacle(who.get_tree(), "juggle_fire" if fire else "juggle",
		"horror" if fire else "wonder", who.global_position,
		SHOW_PAY * float(count) * (1.4 if fire else 1.0),
		"Your creature is juggling %s over the village." % _cargo_word(count), who)


func _cargo_word(count: int) -> String:
	if fire:
		return "%d gouts of fire" % count
	if aloft.is_empty() or not is_instance_valid(aloft[0]):
		return "%d things" % count
	return "%d %ss" % [count, CreatureEyes.kind_of(aloft[0])]


## HOW IT ENDS, and the only part of this that its character has any say in.
func finish(who: Creature) -> void:
	var held := aloft.duplicate()
	aloft.clear()
	_gathering = 0.0
	var kindly := who.morality >= 20.0
	var cruel := who.morality <= -20.0
	who.mind.practise("throw", true)
	# Juggling itself is play: daring, companionable, and a little disorderly.
	# Nothing in it is kind or cruel — see CreatureEthos.MEANING.
	who.mind.shape({"daring": 0.45, "fellowship": 0.4, "order": -0.15})
	who.morality = who.mind.temperament
	who._last_deed = "juggle"
	if fire:
		_scatter_the_fire(who, held)
		who._finish_choice(0.9)
		return
	if kindly:
		_set_down_well(who, held)
		who._finish_choice(1.4)
		return
	if not cruel:
		for thing in held:
			CreatureThrowing.send(thing, Vector3(randf_range(-3, 3), 1.5,
				randf_range(-3, 3)), false)
		who._finish_choice(1.4)
		return
	# THE CRUEL FINISH GOES LAST, and after the scoring, on purpose.
	# `_finish_choice` ends in `_decide`, which picks the creature's next deed —
	# so the meal has to be set up AFTER that or the next decision immediately
	# throws it away. The juggle is scored as the juggle it was; then it keeps
	# one, through the same door everything else it eats goes through.
	who._finish_choice(1.4)
	_have_one(who, held)


## A KIND FINISH. The jump shot first, if it has the arm and there is a
## storehouse in range and anything up there worth putting in one — and it is
## the best throw in the game, because it is the one that feeds people. Whatever
## is left is set down on its feet.
func _set_down_well(who: Creature, held: Array) -> void:
	var scored := false
	for thing in held:
		if not is_instance_valid(thing):
			continue
		var shot := CreatureThrowing.at_the_larder(who, thing)
		if shot != Vector3.ZERO:
			CreatureThrowing.send(thing, shot)
			scored = true
			continue
		CreatureThrowing.send(thing, Vector3.ZERO, true)
	who.express("happy", 2.2)
	who.heart.stir("pride" if scored else "contentment", 0.4)
	if scored:
		GameState.announce("Your creature finishes the trick with a shot at the storehouse.")
	else:
		GameState.announce("Your creature sets them all down, one by one, unhurt.")


## A CRUEL FINISH. It keeps one.
func _have_one(who: Creature, held: Array) -> void:
	var meal: Node3D = null
	for thing in held:
		if not is_instance_valid(thing):
			continue
		if meal == null and (thing is Animal or thing is Villager or thing is Corpse):
			meal = thing
			continue
		CreatureThrowing.send(thing, CreatureThrowing.heave(who))
	if meal == null:
		return
	# Straight into the mouth, through the same door everything else it eats
	# goes through, so a juggled villager costs it exactly what any other
	# eaten villager costs it.
	who._pick_up_thing(meal, "eat")
	who._eat_carried()


## FIRE GOES WHEREVER IT IS FLUNG. A frozen gout is inert — Fireball does
## nothing at all while it is in a grip — so LETTING GO is the whole of it: it
## arms itself in the air, lays its trail across whatever it crosses, and gutters
## out where it stops. Deliberately not burst() here: that would detonate every
## one of them at the creature's own feet, which is a different deed entirely
## and not the one it meant.
func _scatter_the_fire(who: Creature, held: Array) -> void:
	for thing in held:
		if not is_instance_valid(thing):
			continue
		CreatureThrowing.send(thing, CreatureThrowing.heave(who))
	who.express("angry", 2.4)
	who.heart.stir("fury", 0.5)
	who.head.sound(who, "fury", 3.0)
	GameState.announce("Your creature flings the fire it was juggling into the village.")


## INTERRUPTED. Everything in the air comes down where it is, which for a
## villager three storeys up is the whole of the risk in being part of the act.
## `gently` is the one exception: a show that never got started sets its one
## prop back on the grass.
func spill(who: Creature, gently := false) -> void:
	for thing in aloft:
		if not is_instance_valid(thing):
			continue
		var fall := Vector3.ZERO if gently \
			else Vector3(randf_range(-2, 2), -1.0, randf_range(-2, 2))
		CreatureThrowing.send(thing, fall, gently)
	if not aloft.is_empty() and not gently:
		GameState.announce("Your creature drops what it was juggling.")
		who.heart.stir("shame", 0.3)
		who.mind.practise("throw", false)   # a fumble teaches too
	aloft.clear()
	_gathering = 0.0
	_scooping = null
	fire = false


func _forget_the_lost() -> void:
	for i in range(aloft.size() - 1, -1, -1):
		if not is_instance_valid(aloft[i]) or aloft[i].is_queued_for_deletion():
			aloft.remove_at(i)
