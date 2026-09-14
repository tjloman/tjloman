class_name Spool
extends RefCounted
## THE QUEUE FOR THINKING, so a frame costs what it costs no matter how big
## the town gets.
##
## LIKE A PRINT SPOOLER. A document does not hold the machine until it is
## printed; it takes its place in a queue, and the queue empties at whatever
## rate the printer can manage. Nothing is lost, nothing blocks, and the thing
## you notice is that a big job takes longer — not that the computer stopped.
##
## WHAT WAS WRONG WITH THE OLD ANSWER. Scheduler spreads a crowd across frames
## by PHASE: each entity's turn is `(frame + its own id) % stride`, so two
## hundred villagers on a stride of four deal themselves evenly instead of all
## landing together. That fixed a real thundering herd, and it is still how the
## cheap per-frame work is spread. But a phase is statistical, not bounded. A
## villager inside 130m has a stride of 1, so every one of them runs every
## frame, and the frame cost IS the population.
##
## And the expensive call — Villager's `_choose` — is not on a clock at all. It
## fires when a plan runs out, which is usually a trickle and occasionally all
## at once: a wolf comes over the hill, a job fills, a miracle lands, and two
## hundred people re-decide on the same frame. No stride can spread that,
## because the trigger is simultaneous by nature. That is the spike.
##
## WHAT A SPOOL CHANGES is which quantity grows with the population. Before, it
## was frame time. Now it is LATENCY: at `Quality.decisions()` a frame, a town
## of two hundred clears a full-town rethink in about twenty frames — a third of
## a second — and a town of two thousand takes three seconds, during which
## people go on walking where they were walking and idling where they were
## idling. Which is the trade worth making, because a late decision looks like
## a person thinking and a late frame looks like a broken game.
##
## WHAT IS NOT IN HERE. Movement, gravity, animation and the status over
## somebody's head all stay per-frame: those are what make a body look alive,
## and deferring them is a stutter. Fear is not in here either — `scare()` sets
## the state directly and always has, so nobody waits in a queue while a wolf
## eats them.
##
## THE CREATURE'S OWN LANE. It never asks. One entity, thinking every frame it
## wants to, ahead of everything: its mind is the game, and a creature that
## hesitated a third of a second before reacting to praise would be a different
## and worse animal. That is what "a core of its own" means here — GDScript has
## one thread for game logic and the scene tree is not thread-safe, so a real
## thread would mean the creature reading a snapshot and writing back on the
## main thread, which is a great deal of new machinery and a new class of bug
## for one entity. A lane costs nothing and gets the same result.

## Compact the line once the served head gets this long. Slicing a packed array
## is a copy, so it is done rarely rather than every frame.
const TIDY_AT := 256

## THE LINE. An entry is servable only while it sits within `Quality.decisions()`
## live places of the front, which is what stops the order the askers happen to
## arrive in — Godot's tree order, which never changes — from deciding anything.
static var _line := PackedInt64Array()
static var _waiting := {}          # instance id -> true, while it is in `_line`
static var _head := 0              # everything before this is served or dead
static var _frame := -1
static var _spent := 0
static var _served := 0            # last completed frame's count, for readouts


## MAY I THINK NOW?
##
## Ask every frame you want to and act on `true`. On `false`, carry on doing
## whatever you were already doing and ask again next frame — that is the whole
## contract, and it is why a spooled town looks like a town rather than like a
## crowd of statues.
##
## First ask puts you at the back of the line. You are served when you reach
## the front and the frame still has room.
static func turn_to_think(who: Node) -> bool:
	var now := Engine.get_physics_frames()
	if now != _frame:
		_frame = now
		_served = _spent
		_spent = 0
	var budget := Quality.decisions()
	var id := who.get_instance_id()
	if not _waiting.has(id):
		_line.append(id)
		_waiting[id] = true
	if _spent >= budget:
		return false
	# Walk the front of the line, dropping what is served or dead as we pass
	# it, until we have looked at `budget` live entries. Bounded by the budget,
	# so this costs the same on a frame with four in the queue and four hundred.
	var live := 0
	var i := _head
	while i < _line.size() and live < budget:
		var other := _line[i]
		if not _waiting.has(other) or not is_instance_valid(instance_from_id(other)):
			_waiting.erase(other)
			if i == _head:
				_head += 1
			i += 1
			continue
		if other == id:
			_waiting.erase(id)
			if i == _head:
				_head += 1
			_spent += 1
			return true
		live += 1
		i += 1
	if _head > TIDY_AT:
		_line = _line.slice(_head)
		_head = 0
	return false


## How many are standing in the line right now. For the smoke test and for
## anybody wondering whether the town is thinking or waiting.
static func waiting() -> int:
	return _waiting.size()


## How many decisions the last completed frame actually spent.
static func served() -> int:
	return _served


## Forget everybody. For a world teardown — a queue full of freed ids is
## harmless but it is not tidy, and a save load should start from nothing.
static func clear() -> void:
	_line = PackedInt64Array()
	_waiting = {}
	_head = 0
	_spent = 0
	_served = 0
