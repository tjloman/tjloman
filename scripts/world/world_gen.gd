class_name WorldGen
extends Node3D
## WALL CLOCK BY DESIGN: `_frame_spent` measures how much of a REAL frame this
## frame's world-building has eaten. It is the streamer measuring the machine,
## not the world measuring itself — and it must go on working while the tree is
## paused, which is the one time GameState.clock is deliberately stopped and the
## one time loading matters most.
##
## The endless world. Terrain streams in as 48m chunks around the camera;
## elevation, biome, and everything scattered on a chunk is deterministic
## from the world seed, so the same hill is always in the same place.
##
## Biomes (from two low-frequency noise fields — temperature and moisture — and
## one coin of its own for the jungle; see `biome_at`):
##   desert      – hot AND dry: llamas, giraffes, lions, the odd stray dog
##   savanna     – hot: acacias, giraffes, lions, llamas, oxen
##   tundra      – the far cold: reindeer, bison, elk, and what hunts them
##   rainforest  – where wetland meets forest, half the time: coatis, anteaters,
##                 tigers, frogs, and everything small and loud
##   wetland     – soggy lowlands: frogs, pigs, sparse swamp trees
##   forest      – damp: dense trees, deer, bears, wolves, the odd tiger
##   rocky_hills – cold and steep: stone deposits, llamas
##   grassland   – everything gentle: flowers, sheep, horses, strays
##
## Neutral villages generate out in the world. They run the same simulation
## as yours but believe in nothing — until your miracles convince them.

const CHUNK_SIZE := 48.0
const WATER_LEVEL := 0.0
## HOW MUCH OF A FRAME THE WORLD MAY HAVE, in milliseconds — near ring, far
## ring and coarsening together. See `_frame_spent` for why this is a budget
## and not the count it used to be.
##
## A fifth of a sixty-hertz frame. Small enough that a chunk arriving is not a
## hitch anybody sees, large enough that a cold fill still finishes in seconds.
const WORLD_MILLIS := 3.0
const CHUNKS_PER_FRAME := 1      # the floor under the budget: never fewer
## ...and the far ring only ever gets what the near ring did not want. The two
## do not add: `_fill_near` returning true skips `_fill_sight` outright, so the
## whole of a frame's world-building is WORLD_MILLIS however it is divided.
##
## The near ring is filled first because it is the ground you are about to
## stand on; the far ring is the horizon, and a horizon that arrives a frame
## late is a horizon. In the steady state both cost nothing at all — see
## `_sight_filled`, which stops the far sweep for good once it finds no gaps.
##
## And chunks put back down to the far ring's resolution come off the same
## budget, because a coarsening is a mesh cut like any other. See
## Chunk.coarse_due: the work is owed the moment a row is stripped.

## HOW A PLACE IS MADE LAND — six basins on a ring at nine tenths of the radius,
## lifted until the wettest point under it is clear of the water by DRY_CLEAR.
## See `make_dry` for why it is six and not one.
const DRY_RING := 6
const DRY_RING_AT := 0.9
const DRY_CLEAR := 0.6

## HOW WELL A CELL IS KNOWN — the whole of the fog on the temple's well. Bare
## ground raised out in the sight ring is SEEN; a full chunk with everything
## living on it is WALKED. See `_known`.
const SEEN := 1
const WALKED := 2
## How many chunks either side of the creature stay loaded wherever it is. One
## is a three-by-three of them — about a hundred and fifty metres across, which
## is more than its senses reach — and it is deliberately far smaller than the
## camera's ring, because this is ground for the beast to LIVE on rather than
## ground for anyone to look at.
const CREATURE_KEEP := 1
const VILLAGE_CELL_CHANCE := 0.05
const VILLAGE_MIN_CELL_DIST := 3  # chunks from origin before rivals appear
## The grid the sea's flood fill walks, and how far it walks before it gives up
## and calls a sunken region the sea anyway. See `sea_reaches`.
const SEA_STEP := 2.0
const SEA_CELLS := 240            # ~30m of connected water
## How often burned ground is re-tinted as it cools. Tight while a burn is
## going out — that is the one fast stretch of the curve — and lazy for the
## four-minute weathering that follows. See `_tick_burns`.
const BURN_REFRESH := 2.0
const BURN_REFRESH_HOT := 0.5

## WHERE THE EXTREMES BEGIN. Desert wants heat AND dryness together, so a wet
## hot place stays savanna; tundra is the far cold, leaving rocky hills to the
## merely chilly. Rainforest starts a little below the forest line so it takes
## from both its neighbours rather than only from the marsh.
const DESERT_HEAT := 0.52
const DESERT_DRY := 0.0
const TUNDRA_COLD := -0.52
const RAINFOREST_WET := 0.30

## How much world stays LIVE around the focus — collision, water, trees, herds,
## villagers. Set from the graphics tier at boot: a budget phone keeps a tight
## 5x5 so it doesn't drown in nodes the instant the world loads, a capable
## device a 7x7. Rebuilds on world reload.
##
## This is no longer how far you can SEE; it is how far the world is a place.
## See `sight_radius` just below, which is the one sized against the camera.
var load_radius := 2
var unload_radius := 3

## HOW FAR THE LAND ITSELF REACHES, in chunks — see Quality.sight_radius. Past
## `unload_radius` and out to here, a chunk is built as bare ground and nothing
## else: no collision, no water, nothing living on it. It is there so that the
## horizon is the horizon instead of the edge of the loaded world.
##
## Chunks are not destroyed and rebuilt as the player crosses this band; they
## are fleshed out and stripped back down, so a hill's mesh is cut ONCE, when
## the cell first comes into view, and then left standing until it goes over
## the horizon for good. That is the whole of the fix: nothing ever pops in
## within sight, because by the time it is within sight it is already there.
var sight_radius := 5

## Quads along one edge of a chunk, so (chunk_cells + 1)^2 height samples. Also
## from the tier: 24 on a capable device is a two-metre triangle, 16 on a budget
## one is three. Both the mesh and the collision heightmap are cut on this grid,
## so it is the resolution of the world you see AND the one you walk on.
var chunk_cells := 12

var world_seed := 20260714

var focus_node: Node3D            # usually the camera rig
var player_village: Village

## WHAT HAS BEEN DONE TO THE LAND. The terrain itself is pure seed, so this is
## the only part of it that is real history — see TerrainScars, and `deform()`
## below for how a miracle actually moves the earth.
var scars := TerrainScars.new()

## Standing water that is not the sea — rain caught in a hollow. See `flood`.
var _ponds: Array[Dictionary] = []

## Which 2m cells the sea can get to, once the land has been broken open.
## Answered by a flood fill (see `sea_reaches`) and thrown away whole every
## time the earth moves, because moving it is exactly what changes the answer.
var _sea_cache := {}

var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _temp_noise := FastNoiseLite.new()
var _wet_noise := FastNoiseLite.new()
var _jungle_noise := FastNoiseLite.new()
## WHERE THE GOD HAS ACTUALLY BEEN. Cell -> SEEN or WALKED, and the whole of
## the fog on the temple's well.
##
## The land is a function of the seed, so a map COULD draw country nobody has
## ever visited — and should not. A god who has walked a valley and a god who
## has merely been told a valley exists are in different positions, and the
## well is the one place that difference is visible. Recorded here rather than
## anywhere else because this is the one place that knows a chunk was raised at
## all, and like the Chronicle it cannot be reconstructed later: an unvisited
## cell and a visited-then-unloaded cell are identical from outside.
var _known := {}                  # Vector2i -> SEEN or WALKED
var _chunks := {}                 # Vector2i -> Chunk
## Where the far ring was last filled from, and whether it is complete. A full
## sweep of a 17x17 ring is 289 dictionary probes; doing that every frame to
## learn "still nothing missing" is exactly the kind of idle work the scheduler
## exists to stop, so the sweep runs only until it finds no gaps and then not
## again until the focus crosses into another cell.
var _sight_center := Vector2i(2147483647, 2147483647)
var _sight_filled := false
var _village_cells := {}          # Vector2i -> Village (spawned, persistent)
var _wolf_raid_cooldown := 0.0
var _burn_tick := 0.0
## When this frame's world-building began, in real milliseconds. See
## `_frame_spent` — and the pragma at the top of this file for why the wall
## clock is the right clock for a loader.
var _frame_began := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the streamer outlives the pause
	add_to_group("world_gen")
	load_radius = Quality.load_radius()
	unload_radius = Quality.unload_radius()
	sight_radius = maxi(Quality.sight_radius(), unload_radius)
	chunk_cells = Quality.chunk_cells()
	reseed(world_seed)


## SET THE SEED AND REBUILD THE LAND FROM IT.
##
## Every noise here is derived from the one number, and they were tuned in
## `_ready` where nothing could reach them — so loading a saved MAP, which is a
## seed plus a list of reshapings, had no way to say which land the reshapings
## were reshapings OF. See MapFile.
##
## Only touches the generator. Chunks already built are not rebuilt: call this
## before the world is streamed, which for a map load is the only sane moment
## anyway.
## THROW AWAY EVERY CHUNK SO THE LAND IS CUT AGAIN.
##
## Chunk meshes are built from the heights that were true when they streamed in,
## so loading a map over a living world left the OLD ground standing while the
## new ground was what everything walked on and routed over. Dropping them makes
## the streamer rebuild each one as it comes back into range.
func recut() -> void:
	for cell in _chunks.keys():
		var chunk = _chunks[cell]
		if is_instance_valid(chunk):
			chunk.queue_free()
	_chunks.clear()
	_sea_cache.clear()
	_sight_filled = false


func reseed(to: int) -> void:
	world_seed = to
	_sea_cache.clear()
	_height_noise.seed = world_seed
	_height_noise.fractal_octaves = 4
	_height_noise.frequency = 0.007
	_detail_noise.seed = world_seed + 7
	_detail_noise.frequency = 0.05
	_temp_noise.seed = world_seed + 1
	_temp_noise.frequency = 0.0035
	_wet_noise.seed = world_seed + 2
	_wet_noise.frequency = 0.0042
	# THE RAINFOREST COIN. A third noise purely so the jungle can appear in half
	# of the wet forest edge without being a corner of the same two axes — and
	# at a higher frequency than either, so a rainforest breaks into patches
	# inside the wet country rather than claiming all of one side of it.
	_jungle_noise.seed = world_seed + 3
	_jungle_noise.frequency = 0.0065


func _process(delta: float) -> void:
	Ledger.open(&"WorldGen")
	# LOADING GOES ON WHILE THE WORLD IS HELD. The opening screen pauses the
	# tree so nothing ages or starves while the player is choosing — and raising
	# the land is the one job that must NOT stop for that, because it is most of
	# what "loading" means here. So the streamer alone is exempt: this node runs
	# always, everything it spawns is pausable (see _spawn_chunk), and while the
	# game is held the only thing that happens is ground arriving.
	if get_tree().paused:
		if focus_node != null:
			_stream_chunks()
		return
	_tick_burns(delta)
	if focus_node == null:
		return
	_stream_chunks()
	_tick_wolf_raids(delta)


## BURNED GROUND, COOLING IN PLACE.
##
## The ground's colour is baked into the terrain mesh — one vertex colour per
## grid corner — so a burn that changes colour over eight minutes means re-
## cutting the chunks it touches as it goes. That is only affordable because
## `Chunk.recolor` keeps the height grid it already measured and redoes nothing
## but the colours: no noise for the heights, no collision, no re-grounding of
## anything standing there.
##
## Every BURN_REFRESH seconds, and ONLY while something is actually still
## cooling. `still_cooling` goes false once every burn has weathered out to
## scrub, and from then on this costs one walk of the scar list per frame.
func _tick_burns(delta: float) -> void:
	if scars.is_empty():
		return
	scars.clock += delta
	if not scars.still_cooling():
		return
	_burn_tick += delta
	if _burn_tick < (BURN_REFRESH_HOT if scars.cooling_fast() else BURN_REFRESH):
		return
	_burn_tick = 0.0
	var touched := {}
	for area: Rect2 in scars.cooling_areas():
		var grown := area.grow(1.0)
		for cz in range(floori(grown.position.y / CHUNK_SIZE),
				floori(grown.end.y / CHUNK_SIZE) + 1):
			for cx in range(floori(grown.position.x / CHUNK_SIZE),
					floori(grown.end.x / CHUNK_SIZE) + 1):
				touched[Vector2i(cx, cz)] = true
	for cell: Vector2i in touched:
		var cached = _chunks.get(cell)
		if cached != null and is_instance_valid(cached):
			(cached as Chunk).recolor()


## Terrain queries ------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	# The seed, and then whatever has been DONE to the land since. Scars ride on
	# top of the seed rather than replacing it, so a crater in a hillside is
	# still a hillside. Costs one is_empty() check on an untouched world.
	return seeded_height_at(x, z) + scars.offset_at(x, z)


## THE LAND AS IT WAS MADE, before any miracle touched it. Kept apart from
## `height_at` because the difference between the two is the whole question of
## where the sea is: ground that was ALWAYS below the waterline is seabed, and
## a hole dug below it by a fireball is a hole. See `sea_reaches`.
func seeded_height_at(x: float, z: float) -> float:
	var biome := biome_at(x, z)
	var amp := 11.0
	match biome:
		"rocky_hills":
			amp = 24.0
		"wetland":
			amp = 4.0
		"savanna":
			amp = 7.0
		# Dunes: gentler than hills and rounder than grass, so a desert reads as
		# swells rather than as either a plain or a mountain range.
		"desert":
			amp = 9.0
		# The cold flats. Tundra is the flattest country in the game on purpose —
		# it is meant to feel like somewhere with nothing to hide behind.
		"tundra":
			amp = 5.0
		"rainforest":
			amp = 10.0
	var h := _height_noise.get_noise_2d(x, z) * amp + 2.2
	h += _detail_noise.get_noise_2d(x, z) * 0.7
	# The cradle: land near the origin is gently flattened so the player's
	# village always has room to breathe.
	var d := Vector2(x, z).length()
	return lerpf(2.0, h, smoothstep(28.0, 80.0, d))


## WHAT KIND OF PLACE THIS IS, from two noises and a coin.
##
## A first-match ladder, and the ORDER IS THE DESIGN: it is asked hottest and
## coldest first, so the extremes carve their territory out of the milder biomes
## rather than the other way round. A hot marsh is desert, not wetland.
##
## THE RAINFOREST IS THE ODD ONE. It is not a corner of the temperature/wetness
## plane like the rest — it is what happens WHERE WETLAND AND FOREST MEET, and
## only half the time. That band is `w` from a little under the forest line to
## well past the wetland one, and a third noise of its own decides, which is a
## fair coin because simplex is symmetric about zero. It has to be a NOISE and
## not a random roll: this function must give the same answer for the same
## ground forever, or chunks would come back different every time they loaded
## and the save that stores villages as counts would have nothing to stand on.
func biome_at(x: float, z: float) -> String:
	var t := _temp_noise.get_noise_2d(x, z)
	var w := _wet_noise.get_noise_2d(x, z)
	# The hot dry heart of the warm country. Savanna keeps the rest of the heat.
	if t > DESERT_HEAT and w < DESERT_DRY:
		return "desert"
	if t > 0.4:
		return "savanna"
	# And the far cold. Rocky hills keep the merely chilly.
	if t < TUNDRA_COLD:
		return "tundra"
	if w > RAINFOREST_WET and _jungle_noise.get_noise_2d(x, z) > 0.0:
		return "rainforest"
	if w > 0.45:
		return "wetland"
	if w > 0.15:
		return "forest"
	if t < -0.4:
		return "rocky_hills"
	return "grassland"


func is_underwater(x: float, z: float) -> bool:
	# Written out rather than calling `water_level_at` so the seeded height is
	# evaluated once and reused: this is on every routing, placement, drowning
	# and grazing path in the game, and it used to cost two.
	var seeded := seeded_height_at(x, z)
	var ground := seeded + scars.offset_at(x, z)
	if ground < _pond_level_at(x, z) + 0.25:
		return true
	if ground >= WATER_LEVEL + 0.25:
		return false
	# Below the waterline. Seabed, or a hole the sea cannot get into?
	if seeded < WATER_LEVEL + 0.25:
		return true
	return sea_reaches(x, z)


## THE SURFACE OF THE WATER HERE — the sea, or a pond caught in a hollow, or
## nothing at all.
##
## The sea is a single global plane, which is all an unbroken world needs. Once
## the land can be cratered, it needs more: rain falling into a hole should
## stand in it, and a flooded crater has a surface of its own, well above sea
## level. So every pond is a disc with its own height, and this returns the
## highest surface covering the point — or -INF where the ground is dry, which
## compares correctly against any height without a special case at the callers.
func water_level_at(x: float, z: float) -> float:
	var top := _pond_level_at(x, z)
	if top > -INF:
		return top
	# Laid out so the flood fill is only ever reached for ground that has
	# actually been dug below the waterline: this is called every frame for
	# every villager, animal and route cell, and most of them are on dry land
	# nowhere near the sea.
	var seeded := seeded_height_at(x, z)
	if seeded < WATER_LEVEL + 0.25:
		return WATER_LEVEL                   # seabed, always was
	if seeded + scars.offset_at(x, z) >= WATER_LEVEL + 0.25:
		return -INF                          # dry ground: no water here at all
	return WATER_LEVEL if sea_reaches(x, z) else -INF


## WHAT YOU WOULD STAND ON HERE — the ground, or the water covering it. Written
## `maxf(height_at(), WATER_LEVEL)` all over the game, which was right while the
## sea was the only water and everywhere: it floats things at y=0 over a dry pit
## dug below sea level, and sinks them to the bed of a pond.
func surface_at(x: float, z: float) -> float:
	return maxf(height_at(x, z), water_level_at(x, z))


## The highest pond covering the point, or -INF. One `is_empty()` on a world
## nobody has flooded.
func _pond_level_at(x: float, z: float) -> float:
	if _ponds.is_empty():
		return -INF
	var top := -INF
	for pond in _ponds:
		var dx: float = x - float(pond["x"])
		var dz: float = z - float(pond["z"])
		var r: float = pond["r"]
		if dx * dx + dz * dz < r * r:
			top = maxf(top, float(pond["level"]))
	return top


## DOES THE SEA ACTUALLY GET HERE?
##
## For most of the game's life this question did not exist: the world was made
## of unbroken seeded terrain, "below the waterline" and "sea" meant the same
## thing, and one global plane at y=0 drew all of it. Craters ended that. A
## fireball digs 1.7m, they stack, and the village cradle sits 2m above the sea
## — so the second fireball on a spot opened a pit whose floor read as
## underwater. The pit then filled with ocean that had no way of getting to it,
## a hundred and fifty metres inland, and the villagers walked in and drowned.
##
## So: ground that was ALWAYS below the waterline is seabed and always wet.
## Ground dug below it is wet only if there is a continuous below-waterline
## path from it OUT to real seabed — which is what a flood fill answers, and
## which also means a channel dug from the shore inland really does let the sea
## in, exactly as you would hope.
##
## The fill walks a 2m grid, and the whole connected component it explores
## shares one answer, so it is cached for all of them at once and the cost is
## paid once per hole rather than once per villager per frame.
func sea_reaches(x: float, z: float) -> bool:
	if scars.is_empty():
		return seeded_height_at(x, z) < WATER_LEVEL + 0.25
	var start := Vector2i(roundi(x / SEA_STEP), roundi(z / SEA_STEP))
	if _sea_cache.has(start):
		return bool(_sea_cache[start])
	if _sea_cache.size() > 20000:
		_sea_cache.clear()      # a long session's worth: start it over
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var found := false
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var cx := cell.x * SEA_STEP
		var cz := cell.y * SEA_STEP
		var seeded := seeded_height_at(cx, cz)
		if seeded + scars.offset_at(cx, cz) >= WATER_LEVEL + 0.25:
			continue                 # dry ground: the water stops at it
		if seeded < WATER_LEVEL + 0.25:
			found = true             # real seabed — connected, so the sea is in
			break
		if queue.size() >= SEA_CELLS:
			found = true             # a sunken region this big IS the sea
			break
		# Typed on the `for`: an untyped array literal holds Variants, and
		# `cell + step` would then infer a Variant, which this project builds
		# as an error that takes every dependent script down with it.
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + step
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	for cell: Vector2i in seen:
		_sea_cache[cell] = found
	return found


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


## THE COLOUR OF THE GROUND HERE — biome, then sand at the waterline, snow up
## high, bare rock on anything steep, and soot wherever it has burned.
##
## `slope` is the rise over two metres at this point. Pass it if you already
## know it: working it out costs three more `height_at` calls, which is twelve
## noise evaluations, and it is by far the most expensive thing in here. A
## caller walking a grid (Chunk._build_terrain) has the neighbouring heights in
## hand already and can difference them for nothing.
func ground_color(x: float, z: float, h: float, slope := -1.0) -> Color:
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
		"desert":
			base = Color(0.84, 0.74, 0.5)
		"tundra":
			base = Color(0.62, 0.66, 0.66)
		"rainforest":
			base = Color(0.17, 0.38, 0.2)
		_:
			base = Color(0.4, 0.58, 0.32)
	if h < WATER_LEVEL + 0.5:
		base = base.lerp(Color(0.74, 0.68, 0.5), clampf((WATER_LEVEL + 0.5 - h), 0.0, 1.0))
	if h > 14.0:
		base = base.lerp(Color(0.92, 0.92, 0.95), clampf((h - 14.0) / 6.0, 0.0, 0.85))
	var s := slope_at(x, z) if slope < 0.0 else slope
	if s > 1.0:
		base = base.lerp(Color(0.48, 0.45, 0.42), clampf((s - 1.0) / 1.5, 0.0, 0.9))
	# BURNED GROUND COOLS. A fireball does not only dent the earth, it sets it
	# alight — and what it leaves changes: embers for half a minute, then black,
	# then weathering out to dusty scrub, which it stays. The colour AND the
	# strength both come from how old the burn is (TerrainScars.weathered), so
	# there is nothing to decide here beyond mixing it in.
	var burn := scars.burn_at(x, z)
	if burn.a > 0.0:
		base = base.lerp(Color(burn.r, burn.g, burn.b), burn.a)
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
	_sea_cache.clear()
	rebuild_around(TerrainScars.reach_of(scar))
	return scar


## Rebuild every LOADED chunk overlapping a patch of world. Chunks not loaded
## need nothing: they read the scars when they are next built.
## MAKE A PLACE LAND, because something is standing on it.
##
## A village picks the spot for a nest by what a village cares about — near the
## square, clear of the houses, room for the dancers — and nothing in that asks
## whether the ground is under water. So a nest gets raised over a shallow, and
## the creature and any villager who walks out to worship at it steps off the
## stone into the sea. The fix is not to move the nest. It is that a nest is a
## work of the whole town and the ground under it becomes land, which is what a
## foundation IS.
##
## SIX BASINS IN A RING, NOT ONE DOME. One basin tapers as cos squared and is
## down to a sixth of its height at the rim of a nest's footprint, so lifting
## the EDGE clear of the water by two metres would pile eleven metres up under
## the middle and stand the bed on a hill. Six overlapping basins on a ring at
## nine tenths of the radius sum almost flat: the peak comes out at 1.17 times
## the lift actually needed, so a nest in a shallow ends up on a shoal rather
## than on a mound. (One scar cannot cover it alone in any case — TerrainScars
## caps a scar's reach at BUCKET so the lookup stays nine buckets wide.)
##
## Returns whether the place ended up dry. Costs nothing and changes nothing
## when the ground was never wet, which is what makes it safe to call every
## time a nest is built OR LOADED — an old save with a drowned nest repairs
## itself the first time it comes back.
func make_dry(at: Vector2, radius: float, clearance := DRY_CLEAR) -> bool:
	var marks := _dry_marks(at, radius)
	# THE DEEPEST SHORTFALL ANYWHERE UNDER IT. `water_level_at` answers -INF for
	# ground that is already dry, so a spot with nothing over it asks for
	# nothing and the maximum is over the wet ones alone.
	var need := 0.0
	for p: Vector2 in marks:
		var top := water_level_at(p.x, p.y)
		if is_inf(top):
			continue
		need = maxf(need, top + clearance - height_at(p.x, p.y))
	if need <= 0.0:
		return true
	# Laid at unit height first and then scaled to fit, because what six
	# overlapping basins actually come to at any one point is not worth
	# predicting when it can simply be measured. `add` returns the scar itself
	# and the amount is only read when the ground is sampled, so setting it
	# afterwards is the same as having set it now.
	var was: Array[float] = []
	for p: Vector2 in marks:
		was.append(scars.offset_at(p.x, p.y))
	var laid: Array[Dictionary] = []
	for k in DRY_RING:
		var a := TAU * float(k) / float(DRY_RING)
		var where := at + Vector2(cos(a), sin(a)) * radius * DRY_RING_AT
		laid.append(scars.add(TerrainScars.Kind.BASIN, where, TerrainScars.BUCKET, 1.0))
	var unit := INF
	for i in marks.size():
		unit = minf(unit, scars.offset_at(marks[i].x, marks[i].y) - was[i])
	if unit > 0.0:
		for scar: Dictionary in laid:
			scar["amount"] = clampf(need / unit, 0.0, TerrainScars.MOST_RELIEF)
	_sea_cache.clear()
	var touched := TerrainScars.reach_of(laid[0])
	for scar: Dictionary in laid:
		touched = touched.merge(TerrainScars.reach_of(scar))
	rebuild_around(touched)
	# Say honestly whether it worked: a nest raised in deep water may want more
	# lift than one scar is allowed to give, and pretending otherwise would put
	# the drowning back with a clean conscience.
	for p: Vector2 in marks:
		if is_underwater(p.x, p.y):
			return false
	return true


## Where `make_dry` looks: the middle, and three rings out to the rim. Enough to
## catch a channel running under one side of a footprint, which a centre sample
## alone would sail straight over.
func _dry_marks(at: Vector2, radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = [at]
	for ring in [0.4, 0.75, 1.0]:
		for k in 8:
			var a := TAU * float(k) / 8.0
			out.append(at + Vector2(cos(a), sin(a)) * radius * float(ring))
	return out


## Pour a load of something onto the ground — merging into whatever is already
## piled there — and rebuild what stands on it. See TerrainScars.deposit.
func pour(kind: int, at: Vector2, radius: float, amount: float,
		char_amount := 0.0) -> Dictionary:
	var scar := scars.deposit(kind, at, radius, amount, char_amount)
	_sea_cache.clear()
	rebuild_around(TerrainScars.reach_of(scar))
	return scar


## Grow a scar already cut into the world, and rebuild what stands on it.
func reshape(scar: Dictionary, amount: float, radius := -1.0) -> void:
	var was := TerrainScars.reach_of(scar)
	scars.reshape(scar, amount, radius)
	_sea_cache.clear()
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
			var cached = _chunks.get(Vector2i(cx, cz))
			if cached != null and is_instance_valid(cached):
				(cached as Chunk).rebuild_terrain()


## Every loaded chunk rebuilt — for restoring a save full of scars, where the
## land under the player has already been built from an unscarred seed.
func rebuild_all() -> void:
	_sea_cache.clear()
	for cell: Vector2i in _chunks:
		var cached = _chunks[cell]
		if is_instance_valid(cached):
			(cached as Chunk).rebuild_terrain()


## EVERY FLOWER WITHIN REACH, in world space. Chunks keep the spots they
## scattered their meadows on precisely so this can exist: a MultiMesh has no
## nodes, so without it the blooms are invisible to everything but the camera
## and the bees would have to settle for "somewhere grassy".
func blooms_near(at: Vector3, within: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var reach := within * within
	var lo := Vector2i(floori((at.x - within) / CHUNK_SIZE), floori((at.z - within) / CHUNK_SIZE))
	var hi := Vector2i(floori((at.x + within) / CHUNK_SIZE), floori((at.z + within) / CHUNK_SIZE))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var cached = _chunks.get(Vector2i(cx, cz))
			if cached == null or not is_instance_valid(cached):
				continue
			var chunk := cached as Chunk
			for spot: Vector3 in chunk.blooms():
				if spot.distance_squared_to(at) < reach:
					out.append(spot)
	return out


## Chunk streaming ------------------------------------------------------------

func _stream_chunks() -> void:
	_frame_began = Time.get_ticks_msec()
	var focus := focus_node.global_position
	var center := Vector2i(floori(focus.x / CHUNK_SIZE), floori(focus.z / CHUNK_SIZE))
	# THE GROUND THE CREATURE IS STANDING ON IS NEVER UNLOADED.
	#
	# Streaming followed the camera and nothing else, so a creature left to
	# itself while the player looked elsewhere fell out of the world: its chunk
	# unloaded, and with it every tree, bush, animal and herd for a hundred
	# metres in each direction. It did not starve because the world was harsh.
	# It starved because there was nothing there — it was standing in a void,
	# with its wits about it and not one thing to use them on.
	#
	# A small ring, kept alive wherever it wanders, is what lets it go on being
	# a creature when nobody is watching.
	var kept := _creature_cells()
	if _fill_near(center, kept):
		return
	_fill_sight(center)
	_shed(center, kept)


## THE NEAR RING: everywhere that has to be a PLACE. A cell here is either
## built whole or, if the far ring already drew its ground, fleshed out where it
## stands. Returns true when the frame's one chunk has been spent, so the far
## ring knows to wait its turn.
func _fill_near(center: Vector2i, kept: Dictionary) -> bool:
	# NEAREST FIRST, which it was not. This walked the square in raster order —
	# the north-west corner of the ring before the cell you are standing in —
	# so the chunk arriving on the frame you needed it was as likely to be the
	# one behind you as the one you were walking into. Rings out from the
	# middle, exactly as the far ring has always been filled.
	var made := 0
	for ring in range(0, load_radius + 1):
		for cell: Vector2i in _ring_cells(center, ring):
			if not _make_whole(cell):
				continue
			made += 1
			if _frame_spent(made):
				return true
	for cell: Vector2i in kept:
		if not _make_whole(cell):
			continue
		made += 1
		if _frame_spent(made):
			return true
	return false


## HAS THE FRAME'S SHARE OF WORLD-BUILDING BEEN SPENT?
##
## It was a COUNT — one near chunk and two far ones, every frame. A count is
## not a budget: it is a guess that every chunk costs the same, and they do not
## come close. Cutting a mesh for the far ring is a fraction of what fleshing a
## cell out costs, and fleshing one out varies by an order of magnitude with
## what happens to live on it — a cell with a village and three herds on it is
## not the cell next door with two bushes.
##
## So a frame builds whatever fits in WORLD_MILLIS, and ALWAYS AT LEAST ONE
## thing, so that a machine slow enough to blow the budget on a single chunk
## still finishes loading rather than stalling for good. The stutter that is
## left is one chunk wide, which is the smallest it can be without cutting a
## chunk in half.
func _frame_spent(made: int) -> bool:
	if made < 1:
		return false
	return Time.get_ticks_msec() - _frame_began > WORLD_MILLIS


## Make this cell a real place, whatever it is now. Returns true if that cost
## anything — false when it was already whole, which is the usual answer.
func _make_whole(cell: Vector2i) -> bool:
	var cached = _chunks.get(cell)
	if cached != null and is_instance_valid(cached):
		var chunk := cached as Chunk
		if not chunk.terrain_only:
			return false
		# THE GROUND IS ALREADY THERE AND IS NOT TOUCHED. It was cut when this
		# cell first came into view; all that arrives now is what lives on it.
		chunk.flesh_out()
		_maybe_found_village(cell)
		return true
	_spawn_chunk(cell)
	return true


## THE FAR RING: the shape of the land, as far as the camera can see it.
##
## Filled from the inside out, because the nearest missing hill is the one you
## will notice. The sweep stops for good once it finds no gaps, and starts again
## only when the focus crosses into a new cell — see `_sight_filled`.
func _fill_sight(center: Vector2i) -> void:
	if center != _sight_center:
		_sight_center = center
		_sight_filled = false
	if _sight_filled:
		return
	var made := 0
	for ring in range(load_radius + 1, sight_radius + 1):
		for cell: Vector2i in _ring_cells(center, ring):
			if _chunks.has(cell):
				continue
			_spawn_chunk(cell, true)
			made += 1
			if _frame_spent(made):
				return
	_sight_filled = true


## HOW MUCH OF THE WORLD IS ACTUALLY THERE, 0..1 — the far ring's cold fill,
## which is 121 chunks on a budget phone and 289 on a flagship and is by a
## distance the most expensive thing that happens when a game starts.
##
## It is exposed because the START SCREEN SHOULD NOT LET GO UNTIL IT IS DONE.
## The streamer is exempt from the pause precisely so this can happen behind
## the opening screen (see the header), and then the screen handed control over
## the moment somebody pressed Begin — so a player who pressed it quickly got
## the whole cold fill delivered into their first ten seconds of play, which is
## exactly what "it gets slow on the first run" is.
func land_progress() -> float:
	if _sight_filled:
		return 1.0
	var across := sight_radius * 2 + 1
	return clampf(float(_chunks.size()) / float(maxi(across * across, 1)), 0.0, 0.999)


## The cells exactly `ring` chunks out — the perimeter of the square, walked
## directly rather than sieved out of its interior.
func _ring_cells(center: Vector2i, ring: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in range(-ring, ring + 1):
		out.append(center + Vector2i(d, -ring))
		out.append(center + Vector2i(d, ring))
	for d in range(-ring + 1, ring):
		out.append(center + Vector2i(-ring, d))
		out.append(center + Vector2i(ring, d))
	return out


## LEAVING. Two thresholds now, and a chunk crosses them one at a time: past
## `unload_radius` everything living on it goes and the ground stays drawn; past
## `sight_radius` the ground goes too.
##
## Stripping rather than freeing is what makes walking back the way you came
## free. It also means the band between the two rings is the ONLY place a chunk
## is ever destroyed, and that band is well over the horizon.
##
## THE CREATURE'S OWN GROUND IS EXEMPT FROM BOTH. It is kept whole wherever the
## beast has wandered, and the exemption has to cover the free as well as the
## strip: a creature left to itself for a few minutes drifts past the far ring
## as readily as past the near one, and freeing that cell only to have
## `_creature_cells` build it again next frame is a chunk cut per frame,
## forever. A walked simulation of four minutes found exactly that — 3,035
## mesh cuts where 795 were due — before this line existed.
func _shed(center: Vector2i, kept: Dictionary) -> void:
	var coarsened := 0
	for cell: Vector2i in _chunks.keys():
		var cached = _chunks[cell]
		if not is_instance_valid(cached):
			_chunks.erase(cell)
			continue
		if kept.has(cell):
			continue          # the creature is standing here; it stays whole
		var away := (cell - center).abs()
		var out := maxi(away.x, away.y)
		if out > sight_radius:
			(cached as Chunk).queue_free()
			_chunks.erase(cell)
			continue
		var chunk := cached as Chunk
		if out > unload_radius:
			chunk.strip_down()
		# A chunk left cut for walking on that nobody can walk to. This sweep
		# runs every frame it is reached, so anything that misses its turn is
		# simply picked up on the next one — no queue, no state.
		if chunk.coarse_due() and not _frame_spent(coarsened):
			chunk.coarsen()
			coarsened += 1


## THE CELLS TO KEEP ALIVE FOR THE CREATURE, as a set. Empty when there is no
## creature, so a world without one streams exactly as it always did.
##
## Deliberately a much tighter ring than the camera's: this is enough ground for
## the beast to have a world to act in, not enough to be a second view.
func _creature_cells() -> Dictionary:
	var kept := {}
	var beast := get_tree().get_first_node_in_group("creature") as Node3D
	if beast == null or not is_instance_valid(beast):
		return kept
	var here := beast.global_position
	var mid := Vector2i(floori(here.x / CHUNK_SIZE), floori(here.z / CHUNK_SIZE))
	for dz in range(-CREATURE_KEEP, CREATURE_KEEP + 1):
		for dx in range(-CREATURE_KEEP, CREATURE_KEEP + 1):
			kept[mid + Vector2i(dx, dz)] = true
	return kept


## `bare` builds the ground and nothing else — see Chunk.terrain_only. A bare
## chunk founds no village: that waits until the cell is a place people could
## actually be living in, which is exactly when it used to happen.
func _spawn_chunk(cell: Vector2i, bare := false) -> void:
	var chunk := Chunk.new()
	chunk.terrain_only = bare
	# PAUSABLE, EXPLICITLY. This node runs even while the tree is paused so the
	# land can keep arriving, and a child inherits that unless it is told
	# otherwise — which would have quietly left every animal, herd and villager
	# in every chunk running through a pause that exists precisely to stop them.
	chunk.process_mode = Node.PROCESS_MODE_PAUSABLE
	chunk.world = self
	chunk.cell = cell
	chunk.position = Vector3(cell.x * CHUNK_SIZE, 0, cell.y * CHUNK_SIZE)
	add_child(chunk)
	_chunks[cell] = chunk
	# Seen once is seen forever, and walking a cell you had only glimpsed
	# upgrades it — never the other way about.
	var standing: int = WALKED if not bare else SEEN
	if standing > int(_known.get(cell, 0)):
		_known[cell] = standing
	if not bare:
		_maybe_found_village(cell)


## HOW WELL THIS CELL IS KNOWN: 0, SEEN or WALKED. The well fogs the first,
## dims the second and draws the third.
func knows(cell: Vector2i) -> int:
	return int(_known.get(cell, 0))


## Which cell a point on the ground falls in — the one conversion between
## metres and the units the fog is kept in, so nobody does it twice.
static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floorf(x / CHUNK_SIZE)), int(floorf(z / CHUNK_SIZE)))


## THE BOX THE KNOWN WORLD FITS IN, in cells, so the well can stop the player
## scrolling off into country that is not there. An empty world returns a
## single cell at the origin rather than an inverted rectangle.
func known_bounds() -> Rect2i:
	if _known.is_empty():
		return Rect2i(0, 0, 1, 1)
	var lo := Vector2i(2147483647, 2147483647)
	var hi := Vector2i(-2147483648, -2147483648)
	for cell: Vector2i in _known:
		lo.x = mini(lo.x, cell.x)
		lo.y = mini(lo.y, cell.y)
		hi.x = maxi(hi.x, cell.x)
		hi.y = maxi(hi.y, cell.y)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## How many cells have ever been raised, which is the honest measure of how
## much of the world this god has any business drawing.
func known_count() -> int:
	return _known.size()


## Flat triples — x, z, standing — because a dictionary keyed by Vector2i does
## not survive JSON and three ints per cell is the smallest thing that does.
func known_to_save() -> Array:
	var flat: Array = []
	for cell: Vector2i in _known:
		flat.append(cell.x)
		flat.append(cell.y)
		flat.append(int(_known[cell]))
	return flat


func known_from_save(flat: Array) -> void:
	_known.clear()
	var i := 0
	while i + 2 < flat.size():
		_known[Vector2i(int(flat[i]), int(flat[i + 1]))] = int(flat[i + 2])
		i += 3


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
	# SOME TOWNS SHOULD BE ON THE WATER. The footprint rule pushed every
	# settlement inland — dry for eighteen metres in every direction is a rule
	# a lakeshore passes only by accident — so the harbour was a building almost
	# nothing in the world could ever raise. The rule is unchanged, and now the
	# first candidate that is dry AND has a rowable body of water within reach
	# WINS OUTRIGHT; anything merely dry is kept as the fallback and the search
	# carries on looking for a coast. Costs nothing on an inland cell, where the
	# shore probe finds no water and gives up in a few dozen comparisons.
	var inland := Vector3.INF
	var found := Vector3.INF
	for attempt in 24:
		var pos := center + Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-16, 16))
		var biome := biome_at(pos.x, pos.z)
		if biome != "grassland" and biome != "savanna":
			continue
		# The WHOLE settlement footprint must be dry, not just its centre —
		# no more villages founded straddling a lakeshore.
		if not village_site_dry(pos.x, pos.z) or slope_at(pos.x, pos.z) > 0.8:
			continue
		if Waters.coast_at(pos, self):
			found = pos
			break
		if inland == Vector3.INF:
			inland = pos
	if found == Vector3.INF:
		found = inland
	if found != Vector3.INF:
		var pos := found
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
