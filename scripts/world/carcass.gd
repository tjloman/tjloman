class_name Carcass
extends RigidBody3D
## A DEAD BEAST, AND IT IS STILL THERE.
##
## An animal used to end with `queue_free` and a handful of joints of meat
## appearing in the grass where it had been standing — so a bison shot out of the
## sky by a fireball left three chops and no bison. There was no body in the
## game. Nothing to drag off, nothing to throw at a wall, nothing to burn, and
## nothing for a creature to stand over and think about.
##
## IT HAS THE WEIGHT OF THE ANIMAL IT WAS, reckoned off the torso the beast was
## drawn with — so a chicken thrown at a house does not even register as a blow
## (see Blow.MOMENTUM_MATTERS) and a bison takes better than a third of it off
## in one throw. That is the whole of "a bison doesn't strike a house without
## consequences": nobody wrote a rule, the volume was already in the table.
##
## AND NOBODY CAME FOR IT MEANS IT FALLS APART, the same sentence a felled trunk
## is under — see WildTree.LIES_FOR. A body left alone for three quarters of a
## minute becomes the meat it was always going to become, which is what keeps
## this from quietly taking a food source away from every village in the world:
## the joints still arrive, they just arrive after the body has had its chance
## to be a body. Touch it, throw it, roll it down a hill and the clock starts
## over.
##
## BURNT, IT CHARS RATHER THAN VANISHING, and a charred body feeds nobody. Fire
## is not a way to cook dinner here; it is a way to waste one.
##
## THERE IS NO SUCH THING AS A CHILD'S BODY in this game, and that is not this
## file's doing but it is worth writing down where the corpses live: see
## Villager._die, which raises no Corpse at all for anyone under ADULT_AGE. Every
## object like this one is PICKABLE, and PICKABLE means carried off, hurled at a
## wall, set alight, eaten and butchered. Those are not things to do to a dead
## child, so the object does not exist.

## WHAT A BODY WEIGHS, off the volume of the torso it was drawn with. Tuned so a
## bison comes to about nine and a half and a chicken to a third of one — which
## puts the chicken under Blow's momentum floor entirely, and that is correct.
const HEFT_BARE := 0.2
const HEFT_PER_CUBIC := 4.0

## HOW LONG A BODY LIES THERE BEFORE IT IS ONLY MEAT, in seconds. Longer than a
## felled trunk's half-minute: a body is worth more attention than a log, and a
## village that has just lost its livestock should have time to come out and
## look at it.
const LIES_FOR := 45.0

## How long it burns, and what it can take before it is ruined.
const BURNS_FOR := 20.0
const MOST_HEALTH := 40.0
## What a hot stone or a passing gout has to put into it before it catches.
const SCORCH_CATCHES := 60.0
## What is left of the colour afterwards. Not black — ashen.
const CHARRED := Color(0.11, 0.10, 0.09)

var species := "beast"
var meat := 1
var meat_name := "meat"
## The torso the beast was drawn with — its size IS its weight. See
## Animal.SPECIES.
var body := Vector3(0.7, 0.55, 1.1)
var hue := Color(0.6, 0.55, 0.5)

var burning := false
var health := MOST_HEALTH

var _lying_for := 0.0
var _burn_time := 0.0
var _charred := false
var _fire_visual: Node3D = null
var _meshes: Array[MeshInstance3D] = []
var _shown := false


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	# The dead stay where they fall — no rolling downhill into the lake.
	var phys := PhysicsMaterial.new()
	phys.friction = 1.0
	phys.bounce = 0.0
	physics_material_override = phys
	linear_damp = 0.8
	angular_damp = 8.0
	# A THROWN BODY IS SOMETHING PEOPLE WATCH LAND. There is no other way for a
	# RigidBody to notice that it arrived, and there are never many carcasses.
	contact_monitor = true
	max_contacts_reported = 1


func _ready() -> void:
	add_to_group("carcasses")
	add_to_group(Affords.PICKABLE)
	add_to_group(Affords.BURNABLE)
	set_meta("hover_name", "%s carcass" % species.capitalize())
	mass = heft()

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = body
	col.shape = shape
	col.position = Vector3(0, body.y * 0.5, 0)
	add_child(col)

	# THE BEAST'S OWN MODEL IF THE BANK HAS ONE, lying on its side — the same
	# mesh that was walking about a moment ago, which is the only way a body
	# reads as THAT animal's body. Failing that, the torso box it was drawn with.
	var custom := ModelBank.instantiate(species)
	if custom != null:
		custom.position.y += ModelBank.footing(species)
		custom.rotation.z = PI * 0.5
		add_child(custom)
		for mi in custom.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(mi as MeshInstance3D)
	else:
		var torso := Util.box(Vector3(body.x, body.y, body.z), hue,
			Vector3(0, body.y * 0.45, 0))
		torso.rotation.z = PI * 0.5
		add_child(torso)
		_meshes.append(torso)
		var head := Util.sphere(body.y * 0.42, hue,
			Vector3(0, body.y * 0.4, body.z * 0.55))
		add_child(head)
		_meshes.append(head)

	body_entered.connect(_on_hit)


## What it weighs, off the torso it was drawn with. See HEFT_PER_CUBIC.
func heft() -> float:
	return HEFT_BARE + body.x * body.y * body.z * HEFT_PER_CUBIC


func _process(delta: float) -> void:
	Ledger.open(&"Carcass")
	if burning:
		_burn(delta)
		return
	# BEING PLAYED WITH IS NOT BEING ABANDONED. Held (frozen by whatever picked
	# it up), thrown, or still rolling — any of those and the clock is at zero.
	# Asked of the physics server rather than of a flag, so nothing has to
	# remember to tell it.
	if freeze or not sleeping:
		_lying_for = 0.0
		return
	_lying_for += delta
	if _lying_for >= LIES_FOR:
		_fall_apart()


## SOMEBODY IS STILL PLAYING WITH IT. Starts the clock over.
func touched() -> void:
	_lying_for = 0.0


## CUT IT UP. Returns the joints it yields — nothing at all if it has been
## burnt, because a charred body feeds nobody. The carcass is gone afterwards.
func butcher() -> int:
	var got := 0 if _charred else meat
	queue_free()
	return got


## Fire ------------------------------------------------------------------------

func ignite() -> void:
	if burning:
		return
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null and world.is_underwater(global_position.x, global_position.z):
		return
	burning = true
	_burn_time = BURNS_FOR
	_build_fire()


func extinguish() -> void:
	burning = false
	_burn_time = 0.0
	if _fire_visual != null and is_instance_valid(_fire_visual):
		_fire_visual.queue_free()
	_fire_visual = null


## Heat from something that is already alight — a hot stone lying against it, a
## gout rolling past. Enough of it and the body catches.
func scorch(joules: float) -> void:
	if burning or joules < SCORCH_CATCHES:
		return
	ignite()


func full_health() -> float:
	return MOST_HEALTH


func damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		burn_down()


## IT DOES NOT DISAPPEAR. Whatever finished it off, what is left is a body —
## ruined, ashen, still there to be thrown. It falls apart on its own clock like
## any other, and it feeds nobody.
func burn_down() -> void:
	extinguish()
	_char()   # whatever finished it off, it is ruined


## HALFWAY THROUGH, NOT AT THE FIRST LICK OF FLAME. A body that chars the
## instant it catches is a body that can never be saved, and rain douses
## anything BURNABLE it falls on (see MiracleManager._douse_the_built) — so
## there is a window, and getting a lit carcass out from under the fire is worth
## doing. Past halfway the meat is gone whatever happens next.
func _burn(delta: float) -> void:
	_burn_time -= delta
	if _fire_visual != null and is_instance_valid(_fire_visual):
		_fire_visual.scale.y = 1.0 + sin(Time.get_ticks_msec() / 60.0) * 0.15
	if _burn_time <= BURNS_FOR * 0.5:
		_char()
	if _burn_time <= 0.0:
		extinguish()


## ASHEN, AND IT STAYS ASHEN. Each mesh gets its own material the first time, or
## tinting a shared one would blacken every beast in the world.
func _char() -> void:
	if _charred:
		return
	_charred = true
	for mi in _meshes:
		if not is_instance_valid(mi):
			continue
		var mat := Util.mat(CHARRED)
		mi.material_override = mat


func _build_fire() -> void:
	_fire_visual = Node3D.new()
	var tall := maxf(body.y, 0.3)
	for i in 3:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = tall * 0.5
		cone.height = tall * 1.6
		_fire_visual.add_child(Util.mesh_node(cone,
			Color(1.0, randf_range(0.4, 0.7), 0.12),
			Vector3(randf_range(-0.5, 0.5) * body.z, tall * 0.9,
				randf_range(-0.3, 0.3) * body.x), true))
	add_child(_fire_visual)


## What is left when nobody came for it. The joints the beast was always worth,
## unless it was burnt — see `butcher`.
func _fall_apart() -> void:
	var parent := get_parent() as Node3D
	if parent != null and not _charred:
		for i in meat:
			var item := FoodItem.new()
			item.food_type = FoodItem.FoodType.MEAT
			item.meat_name = meat_name
			item.position = parent.to_local(global_position
				+ Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)))
			parent.add_child(item)
	queue_free()


## Touchdown. Whoever's ground this is has just had a body land on it — and if
## that ground is a storehouse, the body is banked rather than bounced.
func _on_hit(_what: Node) -> void:
	if _banked():
		return
	if _shown:
		return
	_shown = true
	VillageWonder.landed(get_tree(), "corpse", global_position,
		linear_velocity.length())


## DROPPED ON A STOREHOUSE, IT IS DINNER. The same door a tree and a rock use —
## the one place a thing stops being itself and becomes stores.
func _banked() -> bool:
	if _charred:
		return false
	for s in get_tree().get_nodes_in_group("stores"):
		var store := s as FoodStore
		if not is_instance_valid(store):
			continue
		if store.global_position.distance_to(global_position) \
				> FoodStore.PLATFORM_RADIUS + 1.0:
			continue
		store.add(FoodItem.FoodType.MEAT, meat)
		var town := store.get_parent() as Village
		if town != null and is_instance_valid(town):
			town.wonder.given(town, "meat", meat, 0.0,
				has_meta("hurled_by_creature"))
		queue_free()
		return true
	return false


func hover_text() -> String:
	if _charred:
		return "A burnt %s — ashen, and good for nothing but throwing." % species
	if burning:
		return "A %s, burning. It will be worth nothing when the fire is done." % species
	return "A dead %s — %d joints of meat. Drop it on a storehouse." % [species, meat]
