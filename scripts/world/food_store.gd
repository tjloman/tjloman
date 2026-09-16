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
const MAX_SHOWN := 12  # per resource; hover for exact counts
const WITHDRAW_BUNDLE := 10  # units pulled per grab (a whole armful)

const GRAIN_COLOR := Color(0.9, 0.6, 0.2)
const MEAT_COLOR := Color(0.72, 0.22, 0.18)
const LUMBER_COLOR := Color(0.55, 0.4, 0.25)
const STONE_COLOR := Color(0.55, 0.54, 0.56)


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

var plant_food := 14
var meat_food := 0
var lumber := 6
var stone := 3
## How much of it is left, and whether it is alight. See Kindling.
var health := MOST_HEALTH
var kindling := Kindling.new()

var _stack: Array[MeshInstance3D] = []
var _intake: Area3D
var _intake_time := 0.5

func _ready() -> void:
	kindling.temper = Kindling.TEMPER_STORES   # timber, but packed and damp inside
	add_to_group("stores")
	add_to_group(Affords.BURNABLE)
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
		add_child(custom)
	else:
		_build_structure()

	_refresh_stack()


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
	_refresh_stack()
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
		_refresh_stack()
	return pulled


func add(type: FoodItem.FoodType, amount: int) -> void:
	if type == FoodItem.FoodType.PLANT:
		plant_food += amount
	else:
		meat_food += amount
	_refresh_stack()


## Takes up to `amount` food of the given type; returns how much was taken.
func take(type: FoodItem.FoodType, amount: int) -> int:
	var taken := 0
	if type == FoodItem.FoodType.PLANT:
		taken = mini(amount, plant_food)
		plant_food -= taken
	else:
		taken = mini(amount, meat_food)
		meat_food -= taken
	_refresh_stack()
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
	_refresh_stack()


func add_stone(amount: int) -> void:
	stone += amount
	_refresh_stack()


## Spends lumber and stone together (for construction); false if short.
func try_spend_materials(lumber_cost: int, stone_cost: int) -> bool:
	if lumber < lumber_cost or stone < stone_cost:
		return false
	lumber -= lumber_cost
	stone -= stone_cost
	_refresh_stack()
	return true


## A spot inside a quadrant for the i-th item of a pile (4 per layer).
func _pile_spot(dir: Vector3, i: int) -> Vector3:
	var layer := floorf(i / 4.0)
	return Vector3(
		randf_range(0.7, PLATFORM_RADIUS - 0.9) * dir.x,
		0.5 + layer * 0.34,
		randf_range(0.7, PLATFORM_RADIUS - 0.9) * dir.z)


func _refresh_stack() -> void:
	for m in _stack:
		m.queue_free()
	_stack.clear()
	for i in mini(plant_food, MAX_SHOWN):
		_show(Util.sphere(0.22, GRAIN_COLOR, _pile_spot(Vector3(1, 0, 1), i)))
	for i in mini(meat_food, MAX_SHOWN):
		_show(Util.box(Vector3(0.3, 0.3, 0.3), MEAT_COLOR, _pile_spot(Vector3(-1, 0, 1), i)))
	for i in mini(lumber, MAX_SHOWN):
		var plank := Util.box(Vector3(1.1, 0.16, 0.3), LUMBER_COLOR,
			_pile_spot(Vector3(-1, 0, -1), i))
		plank.rotation_degrees.y = randf_range(-15, 15)
		_show(plank)
	for i in mini(stone, MAX_SHOWN):
		_show(Util.box(Vector3(0.35, 0.3, 0.35), STONE_COLOR, _pile_spot(Vector3(1, 0, -1), i)))


func _show(m: MeshInstance3D) -> void:
	add_child(m)
	_stack.append(m)


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
