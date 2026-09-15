class_name GestureTrail
extends CanvasLayer
## Draws the glowing mouse trail while a miracle gesture is being cast.

## THE LOOK OF A DRAWN STROKE, in one place. Two passes: a wide soft glow and a
## bright hairline down the middle of it, which is what makes a finger-drag read
## as light rather than as a pen.
##
## Static, and not merely a method on the canvas below, because the start
## screen's logo game draws strokes too (see LogoGame) — and that is supposed to
## be recognisably THE SAME ACT as casting a miracle. Two copies of these four
## numbers would have drifted the first time either was tuned, and the whole
## point of the minigame is that it teaches the gesture you will use all game.
const GLOW_WIDE := 10.0
const GLOW_FINE := 3.0
const GLOW_COLOR := Color(1.0, 0.95, 0.6, 0.35)
const FINE_COLOR := Color(1.0, 1.0, 0.9, 0.9)

var points := PackedVector2Array()
var _canvas: Control


## Lay a stroke down on any canvas, in that canvas's own coordinates.
static func paint(on: CanvasItem, path: PackedVector2Array) -> void:
	if path.size() < 2:
		return
	on.draw_polyline(path, GLOW_COLOR, GLOW_WIDE, true)
	on.draw_polyline(path, FINE_COLOR, GLOW_FINE, true)


func _ready() -> void:
	layer = 10
	_canvas = TrailCanvas.new()
	_canvas.trail = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)


func queue_redraw() -> void:
	_canvas.queue_redraw()


class TrailCanvas:
	extends Control

	var trail: GestureTrail

	func _draw() -> void:
		GestureTrail.paint(self, trail.points)
