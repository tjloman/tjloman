class_name Herd
extends Node3D
## A HERD IS WHAT THE WORLD SIMULATES. The beasts in it are mostly numbers.
##
## The world was empty, and the reason was arithmetic. Every chunk scattered
## about one and a fifth beasts and stopped at four, so a 336-metre window of
## forest held fifty-eight animals and a stretch of highland held seven. A god
## game wants herds on the ridge. Herds are not four.
##
## But a herd cannot be a hundred CharacterBody3Ds. An Animal runs physics every
## frame and thinks once a second, and reindeer roll 2d100 — an average of a
## hundred and one head, nearly twice everything the world used to hold, in a
## single herd. So the HERD is the unit of simulation: it has a position, a
## heading and a purpose, and its members are rows of numbers that keep
## formation around it, drawn as ONE MultiMesh however many of them there are.
##
## Only the few head nearest the camera become real Animals — the ones you can
## pick up and throw, the ones a wolf can actually chase, the ones that can be
## butchered. That few is a fixed budget, so a herd of two hundred costs very
## nearly what a herd of twenty costs. The rest are a shape on the hillside,
## which is what they are to the player anyway until they are close enough to
## matter.
##
## EVERY PER-FRAME COST HERE IS BOUNDED BY A CONSTANT, not by the head count.
## Ground heights are re-sampled a slice at a time, round-robin, because
## `height_at` is noise plus a scar walk and two hundred of those a frame would
## undo the whole point of the exercise.

## HOW MANY COME AT ONCE, as dice: [how many, how many sides, flat bonus].
##
## These are the numbers the design asks for, kept as a table precisely so they
## can be argued with later without touching any code. Bison and elk herd in
## life; they are listed as solitary here because that is what was asked for,
## and changing one's mind about that is a one-line edit.
const SOCIAL := {
	# THE GREAT HERDS.
	"ox": [7, 10, 0],          # cattle: 7-70, the rolling dice of a full herd
	"reindeer": [2, 100, 0],   # 2-200, and they really do gather like that
	"sheep": [3, 10, 0],
	"deer": [2, 8, 0],
	"llama": [2, 6, 0],
	"giraffe": [1, 6, 1],
	"horse": [1, 8, 1],
	"chicken": [2, 6, 0],
	"pig": [1, 6, 0],
	"frog": [1, 4, 0],
	# PACKS AND PREDATORS. A wolf pack is a real society; the big cats and the
	# bear travel in ones and twos and threes.
	"wolf": [1, 18, 6],        # 7-24
	"lion": [1, 6, 0],
	"tiger": [1, 6, 0],
	"bear": [1, 6, 0],
	"dog": [1, 2, 0],
	# THE SOLITARY ONES, who keep their own company.
	"anteater": [1, 1, 0],
	"coati": [1, 1, 0],
	"bison": [1, 1, 0],
	"elk": [1, 1, 0],
}

## THE SEAM BETWEEN NUMBER AND ANIMAL, in both directions. HerdMotion's motion
## names are ModelAnimator's semantic states, so a grazing member becomes a
## grazing animal and back again without anybody visibly changing their mind.
const AS_STATE := {
	"graze": Animal.State.GRAZE,
	"walk": Animal.State.WANDER,
	"run": Animal.State.FLEE,
	"play": Animal.State.WANDER,
	"idle": Animal.State.IDLE,
	"sleep": Animal.State.IDLE,
}
const AS_MOTION := {
	Animal.State.GRAZE: "graze",
	Animal.State.GO_FORAGE: "graze",
	Animal.State.WANDER: "walk",
	Animal.State.FLEE: "run",
	Animal.State.CHASE: "run",
	Animal.State.GO_DRINK: "walk",
	Animal.State.DRINKING: "graze",
	Animal.State.IDLE: "idle",
}

## HOW CLOSE A BEAST MUST BE to stop being a number and become an animal, and
## how far it must wander back out before it is demoted again. The gap between
## the two is not fussiness: without it a beast hovering exactly on the line
## would be built and freed on alternate frames.
const PROMOTE_WITHIN := 40.0
const DEMOTE_BEYOND := 54.0

## ROOM PER HEAD, in metres. The spread grows as the square root of the count so
## that a herd of two hundred is a wide dark mass rather than two hundred beasts
## standing in each other.
const SPACING := 2.3
const SPREAD_LEAST := 3.0

## How often the whole formation is rewritten, and how many ground heights are
## re-sampled per tick. Both are constants, and that is the point.
const SHUFFLE_EVERY := 0.2
const GROUNDS_PER_TICK := 12

## WHAT SHARE OF THE HERD ANSWERS A CHANGE OF MOOD, and how fast the answer
## crosses them.
##
## Not all of them, and not quickly. A herd does not switch: some of it looks
## up, and the rest goes on eating. Four head in ten answer any one change, and
## they are picked at random rather than in a block, so a mood that persists
## converts the mass in waves instead of throwing a switch over it — and a herd
## that is alarmed twice is visibly more alarmed than a herd alarmed once.
##
## Five a tick puts about three and a third seconds between the first head
## coming up and the last, on a big herd. An earlier version crossed the whole
## herd in under a second and it was wrong: it read as one animal with two
## hundred bodies.
const REDEAL_SHARE := 0.4
const REDEAL_PER_TICK := 5

## A HERD IS A POPULATION, not a number that was rolled once.
##
## The dice say how many come over the hill on the day the world is made. What
## happens to them afterwards is the part that matters, because a herd that can
## only ever shrink is scenery with a countdown on it. This is a meat wall: the
## thing wolves grow fat on, the thing a village eats through the winter, the
## thing a creature can drive home, butcher for sport, or — by planting bushes
## and keeping the wolves off it — grow into something enormous.
##
## CAPACITY IS A MULTIPLE OF THE HERD THE LAND FIRST PRODUCED. The dice already
## encode how rich a place is for a species: highland that threw two hundred
## reindeer is highland that can feed two hundred reindeer. So the ceiling starts
## just under the birth size — a herd left entirely alone drifts down, which is
## what makes tending it mean something — and every bush within reach lifts it.
const SEASON := 40.0
const CARRY_BARE := 0.85
const CARRY_PER_BUSH := 0.14
const CARRY_MOST := 3.0
const FORAGE_REACH := 34.0

## How much of itself a fed, unfrightened herd adds in a season, and how long
## the memory of being hunted holds that down. Fear is not decoration: a herd
## being worked by wolves does not calve, so predation costs a herd far more
## than the beasts actually taken.
const BREED := 0.16
const FEAR_PER_LOSS := 0.22
const FEAR_FADE := 0.34

## WHAT A PREDATOR GETS OUT OF IT. Kills bank against the pack's own next head:
## a wolf pack living off fat cattle becomes a bigger wolf pack, which is the
## whole reason the meat wall is worth defending.
const FED_PER_HEAD := 4.0

## A PREDATOR'S CEILING IS MEAT, NOT BERRIES. Bushes are the lever for a grazing
## herd and mean nothing to a wolf, so a pack's capacity rides on how well it
## has been eating lately instead. The larder fades every season, which is what
## closes the loop in both directions: a pack beside a fat herd swells, and a
## pack that has eaten the herd out starves back down to what is left. Without
## the fade, predators would only ever ratchet upward.
const LARDER_PER_MEAL := 0.05
const LARDER_FADE := 0.30

## How far a herd drifts from where it was seeded, and how long it grazes one
## patch before moving on.
const ROAM := 26.0
const GRAZE_LEAST := 14.0
const GRAZE_MOST := 34.0

## HOW MANY HEAD ARE REAL ANIMALS ANYWHERE IN THE WORLD. Static on purpose: a
## per-herd count would let every herd spend the whole budget, and twenty-five
## herds each promoting two dozen head is six hundred CharacterBody3Ds — which
## is the exact thing this class exists to prevent. Only herds near the camera
## promote at all, so in practice two or three are ever bidding for it, but a
## budget that is only respected in practice is not a budget.
static var _agents_afoot := 0

var species := ""
var world: WorldGen = null
var head := 0

## WHAT THE HERD IS DOING, as one word. It is the herd that has a mood, not the
## beast: the mood decides the PROPORTIONS in which its members are dealt their
## motions, and those proportions are what make a mass of boxes read as a herd
## rather than as a formation. See HerdMotion.MOODS.
var mood := "graze"

var _members: Array[Dictionary] = []
var _mm: MultiMesh = null
var _mmi: MultiMeshInstance3D = null
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _graze_left := 0.0
var _shuffle_left := 0.0
var _ground_cursor := 0
var _spread := 0.0
var _redeal_left := 0
var _born_head := 0
var _fear := 0.0
var _fed := 0.0
var _larder := 0.0
var _season_left := 0.0


## Roll the head count for a species. Public so the seeding code and the smoke
## tests can ask the same question the herd asks itself.
static func roll_for(species_name: String, rng: RandomNumberGenerator) -> int:
	var dice: Array = SOCIAL.get(species_name, [1, 1, 0])
	var total: int = dice[2]
	for i in int(dice[0]):
		total += rng.randi_range(1, int(dice[1]))
	return maxi(total, 1)


static func create(species_name: String, count: int, home: WorldGen) -> Herd:
	var h := Herd.new()
	h.species = species_name
	h.head = maxi(count, 1)
	h.world = home
	return h


func _ready() -> void:
	add_to_group("herds")
	_home = global_position
	_target = _home
	_spread = maxf(SPACING * sqrt(float(head)), SPREAD_LEAST)
	_born_head = head
	_season_left = randf() * SEASON     # herds do not all reckon on the same frame
	_build_members()
	_build_multimesh()
	_shuffle_left = randf() * SHUFFLE_EVERY


## Each member is a standing offset from the herd's heart plus a slow private
## sway, so the mass breathes instead of moving as one welded sheet.
func _build_members() -> void:
	for i in head:
		var a := randf() * TAU
		# Square-rooted radius, or every herd is a ring with a hollow middle.
		var r := sqrt(randf()) * _spread
		_members.append({
			"offset": Vector2(cos(a) * r, sin(a) * r),
			# TWO SMALL INTEGERS ARE THE WHOLE ANIMATION STATE of a member:
			# which motion it is playing and which phase offset it plays it at.
			# Everything else is looked up from a table HerdMotion builds once
			# a tick for the entire world. See that file for why.
			"motion": HerdMotion.draw_motion(mood, randf()),
			"slot": randi() % HerdMotion.SLOTS,
			"facing": randf() * TAU,
			# Started at the herd's own ground rather than at zero, and refined
			# by the round-robin afterwards. Sampling two hundred heights in the
			# frame a chunk loads would be a visible hitch, and the difference
			# across a herd's width is a step, not a storey.
			"ground": global_position.y,
			"agent": null,
			"dead": false,
		})


func _build_multimesh() -> void:
	var spec: Dictionary = Animal.SPECIES[species]
	var body: Vector3 = spec["body"]
	var leg: float = spec["leg"]
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	# One box for the whole beast. At the distance these are seen from, legs are
	# a few pixels of nothing, and one instance per head is the entire budget.
	_mm.mesh = Util._pooled_box_mesh(Vector3(body.x, body.y, body.z))
	_mm.instance_count = head
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = Util.shared_mat(spec["color"])
	_mmi.position = Vector3(0, leg + body.y * 0.5, 0)
	add_child(_mmi)
	Util.apply_lod(_mmi, Quality.camera_far())
	_resample_grounds(GROUNDS_PER_TICK * 4)
	_write_transforms()


func _process(delta: float) -> void:
	# The herd itself thinks on the same distance stride everything else does:
	# a herd three hundred metres off does not need its formation rewritten
	# sixty times a second, or indeed five.
	var stride := Util.sim_stride(global_position)
	_graze_left -= delta
	if _graze_left <= 0.0:
		_pick_pasture()
	_season_left -= delta
	if _season_left <= 0.0:
		_season_left = SEASON
		_reckon()
	_drift(delta)
	_shuffle_left -= delta
	if _shuffle_left <= 0.0:
		_shuffle_left = SHUFFLE_EVERY * stride
		_resample_grounds(GROUNDS_PER_TICK)
		_redeal(REDEAL_PER_TICK)
		_write_transforms()
		_tend_agents()


## WHERE THE HERD IS HEADED. Grazing is not wandering: a herd settles on a patch
## and works it over before moving, which is why the interval is long and the
## step is short.
func _pick_pasture() -> void:
	_graze_left = randf_range(GRAZE_LEAST, GRAZE_MOST)
	var a := randf() * TAU
	var r := sqrt(randf()) * ROAM
	var want := _home + Vector3(cos(a) * r, 0.0, sin(a) * r)
	# Never graze out into the water, and never onto a bank so steep the mass
	# would be half-buried in it.
	if world != null and world.is_underwater(want.x, want.z):
		return
	_target = want


func _drift(delta: float) -> void:
	var spec: Dictionary = Animal.SPECIES[species]
	var pace: float = spec["speed"] * 0.18      # grazing, not running
	var to := _target - global_position
	to.y = 0.0
	if to.length() < 0.5:
		# Arrived. Heads go down, and the mix of motions changes with them.
		set_mood("graze")
		return
	set_mood("move")
	global_position += to.normalized() * minf(pace * delta, to.length())


## Ground heights, a slice at a time. `height_at` is noise plus a walk over
## every scar in range, and calling it for two hundred head every tick would
## cost more than the animals it is standing in for.
func _resample_grounds(how_many: int) -> void:
	if world == null or _members.is_empty():
		return
	for i in mini(how_many, _members.size()):
		var m := _members[_ground_cursor % _members.size()]
		var p := global_position + Vector3(m["offset"].x, 0.0, m["offset"].y)
		m["ground"] = world.height_at(p.x, p.z)
		_ground_cursor += 1


func _write_transforms() -> void:
	if _mm == null:
		return
	# ONE TABLE FOR THE WHOLE WORLD, built by whichever herd ticks first this
	# frame. Everything below is a lookup and some adds — no trigonometry runs
	# per member, which is the difference between a herd of two hundred costing
	# what a herd of twenty costs and it costing ten times as much.
	HerdMotion.refresh(float(Time.get_ticks_msec()) * 0.001)
	var here := global_position
	for i in _members.size():
		var m := _members[i]
		# Collapsed to nothing in two cases: a real Animal is standing here
		# instead, or this one was eaten. Scaling the instance away beats
		# rebuilding the MultiMesh, which would mean reallocating it every time
		# anybody walked past a herd or a wolf took one.
		if m["agent"] != null or m["dead"]:
			_mm.set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))
			continue
		var p: Vector4 = HerdMotion.pose(m["motion"], m["slot"])
		var off: Vector2 = m["offset"]
		var turn := Basis.from_euler(Vector3(p.y, float(m["facing"]) + p.w, p.z))
		_mm.set_instance_transform(i, Transform3D(turn, Vector3(
			off.x, float(m["ground"]) - here.y + p.x, off.y)))
		_mm.set_instance_color(i, Color(1, 1, 1))


## THE MOOD CHANGED, so everybody is dealt a new motion — but NOT all in the
## same frame. A herd startling is a ripple that crosses it, and re-dealing the
## whole formation at once looks like a switch being thrown. Members are re-dealt
## a slice at a time on the same round-robin the ground heights ride.
func set_mood(to: String) -> void:
	if to == mood:
		return
	mood = to
	# Only a share answers, and a change arriving mid-ripple ADDS to what is
	# still outstanding rather than replacing it — two alarms in quick
	# succession should move more of the herd than one, not restart the count.
	_redeal_left = mini(_redeal_left + ceili(_members.size() * REDEAL_SHARE),
		_members.size())


func _redeal(how_many: int) -> void:
	if _redeal_left <= 0 or _members.is_empty():
		return
	for i in mini(how_many, _redeal_left):
		# Picked at random, not walked in order: a block of neighbours all
		# changing together is a wipe across the formation, which is exactly
		# the tell that gives away that these are not animals.
		var m := _members[randi() % _members.size()]
		if not m["dead"]:
			m["motion"] = HerdMotion.draw_motion(mood, randf())
		_redeal_left -= 1


## PROMOTION. The handful of head nearest the camera become real beasts, up to
## the device's budget; the rest stay numbers. Demotion runs first so a herd
## walking past you hands its budget on rather than hoarding it.
func _tend_agents() -> void:
	var focus := GameState.camera_focus
	var budget := Quality.herd_agents()
	for i in _members.size():
		var m := _members[i]
		var agent: Animal = m["agent"]
		if agent == null:
			continue
		if not is_instance_valid(agent) or agent.is_queued_for_deletion():
			# Eaten, butchered, or thrown into the sea. It does not come back,
			# and the herd is one head smaller for good — and frightened,
			# whatever it was that took it.
			m["agent"] = null
			m["dead"] = true
			lost_one()
			_agents_afoot -= 1
			continue
		# Keep the row in step with where the animal actually walked to, so
		# demoting it does not teleport it back into formation.
		var local := agent.global_position - global_position
		m["offset"] = Vector2(local.x, local.z)
		m["ground"] = agent.global_position.y
		if agent.global_position.distance_to(focus) > DEMOTE_BEYOND:
			# And hands back what it was doing, so the seam is silent in both
			# directions: a beast that ran off keeps running as a number.
			m["motion"] = AS_MOTION.get(agent.state, mood if mood != "move" else "walk")
			agent.queue_free()
			m["agent"] = null
			_agents_afoot -= 1
	for i in _members.size():
		if _agents_afoot >= budget:
			return
		var m := _members[i]
		if m["agent"] != null or m["dead"]:
			continue
		var p := global_position + Vector3(m["offset"].x, 0.0, m["offset"].y)
		p.y = float(m["ground"])
		if p.distance_to(focus) > PROMOTE_WITHIN:
			continue
		var born := Animal.create(species)
		born.global_position = p
		# Parented to the world, not to the herd: it is a free animal now, and
		# if it runs off it should not be dragged about by the formation.
		get_parent().add_child(born)
		born.global_position = p
		# IT CARRIES ON DOING WHAT IT WAS DOING. Without this a grazing member
		# stands up and wanders the moment it crosses forty metres, which is a
		# visible seam exactly where the player is closest and most likely to
		# be looking. The motion names are ModelAnimator's own vocabulary, so
		# the far pose and the near clip are the same word.
		born.state = AS_STATE.get(m["motion"], Animal.State.IDLE)
		# THE WAY HOME. A promoted beast carries a handle on the herd it came
		# from, so a kill can be credited to the killer's pack and charged to
		# the victim's — which is the whole food chain in one reference.
		born.set_meta("herd", self)
		m["agent"] = born
		_agents_afoot += 1


## How many head are still standing, promoted or not — what the herd would tell
## you if you asked how big it was.
func alive() -> int:
	var n := 0
	for m in _members:
		if not m["dead"]:
			n += 1
	return n


## THE SEASON TURNS. The herd counts what the land will feed it, how frightened
## it is, and how many of it there are, and grows or dwindles accordingly.
##
## Logistic, not linear: growth falls away as the herd approaches what the
## ground can carry, so a tended herd settles at its ceiling instead of running
## off to infinity, and a thin herd on good ground comes back fast.
func _reckon() -> void:
	_fear = maxf(_fear - FEAR_FADE, 0.0)
	_larder *= 1.0 - LARDER_FADE
	var n := alive()
	if n <= 0:
		queue_free()          # the last of them went; the herd is not a thing
		return
	var ceiling := capacity()
	var room := 1.0 - float(n) / maxf(ceiling, 1.0)
	var calm := 1.0 - clampf(_fear, 0.0, 1.0)
	var change := BREED * float(n) * room * calm
	# Over its ceiling the herd thins whether it is calm or not — hunger does
	# not care how safe you feel — so the calm factor only ever helps growth.
	if room < 0.0:
		change = BREED * float(n) * room
	var whole := int(change)
	# The fraction is a chance rather than a rounding, or a herd of six with a
	# gain of 0.4 head a season would never breed at all.
	if randf() < absf(change - float(whole)):
		whole += 1 if change > 0.0 else -1
	if whole > 0:
		_grow(whole)
	elif whole < 0:
		_cull(-whole)


## WHAT THE GROUND WILL FEED, in head. Bushes in reach are the lever the player
## and the creature actually have: plant them and the ceiling rises, and the
## herd fills the room over the following seasons.
func capacity() -> float:
	# A hunting herd is fed by what it catches, and counting bushes for a wolf
	# pack was simply the wrong question — it capped a pack at what the berries
	# nearby would support.
	if Animal.SPECIES[species].get("predator", false):
		var fat := clampf(CARRY_BARE + _larder * LARDER_PER_MEAL, 0.2, CARRY_MOST)
		return maxf(float(_born_head) * fat, 1.0)
	var bushes := 0
	for b in get_tree().get_nodes_in_group("forage"):
		var bush := b as Node3D
		if is_instance_valid(bush) and bush.global_position.distance_to(
				global_position) < FORAGE_REACH:
			bushes += 1
	var mult := clampf(CARRY_BARE + float(bushes) * CARRY_PER_BUSH, 0.2, CARRY_MOST)
	return maxf(float(_born_head) * mult, 1.0)


func _grow(many: int) -> void:
	for i in many:
		# A calf slots into the formation with the rest, and starts out doing
		# what calves do — see HerdMotion's `young` mix.
		var a := randf() * TAU
		var r := sqrt(randf()) * _spread
		_members.append({
			"offset": Vector2(cos(a) * r, sin(a) * r),
			"motion": HerdMotion.draw_motion("young", randf()),
			"slot": randi() % HerdMotion.SLOTS,
			"facing": randf() * TAU,
			"ground": global_position.y,
			"agent": null,
			"dead": false,
		})
	head = _members.size()
	_spread = maxf(SPACING * sqrt(float(alive())), SPREAD_LEAST)
	if _mm != null:
		_mm.instance_count = _members.size()
		_write_transforms()


## Starvation takes the ones with nobody promoted into them first, so a beast
## the player is watching is never quietly deleted out from under them.
func _cull(many: int) -> void:
	var taken := 0
	for m in _members:
		if taken >= many:
			break
		if m["dead"] or m["agent"] != null:
			continue
		m["dead"] = true
		taken += 1


## SOMETHING TOOK ONE. However it went — wolf, villager, creature, or a god in
## a temper — the herd is one smaller and it is frightened, and a frightened
## herd does not calve. Cruelty therefore costs a herd far more than the beast.
func lost_one() -> void:
	_fear = minf(_fear + FEAR_PER_LOSS, 1.0)


## A PREDATOR ATE. Kills bank toward the pack's own next head, which is how a
## wolf pack living beside fat cattle becomes a bigger wolf pack.
func fed_on(worth: float) -> void:
	_fed += worth
	_larder += worth
	while _fed >= FED_PER_HEAD:
		_fed -= FED_PER_HEAD
		if alive() < int(capacity()):
			_grow(1)


## How wide the mass stands, so anything asking "am I among them" can ask about
## the herd rather than about its centre point.
func spread() -> float:
	return _spread


## DRIVEN. The pasture itself moves, not just the beasts — otherwise they walk
## back the moment the creature stops pushing, and shepherding would be a thing
## you did forever and never finished.
func drive_toward(where: Vector3, step: float) -> void:
	var to := where - _home
	to.y = 0.0
	if to.length() < 0.5:
		return
	_home += to.normalized() * minf(step, to.length())
	_target = _home
	_graze_left = 0.0
	set_mood("move")


## SCATTERED, by a creature that does not know how to drive them yet.
func scattered(fear: float) -> void:
	_fear = minf(_fear + fear, 1.0)
	set_mood("flee")
	# They go somewhere other than where they were being pushed, which is what
	# makes a botched drive cost ground rather than merely gain none.
	var a := randf() * TAU
	_target = _home + Vector3(cos(a), 0.0, sin(a)) * ROAM
	_graze_left = GRAZE_LEAST


## SETTLED, by something standing watch over them.
func calmed(by: float) -> void:
	_fear = maxf(_fear - by, 0.0)
	if _fear < 0.2:
		set_mood("graze")


## ONE TAKEN, cleanly, by something that meant to. Prefers a head nobody is
## promoted into, so a beast the player is watching is not deleted mid-stride.
func take_one() -> bool:
	for m in _members:
		if not m["dead"] and m["agent"] == null:
			m["dead"] = true
			lost_one()
			return true
	return false


## In a word: is it doing well? Read off the same numbers the season uses, so
## the label can never disagree with what is about to happen.
func condition() -> String:
	if _fear > 0.5:
		return "hunted"
	var n := float(alive())
	var ceiling := capacity()
	if n > ceiling * 0.95:
		return "as many as the land will feed"
	if n < ceiling * 0.55:
		return "thin"
	return "thriving"


func hover_text() -> String:
	return "A herd of %d %s — %s" % [alive(), species, condition()]
