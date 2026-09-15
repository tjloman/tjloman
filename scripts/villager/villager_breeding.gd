class_name VillagerBreeding
extends RefCounted
## WHO HAS A CHILD, AND WHEN.
##
## Lifted out of Villager, which lives permanently on its line limit, and lifted
## as a subject rather than as a spare part: courting, conceiving and the child
## already at the breast are one question asked in three places, and they were
## three methods far apart in a file with no room for the comment below.
##
## THE COMMENT BELOW IS THE REASON IT MOVED. `conceive` is the most expensive
## thing in a crowded village and it had no business being — see `ROLL FIRST`.

## A CHILD OF MINE STILL AT THE BREAST, and no school to mind it. This walks
## every soul in the village, which is why nothing calls it on a whim.
static func dependent_child(who: Villager) -> bool:
	if who.village.has_edubba():
		return false
	for v in who.village.my_villagers():
		if v.mother == who and v.age < Villager.WEANED_AGE:
			return true
	return false


## Interest reawakens at adulthood and stays high while the body is fed and
## rested — but a mother won't conceive again while a child still trails her
## (they must be grown or gone to school first).
static func wants_to(who: Villager) -> bool:
	if not who.is_adult() or who.pregnant or who.age > 45.0:
		return false
	if who._breed_cooldown > 0.0:
		return false
	if who.hunger > 55.0 or who.energy < 35.0 or who.happiness < 45.0:
		return false
	if who.village.store.total_food() < 4 or who.village.at_capacity():
		return false
	if who.is_teacher:
		return false
	return not dependent_child(who)


## ROLL FIRST, AND THE ORDER IS THE WHOLE OF IT.
##
## The questions here are not expensive on their own. They are expensive SIXTY
## AT A TIME, EVERY FRAME, which is exactly the shape a village takes when it
## gathers at the totem: this runs from State.WORSHIPPING, so a town at prayer
## was a town where every woman in it walked the entire roster twice a frame to
## find out whether she had a child at the breast.
##
## `at_capacity` counts the population and the beds — and `population` walks the
## roster. `dependent_child` walks it again. Two hundred people with sixty of
## them praying is some tens of thousands of operations a frame, spent on a roll
## that comes up once every few minutes.
##
## That is the hitch when a town crowds round its totem, and it is NOT a
## decision problem: the Spool already bounds decisions to a fixed number a
## frame and always did. This was never in the queue at all.
##
## The roll rejects better than a thousand to one and costs one `randf()`.
## Nothing about the outcome changes — a candidate who fails a precondition
## still fails it, just after a die she was always going to be allowed to throw.
static func conceive(who: Villager, delta: float) -> void:
	if not who.is_female or who.pregnant or not who.is_adult() or who.age > 45.0:
		return
	# Untended villages barely grow; tended ones quicken (see conception_chance).
	if randf() > who.village.conception_chance() * delta:
		return
	if who.happiness < 45.0 or who.village.store.total_food() < 4:
		return
	# Shelter bounds the flock, and a mother finishes one child first.
	if who.village.at_capacity() or dependent_child(who):
		return
	_with_whoever_came(who)


## A PARTNER WHO CAME TO THE TOTEM FOR THE SAME REASON. Courting AND
## worshipping both count: insisting the man be mid-worship at the exact instant
## of the roll was a coincidence the pair could rarely manage.
static func _with_whoever_came(who: Villager) -> void:
	for other in who.village.my_villagers():
		if other == who or other.is_female or not other.is_adult():
			continue
		if other.state != Villager.State.WORSHIPPING \
				and other.state != Villager.State.COURT:
			continue
		if other.happiness < 40.0 or other.age > 55.0:
			continue
		if who.global_position.distance_to(other.global_position) < 7.0:
			who.pregnant = true
			who.pregnancy_progress = 0.0
			who._breed_cooldown = 30.0
			if who.village.is_player_home:
				GameState.announce("%s and %s are expecting a child."
					% [who.villager_name, other.villager_name])
			return
