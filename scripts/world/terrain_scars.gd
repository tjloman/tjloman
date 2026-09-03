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


## HOW BURNED the ground is here, 0..1 — read by `WorldGen.ground_color`, so a
## fireball leaves a black mark on the world and not just a dent in it. Fades
## to nothing at the rim like everything else, and saturates rather than sums
## so a spot hit ten times is scorched earth, not a void.
func scorch_at(x: float, z: float) -> float:
	if _scars.is_empty():
		return 0.0
	if x < _min.x or x > _max.x or z < _min.y or z > _max.y:
		return 0.0
	var bx := floori(x / BUCKET)
	var bz := floori(z / BUCKET)
	var worst := 0.0
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
				worst = maxf(worst, burn * pow(1.0 - t, 0.8))
	return minf(worst, 1.0)


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

func to_save() -> Array:
	var out := []
	for scar in _scars:
		out.append(scar.duplicate())
	return out


func from_save(data: Array) -> void:
	_scars.clear()
	_buckets.clear()
	for entry in data:
		var scar: Dictionary = entry
		add(int(scar.get("kind", Kind.CRATER)),
			Vector2(float(scar.get("x", 0.0)), float(scar.get("z", 0.0))),
			float(scar.get("radius", 8.0)), float(scar.get("amount", -2.0)),
			float(scar.get("rings", 3.0)), float(scar.get("char", 0.0)))
