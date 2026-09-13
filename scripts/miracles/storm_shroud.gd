class_name StormShroud
extends Node3D
## THE CREATURE WEARS THE WEATHER.
##
##   S  |  )  (spiral)  (rev)    water + force + ward + air + calm
##
## The second five-rune working, and it is the opposite of the eyes in every
## way that matters. Water, force and air is the thunderstorm the god already
## knows how to call down on a place. `ward` puts it round something instead —
## held over it, carried with it — and `calm` is what keeps it IN THE SKY: a
## storm with calm in it rumbles and flashes and never picks anyone out.
##
## So the creature walks in its own weather. Rain falls off it. The cloud over
## its head talks to itself in sheet lightning, cloud to cloud, all of it
## staying up where it started, and the thunder rolls rather than cracks.
##
## AND BECAUSE IT IS REAL RAIN, it does what rain does. Every fire it passes
## goes out — a beast can walk a burning wood cold — and every field it crosses
## is watered. That is the whole of its teeth for now, on purpose: it is a
## storm that has been told to keep its hands to itself, and the version of it
## that has NOT been told that is a different working with a different price.

## How long it holds, and how much longer a strong working keeps it.
const SECONDS := 45.0
const SECONDS_PER_POTENCY := 20.0
const GRANTED_WITHIN := 60.0

## How wide the weather is round the beast, plus a share of its own size — a
## creature the size of a tower wears a bigger storm than a hatchling does.
const SHROUD := 11.0
const SHROUD_PER_SIZE := 0.55

## How often the rain actually DOES anything (douse, water). The falling water
## is continuous to look at and periodic to the world, which is what keeps a
## forty-five second storm from sweeping every group in the game every frame.
const WORK_EVERY := 0.7
## What one working of the rain is worth to a field under it. Modest: this is a
## storm that follows somebody about for a minute, not a cloudburst.
const BLESS := 3.0

## THE SHEET LIGHTNING. How often a flash goes off, how many bars one flash
## draws between the clouds, and how long a bar hangs.
const FLASH_EVERY_LEAST := 0.5
const FLASH_EVERY_MOST := 2.2
const BARS_LEAST := 2
const BARS_MOST := 5
const BAR_HOLD := 0.14
const BAR_BORE := 0.3
## Where the bars live: the slab of air the cloud occupies, over its head.
const DECK := 13.0
const DECK_DEEP := 4.0

## And the rumble that follows. Quiet and long — thunder that never comes down
## is thunder heard from underneath it.
const RUMBLE_LEAST := 1.6
const RUMBLE_MOST := 5.0
const RUMBLE_LOUD := -9.0

const LIT := Color(0.86, 0.90, 1.0)
const GLOW := Color(0.72, 0.80, 1.0)

## How often the village is impressed all over again by the sight of it.
const AWE_EVERY := 9.0
const AWE_PAY := 3.4


var creature: Creature = null
var left := 0.0

var _cloud: StormCloud = null
var _drops: CPUParticles3D = null
var _flash: OmniLight3D = null
var _until_work := 0.0
var _until_flash := 0.0
var _until_rumble := 0.0
var _until_awe := AWE_EVERY


## PUT IT ON. Cast again to hold it longer rather than to wear two.
static func grant(who: Creature, seconds: float) -> StormShroud:
	var worn := holding(who)
	if worn != null:
		worn.left = maxf(worn.left, seconds)
		return worn
	var shroud := StormShroud.new()
	shroud.creature = who
	shroud.left = seconds
	who.add_child(shroud)
	return shroud


static func holding(who: Creature) -> StormShroud:
	for child in who.get_children():
		if child is StormShroud:
			return child as StormShroud
	return null


func _ready() -> void:
	# TOP LEVEL, and it has to be. The creature grows to fifteen times its own
	# size, and Godot scales a child with its parent — a storm parented into
	# that transform would be a puff of drizzle on a hatchling and a county-wide
	# weather system on a grown beast, from the same numbers.
	top_level = true
	_build()


func _build() -> void:
	_cloud = StormCloud.new()
	add_child(_cloud)
	# BREWED, not merely set. `severity` is an argument to brew(), which is what
	# actually builds the sheets and the MultiMesh — assigning the field alone
	# leaves a cloud with no layers in it, which is to say no cloud.
	_cloud.brew(1.3)

	_drops = CPUParticles3D.new()
	_drops.amount = Quality.particles(220)
	_drops.lifetime = 1.2
	_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drops.emission_box_extents = Vector3(SHROUD * 0.5, 0.2, SHROUD * 0.5)
	_drops.direction = Vector3.DOWN
	_drops.initial_velocity_min = 8.0
	_drops.initial_velocity_max = 11.0
	_drops.gravity = Vector3(0, -12, 0)
	_drops.mesh = Util.speck_mesh(0.05, 0.55, Color(0.7, 0.8, 1.0, 0.6))
	add_child(_drops)

	_flash = OmniLight3D.new()
	_flash.light_color = GLOW
	_flash.light_energy = 0.0
	_flash.omni_range = 40.0
	_flash.shadow_enabled = false
	add_child(_flash)


func _physics_process(delta: float) -> void:
	if creature == null or not is_instance_valid(creature):
		queue_free()
		return
	left -= delta
	if left <= 0.0:
		GameState.announce("The storm round your creature thins, and blows out.")
		if is_instance_valid(_cloud):
			_cloud.disperse()
			_cloud.reparent(get_tree().current_scene)
		queue_free()
		return
	_follow()
	_tick_flash(delta)
	_tick_rumble(delta)
	_tick_work(delta)
	_tick_awe(delta)


## The weather goes where it goes. Everything is placed in world space off the
## creature's own position, so it drifts with the beast rather than snapping.
func _follow() -> void:
	var here := creature.global_position
	global_position = here
	var over := here + Vector3.UP * (DECK + creature.scale.y * 2.0)
	if is_instance_valid(_cloud):
		_cloud.global_position = over
	if is_instance_valid(_drops):
		_drops.global_position = over - Vector3.UP * DECK_DEEP
		_drops.emission_box_extents = Vector3(_reach() * 0.5, 0.2, _reach() * 0.5)


func _reach() -> float:
	return SHROUD + creature.scale.x * SHROUD_PER_SIZE


## CLOUD TO CLOUD, and it never comes down. Each flash is a few short bars
## struck between random points in the slab of air overhead — sheet lightning
## seen from below, which is a storm showing you what it could do.
func _tick_flash(delta: float) -> void:
	if is_instance_valid(_flash):
		_flash.light_energy = maxf(_flash.light_energy - delta * 22.0, 0.0)
	_until_flash -= delta
	if _until_flash > 0.0:
		return
	_until_flash = randf_range(FLASH_EVERY_LEAST, FLASH_EVERY_MOST)
	var over := creature.global_position + Vector3.UP * (DECK + creature.scale.y * 2.0)
	var span := _reach()
	for i in randi_range(BARS_LEAST, BARS_MOST):
		var a := over + Vector3(randf_range(-span, span), randf_range(-DECK_DEEP, DECK_DEEP),
			randf_range(-span, span))
		var b := over + Vector3(randf_range(-span, span), randf_range(-DECK_DEEP, DECK_DEEP),
			randf_range(-span, span))
		_strike_between(a, b)
	if is_instance_valid(_flash):
		_flash.global_position = over
		_flash.light_energy = randf_range(3.5, 7.0)


func _strike_between(a: Vector3, b: Vector3) -> void:
	var span := a.distance_to(b)
	if span < 0.5:
		return
	var bar := BoxMesh.new()
	bar.size = Vector3(BAR_BORE, BAR_BORE, span)
	var arc := Util.mesh_node(bar, LIT, a.lerp(b, 0.5), true)
	get_tree().current_scene.add_child(arc)
	arc.look_at(b, Util.steady_up(arc.global_position, b))
	get_tree().create_timer(BAR_HOLD).timeout.connect(arc.queue_free)


## Thunder that never came down is heard from underneath: long, low, and often.
func _tick_rumble(delta: float) -> void:
	_until_rumble -= delta
	if _until_rumble > 0.0:
		return
	_until_rumble = randf_range(RUMBLE_LEAST, RUMBLE_MOST)
	SoundBank.play_at("boom", creature.global_position, RUMBLE_LOUD)


## AND IT IS REAL RAIN. The same rain the sky drops, through the same door, so
## it feeds and douses exactly what falling water feeds and douses — the herd
## mass included, which is where nearly all the animals in the world are.
func _tick_work(delta: float) -> void:
	_until_work -= delta
	if _until_work > 0.0:
		return
	_until_work = WORK_EVERY
	var manager := MiracleManager.of(get_tree())
	if manager != null:
		manager.rain_upon(creature.global_position, _reach(), BLESS)


## A GOD'S BEAST WALKING IN ITS OWN THUNDERSTORM. There is no miracle going off
## for the village to witness — that is the whole point of it — so the awe comes
## through the same door every other wordless wonder does. See VillageWonder.
func _tick_awe(delta: float) -> void:
	_until_awe -= delta
	if _until_awe > 0.0:
		return
	_until_awe = AWE_EVERY
	VillageWonder.spectacle(get_tree(), "shroud", "wonder", creature.global_position,
		AWE_PAY, "Your creature walks in a storm of its own. Nobody is working.", creature)
	creature.heart.stir("pride", 0.2)
