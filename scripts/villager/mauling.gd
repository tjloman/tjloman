class_name Mauling
extends RefCounted
## THIRTY SECONDS ON THE GROUND.
##
## A wolf used to take a bite worth twenty health out of somebody and walk away
## to look for the next one. Five wolves therefore killed five villagers in the
## time it takes to cross a field — an alpha strike, one soul at a time, against
## which a village has no move at all. By the time the alarm was up the dead
## were already dead, and the militia mustered over bodies. A big pack was not a
## threat the town could answer; it was weather.
##
## A pack does not eat like that. It pulls ONE down and worries it, and that is
## the better part of a minute with the whole pack committed, standing still, in
## the middle of a village full of people who now know exactly where they are.
## That is the window the village never had: half a minute in which the wolves
## are a target rather than an event.
##
## Everything a village can do about wolves hangs off this one object.
##
##   - While it exists the town is OUTRAGED (VillageFeud.outraged), which is
##     what gives a villager who would otherwise run the nerve to pick up a
##     spear and come. A neighbour being eaten is not a fight you calculate.
##   - The pinners go on the blood list the moment the jaws close, so the
##     militia already knows who to go for.
##   - Getting there IN TIME matters, and how much time is left is legible from
##     across the field: the longer they are held the less of them gets up.
##   - And how it ENDS teaches the village its doctrine about this species for
##     as long as anyone who saw it is alive. See VillageFeud.
##
## The mauling is ticked by the VILLAGE, not by either animal — one pin is one
## event shared by a victim, a pack and a town, and none of the three owns it.

## How long one set of jaws needs to finish somebody.
const KILL_SECONDS := 30.0
## Each extra mouth past the first hurries it along by this share, to a cap. A
## pack IS faster than a lone wolf — but never so much faster that the thirty
## seconds stop being the thing the village is racing.
const PACK_HASTE := 0.06
const HASTE_MOST := 0.35
## Past this many, the rest are just circling: there is only so much room at a
## throat. Set so that HASTE_MOST actually BINDS — at six extra mouths the cap
## is what is holding the pace down, not this. A ceiling that can never be
## reached is not a ceiling, it is a comment.
const JAWS_MOST := 8

## WHAT THEY GET UP AT if somebody reaches them: nearly whole in the first
## seconds, barely alive at the end. This is the reward for a fast militia and
## the whole reason the alarm is worth answering at a run.
const RISE_BEST := 75.0
const RISE_WORST := 10.0

## A pinner further off than this has let go — driven back, dead, distracted,
## or lifted away by a divine hand.
const HOLD_WITHIN := 3.2

## How often the victim screams, and how far a scream carries. Every scream is
## a fresh alarm, so a long mauling keeps pulling in help from further out as
## the first wave arrives.
const SCREAM_EVERY := 2.2
const CRY_REACH := 26.0


var victim: Villager = null
var jaws: Array[Animal] = []
## 0..KILL_SECONDS. Not wall-clock: a bigger pack spends it faster.
var worry := 0.0

var _since_cry := SCREAM_EVERY   # so the first tick screams


## THE JAWS CLOSE. Routed through the town because the town is what has to
## answer it — and because a second wolf arriving must find the mauling that is
## already under way rather than start a rival one.
static func seize(prey: Villager, beast: Animal) -> void:
	if prey == null or not is_instance_valid(prey) or prey.is_dying():
		return
	if ChildSafety.spared(prey):
		return    # no child is pinned — see ChildSafety.spared
	if prey.village == null or not is_instance_valid(prey.village):
		return
	prey.village.feud.seize(prey, beast)


## This node is leaving the world, or the hand has taken it: whatever it was
## holding or held by, it is out of it now.
static func free_of(node: Node) -> void:
	if node is Villager:
		var who := node as Villager
		if who.pin != null:
			who.pin.finish(false)
	elif node is Animal:
		var beast := node as Animal
		if beast.pinning != null and is_instance_valid(beast.pinning) \
				and beast.pinning.pin != null:
			beast.pinning.pin.let_go(beast)


## Another mouth on the same person.
func bite(beast: Animal) -> void:
	if beast == null or not is_instance_valid(beast) or jaws.has(beast):
		return
	jaws.append(beast)
	beast.hold_down(victim)


## One set of jaws off — driven back, killed, or gone. The last one off ends it.
func let_go(beast: Animal) -> void:
	jaws.erase(beast)
	if is_instance_valid(beast):
		beast.release_hold()
	if jaws.is_empty():
		finish(false)


## How fast this is going, in seconds of worry per second of clock.
func pace() -> float:
	var mouths := mini(jaws.size(), JAWS_MOST)
	return 1.0 + minf(float(maxi(mouths - 1, 0)) * PACK_HASTE, HASTE_MOST)


## What is left of them if they are pulled out right now.
func rise_health() -> float:
	return lerpf(RISE_BEST, RISE_WORST, clampf(worry / KILL_SECONDS, 0.0, 1.0))


## How far through, 0..1 — for the readout over their head, so a player can see
## at a glance whether it is worth sending the hand.
func gone() -> float:
	return clampf(worry / KILL_SECONDS, 0.0, 1.0)


## Runs on the village's clock. False once this is over and the village should
## forget it.
func worry_at(delta: float) -> bool:
	if victim == null or not is_instance_valid(victim) or victim.is_queued_for_deletion():
		_let_all_go()
		return false
	# Anything that wandered, died or was lifted off is no longer holding.
	Util.prune(jaws)
	for i in range(jaws.size() - 1, -1, -1):
		var beast := jaws[i]
		if beast.is_queued_for_deletion() \
				or beast.global_position.distance_to(victim.global_position) > HOLD_WITHIN:
			beast.release_hold()
			jaws.remove_at(i)
	if jaws.is_empty():
		finish(false)
		return false
	worry += pace() * delta
	if worry >= KILL_SECONDS:
		finish(true)
		return false
	_cry(delta)
	return true


## THE SCREAMING, which is the whole of the victim's own contribution. It is a
## fresh alarm every couple of seconds: the militia is not summoned once, it is
## summoned continuously for as long as this goes on, so help that was too far
## away at the start is not too far away at the end.
func _cry(delta: float) -> void:
	_since_cry += delta
	if _since_cry < SCREAM_EVERY:
		return
	_since_cry = 0.0
	SoundBank.play_at("screech", victim.global_position, -2.0)
	var town := victim.village
	if town == null or not is_instance_valid(town):
		return
	town.raise_alarm(victim.global_position)
	Militia.rally(victim, CRY_REACH)


## OVER, one way or the other.
func finish(killed: bool) -> void:
	var who := victim
	var town: Village = null
	var species := ""
	if not jaws.is_empty() and is_instance_valid(jaws[0]):
		species = jaws[0].species
	if who != null and is_instance_valid(who):
		town = who.village
	_let_all_go()
	victim = null
	if who == null or not is_instance_valid(who):
		return
	who.pin = null
	if killed:
		# The pack eats. One kill feeds all of them, which is why they committed
		# to it — and it is the moment the village's doctrine is written.
		for beast in jaws:
			if is_instance_valid(beast):
				beast.hunger = maxf(beast.hunger - 60.0, 0.0)
		# THEY GO DOWN DYING, not dead. Ten more seconds in which a heal, or a
		# hand, can still make this a story about somebody who lived — and the
		# town swears its oath over a BURIAL, so a man pulled back from there
		# costs the wolves nothing. See Villager.die.
		if not jaws.is_empty() and is_instance_valid(jaws[0]):
			who.hurt_by(jaws[0], who.health + 1.0)
		else:
			who.take_damage(who.health + 1.0)
		if town != null and is_instance_valid(town) and town.is_player_home:
			GameState.announce("The %ss have finished with %s."
				% [species, who.villager_name])
	else:
		who.pulled_free(rise_health())
	jaws.clear()


func _let_all_go() -> void:
	for beast in jaws:
		if is_instance_valid(beast):
			beast.release_hold()
