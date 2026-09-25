class_name Wading
extends RefCounted
## WHEN THE WATER COMES TO THEM.
##
## Walking INTO water is routed round (see NavField.water_route), but only a
## body that is walking asks. A crowd stood watching in a dry pit the god had
## blasted, a deluge filled it over them, and they stood on up to their necks
## until they were nearly dead. Villager._tick_hazards calls this the moment
## somebody who is not already running takes drowning damage.


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
