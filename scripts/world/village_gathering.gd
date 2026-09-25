class_name VillageGathering
extends RefCounted
## WHERE A TOWN GATHERS WHEN IT IS NOT WORKING.
##
## Everything that brought people together went to the totem: worship when they
## were lonely, the homeless bedding down, and the evening dance went to the one
## nest. In a town of four hundred that is a hundred and fifty people standing
## on one patch of dirt, every one of them looking at every other — and that
## looking is what a crowd costs. Villagers do not collide with one another
## (their mask skips their own layer), so the bill is not the physics solver: it
## is script, each of them greeting, murmuring and steering round a hundred
## neighbours instead of five.
##
## So a town gathers ALL OVER ITSELF: at its shrines, at the nest, and round its
## own front doors, with the totem kept for the few. Nobody counts heads — with
## a point at every house in the town, a weighted draw spreads a crowd as evenly
## as counting would, for nothing.

## HOW LIKELY EACH KIND OF PLACE IS, against one another. The totem is the rare
## one on purpose; a doorstep is the commonest, because there are the most of
## them and because that is where people actually sit out in the evening.
const TOTEM := 1.0
const NEST := 3.0
const SHRINE := 3.0
const DOORSTEP := 4.0

## How far out from each kind of place people stand. A house is walked round at
## its own eaves; see `_around`.
const TOTEM_RING := 4.5
const SHRINE_RING := 3.2
const DOORSTEP_BEYOND := 1.6


## WHERE THIS ONE GOES. `at` is where they stand; `mid` is what they stand
## round — a dancer circles it and faces it.
static func spot(town: Village, who: Villager) -> Dictionary:
	# BY KIND FIRST, THEN WHICH ONE. Weighted per PLACE, every shrine a town
	# raised added another share against one doorstep, and a town of four
	# shrines sent two thirds of its evening to them — the crowd moved, it did
	# not spread. tools/gathering.py measured it.
	var shrines: Array[Vector3] = []
	for w in town.workshops:
		if is_instance_valid(w) and w.trade == "shrine":
			shrines.append(w.global_position)
	var kinds: Array = []   # [weight, kind]
	if town.totem != null:
		kinds.append([TOTEM, "totem"])
	if town.nest != null and is_instance_valid(town.nest):
		kinds.append([NEST, "nest"])
	if not shrines.is_empty():
		kinds.append([SHRINE, "shrine"])
	var door := _a_door(town, who)
	if door != null:
		kinds.append([DOORSTEP, "door"])
	var kind := "totem"
	var total := 0.0
	for k in kinds:
		total += float(k[0])
	var roll := randf() * total
	for k in kinds:
		roll -= float(k[0])
		if roll <= 0.0:
			kind = String(k[1])
			break
	var mid := who.global_position
	var ring := TOTEM_RING
	match kind:
		"totem":
			if town.totem != null:
				mid = town.totem.global_position
		"nest":
			mid = town.nest.global_position
			ring = CreatureNest.RING
		"shrine":
			mid = shrines[randi() % shrines.size()]
			ring = SHRINE_RING
		"door":
			mid = door.global_position
			ring = _around(door)
	var a := randf() * TAU
	return {"at": mid + Vector3(cos(a), 0.0, sin(a)) * ring, "mid": mid}


## THEIR OWN DOOR if they have one, and a neighbour's otherwise — the homeless
## sit out on somebody's step, not in the square. Null if the town has no roof.
static func _a_door(town: Village, who: Villager) -> House:
	# Untyped until proved alive: a house in the town's list may have burnt.
	var kept: Variant = who.home
	if kept == null or not is_instance_valid(kept):
		kept = town.houses[randi() % town.houses.size()] if not town.houses.is_empty() else null
	if kept == null or not is_instance_valid(kept):
		return null
	var door := kept as House
	return null if door.under_construction else door


## Stood round a house at its eaves, however long the house is.
static func _around(house: House) -> float:
	var w: float = House.SPECS[house.size]["width"]
	var deep := w * (1.6 if house.size == House.Size.LONGHOUSE else 1.0)
	return maxf(w, deep) * 0.5 + DOORSTEP_BEYOND
