class_name Agitation
extends RefCounted
## EXTREMELY AGITATED: the state above fear.
##
## Fear already existed and it is a sensible, social thing — a villager who is
## afraid runs away from what frightened them, and a herd that is afraid moves
## off. That is exactly wrong for the three situations this game can put a body
## in where there is nothing sensible left to do:
##
##   ALIGHT. You cannot run away from being on fire.
##   STRUCK. A bolt of lightning is over before fleeing is a plan.
##   IN THE AIR. A god has thrown you and the ground is coming.
##
## In all three the old behaviour was a body walking calmly, or tumbling in
## silence, while something unsurvivable happened to it — and silence is what
## made burning a village feel like a spreadsheet. So: a band ABOVE fear, with
## no flee behaviour in it at all, because thrashing is not a plan and is not
## meant to be.
##
## WHAT IT IS MADE OF. A cry, rate-limited across the whole world so that a
## street on fire is a street on fire and not a wall of clipped voices. And a
## flail: the body shaking on all three axes at a rate nothing else in the game
## moves at, laid over whatever pose it already had rather than replacing it,
## so a burning man still runs and a thrown one still tumbles.
##
## IT IS A LOOK AND A SOUND AND NOTHING ELSE. No state, no decision, no
## interruption — the same principle as CreatureHead. A body that is agitated
## is still doing whatever it was doing; it is doing it while coming apart.
##
## ONE OF THESE PER BODY, like Kindling: the two things that have to be
## remembered — when this one last cried, and whether the fit is still on it —
## are the body's own, and keeping them here rather than as two more fields on
## Villager is what fits the whole feature into two lines at the call site.

## How hard the flail is and how fast, in radians and in cycles a second. Fast
## enough to read as panic at a distance, and nowhere near any other motion in
## the game so it cannot be mistaken for walking.
const THRASH := 0.30
const THRASH_RATE := 17.0

## How often ANY body in the world may cry out, and how long one body waits
## before it may again. The first number is what keeps a burning village from
## becoming noise; the second is what stops one man screaming continuously.
const WORLD_REST := 0.22
const OWN_REST := 2.6

## How far a cry carries, past which it is not worth an AudioStreamPlayer3D.
## Measured from the EAR and not from the camera — see Ear.
##
## MUST NOT EXCEED the reach SoundBank.play_on gives a cry, or this gate lets
## through sounds the mixer then cuts off, which is a player and a voice budget
## spent on silence. tools/earshot.py fails the build if the two drift apart;
## it caught them drifting the first time they were written.
const HEARD_WITHIN := 70.0

## When the world last heard anybody at all. Static because the budget is the
## WORLD'S, not each body's — a hundred people each politely waiting their own
## two seconds is still a hundred screams a second.
static var _world_cried := 0.0

var _cried_at := -99.0
var _gripped := false


## ONE FRAME OF COMING APART. The whole of the call site: a body says what is
## happening to it and this decides whether that is past bearing, what it looks
## like, and whether anyone hears it.
##
## `airborne` is passed rather than inferred because a villager and an animal
## spell falling differently and neither spelling belongs in here.
## `flame` is the body's own fire, if it has one lit. It flickers from here
## because a guttering flame is the same fact about the same body as the
## thrashing and the cry, and it was previously a third function on a third
## clock doing it from two call sites that had to remember to.
func judder(who: Node3D, visuals: Node3D, burning: bool, airborne: bool,
		flame: Node3D = null, human := true) -> void:
	if is_instance_valid(flame):
		flame.scale.y = 1.0 + sin(GameState.clock * 16.0) * 0.2
	if not grips(burning, airborne):
		# SOMETHING HAS TO PUT THE BODY BACK. `flail` writes straight onto the
		# visuals' rotation, so without this a villager who stops burning walks
		# the rest of their life at whatever angle the last frame left them.
		if _gripped:
			_gripped = false
			settle(visuals)
		return
	_gripped = true
	flail(visuals)
	_cried_at = cry(who, _cried_at, human)


## IS THIS BODY PAST BEARING IT? The one definition, so the flail, the cry and
## anything that wants to ask later all agree.
##
## `airborne` is passed rather than inferred because a villager and an animal
## spell falling differently and neither spelling belongs in here.
static func grips(burning: bool, airborne: bool, struck := false) -> bool:
	return burning or airborne or struck


## THE BODY COMING APART, laid over whatever pose it already had.
##
## Applied to the VISUALS and not to the body, so nothing here can move a
## villager through a wall, change where they are standing, or fight the
## thing that is actually steering them. It is a shake and it is only a shake.
static func flail(visuals_given: Variant, force := 1.0) -> void:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(visuals_given):
		return
	var visuals := visuals_given as Node3D
	if visuals == null or not is_instance_valid(visuals):
		return
	# One clock for the whole world, so a crowd thrashes together rather than
	# each on its own phase — which reads as a crowd in one disaster instead of
	# as a dozen unrelated malfunctions. The offset by instance id keeps them
	# from being a chorus line.
	var beat := GameState.clock * THRASH_RATE + float(visuals.get_instance_id() % 97)
	var swing := THRASH * clampf(force, 0.0, 1.0)
	visuals.rotation.x = sin(beat) * swing
	visuals.rotation.z = sin(beat * 1.37 + 1.1) * swing
	visuals.rotation.y += sin(beat * 0.71) * swing * 0.35


## PUT THE BODY BACK. Called when the fit passes, because `flail` writes
## straight onto the visuals' rotation and something has to own putting it back
## to nought — otherwise a villager who stops burning walks the rest of their
## life at whatever angle the last frame left them at.
static func settle(visuals_given: Variant) -> void:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(visuals_given):
		return
	var visuals := visuals_given as Node3D
	if visuals == null or not is_instance_valid(visuals):
		return
	visuals.rotation.x = 0.0
	visuals.rotation.z = 0.0


## CRY OUT, if the world has room for it. `last` is the body's own clock, given
## and returned so nothing here has to keep a table of every villager alive.
##
## IT PLAYS ON THE BODY, NOT ON A SPEAKER IN THE FIELD. `play_on` parents the
## emitter to the thing crying, so a villager hurled across a valley is followed
## by their own voice — panning, falloff and Doppler all coming out of the body
## actually travelling — instead of leaving the scream behind at the spot they
## were thrown from and flying off in silence. And it cuts the instant they
## land, because a scream that outlives its owner is a joke.
##
## `play_on` reads res://voices/ first, so a recorded take replaces this
## everywhere with no further work — see voices/aDIRECTIONcoaching.md, [scream].
static func cry(who_given: Variant, last: float, human := true) -> float:
	# Untyped until proved alive: a freed object handed to a typed parameter
	# is the error, raised before any check below could run. Gone is null.
	var who: Node3D = (who_given as Node3D) if is_instance_valid(who_given) else null
	var now := GameState.clock
	if now - last < OWN_REST or now - _world_cried < WORLD_REST:
		return last
	if who == null or not is_instance_valid(who):
		return last
	# ASKED OF THE EAR, not of the camera. The ear stands on the ground the god
	# is looking at and leans toward their hand; the camera can be seventy
	# metres behind it, and measuring from there refused cries that would have
	# been perfectly audible. See Ear.
	if Ear.where().distance_to(who.global_position) > HEARD_WITHIN:
		return last
	_world_cried = now
	if human:
		SoundBank.play_on(who, "scream", -2.0, 0.16)
	else:
		# An animal in the same extremity. The same waveform pitched down and
		# roughened is a beast rather than a person, and one waveform serving
		# both is one waveform to replace when a real one arrives.
		SoundBank.play_on(who, "scream", -4.0, 0.22, randf_range(0.55, 0.78))
	return now
