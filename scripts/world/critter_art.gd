class_name CritterArt
extends RefCounted
## STAND-IN PLATES FOR THE TREE FRIENDS.
##
## The ambient wildlife is meant to be HAND-DRAWN: flat picture-book plates that
## always face you, two or three frames each, painted by a person. None of that
## exists yet, so this paints stand-ins — the same silhouettes, the same frame
## counts, the same sizes and pivots — into small images at boot.
##
## The point of doing it this way rather than with placeholder cubes is that
## everything downstream is then REAL. The billboard, the flipbook timing, the
## alpha edges, the way a squirrel reads at eleven metres, the memory cost: all
## of it is exercised now, and swapping in the finished plates later is a change
## to `_paint` and nothing else. See `PLATES` for what each one has to be.
##
## Cost: fifteen plates of 32x32 RGBA is 60 KB, painted once and shared by every
## critter of that kind — a hundred bees are one texture. There is not a texture
## file in this project and this does not add one.

const SIZE := 32

## WHAT AN ARTIST WOULD BE HANDED. Each kind names its frames, how fast they
## run, how big it stands in metres, and the note that says what the drawing is
## actually of — because "squirrel" is not a brief and "a squirrel side-on,
## sitting up, tail curled over its back" is.
const PLATES := {
	"squirrel": {
		"frames": 3, "fps": 4.0, "size": 0.42, "ink": Color(0.55, 0.34, 0.20),
		"brief": "side-on, sitting up on a limb, tail a full plume curling from"
			+ " below the haunches out and over the head; frames: still,"
			+ " nibbling (head down, paws to mouth), tail-flick",
	},
	"possum": {
		"frames": 2, "fps": 2.5, "size": 0.46, "ink": Color(0.72, 0.70, 0.66),
		"brief": "side-on, low and long, bare tail trailing, snout down;"
			+ " frames: creeping, head-up-listening",
	},
	"bee": {
		"frames": 2, "fps": 18.0, "size": 0.11, "ink": Color(0.92, 0.78, 0.18),
		"brief": "fat striped body, wings a blur; frames: wings up, wings down",
	},
	"moth": {
		"frames": 2, "fps": 9.0, "size": 0.14, "ink": Color(0.86, 0.83, 0.72),
		"brief": "pale triangular wings seen from above; frames: open, closed",
	},
	"fly": {
		"frames": 2, "fps": 22.0, "size": 0.07, "ink": Color(0.18, 0.18, 0.22),
		"brief": "a dark speck with a glint; frames: two wing phases",
	},
	"cricket": {
		"frames": 2, "fps": 6.0, "size": 0.09, "ink": Color(0.28, 0.34, 0.22),
		"brief": "side-on, long back legs cocked; frames: at rest, mid-stridulation",
	},
	"frog": {
		"frames": 2, "fps": 1.6, "size": 0.16, "ink": Color(0.36, 0.52, 0.28),
		"brief": "squat, side-on at the waterline, throat sac;"
			+ " frames: throat slack, throat swollen",
	},
}

static var _plates := {}


## Every frame of one kind, painted once and shared. The array is the flipbook.
static func frames_for(kind: String) -> Array[ImageTexture]:
	if _plates.has(kind):
		return _plates[kind]
	var spec: Dictionary = PLATES.get(kind, PLATES["fly"])
	var out: Array[ImageTexture] = []
	for f in int(spec["frames"]):
		out.append(_paint(kind, f, spec["ink"]))
	_plates[kind] = out
	return out


## THE PART THAT GETS REPLACED. Everything here is a rough shape in flat ink
## with a darker outline — enough to read the animal at a glance and no more.
static func _paint(kind: String, frame: int, ink: Color) -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	match kind:
		"squirrel":
			# SITTING UP, side-on, and the TAIL is the whole silhouette — a plume
			# bulging out to the right and curling over the head. Swept round the
			# outside (from below, through the right, to above) rather than
			# straight across, which merged it into the body and read as a rabbit.
			_blob(img, 0.42, 0.62, 0.15, 0.20, ink)                  # body, upright
			var stoop := 0.0 if frame != 1 else 0.05                 # head dips to nibble
			_blob(img, 0.40, 0.36 + stoop, 0.11, 0.12, ink)          # head
			_blob(img, 0.35, 0.33 + stoop, 0.032, 0.032, Color(0.05, 0.04, 0.03))
			_blob(img, 0.45, 0.26 + stoop, 0.05, 0.07, ink.lightened(0.1))   # ear
			var flick := 0.0 if frame != 2 else -0.22
			_arc(img, 0.64, 0.56, 0.22, PI * 0.5, -PI * 0.5 + flick, 0.085, ink)
			if frame == 1:
				_blob(img, 0.33, 0.47, 0.045, 0.05, ink.darkened(0.2))  # paws, up
		"possum":
			_blob(img, 0.50, 0.58, 0.26, 0.15, ink)
			_blob(img, 0.26, 0.55, 0.11, 0.10, ink.lightened(0.1))
			_arc(img, 0.72, 0.58, 0.20, PI * 1.7, PI * 2.3, 0.045,
				Color(0.62, 0.55, 0.52))
			_blob(img, 0.21, 0.52, 0.03, 0.03, Color(0.05, 0.04, 0.03))
			if frame == 1:
				_blob(img, 0.26, 0.46, 0.10, 0.06, ink.lightened(0.1))  # head up
		"bee":
			_blob(img, 0.50, 0.54, 0.17, 0.13, ink)
			_bar(img, 0.46, 0.54, 0.05, 0.12, Color(0.12, 0.10, 0.06))
			_bar(img, 0.56, 0.54, 0.05, 0.12, Color(0.12, 0.10, 0.06))
			var lift := -0.10 if frame == 0 else 0.06
			_blob(img, 0.44, 0.42 + lift, 0.14, 0.06, Color(1, 1, 1, 0.45))
			_blob(img, 0.60, 0.42 + lift, 0.14, 0.06, Color(1, 1, 1, 0.45))
		"moth":
			var spread := 0.20 if frame == 0 else 0.09
			_blob(img, 0.50 - spread, 0.48, 0.20, 0.16, ink)
			_blob(img, 0.50 + spread, 0.48, 0.20, 0.16, ink)
			_bar(img, 0.50, 0.52, 0.05, 0.24, ink.darkened(0.35))
		"fly":
			_blob(img, 0.50, 0.52, 0.15, 0.12, ink)
			var f := 0.13 if frame == 0 else 0.07
			_blob(img, 0.36, 0.44, f, 0.05, Color(1, 1, 1, 0.35))
			_blob(img, 0.64, 0.44, f, 0.05, Color(1, 1, 1, 0.35))
		"cricket":
			_blob(img, 0.52, 0.58, 0.22, 0.11, ink)
			_blob(img, 0.30, 0.55, 0.09, 0.08, ink.lightened(0.12))
			# The back legs, cocked — and rubbing, on the second frame.
			var kick := 0.0 if frame == 0 else 0.06
			_arc(img, 0.66, 0.56, 0.16, PI * 1.05, PI * 1.75 + kick, 0.035, ink)
			_bar(img, 0.74, 0.66, 0.16, 0.03, ink)
		"frog":
			_blob(img, 0.50, 0.60, 0.28, 0.19, ink)
			_blob(img, 0.34, 0.50, 0.11, 0.10, ink.lightened(0.08))
			_blob(img, 0.31, 0.46, 0.035, 0.035, Color(0.95, 0.88, 0.3))  # eye
			_blob(img, 0.31, 0.46, 0.018, 0.02, Color(0.05, 0.05, 0.05))
			# The throat sac, which is the whole reason to have two frames.
			var sac := 0.05 if frame == 0 else 0.13
			_blob(img, 0.38, 0.66, sac, sac * 0.8, ink.lightened(0.22))
		_:
			_blob(img, 0.5, 0.5, 0.3, 0.3, ink)
	_outline(img)
	return ImageTexture.create_from_image(img)


## A filled ellipse in normalised coordinates, soft at the very edge so the
## alpha does not stair-step at the small sizes these are drawn at.
static func _blob(img: Image, cx: float, cy: float, rx: float, ry: float,
		ink: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			var u := (x + 0.5) / SIZE - cx
			var v := (y + 0.5) / SIZE - cy
			var d := sqrt(u * u / maxf(rx * rx, 1e-6) + v * v / maxf(ry * ry, 1e-6))
			if d > 1.08:
				continue
			var a := clampf((1.08 - d) / 0.16, 0.0, 1.0) * ink.a
			_over(img, x, y, Color(ink.r, ink.g, ink.b, a))


static func _bar(img: Image, cx: float, cy: float, w: float, h: float,
		ink: Color) -> void:
	_blob(img, cx, cy, w * 0.5, h * 0.5, ink)


## A stroke swept along an arc — tails, legs, anything that curves.
static func _arc(img: Image, cx: float, cy: float, radius: float,
		from_a: float, to_a: float, weight: float, ink: Color) -> void:
	var steps := 24
	for i in steps + 1:
		var a := lerpf(from_a, to_a, i / float(steps))
		# Tapering, so a tail is thick where it leaves the body and fine at the tip.
		var taper := lerpf(1.0, 0.45, i / float(steps))
		_blob(img, cx + cos(a) * radius, cy + sin(a) * radius,
			weight * taper, weight * taper, ink)


static func _over(img: Image, x: int, y: int, top: Color) -> void:
	var under := img.get_pixel(x, y)
	var a := top.a + under.a * (1.0 - top.a)
	if a <= 0.0:
		return
	img.set_pixel(x, y, Color(
		(top.r * top.a + under.r * under.a * (1.0 - top.a)) / a,
		(top.g * top.a + under.g * under.a * (1.0 - top.a)) / a,
		(top.b * top.a + under.b * under.a * (1.0 - top.a)) / a, a))


## A dark line around the whole silhouette. This is the single thing that makes
## flat colour read as DRAWN rather than as a decal, and it is why these can sit
## against grass, bark or sky without disappearing into any of them.
static func _outline(img: Image) -> void:
	var edge := img.duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			if img.get_pixel(x, y).a > 0.35:
				continue
			var near := false
			# Typed, or `x + dx` infers a Variant off the untyped literal and
			# the build stops. See tools/check_calls.py.
			for dy: int in [-1, 0, 1]:
				for dx: int in [-1, 0, 1]:
					var px := x + dx
					var py := y + dy
					if px < 0 or py < 0 or px >= SIZE or py >= SIZE:
						continue
					if img.get_pixel(px, py).a > 0.55:
						near = true
			if near:
				edge.set_pixel(x, y, Color(0.10, 0.08, 0.07, 0.85))
	img.copy_from(edge)
