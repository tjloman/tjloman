class_name VillageFeud
extends RefCounted
## WHAT A TOWN LEARNS FROM BURYING ITS OWN, and how long it remembers.
##
## The village already had `resolve` — a single number for whether these people
## stand or bar their doors, learned from how fights went. That is doctrine, and
## it is the right shape for doctrine, but it cannot hold a GRUDGE: it says
## nothing about WHO. A town that has lost three people to the same pack does
## not become 12% braver in general. It becomes a town that hunts wolves.
##
## So this holds two things and nothing else:
##
##   THE MAULINGS UNDER WAY. Every person currently on the ground with the jaws
##   on them. While that list is not empty the town is OUTRAGED, and outrage is
##   what makes an ordinary villager who would have run pick up a spear instead
##   (Militia.dares_fight). The list is ticked here because a mauling belongs to
##   none of the three parties in it — see Mauling.
##
##   THE OATHS. How many souls each species has taken, and when the town swore
##   on it. Once sworn: every one of them within the bounds is hunted, by
##   everybody, on sight, and they hit harder doing it.
##
## THE OATH OUTLIVES THE FIGHT, and dies with the people who swore it. It is
## kept for a lifetime and then let go — not decayed steadily, which would make
## it a mood, but held whole and then gone, because that is what it is: the
## generation that watched it happen, and then that generation being dead.

## Souls lost to one species before the town swears on it.
const SWEAR_AT := 3
## And how long the oath stands: one long human life. Nobody who swore it is
## alive at the end of that, and the town is simply a town with wolves nearby
## again. See GameState.game_years.
const FORGET_YEARS := 70.0

## How much harder a sworn town's blows land. They are not stronger; they have
## done this before, they know where to stand, and they do not hesitate.
const WRATH := 1.6
## And a taste of it from the FIRST death, before any oath: "if they kill a man,
## nearby villagers can start killing wolves with good success."
const BLOODED_WRATH := 1.25

## How near a mauling has to be to put the steel in somebody. Outrage is a thing
## you can see and hear, not a village-wide statistic.
const OUTRAGE_REACH := 30.0

## Every wolf killed pays a little of the debt back. The oath does not end this
## way — only time ends it — but a town that is winning stops counting its dead
## quite so loudly, and this is what keeps a long war from running forever at
## full pitch on three deaths from an hour ago.
const AVENGED_WORTH := 0.34

var maulings: Array[Mauling] = []
var blood := {}       # species -> souls it has taken from us (fractional: see avenged)
var sworn_at := {}    # species -> the game year the oath was sworn


## THE JAWS CLOSE on one of ours. Finds the mauling already under way on this
## person, or starts one — a second wolf must join the first, not open a rival
## pin on the same body.
func seize(prey: Villager, beast: Animal) -> void:
	if prey.pin != null:
		prey.pin.bite(beast)
		return
	var pin := Mauling.new()
	pin.victim = prey
	maulings.append(pin)
	prey.pinned_by(pin)
	pin.bite(beast)
	var town := prey.village
	if town != null and is_instance_valid(town):
		# On the blood list at once, so the militia knows who to go for without
		# waiting for anybody to die first.
		town.mark_for_death(beast)
		if town.is_player_home:
			GameState.announce("%s is down — %ss have them!" % [prey.villager_name, beast.species])


func tick(delta: float) -> void:
	for i in range(maulings.size() - 1, -1, -1):
		if not maulings[i].tick(delta):
			maulings.remove_at(i)


## Is somebody being eaten alive within sight of this spot? The one thing that
## overrides a villager's arithmetic about whether to fight.
func outraged(near: Vector3) -> bool:
	for pin in maulings:
		if pin.victim != null and is_instance_valid(pin.victim) \
				and pin.victim.global_position.distance_to(near) < OUTRAGE_REACH:
			return true
	return false


## A soul lost to this species. This is where a town's opinion of wolves is
## written, and it is written in the only ink that ever writes one.
func blooded(species: String) -> void:
	if species == "":
		return
	var count: float = float(blood.get(species, 0.0)) + 1.0
	blood[species] = count
	if count >= float(SWEAR_AT) and not sworn_at.has(species):
		sworn_at[species] = GameState.game_years
		GameState.announce("They have buried three to the %ss. This village will hunt them now, "
			% species + "every one it sees, for as long as anyone remembers why.")


## A beast of this species killed. Pays down a little of the debt.
func avenged(species: String) -> void:
	if not blood.has(species):
		return
	blood[species] = maxf(float(blood[species]) - AVENGED_WORTH, 0.0)


## Does the town hunt this species on sight? Oaths lapse with the generation
## that swore them, and this is where that is noticed.
func is_sworn(species: String) -> bool:
	if not sworn_at.has(species):
		return false
	if GameState.game_years - float(sworn_at[species]) > FORGET_YEARS:
		sworn_at.erase(species)
		blood.erase(species)
		return false
	return true


## The multiplier on a blow struck against this species.
func wrath(species: String) -> float:
	if is_sworn(species):
		return WRATH
	if float(blood.get(species, 0.0)) >= 1.0:
		return BLOODED_WRATH
	return 1.0


## For the village hover text — a town with an oath on its books should say so.
func report() -> String:
	var said: Array[String] = []
	for species: String in sworn_at.keys():
		if is_sworn(species):
			said.append("sworn against %ss" % species)
	if not maulings.is_empty():
		said.append("ONE OF OURS IS DOWN")
	return ", ".join(said)


func to_dict() -> Dictionary:
	return {"blood": blood.duplicate(), "sworn_at": sworn_at.duplicate()}


func from_dict(data: Dictionary) -> void:
	blood = data.get("blood", {}).duplicate()
	sworn_at = data.get("sworn_at", {}).duplicate()
