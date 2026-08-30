class_name CastOverlay
extends Control
## What CASTING looks like. Two small drawings, and the whole readability of
## the system rests on them:
##
##  * A RING that fills under your finger as you press to open the session, so
##    the summons is something you can see coming and abandon by moving.
##  * A BAR that drains once you stop drawing, so you can see the moment your
##    working will go off — and that drawing again resets it.
##
## Without these the session is an invisible mode, which is worse than the
## button it replaced.

const RING_RADIUS := 42.0
const BAR_WIDTH := 260.0
const BAR_HEIGHT := 7.0

var divine_hand: DivineHand


func _process(_delta: float) -> void:
	if divine_hand != null and is_instance_valid(divine_hand):
		queue_redraw()


func _draw() -> void:
	if divine_hand == null or not is_instance_valid(divine_hand):
		return
	var charge := divine_hand.charge_fraction()
	if charge > 0.0:
		_draw_charge_ring(get_viewport().get_mouse_position(), charge)
	if divine_hand.casting:
		_draw_session()


## The summons, filling. A full ring means the session is about to open.
func _draw_charge_ring(at: Vector2, fraction: float) -> void:
	var faint := Color(1.0, 0.95, 0.7, 0.25)
	draw_arc(at, RING_RADIUS, 0.0, TAU, 48, faint, 3.0, true)
	draw_arc(at, RING_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * fraction, 48,
		Color(1.0, 0.92, 0.5, 0.95), 5.0, true)


## The session's own frame: a border so it is unmistakable that the world is
## held, and a bar counting down to the cast.
func _draw_session() -> void:
	var rect := get_viewport_rect()
	var glow := GameState.alignment_color()
	glow.a = 0.5
	draw_rect(rect, glow, false, 3.0)

	var left := divine_hand.casting_fraction()
	var origin := Vector2(rect.size.x * 0.5 - BAR_WIDTH * 0.5, rect.size.y - 54.0)
	draw_rect(Rect2(origin, Vector2(BAR_WIDTH, BAR_HEIGHT)), Color(0, 0, 0, 0.45))
	# It runs down only while you are NOT drawing; mid-stroke it sits full, so
	# taking your time over a rune can never cost you the working.
	var tint := Color(1.0, 0.9, 0.5) if left > 0.35 else Color(1.0, 0.55, 0.4)
	draw_rect(Rect2(origin, Vector2(BAR_WIDTH * left, BAR_HEIGHT)), tint)
