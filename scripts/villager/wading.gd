class_name Wading
extends RefCounted
## WHEN THE WATER COMES TO THEM.
##
## Walking INTO water is routed round (see NavField.water_route), but only a
## body that is walking asks. A crowd stood watching in a dry pit the god had
## blasted, a deluge filled it over them, and they stood on up to their necks
## until they were nearly dead. Villager._tick_hazards calls this the moment
## somebody who is not already running takes drowning damage.

## How often dry ground is asked whether it is still dry. See `drown`.
const WATER_EVERY := 0.5


## DEEP WATER, one tick of it. True when the caller should stop there — the
## child was spared, or they have gone under.
##
## Against whatever water is ACTUALLY here — the sea, or a pond standing in a
## flooded crater. This once read the sea's constant, so a pond was
## "underwater" for farming, pathing and catching fire, but not for drowning.
##
## ASKED TWICE A SECOND, not every tick. Two land reads a villager a tick was a
## thousand a tick for a town of five hundred, to learn that dry ground was
## still dry; nobody walks into deep water in half a second. While they ARE in
## it, it is asked every tick, so they wade out on time.
static func drown(who: Villager, world: WorldGen, delta: float) -> bool:
	who._water_check -= delta
	var here := who.global_position
	if who._water_check <= 0.0 or who._water_surface > -INF:
		who._water_check = WATER_EVERY
		var level := world.water_level_at(here.x, here.z)
		var depth := level - world.height_at(here.x, here.z)
		who._water_surface = level if depth > Villager.DROWN_DEPTH else -INF
	var surface: float = who._water_surface
	if surface == -INF or here.y >= surface + 0.4:
		return false
	if ChildSafety.spared(who):
		return true    # out of the water and away home: no slow drowning to watch
	if who.burning:
		who.extinguish()  # water douses the flames, but the drowning goes on
	if who.state != Villager.State.FLEE:
		out(who, world)
	who.health -= Villager.HAZARD_RATE * delta
	if who.health <= 0.0:
		who.enter_dying()
		return true
	return false


## OUT, by the shallowest way. The water is level, so shallowest is uphill is
## shoreward — the same rule NavField._least_bad walks by, which the FLEE arm's
## own routing then keeps to, since it is already standing in the water.
static func out(who: Villager, world: WorldGen) -> void:
	var here := who.global_position
	var best := Vector3.FORWARD
	var shallowest := INF
	for i in 8:
		var a := TAU * float(i) / 8.0
		var way := Vector3(cos(a), 0.0, sin(a))
		var x := here.x + way.x * 3.0
		var z := here.z + way.z * 3.0
		var deep := world.water_level_at(x, z) - world.height_at(x, z)
		if deep < shallowest:
			shallowest = deep
			best = way
	who._dismount()
	who.state = Villager.State.FLEE
	who._flee_from = here - best * 5.0
	who._action_time = Villager.FRIGHT_SECONDS
	who._decision_due = false        # out NOW, not when the line reaches them
	who._pitch_body(0.0)
