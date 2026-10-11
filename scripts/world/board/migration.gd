class_name Migration
extends RefCounted
## THE ROAD BETWEEN TOWNS. People a town cannot house or feed leave it, and go
## where there is room; a town short of food, timber or stone sends a few out
## with what it has spare, to a town that wants it and has the other spare, and
## they swap and walk home. Neither is a number moving from one ledger to
## another: it is a BAND, and a band WALKS. It sets off together, at the pace of
## people carrying their lives and their children, and it takes as long to
## arrive as the road is long.
##
## A band is a record (SaveGame.bands): who is in it, by name, where it is going
## and where it stands now. Out of sight that is all it is. In loaded land, with
## either end of its road standing, it is real villagers walking (Migrant;
## Chessboard raises and folds them), because every villager in a loaded chunk
## is real.
##
## RUINS NEITHER SEND NOR RECEIVE. A town in ruin is in survival mode: its few
## may not even know other towns exist, and they feel safer among the stones.
## And nobody goes where they have never heard of: a town knows of the towns
## within KNOWS_OF of it, and past that is the unknown.
##
## RAIDS, ONE DAY: when there is another god, or another player, a band can go
## out armed to take what it wants rather than trade for it. Left for then:
##
##     static func _raid(from: Dictionary, prey: Dictionary) -> void:
##         # a band of the hardened (TownBook.hardiness), sent where the larder
##         # is fullest and the guard thinnest; what it takes, it carries home,
##         # and what it costs is the grudge (Village.grudge) and the dead.
##         pass

## A band sets off when this many are ready to go together — people prefer to
## go in company — or once the first of them has waited WAITS_YEARS for it.
const BAND_LEAST := 4
const WAITS_YEARS := 3.0
## How far a town knows of other towns, in metres.
const KNOWS_OF := 600.0
## A band's pace, metres a second of game time: a family on foot with what it owns.
const PACE := 1.2
## TRADE: how many go, what each carries, the least worth the walk, and how often
## a town sends a party, in game years.
const TRADERS := 4
const CARRIES := 12
const TRADE_LEAST := 8
const TRADE_EVERY := 3.0
## A live town sends at most one band to settle elsewhere this often.
const SETTLE_EVERY := 1.0
## How long a live band musters before it sets off with whoever has come.
const MUSTER := 20.0
## The goods a town trades in, and what it keeps of each before any is spare.
const GOODS: Array[String] = ["food", "lumber", "stone"]

## The villagers walking with each band in loaded land: band id -> Array.
static var walkers := {}
static var _next := 1


## THE ROUND: who sets off — to live elsewhere, or to trade. Called by the
## Chessboard every few seconds.
static func go_round(tree: SceneTree, now: float) -> void:
	var towns := towns_of(tree)
	for town: Dictionary in towns:
		if town["ruined"]:
			continue
		if town["record"] != null:
			_send_from_record(town, towns, now)
		else:
			_send_from_live(town, towns, now)
		_trade_from(town, towns, now)


## THE BANDS AS A SAVE KEEPS THEM: those walking in sight written down as the
## people they are, without stopping them walking.
static func to_save() -> Array:
	var out := []
	for band: Dictionary in SaveGame.bands:
		var kept := band.duplicate(true)
		for one in walkers.get(band["id"], []):
			if is_instance_valid(one):
				(kept["folk"] as Array).append(Migrant.entry_of(one as Villager))
		out.append(kept)
	return out


## EVERY TOWN, standing or remembered, as the same few numbers.
static func towns_of(tree: SceneTree) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in tree.get_nodes_in_group("village"):
		var town := node as Village
		if not is_instance_valid(town) or not town.founded or not is_instance_valid(town.store):
			continue
		var souls := town.population()
		out.append({"node": town, "record": null, "name": town.village_name,
			"pos": Vector2(town.global_position.x, town.global_position.z), "souls": souls,
			"room": town.housing_capacity() + TownRules.CROWDS_IN - souls,
			"ruined": town.houses.is_empty() and souls <= TownFold.RUIN_MOST,
			"food": town.store.total_food(), "lumber": town.store.lumber, "stone": town.store.stone})
	for record: Dictionary in SaveGame.village_memory:
		var at: Array = record.get("pos", [])
		if at.size() < 2 or bool(record.get("home", false)):
			continue
		var board: Dictionary = record.get("board", {})
		var book := TownBook.new()
		book.houses = (record.get("houses", []) as Array).duplicate()
		var souls := (record.get("folk", []) as Array).size()
		var store: Dictionary = record.get("store", {})
		out.append({"node": null, "record": record, "name": String(record.get("name", "")),
			"pos": Vector2(float(at[0]), float(at[1])), "souls": souls,
			"room": book.beds() + TownRules.CROWDS_IN - souls,
			"ruined": bool(board.get("ruined", book.houses.is_empty() and souls <= TownFold.RUIN_MOST)),
			"food": int(store.get("plant", 0)) + int(store.get("meat", 0)),
			"lumber": int(store.get("lumber", 0)), "stone": int(store.get("stone", 0))})
	for town: Dictionary in out:
		town["fed"] = clampf(float(town["food"]) / maxf(float(town["souls"]) * TownRules.EAT_HEAD, 1.0),
			0.0, 1.0)
	return out


## WHERE A BAND OF `many` FROM `from` GOES: the town it knows of with the most
## room and the most to eat, nearer counting for more. Empty if there is none.
static func choose(from: Dictionary, towns: Array, many: int) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for town: Dictionary in towns:
		var far := (town["pos"] as Vector2).distance_to(from["pos"])
		if town["name"] == from["name"] or town["ruined"] or far > KNOWS_OF \
				or int(town["room"]) < many or float(town["fed"]) < 0.6:
			continue
		var score := float(town["room"]) * float(town["fed"]) / (1.0 + far / 150.0)
		if score > best_score:
			best_score = score
			best = town
	return best


## A BAND, setting out from `from` with `folk` (records) for `to`.
static func band_of(kind: String, from: Dictionary, to: Dictionary, folk: Array, now: float) -> Dictionary:
	var at: Vector2 = from["pos"]
	var going: Vector2 = to.get("pos", at + Vector2.from_angle(randf() * TAU) * KNOWS_OF * 1.5)
	var band := {"id": _next, "kind": kind, "from": from["name"], "from_pos": [at.x, at.y],
		"to": to.get("name", ""), "to_pos": [going.x, going.y], "pos": [at.x, at.y],
		"folk": folk, "names": folk.map(func(one): return String(one.get("name", ""))),
		"goods": {}, "back": false, "set_off": true, "muster": MUSTER, "since": now}
	# Numbered past every band already on the road, saved ones included.
	for other: Dictionary in SaveGame.bands:
		_next = maxi(_next, int(other["id"]) + 1)
	band["id"] = _next
	_next += 1
	SaveGame.bands.append(band)
	return band


## ON THE ROAD: `seconds` of game time walked. True on arriving.
static func advance(band: Dictionary, seconds: float) -> bool:
	if not band["set_off"]:
		return false
	var at := Vector2(float(band["pos"][0]), float(band["pos"][1]))
	var going := Vector2(float(band["to_pos"][0]), float(band["to_pos"][1]))
	var step := PACE * seconds
	if at.distance_to(going) <= step:
		band["pos"] = [going.x, going.y]
		return true
	at = at.move_toward(going, step)
	band["pos"] = [at.x, at.y]
	return false


## ARRIVED: settled, traded or home. True when the band is over.
static func arrive(band: Dictionary, tree: SceneTree, now: float) -> bool:
	var towns := towns_of(tree)
	var here := _town_named(towns, String(band["to"]), band["to_pos"])
	if band["kind"] == "trade":
		if not band["back"]:
			if not here.is_empty():
				_swap(band, here)
			band["back"] = true
			band["to"] = band["from"]
			band["to_pos"] = band["from_pos"]
			return false
		if here.is_empty():
			band["kind"] = "settle"               # home is gone: they go where there is room
			return _redirect(band, towns, now)
		for good: String in band["goods"]:
			_give(here, good, int(band["goods"][good]))
		_take_in(band, here, "")
		return true
	if String(band["to"]) == "":
		_free_walkers(band)                         # into the unknown
		return true
	if here.is_empty() or int(here["room"]) < _many(band) or here["ruined"]:
		return _redirect(band, towns, now)
	_take_in(band, here, "%d came from %s to live here." % [_many(band), band["from"]])
	return true


## AND ALL OF THEM INTO THE TOWN THEY CAME TO: the walking ones, the written ones.
static func _take_in(band: Dictionary, town: Dictionary, line: String) -> void:
	var at := Vector2(float(band["pos"][0]), float(band["pos"][1]))
	if town["node"] != null:
		var node := town["node"] as Village
		for one in walkers.get(band["id"], []):
			if is_instance_valid(one):
				Migrant.arrive(one as Villager, node)
		var ground := Vector3(at.x, node.global_position.y, at.y)
		for one: Dictionary in band["folk"]:
			Migrant.arrive(Migrant.raise(one, node, ground, band), node)
		if line != "":
			node.board["arrived"] = float(node.board.get("arrived", 0.0)) + float(_many(band))
			if node.is_player_home:
				GameState.announce(line.replace("live here", "live in %s" % node.village_name))
	else:
		var record: Dictionary = town["record"]
		var folk: Array = record.get("folk", [])
		folk.append_array(band["folk"])
		record["folk"] = folk
		if line != "":
			var book := TownBook.from_dict(record.get("board", {}))
			book.arrived += float(_many(band))
			book.note(line)
			record["board"] = book.to_dict()
	walkers.erase(band["id"])
	band["folk"] = []


static func _redirect(band: Dictionary, towns: Array, now: float) -> bool:
	var at := Vector2(float(band["pos"][0]), float(band["pos"][1]))
	var to := choose({"name": band["to"], "pos": at}, towns, _many(band))
	var going: Vector2 = to.get("pos", at + Vector2.from_angle(randf() * TAU) * KNOWS_OF * 1.5)
	band["to"] = to.get("name", "")
	band["to_pos"] = [going.x, going.y]
	band["since"] = now
	return false


## WHAT THEY SWAP: everything they carried for as much of what they came for as
## the town can spare, one for one.
static func _swap(band: Dictionary, town: Dictionary) -> void:
	var brought: Dictionary = band["goods"]
	var wanted := String(band.get("wants", ""))
	var worth := 0
	for good: String in brought:
		worth += int(brought[good])
		_give(town, good, int(brought[good]))
	var got := _take(town, wanted, mini(worth, maxi(-int(_needs(town)[wanted]), 0)))
	band["goods"] = {wanted: got}


## A TOWN WITH PEOPLE IT CANNOT KEEP, out of sight: they set off together once
## enough are ready, or once the first has waited long enough.
static func _send_from_record(town: Dictionary, towns: Array, now: float) -> void:
	var record: Dictionary = town["record"]
	var out: Array = record.get("setting_out", [])
	if out.is_empty():
		return
	if not record.has("out_since"):
		record["out_since"] = now
	if out.size() < BAND_LEAST and now - float(record["out_since"]) < WAITS_YEARS:
		return
	band_of("settle", town, choose(town, towns, out.size()), out, now)
	record["setting_out"] = []
	record.erase("out_since")


## A STANDING TOWN WITH MORE PEOPLE THAN IT CAN SLEEP OR FEED: the ones with
## no roof, and idle, muster at the totem and go together.
static func _send_from_live(town: Dictionary, towns: Array, now: float) -> void:
	var node := town["node"] as Village
	if now - float(node.get_meta("sent_at", -INF)) < SETTLE_EVERY:
		return
	var over := -int(town["room"])
	var starving := 0
	for who: Villager in node.my_villagers():
		if who.is_adult() and who.hunger > 70.0:
			starving += 1
	var hungry := float(town["fed"]) <= 0.0 and starving * 2 > node.population()
	@warning_ignore("integer_division")
	var many := over if over >= BAND_LEAST else (node.population() / 4 if hungry else 0)
	if many < BAND_LEAST:
		return
	# The ones with no roof first.
	var going := _idle(node)
	going.sort_custom(func(a, b): return a.home == null and b.home != null)
	going = going.slice(0, mini(many, 12))
	if going.size() < BAND_LEAST:
		return
	var to := choose(town, towns, going.size())
	_send_live(node, band_of("settle", town, to, [], now), going)
	node.set_meta("sent_at", now)
	node.board["left"] = float(node.board.get("left", 0.0)) + float(going.size())
	if node.is_player_home:
		GameState.announce("%d of %s set out for %s." % [going.size(), node.village_name,
			String(to.get("name", "lands nobody here has seen"))])


## SENT FROM A STANDING TOWN: they muster at its totem, and set off together.
static func _send_live(node: Village, band: Dictionary, going: Array) -> void:
	band["set_off"] = false
	var totem := node.totem.global_position if is_instance_valid(node.totem) else node.global_position
	band["pos"] = [totem.x, totem.z]
	band["names"] = going.map(func(v): return v.villager_name)
	walkers[band["id"]] = going
	for who: Villager in going:
		Migrant.enlist(who, band)


## TRADE: a town sends a party with what it has spare, to a town it knows of that
## wants it and has spare what this town wants.
static func _trade_from(town: Dictionary, towns: Array, now: float) -> void:
	var last := float(town["record"].get("traded_at", -INF)) if town["record"] != null \
		else float((town["node"] as Village).get_meta("traded_at", -INF))
	if now - last < TRADE_EVERY or _trading(town["name"]):
		return
	var needs := _needs(town)
	var wanted := ""
	for good: String in GOODS:
		if needs[good] > 0 and (wanted == "" or needs[good] > needs[wanted]):
			wanted = good
	if wanted == "":
		return
	for other: Dictionary in towns:
		if other["name"] == town["name"] or other["ruined"] \
				or (other["pos"] as Vector2).distance_to(town["pos"]) > KNOWS_OF:
			continue
		var theirs := _needs(other)
		if theirs[wanted] >= 0:
			continue                              # none of it to spare
		for good: String in GOODS:
			var deal := mini(mini(-needs[good], theirs[good]), TRADERS * CARRIES)
			if good != wanted and deal >= TRADE_LEAST:
				_send_traders(town, other, good, deal, wanted, now)
				return


static func _send_traders(town: Dictionary, other: Dictionary, good: String, deal: int,
		wanted: String, now: float) -> void:
	if town["node"] != null:
		var node := town["node"] as Village
		var hands := _idle(node).slice(0, TRADERS)
		if hands.size() < TRADERS:
			return
		var party := band_of("trade", town, other, [], now)
		party["goods"] = {good: _take(town, good, deal)}
		party["wants"] = wanted
		_send_live(node, party, hands)
		node.set_meta("traded_at", now)
		return
	var record: Dictionary = town["record"]
	var folk: Array = record.get("folk", [])
	var grown := []
	for one: Dictionary in folk:
		var age := float(one.get("age", 0.0))
		if age >= TownRules.CHILD_YEARS and age < TownRules.CHILD_YEARS + TownRules.ADULT_YEARS:
			grown.append(one)
	if grown.size() < TRADERS * 3:
		return                                    # too few to spare four for the road
	var going := grown.slice(0, TRADERS)
	for one: Dictionary in going:
		folk.erase(one)
	var band := band_of("trade", town, other, going, now)
	band["goods"] = {good: _take(town, good, deal)}
	band["wants"] = wanted
	record["traded_at"] = now


## WHAT A TOWN WANTS, good by good: more than nothing is short by that much,
## less than nothing is that much spare. Food against two years' eating (half
## as much again before any is spare); timber and stone against the next few
## longhouses (TownRules.MATERIAL_BUILDS).
static func _needs(town: Dictionary) -> Dictionary:
	var eat := float(town["souls"]) * TownRules.EAT_HEAD * TownRules.RESERVE_YEARS
	var build := House.SPECS[House.Size.LONGHOUSE] as Dictionary
	var keeps := {"food": eat, "lumber": float(build["lumber"]) * TownRules.MATERIAL_BUILDS,
		"stone": float(build["stone"]) * TownRules.MATERIAL_BUILDS}
	var out := {}
	for good: String in GOODS:
		var has := float(town[good])
		out[good] = roundi(keeps[good] - has) if has < keeps[good] \
			else -roundi(maxf(has - keeps[good] * 1.5, 0.0))
	return out


static func _take(town: Dictionary, good: String, many: int) -> int:
	if many <= 0 or good == "":
		return 0
	if town["node"] != null:
		var store := (town["node"] as Village).store
		match good:
			"food":
				var grain := store.take(FoodItem.FoodType.PLANT, many)
				return grain + store.take(FoodItem.FoodType.MEAT, many - grain)
			"lumber":
				var timber := mini(many, store.lumber)
				return timber if store.try_spend_materials(timber, 0) else 0
			"stone":
				var rock := mini(many, store.stone)
				return rock if store.try_spend_materials(0, rock) else 0
		return 0
	var kept: Dictionary = (town["record"] as Dictionary).get("store", {})
	var got := 0
	for key: String in (["plant", "meat"] if good == "food" else [good]):
		var here := mini(many - got, int(kept.get(key, 0)))
		kept[key] = int(kept.get(key, 0)) - here
		got += here
	town["record"]["store"] = kept
	return got


static func _give(town: Dictionary, good: String, many: int) -> void:
	if many <= 0:
		return
	if town["node"] != null:
		var store := (town["node"] as Village).store
		match good:
			"food": store.add(FoodItem.FoodType.PLANT, many)
			"lumber": store.add_lumber(many)
			"stone": store.add_stone(many)
		return
	var kept: Dictionary = (town["record"] as Dictionary).get("store", {})
	var key := "plant" if good == "food" else good
	kept[key] = int(kept.get(key, 0)) + many
	town["record"]["store"] = kept


## Grown, and doing nothing that would be left half-done.
static func _idle(node: Village) -> Array:
	var out := []
	for who: Villager in node.my_villagers():
		if who.is_adult() and (who.state == Villager.State.WANDER or who.state == Villager.State.PLAY):
			out.append(who)
	return out


static func _trading(town_name: String) -> bool:
	for band: Dictionary in SaveGame.bands:
		if band["kind"] == "trade" and band["from"] == town_name:
			return true
	return false


static func _many(band: Dictionary) -> int:
	return (band["folk"] as Array).size() + (walkers.get(band["id"], []) as Array).size()


static func _town_named(towns: Array, town_name: String, at: Array) -> Dictionary:
	var spot := Vector2(float(at[0]), float(at[1]))
	for town: Dictionary in towns:
		if town["name"] == town_name and (town["pos"] as Vector2).distance_to(spot) < SaveGame.SAME_TOWN:
			return town
	return {}


static func _free_walkers(band: Dictionary) -> void:
	for one in walkers.get(band["id"], []):
		if is_instance_valid(one):
			(one as Node).queue_free()
	walkers.erase(band["id"])
