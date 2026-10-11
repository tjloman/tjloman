class_name VillageRaise
extends RefCounted
## A REMEMBERED TOWN, RAISED A FEW PIECES A FRAME.
##
## A town coming back into sight used to be founded first — founders, houses,
## the lot, raised in stages for a town that never existed — and then, the
## frame its founding finished, have its record laid over it in ONE go: the
## founders freed, every house it had placed, every field, and every one of its
## people raised. Three hundred souls and fifty houses was a quarter of a second
## headless and most of a second on a PC (tools/live/unfold_cost.gd), and two
## big towns coming into sight together froze the game for two.
##
## Now a town raised from its record (WorldGen.raise_record sets
## `from_memory`) skips the founding it would throw away, and is put back
## straight from the record, as the founding is: its people a few a frame, then
## its roofs and fields a frame each on a sliced search for ground, then the
## rest. It is held still until it stands, as a founding is.

## People raised a frame. Each is about half a millisecond.
const PEOPLE_A_FRAME := 6


static func found(town: Village) -> void:
	var was := town.process_mode
	town.process_mode = Node.PROCESS_MODE_DISABLED
	var world := town.get_tree().get_first_node_in_group("world_gen") as WorldGen
	var rock := town._build_search(world, Village.ROOM_ROUND_THE_QUARRY)
	if not await town._search_slowly(rock):
		return
	town._place_quarry(town._searched(rock))
	var record := SaveGame.take_back(town, false)
	if record.is_empty():
		town._found_in_stages()           # nothing remembered here after all
		return
	town._take_fields(record)
	# PEOPLE, THEN ROOFS: the reach the builder lays out within is the reach of
	# a town this many strong.
	var folk: Array = record.get("folk", [])
	for i in folk.size():
		var one := Ledger.swap(&"Village:founding", "one of its people")
		town._restore_villager(folk[i])
		Ledger.resume(one)
		if i % PEOPLE_A_FRAME == PEOPLE_A_FRAME - 1 and not await _next_frame(town):
			return
	town._assign_housing()                # the roll counted, so the reach is theirs
	town._update_influence()
	for size in record.get("houses", []):
		var search := town._build_search(world, town._house_room(int(size) as House.Size))
		if not await town._search_slowly(search):
			return
		if town._raise_founding_house(town._searched(search), int(size) as House.Size) < 0:
			break
		if not await _next_frame(town):
			return
	for i in range(town.farms.size(), int(record.get("farms", 0))):
		var search := town._build_search(world, Village.ROOM_ROUND_A_FARM)
		if not await town._search_slowly(search):
			return
		var spot := town._searched(search)
		if spot == Vector3.INF:
			break
		town.spawn_farm_at(spot)
		if not await _next_frame(town):
			return
	# THE REST — its trades, its school, its stock, its rock — and nothing of
	# what is already up is built twice: the rebuild builds UP TO the counts.
	var clock := Ledger.swap(&"Village:founding", "the rest of it")
	town._rebuild(record)
	town._finish_restoring()
	Chessboard.write_back(record, world)     # the herds and woods, as it stands
	town._open_for_business()
	Ledger.resume(clock)
	town.process_mode = was


static func _next_frame(town: Village) -> bool:
	await town.get_tree().process_frame
	return town.is_inside_tree()
