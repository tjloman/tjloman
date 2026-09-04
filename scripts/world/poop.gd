class_name Poop
extends Node3D
## WHAT THE CREATURE LEAVES BEHIND, and what it does to the ground.
##
## Muck is fertiliser. Dropped on a field or among trees it feeds them exactly
## as rain does — a real, useful thing a beast can do for a village without
## being told — and dropped on somebody's house it is a nuisance, which is the
## other half of the same act. The creature is not told which is which: the
## places are offered as different deeds (see Creature._offer_relief) and it
## learns which it prefers, so a gentle beast manures the fields and a
## mischievous one waits for the roof.
##
## It FADES. The ground keeps the good of it, but the thing itself sinks in over
## a few minutes, because a world where every creature's whole digestive history
## is still lying about is neither pleasant nor cheap.

## How long it lasts, and how far its goodness reaches.
const LIFE_SECONDS := 240.0
const REACH := 7.0
## HOW LONG THE GROUND STAYS BLESSED, in seconds, for a full load. Trees and
## fields already know how to be rained on and grow the faster for a while;
## muck is simply another way of being watered, so it goes through exactly the
## same door rather than inventing a parallel notion of fertility.
const NOURISH_SECONDS := 150.0

var amount := 1.0      # 0..1, how much came out
var _age := 0.0
var _pile: Node3D = null


func _ready() -> void:
	add_to_group("poop")
	var size := lerpf(0.22, 0.5, clampf(amount, 0.0, 1.0))
	_pile = Util.lite_sphere(size, Color(0.34, 0.24, 0.15), Vector3.ZERO, 6)
	_pile.scale.y = 0.55
	add_child(_pile)
	# Flies find it within a few seconds, which is the joke and also the one
	# ambient critter that already knows what to do with carrion-ish things.
	SoundBank.play_at("oink", global_position, -22.0, 0.3)
	_feed_the_ground()


## THE GOOD OF IT, given once at the moment it lands rather than ticked. Trees
## and fields both take it; anything else in reach simply ignores it.
func _feed_the_ground() -> void:
	var fed := 0
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(global_position) < REACH:
			tree.rain(NOURISH_SECONDS * amount)
			fed += 1
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(global_position) < REACH:
			farm.water(NOURISH_SECONDS * amount)
			fed += 1
	if fed > 0:
		GameState.announce(GameState.named(
			"Your creature has manured the ground. It will grow the better for it."))


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE_SECONDS:
		queue_free()
		return
	# Sinks into the ground over its last quarter rather than blinking out.
	var left := 1.0 - clampf((_age - LIFE_SECONDS * 0.75) / (LIFE_SECONDS * 0.25), 0.0, 1.0)
	if is_instance_valid(_pile):
		_pile.scale.y = 0.55 * left
		_pile.position.y = -0.1 * (1.0 - left)


func hover_text() -> String:
	return "Muck (it feeds the ground)"
