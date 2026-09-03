class_name WorldGen
extends Node3D
## The endless world. Terrain streams in as 48m chunks around the camera;
## elevation, biome, and everything scattered on a chunk is deterministic
## from the world seed, so the same hill is always in the same place.
##
## Biomes (from two low-frequency noise fields, temperature and moisture):
##   savanna     – hot: acacias, giraffes, lions, llamas, oxen
##   wetland     – soggy lowlands: frogs, pigs, sparse swamp trees
##   forest      – damp: dense trees, deer, bears, wolves, the odd tiger
##   rocky_hills – cold and steep: stone deposits, llamas
##   grassland   – everything gentle: flowers, sheep, horses, strays
##
## Neutral villages generate out in the world. They run the same simulation
## as yours but believe in nothing — until your miracles convince them.

const CHUNK_SIZE := 48.0
const CHUNK_CELLS := 12          # 12x12 quads, 13x13 height samples
const WATER_LEVEL := 0.0
const CHUNKS_PER_FRAME := 1      # one chunk a frame: gentle, no startup stall
const VILLAGE_CELL_CHANCE := 0.05
const VILLAGE_MIN_CELL_DIST := 3  # chunks from origin before rivals appear

## How much world stays live around the focus. Set from the graphics tier
## at boot: a budget phone keeps a tight 5x5 so it doesn't drown in
## nodes/memory the instant the world loads (distance fog hides the short
## horizon); a capable device streams a wider 7x7. Rebuilds on world reload.
var load_radius := 2
var unload_radius := 3

var world_seed := 20260714

var focus_node: Node3D            # usually the camera rig
var player_village: Village

## WHAT HAS BEEN DONE TO THE LAND. The terrain itself is pure seed, so this is
## the only part of it that is real history — see TerrainScars, and `deform()`
## below for how a miracle actually moves the earth.
var scars := TerrainScars.new()

## Standing water that is not the sea — rain caught in a hollow. See `flood`.
var _ponds: Array[Dictionary] = []

var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _temp_noise := FastNoiseLite.new()
var _wet_noise := FastNoiseLite.new()
var _chunks := {}                 # Vector2i -> Chunk
var _village_cells := {}          # Vector2i -> Village (spawned, persistent)
var _wolf_raid_cooldown := 0.0


func _ready() -> void:
	add_to_group("world_gen")
	load_radius = Quality.load_radius()
	unload_radius = Quality.unload_radius()
	_height_noise.seed = world_seed
	_height_noise.fractal_octaves = 4
	_height_noise.frequency = 0.007
	_detail_noise.seed = world_seed + 7
	_detail_noise.frequency = 0.05
	_temp_noise.seed = world_seed + 1
	_temp_noise.frequency = 0.0035
	_wet_noise.seed = world_seed + 2
	_wet_noise.frequency = 0.0042


func _process(delta: float) -> void:
	if focus_node == null:
		return
	_stream_chunks()
	_tick_wolf_raids(delta)


## Terrain queries ------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var biome := biome_at(x, z)
	var amp := 11.0
	match biome:
		"rocky_hills":
			amp = 24.0
		"wetland":
			amp = 4.0
		"savanna":
			amp = 7.0
	var h := _height_noise.get_noise_2d(x, z) * amp + 2.2
	h += _detail_noise.get_noise_2d(x, z) * 0.7
	# The cradle: land near the origin is gently flattened so the player's
	# village always has room to breathe.
	var d := Vector2(x, z).length()
	var seeded := lerpf(2.0, h, smoothstep(28.0, 80.0, d))
	# ...and then whatever has been DONE to the land since. Scars ride on top of
	# the seed rather than replacing it, so a crater in a hillside is still a
	# hillside. Costs one is_empty() check on an untouched world.
	return seeded + scars.offset_at(x, z)


func biome_at(x: float, z: float) -> String:
	var t := _temp_noise.get_noise_2d(x, z)
	var w := _wet_noise.get_noise_2d(x, z)
	if t > 0.4:
		return "savanna"
	if w > 0.45:
		return "wetland"
	if w > 0.15:
		return "forest"
	if t < -0.4:
		return "rocky_hills"
	return "grassland"


func is_underwater(x: float, z: float) -> bool:
	return height_at(x, z) < water_level_at(x, z) + 0.25


## THE SURFACE OF THE WATER HERE — the sea, or a pond caught in a hollow.
##
## The sea is a single global plane, which is all an unbroken world needs. Once
## the land can be cratered, it needs more: rain falling into a hole should
## stand in it, and a flooded crater has a surface of its own, well above sea
## level. So every pond is a disc with its own height, and this returns the
## highest surface covering the point.
##
## Costs one `is_empty()` on a world nobody has flooded, which is the same
## bargain the scars make — and this is called by `is_underwater`, which is on
## every routing and placement path in the game.
func water_level_at(x: float, z: float) -> float:
	if _ponds.is_empty():
		return WATER_LEVEL
	var top := WATER_LEVEL
	for pond in _ponds:
		var dx: float = x - float(pond["x"])
		var dz: float = z - float(pond["z"])
		var r: float = pond["r"]
		if dx * dx + dz * dz < r * r:
			top = maxf(top, float(pond["level"]))
	return top


## IS THIS A HOLLOW, and how deep? Returns the height of the lowest point of
## the rim around `at`, or -INF if the ground runs away downhill somewhere —
## in which case water would simply drain off rather than stand.
##
## The same question the creature asks when it finds itself unable to climb out
## of something (see CreatureSteering.watch_for_pit): one of them is why you
## need a miracle, the other is why the rain stays.
func basin_rim(at: Vector2, reach: float) -> float:
	var floor_y := height_at(at.x, at.y)
	var lowest := INF
	for i in 12:
		var a := TAU * i / 12.0
		var h := height_at(at.x + cos(a) * reach, at.y + sin(a) * reach)
		if h <= floor_y + 0.3:
			return -INF        # open on one side: it drains
		lowest = minf(lowest, h)
	return lowest


## FILL A HOLLOW. Water stands to `level`, out to `radius`. Everything that
## asks whether a point is underwater agrees immediately.
func flood(at: Vector2, radius: float, level: float) -> void:
	# Merge with a pond already standing here rather than stacking discs.
	for pond in _ponds:
		if Vector2(float(pond["x"]), float(pond["z"])).distance_to(at) < radius * 0.5:
			pond["level"] = maxf(float(pond["level"]), level)
			pond["r"] = maxf(float(pond["r"]), radius)
			_show_pond(pond)
			return
	var pond := {"x": at.x, "z": at.y, "r": radius, "level": level}
	_ponds.append(pond)
	_show_pond(pond)


## The water itself: one thin disc, flat, at the pond's surface.
func _show_pond(pond: Dictionary) -> void:
	var old = pond.get("node")
	if old != null and is_instance_valid(old):
		(old as Node3D).queue_free()
	var disc := Util.cylinder(float(pond["r"]), 0.08, Color(0.24, 0.45, 0.62),
		Vector3(float(pond["x"]), float(pond["level"]), float(pond["z"])))
	if Quality.water_alpha():
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.2, 0.42, 0.65, 0.78)
		skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		skin.roughness = 0.1
		skin.metallic = 0.3
		disc.material_override = skin
	add_child(disc)
	pond["node"] = disc


func ponds_to_save() -> Array:
	var out := []
	for pond in _ponds:
		out.append({"x": pond["x"], "z": pond["z"], "r": pond["r"], "level": pond["level"]})
	return out


func ponds_from_save(data: Array) -> void:
	for entry in data:
		var pond: Dictionary = (entry as Dictionary).duplicate()
		_ponds.append(pond)
		_show_pond(pond)


## True only if the WHOLE footprint (a grid, not just corners) is dry —
## so a building's foundation never straddles an inlet or floats over
## water between two dry corners.
func footprint_dry(x: float, z: float, half := 2.5) -> bool:
	for dz in [-half, -half * 0.5, 0.0, half * 0.5, half]:
		for dx in [-half, -half * 0.5, 0.0, half * 0.5, half]:
			if is_underwater(x + dx, z + dz):
				return false
	return true


## True only if a whole village FOOTPRINT is dry land out to `radius` (centre
## plus three rings). A site that fails this is rejected outright, so a
## settlement never straddles a lakeshore with a house, farm, or pen ending up
## sitting in the water — the source of endless pathfinding grief.
func village_site_dry(x: float, z: float, radius := 18.0) -> bool:
	if is_underwater(x, z):
		return false
	for ring: Array in [[radius, 16], [radius * 0.66, 12], [radius * 0.33, 8]]:
		var r: float = ring[0]
		var steps: int = ring[1]
		for i in steps:
			var a := TAU * i / float(steps)
			if is_underwater(x + cos(a) * r, z + sin(a) * r):
				return false
	return true


## True if the straight line between two points stays on dry land (sampled) —
## keeps a village from raising a house on a dry patch across a lake from its
## centre, where its own people could never reach it.
func line_dry(ax: float, az: float, bx: float, bz: float, samples := 6) -> bool:
	for i in range(1, samples + 1):
		var t := float(i) / float(samples + 1)
		if is_underwater(lerpf(ax, bx, t), lerpf(az, bz, t)):
			return false
	return true


## The HIGHEST ground under a footprint. Structures settle on the high
## side so their sunken foundations bridge the downhill gap — never the
## uphill wall buried in the slope.
func settle_height(x: float, z: float, half := 2.5) -> float:
	var best := height_at(x, z)
	for corner in [Vector2(half, half), Vector2(-half, half),
			Vector2(half, -half), Vector2(-half, -half)]:
		best = maxf(best, height_at(x + corner.x, z + corner.y))
	return best


## Approximate slope (rise over 2m) — used to veto building/village sites.
func slope_at(x: float, z: float) -> float:
	var h := height_at(x, z)
	return maxf(
		absf(height_at(x + 2.0, z) - h),
		absf(height_at(x, z + 2.0) - h))


func ground_color(x: float, z: float, h: float) -> Color:
	var base: Color
	match biome_at(x, z):
		"savanna":
			base = Color(0.72, 0.65, 0.38)
		"wetland":
			base = Color(0.33, 0.47, 0.33)
		"forest":
			base = Color(0.28, 0.46, 0.26)
		"rocky_hills":
			base = Color(0.5, 0.48, 0.45)
		_:
			base = Color(0.4, 0.58, 0.32)
	if h < WATER_LEVEL + 0.5:
		base = base.lerp(Color(0.74, 0.68, 0.5), clampf((WATER_LEVEL + 0.5 - h), 0.0, 1.0))
	if h > 14.0:
		base = base.lerp(Color(0.92, 0.92, 0.95), clampf((h - 14.0) / 6.0, 0.0, 0.85))
	var s := slope_at(x, z)
	if s > 1.0:
		base = base.lerp(Color(0.48, 0.45, 0.42), clampf((s - 1.0) / 1.5, 0.0, 0.9))
	# BURNED GROUND stays burned. A fireball does not only dent the earth, it
	# blackens it, and the mark is part of the world from then on.
	var burn := scars.scorch_at(x, z)
	if burn > 0.0:
		base = base.lerp(Color(0.09, 0.07, 0.06), burn * 0.85)
	return base


## Deforming the land ----------------------------------------------------------

## MOVE THE EARTH. Cuts a scar into the world and rebuilds whatever is standing
## on it — mesh, collision, water and everything scattered.
##
## This is the whole public surface of terrain deformation: a miracle says what
## shape it wants and where, and everything else in the game finds out through
## `height_at()`. Returns the scar so a caller that wants to keep pushing (an
## earthquake spreading, a volcano growing) can widen it over time.
## `char_amount` blackens the ground as well as moving it.
func deform(kind: int, at: Vector2, radius: float, amount: float,
		rings := 3.0, char_amount := 0.0) -> Dictionary:
	var scar := scars.add(kind, at, radius, amount, rings, char_amount)
	rebuild_around(TerrainScars.reach_of(scar))
	return scar


## Rebuild every LOADED chunk overlapping a patch of world. Chunks not loaded
## need nothing: they read the scars when they are next built.
## Pour a load of something onto the ground — merging into whatever is already
## piled there — and rebuild what stands on it. See TerrainScars.deposit.
func pour(kind: int, at: Vector2, radius: float, amount: float) -> Dictionary:
	var scar := scars.deposit(kind, at, radius, amount)
	rebuild_around(TerrainScars.reach_of(scar))
	return scar


## Grow a scar already cut into the world, and rebuild what stands on it.
func reshape(scar: Dictionary, amount: float, radius := -1.0) -> void:
	var was := TerrainScars.reach_of(scar)
	scars.reshape(scar, amount, radius)
	rebuild_around(was.merge(TerrainScars.reach_of(scar)))


func rebuild_around(area: Rect2) -> void:
	# Grown by a metre, which is exactly what the shared edges need and no more.
	# A chunk's rim vertices sit at the same world points as its neighbour's, so
	# a scar reaching a chunk boundary must move BOTH or a seam opens along it —
	# the metre of slack pulls the neighbour in. A whole extra ring of chunks
	# was the first attempt, and it tripled the cost of every quake for nothing.
	var grown := area.grow(1.0)
	var x0 := floori(grown.position.x / CHUNK_SIZE)
	var x1 := floori(grown.end.x / CHUNK_SIZE)
	var z0 := floori(grown.position.y / CHUNK_SIZE)
	var z1 := floori(grown.end.y / CHUNK_SIZE)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var chunk: Chunk = _chunks.get(Vector2i(cx, cz))
			if chunk != null and is_instance_valid(chunk):
				chunk.rebuild_terrain()


## Every loaded chunk rebuilt — for restoring a save full of scars, where the
## land under the player has already been built from an unscarred seed.
func rebuild_all() -> void:
	for cell: Vector2i in _chunks:
		var chunk: Chunk = _chunks[cell]
		if is_instance_valid(chunk):
			chunk.rebuild_terrain()


## Chunk streaming ------------------------------------------------------------

func _stream_chunks() -> void:
	var focus := focus_node.global_position
	var center := Vector2i(floori(focus.x / CHUNK_SIZE), floori(focus.z / CHUNK_SIZE))

	var made := 0
	for dz in range(-load_radius, load_radius + 1):
		for dx in range(-load_radius, load_radius + 1):
			var cell := center + Vector2i(dx, dz)
			if _chunks.has(cell):
				continue
			_spawn_chunk(cell)
			made += 1
			if made >= CHUNKS_PER_FRAME:
				return

	for cell: Vector2i in _chunks.keys():
		var away := (cell - center).abs()
		if maxi(away.x, away.y) > unload_radius:
			_chunks[cell].queue_free()
			_chunks.erase(cell)


func _spawn_chunk(cell: Vector2i) -> void:
	var chunk := Chunk.new()
	chunk.world = self
	chunk.cell = cell
	chunk.position = Vector3(cell.x * CHUNK_SIZE, 0, cell.y * CHUNK_SIZE)
	add_child(chunk)
	_chunks[cell] = chunk
	_maybe_found_village(cell)


func chunk_rng(cell: Vector2i, salt := 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, cell.x, cell.y, salt])
	return rng


## Neutral villages -----------------------------------------------------------

## Deterministic placement: a cell is a village site if it wins the hash
## lottery AND no nearby cell holds a better ticket (guarantees spacing).
func _is_village_cell(cell: Vector2i) -> bool:
	if maxi(absi(cell.x), absi(cell.y)) < VILLAGE_MIN_CELL_DIST:
		return false
	var my_ticket := chunk_rng(cell, 99).randf()
	if my_ticket > VILLAGE_CELL_CHANCE:
		return false
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			if dx == 0 and dz == 0:
				continue
			var other := cell + Vector2i(dx, dz)
			if maxi(absi(other.x), absi(other.y)) < VILLAGE_MIN_CELL_DIST:
				continue
			var ticket := chunk_rng(other, 99).randf()
			if ticket <= VILLAGE_CELL_CHANCE and ticket < my_ticket:
				return false
	return true


func _maybe_found_village(cell: Vector2i) -> void:
	if _village_cells.has(cell) or not _is_village_cell(cell):
		return
	var center := Vector3(
		(cell.x + 0.5) * CHUNK_SIZE, 0, (cell.y + 0.5) * CHUNK_SIZE)
	# Find a buildable site near the chunk center.
	var rng := chunk_rng(cell, 5)
	# More tries now that the whole footprint must be dry — a cell near water
	# may need several probes to find a clear pocket (and some simply won't
	# host a village, which is fine in an endless world).
	for attempt in 24:
		var pos := center + Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-16, 16))
		var biome := biome_at(pos.x, pos.z)
		if biome != "grassland" and biome != "savanna":
			continue
		# The WHOLE settlement footprint must be dry, not just its centre —
		# no more villages founded straddling a lakeshore.
		if not village_site_dry(pos.x, pos.z) or slope_at(pos.x, pos.z) > 0.8:
			continue
		var village := Village.new()
		village.is_player_home = false
		village.village_name = _village_name(rng)
		pos.y = height_at(pos.x, pos.z)
		village.position = pos
		# Villages persist even when their chunk unloads.
		add_sibling.call_deferred(village)
		_village_cells[cell] = village
		GameState.announce("Scouts speak of a village called %s, far away. It believes in nothing... yet."
			% village.village_name)
		return


func _village_name(rng: RandomNumberGenerator) -> String:
	var first := ["Ash", "Thorn", "Elm", "Wold", "Bram", "Crag", "Fen", "Gild",
		"Hart", "Mere", "Oak", "Stone", "Wick", "Dun", "Ley"]
	var second := ["ford", "dale", "holm", "wick", "stead", "bury", "combe",
		"ton", "marsh", "field"]
	return first[rng.randi() % first.size()] + second[rng.randi() % second.size()]


func all_villages() -> Array:
	return get_tree().get_nodes_in_group("village")


## Wolves in the dark ---------------------------------------------------------

## At night, wolves gather at the edges of villages whose people have grown
## wicked. Virtue, it turns out, is also perimeter defense.
func _tick_wolf_raids(delta: float) -> void:
	_wolf_raid_cooldown -= delta
	if _wolf_raid_cooldown > 0.0 or not GameState.is_night():
		return
	_wolf_raid_cooldown = 40.0
	for v in all_villages():
		var village := v as Village
		if village.average_morality() > -20.0:
			continue
		if randf() > 0.6:
			continue
		var angle := randf() * TAU
		var pos := village.global_position \
			+ Vector3(cos(angle), 0, sin(angle)) * (village.influence_radius + 6.0)
		pos.y = height_at(pos.x, pos.z) + 0.5
		var wolf := Animal.create("wolf")
		wolf.night_spawned = true
		wolf.position = pos
		add_child(wolf)
		SoundBank.play_at("howl", pos, -4.0)
		GameState.announce("Wolves circle %s in the dark. Wickedness has a smell."
			% village.village_name)
