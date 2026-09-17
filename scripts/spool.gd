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
## AND THE ASKER MUST STOP. This is the one obligation a spool puts on its
## callers, and it is not obvious until it bites.
##
## `_decide` used to change state the instant it was called, so an arm that had
## completed could never run a second time. Asking does not change anything, so
## an arm sits there with its plan already finished and its trigger already
## tripped, and runs its completion AGAIN on every frame until its turn comes.
## In Villager that meant BUILDING_FARM raised a field every frame — and at
## Vector3.INF, because the sentinel that says "no spot" is written on the line
## after the call. Three arms had that shape. The renderer logged it three
## hundred and seventy-nine thousand times.
##
## So a caller that has finished a plan must do nothing further with it until
## the answer arrives. Villager latches the whole match; anything else that
## starts asking has to decide what its own version of standing still is.
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

## HOW LONG A PLACE IN THE LINE SURVIVES WITHOUT BEING ASKED FOR.
##
## THE JAM THIS EXISTS FOR. A place used to be held by having asked ONCE, and
## held forever after. An entity that joined the line and then stopped asking —
## a villager pinned under a wolf, one that is dying, one far enough out that
## Util.sim_stride only lets it run every fortieth frame — went on occupying one
## of the `budget` places at the front of the queue, alive and never served,
## because nothing in the walk below could tell "waiting" from "gone quiet".
##
## Collect `budget` of those and the spool STOPS. Not slows: stops. Nobody is
## ever served again, every villager stands about with a plan that has run out,
## and the town starves with a full granary. It takes hours to gather that many,
## which is exactly when it was seen.
##
## So a place is held by asking, not by having asked. Two seconds of silence and
## the entry is treated as gone; it rejoins at the back the moment it speaks up
## again, which is correct, because an entity that was not asking was not
## waiting for anything. The worst honest gap between two asks is
## Util.sim_stride's 10 multiplied by Quality.sim_relief's 4 — forty frames — so
## this is three times the longest wait any entity can legitimately have.
const GONE_QUIET := 120

## THE LINE. An entry is servable only while it sits within `Quality.decisions()`
## live places of the front, which is what stops the order the askers happen to
## arrive in — Godot's tree order, which never changes — from deciding anything.
static var _line := PackedInt64Array()
static var _waiting := {}          # instance id -> the frame it joined the line
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
	# STAMPED ON EVERY ASK, not only the first. This is the whole of what keeps
	# the line honest — see GONE_QUIET.
	_waiting[id] = now
	if _spent >= budget:
		return false
	# Walk the front of the line, dropping what is served, dead or gone quiet as
	# we pass it, until we have looked at `budget` live entries. Bounded by the
	# budget, so this costs the same with four in the queue and four hundred.
	var live := 0
	var i := _head
	while i < _line.size() and live < budget:
		var other := _line[i]
		if _lapsed(other, now):
			_waiting.erase(other)
			if i == _head:
				_head += 1
			i += 1
			continue
		# NOT ASKING THIS FRAME IS NOT WAITING THIS FRAME.
		#
		# THE JAM THIS EXISTS FOR, and it stopped a town of two hundred and
		# sixty-three from thinking at all: "0 thinking a frame, 65 in the line".
		#
		# A place is held by asking — which `_waiting[id] = now` above makes
		# true — but the walk below counted every unlapsed entry against the
		# budget whether it had spoken this frame or not. And most of a town
		# does not speak every frame: Util.sim_stride puts anybody past 260m on
		# a clock of ten, times up to four for heat, so a villager in the next
		# valley asks once in forty frames. Refuse one of those and it sits in
		# the line, silent, for thirty-nine frames — not lapsed, because
		# GONE_QUIET is a hundred and twenty and has to be, and not asking.
		#
		# Collect `budget` of them at the front and the walk never reaches
		# anybody who IS asking. Not slows: STOPS. Four were served on the first
		# frame and nobody was served again, while the queue filled to the whole
		# town and every one of them stood about with a plan run out — which is
		# also the "villagers stopped taking care of themselves" that was
		# reported from play and never explained.
		#
		# So silence costs nothing and asking costs a place. The order among
		# this frame's askers is still the order they joined, so the longest
		# wait is still served first and nobody is stranded by tree order.
		if int(_waiting[other]) != now:
			i += 1
			continue
		if other == id:
			_waiting.erase(id)
			if i == _head:
				_head += 1
			_spent += 1
			_tidy()
			return true
		live += 1
		i += 1
	_tidy()
	return false


## Is this place no longer anybody's? Served, freed, or silent long enough that
## whatever it was waiting for has stopped mattering.
static func _lapsed(other: int, now: int) -> bool:
	if not _waiting.has(other):
		return true
	if not is_instance_valid(instance_from_id(other)):
		return true
	return now - int(_waiting[other]) > GONE_QUIET


## Throw away the served head of the line. On BOTH paths out, because doing it
## only on the refusal path meant a busy queue — one that grants on nearly every
## call — never compacted at all, and `_line` grew for as long as the session
## lasted.
static func _tidy() -> void:
	if _head > TIDY_AT:
		_line = _line.slice(_head)
		_head = 0


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


## HOW LONG THIS ONE HAS BEEN STANDING IN THE LINE, in seconds. Zero when it is
## not waiting at all.
##
## Here so that a body can be given something to do with the wait. Most waits
## are a fifth of a second and want no covering; it is the STORMS — a wolf, a
## filled job, a whole town re-deciding at once — that produce a pause long
## enough to see, and that is exactly when a villager should be visibly
## thinking rather than visibly stopped. See VillagerLook.may_choose.
static func stalled_for(who: Node) -> float:
	var since = _waiting.get(who.get_instance_id())
	if since == null:
		return 0.0
	return float(Engine.get_physics_frames() - int(since)) \
		/ float(maxi(Engine.physics_ticks_per_second, 1))
