class_name GroundRing
extends MeshInstance3D
## THE EDGE OF WHAT YOU HOLD, STANDING ON THE GROUND IT CLAIMS.
##
## It was a torus lying flat at one height, which is only the truth on a
## billiard table. Every ring in this game is drawn around something standing on
## rolling country, so half of it floated a metre over a rise and the other half
## was buried in the next one — and a boundary you cannot trust the look of is
## worse than no boundary drawn at all, because the player believes it.
##
##     "Let's make the influence rings rise/lower to emanate from the terrain.
##      They should appear like a ring of smoldering fire, or hints of radiant
##      beams (evil/good respectively)."
##
## So it is a CURTAIN rather than a hoop: a ribbon of quads standing upright all
## the way round, each pair of corners planted at the height of the ground under
## it. It climbs the hill and goes down into the dip with the land, and it is
## drawn fading out at the top, so what the player sees is the ground itself
## giving something off along a line.
##
## WHAT IT GIVES OFF depends on what the god has become. A cruel reign gets
## EMBERS — a ragged, uneven, flickering edge, as if the boundary were smoulder-
## ing. A kind one gets BEAMS — even, upright, quiet shafts standing in a row.
## Both are the same geometry and the same tint; the difference is one texture
## and the speed things move at, which is what keeps this cheap enough to have
## one around every village at once.
##
## AND THE GROUND IS ONLY READ WHEN IT MUST BE. Every corner of the ribbon is a
## question put to the terrain, and terrain reads are the most expensive thing
## in this game's frame (see WorldGen.reads and the meter's land-reads line). A
## village never moves, so its ring is built once and then sits there. The
## creature's ring follows a walking animal, so it is rebuilt only when the beast
## has actually gone somewhere — a metre and a half, or a twentieth of the
## ring's own width, whichever is larger. A ring around a giant is wide enough
## that it can afford to be lazier about it than one around a whelp.

## Corners around the circle. Sixty-four is smooth at a hundred metres and is
## also sixty-four questions for the terrain, which is the real budget.
const SEGMENTS := 64
## How tall the curtain stands, and how far its feet are lifted off the grass so
## it never z-fights the ground it is planted on.
const STANDS := 1.7
const LIFT := 0.1
## When it is worth asking the ground again: this far moved, or this much of the
## ring's own radius, whichever is the larger.
const MOVED := 1.5
const MOVED_SHARE := 0.05
const GREW := 0.5
## How fast the fire licks along the edge, and the beams drift, in texture
## widths a second. Embers hurry; light does not.
const EMBERS_RUN := 0.5
const BEAMS_RUN := 0.08
## And how much the smoulder gutters, as a share of its own glow.
const GUTTERS := 0.22
const GUTTER_HZ := 5.7
## Below this the god is cruel enough to burn rather than shine.
const BURNS_BELOW := 0.0

static var _ember_plate: ImageTexture = null
static var _beam_plate: ImageTexture = null

var _skin: StandardMaterial3D
var _built_at := Vector3.INF
var _built_r := -1.0
var _burning := true
var _flow := 0.0
var _colour := Color.WHITE
var _glow := 1.0


func _ready() -> void:
	_skin = StandardMaterial3D.new()
	_skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_skin.vertex_color_use_as_albedo = true
	# A LIGHT, NOT A SURFACE. It is unlit on purpose — a boundary that dimmed at
	# dusk would say the god's hold on the land comes and goes with the sun —
	# and it writes no depth, so the near side of the ring cannot punch a hole
	# in the far side of it.
	_skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_skin.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	_skin.disable_receive_shadows = true
	_skin.texture_repeat = true
	_skin.albedo_texture = _burn_plate()
	material_override = Util.lit(_skin)


## STAND ON THIS GROUND. Rebuilds the ribbon only if the circle has actually
## moved or changed size — see the note above about terrain reads.
func stand_on(centre: Vector3, radius: float, world: WorldGen) -> void:
	if world == null or radius <= 0.0:
		return
	var stir: float = maxf(MOVED, radius * MOVED_SHARE)
	if _built_r > 0.0 and absf(radius - _built_r) < GREW \
			and _built_at.distance_to(centre) < stir:
		return
	_built_at = centre
	_built_r = radius
	_raise(centre, radius, world)


## WHAT IT LOOKS LIKE: the god's own colour, and whether this ground smoulders
## or shines. `align` is -1..+1 as the rest of the game speaks it.
func tint(colour: Color, align: float, glow := 1.0, alpha := 1.0) -> void:
	var burns := align < BURNS_BELOW
	if burns != _burning:
		_burning = burns
		_skin.albedo_texture = _burn_plate() if burns else _shine_plate()
	_colour = colour
	_glow = glow
	_skin.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	_skin.emission_enabled = true
	_skin.emission = colour
	_burn(0.0)


## ONE FRAME OF IT BEING ALIVE, KEPT BY THE RING ITSELF.
##
## The fire runs along the edge and the beams drift, both by moving the texture
## rather than the geometry — the ribbon is rebuilt only when the thing it
## belongs to walks, and nothing else should ever touch it.
##
## It keeps its own time because the callers do not have one. A village's ring
## is told its colour when the population or the belief changes, which is every
## few minutes; a ring that guttered only when it was recoloured would sit dead
## still around every town in the world and flicker once, briefly, when somebody
## was born. Anything drawn as fire has to burn on its own clock.
func _process(delta: float) -> void:
	Ledger.open(&"GroundRing")
	if not visible:
		return
	_flow += delta
	_skin.uv1_offset.x -= (EMBERS_RUN if _burning else BEAMS_RUN) * delta
	_burn(delta)


## The glow, with the gutter of the moment on it. Steady light does not gutter:
## a beam that flickered would be a candle.
func _burn(_delta: float) -> void:
	var gutter := 1.0
	if _burning:
		gutter = 1.0 + sin(_flow * GUTTER_HZ) * GUTTERS \
			+ sin(_flow * GUTTER_HZ * 0.37) * GUTTERS * 0.5
	_skin.emission_energy_multiplier = maxf(_glow * gutter, 0.0)


## THE RIBBON ITSELF. Two corners at every step around the circle — one planted
## on the ground, one STANDS above it — and the top corners are transparent, so
## the whole thing reads as coming up out of the land rather than as a wall
## standing on it.
func _raise(centre: Vector3, radius: float, world: WorldGen) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	# One texture width every four metres of edge, so a hamlet's ring and an
	# empire's are made of the same size of flame.
	var repeats: float = maxf(radius * TAU / 4.0, 1.0)
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var a := t * TAU
		var dx := cos(a) * radius
		var dz := sin(a) * radius
		var ground := world.surface_at(centre.x + dx, centre.z + dz) - centre.y + LIFT
		verts.append(Vector3(dx, ground, dz))
		verts.append(Vector3(dx, ground + STANDS, dz))
		uvs.append(Vector2(t * repeats, 1.0))
		uvs.append(Vector2(t * repeats, 0.0))
		colours.append(Color(1.0, 1.0, 1.0, 1.0))
		colours.append(Color(1.0, 1.0, 1.0, 0.0))
	var faces := PackedInt32Array()
	for i in SEGMENTS:
		var b := i * 2
		faces.append_array([b, b + 1, b + 2, b + 2, b + 1, b + 3])
	var bits := []
	bits.resize(Mesh.ARRAY_MAX)
	bits[Mesh.ARRAY_VERTEX] = verts
	bits[Mesh.ARRAY_TEX_UV] = uvs
	bits[Mesh.ARRAY_COLOR] = colours
	bits[Mesh.ARRAY_INDEX] = faces
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bits)
	mesh = built


## A RAGGED EDGE OF FLAME, in alpha only — the colour comes from the tint, so
## one plate serves a red reign and a black one.
static func _burn_plate() -> ImageTexture:
	if _ember_plate != null:
		return _ember_plate
	_ember_plate = _plate(true)
	return _ember_plate


## AND AN EVEN ROW OF SHAFTS.
static func _shine_plate() -> ImageTexture:
	if _beam_plate != null:
		return _beam_plate
	_beam_plate = _plate(false)
	return _beam_plate


static func _plate(ragged: bool) -> ImageTexture:
	var wide := 64
	var tall := 32
	var img := Image.create(wide, tall, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 24601 if ragged else 1337
	var reach := PackedFloat32Array()
	for x in wide:
		if ragged:
			# Flames of every height, and enough of them touching that the edge
			# reads as one fire rather than as a row of candles.
			reach.append(rng.randf_range(0.35, 1.0))
		else:
			# Shafts: mostly nothing, and every so often one standing its full
			# height. Light comes in beams or it does not come.
			reach.append(1.0 if x % 8 < 2 else rng.randf_range(0.0, 0.16))
	for x in wide:
		for y in tall:
			var up := 1.0 - float(y) / float(tall - 1)   # 0 at the feet
			var high: float = reach[x]
			var lit := 0.0
			if up < high:
				lit = 1.0 - up / maxf(high, 0.001)
				lit = pow(lit, 1.6 if ragged else 2.4)
			img.set_pixel(x, tall - 1 - y, Color(1.0, 1.0, 1.0, lit))
	return ImageTexture.create_from_image(img)
