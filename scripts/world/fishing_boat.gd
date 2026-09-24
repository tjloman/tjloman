class_name FishingBoat
extends RigidBody3D
## A BOAT, WHICH IS WHAT A HARBOUR LOOKS LIKE AND MOST OF WHAT IT EARNS.
##
## The barn set the precedent and said why: a village with forty beasts in it
## should LOOK like a village with forty beasts in it, twice a day, in a line.
## A fishing town is the same argument about water — except that a boat is not
## only a readout. Two of a harbour's fish come off the shore and the rest come
## out of the boats, so a fleet burnt, beached or carried off by a god is a town
## that goes hungry. See Workshop.FISH_PER_BOAT.
##
## IT IS A THING IN THE WORLD, with everything that means here: you can pick it
## up, throw it, set it on fire and watch it burn to the waterline. A god who
## wants a fishing village to stop fishing does not have to level the jetty.
##
## AND IT BELONGS ON THE WATER. Left alone it rows between its mooring and the
## grounds, riding the surface wherever the surface happens to be — which is
## not a constant, because a pond caught in a crater sits at a different height
## from the sea. Thrown onto dry land it is BEACHED: it lies there, it is still
## a boat, and it catches nothing until somebody puts it back in the water.

## How fast it rows, and how far off its mooring counts as arrived.
const ROWS_AT := 2.6
const ARRIVED := 2.0
## The swell: how far it rises and how far it leans, and how fast. Small
## numbers — a boat that pitches visibly is a boat in trouble.
const BOB := 0.14
const ROLL := 0.06
const SWELL := 1.15
## Below this it has stopped tumbling and can be set down on whatever it landed
## on. Generous, because a hull is not a ball and will not roll for ever.
const SETTLED_UNDER := 1.1

## HOW MUCH WATER A BOAT KEEPS AROUND ITSELF, and how hard it leans out of the
## way. A hull is about four metres, so anything closer than this is two boats
## sharing a square of sea.
##
## The berths a harbour hands out are already spread (Waters.a_berth), and this
## is for everything that spreads cannot know about: a second harbour fishing
## the same bay, a boat thrown across the map and re-moored wherever it came
## down, and the crowd at the jetty where the moorings are only a couple of
## metres apart by design.
const CLEARS := 4.2
const GIVES_WAY := 1.6

## WHAT IT IS MADE OF, and what it is worth pulling apart. Timber and tar and
## nothing else, so it catches far more readily than a house does.
const MOST_HEALTH := 120.0

## WHAT A TRIP BRINGS BACK, landed when the boat ties up again.
##
## THE BOAT BANKS IT, NOT THE DOCK, and that is not a detail. A shift is worked
## by a PERSON, so a harbour crediting the fleet's haul on every shift credited
## it once per worker on the jetty — three people standing on shore tripled the
## catch of the same three boats. A boat lands what a boat caught.
const CATCH := 10

## Where it is tied up, and where it fishes. Both world points, both set by the
## dock that built it — along with the granary its hauls go into.
var mooring := Vector3.INF
var grounds := Vector3.INF
var home_store: FoodStore = null
var kindling := Kindling.new()
var health := MOST_HEALTH

var _out := 0.0
var _phase := 0.0
## Loose in the world: thrown, dropped, or otherwise not under its own command
## until it comes to rest. A boat that has come to rest on dry land is beached.
var _loose := false
var _beached := false
var _was_held := false


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	mass = 5.0
	freeze = true          # it steers itself; physics only while it is loose
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.05
	physics_material_override = phys


func _ready() -> void:
	add_to_group("boats")
	add_to_group(Affords.PICKABLE)
	add_to_group(Affords.BURNABLE)
	kindling.temper = Kindling.TEMPER_TIMBER
	_phase = randf() * TAU
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.9, 0.9, 1.1)
	col.shape = shape
	col.position = Vector3(0, 0.45, 0)
	add_child(col)
	set_meta("hover_name", "Fishing boat")
	_build_hull()


## A clinker hull, a thwart and a stub of a mast. Enough to read as a boat from
## the hill, which is the only distance it is ever seen from.
func _build_hull() -> void:
	var timber := Color(0.46, 0.34, 0.22)
	add_child(Util.lite_box(Vector3(2.9, 0.42, 1.05), timber, Vector3(0, 0.21, 0)))
	# The sheer: a narrower strake above, which is what stops it reading as a
	# crate floating on its side.
	add_child(Util.lite_box(Vector3(2.4, 0.22, 0.78),
		timber.lightened(0.12), Vector3(0, 0.5, 0)))
	add_child(Util.lite_box(Vector3(0.1, 1.5, 0.1),
		timber.darkened(0.1), Vector3(-0.2, 1.1, 0)))
	add_child(Util.lite_box(Vector3(0.7, 0.08, 0.9),
		timber.darkened(0.2), Vector3(0.5, 0.46, 0)))


## PUT TO SEA for this many seconds. Called by the dock on every shift worked,
## so a busy harbour keeps its boats out and a quiet one keeps them tied up.
func put_to_sea(seconds: float) -> void:
	if _beached or kindling.alight:
		return
	_out = maxf(_out, seconds)


## IS THIS BOAT EARNING? On the water, under its own command, not alight and
## not in anybody's hand. The granary's question — see Workshop.boats_at_sea.
func is_fishing() -> bool:
	return not _beached and not _loose and not kindling.alight


## IS IT AWAY FROM ITS MOORING RIGHT NOW? Different from `is_fishing`, which
## asks whether it is capable of earning at all.
func is_out() -> bool:
	return _out > 0.0


func hover_text() -> String:
	if kindling.alight:
		return "Fishing boat — ON FIRE"
	if _beached:
		return "Fishing boat — beached, and catching nothing"
	return "Fishing boat — %s" % ("out on the water" if _out > 0.0 else "moored")


func _physics_process(delta: float) -> void:
	Ledger.open(&"FishingBoat")
	kindling.cool(delta)
	var harm := kindling.smoulder(self, delta, MOST_HEALTH)
	if harm > 0.0:
		damage(harm)
		if not is_instance_valid(self):
			return
	if freeze and _was_held:
		return                      # in a hand, or on the creature's back
	if not freeze:
		# LET GO OF, AND FALLING. Physics has it until it stops moving; then it
		# finds out where it landed. A boat is not a ball and this is the whole
		# of its flight — see Blow for what happens when it hits something.
		_was_held = false
		_loose = true
		if linear_velocity.length() < SETTLED_UNDER:
			_come_to_rest()
		return
	if _loose:
		return
	_row(delta)


## WHERE IT LANDED DECIDES WHAT IT IS. Water and it floats and fishes again,
## from wherever it now finds itself; dry land and it is a beached boat, which
## is a thing a village can see and go and do something about.
func _come_to_rest() -> void:
	_loose = false
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	_beached = world == null or not world.is_underwater(global_position.x, global_position.z)
	if _beached:
		_out = 0.0
		rotation.z = 0.0
		return
	# Afloat somewhere new. Tie up where it is, and fish from here.
	mooring = global_position
	if grounds == Vector3.INF or not grounds.is_finite():
		grounds = Waters.off_shore(world, global_position, Workshop.GROUNDS_OUT)


## THE ROWING, and the swell under it. Runs on GameState.clock so a paused
## harbour is a still one and a fleet does not lurch a minute's worth of sea
## the frame the temple closes.
func _row(delta: float) -> void:
	if Util.sim_stride(global_position) > 4:
		return
	var was_out := _out > 0.0
	_out = maxf(_out - delta, 0.0)
	if was_out and _out <= 0.0:
		_land_the_catch()
	var want := grounds if _out > 0.0 else mooring
	if not want.is_finite():
		want = global_position
	var here := global_position
	var flat := Vector3(want.x - here.x, 0.0, want.z - here.z)
	if flat.length() > ARRIVED:
		var step: Vector3 = flat.normalized() * minf(ROWS_AT * delta, flat.length())
		here += step
		# Facing comes off the heading rather than look_at, which would try to
		# point the hull at a spot on the water it is already level with.
		rotation.y = atan2(step.x, step.z)
	# AND KEEP OUT OF THE OTHER HULLS while doing it.
	here += _give_way(here) * GIVES_WAY * delta
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	var sea := here.y
	if world != null:
		sea = world.surface_at(here.x, here.z)
	var beat := GameState.clock * SWELL + _phase
	here.y = sea + sin(beat) * BOB
	global_position = here
	rotation.z = sin(beat * 0.7) * ROLL


## LEAN OUT OF THE WAY OF THE OTHER BOATS. The sum of how far each one nearby
## is inside this one's water, pointed away from it.
##
## TWO BOATS IN EXACTLY THE SAME PLACE have no direction between them to push
## along, and that is not a hypothetical: it is what the old shared fishing spot
## produced every time, and the case a separation rule is most likely to be
## asked about and least likely to have been written for. Each hull leans along
## a bearing of its own, taken from its own instance, so a pile comes apart
## instead of sitting there dividing by zero.
func _give_way(here: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("boats"):
		var other := n as Node3D
		if other == null or other == self or not is_instance_valid(other):
			continue
		var gap := Vector3(here.x - other.global_position.x, 0.0,
			here.z - other.global_position.z)
		var apart := gap.length()
		if apart >= CLEARS:
			continue
		if apart < 0.01:
			var mine := float(get_instance_id() % 628) * 0.01
			push += Vector3(cos(mine), 0.0, sin(mine)) * CLEARS
			continue
		push += gap.normalized() * (CLEARS - apart)
	return push


## THE HAUL, INTO THE GRANARY. The one thing in this file that is not scenery:
## most of a fishing town's food comes through here.
func _land_the_catch() -> void:
	if home_store == null or not is_instance_valid(home_store):
		return
	home_store.add(FoodItem.FoodType.MEAT, CATCH)


## TAKEN UP BY A HAND. The hand freezes what it holds, and a frozen boat that
## has not been let go of is indistinguishable from one steering itself — so it
## is told, once, which of the two it is.
func pick_up() -> void:
	_was_held = true
	_out = 0.0


## THE BURNABLE CONTRACT — see Affords.OWES. A boat is timber and tar: it takes
## far less to light than a house and rather less to sink.
func scorch(joules: float) -> void:
	kindling.warm(self, joules, 2.0)


func ignite() -> void:
	kindling.light(self, 2.0)


func extinguish() -> void:
	kindling.douse(self)


func full_health() -> float:
	return MOST_HEALTH


func damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		burn_down()


## Gone. A hull is not rubble — it goes under, and there is nothing left to
## stand on the shore and look at.
func burn_down() -> void:
	SoundBank.play_at("boom", global_position, -6.0, 0.2, 1.4)
	queue_free()
