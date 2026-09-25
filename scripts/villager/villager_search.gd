class_name VillagerSearch
extends RefCounted
## WHO GOES TO WHICH ONE.
##
## Every "find me the nearest X" a villager asks, in one place. They are pure
## readings of the world from where somebody is standing — no state is kept, no
## decision is made — which is what lets them live outside villager.gd, a file
## that has to keep room for a villager to do something NEW.
##
## TWO RULES RUN THROUGH ALL OF THEM.
##
## NOBODY WALKS INTO THE WATER FOR ANYTHING. Every candidate that is in reach is
## asked `would_drown_at` — and ONLY the ones in reach, last, after the distance.
## It is two or three reads of the terrain noise, and it used to be asked of
## every tree in the loaded world before the distance threw most of them away:
## one woodcutter choosing a tree was hundreds of reads, and a busy frame of
## decisions was ten thousand of them. See tools/sweeps.py. A joint of meat floating in a lake used to take the
## whole town in after it, one at a time, each drowning where the last one did.
##
## AND THE NEAREST IS NOT THE ANSWER. If it were, every idle hand in the village
## would set off for the same tree — so each of these keeps the nearest FEW and
## the asker takes the one its own instance id points at. Same question, same
## world, different answers, and nobody had to be told about anybody else. See
## `_consider` and `_my_pick`.

## How many of the nearest are kept to choose between. Eight: enough that a
## crowd spreads out, few enough that nobody walks past six good trees.
const SPREAD_CHOICES := 8


## THE EDGE OF THE NEAREST WATER, for a fisherman. Probes outward in rings and
## stops a little short of the wet — the spot returned is dry ground you can
## stand on and cast from, not the lake itself.
static func shore(who: Villager) -> Vector3:
	var world := who._world()
	if world == null:
		return Vector3.INF
	for dist: float in [10.0, 20.0, 35.0, 50.0]:
		for i in 8:
			var angle := TAU * i / 8.0 + randf() * 0.3
			var probe := who.global_position + Vector3(cos(angle), 0, sin(angle)) * dist
			if world.is_underwater(probe.x, probe.z):
				var spot := who.global_position + (probe - who.global_position) * 0.85
				spot.y = world.height_at(spot.x, spot.z)
				return spot
	return Vector3.INF


static func forage(who: Villager) -> ForageBush:
	var best: ForageBush = null
	var best_dist := INF
	for b in who.get_tree().get_nodes_in_group("forage"):
		var bush := b as ForageBush
		if not is_instance_valid(bush) or not bush.has_berries():
			continue
		var d := who.global_position.distance_to(bush.global_position)
		if d < best_dist and d < who.village.influence_radius * 2.0 \
				and not who.would_drown_at(bush.global_position):
			best_dist = d
			best = bush
	return best


static func tamable(who: Villager) -> Animal:
	var best: Array = []
	var reach := who.village.influence_radius * 2.0
	for a in who.get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		if not is_instance_valid(animal) or not animal.is_tamable():
			continue
		# A beast standing in deep water is a beast that is drowning, and
		# nobody is gentling it.
		var d := who.global_position.distance_to(animal.global_position)
		if d < reach \
				and not who.would_drown_at(animal.global_position):
			_consider(best, animal, d)
	return _my_pick(who, best) as Animal


## THE NEAREST HUMAN DEAD — for a butcher on the cannibal diet, and for anybody
## who simply wants to stand over them and weep. See Villager.State.MOURNING:
## the same list answers both, because "where are the dead" is one question
## however differently two towns answer it.
##
## `spare_the_eaten` is the mourner asking. Nobody goes to weep over a body that
## somebody is already down on — see `being_eaten`. The eater does NOT ask it:
## several of them down over the same person at once is the darkest thing in
## this game and VillagerFeeding says why it is meant to be possible.
static func corpse(who: Villager, spare_the_eaten := false) -> Corpse:
	var best: Array = []
	var reach := who.village.influence_radius * 1.5
	for c in who.get_tree().get_nodes_in_group("corpses"):
		var body := c as Corpse
		if not is_instance_valid(body) or body.is_queued_for_deletion():
			continue
		if spare_the_eaten and being_eaten(who.get_tree(), body):
			continue
		# The drowned are left where they are. Somebody who went in after the
		# meat and did not come out is not a reason for the next one to go.
		var d := who.global_position.distance_to(body.global_position)
		if d < reach \
				and not who.would_drown_at(body.global_position):
			_consider(best, body, d)
	return _my_pick(who, best) as Corpse


## IS SOMEBODY EATING THIS ONE? `at_it` asks whether they are down on it NOW,
## rather than merely on their way — which is the difference between a mourner
## who never sets out and one who looks up to find it happening beside them.
##
## "A decent man sobbing over the man who is simultaneously being eaten.
## Positively awkward." It was: two unrelated jobs, each perfectly sensible on
## its own, pointed at the same body by two people who could not see each other.
static func being_eaten(tree: SceneTree, body: Corpse, at_it := false) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	for v in tree.get_nodes_in_group("villagers"):
		var other := v as Villager
		if other == null or not is_instance_valid(other) or other.feeding_on != body:
			continue
		if not at_it or other.state == Villager.State.EATING:
			return true
	return false


## IS SOMEBODY STANDING OVER THIS ONE, WEEPING? Present, not on their way —
## what shames an eater is a face, not an intention. See VillagerFeeding.shamed.
static func being_mourned(tree: SceneTree, body: Corpse) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	for v in tree.get_nodes_in_group("villagers"):
		var other := v as Villager
		if other != null and is_instance_valid(other) \
				and other.state == Villager.State.MOURNING and other._target_corpse == body:
			return true
	return false


## THE NEAREST BEAST'S BODY, for a butcher. A carcass is free meat with the
## killing already done — see Carcass, which falls apart into joints on its own
## if nobody comes for it.
static func carcass(who: Villager) -> Carcass:
	var best: Array = []
	var reach := who.village.influence_radius * 2.0
	# `beast`, not `body`: tools/check_calls.py reads a name once per file,
	# and `corpse` above calls its Corpse `body`.
	for c in who.get_tree().get_nodes_in_group("carcasses"):
		var beast := c as Carcass
		if not is_instance_valid(beast) or beast.is_queued_for_deletion():
			continue
		# Nothing burnt. A charred beast feeds nobody, and sending a butcher out
		# to one is sending them on an errand the world has already spoiled.
		if beast.is_spoiled():
			continue
		var d := who.global_position.distance_to(beast.global_position)
		if d < reach \
				and not who.would_drown_at(beast.global_position):
			_consider(best, beast, d)
	return _my_pick(who, best) as Carcass


static func heathen(who: Villager) -> Village:
	var best: Village = null
	var closest := Villager.MISSION_RANGE
	for v in who.get_tree().get_nodes_in_group("village"):
		var town := v as Village
		if not is_instance_valid(town) or town == who.village or town.converted:
			continue
		var gap := town.global_position.distance_to(who.global_position)
		if gap < closest:
			closest = gap
			best = town
	return best


static func damaged_house(who: Villager) -> House:
	for h in who.village.houses:
		if is_instance_valid(h) and h.needs_repair():
			return h
	return null


static func in_group(who: Villager, group: String, max_dist: float) -> Node3D:
	var best: Array = []
	for n in who.get_tree().get_nodes_in_group(group):
		var node := n as Node3D
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is WildTree and ((node as WildTree).is_felled() \
				or (node as WildTree).is_held() or (node as WildTree).burning):
			continue
		var d := who.global_position.distance_to(node.global_position)
		if d < max_dist \
				and not who.would_drown_at(node.global_position):
			_consider(best, node, d)
	return _my_pick(who, best)


## Keep this one if it is among the nearest few, in order. A short insertion
## rather than a sort, because the list is eight long and the candidates can be
## every tree in every loaded chunk.
static func _consider(best: Array, node: Node3D, d: float) -> void:
	var at := best.size()
	while at > 0 and d < float(best[at - 1][0]):
		at -= 1
	if at >= SPREAD_CHOICES:
		return
	best.insert(at, [d, node])
	if best.size() > SPREAD_CHOICES:
		best.resize(SPREAD_CHOICES)


## This villager's own choice from the nearest few. The rank comes from its
## instance id, which is unique, stable for its whole life, and needs asking
## nobody.
static func _my_pick(who: Villager, best: Array) -> Node3D:
	if best.is_empty():
		return null
	return best[int(who.get_instance_id()) % best.size()][1] as Node3D
