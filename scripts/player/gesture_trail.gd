class_name GestureTrail
extends CanvasLayer
## Draws the glowing mouse trail while a miracle gesture is being cast.

var points := PackedVector2Array()
var _canvas: Control


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
		if trail.points.size() < 2:
			return
		draw_polyline(trail.points, Color(1.0, 0.95, 0.6, 0.35), 10.0, true)
		draw_polyline(trail.points, Color(1.0, 1.0, 0.9, 0.9), 3.0, true)
