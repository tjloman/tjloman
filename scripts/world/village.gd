class_name Village
extends Node3D
## A settlement: totem, storehouse, farm, pen, real House nodes, and its
## people. Owns belief, the sphere of influence, the diet policy, and the
## village's collective morality.
##
## Villages other than the player's home spawn NEUTRAL: they run the whole
## simulation — farming, building, breeding — but believe in nothing and
## generate no prayer until your miracles convert them (belief >= 40).

enum Diet { VEGAN, OMNIVORE, CARNIVORE, CANNIBAL }

const CONVERT_BELIEF := 40.0
const BELIEF_DECAY_PER_SEC := 0.02
const WORSHIP_PRAYER_PER_SEC := 1.5
const WORSHIP_BELIEF_PER_SEC := 0.05
const MIN_INFLUENCE := 14.0
const MAX_INFLUENCE := 65.0
const MAX_TAMED := 8

var village_name := "Elsmere"
var is_player_home := true
var converted := false
var belief := 0.0
var influence_radius := MIN_INFLUENCE
var diet := Diet.OMNIVORE

var totem: Node3D
var farm: Farm
var store: FoodStore
var houses: Array[House] = []
var construction_site: House = null
var tamed_animals: Array[Animal] = []

var _totem_orb: MeshInstance3D
var _influence_ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _pen_center := Vector3(0, 0, -11)
var _housing_timer := 0.0
var _breed_timer := 30.0


func _ready() -> void:
	add_to_group("village")
	if is_player_home:
		converted = true
		belief = 25.0

	_build_totem()
	_build_pen()

	farm = Farm.new()
	farm.position = Vector3(9, 0, -4)
	add_child(farm)

	store = FoodStore.new()
	store.position = Vector3(-3, 0, 5)
	add_child(store)

	_build_influence_ring()
	_build_starting_houses()
	_spawn_villagers(12 if is_player_home else 8)
	_update_influence()
	GameState.alignment_changed.connect(_on_alignment_changed)


func _build_totem() -> void:
	totem = Node3D.new()
	totem.name = "Totem"
	totem.add_child(Util.cylinder(0.45, 4.0, Color(0.55, 0.4, 0.25), Vector3(0, 2, 0)))
	_totem_orb = Util.sphere(0.6, Color(1.0, 0.85, 0.3), Vector3(0, 4.4, 0), converted)
	if not converted:
		_totem_orb.material_override = Util.mat(Color(0.5, 0.5, 0.5))
	totem.add_child(_totem_orb)
	add_child(totem)


func _build_pen() -> void:
	var pen := Node3D.new()
	pen.position = _pen_center
	for i in 8:
		var angle := TAU * i / 8.0
		var post_pos := Vector3(cos(angle) * 4.0, 0.5, sin(angle) * 4.0)
		pen.add_child(Util.box(Vector3(0.15, 1.0, 0.15), Color(0.5, 0.38, 0.25), post_pos))
		var rail := Util.box(Vector3(0.08, 0.08, 3.1), Color(0.55, 0.42, 0.28),
			(post_pos + Vector3(cos(angle + TAU / 8.0) * 4.0, 0.5, sin(angle + TAU / 8.0) * 4.0)) / 2.0 \
			+ Vector3(0, 0.25, 0))
		rail.look_at_from_position(rail.position,
			pen.to_local(pen.to_global(post_pos)), Vector3.UP)
		pen.add_child(rail)
	add_child(pen)


func pen_position() -> Vector3:
	return global_position + _pen_center


func _build_influence_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.97
	torus.outer_radius = 1.0
	_ring_material = Util.mat(Color(1.0, 0.95, 0.7, 0.6), true)
	_influence_ring = MeshInstance3D.new()
	_influence_ring.mesh = torus
	_influence_ring.material_override = _ring_material
	_influence_ring.position = Vector3(0, 0.3, 0)
	_influence_ring.visible = converted
	add_child(_influence_ring)


func _build_starting_houses() -> void:
	var sizes: Array = [House.Size.HUT, House.Size.HUT, House.Size.HOUSE] \
		if is_player_home else [House.Size.HUT, House.Size.HUT]
	for i in sizes.size():
		var angle := TAU * i / 6.0 + 0.4
		var house := House.new()
		house.size = sizes[i]
		house.village = self
		house.age = randf_range(5.0, 20.0)
		house.position = Vector3(cos(angle) * 7.5, 0, sin(angle) * 7.5)
		house.look_at_from_position(house.position, Vector3.ZERO, Vector3.UP)
		add_child(house)
		houses.append(house)


func _spawn_villagers(count: int) -> void:
	for i in count:
		var v := _make_villager(randf_range(16.0, 45.0))
		v.position = Vector3(randf_range(-5, 5), 1.0, randf_range(-5, 5))
		add_child(v)
	_assign_housing()


func _make_villager(start_age: float) -> Villager:
	var v := Villager.new()
	v.village = self
	v.age = start_age
	return v


func spawn_child(pos: Vector3) -> void:
	var v := _make_villager(0.0)
	v.position = to_local(pos) + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))
	add_child(v)
	_assign_housing()


func _process(delta: float) -> void:
	var worshippers := 0
	for v in my_villagers():
		if v.is_worshipping():
			worshippers += 1
	if worshippers > 0:
		if converted:
			var conviction := lerpf(0.75, 1.25, (average_morality() + 100.0) / 200.0)
			GameState.add_prayer_power(worshippers * WORSHIP_PRAYER_PER_SEC * conviction * delta)
			change_belief(worshippers * WORSHIP_BELIEF_PER_SEC * delta)
	change_belief(-BELIEF_DECAY_PER_SEC * delta)

	_housing_timer -= delta
	if _housing_timer <= 0.0:
		_housing_timer = 4.0
		_assign_housing()

	_breed_timer -= delta
	if _breed_timer <= 0.0:
		_breed_timer = 50.0
		_breed_livestock()


func my_villagers() -> Array[Villager]:
	var result: Array[Villager] = []
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if is_instance_valid(villager) and villager.village == self:
			result.append(villager)
	return result


func population() -> int:
	return my_villagers().size()


func average_morality() -> float:
	var villagers := my_villagers()
	if villagers.is_empty():
		return 0.0
	var total := 0.0
	for v in villagers:
		total += v.morality
	return total / villagers.size()


## A village that has fallen far enough gives up the plough entirely.
func agriculture_abandoned() -> bool:
	return diet == Diet.CANNIBAL or average_morality() < -40.0


## Belief & conversion --------------------------------------------------------

func change_belief(amount: float) -> void:
	belief = clampf(belief + amount, 0.0, 100.0)
	if not converted and belief >= CONVERT_BELIEF:
		_convert()
	_update_influence()


func _convert() -> void:
	converted = true
	_influence_ring.visible = true
	_totem_orb.material_override = Util.mat(Color(1.0, 0.85, 0.3), true)
	GameState.announce("%s BELIEVES! Their prayers now feed your power." % village_name)
	GameState.shift_alignment(1.0)


func _update_influence() -> void:
	influence_radius = lerpf(MIN_INFLUENCE, MAX_INFLUENCE, belief / 100.0)
	if _influence_ring != null:
		_influence_ring.scale = Vector3(influence_radius, 1.0, influence_radius)
	if is_player_home:
		GameState.set_max_prayer_power(100.0 + belief * 2.0)


func _on_alignment_changed(_value: float) -> void:
	var c := GameState.alignment_color()
	_ring_material.albedo_color = Color(c.r, c.g, c.b, 0.6)
	_ring_material.emission = c


func is_inside_influence(point: Vector3) -> bool:
	var flat := point
	flat.y = 0
	var here := global_position
	here.y = 0
	return flat.distance_to(here) <= influence_radius


## Housing --------------------------------------------------------------------

func housing_capacity() -> int:
	var total := 0
	for h in houses:
		if is_instance_valid(h):
			total += h.capacity()
	return total


func homeless_count() -> int:
	var homeless := 0
	for v in my_villagers():
		if v.home == null:
			homeless += 1
	return homeless


## Greedy re-assignment: fill houses in order; the leftover sleep rough.
func _assign_housing() -> void:
	houses = houses.filter(func(h): return is_instance_valid(h))
	var villagers := my_villagers()
	var slots := []
	for h in houses:
		for i in h.capacity():
			slots.append(h)
	for i in villagers.size():
		villagers[i].home = slots[i] if i < slots.size() else null


func on_house_completed(house: House) -> void:
	if construction_site == house:
		construction_site = null
	GameState.announce("A new %s stands in %s." % [house.size_name().to_lower(), village_name])
	_assign_housing()


func on_house_destroyed(house: House) -> void:
	houses.erase(house)
	if construction_site == house:
		construction_site = null
	_assign_housing()


## Picks a build spot with clearance from other structures, dry and flat.
func find_build_spot(world: WorldGen) -> Vector3:
	for attempt in 20:
		var angle := randf() * TAU
		var dist := randf_range(6.5, maxf(influence_radius * 0.8, 12.0))
		var pos := global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		if world != null:
			if world.is_underwater(pos.x, pos.z) or world.slope_at(pos.x, pos.z) > 0.9:
				continue
			pos.y = world.height_at(pos.x, pos.z)
		var blocked := false
		for h in houses:
			if is_instance_valid(h) and h.global_position.distance_to(pos) < 4.5:
				blocked = true
				break
		for structure: Node3D in [totem, farm, store]:
			if structure.global_position.distance_to(pos) < 6.0:
				blocked = true
				break
		if pen_position().distance_to(pos) < 6.0:
			blocked = true
		if not blocked:
			return pos
	return Vector3.INF


## What the next house should be, sized to the homelessness problem.
func next_house_size() -> House.Size:
	var homeless := homeless_count()
	if homeless >= 5:
		return House.Size.LONGHOUSE
	if homeless >= 3:
		return House.Size.HOUSE
	return House.Size.HUT


## Starts construction (pays materials). Returns the site, or null if broke.
func start_construction(world: WorldGen) -> House:
	if construction_site != null:
		return construction_site
	var size := next_house_size()
	var spec: Dictionary = House.SPECS[size]
	if not store.try_spend_materials(spec["lumber"], spec["stone"]):
		return null
	var spot := find_build_spot(world)
	if spot == Vector3.INF:
		store.add_lumber(spec["lumber"])
		store.add_stone(spec["stone"])
		return null
	var house := House.new()
	house.size = size
	house.village = self
	house.under_construction = true
	house.position = to_local(spot)
	add_child(house)
	houses.append(house)
	construction_site = house
	return house


## Livestock ------------------------------------------------------------------

func on_tamed_gained(animal: Animal) -> void:
	tamed_animals.append(animal)


func on_tamed_lost(animal: Animal) -> void:
	tamed_animals.erase(animal)


func tamed_count() -> int:
	tamed_animals = tamed_animals.filter(func(a): return is_instance_valid(a))
	return tamed_animals.size()


func has_guard_dog() -> bool:
	for a in tamed_animals:
		if is_instance_valid(a) and a.species == "dog":
			return true
	return false


func idle_mount() -> Animal:
	for a in tamed_animals:
		if is_instance_valid(a) and a.spec.get("ride", false) and not a.has_rider():
			return a
	return null


func has_pack_animal() -> bool:
	for a in tamed_animals:
		if is_instance_valid(a) and a.spec.get("pack", false):
			return true
	return false


## The fattest penned animal, for the darker sort of village.
func best_penned_meat() -> Animal:
	var best: Animal = null
	for a in tamed_animals:
		if is_instance_valid(a) and a.meat_yield() > 0:
			if best == null or a.meat_yield() > best.meat_yield():
				best = a
	return best


## Penned livestock multiplies slowly.
func _breed_livestock() -> void:
	tamed_animals = tamed_animals.filter(func(a): return is_instance_valid(a))
	if tamed_animals.size() < 2 or tamed_animals.size() >= MAX_TAMED:
		return
	var by_species := {}
	for a in tamed_animals:
		by_species[a.species] = by_species.get(a.species, 0) + 1
	for species: String in by_species:
		if by_species[species] >= 2:
			var baby := Animal.create(species)
			baby.position = to_local(pen_position()) + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2))
			add_child(baby)
			baby.tame(self)
			return


## Diet policy ----------------------------------------------------------------

func set_diet(new_diet: Diet) -> void:
	if new_diet == diet:
		return
	diet = new_diet
	match diet:
		Diet.VEGAN:
			GameState.shift_alignment(2.0)
			GameState.announce("%s embraces the gentle path. No flesh shall be eaten." % village_name)
		Diet.OMNIVORE:
			GameState.announce("%s will eat what the land provides." % village_name)
		Diet.CARNIVORE:
			GameState.shift_alignment(-2.0)
			GameState.announce("%s turns to meat alone. The animals grow nervous." % village_name)
		Diet.CANNIBAL:
			GameState.shift_alignment(-12.0)
			GameState.announce("The unthinkable is law in %s: the dead shall feed the living." % village_name)
			for v in my_villagers():
				v.witness_horror(10.0)


func diet_name() -> String:
	return ["Vegan", "Omnivore", "Carnivore", "Cannibal"][diet]


func allowed_food_types() -> Array[FoodItem.FoodType]:
	match diet:
		Diet.VEGAN:
			return [FoodItem.FoodType.PLANT]
		Diet.CARNIVORE, Diet.CANNIBAL:
			return [FoodItem.FoodType.MEAT]
		_:
			return [FoodItem.FoodType.PLANT, FoodItem.FoodType.MEAT]


## Miracles -------------------------------------------------------------------

func witness_miracle(type: String, pos: Vector3) -> void:
	var flat := pos
	flat.y = 0
	var here := global_position
	here.y = 0
	if flat.distance_to(here) > maxf(influence_radius * 1.3, 25.0):
		return
	match type:
		"food":
			change_belief(6.0)
			GameState.announce("%s marvels at food from the heavens. Belief grows." % village_name)
		"rain":
			change_belief(4.0)
			GameState.announce("Blessed rain over %s! The crops rejoice." % village_name)
		"heal":
			change_belief(5.0)
			GameState.announce("Vitality flows through %s. They whisper your name." % village_name)
		"lightning":
			change_belief(8.0)
			GameState.announce("%s cowers before your wrath. Fear, too, is belief." % village_name)
			for v in my_villagers():
				var dist := v.global_position.distance_to(pos)
				if dist < 15.0:
					v.witness_horror(3.0)
				if dist < 14.0:
					v.scare(pos)
		"fireball":
			change_belief(7.0)
			GameState.announce("Fire from the sky over %s! They kneel in the ash." % village_name)
			for v in my_villagers():
				var dist := v.global_position.distance_to(pos)
				if dist < 16.0:
					v.witness_horror(2.5)
					v.scare(pos)


func hover_text() -> String:
	return "%s — %s" % [village_name,
		"faithful" if converted else "unbelieving (belief %d/%d)" % [int(belief), int(CONVERT_BELIEF)]]
