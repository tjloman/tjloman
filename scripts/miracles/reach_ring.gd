class_name ReachRing
extends Node3D
## THE CIRCLE THE CREATURE CARRIES, drawn on the grass.
##
## A faithful village already wears its ring (Village._build_influence_ring)
## and that ring is on the ground whether you are casting or not, because it
## is also the village's readout — its size is the population and its colour
## is belief. The creature's circle is a different thing: it MOVES, it is the
## only reach you have out in the wild, and a permanent ring following a
## fifteen-metre animal around would be scenery within a minute.
##
## So it appears when it matters and not before: the ground the beast holds
## lights up the moment you start drawing a rune, and again while a working is
## in your hand, and fades out when you are done. The reach limits where you
## may CAST FROM rather than where a throw may land, so the moment that matters
## is the moment the stroke begins — the game shows you the edge while you are
## standing on the right side of it.
##
## It also flares when a cast is refused for want of ground, so the answer
## arrives even if you were not looking at your feet.

## How quickly it comes up and goes away, in ring-alpha per second. Up fast
## because you may already be winding up; down slow because it is pleasant.
const OPENS := 4.0
const CLOSES := 1.2
## How long a fizzle keeps it up on its own, in seconds.
const AFTER_A_FIZZLE := 2.5
## How far off the ground, so it never z-fights the grass on a slope.
const OFF_THE_GRASS := 0.35

var divine_hand: DivineHand = null

var _ring: MeshInstance3D
var _skin: StandardMaterial3D
var _shown := 0.0
var _flare := 0.0


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.965
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	_skin = Util.mat(Color(1.0, 0.95, 0.7, 0.0), true)
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _skin
	_ring.visible = false
	add_child(_ring)


## A fade on a piece of interface, run off the frame's own `delta` — which
## stops with the tree, so the ring holds its state through a paused temple
## rather than blinking out while you read a chart.
func _process(delta: float) -> void:
	var beast := get_tree().get_first_node_in_group("creature") as Creature
	if beast == null or not is_instance_valid(beast):
		_ring.visible = false
		return
	_flare = maxf(_flare - delta, 0.0)
	var want := 1.0 if (_holding_power() or _flare > 0.0) else 0.0
	_shown = move_toward(_shown, want, (OPENS if want > _shown else CLOSES) * delta)
	if _shown <= 0.001:
		_ring.visible = false
		return
	var span := MiracleReach.beast_reach(beast)
	global_position = Vector3(
		beast.global_position.x, beast.global_position.y + OFF_THE_GRASS,
		beast.global_position.z)
	_ring.scale = Vector3(span, 1.0, span)
	_ring.visible = true
	# It wears the god's alignment, exactly as a village ring does — one
	# vocabulary for "this ground is yours" across the whole game.
	var c := GameState.alignment_color().lerp(Color.WHITE, 0.15)
	_skin.albedo_color = Color(c.r, c.g, c.b, 0.5 * _shown)
	_skin.emission = c
	_skin.emission_energy_multiplier = 1.6 * _shown


## ONE MORE SECOND OF ANSWER. Called when a working guttered out for want of
## ground, so the player sees the edge they just missed.
func flare() -> void:
	_flare = AFTER_A_FIZZLE


func _holding_power() -> bool:
	if divine_hand == null or not is_instance_valid(divine_hand):
		return false
	# WHILE YOU ARE DRAWING, above all. The reach is a limit on where you may
	# CAST FROM, so the moment a casting session opens is the moment the answer
	# to "may I work here" matters — before a rune is drawn, not after one is
	# thrown. See MiracleReach.
	if divine_hand.casting:
		return true
	var held := divine_hand.held_body
	if held == null or not is_instance_valid(held):
		return false
	return held is MiracleOrb or held is Fireball
