class_name GroundGrit
extends RefCounted
## THE GRAIN OF THE GROUND, laid over the colour it already has.
##
##     "I sort of think the ground textures would be great."
##
## The land was flat colour per grid corner — two metres apart — so up close it
## read as painted card. Everything the ground SAYS is in that colour and stays
## there: the biome, the beach, the snowline, the cliff, the burn weathering to
## scrub (WorldGen.ground_color). What it was missing was any grain between the
## corners, and that is this: a texture of light and dark multiplied over the
## colour, so a meadow is still the same green — a shade deeper on average, see
## `kept` — and now has something in it.
##
## LEAN BY CONSTRUCTION. No texture files: both are made from noise on the first
## ask, a few milliseconds behind the opening screen, greyscale (one byte a
## texel), the grain 256 square and the patches 128, under a hundred kilobytes
## with their mipmaps. They are placed by world position, written into each
## ground vertex as it is cut (Chunk._grain), so every chunk still shares ONE
## material and the grain runs on across chunk borders without a seam. Reading
## them is one texture fetch a ground pixel on MEDIUM and two on HIGH; LOW keeps
## the plain colour (Quality.ground_detail).
##
## TWO SCALES, because one tiles. The grain repeats every GRIT_TILE metres, and
## from high up a repeat that short is a pattern you can see; the patches repeat
## every PATCH_TILE, a length the grain's does not divide, so the two never line
## up the same way twice in any distance you can see across.

## How many metres the grain repeats over, and the patches.
const GRIT_TILE := 6.0
const PATCH_TILE := 41.0
## Texels a side.
const GRIT_SIZE := 256
const PATCH_SIZE := 128
## How dark the darkest of each gets, against white. Gentle on purpose: this is
## a grain on a coloured land in a picture-book style, not a photograph.
const GRIT_DARKEST := 0.74
const PATCH_DARKEST := 0.86

static var _grit: ImageTexture = null
static var _patches: ImageTexture = null
static var _grit_mean := 1.0
static var _patch_mean := 1.0


## The fine grain: soil, blades, pebbles, at a few centimetres a texel.
static func grit() -> ImageTexture:
	if _grit == null:
		var made := _make(GRIT_SIZE, 7301, 0.045, 5, GRIT_DARKEST)
		_grit = made[0]
		_grit_mean = made[1]
	return _grit


## The broad patches: where the ground is a little greener or a little worn.
static func patches() -> ImageTexture:
	if _patches == null:
		var made := _make(PATCH_SIZE, 1187, 0.03, 3, PATCH_DARKEST)
		_patches = made[0]
		_patch_mean = made[1]
	return _patches


## HOW MUCH OF ITS BRIGHTNESS THE LAND KEEPS under the grain, on average, in
## linear light: the grain only darkens. NOT COMPENSATED, and that was tried and
## rendered: lifting the colour by the inverse put the brightest of the grain
## past white on land that was already the palest thing in the picture, and the
## grain vanished into it. Darkening a little on average is the better trade —
## the land had light to spare. Read by tools/live/grit_live.gd, which holds it
## to "a little".
static func kept(layers: int) -> float:
	var left := 1.0
	if layers >= 1:
		grit()
		left *= _grit_mean
	if layers >= 2:
		patches()
		left *= _patch_mean
	return left


## Where a ground vertex at this world position reads the grain, and the patches.
static func uv(world: Vector2) -> Vector2:
	return world / GRIT_TILE


static func uv2(world: Vector2) -> Vector2:
	return world / PATCH_TILE


## A tileable greyscale noise, squeezed into [darkest, 1], mipmapped. Returns
## [texture, mean brightness in linear light] — the texture is sampled as sRGB,
## so its bytes are averaged as the renderer will see them. The seamless image
## is the engine's own (C++); the squeeze is one pass over the bytes.
static func _make(size: int, noise_seed: int, frequency: float, octaves: int,
		darkest: float) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	var image := noise.get_seamless_image(size, size)
	image.convert(Image.FORMAT_L8)
	var bytes := image.get_data()
	var span := 1.0 - darkest
	var lit := PackedFloat32Array()
	lit.resize(256)
	for v in 256:
		lit[v] = Color(float(v) / 255.0, 0.0, 0.0).srgb_to_linear().r
	var total := 0.0
	for i in bytes.size():
		var v := roundi((darkest + span * float(bytes[i]) / 255.0) * 255.0)
		bytes[i] = v
		total += lit[v]
	var squeezed := Image.create_from_data(size, size, false, Image.FORMAT_L8, bytes)
	squeezed.generate_mipmaps()
	return [ImageTexture.create_from_image(squeezed), total / float(bytes.size())]
