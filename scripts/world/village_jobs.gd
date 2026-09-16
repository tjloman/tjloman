class_name VillageJobs
extends RefCounted
## HOW MANY HANDS A JOB HAS ROOM FOR, and what everybody else does instead.
##
## THE CROWD PENALTY WAS A DISCOUNT, NOT A LIMIT. A job never actually filled —
## it only got less attractive, seven points a head, and a job docked past
## everything else still won whenever nothing else was on the board. So a town
## put its whole population on a work site by degrees, and there was nobody left
## standing about when the wolves came. A village where every post is taken and
## twenty people are dancing round a fire is not a village doing less work; it
## is a village that has finished its work, and it is the one that can answer
## something.
##
## So room is a CEILING now. A full job is not offered at all, and the penalty
## does what it was always good at — spreading people across the jobs that are
## still open — rather than pretending to be a limit it could not enforce.
##
## AND THE COUNT MOVES WHEN THE POST IS TAKEN. `_jobs` is recomputed once a pass
## by Village._retally, off everybody's current state. Read alone, that is the
## same bug that once had forty people teaching at a school with three posts:
## everybody deciding between two retallies sees the same stale number and every
## one of them passes. `claim` moves it on the frame the job is taken; the
## retally still recomputes it from the roster, which repairs anything that
## dropped a job without saying so.

## Fixed ceilings, for the jobs whose room is not a thing the village built.
## One site, one shore, one carcass — and `expedition`, which is a crowd on
## purpose (see VillageParty.PARTY_MOST).
const ROOM := {
	"build": 3, "build_farm": 2, "build_edubba": 2, "build_shop": 2,
	"build_nest": 3, "fish": 3, "butcher": 2, "butcher_pen": 2,
	"tame": 2, "preach": 2, "feed": 1, "hunt": 4,
	"expedition": VillageParty.PARTY_MOST,
	"circle": CreatureNest.DANCERS,
}
## Timber and stone are limited by the country rather than by anything the town
## built, but "one woodcutter" is not a country, it is an oversight — a village
## of eighty sent one. One hand per this many souls, at least one.
const SOULS_PER_GATHERER := 12

## What an idle villager is drawn to, and how strongly. Dancing outweighs the
## rest because a town at its leisure should LOOK like one.
const REST_DANCE := 5.0
const REST_PRAY := 3.0
const REST_HOME := 4.0
const REST_POTTER := 2.0

## HOW WIDE THE CONGREGATION STANDS. A floor, so a handful still make a circle
## rather than a huddle, and a term that grows with the square root of how many
## are already there — area with the crowd, so the ring does not run away.
const PRAY_RING := 5.0
const PRAY_PER_HEAD := 1.6


## How many hands this job has places for.
static func room_for(town: Village, job: String) -> int:
	match job:
		"farm":
			return maxi(town.farms.size() * 2, 1)
		"work":
			return maxi(Workshop.posts(town), 1)
		"chop", "quarry":
			@warning_ignore("integer_division")
			var hands := maxi(town.population() / SOULS_PER_GATHERER, 1)
			return hands   # whole people; a fraction of a woodcutter is nobody
	return int(ROOM.get(job, 1))


## Is every place taken? A full job is off the board entirely.
static func full(town: Village, job: String) -> bool:
	return int(town._jobs.get(job, 0)) >= room_for(town, job)


## Taken, and counted on the same frame. See the class note.
static func claim(town: Village, job: String) -> void:
	if job == "":
		return
	town._jobs[job] = int(town._jobs.get(job, 0)) + 1


static func release(town: Village, job: String) -> void:
	if job == "" or not town._jobs.has(job):
		return
	town._jobs[job] = maxi(int(town._jobs[job]) - 1, 0)


## NOTHING ON THE BOARD — which is a fine thing to have happen, and used to
## produce a villager walking in a slow random circle for four to nine seconds.
##
## Idleness is a state a village should be able to be IN. There is always time
## for a dance, for the totem, or for sitting near your own door, and a town
## with people doing those things is a town that still has somebody to send when
## something comes out of the trees. It is also the only picture of a village
## that reads as prosperous rather than merely busy.
static func idle(who: Villager) -> void:
	var town := who.village
	var draw := {}
	if town.nest != null and is_instance_valid(town.nest) and not full(town, "circle"):
		draw["dance"] = REST_DANCE
	if town.totem != null and is_instance_valid(town.totem):
		draw["pray"] = REST_PRAY
	if who.home != null and is_instance_valid(who.home):
		draw["home"] = REST_HOME
	draw["potter"] = REST_POTTER
	match _drawn(draw):
		"dance":
			who._target = town.nest.ring_spot(randi() % CreatureNest.DANCERS)
			who.state = Villager.State.GO_CIRCLE
			claim(town, "circle")
			who._held_post = "circle"
		"pray":
			# A RING ROUND THE TOTEM, NOT A HEAP ON IT. This was a six-metre box,
			# so every idle soul in a town of two hundred converged on the same
			# spot and stood in each other — which is the crowd in the middle of
			# the city, and it was never a crowd of people strolling.
			#
			# A ring sized by how many are already at it: a dozen worshippers
			# stand close about the post, a hundred make a congregation you can
			# see the shape of.
			var faithful := maxi(town.job_counts().get("pray", 0), 1)
			var round_it := PRAY_RING + sqrt(float(faithful)) * PRAY_PER_HEAD
			var turn := randf() * TAU
			who._target = town.totem.global_position + Vector3(
				cos(turn), 0.0, sin(turn)) * randf_range(round_it * 0.45, round_it)
			who.state = Villager.State.GO_WORSHIP
		"home":
			who._target = who.home.global_position \
				+ Vector3(randf_range(-3.5, 3.5), 0, randf_range(-3.5, 3.5))
			who.state = Villager.State.WANDER
			who._action_time = randf_range(8.0, 18.0)   # a long sit, not a lap
		_:
			# POTTERING STARTS WHERE YOU ARE. It used to pick a point somewhere
			# in the town's ring and walk straight at it, which is a commute and
			# not a potter. See Stroll, which is legs and pauses from here.
			who.state = Villager.State.WANDER
			Stroll.begin(who)


## One of the weighted options.
static func _drawn(draw: Dictionary) -> String:
	var total := 0.0
	for key: String in draw:
		total += float(draw[key])
	var roll := randf() * total
	for key: String in draw:
		roll -= float(draw[key])
		if roll <= 0.0:
			return key
	return "potter"
