class_name LavaSkin
extends MeshInstance3D
## FRESH LAVA, CHURNING — laid over the ground it was just poured on.
##
## The ground's colour is baked into each chunk's vertices when the chunk is
## cut, so a pour could only ever be one flat ember orange until it crusted
## over; nothing on it moved. This is a skin of the ground's own triangles,
## lifted a hair, drawn by shaders/lava_skin.gdshader: deep orange and bulbous
## red, mixing and swelling. It lives exactly as long as the lava is molten —
## the scar's own clock (TerrainScars.EMBER_SECONDS, then COOLING) — and goes.
##
## ONE SKIN A POOL. A pour that lands on lava still molten warms the skin
## already there and widens it, so a volcano's flank is a few skins rather than
## sixty. And it is laid again whenever a chunk under it is cut again, which is
## what a second pour, a crater or a coarser ring does to the ground.

## How far over the ground it lies, so it never fights the ground for the pixel.
const LIFT := 0.04
## A pour this near a skin, as a share of its radius, warms that skin.
const MERGE := 0.7
const SHADER := preload("res://shaders/lava_skin.gdshader")

var centre := Vector2.ZERO
var radius := 0.0
var _born := 0.0
var _world: WorldGen = null
var _skin: ShaderMaterial = null
var _cuts := {}            # Vector2i chunk cell -> the cut it was laid over
var _fear_due := 0.0       # the scar clock at which it next frightens anybody


## LAVA POURED HERE: the skin already molten near it warmed, or a new one laid.
static func pour(world: WorldGen, at: Vector2, reach: float) -> LavaSkin:
	for n in world.get_tree().get_nodes_in_group("lava_skins"):
		var near := n as LavaSkin
		if near != null and is_instance_valid(near) and not near.is_queued_for_deletion() \
				and near.centre.distance_to(at) < near.radius * MERGE:
			near._fresh(at, reach)
			return near
	var laid := LavaSkin.new()
	laid._world = world
	world.add_child(laid)
	laid._fresh(at, reach)
	return laid


## How molten it still is, 0..1, from how long ago it was last poured: the
## land's own reckoning (TerrainScars.heat), so the glow and the heat people
## keep away from go out together.
static func heat_at(age: float) -> float:
	return TerrainScars.heat(age)


func _ready() -> void:
	add_to_group("lava_skins")
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_skin = ShaderMaterial.new()
	_skin.shader = SHADER
	material_override = _skin


func _process(_delta: float) -> void:
	Ledger.open(&"LavaSkin")
	if _world == null or not is_instance_valid(_world):
		queue_free()
		return
	var heat := heat_at(_world.scars.clock - _born)
	if heat <= 0.0:
		queue_free()
		return
	_skin.set_shader_parameter(&"heat", heat)
	if _stale():
		_drape()
	# SEEN, AND RUN FROM: a pool still molten sends whoever is near it running,
	# every few seconds rather than every frame (HotGround.frighten).
	if heat >= HotGround.FEARED_ABOVE and _world.scars.clock >= _fear_due:
		_fear_due = _world.scars.clock + HotGround.FRIGHTENS_EVERY
		HotGround.frighten(Vector3(centre.x, _world.height_at(centre.x, centre.y), centre.y), radius)


## Poured on: hot again, and wide enough to cover the new pour too.
func _fresh(at: Vector2, reach: float) -> void:
	if radius <= 0.0:
		centre = at
		radius = reach
	else:
		radius = maxf(radius, centre.distance_to(at) + reach)
	_born = _world.scars.clock
	_fear_due = _born          # a fresh pour is seen at once
	_drape()


## Has a chunk under it been cut again since it was laid?
func _stale() -> bool:
	for cell: Vector2i in _cuts:
		var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * WorldGen.CHUNK_SIZE
		var chunk := _world.chunk_at(mid.x, mid.y)
		if chunk == null or chunk.cuts != int(_cuts[cell]):
			return true
	return false


## LAID ON THE GROUND'S OWN TRIANGLES: every cell of every chunk under the pool,
## split the way the chunk splits it (Chunk._cut_mesh), at the heights the
## chunk drew. Flat sheets laid over a dome go under it in the middle.
func _drape() -> void:
	_cuts.clear()
	_skin.set_shader_parameter(&"centre", centre)
	_skin.set_shader_parameter(&"radius", radius)
	var lo := centre - Vector2(radius, radius)
	var hi := centre + Vector2(radius, radius)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for cz in range(floori(lo.y / WorldGen.CHUNK_SIZE), floori(hi.y / WorldGen.CHUNK_SIZE) + 1):
		for cx in range(floori(lo.x / WorldGen.CHUNK_SIZE), floori(hi.x / WorldGen.CHUNK_SIZE) + 1):
			var cell := Vector2i(cx, cz)
			var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * WorldGen.CHUNK_SIZE
			var chunk := _world.chunk_at(mid.x, mid.y)
			if chunk == null:
				continue
			_cuts[cell] = chunk.cuts
			var step := chunk.ground_step()
			if step <= 0.0:
				continue
			var origin := Vector2(chunk.position.x, chunk.position.z)
			for iz in range(maxi(floori((lo.y - origin.y) / step), 0),
					mini(ceili((hi.y - origin.y) / step), int(WorldGen.CHUNK_SIZE / step))):
				for ix in range(maxi(floori((lo.x - origin.x) / step), 0),
						mini(ceili((hi.x - origin.x) / step), int(WorldGen.CHUNK_SIZE / step))):
					var x0 := origin.x + ix * step
					var z0 := origin.y + iz * step
					var corners := [Vector2(x0, z0), Vector2(x0 + step, z0),
						Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step)]
					for idx: int in [0, 1, 2, 0, 2, 3]:
						var c: Vector2 = corners[idx]
						st.add_vertex(Vector3(c.x, chunk.drawn_height(c.x, c.y) + LIFT, c.y))
					any = true
	mesh = st.commit() if any else null
