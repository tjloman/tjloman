class_name TownLand
extends RefCounted
## WHAT THE LAND ROUND A TOWN CAN GIVE IT — the board a town out of sight is
## played on. Read once from the world when the town folds, and again only when
## the land changes (a miracle, a crater, a flood: WorldGen.land_edition) or
## the town outgrows the reach it was read at.
##
## Every number is what the WORLD would put there, asked the way the world asks
## it: the ground by sampling height, slope and water on a grid; the trees,
## bushes and beasts from the very tables a chunk scatters from (Chunk.STAND,
## BUSHES, BEASTS), weighted by how much of each chunk the reach covers; and any
## chunk somebody has actually been to answers with what is really left alive
## there (WorldGen.herds_remembered), hunting and all. Fishing towns and plains
## cities are not rules anywhere — a long shore and no flat ground makes the
## first, a wide grassland makes the second.

## The grid the ground is sampled on, in metres. Sixty-four square metres a
## sample: a field is about two of them.
const SAMPLE := 8.0
## Where the plough goes: flat, dry, and not frozen, sand or jungle.
const FIELD_BIOMES: Array[String] = ["grassland", "savanna", "forest", "wetland"]
const FIELD_SLOPE := 0.35

var reach := 0.0
var biome := "grassland"
var water := 0.0        # samples under water
var shore := 0.0        # dry samples beside water
var fields := 0.0       # samples a field could go on
var wood := 0.0         # trees, as the chunks would grow them
var bushes := 0.0       # berry bushes
var game := 0.0         # meat on the hoof, in food: heads times each kind's meat
var predators := 0.0    # beasts that will take a person
var edition := -1       # the land edition it was read at


## READ THE LAND within `reach` of `at`.
static func read(world: WorldGen, at: Vector3, reach_m: float) -> TownLand:
	var land := TownLand.new()
	land.reach = reach_m
	land.edition = world.land_edition()
	land.biome = world.biome_at(at.x, at.z)
	var wet := {}
	var dry: Array[Vector2i] = []
	var per_chunk := {}
	var span := int(ceilf(reach_m / SAMPLE))
	for gx in range(-span, span + 1):
		for gz in range(-span, span + 1):
			var off := Vector2(gx, gz) * SAMPLE
			if off.length() > reach_m:
				continue
			var x := at.x + off.x
			var z := at.z + off.y
			var cell := WorldGen.cell_of(x, z)
			per_chunk[cell] = int(per_chunk.get(cell, 0)) + 1
			if world.is_underwater(x, z):
				wet[Vector2i(gx, gz)] = true
				land.water += 1.0
				continue
			dry.append(Vector2i(gx, gz))
			if world.slope_at(x, z) < FIELD_SLOPE and FIELD_BIOMES.has(world.biome_at(x, z)):
				land.fields += 1.0
	for g in dry:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if wet.has(g + step):
				land.shore += 1.0
				break
	# A chunk is 48 m square: 36 samples cover the whole of it.
	var whole := pow(WorldGen.CHUNK_SIZE / SAMPLE, 2.0)
	for cell: Vector2i in per_chunk:
		var share := minf(float(per_chunk[cell]) / whole, 1.0)
		var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * WorldGen.CHUNK_SIZE
		land._count_chunk(world, cell, world.biome_at(mid.x, mid.y), share)
	return land


## A LAND MADE UP, for the century harness: whatever it is handed, the rest bare.
static func made(values: Dictionary) -> TownLand:
	var land := TownLand.new()
	for key: String in values:
		land.set(key, values[key])
	return land


func _count_chunk(world: WorldGen, cell: Vector2i, here: String, share: float) -> void:
	var stand: Array = Chunk.STAND.get(here, [0, 0, ""])
	wood += (float(stand[0]) + float(stand[1])) * 0.5 * share
	var bush: Array = Chunk.BUSHES.get(here, [0, 0])
	bushes += (float(bush[0]) + float(bush[1])) * 0.5 * share
	var known = world.herds_remembered(cell)
	if known != null:
		for row: Dictionary in known:
			_count_beasts(String(row.get("species", "")), float(row.get("alive", 0)), share)
		return
	# Never visited: what the dice would put there, two herds to a chunk at most.
	var odds: Dictionary = Chunk.BEASTS.get(here, {})
	var herds := 0.0
	for species: String in odds:
		var chance := minf(float(odds[species]), 2.0 - herds)
		if chance <= 0.0:
			break
		herds += chance
		_count_beasts(species, chance * Herd.typical_for(species), share)


func _count_beasts(species: String, heads: float, share: float) -> void:
	var spec: Dictionary = Animal.SPECIES.get(species, {})
	if spec.is_empty():
		return
	if bool(spec.get("attacks_villagers", false)):
		predators += heads * share
	else:
		game += heads * float(spec.get("meat", 1)) * share


func to_dict() -> Dictionary:
	return {"reach": reach, "biome": biome, "water": water, "shore": shore,
		"fields": fields, "wood": wood, "bushes": bushes, "game": game,
		"predators": predators, "edition": edition}


static func from_dict(data: Dictionary) -> TownLand:
	return made(data)
