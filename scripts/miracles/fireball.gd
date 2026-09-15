class_name Fireball
extends RigidBody3D
## A miraculous ball of fire, conjured into the divine hand. Throw it: it flies
## with real momentum and arcs under gravity. What happens when it lands is the
## difference between the two miracles this one class casts.
##
## SETTING SOMETHING ALIGHT SHOULD NOT COST YOU THE FIELD IT WAS STANDING IN.
## For a long time the only fire in the spellbook was the one that cratered the
## ground it hit, so burning a wood meant digging it up as well, and a player
## who wanted a fire had no way to ask for one that was only a fire. That is
## backwards: deforming the land is a bigger, angrier thing than kindling, and
## it should take more saying.
##
## So bare FIRE is a GOUT — a thrown lick of flame that skids to a stop and guts
## out where it settles, lighting what it touched on the way and leaving the
## earth exactly as it found it. FIRE AND FURY is the FIREBLAST: the old
## detonation, the crater, the killing core. Fury is already the rune of
## violence done to a thing (see earth+fury, the earthquake), so the second
## stroke is the player saying out loud that they want the ground to remember.
const KINDS := {
	# The gout. No crater, no killing core — it burns, and that is all it does,
	# which is exactly why it exists. It skids to a halt far faster than the
	# blast does, because a gout of flame that rolled across the county would
	# be a blast with extra steps.
	"fireball": {
		"reach": 3.2, "kill": 0.0, "hurt": 18.0, "house": 14.0,
		"trail": 2.2, "digs": false, "grip": 9.0, "roll": 1.0,
		"fuse": 14.0, "loud": 1.2, "flare": 0.55,
		"label": "Gout of flame (throw it!)",
	},
	# The blast, unchanged in every number: what `fire` used to be, now asked
	# for with a second stroke.
	"fireblast": {
		"reach": 6.0, "kill": 2.2, "hurt": 45.0, "house": 50.0,
		"trail": 1.7, "digs": true, "grip": 3.6, "roll": 2.5,
		"fuse": 25.0, "loud": 4.0, "flare": 1.0,
		"label": "Fireblast (throw it!)",
	},
}

const KARMA_PER_KILL := -3.0
## What one head of a burned herd is worth against that. Less than a person,
## and not nothing: forty of them is worse than one villager.
const KARMA_PER_HEAD := 0.25
const TRAIL_INTERVAL := 0.09     # seconds between flames dropped in flight
const REST_SPEED := 1.2           # below this it has come to rest -> bursts

## THE ROLLING PROBLEM. A fireball is a sphere, and `friction` on a physics
## material only resists SLIDING — a rolling ball it barely touches. With no
## damping at all, one thrown at a hillside would roll to the lowest point in
## the county and burst three villages away from where it was aimed.
##
## So it is braked BY HAND, and only once it is actually on the ground: damping
## it in flight would flatten the ballistic arc that makes throwing feel like
## throwing. The grip is per second and exponential — see KINDS, where the gout
## takes a far harder one than the blast — so a 20 m/s roll is down to a walking
## pace inside a second, and for the gout inside a third of one.
const SPIN_GRIP := 4.5
## How close to the ground counts as rolling rather than flying.
const TOUCHING := 0.7
## And a hard stop: however gentle the slope, it goes off after `roll` seconds
## on the ground. Nothing rolls out of the shot the player actually took.

## HOW DEEP IT DIGS. A fireball does not only scorch — it takes a divot out of
## the earth and blackens what is left, and the mark stays in the world.
##
## A DIVOT, not an excavation. It was 1.7m deep across 4.8m, which is a bomb
## crater: two of them on a spot dug through the two metres of freeboard under
## the village and let the sea in, and a handful of them turned a field into
## the Somme. A fireball is the cheapest thing in the spellbook and it is meant
## to be thrown by the dozen, so what it leaves has to be something a landscape
## can absorb by the dozen — a scorched dish you could stand in, ankle deep.
const GOUGE_DEPTH := 0.45
const GOUGE_RADIUS := 2.4
const GOUGE_CHAR := 0.9

## And a FLOOR under the digging. Scars add, so however shallow one divot is,
## the twentieth on the same spot is still twenty of them; past this much
## hollowing the ground here simply stops giving. Deliberately under the two
## metres the village cradle stands above the sea, so no amount of shelling a
## town can open it to the water — that consequence is left to the miracles
## that are actually about moving earth.
const DIG_FLOOR := 1.6

## Which of the two this one is — a key of KINDS. Set by MiracleManager before
## the body enters the tree.
var kind := "fireblast"

var _armed := false
var _exploded := false
var _trail_time := 0.0
var _rolling := 0.0


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	mass = 2.0
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	phys.bounce = 0.0
	physics_material_override = phys


func _ready() -> void:
	add_to_group(Affords.PICKABLE)
	var spec: Dictionary = KINDS[kind]

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	col.shape = shape
	add_child(col)

	add_child(Util.sphere(0.35, Color(1.0, 0.45, 0.1), Vector3.ZERO, true))
	add_child(Util.sphere(0.22, Color(1.0, 0.85, 0.3), Vector3.ZERO, true))

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 2.5
	light.omni_range = 9.0
	add_child(light)

	var embers := CPUParticles3D.new()
	embers.amount = Quality.particles(40)
	embers.lifetime = 0.7
	embers.mesh = _ember_mesh()
	embers.direction = Vector3.UP
	embers.initial_velocity_min = 0.5
	embers.initial_velocity_max = 1.5
	embers.gravity = Vector3(0, 1.5, 0)
	add_child(embers)

	get_tree().create_timer(float(spec["fuse"])).timeout.connect(_go_off)


## Two triangles, glowing, always facing you. It was a full 64x32 UV sphere.
func _ember_mesh() -> QuadMesh:
	return Util.speck_mesh(0.1, 0.1, Color(1.0, 0.7, 0.2), true)


func _physics_process(delta: float) -> void:
	if freeze:
		return  # still in the grip
	# Arms the moment the hand lets go and it's genuinely in flight.
	if not _armed and linear_velocity.length() > 2.0:
		_armed = true
	if _armed:
		_lay_trail(delta)
		_brake(delta)
		# It rolls until it stops, then goes off where it settles.
		if linear_velocity.length() < REST_SPEED \
				or _rolling > float(KINDS[kind]["roll"]):
			_go_off()


## Slow the roll — but only once it is down. In the air it keeps every bit of
## the momentum the throw gave it; the moment it touches, the ground drags it
## down hard. Horizontal only, so gravity is never fought.
func _brake(delta: float) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return
	var ground := world.surface_at(global_position.x, global_position.z)
	if global_position.y > ground + TOUCHING:
		return                       # still flying: leave the arc alone
	_rolling += delta
	var drag := exp(-float(KINDS[kind]["grip"]) * delta)
	linear_velocity.x *= drag
	linear_velocity.z *= drag
	angular_velocity *= exp(-SPIN_GRIP * delta)


## Drops a small flame at the ball's ground track and lightly sets alight
## whatever it rolls past — a narrow, spreading wake of fire behind the throw.
func _lay_trail(delta: float) -> void:
	_trail_time -= delta
	if _trail_time > 0.0:
		return
	_trail_time = TRAIL_INTERVAL
	var scene := get_tree().current_scene
	if scene == null:
		return
	var gp := global_position
	var ground_y := gp.y
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		ground_y = world.surface_at(gp.x, gp.z)
	var flame := Util.small_flame(0.4)
	flame.scale = Vector3.ONE * 0.5
	flame.position = Vector3(gp.x, ground_y, gp.z)
	scene.add_child(flame)
	get_tree().create_timer(2.2).timeout.connect(flame.queue_free)
	_ignite_trail(gp, float(KINDS[kind]["trail"]))


## The narrow trail catches trees, fields, and any soul it brushes.
## WHAT A BUILDING IS WORTH IN FULL, for scaling a blow against it. Read off
## the thing itself rather than kept in a table here, because a table here would
## be a second opinion about how tough a granary is and the two would drift.
static func _most_of(built: Node3D) -> float:
	if built.has_method("full_health"):
		return float(built.call("full_health"))
	return 100.0


func _ignite_trail(pos: Vector3, reach: float) -> void:
	# ANYTHING THAT CAN SEE IT GOES. Fleeing reaches much further than burning:
	# a beast does not wait to find out whether the fire rolling past will
	# actually touch it.
	for h in get_tree().get_nodes_in_group("herds"):
		var herd := h as Herd
		if is_instance_valid(herd):
			herd.bolt_from(pos, reach * Herd.FIRE_FLEES)
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(pos) < reach:
			tree.ignite()
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(pos) < reach:
			farm.ignite()
	for grp in ["villagers", "animals"]:
		for n in get_tree().get_nodes_in_group(grp):
			var node := n as Node3D
			if not is_instance_valid(node):
				continue
			var d := node.global_position.distance_to(pos)
			# A TRAIL IS A LICK OF FLAME, not a bonfire: a third of a core, so
			# something skidding past a wall scorches it and something landing
			# on it does not.
			if d < reach and node.has_method("scorch"):
				node.call("scorch", Kindling.HEAT_OF_A_BLAZE / 3.0)
			# Wider than it burns: they run from the flame rolling past them
			# whether or not it is going to touch them.
			if d < reach * Herd.FIRE_FLEES and node.has_method("scare"):
				node.call("scare", pos)


## SET IT OFF WHERE IT STANDS, without waiting for it to get there.
##
## Landing reaches the same code — this is the door for anything that needs the
## effect at a chosen point, which in practice means the smoke tests. They used
## to ask MiracleManager.resolve("fireball", spot) for it, and resolve has no
## fireball case: a thrown ball does its own work when it lands. So the two
## tests that claimed to prove the digging floor and the merging of scars were
## measuring nothing at all, and passing on it, for as long as they have existed.
func burst() -> void:
	_go_off()


## WHERE IT SETTLES. Both kinds land the same way and differ in what landing
## means: the gout scorches a small ring and guts out, the blast detonates,
## kills at the core and takes a bowl out of the earth. Every number below comes
## off the KINDS row, so the difference between a kindling and a bombardment is
## a table rather than two copies of this function.
func _go_off() -> void:
	if _exploded or freeze:  # never in the player's grip
		return
	_exploded = true
	var spec: Dictionary = KINDS[kind]
	var reach: float = spec["reach"]
	var kill: float = spec["kill"]
	var pos := global_position
	SoundBank.play_at("boom", pos, float(spec["loud"]))
	_blast_visuals(pos, reach * float(spec["flare"]))

	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		var d := villager.global_position.distance_to(pos)
		# A gout has no killing core at all — `kill` is zero and this never
		# fires. Being set alight can still finish somebody; it just is not
		# instant, and it is survivable if the town is quick.
		if d < kill:
			GameState.shift_alignment(KARMA_PER_KILL)
			villager.take_damage(999.0, true, true)  # point-blank is instant
		elif d < reach:
			villager.take_damage(float(spec["hurt"]), true)
			villager.ignite()  # the fire sets them alight
			villager.scare(pos)

	for a in get_tree().get_nodes_in_group("animals"):
		var animal := a as Animal
		var d := animal.global_position.distance_to(pos)
		if d < kill:
			animal.die()
		elif d < reach * Herd.FIRE_FLEES:
			if d < reach:
				animal.ignite()
			animal.scare(pos)

	# THE HERDS, WHICH ARE MOST OF THE ANIMALS IN THE WORLD. The loop above
	# reaches a herd's promoted few and nothing else — a couple of dozen head
	# out of however many hundred — so until now a blast thrown into two hundred
	# caribou killed the handful that happened to be real and the rest did not
	# look up. Herd.scorched counts them where they actually stand.
	var caught := 0
	for h in get_tree().get_nodes_in_group("herds"):
		var herd := h as Herd
		if is_instance_valid(herd):
			caught += herd.scorched(pos, reach, kill)
	# AND IT COSTS SOMETHING. Burning a herd alive is charged per head, and the
	# GOUT is charged for it too — the first version only charged when the
	# miracle had a killing core, which meant setting forty head of cattle
	# alight with the miracle designed for setting things alight was free.
	if caught > 0:
		GameState.shift_alignment(KARMA_PER_KILL * KARMA_PER_HEAD * float(caught))

	# EVERYTHING A VILLAGE RAISED, not only its houses. A fire that spared the
	# mill, the well, the barn, the school and the granary was a fire the town
	# could shrug off, and every building added since the houses was in effect
	# fireproof. See Kindling.
	for b in get_tree().get_nodes_in_group(Affords.BURNABLE):
		var built := b as Node3D
		if not is_instance_valid(built) \
				or built.global_position.distance_to(pos) > reach:
			continue
		if built.has_method("damage"):
			# A SHARE OF WHAT IT IS, not a flat number. These were written when
			# every building in the game had a hundred health; now that a
			# granary is worth seven hundred, fifty points off it is a scorch.
			# Scaled by the building's own full health so the big core still
			# takes half a hut down and correspondingly less of a barn — which
			# is what "a barn is stouter than a hut" has to mean.
			built.call("damage",
				float(spec["house"]) * 0.01 * _most_of(built))
		# ...AND IT IS HEATED, which is now the difference between a blast and
		# a fire. It used to CATCH — one core, one building alight, whether it
		# was thatch or a stone granary. A fireball is a great deal of heat and
		# not a decision: whether a thing burns is a question about the thing.
		# See Kindling.warm.
		if built.has_method("scorch"):
			built.call("scorch", Kindling.HEAT_OF_A_BLAZE)

	# Fire catches on the trees it touches — and spreads from there. This is
	# the whole of what a gout is FOR.
	for t in get_tree().get_nodes_in_group("trees"):
		var tree := t as WildTree
		if is_instance_valid(tree) and tree.global_position.distance_to(pos) < reach:
			tree.ignite()

	# A field in reach goes up too.
	for f in get_tree().get_nodes_in_group("farms"):
		var farm := f as Farm
		if is_instance_valid(farm) and farm.global_position.distance_to(pos) < reach:
			farm.ignite()

	# THE EARTH ITSELF. A bowl gouged out of the ground with a lip of thrown
	# spoil around it, and the whole of it burned black — and unlike everything
	# else here, it stays. Come back in an hour and the crater is still there.
	# The gout does not do this, which is its entire reason for existing.
	if bool(spec["digs"]):
		_gouge(pos)

	# WHAT THE CAST ITSELF COSTS. Every other miracle is charged its karma by
	# MiracleManager.resolve — and a thrown fire never goes through resolve,
	# because it does its own work where it lands. So the fireball's row in that
	# table has NEVER been applied: for as long as the game has had fire,
	# hurling it has cost a god nothing at all unless it happened to kill
	# somebody at point blank. The file's own header says the gods of peace do
	# not learn this one; mechanically they might as well have.
	var due: Dictionary = MiracleManager.KARMA.get(kind, {})
	if not due.is_empty():
		GameState.shift_alignment(float(due["player"]))
		var creature := get_tree().get_first_node_in_group("creature") as Creature
		if creature != null and is_instance_valid(creature) \
				and creature.global_position.distance_to(pos) \
					< MiracleManager.CREATURE_SIGHT_RANGE:
			creature.witness(float(due["creature"]))
			creature.mind.witness_miracle(kind)
	CreatureHead.startled(
		get_tree().get_first_node_in_group("creature") as Creature, pos)

	# The blast is the sermon: terror converts where the fire LANDS.
	for v in get_tree().get_nodes_in_group("village"):
		(v as Village).witness_miracle(kind, pos)

	queue_free()


## Take the divot, and blacken it. Skipped over open water, where there is no
## ground to dig and a dish in the lake bed would only be a bigger lake.
##
## The BURNING is not rationed and never has been: a spot shelled a dozen times
## is scorched earth (see TerrainScars.scorch_at, which saturates rather than
## sums). Only the digging has a floor.
func _gouge(pos: Vector3) -> void:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null or world.is_underwater(pos.x, pos.z):
		return
	var here := Vector2(pos.x, pos.z)
	# How much hollowing is left in this ground. Eases into the floor rather
	# than snapping at it, so the last throw that reaches it still does a
	# little rather than nothing.
	var depth := minf(GOUGE_DEPTH,
		maxf(0.0, DIG_FLOOR + world.scars.offset_at(here.x, here.y)))
	# POURED, not cut afresh. A divot laid near one already there GROWS it (see
	# TerrainScars.deposit): shelling one field a hundred times leaves a
	# handful of scars rather than a hundred, which matters because `offset_at`
	# walks every scar near a point on every routing and meshing query in the
	# game. Dry ground — the guard above already turned back over water.
	world.pour(TerrainScars.Kind.CRATER, here, GOUGE_RADIUS, -depth, GOUGE_CHAR)
	# THE WATERLINE IS A THING YOU CAN DIG THROUGH, and it stays that way — but
	# not with fireballs any more. At 0.45m a throw against a 1.6m floor, the
	# ground never opens under a village standing two metres clear of the sea;
	# somewhere already near the waterline it still can, which is the right
	# place for it. Asked of the WATER and not of the number, because inland a
	# hole below sea level stays dry (see WorldGen.sea_reaches).
	if world.is_underwater(here.x, here.y):
		GameState.announce("The ground breaks below the waterline, and the water comes in.")


func _blast_visuals(pos: Vector3, size: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fire := Util.sphere(0.5, Color(1.0, 0.55, 0.1, 0.9), Vector3.ZERO, true)
	fire.position = pos
	scene.add_child(fire)
	# The flash is sized off the same number, so a gout guttering out is a warm
	# flicker and a blast is still the thing that lights up the valley.
	var lit := clampf(size / 6.0, 0.2, 1.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.2)
	flash.light_energy = 7.0 * lit
	flash.omni_range = 22.0 * lit
	flash.position = pos + Vector3(0, 2, 0)
	scene.add_child(flash)
	# There used to be a black disc laid on the ground here, faded out after
	# twenty-five seconds. It is gone: the scorch is now cut into the terrain
	# itself (see `_gouge`), so it is a real feature of the world rather than a
	# decal with a timer, and it does not vanish while you are looking at it.
	var tween := scene.create_tween()
	tween.tween_property(fire, "scale", Vector3.ONE * size, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(fire, "transparency", 1.0, 0.45)
	tween.parallel().tween_property(flash, "light_energy", 0.0, 0.5)
	tween.tween_callback(fire.queue_free)
	tween.tween_callback(flash.queue_free)


func hover_text() -> String:
	return str(KINDS[kind]["label"])
