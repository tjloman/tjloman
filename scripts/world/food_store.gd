class_name FoodStore
extends StaticBody3D
## The village storehouse: a big round market floor, divided into four
## quadrants read like a pie from the sky — grain, meat, lumber, stone —
## each with a colored marker post at the rim and its stock piled inside.
##
##   +X+Z grain (orange) · -X+Z meat (red) · -X-Z lumber (brown) · +X-Z stone (gray)
##
## The hand can WITHDRAW from it (grab the platform: the most plentiful
## resource pops out as a physical item) and anything food- or
## resource-shaped that comes to rest on the platform is absorbed back in.

const PLATFORM_RADIUS := 3.4
const WITHDRAW_BUNDLE := 10  # units pulled per grab (a whole armful)

const GRAIN_COLOR := Color(0.9, 0.6, 0.2)
const MEAT_COLOR := Color(0.72, 0.22, 0.18)
const LUMBER_COLOR := Color(0.55, 0.4, 0.25)
const STONE_COLOR := Color(0.55, 0.54, 0.56)

## WHAT THE PILES SHOW: how full each quarter is, and nothing more exact —
## the hover gives the count. It used to show one mesh per unit, up to twelve
## a quarter, freed and rebuilt at fresh random spots on EVERY deposit and
## every meal: forty-eight nodes of churn and forty-eight draws, flickering
## all day in the middle of every town. Now each quarter is two fixed meshes
## that only ever change scale or visibility.
##
## A quarter's pile grows as it fills, and at HEAP_AT of FULL the heaped mesh
## takes over. It stays heaped until the stock falls to HEAP_UNTIL, so a town
## eating and banking right at the line does not flick between the two.
const FULL := 120
const HEAP_AT := 0.5
const HEAP_UNTIL := 0.4
## How big the growing pile starts, as a share of its size at HEAP_AT.
const SMALLEST := 0.3
## Where each quarter's pile stands: grain, meat, lumber, stone — the order of
## the palette cells, and of the counts in `_show_stock`.
const QUARTERS: Array[Vector3] = [
	Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, -1)]
const PILE_FROM_MIDDLE := 1.9
const FLOOR_TOP := 0.35


## WHAT IT TAKES TO PULL THIS DOWN BY FORCE, against a villager's hundred.
## A building is the thing that PROTECTS the villager, so it cannot be as easy
## to break as the villager is — a fireball that kills the family should not
## also flatten the house in the same instant, and a creature in a temper
## should have to work at it.
##
## Fire is charged as a fraction of this rather than as a flat number, so a
## stout building is stout against BLOWS and still burns to the ground in the
## same minute and a half as a hut. See Kindling.tick.
const MOST_HEALTH := 700.0

## ONE MATERIAL for every pile in every town: a 2x2 texture, one texel a
## resource, and each pile's UVs pinned to its own texel. Baked once.
static var _palette: StandardMaterial3D = null
static var _grow_mesh: Array[Mesh] = []
static var _heap_mesh: Array[Mesh] = []

var plant_food := 14
var meat_food := 0
var lumber := 6
var stone := 3
## How much of it is left, and whether it is alight. See Kindling.
var health := MOST_HEALTH
var kindling := Kindling.new()

var _grow: Array[MeshInstance3D] = []
var _heap: Array[MeshInstance3D] = []
var _heaped: Array[bool] = [false, false, false, false]
var _intake: Area3D
var _intake_time := 0.5

func _ready() -> void:
	kindling.temper = Kindling.TEMPER_STORES   # timber, but packed and damp inside
	add_to_group("stores")
	add_to_group(Affords.BURNABLE)
	add_to_group(WorldGen.SEATED)     # see WorldGen.reseat_over
	set_meta("seat_half", PLATFORM_RADIUS)
	set_meta("hover_name", "Storehouse")
	collision_layer = 4  # hoverable/grabbable by the hand; villagers pass through
	collision_mask = 0

	var col := CollisionShape3D.new()
	var col_shape := CylinderShape3D.new()
	col_shape.radius = PLATFORM_RADIUS + 0.2
	col_shape.height = 0.6
	col.shape = col_shape
	col.position = Vector3(0, 0.3, 0)
	add_child(col)

	# The intake: whatever edible or useful comes to rest on the platform
	# is counted into stock.
	_intake = Area3D.new()
	_intake.collision_layer = 0
	_intake.collision_mask = 4
	var zone := CollisionShape3D.new()
	var zone_shape := CylinderShape3D.new()
	zone_shape.radius = PLATFORM_RADIUS
	zone_shape.height = 3.0
	zone.shape = zone_shape
	zone.position = Vector3(0, 1.2, 0)
	_intake.add_child(zone)
	add_child(_intake)

	# A custom store model replaces the structure; the resource piles still
	# stack on its four quadrants (withdraw/deposit works by position).
	var custom := ModelBank.instantiate("store")
	if custom != null:
		# ON ITS FOOTING, whatever pivot the model was authored with — the
		# same answer, from the same place, that a beast is stood up with.
		# A model pivoted at its middle sinks to the waist without this,
		# which is what "buildings are spawning below ground" was.
		custom.position.y += ModelBank.footing("store")
		add_child(custom)
	else:
		_build_structure()

	_build_piles()
	_show_stock()


## The procedural granary: a round market floor, quartering walls, a canopy
## pole, and a colour-coded marker post at each quadrant's rim.
func _build_structure() -> void:
	add_child(Util.cylinder(PLATFORM_RADIUS + 0.2, 1.4, Color(0.45, 0.36, 0.26),
		Vector3(0, -0.58, 0)))
	add_child(Util.cylinder(PLATFORM_RADIUS, 0.3, Color(0.58, 0.47, 0.33), Vector3(0, 0.2, 0)))

	var wall := Color(0.48, 0.38, 0.27)
	add_child(Util.box(Vector3(PLATFORM_RADIUS * 2.0, 0.5, 0.18), wall, Vector3(0, 0.55, 0)))
	add_child(Util.box(Vector3(0.18, 0.5, PLATFORM_RADIUS * 2.0), wall, Vector3(0, 0.55, 0)))

	add_child(Util.cylinder(0.12, 2.4, Color(0.5, 0.4, 0.28), Vector3(0, 1.2, 0)))
	add_child(Util.prism(Vector3(1.6, 0.7, 1.6), Color(0.65, 0.55, 0.3), Vector3(0, 2.7, 0)))

	for entry: Array in [
		[Vector3(1, 0, 1), GRAIN_COLOR], [Vector3(-1, 0, 1), MEAT_COLOR],
		[Vector3(-1, 0, -1), LUMBER_COLOR], [Vector3(1, 0, -1), STONE_COLOR],
	]:
		var dir: Vector3 = entry[0]
		var color: Color = entry[1]
		var rim := dir.normalized() * (PLATFORM_RADIUS - 0.35)
		add_child(Util.cylinder(0.06, 1.2, Color(0.5, 0.4, 0.28), rim + Vector3(0, 0.6, 0)))
		add_child(Util.sphere(0.18, color, rim + Vector3(0, 1.35, 0), true))


## Absorb items resting on the platform (polled: released items don't
## re-trigger area signals, so we sweep instead).
func _process(delta: float) -> void:
	Ledger.open(&"FoodStore")
	_tick_fire(delta)
	_intake_time -= delta
	if _intake_time > 0.0:
		return
	_intake_time = 0.5
	for body in _intake.get_overlapping_bodies():
		var rb := body as RigidBody3D
		if rb == null or rb.freeze:
			continue  # held things aren't deposits
		if rb.has_meta("no_deposit_until") \
				and GameState.clock < float(rb.get_meta("no_deposit_until")):
			continue  # freshly withdrawn: give the hand time to carry it off
		# NOTHING OF A PERSON IS EVER STOCK.
		#
		# It cannot be banked, so it cannot be served, so it can only ever be
		# eaten where it lies by somebody who has run out of other options —
		# which is the whole of what makes eating it different from eating. A
		# store that took it would turn it into meat_food, and meat_food is
		# what a village hands out at a hearth to anybody who is hungry.
		#
		# Said out loud once per joint, because a player who has carried it all
		# the way here is owed the reason it is being refused.
		if rb is FoodItem and (rb as FoodItem).is_human_meat:
			if not rb.has_meta("refused_at_the_door"):
				rb.set_meta("refused_at_the_door", true)
				GameState.announce("The storehouse will not take that. "
					+ "It goes in nobody's larder.")
			continue
		# HOW FAST IT ARRIVED, read before the body is freed. This is the whole
		# difference between a gift carried in and a shot from the halfway line
		# — see VillageWonder.given.
		var flew := rb.linear_velocity.length()
		var by_beast := rb.has_meta("hurled_by_creature")
		var by_god := rb.has_meta("hurled_by_god")
		if rb is FoodItem:
			var f := rb as FoodItem
			var many := maxi(f.count, 1)
			var word := "grain" if f.food_type == FoodItem.FoodType.PLANT else "meat"
			add(f.food_type, many)  # a bundle banks all its units
			rb.queue_free()
			_thank_the_giver()
			_marvel(word, many, flew, by_beast, by_god)
		elif rb is ResourceItem:
			var r := rb as ResourceItem
			var many := take_bundle(r)
			rb.queue_free()
			_thank_the_giver()
			_marvel(r.kind, many, flew, by_beast, by_god)


## THE TOWN TAKES NOTE. A storehouse is a child of its village, so it does not
## have to go looking for one — and a store standing on nobody's ground (they do
## exist, briefly, while a village is being raised) simply says nothing.
func _marvel(what: String, many: int, flew: float, by_beast: bool, by_god := false) -> void:
	var town := get_parent() as Village
	if town == null or not is_instance_valid(town):
		return
	town.wonder.given(town, what, many, flew, by_beast, by_god)


## A gift to the storehouse gladdens whoever's nearby — the villagers
## appreciate provision, whether it fell from the sky or the creature's claws.
func _thank_the_giver() -> void:
	for v in get_tree().get_nodes_in_group("villagers"):
		if v.global_position.distance_to(global_position) < 12.0:
			v.cheer(1.5)


## Grab a QUARTER of the platform and that resource pops out: grain
## (+X+Z), meat (-X+Z), lumber (-X-Z), stone (+X-Z) — you choose what to
## take by where you grab. Null (with a word) if that pile is bare.
func withdraw_at(world_point: Vector3) -> RigidBody3D:
	var local := to_local(world_point)
	var item: RigidBody3D = null
	# One grab pulls a whole armful — up to WITHDRAW_BUNDLE units at once as a
	# single carriable (no fiddly per-unit tapping on touch).
	if local.x >= 0.0 and local.z >= 0.0:
		var n := mini(plant_food, WITHDRAW_BUNDLE)
		if n > 0:
			plant_food -= n
			var f := FoodItem.new()
			f.count = n
			item = f
		else:
			GameState.announce("The grain quarter is empty.")
	elif local.x < 0.0 and local.z >= 0.0:
		var n := mini(meat_food, WITHDRAW_BUNDLE)
		if n > 0:
			meat_food -= n
			var f := FoodItem.new()
			f.food_type = FoodItem.FoodType.MEAT
			f.count = n
			item = f
		else:
			GameState.announce("The meat quarter is empty.")
	elif local.x < 0.0 and local.z < 0.0:
		var n := mini(lumber, WITHDRAW_BUNDLE)
		if n > 0:
			lumber -= n
			var r := ResourceItem.new()
			r.kind = "lumber"
			r.count = n
			item = r
		else:
			GameState.announce("The lumber quarter is empty.")
	else:
		var n := mini(stone, WITHDRAW_BUNDLE)
		if n > 0:
			stone -= n
			var r := ResourceItem.new()
			r.kind = "stone"
			r.count = n
			item = r
		else:
			GameState.announce("The stone quarter is empty.")
	if item == null:
		return null
	_show_stock()
	item.set_meta("no_deposit_until", GameState.clock + 2.5)
	get_parent().add_child(item)
	item.global_position = global_position + Vector3(0, 2.6, 0)
	return item


## Pull ONE more unit of the held bundle's own resource into it, if the pile
## has any — the "hold to keep grabbing" trickle. Returns false when the
## matching quarter is empty (or the item isn't a resource/food bundle).
func top_up(item: Node) -> bool:
	var pulled := false
	if item is FoodItem:
		var f := item as FoodItem
		# A HAND IS STILL A HAND. Drawing stock out of the store never asked
		# what would fit, so a bundle held over a full granary grew without
		# limit — which made the bundle cap a rule that only applied to the
		# piles on the grass.
		if f.count >= FoodItem.MOST_IN_A_BUNDLE or f.is_human_meat:
			return false
		if f.food_type == FoodItem.FoodType.PLANT and plant_food > 0:
			plant_food -= 1
			f.count += 1
			pulled = true
		elif f.food_type == FoodItem.FoodType.MEAT and meat_food > 0:
			meat_food -= 1
			f.count += 1
			pulled = true
		if pulled:
			f.refresh_bundle()
	elif item is ResourceItem:
		var r := item as ResourceItem
		if r.kind == "lumber" and lumber > 0:
			lumber -= 1
			r.count += 1
			pulled = true
		elif r.kind == "stone" and stone > 0:
			stone -= 1
			r.count += 1
			pulled = true
		if pulled:
			r.refresh_bundle()
	if pulled:
		item.set_meta("no_deposit_until", GameState.clock + 2.5)
		_show_stock()
	return pulled


func add(type: FoodItem.FoodType, amount: int) -> void:
	if type == FoodItem.FoodType.PLANT:
		plant_food += amount
	else:
		meat_food += amount
	_show_stock()


## Takes up to `amount` food of the given type; returns how much was taken.
func take(type: FoodItem.FoodType, amount: int) -> int:
	var taken := 0
	if type == FoodItem.FoodType.PLANT:
		taken = mini(amount, plant_food)
		plant_food -= taken
	else:
		taken = mini(amount, meat_food)
		meat_food -= taken
	_show_stock()
	return taken


func has(type: FoodItem.FoodType) -> bool:
	return plant_food > 0 if type == FoodItem.FoodType.PLANT else meat_food > 0


func total_food() -> int:
	return plant_food + meat_food


## BANK A BUNDLE, worth what it HOLDS rather than one. ResourceItem.count has
## said so since bundles existed and the platform drop has always read it — but
## the creature carrying one in by hand had its own copy of this that banked a
## flat one, so everything the beast fetched arrived worth a single unit.
## One door now, and nowhere left for a second opinion. Returns what was banked.
func take_bundle(item: ResourceItem) -> int:
	var many := maxi(item.count, 1)
	if item.kind == "lumber":
		add_lumber(many)
	else:
		add_stone(many)
	return many


func add_lumber(amount: int) -> void:
	lumber += amount
	_show_stock()


func add_stone(amount: int) -> void:
	stone += amount
	_show_stock()


## Spends lumber and stone together (for construction); false if short.
func try_spend_materials(lumber_cost: int, stone_cost: int) -> bool:
	if lumber < lumber_cost or stone < stone_cost:
		return false
	lumber -= lumber_cost
	stone -= stone_cost
	_show_stock()
	return true


## The two meshes of each quarter, placed once and never freed.
func _build_piles() -> void:
	if _palette == null:
		_bake()
	for q in QUARTERS.size():
		var at := QUARTERS[q].normalized() * PILE_FROM_MIDDLE + Vector3(0, FLOOR_TOP, 0)
		_grow.append(_place_pile(_grow_mesh[q], at))
		_heap.append(_place_pile(_heap_mesh[q], at))


func _place_pile(mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var shown := MeshInstance3D.new()
	shown.mesh = mesh
	shown.material_override = _palette
	shown.position = at
	shown.visible = false
	add_child(shown)
	return shown


## HOW FULL, SHOWN. Writes only what changed: a scale or a visibility flag,
## never a node.
func _show_stock() -> void:
	if _grow.is_empty():
		return                       # before _ready: a save loading into it
	var counts: Array[int] = [plant_food, meat_food, lumber, stone]
	for q in QUARTERS.size():
		var fill := clampf(float(counts[q]) / float(FULL), 0.0, 1.0)
		_heaped[q] = fill >= (HEAP_UNTIL if _heaped[q] else HEAP_AT)
		var growing := counts[q] > 0 and not _heaped[q]
		if _heap[q].visible != _heaped[q]:
			_heap[q].visible = _heaped[q]
		if _grow[q].visible != growing:
			_grow[q].visible = growing
		if growing:
			var size := lerpf(SMALLEST, 1.0, clampf(fill / HEAP_AT, 0.0, 1.0))
			_grow[q].scale = Vector3(size, size, size)


## The palette and all eight meshes, for every storehouse there will ever be.
static func _bake() -> void:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, GRAIN_COLOR)
	img.set_pixel(1, 0, MEAT_COLOR)
	img.set_pixel(0, 1, LUMBER_COLOR)
	img.set_pixel(1, 1, STONE_COLOR)
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = ImageTexture.create_from_image(img)
	skin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_palette = Util.lit(skin)
	_grow_mesh = _bake_grow()
	_heap_mesh = _bake_heaps()


## FILLING: a mound of grain, a few joints, a few planks, a few stones — each
## drawn at its size at HEAP_AT and scaled down from there.
static func _bake_grow() -> Array[Mesh]:
	var mound := SphereMesh.new()
	mound.radius = 1.0
	mound.height = 1.0
	mound.radial_segments = 10
	mound.rings = 4
	mound.is_hemisphere = true
	var joint := BoxMesh.new()
	joint.size = Vector3(0.45, 0.4, 0.45)
	var plank := BoxMesh.new()
	plank.size = Vector3(1.5, 0.18, 0.32)
	var lump := SphereMesh.new()
	lump.radius = 0.36
	lump.height = 0.5
	lump.radial_segments = 6
	lump.rings = 3
	var out: Array[Mesh] = []
	out.append(_weld([[mound, _at(Vector3.ZERO, Vector3(1.0, 0.8, 1.0))]], 0))
	out.append(_weld([[joint, _at(Vector3(-0.3, 0.2, 0.2))], [joint, _at(Vector3(0.3, 0.2, -0.1))],
		[joint, _at(Vector3(0.0, 0.6, 0.05))]], 1))
	out.append(_weld([[plank, _at(Vector3(0, 0.09, -0.36))], [plank, _at(Vector3(0, 0.09, 0.0))],
		[plank, _at(Vector3(0, 0.09, 0.36))]], 2))
	out.append(_weld([[lump, _at(Vector3(-0.35, 0.2, 0.15))], [lump, _at(Vector3(0.35, 0.2, 0.1))],
		[lump, _at(Vector3(0.0, 0.5, -0.1))]], 3))
	return out


## ALL THE WAY HEAPED: one static mesh a quarter, drawn from HEAP_AT up.
static func _bake_heaps() -> Array[Mesh]:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 1.25
	cone.height = 1.5
	cone.radial_segments = 10
	cone.rings = 0
	var sack := SphereMesh.new()
	sack.radius = 0.3
	sack.height = 0.6
	sack.radial_segments = 8
	sack.rings = 4
	var joint := BoxMesh.new()
	joint.size = Vector3(0.45, 0.4, 0.45)
	var plank := BoxMesh.new()
	plank.size = Vector3(1.5, 0.18, 0.32)
	var lump := SphereMesh.new()
	lump.radius = 0.36
	lump.height = 0.5
	lump.radial_segments = 6
	lump.rings = 3
	var grain: Array = [[cone, _at(Vector3(0, 0.75, 0))]]
	for a: float in [0.4, 2.5, 4.4]:
		grain.append([sack, _at(Vector3(cos(a), 0.3, sin(a)) * Vector3(1.1, 1.0, 1.1))])
	var meat: Array = []
	var cairn: Array = []
	for spot: Vector3 in [Vector3(-0.3, 0, -0.3), Vector3(0.3, 0, -0.3), Vector3(-0.3, 0, 0.3),
			Vector3(0.3, 0, 0.3), Vector3(0, 0.4, -0.15), Vector3(0, 0.4, 0.25), Vector3(0.05, 0.8, 0)]:
		meat.append([joint, _at(spot * Vector3(1.4, 1.0, 1.4) + Vector3(0, 0.2, 0))])
		cairn.append([lump, _at(spot * Vector3(1.8, 0.85, 1.8) + Vector3(0, 0.2, 0))])
	var stack: Array = []
	for layer in 4:
		for row in 3:
			var across := Vector3(0, 0.09 + layer * 0.18, (row - 1) * 0.4)
			var turn := PI * 0.5 * float(layer % 2)
			stack.append([plank, Transform3D(Basis(Vector3.UP, turn), Basis(Vector3.UP, turn) * across)])
	var out: Array[Mesh] = []
	out.append(_weld(grain, 0))
	out.append(_weld(meat, 1))
	out.append(_weld(stack, 2))
	out.append(_weld(cairn, 3))
	return out


static func _at(pos: Vector3, stretch := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_scale(stretch), pos)


## WELD PARTS INTO ONE MESH, every vertex's UV pinned to the centre of palette
## cell `cell` (0 grain, 1 meat, 2 lumber, 3 stone). One draw, one material.
static func _weld(parts: Array, cell: int) -> ArrayMesh:
	var uv := Vector2(float(cell % 2) * 0.5 + 0.25, float(cell >> 1) * 0.5 + 0.25)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	for part: Array in parts:
		var arrays := (part[0] as Mesh).surface_get_arrays(0)
		var place: Transform3D = part[1]
		var bend := place.basis.inverse().transposed()
		var base := verts.size()
		var their: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v: Vector3 in their:
			verts.append(place * v)
			uvs.append(uv)
		var their_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for n: Vector3 in their_normals:
			norms.append((bend * n).normalized())
		var order = arrays[Mesh.ARRAY_INDEX]
		if order == null:
			for i in their.size():
				index.append(base + i)
		else:
			var their_order: PackedInt32Array = order
			for i: int in their_order:
				index.append(base + i)
	var welded := []
	welded.resize(Mesh.ARRAY_MAX)
	welded[Mesh.ARRAY_VERTEX] = verts
	welded[Mesh.ARRAY_NORMAL] = norms
	welded[Mesh.ARRAY_TEX_UV] = uvs
	welded[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, welded)
	return mesh


func hover_text() -> String:
	return ("Storehouse — %d plants · %d meat · %d lumber · %d stone\n" +
		"(grab a quarter to take from that pile)") \
		% [plant_food, meat_food, lumber, stone]

## Fire ------------------------------------------------------------------------

## HEAT ON IT, from a fireball, a bolt, or the building next door. It catches
## only when it has had enough of it for what it is made of — see
## Kindling.warm, and Kindling's TEMPER_ table for why a granary takes longer
## than a hut.
func scorch(joules: float) -> void:
	kindling.warm(self, joules, 3.2)


## SET IT ALIGHT. Everything a village raises can burn now — see Kindling for
## why that had to change and what it costs a town.
func ignite() -> void:
	kindling.light(self, 3.2)


## Rain, a healing shower, or somebody with a bucket.
func extinguish() -> void:
	kindling.douse(self)


## Sudden harm — a fireball's core, a quake, a creature's boot.

## WHAT IT IS WORTH IN FULL, so a blow can be reckoned as a share of it. A
## METHOD and not the constant itself: Object.get() does not see constants, so
## anything asking `built.get("MOST_HEALTH")` gets null and quietly treats a
## granary as a hut. See Fireball._most_of.
func full_health() -> float:
	return MOST_HEALTH


func damage(amount: float) -> void:
	health -= amount
	# AND IT SHOWS. See RuinBar: a thing that can be hurt without looking
	# hurt is indistinguishable from a thing that cannot be hurt at all,
	# which is exactly what "the mill will not burn" sounds like from
	# the other side of the screen.
	RuinBar.over(self, health / MOST_HEALTH, 4.0, kindling.alight)
	if health <= 0.0:
		burn_down()


func _tick_fire(delta: float) -> void:
	# COOL OFF between blows: three fireballs in ten seconds is a fire,
	# three across an afternoon is three scorch marks. See Kindling.
	kindling.cool(delta)
	var harm := kindling.smoulder(self, delta, MOST_HEALTH)
	if harm > 0.0:
		damage(harm)


## A GRANARY ON FIRE IS THE HARVEST ON FIRE. What is in it goes with it, which
## is the whole reason burning one is a thing worth doing and a thing worth
## preventing.
func burn_down() -> void:
	plant_food = 0
	meat_food = 0
	lumber = 0
	stone = 0
	GameState.announce("The storehouse burns. A season's harvest with it.")
	health = MOST_HEALTH    # the frame stands; the stores are what was lost
	kindling.douse(self)
