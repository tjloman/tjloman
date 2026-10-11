extends SceneTree
## NO CLIFF WHERE ONE COUNTRY MEETS ANOTHER — checked in a real engine,
## headless:
##
##     godot --headless --path . --script tools/live/seams_live.gd
##
## The land's height is a noise scaled by how rugged its country is — rocky
## hills twenty-four metres, wetland four — and the scale used to change all at
## once at the border: a hill across one had a step metres high in it, in a line,
## that looked like a seam and that no villager could climb. Walks a stretch of
## the world, finds every border, and measures the land across each one against
## the steepest the land gets anywhere else.
## Exits non-zero on failure. Names no class of the game's (see look.gd).

const SPAN := 2400.0
const EVERY := 6.0

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %-66s %s" % [what, "yes" if ok else "NO"])
	if not ok:
		fails += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 120:
		await process_frame
	var world: Node = current_scene.world_gen
	print("WHERE ONE COUNTRY MEETS ANOTHER")
	var borders := 0
	var worst_border := 0.0
	var worst_land := 0.0
	var worst_at := Vector2.ZERO
	var worst_land_at := Vector2.ZERO
	var z := -SPAN * 0.5
	while z < SPAN * 0.5:
		var x := -SPAN * 0.5
		var was := ""
		while x < SPAN * 0.5:
			var here: String = world.biome_at(x, z)
			# The rise over one metre, read as the drawn land is: on the half-metre grid.
			var rise := absf(world.seeded_height_at(x + 0.5, z) - world.seeded_height_at(x - 0.5, z))
			if was != "" and here != was:
				borders += 1
				# Across the border itself, at the half-metre the biome changes.
				var a := x - EVERY
				var b := x
				while b - a > 0.5:
					var mid := (a + b) * 0.5
					if world.biome_at(mid, z) == was:
						a = mid
					else:
						b = mid
				# Measured over the metre either side of where it changes, as the
				# rest of the land is: a rise a metre.
				var mid_at := (a + b) * 0.5
				var step := absf(world.seeded_height_at(mid_at + 0.5, z) - world.seeded_height_at(mid_at - 0.5, z))
				if step > worst_border:
					worst_border = step
					worst_at = Vector2(a, z)
			elif Vector2(x, z).length() > 100.0 and world.biome_at(x - 3.0, z) == here \
					and world.biome_at(x + 3.0, z) == here and world.biome_at(x - 0.5, z) == here \
					and world.biome_at(x + 0.5, z) == here:
				if rise > worst_land:
					worst_land = rise                     # well inside one country
					worst_land_at = Vector2(x, z)
			was = here
			x += EVERY
		z += EVERY * 8.0
	print("    %d borders crossed; the steepest metre of land anywhere else %.2f m" % [borders, worst_land])
	var across := ""
	for k in range(-6, 7):
		var px := worst_at.x + k * 2.0
		across += " %s %.1f" % [world.biome_at(px, worst_at.y).substr(0, 4), world.seeded_height_at(px, worst_at.y)]
	print("    the worst metre across a border %.2f m, at %.0f, %.0f:%s" % [worst_border, worst_at.x,
		worst_at.y, across])
	check(borders > 50, "the stretch walked crosses many borders (%d)" % borders)
	var climb: float = load("res://scripts/villager/villager_feet.gd").get_script_constant_map()["MOST_CLIMB"]
	check(worst_border <= worst_land * 1.2,
		"no border is much steeper than the land itself (%.2f m a metre against %.2f)" % [worst_border, worst_land])
	check(worst_border <= climb * 0.75,
		"and every one is walkable, well inside what a villager climbs (%.2f against %.2f)" % [worst_border, climb])
	print("SEAMS LIVE: %s" % ("all pass" if fails == 0 else "%d FAILING" % fails))
	quit(1 if fails > 0 else 0)
