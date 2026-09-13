class_name MapFile
extends RefCounted
## SAVING A MAP, AND LOADING IT AS A LEVEL.
##
## A hand-made island for the introduction does not need a terrain editor, a
## heightmap format or a painting tool. The game already has all three and they
## are the miracles: an earthquake rucks the ground up, a volcano raises a
## mountain, molten rock fills a crater in, a fireblast digs one. And every one
## of those reshapings is already RECORDED — TerrainScars keeps them as a list
## of dictionaries and can already write itself out, because the save game has
## always had to bring your craters back.
##
## So a map is two things and nothing else:
##
##   THE SEED, which is the land as it was made.
##   THE SCARS, which are everything anybody has since done to it.
##
## Which means the map editor is: turn on infinite prayer, sculpt the coastline
## with lightning and lava for an afternoon, and press save. There is no
## separate tool, no import step, and no second representation of the terrain
## that can drift out of agreement with the first. What you sculpted IS the
## file, because it is the same data the game was already carrying.
##
## WHAT A MAP DELIBERATELY DOES NOT CARRY, yet: villages, creatures, props,
## quest markers. Those are placements rather than terrain and they want their
## own list — but the ground has to come first, because everything else is
## positioned against it.

## Where maps live. `user://` so a player can make one too, and so the ones
## shipped with the game can be dropped in beside them.
const DIR := "user://maps"
const EXT := ".hoh"
## Bumped when the shape of the file changes in a way an older one cannot be
## read as. Written into every map.
const FORMAT := 1


## WRITE THE WORLD OUT. Returns the path, or "" if it could not be written.
## `keep_scorch` writes the blackening out with the shape. Off by default, and
## that default matters: you sculpt a coastline with volcanoes and molten rock,
## and every one of those chars the ground it moves. Saved as they came, a
## hand-made island is a BURNT island — the record of how it was made rather
## than the thing that was made. A map is terrain; the soot is not part of it.
static func save_as(world: WorldGen, map_name: String, keep_scorch := false) -> String:
	if world == null or not is_instance_valid(world):
		return ""
	var clean := _tidy(map_name)
	if clean == "":
		return ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := "%s/%s%s" % [DIR, clean, EXT]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify({
		"format": FORMAT,
		"name": map_name,
		"seed": world.world_seed,
		# The whole of what has been done to the land, exactly as the save game
		# already stores it — one representation, not two.
		"scars": _shape_only(world.scars.to_save(), keep_scorch),
	}, "\t"))
	file.close()
	return path


## READ ONE IN. The seed is set FIRST and the noise rebuilt from it, because
## every scar is an offset on top of ground that must already be the right
## ground. Returns false if there was nothing to read.
static func load_into(world: WorldGen, map_name: String) -> bool:
	var data := read(map_name)
	if data.is_empty() or world == null:
		return false
	world.reseed(int(data.get("seed", world.world_seed)))
	world.scars.from_save(data.get("scars", []))
	# And drop every chunk, or the old ground goes on being drawn over the new.
	world.recut()
	return true


## STRIP THE SOOT, keeping every metre of the shape. See `save_as`.
static func _shape_only(saved: Dictionary, keep_scorch: bool) -> Dictionary:
	if keep_scorch:
		return saved
	var out := saved.duplicate(true)
	for scar: Dictionary in out.get("scars", []):
		scar["char"] = 0.0
		scar["burned"] = 0.0
	return out


## The raw dictionary of a map, or {} if there is no such map.
static func read(map_name: String) -> Dictionary:
	var path := "%s/%s%s" % [DIR, _tidy(map_name), EXT]
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


## Every map on disk, by name.
static func all_maps() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return found
	for name in dir.get_files():
		if name.ends_with(EXT):
			found.append(name.substr(0, name.length() - EXT.length()))
	found.sort()
	return found


## What a map is, in one line — for a menu.
static func describe(map_name: String) -> String:
	var data := read(map_name)
	if data.is_empty():
		return "%s — missing" % map_name
	var scars: Variant = data.get("scars", {})
	var many := 0
	if scars is Dictionary:
		many = ((scars as Dictionary).get("scars", []) as Array).size()
	elif scars is Array:
		many = (scars as Array).size()
	return "%s — seed %d, %d reshaping(s)" % [
		String(data.get("name", map_name)), int(data.get("seed", 0)), many]


## A file name that cannot escape its directory or surprise a filesystem.
static func _tidy(map_name: String) -> String:
	var out := ""
	for c: String in map_name.strip_edges().to_lower():
		if c.is_valid_identifier() or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
	return out.substr(0, 48)
