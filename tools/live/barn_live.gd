extends SceneTree
## A BARN'S STOCK EATS, AND GOES WITH ITS TOWN — checked in a real engine,
## headless:
##
##     godot --headless --path . --script tools/live/barn_live.gd
##
##   1. a barn stocked from a record keeps that many head, of that kind;
##   2. the town writes them into its record, by kind;
##   3. the morning trough takes the granary's grain at Drove.trough — and a
##      head of a big herd costs more than one of a small herd.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 150:
		await process_frame
	for n in root.find_children("*", "StartScreen", true, false):
		n.queue_free()
	paused = false
	var town: Node = current_scene.village
	var shops: Script = load("res://scripts/world/workshop.gd")
	var drove: Script = load("res://scripts/animals/drove.gd")
	print("A BARN'S STOCK")
	var barns := []
	for heads in [10, 60]:
		var barn = shops.create("barn", town)
		barn.position = Vector3(30.0 + barns.size() * 12.0, 0.0, 30.0)
		town.add_child(barn)
		town.workshops.append(barn)
		barns.append(barn)
		barn.stock_up("pig", heads)
		barn.stock_up("pig", 5)            # a barn keeping pigs already is not stocked twice
	await process_frame
	check(barns[0].stock_kinds() == {"pig": 10}, "a barn stocked from a record keeps that many, of that kind (%s)"
		% barns[0].stock_kinds())
	var kept: Dictionary = town.to_dict().get("kept", {})
	# (A barn's first morning sends a share to the store: count what it holds now.)
	var held: int = barns[0].stock_held() + barns[1].stock_held()
	check(int(kept.get("pig", 0)) == held and held > 60, "and its town writes them down by kind (%s)" % kept)
	# The morning trough, out of a full granary.
	var asks := []
	var mouths := []
	for barn in barns:
		mouths.append(barn.stock_held())
		town.store.add(0, 2000)            # FoodItem.FoodType.PLANT
		var before: int = town.store.plant_food
		barn._fill_the_trough()
		asks.append(before - town.store.plant_food)
	print("    ten head ate %d, sixty ate %d" % asks)
	check(asks[0] == drove.trough(mouths[0]) and asks[1] == drove.trough(mouths[1]),
		"the trough takes Drove.trough of the granary (%d and %d head)" % mouths)
	check(float(asks[1]) / mouths[1] >= 1.5 * float(asks[0]) / mouths[0],
		"and a head of a big herd costs more than one of a small herd")
	print("BARN LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
