class_name Caravan
extends RigidBody3D
## A TOWN IN A WAGON.
##
## Villages could only ever appear where the world generator decided to put
## one — three chunks out from the origin, on a cell that rolled the right
## ticket, in a biome the generator happened to like. The player had no say in
## it at all. You could burn a village down and you could convert one, and
## there was no verb anywhere in the game for FOUNDING one.
##
## THE HAND IS THE VERB. A wagon is a thing you pick up and put down, exactly
## like a rock or a sheep, and where you put it down a town stands. There is no
## menu, no build mode and no placement cursor: carry it there, drop it, and if
## the ground will not take it the wagon tells you why and stays a wagon so you
## can carry it somewhere better.
##
## WHERE THE WAGON COMES FROM is the part that makes this a simulation rather
## than a button. A town that has outgrown its roofs packs one. People sleeping
## rough ARE the colonists — the overcrowding that used to be a slow drag on a
## village's mood is now the thing that produces expeditions, which is what
## overcrowding has always meant everywhere else.
##
## AND A TOWN THAT KEEPS STOCK SENDS A BETTER ONE. Herders know how to start
## somewhere from nothing; that is most of what herding is. So the beasts in
## the pen buy the expedition more people, more timber and a few head to drive
## along with it — see `pack`, where every one of those is read off
## `tamed_count`.
##
## A WAGON ON THE ROAD HOLDS GROUND. It is in MiracleReach's circles for as
## long as it is a wagon, so leading a settling party across the map carries
## your power with it — you can work miracles over the expedition, and the
## moment it settles the circle it was holding becomes the town's own.

## WHAT IT TAKES TO PACK ONE, and what goes in it. Souls come out of the
## village's homeless, so a town only sends people it could not house anyway.
const SOULS_SENT := 8
const SOULS_MOST := 22
const LUMBER_SENT := 40
const STONE_SENT := 15
const FOOD_SENT := 30

## WHAT A HERDING TOWN ADDS. Every this-many head in the books is worth one
## more colonist and one more beast driven along, up to the caps — a village
## that has made itself good at animals founds visibly better towns.
const HEAD_PER_BONUS := 12
const SOULS_PER_BONUS := 2
const BONUS_MOST := 7
const HEAD_MOST := 9
## And what a bonus is worth in timber, which is what a new town is short of.
const LUMBER_PER_BONUS := 12

## HOW LONG IT MUST SIT STILL before it unpacks. Long enough that setting it
## down and thinking better of it is possible, short enough that nobody stands
## there wondering whether it worked.
const SETTLES_AFTER := 2.5
const STILL_ENOUGH := 0.6

## THE EXPEDITION. How near your hand has to be for the creature to reckon it
## is being led somewhere, and how long it will stand there holding a town on
## its back after you have wandered off before it puts the thing down.
const LEADS_FROM := 45.0
const SETS_IT_DOWN := 20.0
## Where on the creature the meta that times that lives. A meta rather than a
## field because Creature sits permanently on its line limit and a hauling
## timer is not worth a line of it — the same trick `struck_by_god` uses.
const ALONE_META := "hauled_alone"

## HOW MUCH GROUND A WAGON HOLDS while it is on the road — and it is ONE METRE,
## which is not a typo.
##
## It was twenty, on the reasoning that a settling party is a town that has not
## arrived yet. In the hand that is a town you can carry: park the wagon and
## you have twenty metres of castable country anywhere on the map, refilling
## your leash as fast as a real village does. A wagon is not a country. It is a
## thing you are moving.
##
## So the circle is exactly wide enough to pick the wagon up and put it down
## again, and no wider — and standing in it fills the leash to ONE PER CENT,
## which is a moment's grip and not a breath of a gesture. Everything a wagon
## affords is moving the wagon.
const REACH := 1.0
## What standing on a wagon's ground refills your leash to, as a share of the
## whole. Enough to take hold of it; not enough to finish a rune or lift a
## tree. See MiracleReach.pay_out.
const REFILLS_TO := 0.01

## AND HOW CLEAR OF AN EXISTING TOWN IT HAS TO STAND. Two influence radii of
## the largest village in the game, so a colony is never founded inside one.
const CLEAR_OF_TOWNS := 90.0
## The slope a cart can be unloaded on, how much ground a town needs, and how
## many places that ground is read at. A settlement is not a point.
const STEEPEST := 0.8
const FOOTPRINT := 18.0
const SLOPE_PROBES := 8
## What it says when the ground will not do, and how long it says it for.
const NOT_HERE := "on to greener pastures..."
const SAYS_NO_FOR := 1.8

## For naming colonies after their mother. Past the end of this a town is simply
## the last numeral again, which will do: nobody is founding eleven colonies out
## of one village.
const NUMERALS: Array[String] = [
	"", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
]

## WHAT IS IN IT. Every one of these is taken out of the village that packed it,
## and put into the village it becomes.
var souls := SOULS_SENT
var lumber := LUMBER_SENT
var stone := STONE_SENT
var food := FOOD_SENT
var head := 0
## What sort of beasts, in the order they will be unloaded. Read off the pen of
## the town that packed it, so a colony out of a sheep town arrives with sheep.
var stock: Array[String] = []
var from_name := "somewhere"

var _settling := 0.0
var _complained := ""
## Has anybody actually picked this up? A freshly packed wagon is standing in
## the middle of the town that packed it, which is the one place a colony may
## not be founded — so without this it announced "too near Elsmere" the moment
## it appeared, before the player had touched it.
var _travelled := false


static func create(town: Village) -> Caravan:
	var cart := Caravan.new()
	cart.from_name = town.village_name
	return cart


## CAN THIS TOWN SPARE ONE? Returns "" when it can, and otherwise the reason,
## phrased for a player rather than for a log. The village asks this; nothing
## else should need to.
static func why_not(town_given: Variant) -> String:
	# Untyped until proved alive: a freed object handed to a typed
	# parameter is the error, before any check here could run.
	if not is_instance_valid(town_given):
		return "there is no village here"
	var town := town_given as Village
	if town == null or not is_instance_valid(town):
		return "there is no village here"
	if town.homeless_count() < SOULS_SENT:
		return "%s has nobody sleeping rough to send" % town.village_name
	if town.store == null or not is_instance_valid(town.store):
		return "%s has no stores to load" % town.village_name
	if town.store.lumber < LUMBER_SENT or town.store.stone < STONE_SENT:
		return "%s cannot spare the timber and stone" % town.village_name
	if town.store.plant_food + town.store.meat_food < FOOD_SENT:
		return "%s has not the food to feed a journey" % town.village_name
	return ""


## PACK ONE, taking every bit of it out of the town. Returns null if the town
## could not spare it after all — `why_not` is the question to ask first.
static func pack(town: Village) -> Caravan:
	if why_not(town) != "":
		return null
	var cart := Caravan.create(town)
	# THE HERDERS' BONUS. Stock in the books is experience at starting from
	# nothing, and it buys people, timber and beasts to drive along. Rounded
	# DOWN on purpose: eleven head is not a twelfth of a bonus, it is no bonus.
	@warning_ignore("integer_division")
	var rungs := town.tamed_count() / HEAD_PER_BONUS
	var bonus := mini(rungs, BONUS_MOST)
	cart.souls = mini(SOULS_SENT + bonus * SOULS_PER_BONUS, SOULS_MOST)
	cart.lumber = LUMBER_SENT + bonus * LUMBER_PER_BONUS
	cart.head = mini(bonus, HEAD_MOST)
	cart.stock = _drive_off(town, cart.head)
	cart.head = cart.stock.size()
	town.store.lumber -= LUMBER_SENT
	town.store.stone -= STONE_SENT
	var took := town.store.take(FoodItem.FoodType.PLANT, FOOD_SENT)
	if took < FOOD_SENT:
		took += town.store.take(FoodItem.FoodType.MEAT, FOOD_SENT - took)
	cart.food = took
	return cart


## TAKE THE BEASTS OUT OF THE PEN, up to `many`, and remember what they were.
## They leave the old town's books here rather than at the far end, because a
## wagon lost on the road should cost the village that packed it.
static func _drive_off(town: Village, many: int) -> Array[String]:
	var driven: Array[String] = []
	Util.prune(town.tamed_animals)
	for a in town.tamed_animals.duplicate():
		if driven.size() >= many:
			break
		var beast := a as Animal
		if beast == null or not is_instance_valid(beast):
			continue
		driven.append(beast.species)
		town.on_tamed_lost(beast)
		beast.queue_free()
	return driven


## WHERE A HAULING CREATURE WALKS, or INF when the expedition is over and it
## should set the wagon down.
##
## THE POINT OF THE YOKE IS THE CIRCLES. A creature holds ground and so does a
## wagon (see MiracleReach), so a beast walking a cart across the map carries
## two overlapping circles of castable country with it — which is what makes
## leading a settling party different from merely walking somewhere. Everything
## the creature does on the road, it does inside your reach.
##
## It follows your HAND rather than a destination, because the destination is
## the thing you have not decided yet. That is the whole expedition: you go
## looking, the animal comes with the town on its back, and where you stop is
## where the town is. If you leave it standing there for twenty seconds it
## concludes that this was not an expedition after all and puts the cart down.
static func walks_with(who: Creature, delta: float) -> Vector3:
	var alone := float(who.get_meta(ALONE_META, 0.0))
	var hand := who.divine_hand
	if hand != null and is_instance_valid(hand) \
			and hand.global_position.distance_to(who.global_position) < LEADS_FROM:
		who.set_meta(ALONE_META, 0.0)
		return hand.global_position
	alone += delta
	who.set_meta(ALONE_META, alone)
	if alone < SETS_IT_DOWN:
		return who.global_position   # stands where it is, holding the town
	who.set_meta(ALONE_META, 0.0)
	return Vector3.INF


func _init() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	mass = 9.0
	var phys := PhysicsMaterial.new()
	phys.friction = 1.0
	phys.bounce = 0.0
	physics_material_override = phys


func _ready() -> void:
	add_to_group("caravans")
	add_to_group(Affords.PICKABLE)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 1.6, 1.3)
	col.shape = shape
	col.position = Vector3(0, 0.8, 0)
	add_child(col)
	_build_cart()


func _build_cart() -> void:
	var timber := Color(0.5, 0.37, 0.23)
	add_child(Util.lite_box(Vector3(2.0, 0.7, 1.15), timber, Vector3(0, 0.85, 0)))
	# The tilt: a canvas hood over the bed, which is what makes a box read as a
	# wagon at fifty metres with no texture on it.
	add_child(Util.lite_capsule(0.56, 1.8, Color(0.86, 0.83, 0.72),
		Vector3(0, 1.45, 0)))
	for side in [-0.62, 0.62]:
		for along in [-0.66, 0.66]:
			var wheel := Util.lite_cylinder(0.38, 0.12, Color(0.38, 0.28, 0.18),
				Vector3(along, 0.38, side))
			wheel.rotation.x = PI * 0.5
			add_child(wheel)
	# The pole, so it is obvious which end an animal goes on.
	add_child(Util.lite_box(Vector3(1.1, 0.12, 0.12), timber.darkened(0.15),
		Vector3(1.5, 0.5, 0)))


func hover_text() -> String:
	var line := "Wagon out of %s  ·  %d souls, %d timber, %d stone" % [
		from_name, souls, lumber, stone]
	if head > 0:
		line += ", %d head" % head
	return line + "\n(set it down where you want a town)"


func _physics_process(delta: float) -> void:
	Ledger.open(&"Caravan")
	if freeze:
		_settling = 0.0
		_travelled = true
		return  # in the grip, or on the creature's back
	if linear_velocity.length() > STILL_ENOUGH:
		_settling = 0.0
		return
	_settling += delta
	if _settling >= SETTLES_AFTER:
		settle()


## UNPACK, HERE. Checks the ground first, and when the ground will not do it
## says so ONCE and stays a wagon — the answer to "why did nothing happen" has
## to arrive without the player having to ask twice.
func settle() -> void:
	var trouble := _ground_trouble()
	if trouble != "":
		_settling = 0.0
		if _travelled and trouble != _complained:
			_complained = trouble
			GameState.hint(trouble)
			_say_no(trouble)
		return
	var town := Village.new()
	town.is_player_home = false
	town.village_name = _colony_name()
	town.founding = souls
	town.position = global_position
	get_parent().add_child(town)
	# AND WHAT THE WAGON CARRIED, unloaded once the town is standing. It is done
	# from here rather than inside Village._ready so that founding a colony costs
	# Village nothing but a single number.
	if town.store != null and is_instance_valid(town.store):
		town.store.plant_food += food
		town.store.lumber += lumber
		town.store.stone += stone
	_unload_stock(town)
	GameState.announce("%s is founded — %d souls out of %s." % [
		town.village_name, souls, from_name])
	GameState.shift_alignment(2.0)
	# THEY CAME WITH YOUR FAITH ALREADY, and this is the door rather than the
	# `converted` flag: `change_belief` is what runs the conversion proper, with
	# its announcement, its gold totem and the runes a new flock teaches you.
	# Setting the flag by hand gave you a village that believed and a totem that
	# had never heard of it.
	town.change_belief(Village.CONVERT_BELIEF + 10.0)
	queue_free()


## WHAT A COLONY IS CALLED. Its mother's name and a numeral, which is how
## colonies have always been named and carries the lineage for free: three
## wagons out of Elsmere give you Elsmere II, III and IV, and a wagon out of
## Elsmere III still reads its root as Elsmere.
func _colony_name() -> String:
	var root: String = from_name.split(" ")[0]
	var nth := 1
	for v in get_tree().get_nodes_in_group("village"):
		var town := v as Village
		if town != null and is_instance_valid(town) \
				and town.village_name.begins_with(root):
			nth += 1
	return "%s %s" % [root, NUMERALS[mini(nth, NUMERALS.size() - 1)]]


## THE WAGON'S OWN ANSWER, over its head, where the player is already looking.
## A hint at the foot of the screen is the right place for a rule and the wrong
## place for "not here" — by the time you have read it you have stopped looking
## at the thing that said it.
func _say_no(why: String) -> void:
	var said := Util.status_label(NOT_HERE, 0.016)
	said.position = Vector3(0, 2.6, 0)
	said.modulate = Color(1.0, 0.92, 0.7)
	add_child(said)
	set_meta("refused", why)
	var fade := create_tween()
	fade.tween_interval(SAYS_NO_FOR)
	fade.tween_property(said, "modulate:a", 0.0, 0.8)
	fade.tween_callback(said.queue_free)


func _unload_stock(town: Village) -> void:
	var pen := town.pen_position()
	for i in stock.size():
		var beast := Animal.create(stock[i])
		beast.tamed_by = town
		town.add_child(beast)
		var turn := TAU * float(i) / maxf(float(stock.size()), 1.0)
		beast.global_position = pen + Vector3(cos(turn), 0.0, sin(turn)) * 2.2
		town.on_tamed_gained(beast)


## WHY THIS GROUND WILL NOT TAKE A TOWN, or "" when it will.
##
## THE WHOLE FOOTPRINT, not the spot the wheels are on. A wagon set down on the
## one dry rock in a marsh passed every test and founded a town whose houses,
## fields and pen were all underwater — `village_site_dry` rings out to the
## radius a settlement actually occupies, which is the question that was meant
## to be asked. The slope is sampled the same way: flat here and a cliff eight
## metres on is not a place to unload a wagon.
func _ground_trouble() -> String:
	var here := global_position
	for v in get_tree().get_nodes_in_group("village"):
		var town := v as Village
		if town == null or not is_instance_valid(town):
			continue
		if town.global_position.distance_to(here) < CLEAR_OF_TOWNS:
			return "Too near %s — a colony wants its own country." % town.village_name
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return ""
	if not world.village_site_dry(here.x, here.z, FOOTPRINT):
		return "There is water across this ground — carry it further in."
	if _roughest(world, here) > STEEPEST:
		return "Too broken to unload a wagon — find flatter ground."
	return ""


## THE WORST SLOPE ANYWHERE UNDER THE TOWN THAT WOULD STAND HERE. One reading
## at the wheels says nothing about the field forty paces off.
func _roughest(world: WorldGen, here: Vector3) -> float:
	var worst := world.slope_at(here.x, here.z)
	for ring: float in [FOOTPRINT * 0.5, FOOTPRINT]:
		for i in SLOPE_PROBES:
			var turn := TAU * float(i) / float(SLOPE_PROBES)
			worst = maxf(worst, world.slope_at(
				here.x + cos(turn) * ring, here.z + sin(turn) * ring))
	return worst
