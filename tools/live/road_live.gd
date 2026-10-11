extends SceneTree
## THE ROAD BETWEEN TOWNS — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/road_live.gd
##
##   1. a town out of sight is stepped by the board, not frozen until it is seen,
##      quietly — its history is told once, for all the years, when it is seen;
##   2. those its numbers send away leave BY NAME, and are not told as dead;
##   3. they wait for company and set off as a band, for the town they know of
##      with room and food; never for a ruin, and a ruin sends nobody;
##   4. a band walks, and on arriving its people are that town's, by name;
##   5. a town short of timber trades its spare food with one that has timber
##      spare: the traders go, swap, come home, and are home again;
##   6. a standing town with more people than roofs sends the roofless: they
##      leave its roll, muster at the totem and set off together, as villagers;
##   7. out of loaded land a walking band is folded back into its record, the
##      same people; and a band coming into loaded land to a standing town is
##      real villagers, who join it when they arrive;
##   8. a save keeps the bands, walkers written down by name.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

## Where the records of this test stand: far from home, out of sight.
const FAR := Vector2(3000.0, 3000.0)

var fails := 0
var road: Script
var saves: Node
var state: Node


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	state = root.get_node("/root/GameState")
	saves = root.get_node("/root/SaveGame")
	road = load("res://scripts/world/board/migration.gd")
	var fold: Script = load("res://scripts/world/board/town_fold.gd")
	var lands: Script = load("res://scripts/world/board/town_land.gd")
	var main: Node = current_scene
	var home: Node = main.village
	saves.village_memory.clear()
	saves.bands.clear()
	print("THE ROAD")
	var now: float = state.game_years

	# 1. Stepped out of sight.
	var behind := _record("Lagwick", FAR + Vector2(-500.0, 0.0), 20, 6, 300)
	behind["at_years"] = now - 3.0
	# The land read as a fold reads it: the board steps a town on the land it has.
	behind["land"] = lands.read(main.world_gen, Vector3(behind["pos"][0], 0.0, behind["pos"][1])).to_dict()
	saves.village_memory.append(behind)
	await seconds(9.0)
	check(float(behind["at_years"]) > now - 1.0, "a town out of sight is stepped by the board (%.1f years behind)"
		% (now - float(behind["at_years"])))
	var lines: Array = (behind["board"].get("chronicle", []) as Array).map(func(line): return String(line[1]))
	check(not lines.any(func(line): return line.contains("years passed")),
		"stepped out of sight, it writes nothing in its history yet (%d lines)" % lines.size())
	saves.village_memory.erase(behind)
	fold.catch_up(behind, lands.from_dict(behind["land"]), 7, float(state.game_years) + 0.5)
	lines = (behind["board"].get("chronicle", []) as Array).map(func(line): return String(line[1]))
	var told_once: Array = lines.filter(func(line): return line.contains("years passed"))
	check(told_once.size() == 1 and told_once[0].begins_with("3 years passed"),
		"and brought back, it tells all the years away, once (%s)" % str(told_once))

	# 2. Leaving by name: a town of sixty with roofs for ten, caught up five years.
	var crowded := _record("Crushby", FAR + Vector2(0.0, -400.0), 60, 1, 300)
	crowded["land"] = behind["land"]
	var had: Array = (crowded["folk"] as Array).map(func(one): return one["name"])
	fold.catch_up(crowded, lands.from_dict(crowded["land"]),
		7, float(crowded["at_years"]) + 5.0)
	var out: Array = crowded.get("setting_out", [])
	var told := "\n".join((crowded["board"]["chronicle"] as Array).map(func(line): return String(line[1])))
	check(not out.is_empty() and out.all(func(one): return had.has(one["name"])),
		"those its numbers send away are its own people, by name (%d)" % out.size())
	check(out.all(func(one): return not told.contains(String(one["name"]) + " (")),
		"and they are not told as dead")

	# 3. A band, for the town with room — never the ruin.
	var crowd := _record("Packham", FAR, 30, 1, 200)
	crowd["setting_out"] = (crowd["folk"] as Array).slice(0, 5)
	for one in crowd["setting_out"]:
		(crowd["folk"] as Array).erase(one)
	var roomy := _record("Roomford", FAR + Vector2(200.0, 0.0), 10, 8, 400)
	var ruin := _record("Ashstead", FAR + Vector2(60.0, 0.0), 6, 0, 50)
	ruin["board"]["ruined"] = true            # roofs to spare, nearer: still not
	ruin["houses"] = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
	ruin["setting_out"] = (ruin["folk"] as Array).slice(0, 4)
	saves.village_memory.append_array([crowd, roomy, ruin])
	road.go_round(self, now)
	var band := _band_from("Packham")
	check(not band.is_empty() and band["to"] == "Roomford" and (band["folk"] as Array).size() == 5,
		"five ready to go set off as a band, for the town with room (%s)" % band.get("to", "none"))
	check(_band_from("Ashstead").is_empty(), "a ruin sends nobody, and nobody goes to one")
	var walkers_names: Array = band.get("names", [])

	# 4. It walks, and arrives.
	var started: Array = band.get("pos", [0, 0])
	road.advance(band, 10.0)
	check(Vector2(float(band["pos"][0]), float(band["pos"][1])).distance_to(
		Vector2(float(started[0]), float(started[1]))) > 5.0, "a band walks: ten seconds, twelve metres on")
	band["pos"] = [roomy["pos"][0] - 2.0, roomy["pos"][1]]
	await seconds(2.0)
	var folk_names: Array = (roomy["folk"] as Array).map(func(one): return one["name"])
	check(not saves.bands.has(band) and walkers_names.all(func(n): return folk_names.has(n)),
		"arrived, its people are Roomford's, by name")
	check(float(roomy["board"].get("arrived", 0.0)) >= 5.0, "and Roomford's history says they came")

	# 5. Trade: food spare, timber short; timber spare, food short.
	var granary := _record("Granby", FAR + Vector2(0.0, 300.0), 30, 6, 500)
	granary["store"]["lumber"] = 0
	var timber := _record("Timberton", FAR + Vector2(150.0, 300.0), 30, 6, 0)
	timber["store"]["lumber"] = 400
	saves.village_memory.append_array([granary, timber])
	var souls_before: int = (granary["folk"] as Array).size()
	road.go_round(self, now)
	var party := _band_from("Granby", "trade")
	check(not party.is_empty() and party["kind"] == "trade" and party["to"] == "Timberton"
		and int(party["goods"].get("food", 0)) > 0, "a town short of timber sends traders with its spare food (%s)"
		% str(party.get("goods", {})))
	check((granary["folk"] as Array).size() == souls_before - road.TRADERS, "and they are away from it")
	party["pos"] = [timber["pos"][0] - 1.0, timber["pos"][1]]
	await seconds(1.0)
	check(party["back"] and int(party["goods"].get("lumber", 0)) > 0, "they swap it for timber (%s)"
		% str(party.get("goods", {})))
	var swapped: int = int(party["goods"].get("lumber", 0))
	party["pos"] = [granary["pos"][0] + 1.0, granary["pos"][1]]
	await seconds(1.0)
	check(not saves.bands.has(party) and int(granary["store"]["lumber"]) == swapped
		and (granary["folk"] as Array).size() == souls_before, "and come home with it, all of them")

	# 6. A standing town with more people than roofs.
	var town: Node = home
	var room_before: int = town.my_villagers().size()
	for house in town.houses:
		house.under_construction = true          # no beds to sleep in
	saves.village_memory.append(_record("Spareham", Vector2(town.global_position.x + 250.0,
		town.global_position.z), 8, 10, 500))
	road.go_round(self, state.game_years)
	var leaving := _band_from(town.village_name)
	var walking: Array = road.walkers.get(leaving.get("id", -1), [])
	check(not leaving.is_empty() and walking.size() >= road.BAND_LEAST,
		"a standing town with more people than roofs sends some away (%d)" % walking.size())
	check(walking.all(func(w): return not w.journey.is_empty()) \
		and town.my_villagers().size() == room_before - walking.size(), "they leave its roll (%d to %d)"
		% [room_before, town.my_villagers().size()])
	for house in town.houses:
		house.under_construction = false
	await seconds(25.0)
	check(leaving.get("set_off", false), "they muster, and set off together")
	var moved: float = Vector2(float(leaving["pos"][0]), float(leaving["pos"][1])).distance_to(
		Vector2(town.totem.global_position.x, town.totem.global_position.z))
	check(moved > 1.0, "walking (%.0f m from the totem)" % moved)

	# 7. Out of loaded land, folded: the same people.
	var names_walking: Array = walking.map(func(w): return w.villager_name)
	leaving["pos"] = [FAR.x + 900.0, FAR.y + 900.0]
	await seconds(6.0)
	var written: Array = (leaving["folk"] as Array).map(func(one): return one["name"])
	check(not road.walkers.has(leaving["id"]) and names_walking.all(func(n): return written.has(n)),
		"out of loaded land a band is its record again, the same people (%d)" % written.size())
	# And one coming in, to home.
	var coming: Dictionary = road.band_of("settle", {"name": "Farholt", "pos": Vector2(town.global_position.x + 30.0,
		town.global_position.z)}, {"name": town.village_name, "pos": Vector2(town.global_position.x,
		town.global_position.z)}, [_person("Wenna", 30.0), _person("Odo", 28.0), _person("Brisk", 9.0)], now)
	await seconds(6.0)
	var raised: Array = road.walkers.get(coming["id"], [])
	check(raised.size() == 3, "coming into loaded land to a standing town, a band is villagers walking (%d)"
		% raised.size())
	# 8. Saved, the walkers written down by name without stopping them.
	var saved: Array = JSON.parse_string(JSON.stringify(road.to_save()))
	var kept := false
	for b: Dictionary in saved:
		if int(b["id"]) == int(coming["id"]):
			kept = ["Wenna", "Odo", "Brisk"].all(func(n): return (b["folk"] as Array).any(
				func(one): return one["name"] == n))
	check(kept and (coming["folk"] as Array).is_empty(), "a save keeps the bands, walkers by name")
	await seconds(30.0)
	var folk_now: Array = town.my_villagers().map(func(v): return v.villager_name)
	print("    the band coming in: %s, at %s, %d walking, %d written" % ["on the road" if saves.bands.has(coming)
		else "arrived", str(coming["pos"]), (road.walkers.get(coming["id"], []) as Array).size(),
		(coming["folk"] as Array).size()])
	print("    missing: %s" % str(["Wenna", "Odo", "Brisk"].filter(func(n): return not folk_now.has(n))))
	# (A child with no family in the town is taken in "to family elsewhere" at
	# night — see ChildSafety — so only the grown are certain to be there.)
	check(not saves.bands.has(coming) and ["Wenna", "Odo"].all(func(n): return folk_now.has(n)),
		"and arrived, they are its people")

	_done()


func _record(town_name: String, at: Vector2, souls: int, houses: int, food: int) -> Dictionary:
	var folk := []
	for i in souls:
		folk.append(_person("%s %d" % [town_name, i], 6.0 + float(i * 37 % 50)))
	var built := []
	for i in houses:
		built.append(1)
	return {"name": town_name, "home": false, "pos": [at.x, at.y], "at_years": state.game_years,
		"folk": folk, "houses": built, "farms": 1,
		"store": {"plant": food, "meat": 0, "lumber": 60, "stone": 60},
		"board": {"fed": 1.0, "chronicle": []}}


func _person(called: String, age: float) -> Dictionary:
	return {"name": called, "female": called.length() % 2 == 0, "age": age, "lifespan": 75.0,
		"health": 100.0, "hunger": 20.0, "energy": 80.0}


func _band_from(town_name: String, kind := "settle") -> Dictionary:
	for band: Dictionary in saves.bands:
		if band["from"] == town_name and band["kind"] == kind:
			return band
	return {}


func _done() -> void:
	print("ROAD LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
