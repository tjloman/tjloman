class_name Scheduler
extends RefCounted
## WHEN EACH THING GETS ITS TURN.
##
## THE BUG THIS EXISTS FOR. Everything that runs on a coarse clock — villagers,
## beasts, villages — counted its own skipped frames from zero:
##
##     _sim_skip += 1
##     if _sim_skip < stride: return
##
## Every one of them starts at zero. So two hundred villagers at a stride of
## four do not spread themselves over four frames; they ALL run on the same
## frame and ALL skip the next three. The average frame time is exactly what it
## would have been, and the PEAK is four times worse — and a peak is what
## a player sees, what a frame-time average eventually crosses a threshold on,
## and therefore what makes the graphics tier drop.
##
## Then it got worse, because the tier dropping RAISES the stride
## (Quality.sim_relief), which makes the spikes taller and rarer. The device
## easing off made the stutter worse, so it eased off further. That loop is why
## the world kept announcing that it was breathing out and working hard, over
## and over, on a machine that was perfectly fine.
##
## THE FIX IS A PHASE. Each entity's turn comes up on `(frame + its own id) %
## stride == 0`, so a crowd of them deals itself evenly across every frame in
## the cycle. It needs no counter, no registration, no central list and no
## agreement between them: an entity's id is a number it already has, and the
## arithmetic is two integer operations. Sequentially created entities land on
## consecutive phases, which is the best spread there is.
##
## AND THE TIME STILL ADDS UP. An entity that has not run for six frames is
## charged six frames of delta, counted from the frame it actually last ran, so
## a villager on a coarse clock walks exactly as far and gets exactly as hungry
## as one running every frame. That was already true and must stay true: this
## changes WHEN the work happens, never how much of it there is.
##
## WHICH PUTS AN OBLIGATION ON THE CALLER. `last_ran` must be written every
## frame the entity actually runs — INCLUDING the frames it runs at full rate
## and never asks this function anything. An entity that only records its turns
## while it is on a coarse clock is not recording when it last ran, it is
## recording when it was last far away, and the difference between those two is
## paid out in one step the moment its stride changes. See MOST_OWED.


## THE MOST ANY ENTITY MAY BE CHARGED IN ONE TICK, in frames.
##
## The worst stride in the game is Util.sim_stride's 10 multiplied by
## Quality.sim_relief's ceiling of 4, so forty frames is the largest gap that
## can honestly open between two turns. Anything beyond that is not a coarse
## clock, it is a bug — and folding it into one step does not "catch up", it
## TELEPORTS: `delta` and the velocity scale are multiplied by this number, so
## a villager handed nine hundred frames walks fifteen metres between one
## frame and the next, through whatever was in the way.
##
## That is not hypothetical. `_sim_last` was only written on the coarse branch,
## so an entity standing near the camera — where the stride is 1 and the branch
## is skipped — never updated it at all. The moment anything nudged its stride
## above 1, it cashed in every frame it had spent near the camera at once. The
## call sites keep the clock honest now; this is the floor under them.
const MOST_OWED := 40


## WHOSE TURN IS IT, and for how much time?
##
## Returns the number of FRAMES this entity should be charged for — pass that to
## its delta — or 0 if this is not its frame. `last_ran` is the entity's own
## record of the physics frame it last ticked on; store what `now()` gives back.
static func turn(who: Node, stride: int, last_ran: int) -> int:
	if stride <= 1:
		return 1
	var frames := int(Engine.get_physics_frames())
	# THE PHASE. `who`'s id is a number nobody else has and nobody had to hand
	# out, so a hundred entities on the same stride land on every frame of the
	# cycle in turn rather than all on one of them.
	if (frames + int(who.get_instance_id())) % stride != 0:
		return 0
	# Counted from when it ACTUALLY last ran, not from the stride — because the
	# stride changes as a thing walks toward and away from the camera, and a
	# creature that has been on a coarse clock owes the time it really missed.
	return clampi(frames - last_ran, 1, MOST_OWED)


## The frame an entity should remember it ran on.
static func now() -> int:
	return int(Engine.get_physics_frames())


## HOW EVENLY A CROWD IS SPREAD, 0..1 — for the smoke test and the debug menu.
## One means every frame of the cycle carries the same share; the old counter
## scored 1/stride, because one frame carried all of it.
static func spread(ids: Array, stride: int) -> float:
	if stride <= 1 or ids.is_empty():
		return 1.0
	var bins := []
	bins.resize(stride)
	bins.fill(0)
	for id: int in ids:
		var at: int = id % stride
		bins[at] = int(bins[at]) + 1
	var most := 0
	for n: int in bins:
		most = maxi(most, n)
	# The perfect share against the worst frame's share.
	return (float(ids.size()) / float(stride)) / maxf(float(most), 1.0)
