class_name TreeArt
extends RefCounted
## STAND-IN PLATES FOR TREES SEEN FROM A LONG WAY OFF.
##
## Past Quality.clutter_distance a real tree stops drawing, and until now that
## was the end of it: the far ring was bare ground to the horizon, and a wood
## arrived all at once as you walked into it. What stands out there instead is
## one of these — a painted tree on a quad that turns to face you, two triangles
## and no node at all, drawn for a whole chunk in a single MultiMesh.
##
## Like CritterArt, the drawings are STAND-INS painted at boot. The briefs below
## say what each one has to be, so a person can paint the real thing later and
## change nothing else. Four plates of 64x64 RGBA with mipmaps is about 340 KB,
## painted once and shared by every tree in the world of that kind.
##
## MIPMAPS ARE NOT OPTIONAL HERE. A plate is about 26 pixels tall at two hundred
## metres, and a 64-pixel drawing sampled down to that without them crawls and
## sparkles the moment the camera moves — which is precisely when these are
## being looked at.

const SIZE := 64
## Below this much lumber a tree is not worth boarding. At lumber 4 — the
## smallest a scattered tree is ever spawned at — a conifer is 5.6m and reads as
## about 26 pixels at two hundred metres. At lumber 1, a replanted seedling, it
## is 1.2m and six pixels of nothing.
const LEAST_LUMBER := 4.0

## WHAT AN ARTIST WOULD BE HANDED. `trunk` is how far up the plate the bole
## reaches, `crown` the shape sitting on it, and the colours are the ones the
## real tree is actually built from — see WildTree._ready, which reads them from
## here so the two can never drift apart.
const PLATES := {
	"forest": {
		"crown": "cone", "trunk": 0.57, "bole": 0.045,
		"bark": Color(0.42, 0.3, 0.18), "leaf": Color(0.2, 0.45, 0.2),
		"brief": "a conifer read from any side: one straight bole, a single"
			+ " dense spire of needles starting a little below the crown break"
			+ " and tapering to a point; ragged at the edge, never a clean"
			+ " triangle, and darker on the lower half where the light does"
			+ " not reach",
	},
	"grassland": {
		"crown": "cone", "trunk": 0.57, "bole": 0.045,
		"bark": Color(0.42, 0.3, 0.18), "leaf": Color(0.28, 0.52, 0.24),
		"brief": "as the forest tree but lighter and a touch more open — a"
			+ " field tree that has had room, so the crown is broader and the"
			+ " sky shows through it in places",
	},
	"savanna": {
		"crown": "plate", "trunk": 0.88, "bole": 0.057,
		"bark": Color(0.42, 0.3, 0.18), "leaf": Color(0.4, 0.5, 0.22),
		"brief": "an acacia: a long bare bole and a wide flat plate of canopy"
			+ " balanced on top, thin at the rim and thickening to the trunk;"
			+ " the silhouette everyone knows from a dusk photograph",
	},
	"wetland": {
		"crown": "cone", "trunk": 0.50, "bole": 0.05,
		"bark": Color(0.35, 0.28, 0.2), "leaf": Color(0.25, 0.4, 0.24),
		"brief": "a swamp tree: shorter, wetter, blue-green, with the crown"
			+ " starting low on the bole and the lowest boughs drooping — it"
			+ " should look heavy with water",
	},
}

static var _plates := {}
static var _boards := {}


## The leaf colour of a style, for the tree and for its plate alike.
static func leaf_of(style: String) -> Color:
	return PLATES.get(style, PLATES["forest"])["leaf"]


## The bark colour, same arrangement.
static func bark_of(style: String) -> Color:
	return PLATES.get(style, PLATES["forest"])["bark"]


## THE BOARD: one metre square, pivoted at its foot, turning about its own
## vertical so a tree never lies down when you look at the country from above.
##
## Sized per instance through the transform, because every tree is a different
## height and they all share this one mesh. `billboard_keep_scale` is what makes
## that survive the billboarding — without it every tree in the world comes out
## the same size, which is a very confusing picture.
##
## ALPHA SCISSOR, NOT ALPHA BLEND. A cut-out writes depth and needs no sorting,
## so a thousand of these can be drawn in any order and still occlude one
## another properly. Blending them would mean sorting a thousand quads every
## frame and getting the halos wrong anyway.
static func board(style: String) -> QuadMesh:
	var m: QuadMesh = _boards.get(style)
	if m != null:
		return m
	m = QuadMesh.new()
	m.size = Vector2.ONE
	m.center_offset = Vector3(0, 0.5, 0)     # stand it on the ground, not through it
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = plate(style)
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	skin.alpha_scissor_threshold = 0.5
	skin.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	skin.billboard_keep_scale = true
	skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	skin.vertex_color_use_as_albedo = true   # per-instance tint, per-instance dimming
	skin.roughness = 1.0
	# Lit, not unshaded: an unshaded wood keeps its noon colour through the
	# night and reads as a row of lamps on a dark hillside.
	skin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.material = skin
	_boards[style] = m
	return m


## The drawing itself, painted once per style.
static func plate(style: String) -> ImageTexture:
	var tex: ImageTexture = _plates.get(style)
	if tex != null:
		return tex
	tex = ImageTexture.create_from_image(_paint(style))
	_plates[style] = tex
	return tex


static func _paint(style: String) -> Image:
	var spec: Dictionary = PLATES.get(style, PLATES["forest"])
	var img := Image.create_empty(SIZE, SIZE, true, Image.FORMAT_RGBA8)
	var bark: Color = spec["bark"]
	var leaf: Color = spec["leaf"]
	var trunk_top: float = spec["trunk"]
	var bole: float = spec["bole"]
	var cone: bool = spec["crown"] == "cone"
	# The crown starts a little below the break, so the bole is not a bare pole
	# with a hat on it.
	var crown_foot := trunk_top - (0.06 if cone else 0.01)
	for y in SIZE:
		for x in SIZE:
			var u := (x + 0.5) / SIZE - 0.5            # -0.5 .. 0.5 across
			var v := 1.0 - (y + 0.5) / SIZE            # 0 at the foot, 1 at the top
			var hit := Color(0, 0, 0, 0)
			if v <= trunk_top and absf(u) <= bole:
				hit = bark.darkened(0.15 * (1.0 - v))
			if v >= crown_foot:
				var up := (v - crown_foot) / maxf(1.0 - crown_foot, 0.001)
				# The two sides are nibbled independently and PER ROW, not per
				# pixel: a per-pixel wobble puts loose specks in the air beside
				# the tree, because pixels inside the fringe pass or fail on
				# their own. Per row it is one wobbly outline, which is what
				# foliage against the sky actually looks like.
				var wide := _crown_half(cone, up)
				var half := wide * _ragged(y, 1 if u < 0.0 else 0)
				if absf(u) <= half:
					# Darker low and on the left, so the mass reads as a mass
					# and not as a flat sticker.
					var shade := 0.30 * (1.0 - up) + 0.12 * (0.5 - u)
					hit = leaf.darkened(clampf(shade, 0.0, 0.45))
			img.set_pixel(x, y, hit)
	img.generate_mipmaps()
	return img


## How wide the crown is at `up` (0 at its foot, 1 at the top), as a fraction
## of the plate. Both shapes reach half the plate's width at their widest, which
## is what makes the plate's own width the tree's width.
static func _crown_half(cone: bool, up: float) -> float:
	if cone:
		# A spire: widest a little above its foot, then tapering to the point.
		return 0.5 * (1.0 - up) * (0.55 + 0.45 * minf(up * 6.0, 1.0))
	# An acacia's plate: thick at the middle, thinning to the rim.
	return 0.5 * sqrt(maxf(1.0 - (up * 2.0 - 1.0) * (up * 2.0 - 1.0), 0.0))


## A RAGGED EDGE. A cone cut exactly is a triangle and reads as one; foliage
## has to be broken up at its outline or it looks like a road sign. A cheap
## hash of the row and which side of the trunk it is, scaled tight so it only
## ever nibbles the rim.
static func _ragged(y: int, side: int) -> float:
	var n := float(((y * 73856093) ^ ((side + 1) * 19349663)) & 255) / 255.0
	return 0.84 + 0.26 * n
