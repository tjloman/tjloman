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
const CHUNK_CELLS := 16          # 16x16 quads, 17x17 height samples
const LOAD_RADIUS := 3           # chunks kept live around the focus
const UNLOAD_RADIUS := 5
const WATER_LEVEL := 0.0
const CHUNKS_PER_FRAME := 2
const VILLAGE_CELL_CHANCE := 0.05
const VILLAGE_MIN_CELL_DIST := 3  # chunks from origin before rivals appear

var world_seed := 20260714

var focus_node: Node3D            # usually the camera rig
var player_village: Village

var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _temp_noise := FastNoiseLite.new()
var _wet_noise := FastNoiseLite.new()
var _chunks := {}                 # Vector2i -> Chunk
var _village_cells := {}          # Vector2i -> Village (spawned, persistent)
var _wolf_raid_cooldown := 0.0


func _ready() -> void:
	add_to_group("world_gen")
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
	return lerpf(2.0, h, smoothstep(28.0, 80.0, d))


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
	return height_at(x, z) < WATER_LEVEL + 0.25


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
	return base


## Chunk streaming ------------------------------------------------------------

func _stream_chunks() -> void:
	var focus := focus_node.global_position
	var center := Vector2i(floori(focus.x / CHUNK_SIZE), floori(focus.z / CHUNK_SIZE))

	var made := 0
	for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var cell := center + Vector2i(dx, dz)
			if _chunks.has(cell):
				continue
			_spawn_chunk(cell)
			made += 1
			if made >= CHUNKS_PER_FRAME:
				return

	for cell: Vector2i in _chunks.keys():
		var away := (cell - center).abs()
		if maxi(away.x, away.y) > UNLOAD_RADIUS:
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
	for attempt in 12:
		var pos := center + Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
		var biome := biome_at(pos.x, pos.z)
		if biome != "grassland" and biome != "savanna":
			continue
		if is_underwater(pos.x, pos.z) or slope_at(pos.x, pos.z) > 0.8:
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
