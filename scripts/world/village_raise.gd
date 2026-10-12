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
## Hands put to work a frame, by the charter. Each is about a tenth.
const HANDS_A_FRAME := 20


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
	var settling := Ledger.swap(&"Village:founding", "its roll and its reach")
	town._assign_housing()                # the roll counted, so the reach is theirs
	town._update_influence()
	Ledger.resume(settling)
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
	# ITS TRADES, a building a frame — each asks where it may stand.
	var trades: Dictionary = record.get("trades", {})
	for which: String in trades:
		if not Workshop.TRADES.has(which):
			continue
		for i in maxi(int(trades[which]) - Workshop.how_many(town, which), 0):
			var one := Ledger.swap(&"Village:founding", "one of its trades")
			var stood := town._raise_trade(which, world)
			Ledger.resume(one)
			if not stood or not await _next_frame(town):
				break
		if not town.is_inside_tree():
			return
	# ITS SCHOOL, on a sliced search like a house's.
	if bool(record.get("edubba", false)) and not town.has_edubba():
		var school := town._build_search(world, Village.ROOM_ROUND_THE_SCHOOL)
		if not await town._search_slowly(school):
			return
		town._raise_school(town._searched(school))
		if not await _next_frame(town):
			return
	# THE REST, A PIECE A FRAME, each named on the meter. It was one frame —
	# "the rest of it" — and on a PC it once stood at three quarters of a
	# second without saying which part. Nothing is searched for here: what the
	# steps above could not place is not asked about again in one frame
	# (`_as_placed`), and is only said.
	var clock := Ledger.swap(&"Village:founding", "its stock and its rock")
	town._rebuild(_as_placed(town, record))
	Ledger.resume(clock)
	if not await _next_frame(town):
		return
	clock = Ledger.swap(&"Village:founding", "its roll")
	town._finish_restoring()
	town._refresh_roster()
	town._retally()
	Ledger.resume(clock)
	if not await _next_frame(town):
		return
	clock = Ledger.swap(&"Village:founding", "its herds and woods")
	Chessboard.write_back(record, world)     # what its hunting and felling left
	Ledger.resume(clock)
	# AND TO WORK, a few hands a frame: every one dealt before the town runs.
	town.charter = await VillageCharter.deal_slowly(town, HANDS_A_FRAME)
	if not town.is_inside_tree():
		return
	var opening := Ledger.swap(&"Village:founding", "switched on")
	town.founded = true
	town.process_mode = was
	Ledger.resume(opening)


## THE RECORD AS FAR AS THE STEPS ABOVE GOT: houses, fields, trades and the
## school as they now stand, so `_rebuild` builds none of them again in one
## frame — a search that finds no room is the slowest one there is. What would
## not fit is said, as `_rebuild` says it.
static func _as_placed(town: Village, record: Dictionary) -> Dictionary:
	var placed := record.duplicate()
	var houses: Array = record.get("houses", [])
	placed["houses"] = houses.slice(0, mini(houses.size(), town.houses.size()))
	placed["farms"] = mini(int(record.get("farms", 0)), town.farms.size())
	placed["edubba"] = town.has_edubba()
	var trades := {}
	var wanted: Dictionary = record.get("trades", {})
	for which: String in wanted:
		trades[which] = mini(int(wanted[which]), Workshop.how_many(town, which))
	placed["trades"] = trades
	if town.houses.size() < houses.size() or town.farms.size() < int(record.get("farms", 0)):
		push_warning(("%s wanted %d house(s) and %d field(s) back and could place %d and %d "
			+ "— no room for the rest.") % [town.village_name, houses.size(),
				int(record.get("farms", 0)), town.houses.size(), town.farms.size()])
	return placed


static func _next_frame(town: Village) -> bool:
	await town.get_tree().process_frame
	return town.is_inside_tree()
