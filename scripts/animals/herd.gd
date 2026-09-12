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
## can be argued with later without touching any code — which is exactly what
## happened to bison and elk, who began here as solitary and are now the small
## bands they are in life. That was two lines.
const SOCIAL := {
	# THE GREAT HERDS.
	"ox": [7, 10, 0],          # cattle: 7-70, the rolling dice of a full herd
	"caribou": [2, 100, 0],    # 2-200 wild, and they really do gather like that
	# The domestic one comes from a village taming caribou, not from the world,
	# so its dice only matter if one is ever loosed again.
	"reindeer": [1, 4, 0],
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
	# THE SMALL BANDS. Neither a great herd nor a lone animal — a bison mob or a
	# few elk together, which is what both actually do.
	"bison": [2, 8, 0],        # 2-16
	"elk": [3, 2, 0],          # 3-6, and tight
	# THE NEAR-SOLITARY. One, or now and then a pair — nothing in the world is
	# strictly alone any more, and that is right: even the animals that keep
	# their own company turn up two at a time often enough to notice.
	"anteater": [1, 2, 0],
	"coati": [1, 2, 0],
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

## How often the formation is stirred, and how much of it moves per tick. Both
## are constants, and that is the point — nothing in this file may scale with
## the head count.
const SHUFFLE_EVERY := 0.2
const GROUNDS_PER_TICK := 12
## How many instances are rewritten per stir. Sized for the WORST CASE THAT IS
## ACTUALLY LOOKED AT: a big herd you are standing in. At sixty-four a
## four-hundred-head barn refreshed each beast every 1.2 seconds, which steps
## visibly; at this it is under two thirds of a second and reads as movement.
## Distant herds stir on a longer clock anyway, so they cost a fraction of this.
const WRITES_PER_TICK := 128
## How far the herd's own origin may drift in height before the whole formation
## is rewritten rather than a slice of it. Instance heights are relative to that
## origin, so a herd walking uphill would otherwise leave half its members
## buried until their turn came round.
const DRIFT_REWRITE := 0.4

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

## WHAT A HERD NOTICES, and how often it looks up.
##
## It noticed NOTHING before this. `scattered` and `lost_one` were only ever
## called from outside, so a pack could walk to the edge of a grazing herd and
## stand there, and the herd went on eating until something died. That is the
## one thing a herd animal is actually for.
##
## Looking is deliberately slow and deliberately short-sighted. A herd is not a
## radar: it catches what is close, it is slower to notice than a predator is to
## approach, and the whole scan is over the `herds` group — a few dozen nodes —
## on a timer of its own rather than on the formation tick.
const WATCH_EVERY := 2.5
const NOTICE := 46.0
const BOLT_WITHIN := 22.0
## How much of a fright one pack is, scaled by how many of them there are and
## how close. A lone bear across the meadow is a raised head; a wolf pack at
## twenty metres is the whole herd running.
const DREAD_PER_HEAD := 0.012

## AND WHAT A PACK DOES ABOUT IT. Predators are herds too, and this is the other
## half of the same tick: a pack picks the nearest worthwhile herd and closes on
## it, which is what stalking IS at the scale a herd is simulated at.
const STALK_WITHIN := 90.0
const STALK_STEP := 9.0
## HOW FULL A PACK HAS TO BE BEFORE IT LEAVES OFF. Without this a pack that
## found a herd never stopped following it: wolves outrun cattle, so the gap
## closed to nothing and stayed there, the herd sat at maximum fright for ever
## and never calved again, and every herd a pack ever met was doomed. A fed pack
## lies up instead, which is both true of wolves and the only thing that gives a
## hunted herd its seasons back.
const HUNTS_BELOW := 9.0

## HOW MUCH FASTER A FRIGHTENED HERD MOVES than a grazing one. Grazing pace is a
## fifth of the animal's speed; running is most of it, which is what makes the
## distance a herd opens up actually depend on what it is.
const BOLT_PACE := 0.8
## And how fast a band that has decided to go somewhere moves. Grazing pace is
## a fifth of the animal, which at two hundred metres is a nine-minute walk that
## nobody would ever see finish. A herd travelling to rejoin its own kind is not
## grazing: it is going somewhere, and it looks like it.
const TREK_PACE := 0.45

## JOINING, AND CALVING OFF. A herd is not a fixed thing with a head count that
## only goes up and down — it is a BAND, and bands run together and break apart.
##
## Two motions, opposite and answering each other. A herd cut down to a remnant
## goes looking for its own kind and walks into them, because that is what a
## frightened few actually do. A herd that has filled the ground it stands on
## sheds a small band off itself, which walks away and settles somewhere else —
## and that is how a meadow the creature has planted thick with bushes stops
## being one enormous mass and becomes a country with herds in it.
##
## SMALLNESS ALONE IS NOT LONELINESS. That was the first thing this got wrong:
## a band shed for being crowded is small by definition, so it turned straight
## round and walked back into the herd that shed it, forever. What sends a herd
## looking is being a REMNANT — fewer than it was, few for its kind, and either
## still afraid or on ground that will not feed even the few that are left. A
## young band is small and calm and has room, so it stays where it was put; and
## an anteater, whose kind travels in ones and twos, is never few for its kind
## at all and never goes looking for anybody.
const LONELY_SHARE := 0.35
const JOIN_FEAR := 0.25
const SEEK_WITHIN := 200.0
const SEEK_STEP := 8.0
const JOIN_WITHIN := 4.0
## Never onto ground that cannot feed the pair. A quarter over the ceiling is
## allowed — they crowd, and the season thins them — but a remnant walking into
## an already-full herd only to starve there is not a rescue.
const JOIN_ROOM := 1.25

## WHEN A HERD FEELS CROWDED, and how much of itself goes when it does.
##
## "Too huge" HAS TO MEAN TOO HUGE FOR ITS KIND. A flat head count was tried
## first and it was wrong in a way worth writing down: at forty head, sixteen of
## the twenty species in the table could never split however well they were
## tended, because a mob of bison tops out at sixteen and a band of elk at six.
## Twice what a band of this kind usually comes to is the same question asked
## properly, and it lets a thick, well-fed deer wood throw off deer.
##
## The share that leaves is deliberately small — a band, not a halving — and
## both it and what stays behind must still be a band rather than a stray, which
## is the floor that keeps the near-solitary species out of this entirely.
const CALVE_AT := 0.9
const CALVE_TIMES := 2.0
const CALVE_LEAST := 6
const CALVE_SHARE := 0.25
const CALVE_PARTY := 3
const CALVE_WALK := 90.0
## How many bands of one kind the country round here will hold. Counted during
## the look-about, which was walking the herd list anyway, so it costs nothing.
## This is what bounds the whole business: bands fill the neighbourhood and then
## no more are shed, rather than a rich meadow budding herds without end.
const KIN_MOST := 3
## And how long a herd is left alone after joining or shedding, in seconds.
const SETTLE := 240.0

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

## WHOSE THEY ARE. A herd with a keeper is a BARN'S herd: village livestock,
## not wildlife. It does not flee, it does not stalk, nothing hunts it into the
## ground, and its ceiling is the stalls its village has built rather than the
## bushes it can reach. Everything else — the formation, the motions, the
## promotion of the nearest few into real animals — is identical, which is the
## whole reason a barn can hold four hundred head for what forty used to cost.
var keeper: Village = null

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
var _write_cursor := 0
var _written_y := 0.0
var _spread := 0.0
var _redeal_left := 0
var _born_head := 0
var _fear := 0.0
var _fed := 0.0
var _larder := 0.0
var _season_left := 0.0
var _watch_left := 0.0
## WHAT THE LAST LOOK ROUND FOUND OF THEIR OWN KIND, kept so the season's
## reckoning can ask about the neighbourhood without walking the herd list a
## second time. `_joining` is a DECISION, not an observation: once a herd has
## settled on somebody to walk to it does not change its mind, which is what
## makes joining something that actually finishes.
var _kin: Herd = null
var _kin_gap := INF
var _kin_near := 0
var _joining: Herd = null
var _settle_left := 0.0


## Roll the head count for a species. Public so the seeding code and the smoke
## tests can ask the same question the herd asks itself.
static func roll_for(species_name: String, rng: RandomNumberGenerator) -> int:
	var dice: Array = SOCIAL.get(species_name, [1, 1, 0])
	var total: int = dice[2]
	for i in int(dice[0]):
		total += rng.randi_range(1, int(dice[1]))
	return maxi(total, 1)


## WHAT A BAND OF THIS KIND USUALLY COMES TO, read off the same dice the world
## rolls rather than kept as a second table — so an argument about how many
## wolves travel together only ever has to be had in one place. This is what
## "small for its kind" is measured against, and it is why an anteater, whose
## kind comes one or two at a time, is never small for its kind at all.
static func typical_for(species_name: String) -> float:
	var dice: Array = SOCIAL.get(species_name, [1, 1, 0])
	return float(dice[0]) * (float(dice[1]) + 1.0) * 0.5 + float(dice[2])


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
	# NO PER-INSTANCE COLOUR. Every beast in a herd is the same species and so
	# the same colour, which the shared material already says; the channel was
	# being written white once per member per tick and cost a Color of memory
	# each. It comes back the day something has to look different — a branded
	# beast, a sick one — and not before.
	# THE SPECIES' OWN MODEL, if the project has one for it. A herd is one mesh
	# drawn many times over, so the low-poly beast costs exactly what the box
	# cost — and the seam between a numbered member and the real Animal standing
	# next to it stops being the difference between a sheep and a crate.
	#
	# The model keeps its own material: overriding it with the species colour is
	# right for a box and wrong for anything with a texture on it. And it sits
	# at the herd's own origin, because a model's pivot is at its FEET (the
	# models README asks for that, and Animal adds its custom model at the body
	# origin on the same understanding) — while the box has to be lifted by half
	# its height plus the legs it does not have.
	_mm.instance_count = head
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	var model := ModelBank.mesh_for(species)
	if model != null:
		_mm.mesh = model
	else:
		# One box for the whole beast. At the distance these are seen from, legs
		# are a few pixels of nothing, and one instance per head is the budget.
		_mm.mesh = Util._pooled_box_mesh(Vector3(body.x, body.y, body.z))
		_mmi.material_override = Util.shared_mat(spec["color"])
		_mmi.position = Vector3(0, leg + body.y * 0.5, 0)
	add_child(_mmi)
	Util.apply_lod(_mmi, Quality.camera_far())
	_resample_grounds(GROUNDS_PER_TICK * 4)
	_write_transforms()          # in full: nothing is on screen until it is


func _process(delta: float) -> void:
	# The herd itself thinks on the same distance stride everything else does:
	# a herd three hundred metres off does not need its formation rewritten
	# sixty times a second, or indeed five.
	var stride := Util.sim_stride(global_position)
	_graze_left -= delta
	if _graze_left <= 0.0:
		_pick_pasture()
	_watch_left -= delta
	if _watch_left <= 0.0:
		_watch_left = WATCH_EVERY * float(stride)
		_look_about()
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
		# THE GROUND MOVED UNDER THEM. Instance heights are stored relative to
		# the herd's own origin, so walking up a hill leaves every un-rewritten
		# member floating or buried until its turn comes round. Past a stride of
		# drift the whole formation is rewritten at once — which is rare, because
		# a grazing herd moves at about a fifth of a metre a second.
		if absf(global_position.y - _written_y) > DRIFT_REWRITE:
			_write_transforms()
		else:
			_write_transforms(WRITES_PER_TICK)
		_tend_agents()


## LOOKING UP. Prey herds find whatever is hunting nearby and answer it; packs
## find whatever is worth hunting and go towards it. One scan serves both,
## because a herd and a pack are the same object asking opposite questions.
func _look_about() -> void:
	if alive() <= 0 or keeper != null:
		return          # penned stock neither bolts nor hunts
	var hunter: bool = Animal.SPECIES[species].get("predator", false)
	var closest: Herd = null
	var gap := INF
	var kin: Herd = null
	var kin_gap := INF
	var near := 0
	for h in get_tree().get_nodes_in_group("herds"):
		var other := h as Herd
		if other == self or not is_instance_valid(other) or other.alive() <= 0:
			continue
		var d := other.global_position.distance_to(global_position) - other.spread()
		# THEIR OWN KIND, noted whether this herd wants company or not. The count
		# is what tells a crowded herd whether there is room in the country round
		# here for another band of them, and both answers come out of the walk
		# over the herd list that was happening anyway.
		if other.species == species:
			if other.keeper == null:
				if d < SEEK_WITHIN:
					near += 1
				if d < kin_gap:
					kin_gap = d
					kin = other
			continue
		var theirs: bool = Animal.SPECIES[other.species].get("predator", false)
		if hunter == theirs:
			continue          # packs ignore packs; grazers ignore grazers
		if hunter and not _worth_hunting(other):
			continue
		if d < gap:
			gap = d
			closest = other
	_kin = kin
	_kin_gap = kin_gap
	_kin_near = near
	_go_join()
	if closest == null:
		return
	if hunter:
		_stalk(closest, gap)
	else:
		_take_fright(closest, gap)


## WALKING TO THE OTHERS. A herd that has decided to join does not change its
## mind: its pasture keeps moving toward them until it gets there, or until
## there is nobody left to get to. It is the same motion a pack uses to close on
## prey and for the same reason — the herd's HOME moves, not merely the beasts,
## or they would turn round and wander back the moment they stopped walking.
func _go_join() -> void:
	if _joining == null:
		return
	if not is_instance_valid(_joining) or _joining.is_queued_for_deletion() \
			or _joining.alive() <= 0 or _joining.keeper != null:
		_joining = null
		return
	var gap := _joining.global_position.distance_to(global_position) \
			- _joining.spread() - spread()
	if gap < JOIN_WITHIN:
		_join_into(_joining)
		return
	if gap > SEEK_WITHIN * 1.5:
		_joining = null           # they have gone too far to be worth following
		return
	# The same motion a creature uses to drive them, which is the right one: the
	# pasture itself creeps toward the others and STOPS on them rather than
	# sliding straight past, and the mass walks after it at its own pace.
	drive_toward(_joining.global_position, SEEK_STEP)


## AND ARRIVING. Whichever band is smaller is the one that walks in and stops
## existing — deterministically, so two herds that decided about each other on
## the same afternoon cannot each swallow the other.
func _join_into(host: Herd) -> void:
	if host.alive() > alive() or (host.alive() == alive()
			and host.get_instance_id() > get_instance_id()):
		host.merge_from(self)
		# LET GO OF THE ROWS RATHER THAN KILLING THEM. merge_from appends the
		# very same dictionaries to the host, so marking them dead here would
		# have marked them dead THERE — every beast that had just walked in
		# would have died on arrival. Dropping the array instead leaves alive()
		# reading zero for anything still holding this herd, which is what the
		# rest of the file already checks for.
		_members = []
		head = 0
		if _mm != null:
			_mm.instance_count = 0
		queue_free()
	else:
		_joining = null           # the other one is the one that should be walking


## TAKEN IN. Another band of the same kind walks up and is simply part of this
## one afterwards.
##
## Beasts that are real animals at that moment keep the ground they are standing
## on — their offset is re-reckoned against this herd's heart and their handle on
## the way home is repointed, so nothing the player is actually looking at jumps.
## The rest are numbers, and numbers are dealt fresh places in the joined
## formation, which is what makes two masses read afterwards as one herd rather
## than as two clumps that happen to be touching.
func merge_from(other: Herd) -> void:
	var shift := other.global_position - global_position
	for m in other.taken_over():
		if m["dead"]:
			continue
		var agent: Animal = m["agent"]
		if agent != null and is_instance_valid(agent):
			agent.set_meta("herd", self)
			m["offset"] += Vector2(shift.x, shift.z)
		else:
			var ang := randf() * TAU
			var rad := sqrt(randf()) * _spread
			m["offset"] = Vector2(cos(ang) * rad, sin(ang) * rad)
			m["ground"] = global_position.y
		_members.append(m)
	# THE BETTER GROUND OF THE TWO. Both numbers mean "what this species got out
	# of country like this", and taking the larger is what stops a rescue from
	# being punished: two remnants that join should not immediately be over a
	# ceiling neither of them was over apart.
	_born_head = maxi(_born_head, other.born_head())
	head = _members.size()
	_spread = maxf(SPACING * sqrt(float(alive())), SPREAD_LEAST)
	_settle_left = SETTLE
	if _mm != null:
		_mm.instance_count = _members.size()
		_write_transforms()


## The rows themselves, handed over to the herd this one is walking into. Only
## ever called by merge_from, on a herd that is about to stop existing.
func taken_over() -> Array[Dictionary]:
	return _members


## What the land this herd came up on was worth, in head.
func born_head() -> int:
	return _born_head


## A pack only bothers with what it actually eats. The prey list is the same one
## a single Animal hunts from, so a wolf pack and a wolf want the same things.
func _worth_hunting(prey: Herd) -> bool:
	var eats: Array = Animal.SPECIES[species].get("prey", [])
	return eats.has(prey.species)


## CLOSING. The pack's pasture moves toward the herd, which means its members
## drift that way and its promoted beasts arrive with prey in front of them —
## hunting at the scale a herd is simulated at, without a second set of rules.
func _stalk(prey: Herd, gap: float) -> void:
	if gap > STALK_WITHIN or gap < 2.0:
		return
	if _larder >= HUNTS_BELOW:
		return          # fed. It lies up rather than working a herd it cannot eat.
	var to := prey.global_position - global_position
	to.y = 0.0
	if to.length() < 0.5:
		return
	_home += to.normalized() * STALK_STEP
	_target = _home
	_graze_left = GRAZE_MOST
	set_mood("move")


## NOTICING. Nearer and more numerous is worse; past a point they simply go. The
## fright itself is what suppresses breeding, so a herd worked by a pack that
## never catches anything still pays for being hunted.
func _take_fright(pack: Herd, gap: float) -> void:
	if gap > NOTICE:
		return
	var dread := float(pack.alive()) * DREAD_PER_HEAD * (1.0 - gap / NOTICE)
	_fear = minf(_fear + dread, 1.0)
	if gap < BOLT_WITHIN:
		set_mood("flee")
		# Away, not anywhere: a herd that bolts toward the wolves is a herd
		# nobody will believe.
		var away := global_position - pack.global_position
		away.y = 0.0
		if away.length() < 0.5:
			away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
		_target = global_position + away.normalized() * ROAM
		_graze_left = GRAZE_LEAST
	else:
		set_mood("alert")


## WHERE THE HERD IS HEADED. Grazing is not wandering: a herd settles on a patch
## and works it over before moving, which is why the interval is long and the
## step is short.
func _pick_pasture() -> void:
	_graze_left = randf_range(GRAZE_LEAST, GRAZE_MOST)
	if keeper != null:
		return          # a barn says where its stock stands, not the stock
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
	# Grazing is a stroll; bolting is most of what the animal can do. A herd that
	# fled at grazing pace was a herd that could never open any distance at all.
	var pace := 0.18
	if mood == "flee":
		pace = BOLT_PACE
	elif _joining != null:
		pace = TREK_PACE
	var step: float = spec["speed"] * pace
	var to := _target - global_position
	to.y = 0.0
	if to.length() < 0.5:
		# Arrived. Heads go down, and the mix of motions changes with them.
		set_mood("graze")
		return
	set_mood("move")
	global_position += to.normalized() * minf(step * delta, to.length())


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


func _write_transforms(how_many := 0) -> void:
	if _mm == null or _members.is_empty():
		return
	# ONE TABLE FOR THE WHOLE WORLD, built by whichever herd ticks first this
	# frame. Everything below is a lookup and some adds — no trigonometry runs
	# per member, which is the difference between a herd of two hundred costing
	# what a herd of twenty costs and it costing ten times as much.
	HerdMotion.refresh(float(Time.get_ticks_msec()) * 0.001)
	# A SLICE, ROUND-ROBIN, unless somebody asked for the lot. This was the last
	# thing in here that still scaled with the head count: four hundred head
	# meant four hundred transform writes several times a second, and a barn
	# holding twelve hundred meant six thousand a second. Now it is a constant,
	# and what it costs a herd of twelve hundred is what it costs a herd of
	# twelve.
	#
	# What that buys is paid for in ANIMATION RATE, and only for the far mass: a
	# big herd's individuals bob more slowly because each one is rewritten less
	# often. That is invisible at the distance a four-hundred-head herd is seen
	# from, and the beasts close enough to look at are promoted to real animals
	# with real clips anyway.
	var todo := _members.size() if how_many <= 0 else mini(how_many, _members.size())
	var here := global_position
	for step in todo:
		var i := (_write_cursor + step) % _members.size()
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
	_write_cursor = (_write_cursor + todo) % _members.size()
	_written_y = here.y


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
		# NEVER OUT OF SOMEBODY'S HAND. A beast that is held or in flight is the
		# one beast the player is certainly paying attention to, and demotion
		# frees the node — so a sheep carried or thrown past the demote range
		# simply vanished from the hand that was holding it. It is also the one
		# beast whose distance from the camera means nothing about whether it
		# matters.
		if agent.state == Animal.State.HELD or agent.state == Animal.State.FALLING:
			continue
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
		# A BARN'S BEAST COMES BACK TAMED. Promotion has to restore what the
		# animal WAS, or every time you walked up to the barn its stock would
		# turn feral in front of you.
		if keeper != null and is_instance_valid(keeper):
			born.tamed_by = keeper
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


## GOING. A herd leaves when its chunk unloads, and it takes its promoted
## beasts with it — they are parented to that same chunk, not to the herd.
##
## The agent budget is a STATIC count for the whole world, so every one of those
## had to be handed back, and nothing handed them back. The count only ever went
## one way: stand near three or four herds, walk away from them, and the world
## has spent its entire allowance on animals that no longer exist. Nothing
## anywhere promotes again for the rest of the session — and a herd that cannot
## promote is a picture. It has no collider, so the hand's raycast goes straight
## through it: no mouse-over, nothing to pick up. It puts no Animal in the
## "animals" group, so nobody hunts it, tames it or herds it. And the only thing
## left to see is the MultiMesh, which is why the beasts stopped wearing their
## models. All of that from a counter that never came down.
func _exit_tree() -> void:
	for m in _members:
		if m["agent"] != null:
			m["agent"] = null
			_agents_afoot -= 1
	# The beasts are going too — freed with the chunk — so this is a release of
	# SLOTS, not a demotion, and it does not care whether the node is still valid.
	_agents_afoot = maxi(_agents_afoot, 0)


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
	_consider_company()


## AND THEN: DOES IT WANT COMPANY, OR ROOM?
##
## Both questions are asked once a season and never per frame, and both are
## answered out of numbers the look-about gathered anyway. A herd that has just
## done either is left alone for a while afterwards, which is the thing that
## stops a band being shed and rejoined and shed again for ever.
func _consider_company() -> void:
	if keeper != null:
		return          # a village's stock joins nothing and splits nowhere
	if _settle_left > 0.0:
		_settle_left -= SEASON
		return
	if _joining != null:
		return          # already walking to somebody
	if _wants_company():
		if _kin != null and is_instance_valid(_kin) and _kin_gap < SEEK_WITHIN \
				and float(alive() + _kin.alive()) <= _kin.capacity() * JOIN_ROOM:
			_joining = _kin
		return
	if _wants_room() and _kin_near < KIN_MOST:
		_calve_off()


## SMALL FOR ITS KIND, FEWER THAN IT WAS, AND STILL IN TROUBLE.
##
## All three, and the three are not decoration. Small alone would send a band
## that had just been shed for crowding straight back into the herd that shed
## it. Fewer-than-it-was is what makes this a REMNANT rather than a species that
## simply travels in small numbers — an anteater is never few for its kind and a
## bear that was rolled alone was never reduced to it. And the last is the part
## that makes it mean something: a herd goes looking for the others because it
## is frightened, or because the ground it is left on will not feed even the few
## of it that are still standing.
func _wants_company() -> bool:
	var n := alive()
	if n >= _born_head:
		return false
	if float(n) >= typical_for(species) * LONELY_SHARE:
		return false
	return _fear > JOIN_FEAR or float(n) >= capacity()


## FULL. As many as this ground will feed, and enough of them that a band coming
## off it is still a band.
func _wants_room() -> bool:
	var n := float(alive())
	return n >= float(CALVE_LEAST) and n >= typical_for(species) * CALVE_TIMES \
			and n >= capacity() * CALVE_AT


## SHEDDING A BAND. A quarter of the herd walks off to found another one.
##
## The daughter inherits what the land was worth, not the handful that walked:
## `_born_head` means "what this species gets out of country like this", and the
## band is going to country like this. Founding it on the eight head that left
## would put it over its ceiling on the day it was born, and it would starve
## back down to nothing while the herd it came from went on filling up.
func _calve_off() -> void:
	var n := alive()
	var many := maxi(int(float(n) * CALVE_SHARE), CALVE_PARTY)
	if n - many < CALVE_PARTY:
		return
	var away := _spot_for_band()
	if is_inf(away.x):
		return
	var band := Herd.create(species, many, world)
	band.position = position + (away - global_position)
	get_parent().add_child(band)
	# After the child is in the tree, because _ready reads its own head count as
	# the land's worth and would otherwise overwrite both of these.
	band.founded_by(_born_head, SETTLE)
	# The same machinery starvation uses, and for the same reason: it takes the
	# rows nobody is promoted into first, so a beast the player is watching
	# never vanishes out from under them to join a band over the hill.
	_cull(many)
	_settle_left = SETTLE


## WHERE THE NEW BAND GOES: away from the nearest of their own kind, so the
## country fills outward rather than stacking bands on one hill. Returns an
## infinite point when every direction tried was water.
func _spot_for_band() -> Vector3:
	var base := randf() * TAU
	if _kin != null and is_instance_valid(_kin):
		var off := global_position - _kin.global_position
		if Vector2(off.x, off.z).length() > 1.0:
			base = atan2(off.z, off.x)
	for i in 5:
		var ang := base + randf_range(-0.6, 0.6) + float(i) * 1.1
		var spot := global_position + Vector3(cos(ang), 0.0, sin(ang)) * CALVE_WALK
		if world == null:
			return spot
		if world.is_underwater(spot.x, spot.z):
			continue
		spot.y = world.height_at(spot.x, spot.z)
		return spot
	return Vector3(INF, INF, INF)


## HOW A BAND SHED BY ANOTHER HERD IS SET UP, once it is in the tree.
func founded_by(land_worth: int, settle: float) -> void:
	_born_head = maxi(land_worth, head)
	_settle_left = settle


## WHAT THE GROUND WILL FEED, in head. Bushes in reach are the lever the player
## and the creature actually have: plant them and the ceiling rises, and the
## herd fills the room over the following seasons.
func capacity() -> float:
	# PENNED STOCK IS LIMITED BY THE BARN AND NOTHING ELSE. Counting bushes for
	# a village's livestock would be the same error as counting them for a wolf:
	# these animals are fed from the store by people whose job that is.
	if keeper != null and is_instance_valid(keeper):
		return float(Workshop.stalls(keeper))
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


## TAKEN IN. A real animal becomes a row of numbers: the node goes, the head
## count stays. This is the whole of the barn's trick — a village that keeps
## four hundred beasts is not running four hundred bodies, it is running one
## herd and a budget, exactly as the wild ones do.
func absorb(beast: Animal) -> void:
	if not is_instance_valid(beast):
		return
	if beast.tamed_by != null:
		beast.tamed_by.on_tamed_lost(beast)
	_grow(1)
	_members[_members.size() - 1]["ground"] = beast.global_position.y
	beast.queue_free()


## PICKED UP. A beast in a god's hand has left the herd.
##
## It used to stay a member, and the herd went on treating its row as part of
## the formation — so carrying one home stretched the herd across the map, with
## the mass drawing an instance wherever the beast had been put down, and
## setting it down two hundred metres away left a lone box standing in a field
## belonging to a herd on the far side of the valley.
##
## So it is released outright: the row goes, the slot goes back to the budget,
## and what is left in the hand is an ordinary animal that happens to have come
## out of a herd. The herd is one head down and frightened by it, which is the
## same reckoning as anything else being taken from them — a hand reaching out
## of the sky and lifting one away is not a thing they shrug off.
func release(beast: Animal) -> void:
	for m in _members:
		if m["agent"] == beast:
			m["agent"] = null
			m["dead"] = true
			_agents_afoot = maxi(_agents_afoot - 1, 0)
			break
	if beast.has_meta("herd"):
		beast.remove_meta("herd")
	lost_one()
	_spread = maxf(SPACING * sqrt(float(alive())), SPREAD_LEAST)


## AND ONE TAKEN OUT FOR THE TABLE, without ever building it. A butcher does
## not need the animal to exist to get meat off it.
func slaughter() -> int:
	if alive() <= 0:
		return 0
	take_one()
	return int(Animal.SPECIES[species].get("meat", 1))


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
	if _joining != null and is_instance_valid(_joining):
		return "looking for the others"
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
