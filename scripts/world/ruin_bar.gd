class_name RuinBar
extends Node3D
## WHAT IS LEFT OF A BUILDING, over the building.
##
## A village's buildings could be hurt for a long time before anybody could SEE
## that they were being hurt. A mill took forty blows and looked exactly the
## same for the first thirty-nine, which is indistinguishable from a mill that
## cannot be hurt at all — and "I cannot burn down the mill" is what that
## indistinguishability sounds like from the other side of the screen.
##
## So: a bar, and it earns its place by being ABSENT almost always. It appears
## the moment a thing is first hurt or first alight and never before, which
## means a peaceful town has none of these floating over it and a town under
## fire is legible at a glance from across the valley.
##
## ONE CLASS FOR EVERY STRUCTURE. The alternative was the same forty lines in
## the house, the workshop, the granary, the school, the field and the nest,
## which is how six of them end up subtly different.

## How wide the bar is in metres, how thick, and how far above whatever it is
## measuring it floats. Sized to be read from the air rather than from a
## doorway: this is a god's information.
const WIDE := 3.6
const THICK := 0.42
const FLOAT_BY := 1.4

## Past this it is not drawn at all. A town on the horizon does not need its
## bookkeeping rendered, and these are one draw call each.
const SEEN_WITHIN := 90.0

## Full, hurt, nearly gone. Stepped rather than lerped because a bar that eases
## from green to red through brown says "somewhere in the middle" at every
## moment and a stepped one says which of the three states this is.
const HALE := Color(0.45, 0.80, 0.40)
const HURT := Color(0.95, 0.80, 0.30)
const DOOMED := Color(0.90, 0.28, 0.22)
const BACKING := Color(0.06, 0.05, 0.08, 0.72)
## Below this share it reads as doomed; below the first it reads as hurt.
const HURT_UNDER := 0.66
const DOOMED_UNDER := 0.3

static var _pixel: ImageTexture = null

var _fill: Sprite3D = null
var _back: Sprite3D = null


## PUT ONE OVER THIS THING, or update the one already there. The only door in,
## and deliberately a static: a building should be able to say "I have been
## hurt" in one line without knowing whether it already has a bar.
##
## `share` is 0..1 of full health. At 1.0 with nothing alight the bar is taken
## away again, which is what keeps a healthy town clean.
static func over(who_given: Variant, share: float, high: float, alight := false) -> void:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(who_given):
		return
	var who := who_given as Node3D
	if not is_instance_valid(who):
		return
	var bar := who.get_node_or_null("ruin_bar") as RuinBar
	if share >= 1.0 and not alight:
		if bar != null:
			bar.queue_free()
		return
	if bar == null:
		bar = RuinBar.new()
		bar.name = "ruin_bar"
		who.add_child(bar)
		bar.position = Vector3(0.0, high + FLOAT_BY, 0.0)
	bar.set_share(clampf(share, 0.0, 1.0))


func _ready() -> void:
	_back = _plate(BACKING, 1.0, 0.0)
	_fill = _plate(HALE, 1.0, 0.01)


## One billboarded plate. A Sprite3D on a single white pixel, scaled — which is
## the cheapest possible coloured rectangle that always faces the camera, and
## needs no mesh, no material per bar and no shader.
func _plate(tint: Color, share: float, nudge: float) -> Sprite3D:
	var plate := Sprite3D.new()
	plate.texture = _white()
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.shaded = false
	plate.no_depth_test = false
	plate.modulate = tint
	plate.pixel_size = 1.0
	plate.scale = Vector3(WIDE * share, THICK, 1.0)
	plate.position = Vector3(0.0, 0.0, nudge)
	plate.visibility_range_end = SEEN_WITHIN
	add_child(plate)
	return plate


## HOW MUCH IS LEFT. The fill shrinks from the LEFT edge rather than from the
## middle — a bar that empties symmetrically reads as a thing getting smaller
## instead of a thing running out.
func set_share(share: float) -> void:
	if _fill == null or not is_instance_valid(_fill):
		return
	_fill.scale.x = WIDE * share
	_fill.position.x = -WIDE * 0.5 * (1.0 - share)
	if share < DOOMED_UNDER:
		_fill.modulate = DOOMED
	elif share < HURT_UNDER:
		_fill.modulate = HURT
	else:
		_fill.modulate = HALE


## ONE WHITE PIXEL, made once and shared by every bar in the world. A texture
## per bar would be a texture per burning building.
static func _white() -> ImageTexture:
	if _pixel != null:
		return _pixel
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	_pixel = ImageTexture.create_from_image(img)
	return _pixel
