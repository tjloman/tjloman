class_name Quench
extends RefCounted
## WHAT WATER DOES TO FIRE.
##
## Every fire in the hand went straight through the surface as though it were
## not there: a gout sank to the lake bed and burned nothing down there, a
## fireblast went off under ten metres of water, and a lavaball landed on the
## sea floor, where pouring lava was refused outright — so nothing happened at
## all. Now each one meets the water at its surface:
##
##   A GOUT, or a firestorm's orb, FIZZLES: a hiss and a puff of steam, and
##   that is all it ever does.
##   A FIREBLAST GOES OFF ON THE SURFACE: the blast where it touched, a column
##   of spray and steam — and no crater, there being no ground to dig.
##   A LAVABALL MEETS IT AND SETS: a burst of steam, a few boulders thrown up
##   out of it still burning, and its core sinking, darkening, to become new
##   floor — black rock, as on land, with no ember left in it. Enough of them
##   and the floor breaks the surface: new land.

## What water does to each kind of conjured orb that is fire (MiracleOrb).
## Anything not here goes through the surface as it always has.
const AT_THE_SURFACE := {"lavaball": "quench", "firestorm": "fizzle"}

## How long the molten core takes to sink and set, in seconds.
const SINKS_FOR := 1.2
## The boulders a lavaball throws up: how many, and how big (RockDeposit rungs).
const BOULDERS_LEAST := 2
const BOULDERS_MOST := 4
const BOULDER_RUNGS: Array[int] = [1, 1, 2, 2, 3]


## THE WATER'S SURFACE under a body, or -INF where it is over dry ground.
static func surface_under(tree: SceneTree, at: Vector3) -> float:
	var world := tree.get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return -INF
	return world.water_level_at(at.x, at.z)


## Has this body met the water — at the surface or below it?
static func in_water(body: Node3D) -> bool:
	var top := surface_under(body.get_tree(), body.global_position)
	return not is_inf(top) and body.global_position.y <= top + 0.05


## A HISS AND A PUFF OF STEAM, and nothing else: a fire the water put out.
static func fizzle(scene: Node, at: Vector3, size := 1.0) -> void:
	if scene == null:
		return
	SoundBank.play_at("whisper", at, -6.0, 0.2, 0.55)
	steam(scene, at, 0.8 * size, 1.6)


## A COLUMN OF SPRAY AND STEAM, for a fire that went off on the water.
static func burst(scene: Node, at: Vector3, reach: float) -> void:
	if scene == null:
		return
	steam(scene, at, reach * 0.6, 2.6)
	var spray := CPUParticles3D.new()
	spray.amount = Quality.particles(40)
	spray.lifetime = 1.4
	spray.one_shot = true
	spray.explosiveness = 0.9
	spray.mesh = Util.speck_mesh(0.18, 0.18, Color(0.82, 0.9, 1.0, 0.85), true)
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = reach * 0.25
	spray.direction = Vector3.UP
	spray.spread = 25.0
	spray.initial_velocity_min = 6.0
	spray.initial_velocity_max = 13.0
	spray.gravity = Vector3(0, -16.0, 0)
	spray.position = at
	scene.add_child(spray)
	spray.emitting = true
	scene.get_tree().create_timer(spray.lifetime + 0.5).timeout.connect(spray.queue_free)


## STEAM, rising and spreading from a point on the water.
static func steam(scene: Node, at: Vector3, size: float, seconds: float) -> void:
	var puff := CPUParticles3D.new()
	puff.amount = Quality.particles(int(14 + size * 10.0))
	puff.lifetime = seconds
	puff.one_shot = true
	puff.explosiveness = 0.6
	puff.mesh = Util.speck_mesh(0.7, 0.7, Color(0.92, 0.93, 0.95, 0.55), true)
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = maxf(size * 0.5, 0.3)
	puff.direction = Vector3.UP
	puff.spread = 35.0
	puff.initial_velocity_min = 1.2
	puff.initial_velocity_max = 3.0 + size
	puff.gravity = Vector3(0, 0.6, 0)
	puff.scale_amount_min = 0.8
	puff.scale_amount_max = 1.8 + size * 0.3
	puff.position = at + Vector3(0, 0.2, 0)
	scene.add_child(puff)
	puff.emitting = true
	scene.get_tree().create_timer(seconds + 0.5).timeout.connect(puff.queue_free)


## A LAVABALL INTO THE WATER, at `at` on the surface: steam, burning boulders
## thrown up, and the core sinking to set as new floor. `lay` is called with
## (where, rise, reach, loud, cooled) when the core reaches the bottom — the
## same laying the lava does on land (MiracleManager.lay_lava), set cold.
static func lava_into_water(owner: Node, world: WorldGen, at: Vector3, rise: float,
		reach: float, loud: bool, lay: Callable) -> void:
	var scene := owner.get_tree().current_scene
	SoundBank.play_at("whisper", at, 2.0, 0.15, 0.4)
	SoundBank.play_at("boom", at, -8.0)
	steam(scene, at, reach, 3.2)
	_boulders(world, at, reach)
	# THE CORE, sinking and going dark on its way down.
	var floor_y := world.height_at(at.x, at.z)
	var core := Util.sphere(0.45, Color(1.0, 0.45, 0.08), Vector3.ZERO, true)
	core.position = at
	scene.add_child(core)
	var sink := owner.create_tween()
	sink.tween_property(core, "position:y", floor_y + 0.2, SINKS_FOR) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	sink.parallel().tween_property(core, "scale", Vector3.ONE * 0.7, SINKS_FOR)
	sink.parallel().tween_property(core, "transparency", 0.85, SINKS_FOR)
	sink.tween_callback(core.queue_free)
	sink.tween_callback(lay.bind(Vector2(at.x, at.z), rise, reach, loud, true))


## Burning boulders, thrown up out of the steam. Wherever they come down in the
## water they go cold (RockDeposit._drowned); on a shore they go on burning.
static func _boulders(world: WorldGen, at: Vector3, reach: float) -> void:
	var parent: Node = world.chunk_at(at.x, at.z)
	if parent == null:
		parent = world
	for i in randi_range(BOULDERS_LEAST, BOULDERS_MOST):
		var rock := RockDeposit.new()
		rock.rung = BOULDER_RUNGS[randi() % BOULDER_RUNGS.size()]
		parent.add_child(rock)
		var away := Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0)
		rock.global_position = at + Vector3(away.x, 0.8, away.y)
		rock.shake_loose()
		rock.linear_velocity = Vector3(away.x, 0.0, away.y) * randf_range(3.0, 4.0 + reach) \
			+ Vector3.UP * randf_range(7.0, 11.0)
		rock.warm(rock.holds())          # alight: it has caught (RockDeposit._catch)
