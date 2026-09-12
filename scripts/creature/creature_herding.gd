class_name CreatureHerding
extends RefCounted
## WHAT A CREATURE CAN DO WITH A HERD, none of which it knows to begin with.
##
## A herd is the richest thing in the world to have an opinion about. It feeds a
## village, it feeds wolves, it can be driven home, harvested, stood guard over,
## or simply pulled apart for the pleasure of it. So it is offered as SEVERAL
## DIFFERENT DEEDS and the creature is told nothing whatever about any of them.
##
## NOTHING HERE IS A RULE ABOUT WHEN. Every deed goes on the ballot whenever a
## herd is close enough to be among, and which one a creature reaches for is
## settled by the same four things that settle everything else it does: what it
## has learned the deed is worth, what its character makes palatable, what it
## believes about circumstances like these, and what you have praised or scolded
## it for. A creature that has never been rewarded for driving cattle will not
## drive cattle, however many cattle it walks through.
##
## AND IT HAS TO GET GOOD AT THEM, which is the other half. A beast that has
## never driven anything scatters a herd across a hillside: the herd panics, the
## village is no better fed, and the attempt teaches it that shepherding is
## miserable work — unless you were there to say otherwise. Only practice makes
## the deed actually WORK, and only its working makes it pay. That is the
## difference between a creature that herds because you raised it to and one
## that herds because a rule fired when it saw a herd.

## How close counts as being among them. Measured from the edge of the mass
## rather than its heart, or a two-hundred-head herd could be stood in the
## middle of and still not noticed.
const AMONG := 9.0

## HOW OFTEN A DRIVE COMES OFF, at no skill and at the top of the climb. The
## floor is deliberately not zero: a hopeless creature must succeed occasionally
## or it can never learn that the deed is worth anything, and the whole thing
## dies in its first minute.
## What one beast's worth of meat is, as a meal. The creature eats in these
## until it has had enough or the carcass is done.
const MEAL_UNITS := 1.0

const DRIVE_WORST := 0.18
const DRIVE_BEST := 0.94

## How far one good drive moves the herd's pasture toward where it is wanted.
const DRIVE_STEP := 16.0

## What a botched drive does. A scattered herd is a frightened herd, and a
## frightened herd does not calve — so a clumsy shepherd costs the village more
## than it knows.
const SCATTER_FEAR := 0.30

## Standing watch. Worth little each time and it calms them, which is the whole
## of what a guard actually does for a herd.
const GUARD_CALM := 0.26

## A herd will not be culled below this; you cannot eat the last of something.
const SPARE := 6

## WHAT EACH DEED PAYS THE CREATURE, and what it costs your standing. These are
## the OUTCOMES of deeds that came off, not preferences — a creature only ever
## meets these numbers after it has already decided to try.
const WORTH := {
	"shepherd": {"reward": 0.95, "karma": 0.55},
	"cull": {"reward": 0.75, "karma": 0.10},
	"guard": {"reward": 0.45, "karma": 0.45},
}


## The herd it is standing in, if any.
static func nearest(who: Creature) -> Herd:
	var best: Herd = null
	var closest := INF
	for h in who.get_tree().get_nodes_in_group("herds"):
		var herd := h as Herd
		if not is_instance_valid(herd) or herd.alive() <= 0:
			continue
		var gap := herd.global_position.distance_to(who.global_position) - herd.spread()
		if gap < closest and gap < AMONG:
			closest = gap
			best = herd
	return best


## Everything it could do about the herd it is standing in. All of it goes on
## the ballot; none of it is recommended.
static func offer(who: Creature, opts: Dictionary) -> void:
	var herd := nearest(who)
	if herd == null:
		return
	who.offer_option(opts, "shepherd", "herd", herd)
	who.offer_option(opts, "guard", "herd", herd)
	# Not a rule about appetite — a fact about the herd. There is no taking one
	# when there is barely a herd left to take it from.
	if herd.alive() > SPARE:
		who.offer_option(opts, "cull", "herd", herd)


## Do it, and teach the creature from HOW IT WENT rather than from what it
## meant. A drive that scattered the herd is a bad memory of shepherding even
## though shepherding is a kindness, which is exactly the point: the creature
## has to get good at a thing before the thing starts being worth doing.
static func go(who: Creature, verb: String, herd: Herd) -> void:
	if herd == null or not is_instance_valid(herd):
		return
	var reward := 0.0
	match verb:
		"shepherd":
			reward = _drive(who, herd)
		"cull":
			reward = _cull(who, herd)
		"guard":
			reward = _guard(who, herd)
		_:
			return
	who.mind.reinforce(reward)


## DRIVING THEM. The one deed where skill plainly shows, because a failure is
## not nothing happening — it is the herd going everywhere at once.
static func _drive(who: Creature, herd: Herd) -> float:
	var odds := lerpf(DRIVE_WORST, DRIVE_BEST, who.mind.knack("shepherd"))
	var came_off := randf() < odds
	who.mind.practise("shepherd", came_off)
	if not came_off:
		herd.scattered(SCATTER_FEAR)
		GameState.announce(GameState.named(
			"Your creature went at the %s and they scattered." % herd.species))
		return -0.45
	var home := _where_wanted(who, herd)
	herd.drive_toward(home, DRIVE_STEP)
	_pay("shepherd")
	GameState.announce(GameState.named(
		"Your creature drove the %s toward the village." % herd.species))
	return float(WORTH["shepherd"]["reward"])


## TAKING ONE FOR THE TABLE. Skill here is the difference between a clean kill
## and a chase that frightens the whole herd for nothing.
static func _cull(who: Creature, herd: Herd) -> float:
	var odds := lerpf(DRIVE_WORST, DRIVE_BEST, who.mind.knack("cull"))
	var came_off := randf() < odds
	who.mind.practise("cull", came_off)
	if not came_off:
		herd.scattered(SCATTER_FEAR * 0.7)
		return -0.3
	var meat: int = int(Animal.SPECIES[herd.species].get("meat", 1))
	herd.take_one()
	# IT EATS FIRST, IF IT IS HUNGRY. Every kill went straight into the granary
	# and the creature got a lesson and nothing else — so the one deed that
	# connects it to the herds could not feed it, and a beast that hunted well
	# all night starved doing it. An animal that brings down prey eats; what it
	# does not need is what it carries home, and carrying it home is what makes
	# it a creature of the village rather than a wolf.
	var ate := 0
	while ate < meat and who.hungry_enough() and who.can_swallow(MEAL_UNITS):
		who.feed_on(MEAL_UNITS)
		ate += 1
	var left := meat - ate
	var store := CreatureEyes.nearest_store(who.get_tree(), who.global_position)
	if store != null and left > 0:
		store.add(FoodItem.FoodType.MEAT, left)
	if ate > 0 and left > 0:
		GameState.announce(GameState.named(
			"Your creature brought down a %s, ate its fill, and carried the rest home."
			% herd.species))
	elif ate > 0:
		GameState.announce(GameState.named(
			"Your creature brought down a %s and ate." % herd.species))
	elif store != null:
		GameState.announce(GameState.named(
			"Your creature brought down a %s for the stores." % herd.species))
	_pay("cull")
	return float(WORTH["cull"]["reward"])


## STANDING WITH THEM. Nothing dramatic — it settles them, which is exactly what
## a guard is for, and it is the only one of the three that cannot go wrong.
static func _guard(who: Creature, herd: Herd) -> float:
	who.mind.practise("guard", true)
	herd.calmed(GUARD_CALM * (0.5 + who.mind.knack("guard")))
	_pay("guard")
	return float(WORTH["guard"]["reward"])


## What the village makes of it. Kept in one place so a deed's standing with
## people is never quietly different from one call site to the next.
static func _pay(verb: String) -> void:
	var karma: float = float(WORTH[verb]["karma"])
	if not is_zero_approx(karma):
		GameState.shift_alignment(karma)


## WHERE A DRIVEN HERD IS BEING DRIVEN TO — the granary, because that is what
## driving a herd is FOR as far as a village is concerned. With no store in
## reach there is nowhere in particular to put them, and the herd is simply
## pushed away from the creature, which is the other thing driving means.
static func _where_wanted(who: Creature, herd: Herd) -> Vector3:
	var store := CreatureEyes.nearest_store(who.get_tree(), who.global_position, 220.0)
	if store != null and is_instance_valid(store):
		return store.global_position
	var away := herd.global_position - who.global_position
	away.y = 0.0
	if away.length() < 0.5:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	return herd.global_position + away.normalized() * DRIVE_STEP
