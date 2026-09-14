class_name LightMeter
extends RefCounted
## A LIGHT SENSOR ON THE CAMERA BODY.
##
## How bright it is WHERE THE PLAYER IS, and what their eyes have made of that.
##
## WHY NOT THE RENDERER'S OWN. Godot can meter the rendered frame
## (CameraAttributesPractical.auto_exposure), and for this game it is the wrong
## instrument for two reasons:
##
##   MOST OF THE LIGHT IN THIS WORLD IS NOT LIGHT. Torches and lit windows are
##   emissive billboards with no OmniLight behind them at all — deliberately,
##   so a village ablaze stays cheap. A luminance histogram reads PIXELS, so a
##   torchlit street meters as a few bright specks on a dark field rather than
##   as a lit place. The game knows where every hearth, torch and window is.
##   The renderer has to guess.
##
##   AND A FRAME METER IS FOOLED BY WHERE YOU POINT. Tilt up to the sky and it
##   stops down; tilt at the ground and it opens up. On a camera that pans
##   constantly over a landscape that is an exposure that never settles. A
##   sensor on the camera's POSITION does not do that.
##
## THE ADAPTATION IS THE WHOLE EFFECT, and it has to be lopsided. A pupil
## constricts in a moment and the rods take minutes; being blinded for a long
## time is merely annoying, and a dark that arrives instantly is not a dark you
## ever felt your eyes open in. So brightening is nearly immediate and darkening
## takes about nine seconds — which is what makes the stars ARRIVE when you walk
## away from the fire instead of being switched on.
##
## WHAT READS IT: the exposure, how much colour the eye is getting (see
## `colour`), and how many stars are out. Nightfall owns one of these and ticks
## it; main.gd reads it into the Environment.

## The sky, from black to noon. Real daylight is some hundred thousand times a
## full moon and no game can use that range, so it is compressed hard: what
## matters is the ORDER — noon, overcast, dusk, moon, starlight — not the ratio.
const MOON_LUX := 0.045
const STAR_LUX := 0.008
## Where the sun's elevation puts the day between those and full daylight.
const DAY_FROM := -0.14
const DAY_TO := 0.28

## What one hearth is worth at its own centre, and one carried torch.
##
## A TOTEM IS MIDDLING. Standing at one should thin the sky, not close it: a
## town is a lit place and you can still see the brighter stars over it. At
## LOCAL_WASH it wiped them entirely, which made every village a hole in the
## night. Half of that leaves the sky about half out.
const HEARTH_LUX := 0.155
const TORCH_LUX := 0.011
## How far a village's torchlight is still worth counting.
const TOWN_REACH := 70.0
## And the creature, which is a lantern that follows you about. Deliberately
## generous: a blazing saintly creature SHOULD cost you the night sky, and a
## dim one should let you have it back. That is a trade worth being able to
## feel.
const HALO_LUX := 0.22

## THE CREATURE'S OWN HEARTH, which is a different thing from a village's: it
## is a bonfire in a walled yard and you are meant to be dazzled by it. Over
## LOCAL_WASH, so the sky closes completely inside the nest and opens again as
## you walk out of it.
const NEST_LUX := 0.36
const NEST_REACH := 26.0

## Seconds to adapt. See the class note: these are not the same number and the
## difference is the point.
const OPEN_UP := 9.0        # into the dark — slow, and felt
const STOP_DOWN := 0.4      # out of it — nearly at once

## What the exposure runs between. 1.0 is what the game shipped with, so a lit
## day looks as it always did and only the dark is lifted.
const EXPOSURE_DARK := 1.85
const EXPOSURE_LIGHT := 0.92
## How much colour survives at the bottom. Not zero: a scotopic eye is not a
## black-and-white film, it is a blue one that has lost its reds — which is why
## this pairs with a cold cast rather than replacing it.
const COLOUR_FLOOR := 0.38

## HOW MUCH LIGHT IN YOUR OWN EYES puts the stars out, over and above whatever
## the sky is doing.
##
## SET TO A WHOLE HEARTH ON PURPOSE, so standing at a fire wipes the sky
## exactly and the gate starts opening the instant you turn away from it. Set
## lower — it was a third of this — and the surplus has to decay past the
## threshold before anything at all happens, which buys eight seconds of
## nothing followed by a rush. The arrival should BEGIN at once and take its
## time finishing, which is what walking away from a fire is actually like.
##
## It also prices the other sources honestly: a town on the horizon barely
## touches the stars, and a creature blazing beside you cuts them to a third.
const LOCAL_WASH := 0.30
## And how bright the sky itself has to get before it does the wiping. Dusk is
## about 0.3 and that is roughly where the last of them go.
const SKY_WASH_FROM := 0.02
const SKY_WASH_TO := 0.34

## Above this the sensor is saturated — a fireball, a volcano, a firestorm. The
## exposure slams down, everything not alight goes black by contrast, and there
## are no stars at all. The top end of the same instrument.
const GLARE_AT := 2.2

var _lux := 1.0
var _adapted := 1.0


## Take a reading, and let the eye move toward it. Called on a slow tick; the
## adaptation is time-based, so the rate it is called at does not change how it
## feels — only how smoothly.
func tick(at: Vector3, hearths: Array[OmniLight3D], tree: SceneTree,
		delta: float) -> void:
	_lux = _sky() + _local(at, hearths, tree)
	var toward := STOP_DOWN if _lux > _adapted else OPEN_UP
	_adapted = lerpf(_adapted, _lux, 1.0 - exp(-delta / toward))


## THE SKY'S OWN CONTRIBUTION. Starlight is the floor and it never goes out —
## that is what makes a moonless night readable rather than a black screen.
func _sky() -> float:
	var elev := GameState.sun_elevation()
	var day := smoothstep(DAY_FROM, DAY_TO, elev)
	# The moon rides opposite the sun, so it is strongest when the sun is
	# furthest down — which is exactly when it is wanted.
	var moon := MOON_LUX * clampf(-elev, 0.0, 1.0)
	return STAR_LUX + moon + (1.0 - STAR_LUX - moon) * day


## EVERYTHING BURNING NEARBY. Three sources, because three are what the world
## actually has: the hearth pool Nightfall follows the camera with, the torches
## a town carries after dark, and the creature's own radiance.
func _local(at: Vector3, hearths: Array[OmniLight3D], tree: SceneTree) -> float:
	# `got` and not `lux`: this class has a `lux()` method, and a local of that
	# name shadows it at every load.
	var got := 0.0
	for light in hearths:
		if not is_instance_valid(light) or light.light_energy <= 0.01:
			continue
		var reach := maxf(light.omni_range, 1.0)
		var fade := clampf(1.0 - light.global_position.distance_to(at) / reach, 0.0, 1.0)
		got += HEARTH_LUX * light.light_energy / 2.2 * fade * fade
	for v in tree.get_nodes_in_group("village"):
		var town := v as Village
		if not is_instance_valid(town):
			continue
		var away := town.global_position.distance_to(at)
		if away > TOWN_REACH:
			continue
		var fade := 1.0 - away / TOWN_REACH
		got += TORCH_LUX * float(_torches_lit(town)) * fade * fade
	var beast := tree.get_first_node_in_group("creature") as Node3D
	if beast != null and is_instance_valid(beast):
		var fade := clampf(1.0 - beast.global_position.distance_to(at) / 30.0, 0.0, 1.0)
		got += HALO_LUX * fade * fade
	# THE NEST IS THE BRIGHTEST PLACE IN THE WORLD THAT IS NOT ON FIRE. It has
	# a hearth of its own that Nightfall's pool knows nothing about — the pool
	# only ever deals to village totems — so a player standing in their own
	# creature's nest had a full sky of stars over a bonfire. Metered over the
	# wash threshold on purpose: no stars here at all.
	for n in tree.get_nodes_in_group("creature_nest"):
		var nest := n as Node3D
		if not is_instance_valid(nest):
			continue
		var fade := clampf(1.0 - nest.global_position.distance_to(at) / NEST_REACH, 0.0, 1.0)
		got += NEST_LUX * fade * fade
	return got


## HOW MANY FLAMES ARE BURNING OVER A TOWN RIGHT NOW.
##
## Reaches into Village's own MultiMesh rather than asking it, because Village
## is at its public-method ceiling and this is the only caller. It is also the
## only way to know: the torches are billboards, not lights, so there is nothing
## in the renderer that knows they are there at all.
func _torches_lit(town: Village) -> int:
	var lit := town._torches
	if lit == null or not is_instance_valid(lit) or not lit.visible:
		return 0
	return lit.multimesh.instance_count


## WHAT THE EYE HAS SETTLED ON, 0 (fully dark-adapted) to 1 (broad day) and
## beyond 1 when something is on fire.
func adapted() -> float:
	return _adapted


## What is actually out there this instant, before the eye has caught up.
func lux() -> float:
	return _lux


## How far open the shutter should be. Falls below 1 in daylight and in glare,
## rises in the dark.
func exposure() -> float:
	var t := clampf(_adapted / GLARE_AT, 0.0, 1.0)
	return lerpf(EXPOSURE_DARK, EXPOSURE_LIGHT, sqrt(t))


## HOW MANY STARS ARE OUT, 0..1. Two gates, and both have to open: the eye has
## to be dark-adapted AND the sky has to actually be dark. Standing in a cellar
## at noon does not show you the Milky Way.
func starlight() -> float:
	var sky := _sky()
	# THE TWO GATES MUST MEASURE DIFFERENT THINGS, which the first version of
	# this did not: both asked how dark it was, so on a clear night each
	# returned about 0.86 and multiplying them capped the sky at 0.74. The
	# stars never fully arrived however long you stood in the dark.
	#
	# What the EYE gate is actually about is light in your own eyes — the fire
	# you are standing at — which is the ADAPTED level above and beyond the
	# sky's own. Walk away from the hearth and that surplus drains at OPEN_UP,
	# so the stars arrive over about nine seconds and then all of them are out.
	var wash := 1.0 - smoothstep(0.0, LOCAL_WASH, _adapted - sky)
	var dark_sky := 1.0 - smoothstep(SKY_WASH_FROM, SKY_WASH_TO, sky)
	return clampf(wash, 0.0, 1.0) * clampf(dark_sky, 0.0, 1.0)


## HOW MUCH COLOUR THE EYE IS GETTING, 0 (scotopic) to 1 (full daylight).
##
## The Purkinje shift, which is a real thing and the reason a moonlit field
## looks the way it does: as the rods take over, reds collapse toward black and
## the blue-greens hold on. So a dark-adapted wood genuinely goes cold and
## desaturated — and a torch you are carrying pulls a pool of true colour along
## with you, which is most of why carrying one feels like something.
func colour() -> float:
	return lerpf(COLOUR_FLOOR, 1.0, clampf(_adapted / 0.5, 0.0, 1.0))
