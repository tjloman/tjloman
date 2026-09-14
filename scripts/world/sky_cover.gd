class_name SkyCover
extends RefCounted
## THE STARS, AND THE PAINTED HORIZON WHEN THERE IS ONE.
##
## ProceduralSkyMaterial takes one `sky_cover`: an equirectangular texture whose
## colours are ADDED to the gradient, with a `sky_cover_modulate` over it. Added
## is exactly right for both things that belong up there — a star adds light to
## the sky and so does a lit cloud — and the modulate is the handle the light
## meter pulls.
##
## THE STARS ARE GENERATED AND NOT PAINTED, and that is not a shortcut. A
## painted star is always the same brightness, so it cannot come out slowly as
## the eye adapts — and arriving slowly is the whole of what makes walking away
## from a campfire feel like anything. Generated, they live on one channel the
## meter drives. See LightMeter.starlight.
##
## THE SAME FIELD EVERY SESSION. Seeded from a constant, because constellations
## a player half-learns are worth more than fresh noise, and a sky that is
## different every time you load is a sky nobody ever looks at twice.
##
## THE PAINTED BAND, when res://sky/band.* exists, is composited into the same
## image at the horizon — one texture, one slot, built once at boot. See
## sky/README.md for what it has to be.

## Equirectangular, so twice as wide as it is tall. A star is one or two pixels
## and wants the resolution; the sky is the one texture in this game that is
## looked at across the whole screen.
const WIDE := 1024
const TALL := 512
## How many stars, at the top tier. Thinned on a budget device with the rest.
const STARS := 1400
## The seed the sky is made from. Change it and every constellation changes.
const SKY_SEED := 20250914

## Where a painted horizon band is looked for, and the names tried in order.
const BAND_DIR := "res://sky/"
const BAND_NAMES: Array[String] = ["band", "horizon", "sky"]
const BAND_EXTS: Array[String] = [".png", ".webp", ".jpg", ".jpeg", ".exr"]

static var _made: ImageTexture = null


## The cover, built once and kept. Null is never returned — a sky with no stars
## in it is still a sky, but there is no reason to have one.
static func texture() -> ImageTexture:
	if _made != null:
		return _made
	var img := Image.create_empty(WIDE, TALL, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_scatter(img)
	_milky(img)
	_band(img)
	img.generate_mipmaps()
	_made = ImageTexture.create_from_image(img)
	return _made


## THE STARS. Placed on the sphere rather than on the rectangle: an equirect
## image is enormously stretched at the poles, so scattering uniformly in UV
## puts a dense cap of stars directly overhead and a bare band at the horizon —
## which is precisely backwards from what anybody has ever seen.
##
## Sampling `v` by arccos of a uniform gives equal area on the sphere, which is
## the same trick as scattering points on a globe.
static func _scatter(img: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SKY_SEED
	var many := int(STARS * clampf(Quality.particle_scale(), 0.4, 1.0))
	for i in many:
		var u := rng.randf()
		# -1..1 uniform, then to a row: equal area, so no crowding at the poles.
		var y := 1.0 - 2.0 * rng.randf()
		var px := int(u * WIDE) % WIDE
		var py := clampi(int((1.0 - (asin(y) / PI + 0.5)) * TALL), 0, TALL - 1)
		# Most stars are faint. A handful are not, and those are the ones a
		# player actually uses to tell one patch of sky from another.
		var mag := pow(rng.randf(), 3.2)
		var bright := 0.10 + 0.90 * mag
		# Blue-white to warm amber, with the hot ones commoner, as they look.
		var warm := pow(rng.randf(), 2.0)
		var tint := Color(0.78, 0.86, 1.0).lerp(Color(1.0, 0.84, 0.66), warm)
		_dot(img, px, py, tint * bright, mag)
	# Nothing below the horizon: the cover wraps the whole sphere and the lower
	# half of it is under the ground.
	for y2 in range(TALL / 2, TALL):
		for x2 in WIDE:
			img.set_pixel(x2, y2, Color(0, 0, 0, 0))


## One star, with a soft neighbour or two if it is a bright one — a single lit
## pixel disappears the moment the texture is filtered or mipped.
static func _dot(img: Image, px: int, py: int, colour: Color, mag: float) -> void:
	_add(img, px, py, colour)
	if mag < 0.55:
		return
	var halo := colour * 0.28
	_add(img, px + 1, py, halo)
	_add(img, px - 1, py, halo)
	_add(img, px, py + 1, halo)
	_add(img, px, py - 1, halo)


static func _add(img: Image, px: int, py: int, colour: Color) -> void:
	if py < 0 or py >= TALL:
		return
	var x := ((px % WIDE) + WIDE) % WIDE     # the sky wraps; the image must too
	var was := img.get_pixel(x, py)
	img.set_pixel(x, py, Color(
		minf(was.r + colour.r, 1.0), minf(was.g + colour.g, 1.0),
		minf(was.b + colour.b, 1.0), 1.0))


## A FAINT BAND ACROSS THE WHOLE SKY. One diagonal smear of unresolved stars is
## the single thing that stops a scattered field reading as noise — it gives the
## sky a direction, and a direction is what makes it look like somewhere rather
## than like a screensaver.
static func _milky(img: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SKY_SEED + 1
	for i in 9000:
		var u := rng.randf()
		# The band runs at a slant and sags: a sine across the width, with the
		# scatter tight to it and a long tail away from it.
		var mid := 0.30 + 0.13 * sin(u * TAU + 0.7)
		var spread := rng.randfn(0.0, 0.035)
		var v := clampf(mid + spread, 0.0, 0.49)
		var px := int(u * WIDE) % WIDE
		var py := int(v * TALL)
		var faint := 0.035 * (1.0 - absf(spread) * 14.0)
		if faint <= 0.0:
			continue
		_add(img, px, py, Color(0.72, 0.76, 0.92) * faint)


## THE PAINTED HORIZON, if anybody has painted one. Added into the rows either
## side of the horizon line, left alone entirely when the file is absent — which
## is the state this ships in.
static func _band(img: Image) -> void:
	var src := _find_band()
	if src == null:
		return
	src.resize(WIDE, TALL / 2, Image.INTERPOLATE_LANCZOS)
	src.convert(Image.FORMAT_RGBA8)
	for y in TALL / 2:
		for x in WIDE:
			var paint := src.get_pixel(x, y)
			if paint.a <= 0.004:
				continue
			_add(img, x, y, Color(paint.r, paint.g, paint.b) * paint.a)


static func _find_band() -> Image:
	for stem: String in BAND_NAMES:
		for ext: String in BAND_EXTS:
			var path := BAND_DIR + stem + ext
			if not ResourceLoader.exists(path):
				continue
			var res := load(path)
			if res is Texture2D:
				return (res as Texture2D).get_image()
	return null
