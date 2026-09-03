class_name TreeFriends
extends Node3D
## THE LUSHNESS. Everything small and alive that the world does not need.
##
## Bees over the flowers in daylight and moths over them at night; crickets in
## the grass after dark; peepers at the water's edge; flies over meat and over
## whatever has died; squirrels working the limbs of a wood in the sun and
## possums in the same trees once it is dark. None of it is load-bearing — see
## Critter — and all of it can be switched off in one place.
##
## WHAT MAKES IT WORTH HAVING is that it is CONDITIONAL. A cricket at noon or a
## bee at midnight would make the whole thing read as wallpaper. Every kind here
## has a host it needs and an hour it keeps, so noticing a moth means the sun
## has gone down, and hearing peepers means there is standing water nearby that
## you may not have known about.
##
## IT IS ALSO A GIFT. This is the supporters' build: `GameState.tree_friends`
## gates it, and that setting cannot be turned on without the entitlement. The
## game underneath is identical, which is the only honest way to sell an
## ornament — nothing here is an advantage.

## How near the camera a critter has to be to exist at all. Well inside the
## clutter distance: these are small, and one at forty metres is a wasted quad.
const NEAR := 34.0
const GONE := 44.0
## How many get a voice. Audio players are the expensive part, not the plates,
## and six overlapping loops is already a dense-sounding wood.
const VOICES := 6
## Seconds between census passes. Nothing here is urgent.
const CENSUS := 0.9

## WHAT LIVES WHERE, AND WHEN. `hours` is the fraction of the day it keeps
## (GameState.day_fraction, 0 = midnight); `voice` names its loop in SoundBank;
## `shy` is the distance at which people frighten it off.
const KINDS := {
	"bee": {
		"host": "bloom", "day": true, "voice": "bees",
		"roam": 0.7, "lift": 0.35, "shy": 0.0, "per_host": 2,
	},
	"moth": {
		"host": "bloom", "day": false, "voice": "",
		"roam": 0.9, "lift": 0.5, "shy": 0.0, "per_host": 1,
	},
	"cricket": {
		"host": "grass", "day": false, "voice": "crickets",
		"roam": 0.0, "lift": 0.02, "shy": 0.0, "per_host": 1,
	},
	"frog": {
		"host": "water", "day": false, "voice": "peepers",
		"roam": 0.5, "lift": 0.06, "shy": 3.5, "per_host": 2,
	},
	"fly": {
		"host": "carrion", "day": true, "voice": "flies",
		"roam": 0.35, "lift": 0.25, "shy": 0.0, "per_host": 3,
	},
	"squirrel": {
		"host": "tree", "day": true, "voice": "chitter",
		"roam": 0.8, "lift": 2.4, "shy": 6.0, "per_host": 1,
	},
	"possum": {
		"host": "tree", "day": false, "voice": "rustle",
		"roam": 0.6, "lift": 2.0, "shy": 7.0, "per_host": 1,
	},
}

var world: WorldGen

var _critters: Array[Critter] = []
var _since_census := 0.0
var _voiced: Array[Critter] = []


func _ready() -> void:
	add_to_group("tree_friends")


func _process(delta: float) -> void:
	_since_census += delta
	if _since_census < CENSUS:
		return
	_since_census = 0.0
	if not GameState.tree_friends:
		if not _critters.is_empty():
			clear()
		return
	_cull()
	_recruit()
	_hand_out_voices()


## Everything gone — when the setting is switched off, or the world reloads.
func clear() -> void:
	for c in _critters:
		if is_instance_valid(c):
			c.queue_free()
	_critters.clear()
	_voiced.clear()


func population() -> int:
	return _critters.size()


## Anything too far to see, anything whose host has been eaten, cut down or
## burned, and anything whose hour has passed.
func _cull() -> void:
	var eye := _eye()
	var kept: Array[Critter] = []
	for c in _critters:
		if not is_instance_valid(c):
			continue
		var lost := c.host != null and not is_instance_valid(c.host)
		if lost or c.global_position.distance_to(eye) > GONE or not _in_season(c.kind):
			c.queue_free()
			continue
		kept.append(c)
	_critters = kept


## Fill up to the budget, one kind at a time, cycling so no single kind can
## starve the others out on a map that happens to be all trees.
func _recruit() -> void:
	var budget := Quality.critters()
	if _critters.size() >= budget:
		return
	var eye := _eye()
	var names := KINDS.keys()
	names.shuffle()
	for kind: String in names:
		if _critters.size() >= budget:
			return
		if not _in_season(kind):
			continue
		var spec: Dictionary = KINDS[kind]
		var host := _find_host(String(spec["host"]), eye)
		if host.is_empty():
			continue
		for i in int(spec["per_host"]):
			if _critters.size() >= budget:
				return
			_settle(kind, spec, host)


## Is it this one's hour? Everything here is either a day creature or a night
## one, which is the whole reason the set reads as alive rather than as decor.
func _in_season(kind: String) -> bool:
	var spec: Dictionary = KINDS.get(kind, {})
	if spec.is_empty():
		return false
	return bool(spec["day"]) != GameState.is_night()


## WHERE ONE COULD LIVE — a tree, a patch of blooms, a waterside, a piece of
## meat, or open grass. Returns {"node": Node3D or null, "at": Vector3} and an
## empty Dictionary when there is nowhere suitable in reach.
func _find_host(sort: String, eye: Vector3) -> Dictionary:
	match sort:
		"tree":
			return _nearby_node("trees", eye)
		"carrion":
			var meat := _nearby_node("corpses", eye)
			return meat if not meat.is_empty() else _nearby_node("food", eye)
		"bloom":
			return _bloom_spot(eye)
		"water":
			return _water_spot(eye)
		_:
			return _grass_spot(eye)


## A random member of a group within reach — random rather than nearest, so a
## wood does not end up with every squirrel in the same three trees.
func _nearby_node(group: String, eye: Vector3) -> Dictionary:
	var found: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(group):
		var node := n as Node3D
		if is_instance_valid(node) and node.global_position.distance_to(eye) < NEAR:
			found.append(node)
	if found.is_empty():
		return {}
	var pick: Node3D = found[randi() % found.size()]
	return {"node": pick, "at": pick.global_position}


## THE FLOWERS THEMSELVES. Chunks record where they scattered their blooms (see
## Chunk._scatter_flowers) precisely so the bees can be over actual flowers
## rather than over grass that happens to be the right biome.
func _bloom_spot(eye: Vector3) -> Dictionary:
	if world == null:
		return {}
	var spots := world.blooms_near(eye, NEAR)
	if spots.is_empty():
		return {}
	return {"node": null, "at": spots[randi() % spots.size()]}


## The edge of standing water, found by walking out from a random bearing until
## the ground stops being wet. The SHORE is what frogs want — sitting in the
## middle of a pond would read as drowning.
func _water_spot(eye: Vector3) -> Dictionary:
	if world == null:
		return {}
	for tries in 6:
		var a := randf() * TAU
		var d := randf_range(6.0, NEAR)
		var at := Vector2(eye.x + cos(a) * d, eye.z + sin(a) * d)
		if not world.is_underwater(at.x, at.y):
			continue
		# Walk back toward dry land a metre at a time and stop at the line.
		for step in 8:
			var back := at - Vector2(cos(a), sin(a)) * 1.2
			if not world.is_underwater(back.x, back.y):
				var y := world.surface_at(back.x, back.y)
				return {"node": null, "at": Vector3(back.x, y, back.y)}
			at = back
	return {}


func _grass_spot(eye: Vector3) -> Dictionary:
	if world == null:
		return {}
	for tries in 5:
		var a := randf() * TAU
		var d := randf_range(5.0, NEAR)
		var x := eye.x + cos(a) * d
		var z := eye.z + sin(a) * d
		if world.is_underwater(x, z):
			continue
		if world.biome_at(x, z) == "rocky_hills":
			continue           # crickets do not live in scree
		return {"node": null, "at": Vector3(x, world.height_at(x, z), z)}
	return {}


func _settle(kind: String, spec: Dictionary, host: Dictionary) -> void:
	var c := Critter.new()
	c.kind = kind
	c.host = host.get("node")
	c.roam = float(spec["roam"])
	c.shy = float(spec["shy"])
	var at: Vector3 = host["at"]
	# `lift` is how far up its host it sits: a squirrel is in the limbs, a
	# cricket is in the grass, flies are just above the meat.
	c.anchor = at + Vector3(
		randf_range(-1.0, 1.0), float(spec["lift"]), randf_range(-1.0, 1.0))
	add_child(c)
	c.position = c.anchor
	_critters.append(c)


## VOICES GO TO THE NEAREST FEW, and are taken back when something closer turns
## up. A wood can hold thirty critters and still only ever be running six audio
## players, which is what keeps this affordable on a phone.
func _hand_out_voices() -> void:
	var eye := _eye()
	var ranked: Array[Critter] = []
	for c in _critters:
		if is_instance_valid(c) and not String(KINDS[c.kind]["voice"]).is_empty():
			ranked.append(c)
	ranked.sort_custom(func(a: Critter, b: Critter) -> bool:
		return a.global_position.distance_squared_to(eye) \
			< b.global_position.distance_squared_to(eye))
	var want := ranked.slice(0, VOICES)
	for c in _voiced:
		if is_instance_valid(c) and not want.has(c):
			c.listen(false)
	for c: Critter in want:
		c.listen(true, String(KINDS[c.kind]["voice"]))
	_voiced = want


func _eye() -> Vector3:
	return GameState.camera_focus
