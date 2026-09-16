class_name Crowd
extends RefCounted
## A FRAME COSTS WHAT IT COSTS, HOWEVER BIG THE TOWN IS.
##
## Spool made that true of DECISIONS: a fixed number are served a frame, and a
## whole village re-deciding at once costs latency rather than frame time. It
## was never true of the other path — the one every villager runs every frame
## whether it is thinking or not. Movement, gravity, hunger, ageing, the
## watchdogs, the ground checks, the animation and the label over their head.
## None of that is expensive. All of it, two hundred times, sixty times a
## second, is the whole frame.
##
## AND THE SIMULATION LOD WAS NO HELP IN THE ONE CASE THAT HURTS. `sim_stride`
## thins the world by DISTANCE — every tenth frame past 260 metres, every
## fourth past 130, full rate inside that. A city of two hundred people fits
## comfortably inside 130 metres. So the band that was meant to protect the
## frame gave every single one of them full rate, precisely because they were
## all standing together in the place the player was looking at.
##
## SO THE BAND COUNTS ITSELF. Everything that asks whether it is near says so
## by asking, and the answer next frame is how many there were. Past what a
## frame can comfortably carry, the stride rises for everybody until the work
## fits — which Scheduler then deals evenly across the cycle, because it has
## always spread a crowd by phase rather than by counter.
##
## The census costs nothing. It is not a walk over a group; it is a tally kept
## as a side effect of work that was happening anyway, one integer per ask.
##
## WHAT THIS TRADES. A packed city simulates at a quarter rate: people walk and
## eat and age at exactly the same speed (Scheduler charges the frames they
## missed), they simply update in four batches instead of one. What you lose is
## the smoothness of any single body's motion in a dense crowd, which is the
## cheapest thing in the game to lose and the hardest to see — because it is a
## dense crowd.

## HOW MANY BODIES THE NEAR BAND CARRIES AT FULL RATE, by graphics tier. Under
## this, nothing changes at all and a village of fifty is exactly as it was.
const AT_FULL: Array[int] = [40, 60, 90]
## And the most the crowd may ever thin itself. Past a quarter rate a walk
## starts to read as a stutter rather than as a slower walk, and a city that
## large is a problem to solve elsewhere.
const STRIDE_MOST := 4

static var _counted := 0
static var _crowd := 0
static var _frame := -1


## I AM IN THE NEAR BAND. Said by anything that has just worked out that it is,
## which is the only census this needs: the tally is a side effect of a question
## that was being asked anyway.
static func counted_near() -> void:
	_roll()
	_counted += 1


## HOW OFTEN A BODY IN THE NEAR BAND SHOULD TICK, given how many of them there
## are. One in an ordinary village; more when the town is a city.
static func stride() -> int:
	_roll()
	var full: int = AT_FULL[clampi(Quality.effective_tier(), 0, AT_FULL.size() - 1)]
	if _crowd <= full:
		return 1
	@warning_ignore("integer_division")
	var thinned := 1 + (_crowd - 1) / full
	return clampi(thinned, 1, STRIDE_MOST)


## HOW MANY WERE COUNTED last frame. For the debug readout, and for anybody
## wondering why the town is running in batches.
static func near() -> int:
	_roll()
	return _crowd


## Roll the tally over when the frame does. Everything here goes through this,
## so the count a frame reads is always the WHOLE of the previous frame rather
## than however much of this one has happened so far.
static func _roll() -> void:
	var now := int(Engine.get_physics_frames())
	if now != _frame:
		_frame = now
		_crowd = _counted
		_counted = 0


## Forget the census. For a world teardown, so a new map does not begin by
## thinning itself against the last one's city.
static func clear() -> void:
	_counted = 0
	_crowd = 0
	_frame = -1
