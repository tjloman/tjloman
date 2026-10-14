class_name HotGround
extends RefCounted
## GROUND TOO HOT TO WALK ON, and the people who keep off it.
##
## Fresh lava glows for half a minute and cools over twenty seconds more
## (TerrainScars.EMBER_SECONDS, COOLING), and nothing ever told a villager so:
## they walked to their work straight across a pool still molten, and stood in
## it, because the only ground they had ever been taught to fear was water.
## Now:
##   - a step onto ground still burning is not taken: they go round it, the
##     way they go round a lake, keeping to one side once they have chosen it
##     (`heading`); and somebody standing in it walks out the coolest way.
##     Inside their own town too, where the water check is skipped (VillagerFeet);
##   - standing in it sets them alight (Villager._tick_hazards, `underfoot`);
##   - and molten ground in sight frightens them: a pool poured near people
##     sends them running, every few seconds for as long as it glows
##     (`frighten`, from LavaSkin), the volcano's lava with it.
## A burn from a fireball is ground too hot to cross while it glows as well.

## Hotter than this, a step is refused. Heat is the burn's char, falling off to
## its rim, times how molten it still is (TerrainScars.heat_at): lava is char 1,
## so a fresh pool refuses about nine tenths of the way out to its rim.
const TOO_HOT := 0.15
## Hotter than this underfoot, and they catch: further in than a toe at the rim.
const BURNS_ABOVE := 0.4
## How far past the rim of a molten pool people see it and run.
const SEEN_FROM := 10.0
## A pool frightens while it is at least this molten, and no oftener than this.
const FEARED_ABOVE := 0.5
const FRIGHTENS_EVERY := 4.0
## The turns tried for a way round, smallest first.
const TURNS: Array[float] = [25.0, 50.0, 75.0, 100.0, 130.0, 165.0]
## How far ahead a step is looked at, as shares of the probe the walker gives.
const LOOKS: Array[float] = [0.5, 1.0, 2.0]
const _SIDE := &"heat_side"


## WHICH WAY TO STEP, given the way `who` wanted to go: that way if the ground
## is cool, the first turn either side that keeps off the heat if not (the
## side kept from step to step, so they follow the edge round rather than
## dithering), out the coolest way if they are standing in it, and nowhere at
## all if they are ringed by it: they stand, and it cools.
static func heading(who: Object, pos: Vector3, desired: Vector3, world: WorldGen,
		probe: float) -> Vector3:
	if world == null or desired == Vector3.ZERO or not world.scars.hot_anywhere():
		return desired
	var scars := world.scars
	if scars.heat_at(pos.x, pos.z) > TOO_HOT:
		return _coolest(pos, desired, scars, probe)
	if not _hot_ahead(pos, desired, scars, probe):
		if who != null:
			who.set_meta(_SIDE, 0)
		return desired
	var side := int(who.get_meta(_SIDE, 0)) if who != null else 0
	for deg: float in _sweep(side):
		var turned := desired.rotated(Vector3.UP, deg_to_rad(deg))
		if not _hot_ahead(pos, turned, scars, probe):
			if who != null:
				who.set_meta(_SIDE, 1 if deg > 0.0 else -1)
			return turned
	return Vector3.ZERO


## Hot enough underfoot to set somebody alight?
static func underfoot(world: WorldGen, pos: Vector3) -> bool:
	return world != null and world.scars.heat_at(pos.x, pos.z) > BURNS_ABOVE


## A MOLTEN POOL, SEEN: everybody within SEEN_FROM of its rim who is not already
## running runs from its middle (Villager.scare, which also knows a fright
## already run from).
static func frighten(centre: Vector3, reach: float) -> void:
	var sees := reach + SEEN_FROM
	for one in CrowdClock.around(centre, sees):
		var who := one as Villager
		if who == null or not is_instance_valid(who) or who.is_afraid():
			continue
		if Vector2(who.global_position.x - centre.x, who.global_position.z - centre.z).length() < sees:
			who.scare(centre)


static func _hot_ahead(pos: Vector3, dir: Vector3, scars: TerrainScars, probe: float) -> bool:
	for share: float in LOOKS:
		if scars.heat_at(pos.x + dir.x * probe * share, pos.z + dir.z * probe * share) > TOO_HOT:
			return true
	return false


## OUT, from inside it: the coolest of sixteen headings a probe away, the one
## nearest the way they wanted to go among equals.
static func _coolest(pos: Vector3, desired: Vector3, scars: TerrainScars, probe: float) -> Vector3:
	var best := desired
	var least := INF
	for i in 16:
		var dir := desired.rotated(Vector3.UP, TAU * float(i) / 16.0)
		var heat := scars.heat_at(pos.x + dir.x * probe, pos.z + dir.z * probe) - dir.dot(desired) * 0.01
		if heat < least:
			least = heat
			best = dir
	return best


## The turns to try: the side already chosen first, smallest to largest, then
## the other; with no side chosen yet, each size both ways before the next.
static func _sweep(side: int) -> Array[float]:
	var out: Array[float] = []
	if side == 0:
		for turn: float in TURNS:
			out.append(turn)
			out.append(-turn)
		return out
	for turn: float in TURNS:
		out.append(turn * side)
	for turn: float in TURNS:
		out.append(-turn * side)
	return out
