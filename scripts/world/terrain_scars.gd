class_name TerrainScars
extends RefCounted
## LAND THAT REMEMBERS WHAT WAS DONE TO IT.
##
## Every hill in this world is derived from the world seed, which is what makes
## it endless and what makes it free: nothing about the terrain has to be
## stored, because `WorldGen.height_at()` can work any point out from noise. A
## world you can only LOOK at needs nothing more.
##
## A world you can WRECK does. So the ground is now noise PLUS A LIST OF SCARS
## — craters, cones, ripples — and `height_at()` adds them up. Everything that
## reads the land goes through that one function, so a scar propagates for free
## to collision, to water, to where villagers may build, to what the router
## thinks is walkable, and to the colour of the ground. Deform the land and the
## whole simulation agrees with you a frame later.
##
## THE COST HAS TO BE ~NOTHING, because height_at() is on every hot path in the
## game: routing, ground checks, placement, meshing. Three guards, in order:
##
##   1. NO SCARS AT ALL — one `is_empty()`, and that is the whole call. This is
##      the case for an untouched world, which is most worlds most of the time.
##   2. OUTSIDE EVERYTHING — one AABB test against the union of every scar. In
##      an endless world nearly every query is nowhere near the damage.
##   3. ACTUALLY NEAR ONE — only now does it hash into buckets, and only the
##      nine around the point, because a scar's reach is capped to a bucket.
##
## Scars are PLAY, not seed, so unlike the terrain they are written to the save.

## What shape a scar cuts. Each is a radial profile — a function of how far you
## are from the centre — which is what keeps them cheap and seamless.
enum Kind {
	CRATER,   ## a bowl with a raised lip: fireballs, force bolts
	CONE,     ## a mountain with a crater at its summit: volcanoes
	RIPPLE,   ## concentric rings, standing waves: earthquakes
	BASIN,    ## a smooth wide sink, no lip: flooding a valley
}

## Spatial hash cell, and the hard cap on how far one scar may reach. They are
## the same number on purpose: it means a point can only be touched by a scar
## centred in its own bucket or one of the eight around it, so the lookup is a
## fixed nine buckets no matter how much of the world has been cratered.
const BUCKET := 32.0

## NOTHING MAY PILE UP FOREVER. The ceiling on how far one scar can push the
## ground, in metres. Scars ADD, so without this two casts on one spot make a
## tower twice as tall as either, three make it three times, and a volcano cast
## a few times over becomes Olympus Mons. Roughly the height of the tallest
## trees plus half again — a landmark, not an orbital feature.
const MOST_RELIEF := 34.0

## How near a new deposit has to land to merge into an existing one, as a
## fraction of the larger footprint. Keeps a volcano's thirty globs down to a
## handful of scars — see `deposit`.
const MERGE_WITHIN := 0.75

## BURNED GROUND COOLS. A fireball's mark was one flat near-black colour that
## never changed, which made the world read as a scrapbook of everything that
## had ever happened to it, all equally recent. Fire has a life: it glows, it
## goes out, and what is left weathers.
##
##   0-30s      EMBER   still hot, red and orange, the mark of a fresh strike
##   30-50s             cooling through to charcoal
##   50s-4min   CHAR    black, and this is what "burned" looks like
##   4-8min             weathering out
##   past 8min  SCRUB   dusty pale ground, and it stays that way
##
## The COOLING window was twelve seconds first, and simulating the ramp against
## the refresh rate caught it: the red-to-black step is a colour distance of
## about 0.9, so over twelve seconds a two-second refresh SNAPS through it in
## six visible jumps of 0.17 each. Twenty seconds and a half-second refresh
## while anything is in that window puts the step at 0.023, which is smooth.
##
## It does not go back to grass. Scars are the world's memory, and a burned
## field that becomes indistinguishable from one that never burned has
## forgotten. Scrub IS the end state — it is just no longer smoking about it.
const EMBER_SECONDS := 30.0
const COOLING := 20.0
const CHAR_SECONDS := 240.0
const SCRUB_SECONDS := 480.0

const EMBER_COLOR := Color(1.0, 0.34, 0.07)
const CHAR_COLOR := Color(0.09, 0.07, 0.06)
const SCRUB_COLOR := Color(0.66, 0.58, 0.42)
## How strongly each stage takes over the ground under it. Scrub settles well
## short of full so the biome still shows through: old burn is a tint on the
## land, not a coat of paint over it.
const EMBER_WEIGHT := 0.95
const CHAR_WEIGHT := 0.85
const SCRUB_WEIGHT := 0.72

## Seconds of world time since this scar layer began. Advanced by WorldGen and
## saved with the scars, so a fire left burning when you quit is exactly as old
## when you come back — and an hour-old crater loads as scrub, not as embers.
var clock := 0.0

## Every scar cut into the world, and the buckets that index them.
var _scars: Array[Dictionary] = []
var _buckets := {}
## The union of every scar's footprint, for the early-out.
var _min := Vector2.ZERO
var _max := Vector2.ZERO


func is_empty() -> bool:
	return _scars.is_empty()


func count() -> int:
	return _scars.size()


## CUT THE LAND. `amount` is the peak displacement in metres — positive raises,
## negative sinks. `radius` is where the scar fades to nothing, capped so the
## bucket lookup stays a fixed size.
## `char` (0..1) blackens the ground as well as moving it, which is what makes
## a fireball's crater read as BURNED rather than merely dug.
func add(kind: int, at: Vector2, radius: float, amount: float, rings := 3.0,
		char_amount := 0.0) -> Dictionary:
	radius = clampf(radius, 1.0, BUCKET)
	var scar := {
		"kind": kind, "x": at.x, "z": at.y,
		"radius": radius, "amount": clampf(amount, -MOST_RELIEF, MOST_RELIEF),
		"rings": rings, "char": char_amount,
		# WHEN IT BURNED, on the scar layer's own clock — which is what lets the
		# mark cool from ember to char to scrub. See `weathered`.
		"burned": clock,
	}
	_scars.append(scar)
	_index(scar)
	_grow_bounds(at, radius)
	return scar


## How far the land at this point has been pushed from where the seed put it.
func offset_at(x: float, z: float) -> float:
	if _scars.is_empty():
		return 0.0
	if x < _min.x or x > _max.x or z < _min.y or z > _max.y:
		return 0.0
	var bx := floori(x / BUCKET)
	var bz := floori(z / BUCKET)
	var total := 0.0
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var here: Array = _buckets.get(Vector2i(bx + dx, bz + dz), [])
			for scar: Dictionary in here:
				total += _contribution(scar, x, z)
	return total


## HOW BURNED the ground is here, 0..1 — the raw strength of the mark, with no
## regard for how long ago it happened. `burn_at` is what the ground colour
## wants; this stays for anything only asking whether a spot has ever burned.
func scorch_at(x: float, z: float) -> float:
	return burn_at(x, z).a


## WHAT THE FIRE HAS LEFT HERE — a colour, with its strength in the alpha.
##
## One walk of the nine buckets answers both the intensity and the STAGE, and
## the strongest mark wins rather than summing, so a spot hit ten times is
## scorched earth and not a void. A fresh strike on old char re-reddens it,
## because `deposit` carries the newer burn time through the merge.
func burn_at(x: float, z: float) -> Color:
	if _scars.is_empty():
		return Color(0, 0, 0, 0)
	if x < _min.x or x > _max.x or z < _min.y or z > _max.y:
		return Color(0, 0, 0, 0)
	var bx := floori(x / BUCKET)
	var bz := floori(z / BUCKET)
	var worst := 0.0
	var tint := CHAR_COLOR
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var here: Array = _buckets.get(Vector2i(bx + dx, bz + dz), [])
			for scar: Dictionary in here:
				var burn := float(scar.get("char", 0.0))
				if burn <= 0.0:
					continue
				var ddx: float = x - float(scar["x"])
				var ddz: float = z - float(scar["z"])
				var radius: float = scar["radius"]
				var d2 := ddx * ddx + ddz * ddz
				if d2 >= radius * radius:
					continue
				# Hottest in the middle, gone by the rim.
				var t := sqrt(d2) / radius
				var stage := weathered(clock - float(scar.get("burned", 0.0)))
				var strength := burn * pow(1.0 - t, 0.8) * stage.a
				if strength > worst:
					worst = strength
					tint = Color(stage.r, stage.g, stage.b)
	tint.a = minf(worst, 1.0)
	return tint


## THE COLOUR OF A BURN THIS OLD, with its weight in the alpha. Pure arithmetic
## on the age in seconds — no state, so it gives the same answer to the mesh,
## to a test, and to anything that wants to ask ahead of time.
static func weathered(age: float) -> Color:
	if age < EMBER_SECONDS:
		return Color(EMBER_COLOR, EMBER_WEIGHT)
	if age < EMBER_SECONDS + COOLING:
		var k := (age - EMBER_SECONDS) / COOLING
		return Color(EMBER_COLOR.lerp(CHAR_COLOR, k),
			lerpf(EMBER_WEIGHT, CHAR_WEIGHT, k))
	if age < CHAR_SECONDS:
		return Color(CHAR_COLOR, CHAR_WEIGHT)
	if age < SCRUB_SECONDS:
		var k := (age - CHAR_SECONDS) / (SCRUB_SECONDS - CHAR_SECONDS)
		return Color(CHAR_COLOR.lerp(SCRUB_COLOR, k),
			lerpf(CHAR_WEIGHT, SCRUB_WEIGHT, k))
	return Color(SCRUB_COLOR, SCRUB_WEIGHT)


## SET AN EXISTING SCAR ALIGHT — for the case where the ground was reshaped
## rather than newly cut, so there is no `add` or `deposit` to carry a char in.
## Filling a crater with lava is the one that needs it: the hole's own scar is
## shrunk toward flat, and it should come out glowing.
func scorch(scar: Dictionary, char_amount: float) -> void:
	if char_amount <= 0.0:
		return
	scar["char"] = maxf(float(scar.get("char", 0.0)), char_amount)
	scar["burned"] = clock


## Is anything in the FAST part of the curve — the red-to-black cool, which is
## the only stretch that moves quickly enough to need a tight refresh? The long
## char-to-scrub fade covers about 0.5 of colour over four minutes, which is
## invisible at any refresh rate worth having.
func cooling_fast() -> bool:
	for scar in _scars:
		if float(scar.get("char", 0.0)) <= 0.0:
			continue
		var age := clock - float(scar.get("burned", 0.0))
		if age > EMBER_SECONDS - 1.0 and age < EMBER_SECONDS + COOLING + 1.0:
			return true
	return false


## Is anything here still changing colour? Once every burn has weathered out to
## scrub the ground is settled and needs re-colouring never again — which is
## what stops WorldGen's refresh running for the rest of the session.
func still_cooling() -> bool:
	for scar in _scars:
		if float(scar.get("char", 0.0)) <= 0.0:
			continue
		if clock - float(scar.get("burned", 0.0)) < SCRUB_SECONDS:
			return true
	return false


## The footprints of every scar still changing colour, so the caller can re-cut
## exactly the chunks whose ground has moved on and no others.
func cooling_areas() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for scar in _scars:
		if float(scar.get("char", 0.0)) <= 0.0:
			continue
		if clock - float(scar.get("burned", 0.0)) < SCRUB_SECONDS:
			out.append(reach_of(scar))
	return out


## One scar's push at a point. Everything is a radial profile times a falloff
## that reaches exactly zero at the rim, so scars blend into the untouched land
## and into each other without a seam.
func _contribution(scar: Dictionary, x: float, z: float) -> float:
	var radius: float = scar["radius"]
	var dx: float = x - float(scar["x"])
	var dz: float = z - float(scar["z"])
	var d2 := dx * dx + dz * dz
	if d2 >= radius * radius:
		return 0.0
	var d := sqrt(d2)
	var t := d / radius            # 0 at the centre, 1 at the rim
	var amount: float = scar["amount"]
	match int(scar["kind"]):
		Kind.CRATER:
			# A bowl, and a lip of spoil thrown up around it — the lip is what
			# makes a crater read as an impact rather than a dent.
			#
			# Both terms are scaled by `amount`, and the lip is SUBTRACTED, so
			# the spoil always goes the opposite way to the hole: a negative
			# amount digs down and throws a rim up, and a positive one would
			# raise a mound ringed by a moat. Getting this backwards made a
			# fireball build a hill.
			var bowl := cos(t * PI) * 0.5 + 0.5    # 1 at centre, 0 at rim
			var lip := sin(clampf((t - 0.55) / 0.45, 0.0, 1.0) * PI) * 0.35
			return amount * (bowl - lip)
		Kind.CONE:
			# A mountain, with its own crater bitten out of the summit. Note
			# that `amount` is the height of the UNBITTEN cone: the mouth takes
			# a chunk back out, so the summit rim peaks at about 0.70 of it and
			# the floor of the crater sits at about 0.45.
			var flank := pow(1.0 - t, 1.7)
			var mouth := maxf(0.0, 1.0 - t / 0.22)
			return amount * (flank - mouth * mouth * 0.55)
		Kind.RIPPLE:
			# Standing waves, fading to nothing at the rim. This is the land
			# still ringing from a blow.
			return amount * cos(t * PI * float(scar["rings"])) * pow(1.0 - t, 1.6)
		_:
			# BASIN: a plain smooth sink, no lip, no ringing.
			return amount * pow(cos(t * PI * 0.5), 2.0)


## POUR SOMETHING ONTO THE GROUND, merging with what is already there.
##
## A lavaball is a truckful of molten rock, and a mountain is what you get from
## throwing thirty of them at one spot. Laying thirty separate scars would work
## and would also be a quiet disaster: `offset_at` walks every scar in the nine
## buckets around a point, and it is called on every routing, placement and
## meshing query in the game, so thirty overlapping scars means thirty distance
## computations on a hot path forever after.
##
## So a deposit landing near an existing one of the same kind GROWS it instead:
## the amount adds, the footprint widens a little, and the centre creeps toward
## where the new load fell. Thirty globs settle into a handful of scars, the
## mountain still emerges from where they actually landed, and `height_at` stays
## cheap. Returns the scar that ended up holding it.
## `char_amount` blackens as `add` does, and on a merge the darker of the two
## wins — so a spot shelled over and over is one scar, burned black, rather than
## a growing pile of them.
func deposit(kind: int, at: Vector2, radius: float, amount: float,
		char_amount := 0.0) -> Dictionary:
	for scar in _scars:
		if int(scar["kind"]) != kind:
			continue
		var centre := Vector2(float(scar["x"]), float(scar["z"]))
		var gap := centre.distance_to(at)
		if gap > maxf(float(scar["radius"]), radius) * MERGE_WITHIN:
			continue
		# How much of the pile is already this scar's decides how far the centre
		# moves: a big mound barely shifts for one more truckload.
		var had: float = absf(float(scar["amount"]))
		var pull := clampf(absf(amount) / maxf(had + absf(amount), 0.001), 0.0, 0.5)
		var moved := centre.lerp(at, pull)
		scar["x"] = moved.x
		scar["z"] = moved.y
		scar["char"] = maxf(float(scar.get("char", 0.0)), char_amount)
		if char_amount > 0.0:
			scar["burned"] = clock      # a fresh strike re-reddens old char
		reshape(scar, float(scar["amount"]) + amount,
			maxf(float(scar["radius"]), radius) + gap * 0.35)
		return scar
	return add(kind, at, radius, amount, 3.0, char_amount)


## GROW A SCAR THAT IS ALREADY THERE, rather than laying another on top of it.
##
## This is what makes a mountain RISE instead of appearing: a volcano keeps one
## scar and widens and heightens it over a minute. Adding a fresh scar each time
## would sum, which is exactly how the first volcano ended up a spire.
##
## The height is capped here rather than at the call site, so no caller can
## reach past the ceiling by accident.
func reshape(scar: Dictionary, amount: float, radius := -1.0) -> void:
	if radius > 0.0:
		# Re-filed under its new footprint, since a wider scar touches more
		# buckets than it did.
		_drop_from_buckets(scar)
		scar["radius"] = clampf(radius, 1.0, BUCKET)
		_index(scar)
		_grow_bounds(Vector2(float(scar["x"]), float(scar["z"])), float(scar["radius"]))
	scar["amount"] = clampf(amount, -MOST_RELIEF, MOST_RELIEF)


func _drop_from_buckets(scar: Dictionary) -> void:
	for key: Vector2i in _buckets:
		var here: Array = _buckets[key]
		if scar in here:
			here.erase(scar)


## THE HOLE NEAREST THIS POINT, if there is one — the scar that dug it, whole.
##
## What a lavaball needs in order to FILL a crater rather than bury it. Laying a
## wide smooth dome over a narrow crater cancels the middle and leaves a ring of
## spoil around it, which is a worse landscape than the hole was. Handed the
## original scar, the filler can lay down that exact profile with the sign
## flipped, and the two cancel to nothing everywhere at once.
func hollow_near(at: Vector2, within := 7.0) -> Dictionary:
	var best := {}
	var closest := within
	for scar in _scars:
		if float(scar["amount"]) >= 0.0:
			continue                      # this one raised ground, not dug it
		var d := Vector2(float(scar["x"]), float(scar["z"])).distance_to(at)
		if d < closest:
			closest = d
			best = scar
	return best


## The square of world a scar can possibly touch — what chunks must be rebuilt.
static func reach_of(scar: Dictionary) -> Rect2:
	var r: float = scar["radius"]
	return Rect2(float(scar["x"]) - r, float(scar["z"]) - r, r * 2.0, r * 2.0)


func _index(scar: Dictionary) -> void:
	# Filed under every bucket its footprint touches, so the nine-bucket read
	# above is guaranteed to find it.
	var reach := reach_of(scar)
	var x0 := floori(reach.position.x / BUCKET)
	var x1 := floori(reach.end.x / BUCKET)
	var z0 := floori(reach.position.y / BUCKET)
	var z1 := floori(reach.end.y / BUCKET)
	for bz in range(z0, z1 + 1):
		for bx in range(x0, x1 + 1):
			var key := Vector2i(bx, bz)
			if not _buckets.has(key):
				_buckets[key] = []
			(_buckets[key] as Array).append(scar)


func _grow_bounds(at: Vector2, radius: float) -> void:
	if _scars.size() == 1:
		_min = at - Vector2(radius, radius)
		_max = at + Vector2(radius, radius)
		return
	_min.x = minf(_min.x, at.x - radius)
	_min.y = minf(_min.y, at.y - radius)
	_max.x = maxf(_max.x, at.x + radius)
	_max.y = maxf(_max.y, at.y + radius)


## Saving and loading -----------------------------------------------------------
##
## Scars are the one part of the terrain that is NOT recoverable from the seed,
## so they are the one part that has to be written down.

## The clock rides along with the scars, so ages survive the trip: a fire left
## burning when you quit is exactly as old when you come back, and a crater cut
## an hour ago loads as scrub rather than re-igniting.
func to_save() -> Dictionary:
	var out := []
	for scar in _scars:
		out.append(scar.duplicate())
	return {"clock": clock, "scars": out}


func from_save(data: Variant) -> void:
	_scars.clear()
	_buckets.clear()
	# An older save is a bare Array of scars with no clock and no burn times;
	# those load with `burned` 0 against a clock of 0, which puts them at age
	# zero — glowing. So the clock is wound past the whole weathering instead,
	# and everything already in the ground comes back settled, which is what a
	# world you left an hour ago should look like.
	var rows: Array = data if data is Array else (data as Dictionary).get("scars", [])
	clock = 0.0 if data is Array else float((data as Dictionary).get("clock", 0.0))
	if data is Array:
		clock = SCRUB_SECONDS + 1.0
	for entry in rows:
		var scar: Dictionary = entry
		var made := add(int(scar.get("kind", Kind.CRATER)),
			Vector2(float(scar.get("x", 0.0)), float(scar.get("z", 0.0))),
			float(scar.get("radius", 8.0)), float(scar.get("amount", -2.0)),
			float(scar.get("rings", 3.0)), float(scar.get("char", 0.0)))
		made["burned"] = float(scar.get("burned", 0.0))
