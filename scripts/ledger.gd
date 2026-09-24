class_name Ledger
extends RefCounted
## WHERE THE SCRIPT TIME WENT, BY CLASS.
##
## A phone reported a hundred milliseconds a frame with ninety-one of them in
## `_process` and none of them in the draw. That is half an answer: it rules out
## the GPU, the driver, the fill rate and the whole graphics tier, and it leaves
## forty classes that implement `_process` and no way to tell which of them is
## spending it.
##
## Everything past that point is guessing, and this codebase has a rule about
## guessing — so the classes that exist in their hundreds clock themselves, and
## the meter prints the bill.
##
## WHAT IT COSTS WHEN NOBODY IS LOOKING. One static call and one boolean test,
## at the top of a `_process` that was going to run anyway — about a tenth of a
## microsecond, which across the couple of thousand nodes in this game that
## actually run a script is well under a millisecond — and buys the ability to answer this question on the device
## rather than by argument. It is only ever ON while the frame meter is open.
##
## WHAT IS NOT CLOCKED, AND WHY — AND IT IS NOW ALMOST NOTHING.
##
## This file used to say that Villager and Creature were not clocked, because
## both sat exactly on the 2500-line limit and a stopwatch cost a line somebody
## else's paragraph would have to pay for. Both are clocked now, and so is every
## other `_process` and `_physics_process` in the game — thirty of them went in
## at once, because a bill with a forty-three millisecond line reading
## "(everything else)" is not a bill, it is a shrug.
##
## WHAT THE GAP MEANS, EXACTLY, and it is worth being precise because it is the
## row people read first. The baton is continuous: from the first `open` of a
## page to the page turning, SOMEBODY is always being charged. So the gap is not
## "the classes nobody clocked" scattered through the frame — everything after
## the first clock goes on somebody's bill whether it belongs there or not.
##
## The gap is the head of the frame: the span between the page turning and the
## first `open` of the next one. With every callback clocked, what is left in it
## is the engine's own work before any script runs — the physics server's step,
## its broadphase and solver, the transform propagation — which is real, is
## often most of it, and is not a class anybody can go and optimise. That is
## worth knowing as such, and tools/attribution.py keeps it that way by failing
## the moment a per-frame callback goes unclocked again.

## WHAT A ROW IS, EXACTLY: AN UPPER BOUND, NOT A COST.
##
## A clock is shut by the next one opening, so a class is charged from its own
## `open` to the next — and everything that runs in between goes on its bill,
## whether it belongs to it or not. Two things run in between. The first is any
## UNCLOCKED class interleaved with it, which is why Villager had to be clocked
## the moment Animal was: two hundred and sixty villagers and twenty-four beasts
## share a physics tick, and every villager between two beasts was billed to the
## beast. The second cannot be closed from in here at all — between the last
## node of one physics step and the first node of the next, the ENGINE runs its
## solver, and that goes to whichever node happened to be last.
##
## Which is how a reading came back saying Animal cost 141.7ms out of a physics
## total of 33.2ms. A part cannot exceed the whole; what it was reporting was
## Animal plus Villager plus eight runs of the solver.
##
## SO THE METER PRINTS `counted` AGAINST GODOT'S OWN FIGURE, and the moment the
## first is larger than the second the rows are absorbing something and say so.
## A profiler that cannot tell you it is wrong is worse than none, because it is
## also a claim.
##
## AND THE UNACCOUNTED IS PRINTED TOO. The sum of what is measured is always
## less than Godot's own `TIME_PROCESS`, and the gap is printed rather than
## quietly dropped. A ledger that only shows what it was told to show is a
## ledger that confirms whatever the person writing it already believed.

## Kept in microseconds and turned over once a frame, so the meter is reading a
## finished page rather than one being written under it.
static var on := false

static var _open := &""
static var _since := 0
static var _spent := {}
static var _rang := {}
static var _page := {}
static var _rings := {}


## OPEN A CLOCK ON THIS CLASS, and shut whatever was open.
##
## ONE LINE AT THE TOP OF `_process`, AND NOTHING AT THE BOTTOM. That is the
## whole design, and it is not laziness — it is the only shape that works.
##
## A stopwatch that has to be stopped means wrapping the body in a second
## function, because half these `_process` bodies return early and a `stop`
## after the body would never run on those paths. Renaming eleven `_process`
## methods to `_tick_ledger` was tried first, and it broke tools/drove.py
## within the minute: that file reads the barn's `_process` to check it gives
## its herds one order a leg, and the body it was reading had moved. Every tool
## that reads a `_process` body would have been silently wrong about eleven
## classes, and only one of them said so.
##
## So the clock is closed by the NEXT one opening. A class is charged from its
## own `open` to whoever opens next, which is the time spent in its `_process`
## plus a sliver of the engine's own dispatch — and that sliver belongs to it
## anyway. The last one of the frame is closed when the page turns.
static func open(what: StringName) -> void:
	if not on:
		return
	var now := Time.get_ticks_usec()
	if _open != &"":
		_spent[_open] = int(_spent.get(_open, 0)) + (now - _since)
	_open = what
	_since = now
	_rang[what] = int(_rang.get(what, 0)) + 1


## SHUT WHATEVER IS OPEN. Called when the page turns, and by anything that
## knows it is the last word in a frame.
static func shut() -> void:
	if not on or _open == &"":
		return
	_spent[_open] = int(_spent.get(_open, 0)) + (Time.get_ticks_usec() - _since)
	_open = &""


## TURN THE PAGE. Called once a frame by whoever is reading it. What was being
## written becomes what is read, and the next frame starts from nothing.
static func turn_the_page() -> void:
	shut()
	_page = _spent
	_rings = _rang
	_spent = {}
	_rang = {}


## THE BILL, dearest first: [name, milliseconds, how many of them ran].
static func rows() -> Array:
	var out := []
	for what: StringName in _page:
		out.append([String(what), float(_page[what]) / 1000.0,
			int(_rings.get(what, 0))])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


## What the ledger accounts for altogether, in milliseconds. The meter prints
## this against Godot's own figure so the GAP is visible — see the header.
static func counted() -> float:
	var all := 0
	for what: StringName in _page:
		all += int(_page[what])
	return float(all) / 1000.0
