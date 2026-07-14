class_name Village
extends Node3D
## A settlement: houses, totem, farm, food store, and its people.
## Owns the belief value and the visible sphere of influence.
##
## Belief economy (PoC numbers, all tunable at the top):
##  - Witnessed miracles raise belief (lightning raises it through fear,
##    at a happiness cost).
##  - Worshippers at the totem generate prayer power and a trickle of belief.
##  - Belief decays very slowly, and sets the influence radius and the
##    player's maximum prayer power.

const HOUSE_COUNT := 6
const VILLAGER_COUNT := 12
const BELIEF_DECAY_PER_SEC := 0.02
const WORSHIP_PRAYER_PER_SEC := 1.5
const WORSHIP_BELIEF_PER_SEC := 0.05
const MIN_INFLUENCE := 14.0
const MAX_INFLUENCE := 65.0

var belief := 25.0
var influence_radius := MIN_INFLUENCE

var totem: Node3D
var farm: Farm
var store: FoodStore
var houses: Array[Node3D] = []

var _influence_ring: MeshInstance3D


func _ready() -> void:
	add_to_group("village")
	_build_totem()
	_build_houses()

	farm = Farm.new()
	farm.position = Vector3(9, 0, -4)
	add_child(farm)

	store = FoodStore.new()
	store.position = Vector3(-3, 0, 5)
	add_child(store)

	_build_influence_ring()
	_spawn_villagers()
	_update_influence()


func _build_totem() -> void:
	totem = Node3D.new()
	totem.name = "Totem"
	totem.add_child(Util.cylinder(0.45, 4.0, Color(0.55, 0.4, 0.25), Vector3(0, 2, 0)))
	totem.add_child(Util.sphere(0.6, Color(1.0, 0.85, 0.3), Vector3(0, 4.4, 0), true))
	add_child(totem)


func _build_houses() -> void:
	for i in HOUSE_COUNT:
		var angle := TAU * i / HOUSE_COUNT + 0.3
		var pos := Vector3(cos(angle) * 7.0, 0, sin(angle) * 7.0)
		var house := Node3D.new()
		house.name = "House%d" % i
		house.position = pos
		house.add_child(Util.box(Vector3(2.2, 1.8, 2.2), Color(0.75, 0.65, 0.5), Vector3(0, 0.9, 0)))
		var roof := Util.prism(Vector3(2.6, 1.2, 2.6), Color(0.6, 0.25, 0.2), Vector3(0, 2.4, 0))
		house.add_child(roof)
		house.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)
		add_child(house)
		houses.append(house)


func _build_influence_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.97
	torus.outer_radius = 1.0
	_influence_ring = Util.mesh_node(torus, Color(1.0, 0.95, 0.7, 0.6), Vector3(0, 0.15, 0), true)
	add_child(_influence_ring)


func _spawn_villagers() -> void:
	for i in VILLAGER_COUNT:
		var v := Villager.new()
		v.village = self
		var home := houses[i % houses.size()]
		v.home_position = home.position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		v.position = v.home_position + Vector3(randf_range(-3, 3), 1.0, randf_range(-3, 3))
		add_child(v)


func _process(delta: float) -> void:
	var worshippers := 0
	for v in get_tree().get_nodes_in_group("villagers"):
		if (v as Villager).is_worshipping():
			worshippers += 1
	if worshippers > 0:
		GameState.add_prayer_power(worshippers * WORSHIP_PRAYER_PER_SEC * delta)
		change_belief(worshippers * WORSHIP_BELIEF_PER_SEC * delta)

	change_belief(-BELIEF_DECAY_PER_SEC * delta)


func change_belief(amount: float) -> void:
	belief = clampf(belief + amount, 0.0, 100.0)
	_update_influence()


func _update_influence() -> void:
	influence_radius = lerpf(MIN_INFLUENCE, MAX_INFLUENCE, belief / 100.0)
	if _influence_ring != null:
		_influence_ring.scale = Vector3(influence_radius, 1.0, influence_radius)
	GameState.set_max_prayer_power(100.0 + belief * 2.0)


func is_inside_influence(point: Vector3) -> bool:
	var flat := point
	flat.y = 0
	return flat.distance_to(global_position) <= influence_radius


## Called by MiracleManager when a miracle lands. Villagers who can plausibly
## see it (inside ~1.3x influence) adjust their faith.
func witness_miracle(type: String, pos: Vector3) -> void:
	var flat := pos
	flat.y = 0
	if flat.distance_to(global_position) > influence_radius * 1.3:
		GameState.announce("A miracle unseen converts no one.")
		return
	match type:
		"food":
			change_belief(6.0)
			GameState.announce("The villagers marvel at food from the heavens. Belief grows.")
		"rain":
			change_belief(4.0)
			GameState.announce("Blessed rain! The crops rejoice, and so do the people.")
		"heal":
			change_belief(5.0)
			GameState.announce("Vitality flows through the village. They whisper your name in thanks.")
		"lightning":
			change_belief(8.0)
			GameState.announce("The people cower before your wrath. Fear, too, is belief.")
			for v in get_tree().get_nodes_in_group("villagers"):
				var villager := v as Villager
				if villager.global_position.distance_to(pos) < 14.0:
					villager.scare(pos)
