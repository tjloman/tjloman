class_name Audience
extends RefCounted
## WALL CLOCK BY DESIGN: a slap is how fast a FINGER crosses the glass, timed
## the way DivineHand times a throw — a press spanning a pause is a resting
## hand, not a blow. Everything the creature lives through runs on its own ticks.
## HOLD YOUR HAND ON IT, AND IT STOPS TO LOOK AT YOU.
##
## On a phone the creature was the hardest thing in the game to reach: P and L
## are keys, the Praise and Scold buttons only came up once you had found the
## lock-on, and a thumb on the beast itself did nothing a thumb on the grass
## would not. Black & White answered this with the hand: you stroke the
## creature to reward it and slap it to correct it, and both are gestures ON
## THE CREATURE rather than buttons beside it.
##
## So a hold on the creature opens an audience with it:
##
##   * it stops what it is doing and turns to face you (Creature.greeting_eye
##     holds it in HEED; it is not frozen, it is attending),
##   * the camera glides round to a shot of it from the side you were already
##     looking from, a little above its head, so it looks up at you,
##   * and it GREETS you — how it feels just now, and about what (see
##     CreatureGreeting, which reads that off the creature rather than making
##     it up).
##
## While the audience is open, the hand is for the creature only:
##
##   STROKE it — rub back and forth across it, unhurried — and that is praise.
##   SLAP it — a fast swipe across it — and that is a scolding. The harder the
##        swipe, the more it stings.
##   TAP it and it tells you again how it feels. TAP AWAY and it goes back to
##        its day. Nothing for a while, and it goes back anyway.
##
## Praise and scolding are the same two acts they always were (Creature.praise
## and Creature.scold): this changes how you reach them, not what they teach.
## And a creature in the middle of deciding something (CreatureIntent) is not
## made to stand still for you — your hand lands on the decision, as P and L do.

## How long the hand rests on the creature before it is called.
const HOLD := 0.5
## Seconds of nothing before it goes back to what it was doing.
const IDLE := 25.0
## Further than this and a press was not a tap, in pixels.
const TAP_SLOP := 16.0
## How much rubbing over it makes a stroke, in screen heights of travel.
const PET_PATH := 0.45
## How fast a swipe across it makes a slap, in screen heights a second, and how
## long the speed is measured over. A rub is well under one; a flick is three.
const SLAP_SPEED := 2.0
const SLAP_WINDOW := 0.08
## How long after a stroke or a slap it answers you, in seconds.
const ANSWER := 1.4
## THE SHOT, in the creature's own heights: what it aims at, how far back it
## stands, and how far down it looks.
const SHOT_EYE := 0.72
const SHOT_BACK := 1.7
const SHOT_PITCH := -14.0

## Which feeling it sounds, for each mood. See CreatureHead.SAYS.
const VOICE := {
	"frightened": "dread", "angry": "fury", "upset": "grief",
	"cruelly joking": "delight", "enthusiastic": "pride", "excited": "delight",
}

## The creature you are with, or null.
var who: Creature = null
## What it said, as CreatureGreeting.compose gives it: {"mood", "line"}.
var greeting := {}
## What your hand last did to it — "stroke" or "slap" — and when, on the
## hand's clock. See `just_touched`.
var touched := ""
var touched_at := -INF

var _rig: CameraRig = null
var _held := false
var _idle := 0.0
var _answer_in := 0.0
## The press in progress: where it began, how far it has rubbed over the
## creature, the recent samples a swipe's speed is read from, and what it has
## already done (one stroke and one slap a press).
var _down := false
var _from := Vector2.ZERO
var _last := Vector2.ZERO
var _travel := 0.0
var _rubbed := 0.0
var _samples: Array = []
var _stroked := false
var _slapped := false


func is_open() -> bool:
	return who != null and is_instance_valid(who)


## WHY IT WILL NOT STOP, or "" if it will. Said rather than silently ignored:
## a hold that does nothing reads as a hold that is broken.
static func refusal(c: Creature) -> String:
	match c.state:
		Creature.State.SLEEPING:
			return "%s is fast asleep. Let it rest." % c.called()
		Creature.State.FLEE:
			return "%s is too frightened to stop." % c.called()
		Creature.State.DEPART:
			return "%s will not stop for you." % c.called()
		Creature.State.CAST:
			return "%s is in the middle of a working." % c.called()
	return ""


## Call it. False, with the reason announced, if it will not come.
func open(c: Creature, rig: CameraRig) -> bool:
	var no := refusal(c)
	if no != "":
		GameState.announce(no)
		return false
	who = c
	_rig = rig
	# STILL DECIDING, and it is not made to stand for you: your hand lands on
	# the decision. See CreatureIntent.
	_held = c.state != Creature.State.WEIGHING
	if _held:
		c.state = Creature.State.HEED
		c.velocity = Vector3.ZERO
	_idle = 0.0
	_down = false
	touched = ""
	_frame()
	BootTrail.mark("an audience with the creature")
	greet()
	return true


## It goes back to its day. The camera stays where it is, as yours.
func close() -> void:
	if is_instance_valid(who):
		who.greeting_eye = Vector3.INF
	who = null
	greeting = {}
	_down = false
	if _rig != null and is_instance_valid(_rig):
		_rig.framed = false


## Ask it how it is, and have it say so out loud.
func greet() -> void:
	greeting = CreatureGreeting.compose(who)
	if not _held:
		var deciding := who.intent.said(who)
		if deciding != "":
			greeting["line"] = deciding.replace(
				"Praise it, or scold it, NOW.", "Stroke it to let it, slap it to stop it.")
	var mood := String(greeting["mood"])
	if VOICE.has(mood):
		who.head.sound(who, String(VOICE[mood]), 1.0)
	else:
		SoundBank.play_at("coo", who.global_position, -4.0, 0.15, 0.7)


## Once a physics tick, from the hand.
func tick(delta: float) -> void:
	if not is_open():
		if who != null:
			close()
		return
	# IT WENT. Fled, fell asleep, decided — whatever it was, it is not
	# standing for you any more, and an audience with nobody is over.
	#
	# EXCEPT TO SULK. A scolding has always sent it into a sulk where it
	# stands (Creature.scold), and that is still in front of you: you may
	# stroke it while it sulks, and when the sulk is over it goes off about
	# its day — which is the audience over, the way a slap ends one.
	var stays := [Creature.State.HEED, Creature.State.SULK] if _held \
		else [Creature.State.WEIGHING]
	if who.state not in stays:
		close()
		return
	if who.state == Creature.State.HEED and _rig != null and is_instance_valid(_rig):
		who.greeting_eye = _rig.camera.global_position
	_idle += delta
	if _idle >= IDLE:
		close()
		return
	if _answer_in > 0.0:
		_answer_in -= delta
		if _answer_in <= 0.0:
			greet()


## A finger (or the button) goes down.
func press(at: Vector2) -> void:
	_down = true
	_from = at
	_last = at
	_travel = 0.0
	_rubbed = 0.0
	_samples = [[at, _now()]]
	_stroked = false
	_slapped = false
	_idle = 0.0


## It moves. Every move is weighed for a slap; moves over it add to a stroke.
## `screen` is the height of the screen in pixels, which every distance here is
## measured in, so a phone and a monitor ask the same of a hand.
func move(at: Vector2, on_it: bool, screen: float) -> void:
	if not _down:
		return
	var step := at.distance_to(_last)
	_travel += step
	_last = at
	var now := _now()
	_samples.append([at, now])
	while _samples.size() > 2 and now - float(_samples[0][1]) > SLAP_WINDOW:
		_samples.pop_front()
	_idle = 0.0
	var speed := _speed(screen)
	# A SLAP is a swipe ACROSS it, so it may start on the grass beside it; it
	# only has to be fast while the hand is on it.
	if on_it and not _slapped and speed >= SLAP_SPEED:
		_slap(speed / SLAP_SPEED)
		return
	if on_it and speed < SLAP_SPEED:
		_rubbed += step / maxf(screen, 1.0)
		if not _stroked and not _slapped and _rubbed >= PET_PATH:
			_stroke()


## And it comes up. A press that never went anywhere was a tap: on it, it is
## asked again; off it, you are done.
func release(on_it: bool) -> void:
	if not _down:
		return            # the press that OPENED this; it is not a tap
	_down = false
	if _travel > TAP_SLOP or _stroked or _slapped:
		return
	if on_it:
		greet()
	else:
		close()


## What the hand did to it in the last moment, or "" — so a slap that landed
## and a stroke that counted can be told apart from a hand that only moved.
func just_touched() -> String:
	return touched if _now() - touched_at < 1.2 else ""


## A second finger came down: the press is the camera's now, not a stroke.
func cancel_press() -> void:
	_down = false


func _stroke() -> void:
	_stroked = true
	touched = "stroke"
	touched_at = _now()
	who.praise()
	who.head.sound(who, "delight", -2.0)
	_answer_in = ANSWER


## THE HARDER, THE MORE IT STINGS — and the more it remembers whose hand it
## was. A scolding is the lesson; the sting and the fright are the slap.
func _slap(force: float) -> void:
	_slapped = true
	touched = "slap"
	touched_at = _now()
	who.scold()
	var hard := clampf(force, 1.0, 3.0)
	who.feel("pain", 0.15 * hard, 1.2)
	who.fear = minf(who.fear + 5.0 * hard, 100.0)
	who.head.sound(who, "pain", hard)
	SoundBank.play_at("pick", who.global_position, -2.0 + hard * 2.0, 0.1, 0.6)
	if _rig != null and is_instance_valid(_rig):
		_rig.shake(0.06 * hard)
	_answer_in = ANSWER


## THE SHOT. From the side you were already looking from — it turns round to
## face you, rather than the world swinging round behind it — and from a little
## above its head, so it looks UP at you, which is the whole picture.
func _frame() -> void:
	if _rig == null or not is_instance_valid(_rig):
		return
	var tall := CreatureBody.STANDING * who.scale.y
	var aim := who.global_position + Vector3.UP * tall * SHOT_EYE
	_rig.glide_to(aim, _rig.rotation.y, SHOT_PITCH, tall * SHOT_BACK)
	if _held:
		who.greeting_eye = aim + _rig.global_transform.basis.z * tall * SHOT_BACK


## How fast the hand is going, in screen heights a second, over the last
## SLAP_WINDOW.
func _speed(screen: float) -> float:
	if _samples.size() < 2:
		return 0.0
	var first: Array = _samples[0]
	var last: Array = _samples[_samples.size() - 1]
	var span := float(last[1]) - float(first[1])
	if span <= 0.0:
		return 0.0
	return (last[0] as Vector2).distance_to(first[0] as Vector2) / maxf(screen, 1.0) / span


## The hand's own clock — wall time, for the same reason DivineHand keeps one:
## this measures a finger, not the world.
static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
