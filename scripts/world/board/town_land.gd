class_name TownLand
extends RefCounted
## WHAT THE LAND ROUND A TOWN CAN GIVE IT — the board a town out of sight is
## played on. Read once from the world when the town folds, and again only when
## the land changes (a miracle, a crater, a flood: WorldGen.land_edition).
##
## Every number is what the WORLD would put there, asked the way the world asks
## it: the ground by sampling height, slope and water on a grid; the trees,
## bushes and beasts from the very tables a chunk scatters from (Chunk.STAND,
## BUSHES, BEASTS), weighted by how much of each chunk is covered; and any chunk
## somebody has actually been to answers with what is really left alive there
## (WorldGen.herds_remembered), hunting and all. Fishing towns and plains cities
## are not rules anywhere — a long shore and no flat ground makes the first, a
## wide grassland makes the second.
##
## IN RINGS, BECAUSE A TOWN'S REACH GROWS. Everything is kept by how far out it
## lies, so the board can ask what lies within the reach a town of its size has
## (`near`): a hamlet builds close to its totem and a city further out, exactly
## as a live town's ring of influence widens with its people (Village.
## _update_influence). The wild larders — water, game, berries, timber — are
## counted out to the whole reach, because hunters and fishers walk further
## than builders build.
##
## AND ONLY ITS OWN GROUND. Ground nearer another town — standing or out of
## sight — is that town's: two neighbours do not both farm the same field or
## fish the same shore.

## The grid the ground is sampled on, in metres. Sixty-four square metres a
## sample.
const SAMPLE := 8.0
## How wide a ring is, and how far the whole reading reaches.
const RING := 20.0
const REACH := 120.0
## Where the plough goes: flat, dry, and not frozen, sand or jungle.
const FIELD_BIOMES: Array[String] = ["grassland", "savanna", "forest", "wetland"]
const FIELD_SLOPE := 0.35
## Where a house can stand: the live town's own test (Village.find_build_spot
## asks the same slope of a spot, a dry footprint this wide, and a dry way home).
const BUILD_SLOPE := 0.9
const FOOTPRINT := 2.2
## Nothing is built further out than this — a full-grown town builds within
## four-fifths of a 65 m ring (TownRules.build_reach) — so room is only looked
## for this far, and fields with it.
const BUILDS_OUT := 56.0
## What is kept in each ring.
const KEYS: Array[String] = ["water", "shore", "fields", "room", "wood", "bushes",
	"game", "predators", "game_now", "predators_now", "wood_now"]
## The wild larders: counted out to the whole reach, not just where it builds.
const WILD: Array[String] = ["water", "shore", "wood", "bushes", "game", "predators",
	"game_now", "predators_now", "wood_now"]

var reach := 0.0
var biome := "grassland"
var water := 0.0        # samples under water
var shore := 0.0        # dry samples beside water
var fields := 0.0       # samples a field could go on
var room := 0.0         # samples a house or a field could stand on
var wood := 0.0         # trees, as the chunks would grow them
var wood_now := 0.0     # and as they stand: less what is down for good, and what was planted
var bushes := 0.0       # berry bushes
## THE BEASTS: what the land holds of them — every herd as it was born, which
## is what it grows back to — and what is left of them now, where somebody has
## been and seen. The board's larders start at the share left (Chessboard.fold)
## and hand back what its hunting left when the town comes back (`write_back`).
var game := 0.0         # meat on the hoof the land holds, in food: heads times meat
var predators := 0.0    # beasts that will take a person, as the land holds them
var game_now := 0.0     # and as they stand now
var predators_now := 0.0
var edition := -1       # the land edition it was read at
var rings: Array = []   # per ring, a Dictionary of KEYS
var _near := {}         # ring count -> the TownLand within it


## READ THE LAND round `at`, out to REACH, keeping only ground nearer this town
## than any of `neighbours` (their positions on the ground plane).
static func read(world: WorldGen, at: Vector3, neighbours: Array = []) -> TownLand:
	var land := TownLand.new()
	land.reach = REACH
	land.edition = world.land_edition()
	land.biome = world.biome_at(at.x, at.z)
	var count := int(ceilf(REACH / RING))
	for i in count:
		var ring := {}
		for key: String in KEYS:
			ring[key] = 0.0
		land.rings.append(ring)
	var here := Vector2(at.x, at.z)
	var wet := {}
	var dry := {}
	var per_chunk := {}          # cell -> per-ring sample counts
	var span := int(ceilf(REACH / SAMPLE))
	for gx in range(-span, span + 1):
		for gz in range(-span, span + 1):
			var off := Vector2(gx, gz) * SAMPLE
			if off.length() > REACH:
				continue
			var spot := here + off
			if _theirs(spot, here, neighbours):
				continue
			var r := mini(int(off.length() / RING), count - 1)
			var ring: Dictionary = land.rings[r]
			var cell := WorldGen.cell_of(spot.x, spot.y)
			if not per_chunk.has(cell):
				var fresh := PackedInt32Array()       # a packed array is a value:
				fresh.resize(count)                   # sized here, then stored
				per_chunk[cell] = fresh
			var tally: PackedInt32Array = per_chunk[cell]
			tally[r] += 1
			per_chunk[cell] = tally
			if world.is_underwater(spot.x, spot.y):
				wet[Vector2i(gx, gz)] = true
				ring["water"] += 1.0
				continue
			dry[Vector2i(gx, gz)] = r
			if off.length() <= BUILDS_OUT and _buildable(world, here, spot):
				ring["room"] += 1.0
				if world.slope_at(spot.x, spot.y) < FIELD_SLOPE \
						and FIELD_BIOMES.has(world.biome_at(spot.x, spot.y)):
					ring["fields"] += 1.0
	for g: Vector2i in dry:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if wet.has(g + step):
				land.rings[dry[g]]["shore"] += 1.0
				break
	# A chunk is 48 m square: this many samples cover the whole of it.
	var whole := pow(WorldGen.CHUNK_SIZE / SAMPLE, 2.0)
	for cell: Vector2i in per_chunk:
		var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * WorldGen.CHUNK_SIZE
		var kind := world.biome_at(mid.x, mid.y)
		var counts: PackedInt32Array = per_chunk[cell]
		for r in count:
			if counts[r] > 0:
				land._count_chunk(world, cell, kind, minf(float(counts[r]) / whole, 1.0), land.rings[r])
	land._total(count)
	return land


## A LAND MADE UP, for the century harness: whatever it is handed, the rest bare.
static func made(values: Dictionary) -> TownLand:
	var land := TownLand.new()
	for key: String in values:
		land.set(key, values[key])
	return land


## WHAT LIES WITHIN `build_reach` for building and farming, and everything wild
## out to the whole reading. Kept, so a town asks this every step for nothing.
func near(build_reach: float) -> TownLand:
	if rings.is_empty():
		return self
	var count := clampi(int(ceilf(build_reach / RING)), 1, rings.size())
	if _near.has(count):
		return _near[count]
	var part := TownLand.made({"biome": biome, "edition": edition, "reach": build_reach})
	for r in rings.size():
		var ring: Dictionary = rings[r]
		for key: String in KEYS:
			if r < count or WILD.has(key):
				part.set(key, float(part.get(key)) + float(ring[key]))
	_near[count] = part
	return part


## COULD THE LIVE TOWN BUILD HERE? Its own test, asked the same way (Village.
## _ground_for_building): gentle enough, a dry footprint, and a dry straight
## way home to the totem. A town beside a lake cannot build across the water,
## however flat the far shore is — and neither can its numbers.
static func _buildable(world: WorldGen, home: Vector2, spot: Vector2) -> bool:
	return world.slope_at(spot.x, spot.y) <= BUILD_SLOPE \
		and world.footprint_dry(spot.x, spot.y, FOOTPRINT) \
		and world.line_dry(home.x, home.y, spot.x, spot.y)


## Is this spot nearer one of the neighbours than the town itself?
static func _theirs(spot: Vector2, here: Vector2, neighbours: Array) -> bool:
	var mine := spot.distance_squared_to(here)
	for other: Vector2 in neighbours:
		if spot.distance_squared_to(other) < mine:
			return true
	return false


func _total(count: int) -> void:
	for r in count:
		for key: String in KEYS:
			set(key, float(get(key)) + float(rings[r][key]))


func _count_chunk(world: WorldGen, cell: Vector2i, here: String, share: float, ring: Dictionary) -> void:
	var stand: Array = Chunk.STAND.get(here, [0, 0, ""])
	var grows := (float(stand[0]) + float(stand[1])) * 0.5
	ring["wood"] += grows * share
	ring["wood_now"] += _wood_standing(world, cell, grows) * share
	var bush: Array = Chunk.BUSHES.get(here, [0, 0])
	ring["bushes"] += (float(bush[0]) + float(bush[1])) * 0.5 * share
	var known = world.herds_remembered(cell)
	if known != null:
		for row: Dictionary in known:
			var born := float(row.get("born", row.get("alive", 0)))
			_count_beasts(String(row.get("species", "")), maxf(born, float(row.get("alive", 0))),
				float(row.get("alive", 0)), share, ring)
		return
	# Never visited: what the dice would put there, two herds to a chunk at most.
	var odds: Dictionary = Chunk.BEASTS.get(here, {})
	var herds := 0.0
	for species: String in odds:
		var chance := minf(float(odds[species]), 2.0 - herds)
		if chance <= 0.0:
			break
		herds += chance
		var heads := chance * Herd.typical_for(species)
		_count_beasts(species, heads, heads, share, ring)


static func _count_beasts(species: String, heads: float, alive: float, share: float,
		ring: Dictionary) -> void:
	var spec: Dictionary = Animal.SPECIES.get(species, {})
	if spec.is_empty():
		return
	if bool(spec.get("attacks_villagers", false)):
		ring["predators"] += heads * share
		ring["predators_now"] += alive * share
	else:
		var meat := float(spec.get("meat", 1))
		ring["game"] += heads * meat * share
		ring["game_now"] += alive * meat * share


## WHAT THE TOWN'S HUNTING LEFT, handed back to the world as it comes back into
## sight: every herd the world remembers round `at` stands at the share of its
## kind the board says is left — game at `game_share` of what it was born,
## man-eaters at `beast_share`. A herd hunted to nothing is gone. Ground that is
## standing now has its herds standing too: those are thinned to the same share
## the way a hunter thins them (Herd.take_one, never a beast being watched), and
## never added to — a live herd grows back by its own season.
static func write_back(world: WorldGen, at: Vector2, game_share: float, beast_share: float) -> void:
	var span := int(ceilf(REACH / WorldGen.CHUNK_SIZE))
	var centre := WorldGen.cell_of(at.x, at.y)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var cell := centre + Vector2i(dx, dz)
			var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * WorldGen.CHUNK_SIZE
			var standing := world.chunk_at(mid.x, mid.y)
			if standing != null and not standing.terrain_only:
				_thin(standing, game_share, beast_share)
				continue
			var known = world.herds_remembered(cell)
			if known == null:
				# Nobody has been here: the share is kept for when somebody is.
				world._remember_herd_share(cell, game_share, beast_share)
				continue
			var kept := []
			for row: Dictionary in known:
				var spec: Dictionary = Animal.SPECIES.get(String(row.get("species", "")), {})
				var share := beast_share if bool(spec.get("attacks_villagers", false)) else game_share
				var born := int(row.get("born", row.get("alive", 0)))
				var left := roundi(born * share)
				if left > 0:
					var after := row.duplicate()
					after["alive"] = left
					kept.append(after)
			world.remember_herds(cell, kept)


func to_dict() -> Dictionary:
	return {"reach": reach, "biome": biome, "water": water, "shore": shore,
		"fields": fields, "room": room, "wood": wood, "bushes": bushes, "game": game,
		"predators": predators, "game_now": game_now, "predators_now": predators_now,
		"wood_now": wood_now,
		"edition": edition, "rings": rings}


static func from_dict(data: Dictionary) -> TownLand:
	var land := made(data)
	land.rings = (data.get("rings", []) as Array).duplicate(true)
	return land


## AND WHAT ITS FELLING LEFT of the woods round it: every chunk the town's
## numbers reach has as many of its trees down as the board says, the newly cut
## ones counted from today — and one drawn far off as billboards is drawn again
## with them gone. A wood of real trees is left as it stands: trees do not
## vanish in front of the player.
static func write_back_woods(world: WorldGen, at: Vector2, wood_share: float) -> void:
	var span := int(ceilf(REACH / WorldGen.CHUNK_SIZE))
	var centre := WorldGen.cell_of(at.x, at.y)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var cell := centre + Vector2i(dx, dz)
			var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * WorldGen.CHUNK_SIZE
			if mid.distance_to(at) > REACH + WorldGen.CHUNK_SIZE * 0.5:
				continue
			var standing := world.chunk_at(mid.x, mid.y)
			if standing != null and (not standing.terrain_only or standing.wooded):
				continue
			var stand: Array = Chunk.STAND.get(world.biome_at(mid.x, mid.y), [0, 0, ""])
			var grows := (float(stand[0]) + float(stand[1])) * 0.5
			var more := roundi(_wood_standing(world, cell, grows) - grows * wood_share)
			if more > 0:
				world.remember_felled(cell, {"any": more})
				if standing != null:
					standing.restand()


## THE TREES STANDING IN A CELL: what its stand grows, less what is down for
## good, and what was planted and lives.
static func _wood_standing(world: WorldGen, cell: Vector2i, grows: float) -> float:
	var down := 0.0
	for entry: Dictionary in world.felled_at(cell):
		down += 1.0 if entry.has("seed") else float(entry["any"])
	return maxf(grows - down, 0.0) + float(world.sown_at(cell).size())


static func _thin(chunk: Chunk, game_share: float, beast_share: float) -> void:
	for node in chunk.get_children():
		var herd := node as Herd
		if herd == null or herd.keeper != null or herd.is_queued_for_deletion():
			continue
		var spec: Dictionary = Animal.SPECIES.get(herd.species, {})
		var share := beast_share if bool(spec.get("attacks_villagers", false)) else game_share
		var left := roundi(herd.born_head() * share)
		for i in maxi(herd.alive() - left, 0):
			if not herd.take_one():
				break
