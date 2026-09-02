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
const PRAYER_PER_VILLAGE := 120.0   # each convert widens your prayer reservoir
const FARM_HALF := 3.9              # a field's clearance radius (no overlaps)

## THE ALARM: when one of them is attacked, the whole village drops its work
## and takes up arms for a while. Grudge is how much they blame the CREATURE
## for their blood — once it passes GRUDGE_HOSTILE they will fight it too.
## The miracles the crowd mind reads as a terror rather than a blessing.
const TERRORS := [
	"lightning", "fireball", "thunderclap", "lightning_storm", "tornado",
	"thunderstorm", "tempest", "firestorm", "hurricane",
]
## TORCHES. Anyone still out after dark carries one, and they are the reason a
## village reads as inhabited at night rather than as a field of dark boxes.
##
## They are NOT lights. There may be a thousand villagers, and a thousand point
## lights is not a thing a phone will do — the real light after dark is a small
## pool that follows the camera (Nightfall) plus the creature's own glow. These
## are flames: emissive billboards, all of a town's in ONE MultiMesh and so one
## draw call, updated on a lazy clock and only while the town is near enough to
## see. What they cost is a couple of dozen matrices a second.
const TORCH_RANGE := 90.0        # past this a town's torches stop drawing at all
const TORCH_REFRESH := 0.4       # how often the flames are re-dealt to people
const TORCH_FLICKER := 1.0 / 15.0
const TORCH_MOST := 24           # the most flames one town ever draws
const TORCH_COLOR := Color(1.0, 0.68, 0.28)
const TORCH_SIZE := Vector2(0.28, 0.42)

const ALARM_SECONDS := 45.0
const GRUDGE_HOSTILE := 35.0
const GRUDGE_DECAY := 0.4          # per second: fear of the beast fades slowly

## RESOLVE — what this village has LEARNED about facing danger. Standing and
## winning stiffens them; burying their dead teaches them to hide instead. So
## one village becomes a militia and another a people who bar their doors, out
## of their own history rather than a rule.
const RESOLVE_START := 50.0
const RESOLVE_WIN := 14.0     # a beast killed, a monster driven off
const RESOLVE_LOSS := 22.0    # one of ours died fighting
const RESOLVE_FIGHT := 35.0   # below this they hide rather than fight

## A village LEFT ALONE barely grows. Divine attention — your miracles, your
## hand, your creature's work among them — is what quickens a people: it lifts
## their spirits, and children follow. Attention fades if you wander off, so a
## kingdom expands where you actually tend it rather than everywhere at once.
const ATTENTION_DECAY := 0.5       # per second (a miracle's notice lasts ~a minute)
## CONCEPTION, given that a couple have actually MET at the totem. This used to
## be a per-second lottery that ran whether or not anyone was there, at odds so
## long that a couple courting for a full eight seconds conceived about six
## times in a hundred. Simulated over a night, that killed every village in
## twenty-four runs out of twenty-four: a lifetime here is ~3.6 real hours, so
## an unattended run turns over two whole generations, and the flock could not
## replace itself even once. What limits growth is now how often they COURT
## (see Villager._breed_cooldown) — which is what divine attention speeds up —
## rather than a coin that almost never lands.
const BREED_BASE := 0.45           # per second WHILE a partner is present
const BREED_ATTENTION_GAIN := 50.0  # attention needed to double that

## Hand-placed founding homes, clear of the farm (E), store (NW), and pen (S).
const STARTER_HOUSE_SPOTS: Array[Vector3] = [
	Vector3(5, 0, 9), Vector3(-4.5, 0, 10), Vector3(10.5, 0, 5),
]

var village_name := "Elsmere"
var is_player_home := true
var converted := false
var belief := 0.0
var influence_radius := MIN_INFLUENCE
var diet := Diet.OMNIVORE

var totem: Node3D
var farm: Farm                 # the founding field (always farms[0])
var farms: Array[Farm] = []
var store: FoodStore
var houses: Array[House] = []
var construction_site: House = null
var tamed_animals: Array[Animal] = []
var edubba: Edubba = null      # the schoolhouse, once built
var teacher: Villager = null   # the one adult who minds the school

## Militia state. `alarm` counts down while the village is roused; `threat_pos`
## is where the trouble was last seen; `grudge` is their anger at the creature.
var alarm := 0.0
var threat_pos := Vector3.INF
var grudge := 0.0
## Beasts marked for death. When one of ours is killed, its killer goes on this
## list and the whole village hunts THAT animal until it is dead.
var vendetta: Array[Animal] = []
## 0..100 — how much divine notice this village has had lately.
## THE CROWD MIND. The town thinks once, a couple of times a second, and every
## villager reads the result instead of working it out for themselves — which
## is what makes a settlement of hundreds affordable. See VillageHive.
var hive := VillageHive.new()
var attention := 0.0
## 0..100 — hard-won nerve. See RESOLVE_* above.
var resolve := RESOLVE_START

var _totem_orb: MeshInstance3D
var _influence_ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _pen_center := Vector3(0, 0, -11)
var _housing_timer := 0.0
var _sim_skip := 0                  # frames skipped while far from the camera
var _breed_timer := 30.0
## Population, sampled now and then. A village dying of demographics dies
## SILENTLY — the flock thins over hours and nothing announces it — so the
## roster reads the trend out loud instead of leaving you to find the bodies.
var _pop_samples: Array = []
var _pop_timer := 20.0
var _torches: MultiMeshInstance3D = null   # built the first night it is watched
var _torch_timer := 0.0
var _torch_age := 0.0
var _flicker_beat := 0.0


func _ready() -> void:
	add_to_group("village")
	if is_player_home:
		converted = true
		belief = 25.0

	_build_totem()
	_build_pen()

	# The round market sits well clear of the house ring to the northwest.
	store = FoodStore.new()
	store.position = _grounded(Vector3(-9, 0, 6), 3.5)
	add_child(store)
	if is_player_home:
		store.plant_food += 8  # a founding surplus, so the game starts kind

	# The founding field is placed AFTER the store so its clearance check reads
	# the store's final spot — no field ends up buried under the market floor.
	farm = Farm.new()
	farm.position = _farm_position(Vector3(10, 0, -4))
	add_child(farm)
	farms.append(farm)

	_build_influence_ring()
	_build_starting_houses()
	_spawn_villagers(12 if is_player_home else 8)
	_update_influence()
	GameState.alignment_changed.connect(_on_alignment_changed)
	# If a saved game remembers a town that stood here, this IS that town —
	# take back its name, its faith, its stocks and its people.
	SaveGame.recall(self)


func _build_totem() -> void:
	totem = Node3D.new()
	totem.name = "Totem"
	totem.add_child(Util.cylinder(0.45, 4.0, Color(0.55, 0.4, 0.25), Vector3(0, 2, 0)))
	_totem_orb = Util.sphere(0.6, Color(1.0, 0.85, 0.3), Vector3(0, 4.4, 0), converted)
	if not converted:
		_totem_orb.material_override = Util.mat(Color(0.5, 0.5, 0.5))
	totem.add_child(_totem_orb)
	add_child(totem)


## Converts a flat village-local offset into one that settles on the HIGH
## side of the terrain under the structure's footprint — nothing buried
## uphill, foundations bridging downhill. `half` is the footprint half-width.
func _grounded(local: Vector3, half := 2.5) -> Vector3:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return local
	# Keep foundations out of the water: if the requested footprint is wet,
	# spiral outward for the nearest dry spot before settling the height.
	if not world.footprint_dry(global_position.x + local.x, global_position.z + local.z, half):
		local = _nearest_dry_local(world, local, half)
	local.y = world.settle_height(
		global_position.x + local.x, global_position.z + local.z, half) - global_position.y
	return local


## Spirals out from a wet offset to the nearest dry footprint (keeping the
## structure near where it was meant to go). Falls back to the original.
func _nearest_dry_local(world: WorldGen, local: Vector3, half: float) -> Vector3:
	for ring in range(1, 7):
		var r := ring * 2.0
		for i in 8:
			var a := TAU * i / 8.0
			var cand := local + Vector3(cos(a) * r, 0, sin(a) * r)
			if world.footprint_dry(global_position.x + cand.x, global_position.z + cand.z, half):
				return cand
	return local


func _build_pen() -> void:
	var pen := Node3D.new()
	pen.position = _grounded(_pen_center, 4.0)
	for i in 8:
		var angle := TAU * i / 8.0
		var next_angle := angle + TAU / 8.0
		var post_pos := Vector3(cos(angle) * 4.0, 0.5, sin(angle) * 4.0)
		var next_pos := Vector3(cos(next_angle) * 4.0, 0.5, sin(next_angle) * 4.0)
		# Posts run deep below grade so sloped ground never leaves them floating.
		pen.add_child(Util.box(Vector3(0.15, 2.2, 0.15), Color(0.5, 0.38, 0.25),
			post_pos - Vector3(0, 0.4, 0)))
		var rail := Util.box(Vector3(0.08, 0.08, 3.1), Color(0.55, 0.42, 0.28),
			(post_pos + next_pos) / 2.0 + Vector3(0, 0.25, 0))
		# Aim the rail along the fence line with pure math — look_at needs
		# the node in the tree, and the pen isn't added yet.
		rail.basis = Basis.looking_at(next_pos - post_pos, Vector3.UP)
		pen.add_child(rail)
	# The well at the pen's heart: a stone ring of water for the animals.
	pen.add_child(Util.cylinder(0.85, 0.6, Color(0.55, 0.53, 0.5), Vector3(0, 0.3, 0)))
	pen.add_child(Util.cylinder(0.68, 0.1, Color(0.25, 0.45, 0.65), Vector3(0, 0.62, 0)))
	for side in [-1.0, 1.0]:
		pen.add_child(Util.box(Vector3(0.1, 1.5, 0.1), Color(0.5, 0.38, 0.25),
			Vector3(0.75 * side, 0.9, 0)))
	pen.add_child(Util.prism(Vector3(2.0, 0.5, 1.0), Color(0.6, 0.45, 0.3), Vector3(0, 1.8, 0)))
	add_child(pen)


func pen_position() -> Vector3:
	return global_position + _pen_center


## The well stands at the pen's center; tamed animals drink here.
func well_position() -> Vector3:
	return pen_position()


## True if any penned animal is going hungry (a villager should feed them).
func penned_hungry() -> bool:
	for a in tamed_animals:
		if is_instance_valid(a) and a.hunger > 60.0:
			return true
	return false


## A villager arrived with feed from the store: every animal at the pen eats.
func feed_penned() -> void:
	for a in tamed_animals:
		if is_instance_valid(a) and a.global_position.distance_to(pen_position()) < 14.0:
			a.hunger = maxf(a.hunger - 60.0, 0.0)


## The nearest of this village's fields (villagers work whichever is closest).
## The nearest field this villager may work: dry, not burning, and not already
## claimed by someone else. Claims it for them (one farmer per field), reserved
## by the WANTING — so others look elsewhere the moment this one decides to go.
func pick_farm(from: Vector3, by: Villager) -> Farm:
	Util.prune(farms)
	var best: Farm = null
	var best_dist := INF
	for f in farms:
		var field := f as Farm
		if not field.is_workable() or not field.is_free_for(by):
			continue
		var d := from.distance_to(field.global_position)
		if d < best_dist:
			best_dist = d
			best = field
	if best != null:
		best.claim(by)
	return best


## A dry, field-sized position near a preferred local offset that also DOESN'T
## overlap any existing structure. Snap to dry land; if the preferred spot is
## wet or crowded, ring the village's (dry) centre for a clear, dry footprint.
func _farm_position(preferred: Vector3) -> Vector3:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	var grounded := _grounded(preferred, 3.6)
	if world == null or _farm_spot_ok(world, grounded):
		return grounded
	for i in 24:
		var a := TAU * i / 24.0
		var cand := _grounded(Vector3(cos(a), 0, sin(a)) * randf_range(7.0, 16.0), 3.6)
		if _farm_spot_ok(world, cand):
			return cand
	return grounded  # give up gracefully; at least it sits on the ground


func _farm_spot_ok(world: WorldGen, local: Vector3) -> bool:
	var wx := global_position.x + local.x
	var wz := global_position.z + local.z
	return not world.is_underwater(wx, wz) and _spot_clear(wx, wz, FARM_HALF)


## True if a footprint of half-width `half` at a WORLD point clears every
## structure this village has raised — so nothing is ever built through
## anything else.
func _spot_clear(wx: float, wz: float, half: float) -> bool:
	var p := Vector2(wx, wz)
	if totem != null and p.distance_to(_flat(totem.global_position)) < 2.5 + half:
		return false
	if store != null and is_instance_valid(store) \
			and p.distance_to(_flat(store.global_position)) < FoodStore.PLATFORM_RADIUS + 1.0 + half:
		return false
	if edubba != null and is_instance_valid(edubba) \
			and p.distance_to(_flat(edubba.global_position)) < 3.2 + half:
		return false
	if p.distance_to(_flat(pen_position())) < 5.5 + half:
		return false
	for h in houses:
		if is_instance_valid(h) and p.distance_to(_flat(h.global_position)) < 3.2 + half:
			return false
	for f in farms:
		if is_instance_valid(f) and p.distance_to(_flat(f.global_position)) < FARM_HALF + half:
			return false
	return true


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Wants another field? One per ~7 mouths, capped so villages stay villages.
func wants_new_farm() -> bool:
	Util.prune(farms)
	return farms.size() < mini(1 + int(population() / 7.0), 4)


## A farmer finished breaking new ground: register the field.
func spawn_farm_at(world_spot: Vector3) -> void:
	var new_farm := Farm.new()
	new_farm.position = _farm_position(to_local(world_spot))  # guaranteed dry
	add_child(new_farm)
	farms.append(new_farm)
	if is_player_home:
		GameState.announce("A new field has been broken in %s." % village_name)


## Births are bounded by shelter: a village can outgrow its housing a
## little, but not without limit — build homes to grow the flock.
func at_capacity() -> bool:
	return population() >= housing_capacity() + 8


func _build_influence_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.97
	torus.outer_radius = 1.0
	# A thin flat ring — its tube needs almost no detail, and the default
	# 64x32 was pointless geometry on a ring seen edge-on.
	torus.rings = 48
	torus.ring_segments = 6
	_ring_material = Util.mat(Color(1.0, 0.95, 0.7, 0.6), true)
	_influence_ring = MeshInstance3D.new()
	_influence_ring.mesh = torus
	_influence_ring.material_override = _ring_material
	_influence_ring.position = Vector3(0, 0.3, 0)
	# The ring IS the readout now: its SIZE is the population, its COLOR
	# is belief — every village wears its state on the ground around it.
	_influence_ring.visible = true
	add_child(_influence_ring)


func _build_starting_houses() -> void:
	var sizes: Array = [House.Size.HUT, House.Size.HUT, House.Size.HOUSE] \
		if is_player_home else [House.Size.HUT, House.Size.HUT]
	for i in sizes.size():
		var house := House.new()
		house.size = sizes[i]
		house.village = self
		house.age = randf_range(5.0, 20.0)
		house.position = _grounded(STARTER_HOUSE_SPOTS[i], 2.0)
		# Face the totem — computed off-tree, so no look_at here.
		house.basis = Basis.looking_at(
			-Vector3(house.position.x, 0, house.position.z), Vector3.UP)
		add_child(house)
		houses.append(house)


func _spawn_villagers(count: int) -> void:
	for i in count:
		var v := _make_villager(randf_range(16.0, 45.0))
		var spot := _grounded(Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)), 0.5)
		v.position = spot + Vector3(0, 0.6, 0)
		add_child(v)
	_assign_housing()


func _make_villager(start_age: float) -> Villager:
	var v := Villager.new()
	v.village = self
	v.age = start_age
	return v


func spawn_child(pos: Vector3, mother: Villager = null) -> void:
	var v := _make_villager(0.0)
	v.mother = mother
	v.position = to_local(pos) + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))
	add_child(v)
	_assign_housing()


## The village wants a school once it has a couple of children, the timber
## and stone to raise one, and doesn't already have an Edubba.
func child_count() -> int:
	var n := 0
	for v in my_villagers():
		if not v.is_adult():
			n += 1
	return n


func has_edubba() -> bool:
	return edubba != null and is_instance_valid(edubba)


func wants_edubba() -> bool:
	return not has_edubba() and child_count() >= 2 \
		and store.lumber >= 8 and store.stone >= 5 and construction_site == null


func spawn_edubba_at(world_spot: Vector3) -> void:
	if has_edubba():
		return
	if not store.try_spend_materials(8, 5):
		return
	var e := Edubba.new()
	e.village = self
	e.position = to_local(world_spot)
	add_child(e)
	edubba = e
	if is_player_home:
		GameState.announce("%s has raised an Edubba. Its children will learn there now." % village_name)


## Keeps exactly one living teacher assigned while a school stands.
func needs_teacher() -> bool:
	if not has_edubba():
		return false
	if teacher != null and is_instance_valid(teacher) and teacher.village == self \
			and teacher.is_adult():
		return false
	teacher = null
	return true


func _process(delta: float) -> void:
	# Ahead of the LOD gate, on the real clock: the torches are a LOOK, and a
	# look that updates on a strided tick judders. They cost nothing when the
	# town is far off or the sun is up, which the tick checks first thing.
	_tick_torches(delta)

	# Simulation LOD: a village far from the camera runs its bookkeeping (prayer,
	# belief, housing) on a slower clock — the per-frame worshipper scan is the
	# priciest thing here, and distant towns needn't pay it every frame.
	var stride := Util.sim_stride(global_position)
	if stride > 1:
		_sim_skip += 1
		if _sim_skip < stride:
			return
		delta *= _sim_skip
		_sim_skip = 0
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

	if alarm > 0.0:
		alarm -= delta
	if grudge > 0.0:
		grudge = maxf(grudge - GRUDGE_DECAY * delta, 0.0)
	if attention > 0.0:
		attention = maxf(attention - ATTENTION_DECAY * delta, 0.0)
	# The town takes stock — once, for everybody.
	hive.tick(delta, self)

	_housing_timer -= delta
	if _housing_timer <= 0.0:
		_housing_timer = 4.0
		_assign_housing()
		_update_influence()  # ring size tracks population; orb tracks prayer

	_breed_timer -= delta
	if _breed_timer <= 0.0:
		_breed_timer = 50.0
		_breed_livestock()

	_pop_timer -= delta
	if _pop_timer <= 0.0:
		_pop_timer = 20.0
		_pop_samples.append(population())
		if _pop_samples.size() > 12:      # about four minutes of history
			_pop_samples.pop_front()


## TORCHLIGHT ------------------------------------------------------------------

## Flames over the people who are still out after dark. Everything expensive is
## behind an early return: by day, or from far off, this is two comparisons.
func _tick_torches(delta: float) -> void:
	var wanted := GameState.is_night() \
		and Util.sim_stride(global_position) <= 2 \
		and _within(TORCH_RANGE)
	if not wanted:
		if _torches != null and _torches.visible:
			_torches.visible = false
		return
	_torch_age += delta
	_torch_timer -= delta
	if _torch_timer > 0.0:
		# Flicker on its own slower clock. A flame at 15Hz is indistinguishable
		# from one at 60, and this is a per-instance write for every torch in
		# town — worth doing a quarter as often.
		_flicker_beat -= delta
		if _flicker_beat <= 0.0:
			_flicker_beat = TORCH_FLICKER
			_flicker_torches()
		return
	_torch_timer = TORCH_REFRESH
	_deal_torches()


## Hand the flames out to whoever is awake and outdoors. Sleepers carry none:
## a town at three in the morning should be a few lit windows and a watchman,
## not a torchlit parade.
func _deal_torches() -> void:
	var carriers: Array[Vector3] = []
	var most := Quality.particles(TORCH_MOST)
	for v in my_villagers():
		if carriers.size() >= most:
			break
		if v.state == Villager.State.SLEEPING or v.is_dying():
			continue
		carriers.append(v.global_position + Vector3(0.35, 1.45, 0))
	if carriers.is_empty():
		if _torches != null:
			_torches.visible = false
		return
	if _torches == null:
		_build_torches()
	var mm := _torches.multimesh
	mm.instance_count = carriers.size()
	for i in carriers.size():
		mm.set_instance_transform(i, Transform3D(Basis(), to_local(carriers[i])))
		mm.set_instance_color(i, TORCH_COLOR)
	_torches.visible = true
	_flicker_torches()


## A flame is never steady. Two waves out of step per torch, so no two in the
## town pulse together — which is what stops a row of them reading as a string
## of fairy lights.
func _flicker_torches() -> void:
	if _torches == null or not _torches.visible:
		return
	var mm := _torches.multimesh
	for i in mm.instance_count:
		var phase := float(i) * 1.7
		var beat := sin(_torch_age * 7.1 + phase) * 0.16 \
			+ sin(_torch_age * 3.3 + phase * 2.1) * 0.1
		mm.set_instance_color(i, Color(
			TORCH_COLOR.r, TORCH_COLOR.g, TORCH_COLOR.b, clampf(0.85 + beat, 0.4, 1.0)))


func _build_torches() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Util.flame_mesh(TORCH_SIZE.x, TORCH_SIZE.y)
	mm.instance_count = 0
	_torches = MultiMeshInstance3D.new()
	_torches.multimesh = mm
	_torches.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_torches)


## Is what the player is looking at inside `reach` of this town?
func _within(reach: float) -> bool:
	return GameState.camera_focus.distance_to(global_position) < reach


func my_villagers() -> Array[Villager]:
	var result: Array[Villager] = []
	for v in get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if is_instance_valid(villager) and villager.village == self:
			result.append(villager)
	return result


func population() -> int:
	return my_villagers().size()


## How many of my villagers are currently occupied by each job — a deciding
## villager reads this to steer toward under-served work, so the flock spreads
## across the village's needs instead of all conga-lining to one resource.
func job_counts() -> Dictionary:
	var counts := {}
	for v in my_villagers():
		var job := v.current_job()
		if job != "":
			counts[job] = counts.get(job, 0) + 1
	return counts


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
	# Every convert widens your spellbook: their faith teaches you new wonders,
	# and their prayers can pay for any miracle you already know.
	var manager := get_tree().get_first_node_in_group("miracles") as MiracleManager
	if manager != null:
		var taught: Array = manager.newly_taught()
		if not taught.is_empty():
			GameState.announce("Their devotion teaches you: %s!"
				% ", ".join(taught).replace("_", " "))


## The world is the interface: ring size = population, ring color =
## belief (gray heathens brighten to gold; converted rings wear the
## god's alignment color), totem orb glow = prayer power.
func _update_influence() -> void:
	influence_radius = clampf(10.0 + population() * 1.8, MIN_INFLUENCE, MAX_INFLUENCE)
	if _influence_ring != null:
		_influence_ring.scale = Vector3(influence_radius, 1.0, influence_radius)
	if _ring_material != null:
		var c: Color
		if converted:
			c = GameState.alignment_color().lerp(Color.WHITE, 0.1)
		else:
			c = Color(0.45, 0.45, 0.45).lerp(Color(1.0, 0.9, 0.55), belief / CONVERT_BELIEF)
		_ring_material.albedo_color = Color(c.r, c.g, c.b, 0.55)
		_ring_material.emission = c
		_ring_material.emission_energy_multiplier = 0.4 + (belief / 100.0) * 1.6
	if _totem_orb != null and converted:
		var orb := _totem_orb.material_override as StandardMaterial3D
		if orb != null and orb.emission_enabled:
			orb.emission_energy_multiplier = 0.4 + 3.2 \
				* (GameState.prayer_power / maxf(GameState.max_prayer_power, 1.0))
	if is_player_home:
		# Every converted village widens the reservoir of prayer you can
		# hold — the gate behind the mightiest, most constant miracles.
		var believers := 0
		for v in get_tree().get_nodes_in_group("village"):
			if (v as Village).converted:
				believers += 1
		GameState.set_max_prayer_power(100.0 + belief * 2.0 + believers * PRAYER_PER_VILLAGE)


func _on_alignment_changed(_value: float) -> void:
	_update_influence()


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
## Also marks which houses are lived in — occupancy is what keeps a
## house standing against the years.
func _assign_housing() -> void:
	Util.prune(houses)
	var villagers := my_villagers()
	var slots := []
	for h in houses:
		for i in h.capacity():
			slots.append(h)
	var lived_in := {}
	for i in villagers.size():
		villagers[i].home = slots[i] if i < slots.size() else null
		if villagers[i].home != null:
			lived_in[villagers[i].home] = true
	for h in houses:
		h.occupied = lived_in.has(h)


## A villager set down here by the hand has joined us — welcome them home.
## The god's own touch is the strongest attention of all.
func adopt(_newcomer: Villager) -> void:
	notice(40.0)
	_assign_housing()


func on_house_completed(house: House) -> void:
	if construction_site == house:
		construction_site = null
	if is_player_home:
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
			if world.slope_at(pos.x, pos.z) > 0.9:
				continue
			# The WHOLE footprint must be dry — no floating over an inlet.
			if not world.footprint_dry(pos.x, pos.z, 2.2):
				continue
			# And the way there must stay on land — never build across a lake.
			if not world.line_dry(global_position.x, global_position.z, pos.x, pos.z):
				continue
			pos.y = world.settle_height(pos.x, pos.z, 2.2)
		var blocked := false
		for h in houses:
			if is_instance_valid(h) and h.global_position.distance_to(pos) < 4.5:
				blocked = true
				break
		if totem.global_position.distance_to(pos) < 6.0:
			blocked = true
		for f in farms:
			if is_instance_valid(f) and f.global_position.distance_to(pos) < 7.0:
				blocked = true
				break
		# The round market is wide — houses keep extra distance from it.
		if store.global_position.distance_to(pos) < 8.5:
			blocked = true
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
	Util.prune(tamed_animals)
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
	Util.prune(tamed_animals)
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
	notice(30.0)   # a wonder over their heads is the loudest kind of attention
	var flat := pos
	flat.y = 0
	var here := global_position
	here.y = 0
	if flat.distance_to(here) > maxf(influence_radius * 1.3, 25.0):
		return
	# The CROWD MIND takes it as one event, whatever the particular miracle was:
	# a wonder if it blessed them, a horror if it broke over their heads. Each
	# villager then reads the town's mood rather than judging the sky themselves.
	hive.witness("horror" if type in TERRORS else "wonder", pos, 1.0)
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
		"forest_seed", "forage_thicket":
			change_belief(5.0)
			GameState.announce("Green life bursts forth near %s. A generous god!" % village_name)
		"bird_flock":
			change_belief(4.0)
			GameState.announce("An omen of birds passes over %s." % village_name)
		"cloudburst", "deluge":
			change_belief(6.0)
			GameState.announce("The heavens open over %s. Every cistern brims." % village_name)
		"gust":
			change_belief(2.0)
		"thunderclap":
			change_belief(5.0)
			GameState.announce("Thunder splits the air over %s, and no one is harmed." % village_name)
			for v in my_villagers():
				if v.global_position.distance_to(pos) < 18.0:
					v.scare(pos)
		"lightning_storm", "tornado", "thunderstorm":
			change_belief(10.0)
			GameState.announce("%s trembles beneath a wrath from the heavens." % village_name)
			for v in my_villagers():
				if v.global_position.distance_to(pos) < 20.0:
					v.witness_horror(4.0)
					v.scare(pos)
		# The great storms. Belief through sheer terror — and they will
		# remember it as long as anyone in the village is alive to.
		"tempest", "firestorm", "hurricane":
			change_belief(14.0)
			remember_battle(false)   # nothing can be fought; the doctrine learns fear
			GameState.announce("The sky comes apart over %s. They will speak of this for generations."
				% village_name)
			for v in my_villagers():
				if v.global_position.distance_to(pos) < 34.0:
					v.witness_horror(7.0)
					v.scare(pos)
		_:
			change_belief(3.0)


func hover_text() -> String:
	var faith: String = "faithful" if converted \
		else "unbelieving (belief %d/%d)" % [int(belief), int(CONVERT_BELIEF)]
	# Their growth is legible: a tended people quicken, a neglected one idles.
	var mood := "quiet — they grow slowly untended"
	if attention > 60.0:
		mood = "THRIVING under your attention"
	elif attention > 20.0:
		mood = "heartened by your notice"
	var extra := ""
	if is_roused():
		extra = "\nROUSED — %d under arms" % armed_count()
	return "%s — %s\n%s (pop %d)\nThe town is %s%s" % [
		village_name, faith, mood, population(), hive.report(), extra]


## Militia ---------------------------------------------------------------------

## One of ours has been hurt (or a menace was spotted): rouse the village. For
## ALARM_SECONDS the able-bodied will arm themselves and drive the threat off
## instead of going about their work.
func raise_alarm(where: Vector3, from_creature := false) -> void:
	var was_calm := alarm <= 0.0
	alarm = ALARM_SECONDS
	threat_pos = where
	# An animal in the fold frightens them; the god's own beast turning on them
	# is an OUTRAGE, which is the feeling that eventually makes a mob.
	hive.witness("outrage" if from_creature else "horror", where, 1.0)
	if from_creature:
		grudge = minf(grudge + 18.0, 100.0)
	if was_calm and is_player_home:
		if from_creature and grudge >= GRUDGE_HOSTILE:
			GameState.announce("%s has had enough of your creature. They are taking up arms!"
				% village_name)
		else:
			GameState.announce("Alarm in %s! They are arming themselves." % village_name)


func is_roused() -> bool:
	return alarm > 0.0


## True once the village blames your creature enough to actually fight it.
func hates_creature() -> bool:
	return grudge >= GRUDGE_HOSTILE


## How many of my people are already carrying arms.
func armed_count() -> int:
	var n := 0
	for v in my_villagers():
		if v.weapon != "":
			n += 1
	return n


## Blood debt: this beast killed one of ours. Every able hand will hunt it down
## specifically, on top of clearing any predator inside the village bounds.
func mark_for_death(beast: Animal) -> void:
	if beast == null or not is_instance_valid(beast):
		return
	Util.prune(vendetta)
	if not vendetta.has(beast):
		vendetta.append(beast)
		if is_player_home:
			GameState.announce("%s swears vengeance on the %s that killed their own."
				% [village_name, beast.species])
	raise_alarm(beast.global_position)


## The beast this villager should hunt: a blood-debt target first (anywhere),
## otherwise any predator that has come inside the village bounds. Returns null
## when there is nothing to fight.
func fight_target(from: Vector3) -> Animal:
	Util.prune(vendetta)
	var best: Animal = null
	var best_dist := INF
	for a in vendetta:
		var beast := a as Animal
		var d := from.distance_to(beast.global_position)
		if d < best_dist and d < 90.0:
			best_dist = d
			best = beast
	if best != null:
		return best
	# No blood debt outstanding: drive off whatever prowls our ground.
	for n in get_tree().get_nodes_in_group("animals"):
		var beast := n as Animal
		if not is_instance_valid(beast) or beast.tamed_by != null:
			continue
		if not beast.spec.get("predator", false):
			continue
		var here := beast.global_position.distance_to(global_position)
		if here > influence_radius:
			continue   # only what is INSIDE our bounds
		var d := from.distance_to(beast.global_position)
		if d < best_dist:
			best_dist = d
			best = beast
	return best


## Divine attention -----------------------------------------------------------

## Something of yours touched this village — a miracle, your hand, your
## creature's labour among them. Lifts their spirits and, with them, the odds
## of children. Untended villages coast along at BREED_BASE and barely grow.
func notice(amount: float) -> void:
	attention = minf(attention + amount, 100.0)


## The per-second chance a courting pair conceives, once they are TOGETHER.
## Divine attention roughly triples it — so a tended village fills its houses
## quickly and a neglected one still plods along instead of dying out.
func conception_chance() -> float:
	return BREED_BASE * (1.0 + attention / BREED_ATTENTION_GAIN)


## Which way the population is going, in one word. Compares the recent half of
## the record against the older half, so a single birth or death does not swing
## it. Returns "" until there is enough history to be worth saying.
func trend() -> String:
	if _pop_samples.size() < 6:
		return ""
	var half := int(_pop_samples.size() / 2.0)
	var older := 0.0
	var recent := 0.0
	for i in _pop_samples.size():
		if i < half:
			older += float(_pop_samples[i])
		else:
			recent += float(_pop_samples[i])
	older /= float(half)
	recent /= float(_pop_samples.size() - half)
	if recent > older + 0.5:
		return "growing"
	if recent < older - 0.5:
		return "DWINDLING"
	return "steady"


## How a fight went. Winning teaches them to stand; losing their own teaches
## them to hide. This is the village's whole military doctrine, learned.
func remember_battle(won: bool) -> void:
	var before := resolve
	if won:
		resolve = minf(resolve + RESOLVE_WIN, 100.0)
		if is_player_home and before < RESOLVE_FIGHT and resolve >= RESOLVE_FIGHT:
			GameState.announce("%s has found its courage." % village_name)
	else:
		resolve = maxf(resolve - RESOLVE_LOSS, 0.0)
		if is_player_home and before >= RESOLVE_FIGHT and resolve < RESOLVE_FIGHT:
			GameState.announce("%s has lost its nerve. They will hide now." % village_name)


## Do these people stand and fight, or bar their doors? Numbers and arms embolden
## them on top of whatever their history taught.
func will_fight(allies: int, armed: bool) -> bool:
	var nerve := resolve + allies * 6.0 + (18.0 if armed else 0.0)
	return nerve >= RESOLVE_FIGHT + 15.0


## Somewhere to cower: the nearest home, or failing that the totem.
func refuge(from: Vector3) -> Vector3:
	var best := totem.global_position
	var best_dist := INF
	for h in houses:
		if not is_instance_valid(h) or h.under_construction:
			continue
		var d := from.distance_to(h.global_position)
		if d < best_dist:
			best_dist = d
			best = h.global_position
	return best


## Persistence -----------------------------------------------------------------

## A village's LIVED state. The terrain and where towns sit regenerate from the
## world seed, so only what play has changed needs storing: faith, stocks, the
## people, and the doctrine they have learned.
func to_dict() -> Dictionary:
	var folk := []
	for v in my_villagers():
		folk.append({
			"name": v.villager_name, "female": v.is_female, "age": v.age,
			"morality": v.morality, "health": v.health, "weapon": v.weapon,
			"hunger": v.hunger, "energy": v.energy,
		})
	return {
		"name": village_name, "home": is_player_home,
		"pos": [global_position.x, global_position.z],
		"converted": converted, "belief": belief, "diet": int(diet),
		"resolve": resolve, "grudge": grudge, "attention": attention,
		"hive": hive.to_dict(),
		"store": {
			"plant": store.plant_food, "meat": store.meat_food,
			"lumber": store.lumber, "stone": store.stone,
		},
		"folk": folk,
	}


## Restore a village's lived state onto a freshly generated one. Its people are
## replaced wholesale by the saved roster.
func from_dict(data: Dictionary) -> void:
	village_name = String(data.get("name", village_name))
	hive.from_dict(data.get("hive", {}))
	converted = bool(data.get("converted", converted))
	belief = float(data.get("belief", belief))
	diet = data.get("diet", diet) as Diet
	resolve = float(data.get("resolve", RESOLVE_START))
	grudge = float(data.get("grudge", 0.0))
	attention = float(data.get("attention", 0.0))
	var st: Dictionary = data.get("store", {})
	if not st.is_empty() and is_instance_valid(store):
		store.plant_food = int(st.get("plant", store.plant_food))
		store.meat_food = int(st.get("meat", store.meat_food))
		store.lumber = int(st.get("lumber", store.lumber))
		store.stone = int(st.get("stone", store.stone))
	var folk: Array = data.get("folk", [])
	if not folk.is_empty():
		for v in my_villagers():
			v.queue_free()
		for entry: Dictionary in folk:
			_restore_villager(entry)
	if converted:
		_totem_orb.material_override = Util.mat(Color(1.0, 0.85, 0.3), true)
	_update_influence()


func _restore_villager(entry: Dictionary) -> void:
	var v := Villager.new()
	v.village = self
	v.age = float(entry.get("age", 25.0))
	add_child(v)
	# Name and sex are set in _ready, so overwrite them once it is in the tree.
	v.is_female = bool(entry.get("female", true))
	v.villager_name = String(entry.get("name", v.villager_name))
	v.morality = float(entry.get("morality", 20.0))
	v.health = float(entry.get("health", 100.0))
	v.weapon = String(entry.get("weapon", ""))
	v.hunger = float(entry.get("hunger", 30.0))
	v.energy = float(entry.get("energy", 80.0))
	v.position = _grounded(Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), 0.5) \
		+ Vector3(0, 0.6, 0)

