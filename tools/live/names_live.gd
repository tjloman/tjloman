extends SceneTree
## EVERY TOWN ITS OWN NAMES — checked in a real engine, headless:
##
##     godot --headless --path . --script tools/live/names_live.gd
##
##   1. the names file is read in the engine, so a few thousand names for each
##      sex rather than the old twelve (VillagerNames, data/villager_names.json);
##   2. in every town in the world, no two people share a name;
##   3. the world as a whole uses more names than the old twenty-four;
##   4. a town naming four hundred newcomers gives four hundred names, none
##      twice and none its people already have;
##   5. a town brought back with ten men all called Pip keeps the first Pip and
##      names the other nine afresh, all different (VillagerNames.bring_back).
## Exits non-zero on failure. Names no class of the game's (see look.gd).

const OLD: Array[String] = [
	"Bess", "Dara", "Greta", "Isolde", "Kira", "Mabel", "Opal", "Rosa", "Tilda", "Vera",
	"Yara", "Freya", "Aldo", "Cormac", "Edwin", "Fen", "Hobb", "Jarek", "Lomax", "Nol",
	"Pip", "Sten", "Ulf", "Wick",
]

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
	for i in 120:
		await physics_frame
	var names: Script = load("res://scripts/villager/villager_names.gd")
	print("EVERY TOWN ITS OWN NAMES")

	# 1. The file, read in the engine.
	var women: int = names.names(true).size()
	var men: int = names.names(false).size()
	check(women >= 1500 and men >= 1500,
		"the names file is read: %d for women, %d for men" % [women, men])

	# 2 and 3. The towns standing now.
	var towns := 0
	var people := 0
	var repeats: Array[String] = []
	var everyone := {}
	var home: Node = null
	for town in get_nodes_in_group("village"):
		var folk: Array = town.my_villagers()
		if folk.is_empty():
			continue
		towns += 1
		if home == null or folk.size() > home.my_villagers().size():
			home = town
		var seen := {}
		for one in folk:
			people += 1
			everyone[one.villager_name] = true
			if seen.has(one.villager_name):
				repeats.append("%s in %s" % [one.villager_name, town.village_name])
			seen[one.villager_name] = true
	check(towns > 0 and repeats.is_empty(), "in each of %d towns (%d people), no two share a name%s"
		% [towns, people, "" if repeats.is_empty() else ": " + ", ".join(repeats.slice(0, 4))])
	check(everyone.size() > OLD.size(),
		"the world uses %d names, not the old %d" % [everyone.size(), OLD.size()])

	# 4. Four hundred newcomers to the biggest town.
	if home != null:
		var had := {}
		for one in home.my_villagers():
			had[one.villager_name] = true
		var given := {}
		var clashes := 0
		for i in 400:
			var said: String = names.pick(i % 2 == 0, home)
			if given.has(said) or had.has(said):
				clashes += 1
			given[said] = true
		check(clashes == 0, "%s names 400 newcomers with %d repeats" % [home.village_name, clashes])

	# 5. A town saved when there were twelve names, brought back.
	var town := Node.new()
	root.add_child(town)
	names.forget(town)
	var back: Array[String] = []
	for i in 10:
		back.append(names.bring_back(town, "", "Pip", false))
	var distinct := {}
	for said in back:
		distinct[said] = true
	check(back[0] == "Pip" and distinct.size() == 10 and back.count("Pip") == 1,
		"ten Pips brought back: the first keeps it, the rest are %s" % ", ".join(back.slice(1, 5)))
	town.queue_free()
	_done()


func _done() -> void:
	print("NAMES LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
