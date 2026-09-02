class_name StormCloud
extends Node3D
## WEATHER THAT LOOKS LIKE WEATHER.
##
## A rain cloud used to be five bulbous spheres that snapped into existence,
## sat perfectly still for twelve seconds, and snapped out again. It read as
## five grey balls, because that is what it was.
##
## This is a SWIRL OF SOFT LAYERS. Each layer is a wide, flat, streaked patch of
## vapour lying in the sky, and each one:
##
##   TURNS, slowly, at its own rate and in its own direction, so the whole mass
##   shears against itself the way real weather does;
##   BREATHES, scaling up and down out of phase with its neighbours, which is
##   what makes it billow rather than merely rotate;
##   COMES AND GOES, fading in somewhere, holding, fading out, and being reborn
##   somewhere else — so the cloud is never the same cloud twice and nothing
##   ever pops. The whole mass fades in when it gathers and dissolves when it
##   goes, too. Nothing in the sky appears from nothing.
##
## DEFINITION COMES FROM OVERLAP. One layer is a vague smudge; six overlapping
## at different angles, heights and opacities have edges, depth and a shape. So
## SEVERITY IS LAYER COUNT: a drizzle is a handful of pale wisps and a hurricane
## is a dark, crowded, fast-turning mass, and they are the same code.
##
## The whole thing is ONE DRAW CALL. A MultiMesh carries every layer with its
## own transform and its own colour — per-instance alpha is what lets each
## fade independently — and every layer is a single quad, two triangles. A
## hurricane's twenty-two layers come to forty-four triangles, against 1,440
## for the five spheres it replaces.
##
## The one real cost is FILL RATE: big soft transparent quads stacked over each
## other is overdraw, which is what a tiled mobile GPU minds most. That is why
## the layer count runs through the graphics budget (and so through the thermal
## band), and why the density is worked out rather than eyeballed (see the
## note on SPREAD below).

## Layers at the gentlest and fiercest weather, before the graphics budget.
const LAYERS_CALM := 7
const LAYERS_FIERCE := 22
## How wide the mass is, and how wide one layer is within it.
##
## These two together decide how CROWDED the sky looks, and getting them wrong
## is easy: the first pass spread a deluge over forty metres with smaller
## sheets, which made the fiercest weather the THINNEST — 0.9 layers deep
## against a shower's 3.7. A storm has to be denser than a drizzle, so the
## fierce spread grows less than the layer count does and the sheets grow with
## it. Worked out, that is 3.6 layers deep for a shower and 5.5 for a deluge.
const SPREAD_CALM := 9.0
const SPREAD_FIERCE := 16.0
const LAYER_CALM := 13.0
const LAYER_FIERCE := 16.0
## How much of the sky's depth the layers are spread through.
const DEPTH := 4.5

## One layer's life: fade in, hold, fade out, be reborn elsewhere.
const BORN := 1.6
const DIES := 2.2
const LIVES_MIN := 7.0
const LIVES_MAX := 16.0
## The whole mass gathering and dispersing.
const GATHER := 2.5
const DISPERSE := 3.0

## How fast layers turn and breathe. Fiercer weather turns faster.
const SPIN_CALM := 0.06
const SPIN_FIERCE := 0.30
const BREATH_MIN := 0.06
const BREATH_MAX := 0.16

## The colour of vapour, from a pale shower to a bruised storm front.
const PALE := Color(0.78, 0.80, 0.86)
const DARK := Color(0.24, 0.25, 0.32)
## How solid one layer is allowed to be. Low, because the look comes from a
## dozen of them overlapping, not from any one being opaque.
const DENSITY_CALM := 0.28
const DENSITY_FIERCE := 0.46

## The soft streaked patch every layer is drawn with. Generated once, in code,
## and shared by every cloud ever cast (see `_vapour_texture`).
const TEXTURE_SIZE := 64

static var _vapour: ImageTexture = null
static var _skin: StandardMaterial3D = null
static var _sheet: QuadMesh = null

var severity := 1.0

var _multi: MultiMesh
var _layers: Array[Dictionary] = []
var _age := 0.0
var _leaving := 0.0     # seconds left of dispersing, or 0 while it stands
var _tint := PALE


## Gather a cloud. `severity` is the potency of the working: 1 is a shower,
## 3.6 a deluge. Everything about how it looks follows from that one number.
func brew(strength: float) -> void:
	severity = clampf(strength, 0.5, 4.0)
	var fierce := clampf((severity - 1.0) / 2.6, 0.0, 1.0)
	_tint = PALE.lerp(DARK, fierce)

	var wanted := int(lerpf(LAYERS_CALM, LAYERS_FIERCE, fierce))
	# Layers are the fill-rate cost, so they take the graphics budget directly
	# rather than through the particle floor — a lesser device should genuinely
	# get a thinner cloud, and four sheets still read as one.
	var count := maxi(int(wanted * Quality.particle_scale()), 4)
	var spread := lerpf(SPREAD_CALM, SPREAD_FIERCE, fierce)
	var sheet := lerpf(LAYER_CALM, LAYER_FIERCE, fierce)
	var spin := lerpf(SPIN_CALM, SPIN_FIERCE, fierce)

	_multi = MultiMesh.new()
	_multi.transform_format = MultiMesh.TRANSFORM_3D
	_multi.use_colors = true
	_multi.mesh = _sheet_mesh()
	_multi.instance_count = count

	for i in count:
		_layers.append(_new_layer(spread, sheet, spin, true))
	var view := MultiMeshInstance3D.new()
	view.multimesh = _multi
	# A cloud is its own light source as far as we are concerned: unshaded, and
	# never casting or catching a shadow.
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)
	_write_layers()


## One layer, placed at random within the mass. `staggered` starts the cloud
## mid-life so it does not begin with every layer fading in together.
func _new_layer(spread: float, sheet: float, spin: float, staggered := false) -> Dictionary:
	var angle := randf() * TAU
	var reach := sqrt(randf()) * spread     # sqrt keeps them evenly spread, not clumped
	var lives := randf_range(LIVES_MIN, LIVES_MAX)
	return {
		"orbit": angle,
		"reach": reach,
		"height": randf_range(-DEPTH * 0.5, DEPTH * 0.5),
		"turn": randf_range(-spin, spin),
		"drift": randf_range(-spin, spin) * 0.35,
		"roll": randf() * TAU,
		"size": sheet * randf_range(0.7, 1.35),
		"breath": randf_range(BREATH_MIN, BREATH_MAX),
		"phase": randf() * TAU,
		"lives": lives,
		"age": randf() * lives if staggered else 0.0,
		"spread": spread,
		"sheet": sheet,
		"spin": spin,
	}


func _process(delta: float) -> void:
	_age += delta
	if _leaving > 0.0:
		_leaving -= delta
		if _leaving <= 0.0:
			queue_free()
			return
	for i in _layers.size():
		var layer: Dictionary = _layers[i]
		layer["age"] = float(layer["age"]) + delta
		# Turn about the middle, and roll on its own axis: the two together are
		# what make a flat sheet read as churning vapour rather than a spinning
		# plate.
		layer["orbit"] = float(layer["orbit"]) + float(layer["turn"]) * delta
		layer["roll"] = float(layer["roll"]) + float(layer["drift"]) * delta
		if float(layer["age"]) >= float(layer["lives"]):
			# Gone. Another gathers somewhere else — the cloud is never twice
			# the same cloud, and nothing ever winks out on the spot.
			_layers[i] = _new_layer(
				float(layer["spread"]), float(layer["sheet"]), float(layer["spin"]))
	_write_layers()


## Push every layer's transform and colour into the MultiMesh. This is the
## whole per-frame cost: a couple of dozen matrices.
func _write_layers() -> void:
	var mass := _mass_alpha()
	var density := lerpf(DENSITY_CALM, DENSITY_FIERCE,
		clampf((severity - 1.0) / 2.6, 0.0, 1.0))
	for i in _layers.size():
		var layer: Dictionary = _layers[i]
		var alpha := _layer_alpha(layer) * mass * density
		var breathe := 1.0 + sin(_age * float(layer["breath"]) * TAU + float(layer["phase"])) * 0.22
		var wide: float = float(layer["size"]) * breathe
		var orbit: float = float(layer["orbit"])
		var reach: float = float(layer["reach"])
		# Flat in the sky (the quad stands up by default, so it is laid down),
		# then rolled about the vertical so each sheet points its own way.
		var basis := Basis(Vector3.UP, float(layer["roll"])) \
			* Basis(Vector3.RIGHT, -PI * 0.5) \
			* Basis().scaled(Vector3(wide, wide, 1.0))
		var where := Vector3(cos(orbit) * reach, float(layer["height"]), sin(orbit) * reach)
		_multi.set_instance_transform(i, Transform3D(basis, where))
		_multi.set_instance_color(i, Color(_tint.r, _tint.g, _tint.b, alpha))


## A layer fades in when it forms and out when it goes, so no sheet ever
## appears or vanishes on the spot.
func _layer_alpha(layer: Dictionary) -> float:
	var age: float = float(layer["age"])
	var lives: float = float(layer["lives"])
	if age < BORN:
		return smoothstep(0.0, 1.0, age / BORN)
	var left := lives - age
	if left < DIES:
		return smoothstep(0.0, 1.0, left / DIES)
	return 1.0


## And the whole mass gathers rather than appearing, and disperses rather than
## being deleted.
func _mass_alpha() -> float:
	if _leaving > 0.0:
		return smoothstep(0.0, 1.0, _leaving / DISPERSE)
	return smoothstep(0.0, 1.0, _age / GATHER)


## Begin to disperse. The node frees itself once it has faded.
func disperse() -> void:
	if _leaving <= 0.0:
		_leaving = DISPERSE


## How many sheets this mass ended up with, after the graphics budget.
func layers() -> int:
	return _layers.size()


## What this cloud is, in one line — for the smoke test and the workshop.
func report() -> String:
	var fierce := clampf((severity - 1.0) / 2.6, 0.0, 1.0)
	return "%d sheets, %.0fm across, %s, turning at %.2f rad/s" % [
		_layers.size(), lerpf(SPREAD_CALM, SPREAD_FIERCE, fierce) * 2.0,
		"pale" if fierce < 0.35 else ("grey" if fierce < 0.7 else "bruised"),
		lerpf(SPIN_CALM, SPIN_FIERCE, fierce)]


## Where the rain should fall from — the underside of the mass.
func underside() -> float:
	return -DEPTH * 0.5


## The shared quad every layer is drawn with, and the material that makes it
## look like vapour. Built once for the whole game.
static func _sheet_mesh() -> QuadMesh:
	if _sheet != null:
		return _sheet
	_sheet = QuadMesh.new()
	_sheet.size = Vector2(1.0, 1.0)
	_sheet.material = _vapour_skin()
	return _sheet


static func _vapour_skin() -> StandardMaterial3D:
	if _skin != null:
		return _skin
	var m := StandardMaterial3D.new()
	m.albedo_texture = vapour_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The per-instance colour carries both the tint and the fade, which is the
	# whole reason one draw call can hold a cloud whose layers breathe apart.
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Soft sheets stacked on each other must not fight over the depth buffer,
	# or the layer that happens to be nearest punches a hole in the rest.
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	_skin = m
	return m


## A STREAKED PATCH OF VAPOUR, drawn in code like everything else in this game.
##
## Soft elliptical falloff so the sheet has no edges, multiplied by noise
## sampled with a squashed vertical so the detail runs in HORIZONTAL STREAKS —
## which is what stops a stack of these reading as a stack of fuzzy balls.
##
## Built once and shared. Sixty-four square is small enough that generating it
## costs a few milliseconds and large enough that the streaks read; it is
## warmed at world load (see MiracleManager) so no cloud ever pays for it.
static func vapour_texture() -> ImageTexture:
	if _vapour != null:
		return _vapour
	var noise := FastNoiseLite.new()
	noise.seed = 90210
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.055
	noise.fractal_octaves = 3
	# Eight bits a channel: a float texture would be four times the memory and
	# four times the bandwidth for a soft grey smudge that needs neither.
	var img := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		var v := float(y) / TEXTURE_SIZE * 2.0 - 1.0
		for x in TEXTURE_SIZE:
			var u := float(x) / TEXTURE_SIZE * 2.0 - 1.0
			# Wider than tall, so one sheet is already a streak before the
			# noise gets to it.
			var d := sqrt(u * u * 0.62 + v * v * 1.45)
			var soft := smoothstep(1.0, 0.15, d)
			# Squashing y in the noise lookup stretches the features sideways.
			var n: float = noise.get_noise_2d(float(x), float(y) * 3.4) * 0.5 + 0.5
			var a: float = pow(soft * (0.40 + 0.60 * n), 1.35)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_vapour = ImageTexture.create_from_image(img)
	return _vapour
