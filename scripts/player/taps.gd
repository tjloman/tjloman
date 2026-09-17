class_name Taps
extends RefCounted
## HOW MANY TIMES IN A ROW, AND HOW FAST.
##
## The game had one press and one hold and nothing else, and there are now
## several things that want a third word: close the panel that is open, knock on
## a roof to see who lives there, point the creature's attention at a thing
## without ordering it anywhere. All of those are "tap again", and none of them
## can be a hold, because the hold is already taken twice over — it opens the
## casting session and it ties the lead.
##
## TWO, NOT THREE. Three taps is a gesture people perform wrong: the third
## arrives late on a phone that is dropping frames, which is exactly the phone
## this is for, and a triple that lands as a double does the wrong thing rather
## than nothing. Two is the one multiple every touch platform has trained
## everybody in, and it leaves the third available later if anything ever truly
## needs it.
##
## AND IT MUST NOT STEAL THE FIRST TAP. Everything the single press already does
## goes on happening; the double is only ever read as a SECOND meaning laid over
## it. Anything else would mean waiting out the double-tap window before acting
## on a single one, which is a tenth of a second of the game not answering the
## finger — and not answering the finger is the one thing this project keeps
## refusing to do.

## How long after a tap another one still counts as part of the same gesture.
## Long enough to be comfortable on a phone held in one hand, short enough that
## two separate decisions are never read as one.
const WITHIN := 0.34
## And how far the second may land from the first. A double tap is two taps in
## one PLACE; a finger that moved across the screen was doing something else.
const NEAR := 54.0


var _last := -999.0
var _where := Vector2.INF
var _run := 0


## A PRESS HAPPENED. Returns how many taps in a row this one makes: 1 for a
## fresh tap, 2 for a double, and it starts again from 1 after that — so a
## drummed finger reads as double, single, double rather than as four.
func pressed(at: Vector2, now: float) -> int:
	if now - _last <= WITHIN and _where.distance_to(at) <= NEAR and _run == 1:
		_run = 2
	else:
		_run = 1
	_last = now
	_where = at
	return _run


## Forget the run. Said when something else claimed the gesture — a drag, a
## hold, a second finger — so the tap after it starts clean rather than
## completing a double with whatever happened before.
func cancel() -> void:
	_run = 0
	_last = -999.0
	_where = Vector2.INF
