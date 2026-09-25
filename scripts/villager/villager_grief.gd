class_name VillagerGrief
extends RefCounted
## WHAT A VILLAGER DOES OVER THE DEAD: weeps over a person, cuts up a beast.
##
## Moved out of villager.gd, which has to keep room for the next thing a
## villager learns to do. Each step returns true when the villager should take
## up a new plan — the villager's own arm asks for it, where tools/stuck.py can
## see the way out.

## HOW LONG THEY STAND OVER A BODY AND WEEP, in seconds.
##
## A death in this game was a line of text and a corpse nobody looked at. The
## village hive registered it, the god was told, and every soul in the place
## carried on hauling stone past their neighbour lying in the road. Grief that
## nothing DOES is not grief, it is bookkeeping.
##
## Long enough to be a thing you notice happening from across the square, short
## enough that a bad week does not stop the harvest. Crowding does the rest: the
## job board already docks a job by how many are at it (see CROWD_PENALTY), so
## two or three go and the rest keep working, which is what a funeral looks like.
const MOURN_SECONDS := 14.0
## WHAT IT DOES TO SOMEBODY to look up from their dead and find them being
## eaten, and how often a mourner checks, in physics frames.
##
## HIGH ON THE SCALE AND NOT OFF IT. `witness_horror` takes MORALITY, because in
## this game atrocity hardens whoever sees it — and a villager under
## VillagerFeeding.WICKED eats bodies before the granary. A weight big enough to
## tip a decent mourner under that line in one sighting would send them from
## weeping over the dead to eating them, which is a spiral nobody asked for.
## Six sits beside the worst things a village already sees (see Village).
const HORROR_OF_IT := 6.0
const HORROR_EVERY := 12
## How long a beast takes to cut up where it fell.
const SKIN_SECONDS := 4.0


## ONE FRAME OF STANDING OVER A BODY.
static func mourn(who: Villager, delta: float) -> bool:
	who._apply_gravity_only(delta)
	who._action_time -= delta
	# OPENLY. Every couple of seconds, at a volume that carries about as far as
	# the body does — meant to be heard by somebody standing in the square, not
	# across the valley. See SoundBank.
	who._work_noise("weep", 2.3, delta)
	# THE BODY MAY BE TAKEN WHILE THEY ARE STILL AT IT: a god lifts it, a
	# creature eats it, the decay timer runs out. Then they get up.
	if not is_instance_valid(who._target_corpse):
		who._target_corpse = null
		return true
	# AND IF SOMEBODY KNEELS DOWN BESIDE THEM AND BEGINS TO EAT, they do not go
	# on sobbing. Asked a few times a second rather than every tick — there are
	# only ever a few mourners, but two hundred villagers to ask about. They
	# run, and running is its own plan: this does not ask for another.
	if Engine.get_physics_frames() % HORROR_EVERY == 0 \
			and VillagerSearch.being_eaten(who.get_tree(), who._target_corpse, true):
		who.witness_horror(HORROR_OF_IT)
		who.scare(who._target_corpse.global_position)
		who._target_corpse = null
		return false
	if who._action_time > 0.0:
		return false
	# WHAT IT LEAVES BEHIND. Grief costs happiness and is not supposed to be
	# free — but standing with your dead is the decent thing, and a person who
	# does it comes away a little better than they went in.
	who.happiness = maxf(who.happiness - 12.0, 0.0)
	who.morality = minf(who.morality + 3.0, 100.0)
	if who.village != null:
		who.village.hive.witness("death", who.global_position, 0.5)
	who._target_corpse = null
	return true


## ONE FRAME OF CUTTING UP A BEAST. The joints it came to when it is done, or -1
## while there is still work in it — the villager shoulders them itself.
static func skin(who: Villager, delta: float) -> int:
	who._apply_gravity_only(delta)
	who._action_time -= delta
	who._work_noise("saw", 1.1, delta)
	if who._action_time > 0.0:
		return -1
	var joints := 0
	if is_instance_valid(who._target_carcass):
		var beast := who._target_carcass.species
		joints = who._target_carcass.butcher()
		who._carry_announce = "%s butchered a %s." % [who.villager_name, beast]
	who._target_carcass = null
	return joints
