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
	#
	# TWENTY-FOUR WOLVES IS TRUE AND UNPLAYABLE. It was set from what wolves
	# actually do, and a pack that size is not a threat in a game, it is a
	# weather event: it takes a village apart before anybody can be sent to meet
	# it, and there is no answer to it that is not a miracle. 2d4 is four or
	# five wolves, which a militia can lose to and can also beat — which is the
	# only size a threat is worth having.
	"wolf": [2, 4, 0],         # 2-8
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
## How far off a herd's name still draws. See `_build_multimesh`.
const HERD_TAG_REACH := 180.0
## How many head it takes before the number over them is worth reading. Below
## this you are looking at animals, not at a herd. See `_retag`.
const TAG_WORTH_IT := 3
## THE HAND'S OWN RESERVE. How near counts as under it, and how many heads it
## may make real regardless of the world's allowance. See `_reach_of_the_hand`.
const HAND_REACH := 6.0
const HAND_TAKES := 3
## How far past its own nominal spread a herd's members may actually be standing
## before the hand stops looking. See `_reach_of_the_hand`.
const SPREAD_SLACK := 2.5

## HOW FAR A HEAD MAY STAND FROM ITS OWN HERD'S HEART before it stops being part
## of that herd and founds its own.
##
## NOTHING EVER PULLED A STRAYED ROW HOME. A row's offset is dealt once and then
## only ever pushed OUTWARD: a gust blows rows downwind (`blown`), and a
## promoted animal that walked off and was demoted keeps wherever it actually
## got to (`_tend_agents`). `_redeal` re-rolls what a row is DOING and never
## where it stands. So over an evening a hunted, harried herd grows a scatter of
## outliers standing a hundred metres from the mass, and they are the ones the
## player finds and cannot pick up: the hand's reach gives up on the whole herd
## at one generous span check before it ever looks at the rows, and no span
## measured off the heart can cover a head that far out.
##
## Widening that check is the wrong fix twice over — it would make every herd in
## the world answer the hand from far away, and it would leave the thing still
## drawn as part of a herd it is plainly not with. A beast a hundred metres from
## the herd IS NOT IN THE HERD. It is a herd.
##
## THE LIMIT IS NOT A NUMBER OF ITS OWN. It is `hand_span()` less the hand's own
## reach — the shedding is defined as "further out than this herd will answer
## for", so the two can never disagree. Written as an independent constant first
## (twenty-six metres, which sounded reasonable), and tools/herd_stray.py showed
## that making things WORSE: a small herd answers the hand within about fourteen
## metres, so a tolerance of twenty-six left every remnant carrying strays it
## would not reach, and the daughters it shed inherited the same hole.
##
## How close two strays must be to found a herd TOGETHER rather than one apiece,
## as a share of the SMALLEST span any herd has. A newborn band of one or two
## head answers the hand within about fourteen metres, so gathering strays from
## further than that founds a herd that cannot reach its own members on the day
## it is born. Same trap, one level down.
const STRAY_GATHER_SHARE := 0.75
## How far off the middle the heart has to be before it is worth moving. Below
## this it is noise, and rewriting every instance transform for noise is the
## sort of thing that costs a frame on a phone. See `_recentre`.
const RECENTRE_LEAST := 1.0
const PROMOTE_WITHIN := 40.0
const DEMOTE_BEYOND := 54.0
## HOW MANY ROWS ARE LOOKED AT per tick when a herd is near enough to be worth
## looking at. A constant, like everything else per-frame in this file: the herd
## in front of you fills the world's whole agent budget several times over
## inside a second, and the one beast under the player's cursor is promoted by
## `_reach_of_the_hand` on the spot regardless.
const PROMOTES_SCANNED := 32

## ROOM PER HEAD, in metres. The spread grows as the square root of the count so
## that a herd of two hundred is a wide dark mass rather than two hundred beasts
## standing in each other.
const SPACING := 2.3
const SPREAD_LEAST := 3.0

## How often the formation is stirred, and how much of it moves per tick. Both
## are constants, and that is the point — nothing in this file may scale with
## the head count.
const SHUFFLE_EVERY := 0.35
## HOW MANY HEADS GET THEIR GROUND RE-READ per shuffle, at rest — and how far
## the herd may WALK before every one of them has had it re-read.
##
## A flat twelve was the bug. The ground under a member changes because the HERD
## MOVED, so a fixed count means a two-hundred-head herd takes seventeen
## shuffles — four seconds at a stride of one, twelve at a stride of three — to
## come round, and every head is drawn at the height of wherever it was standing
## four to twelve seconds ago. On anything but a billiard table that is a herd
## sunk to the knees in a hillside and popping out of it, which is exactly what
## it looked like.
##
## So the sweep is paid for by DISTANCE now. Standing still it costs the old
## twelve; walking, it costs whatever keeps every head within GROUND_DRIFT of
## the truth, capped so a stampede cannot run away with the frame.
const GROUNDS_PER_TICK := 12
const GROUND_DRIFT := 0.7
const GROUNDS_MOST := 96
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

## ONE HUNGER FOR THE WHOLE HERD -------------------------------------------
##
## Not one per beast. A hundred and sixty appetites is a hundred and sixty
## numbers to carry, decrement and compare, to say a thing the player can only
## ever see about the mass anyway: they are being fed, or they are not. So the
## herd is hungry, and every beast in it is exactly as hungry as the herd.
##
## It rises every season and comes down when somebody fills the trough (see
## Drove, and `fed`). What it costs is growth first and head second: a hungry
## herd does not calve, and a starving one thins — which is the honest answer
## to a barn that had grown to a hundred and sixty head beside twelve hungry
## villagers. Stock eat the town's grain now. A herd too big for its village
## empties the granary and then becomes a herd the village can feed.
const HUNGER_PER_SEASON := 0.16
const HUNGER_MOST := 1.6
## Above this it is not hunger, it is starvation, and a share of them go.
const STARVES_ABOVE := 1.0
const STARVE_SHARE := 0.07

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
const WATCH_EVERY := 4.0
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
## HOW MANY HEAD OF ONE KIND THE COUNTRY ROUND HERE WILL HOLD, counting every
## band of them together.
##
## `capacity()` is a ceiling on ONE HERD, worked from what that herd was
## founded at and what forage it can reach — so two herds standing in the same
## meadow each grew to their own full size and the meadow carried twice what
## either of them thought it could. Three bands, three times. KIN_MOST bounds
## how many bands may be SHED into a neighbourhood and does nothing whatever
## about how big the ones already there get.
##
## This is the other half: the grass is finite and it does not care how the
## mouths eating it are grouped. Counted over the same walk of the herd list
## the look-about was making anyway, so it costs nothing.
const HEAD_NEAR_MOST := 90
## Over how wide a piece of country. Tighter than SEEK_WITHIN, which is how far
## a herd will WALK to find company — this is how far it eats.
const GRAZED_WITHIN := 120.0
## And how long a herd is left alone after joining or shedding, in seconds.
const SETTLE := 240.0

## FIRE IN A HERD.
##
## Every miracle in the game reached a herd's promoted few and nothing else,
## because a miracle looks through the "animals" group and a herd puts at most a
## couple of dozen head in it however many hundred it holds. So a fireblast
## thrown into two hundred caribou killed the handful that happened to be real
## and the other hundred and seventy-six did not so much as look up. The mass is
## the herd; if the mass cannot be burned then burning a herd is a trick of the
## camera angle.
##
## Members are counted WHERE THEY ACTUALLY STAND — each one's own offset against
## the blast — so a herd standing half in the fire loses half of itself and no
## more. Nothing here is a share or a guess.
##
## And they run from it whatever it did to them. Fleeing reaches much further
## out than burning does: an animal that can see fire goes, which is both true
## and the thing that makes a gout thrown at the edge of a herd worth throwing.
const BURN_SECONDS := Animal.BURN_SECONDS
const FIRE_FLEES := 4.0
const FIRE_FEAR := 0.55

## BEING BLOWN ABOUT. How much of the wind's speed a beast is thrown at, and
## how much lift goes with it so it leaves the ground rather than skidding.
##
## HOW FAR A NUMBERED HEAD GOES IS NOT A SEPARATE NUMBER. It is worked out from
## exactly the throw a real beast gets — the same speed, over the same time in
## the air — because they are standing in the same wind and the player is
## looking at both at once. Tuned apart, they disagreed badly: the mass slid
## ten metres downwind while the bodies beside it flew two, so the herd appeared
## to outrun the animals in it.
##
## The scatter is the only part that varies, and it exists because a mass that
## moves exactly together slides like one sheet of ice.
const BLOWN_THROW := 0.6
const BLOWN_LIFT := 3.5
const BLOWN_SCATTER_LEAST := 0.7
const BLOWN_SCATTER_MOST := 1.4

## How far a herd drifts from where it was seeded, and how long it grazes one
## patch before moving on.
## HOW A HERD SPENDS ITS DAY. Almost all of it standing still with its head
## down — which is what cattle do, and what a fourteen-second grazing window
## emphatically was not: a herd picked a new pasture three times a minute, so
## every herd in the world was walking almost all of the time, and walking is
## where the whole cost is (a route probe, a drift step, a formation rewrite and
## a ground resample, per herd, per tick).
##
## Grazing is nearly free by comparison. Nothing here changes what a herd DOES
## when something happens to it — a startled herd still bolts on the same frame
## it hears the thing — it only stops them milling about for no reason.
const ROAM := 18.0
const GRAZE_LEAST := 90.0
const GRAZE_MOST := 260.0
## How far a member turns toward the herd's heading each time its row is
## rewritten, and how far off true it settles so a moving herd still reads as
## animals rather than as a formation.
const TURN_TAKE := 0.22
const LEAN_OFF := 0.09

## HOW MANY HEAD ARE REAL ANIMALS ANYWHERE IN THE WORLD. Static on purpose: a
## per-herd count would let every herd spend the whole budget, and twenty-five
## herds each promoting two dozen head is six hundred CharacterBody3Ds — which
## is the exact thing this class exists to prevent. Only herds near the camera
## promote at all, so in practice two or three are ever bidding for it, but a
## budget that is only respected in practice is not a budget.
## THE BUDGET, AND WHY IT IS RECONCILED RATHER THAN TRUSTED.
##
## This was a one-way counter kept by hand: every promotion added one, every
## demotion, death, butchering, drowning, chunk unload and herd teardown was
## supposed to take one back, and each of those is a separate line in a separate
## place. Miss ONE of them, once, and the world's entire allowance is spent on
## animals that no longer exist — for the rest of the session, because nothing
## ever counted it again. The symptom is exact and was reported exactly: a herd
## you are standing over with none of it grabbable, and one or two heads
## becoming real only as a miracle kills others and hands their slots back.
##
## A counter that can only be wrong in one direction and never checks itself is
## not a budget, it is a leak with a limit. So each herd knows how many of its
## OWN rows have a living body in them — recomputed from the rows themselves,
## in a loop `_tend_agents` was already walking — and the global figure is the
## sum of those, taken fresh before anybody spends. That is one integer read per
## herd in the world, and it makes the whole class of bug impossible rather than
## fixing the instance of it.
static var _agents_afoot := 0

## HOW MANY HEAD ARE VISIBLE AT ONCE, or -1 for all of them. Set by whoever
## keeps the herd — a wild one is never told, and shows everybody. A barn tells
## its stock how many it has let out into the yard, and tells them none while
## they are in. The rest go on eating, breeding and being butchered from the
## book; they are simply not standing in the road. See Workshop.
var shown := -1

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
## HOW HUNGRY THEY ALL ARE — one number, shared. Zero is fed. See the note by
## HUNGER_PER_SEASON for why this is not a field on every beast.
var hunger := 0.0

## WHAT THE HERD IS DOING, as one word. It is the herd that has a mood, not the
## beast: the mood decides the PROPORTIONS in which its members are dealt their
## motions, and those proportions are what make a mass of boxes read as a herd
## rather than as a formation. See HerdMotion.MOODS.
var mood := "graze"

var _members: Array[Dictionary] = []
var _mm: MultiMesh = null
## The name over the herd. See `_build_multimesh`.
var _tag: Label3D = null
var _mmi: MultiMeshInstance3D = null
var _home := Vector3.ZERO
var _target := Vector3.ZERO
## How many of this herd's rows have a real Animal standing in them. See
## `_agents_afoot`.
var _afoot_here := 0
## Which way the mass is travelling, and whether anybody should be coming round
## to it. See `_write_transforms`.
var _heading := 0.0
var _turning := false
## The physics frame this herd last ticked on. See Scheduler.
var _sim_last := 0
var _graze_left := 0.0
var _shuffle_left := 0.0
var _ground_cursor := 0
## Where the herd was when the grounds were last re-read, so the next sweep can
## be sized by how far it has walked since.
var _ground_from := Vector2.ZERO
var _write_cursor := 0
## WHICH ROWS HOLD A REAL BEAST. A candidate list, not a truth: `_promote` is
## the only thing that ever puts an agent in a row so nothing is ever missing,
## and the several things that take one out may leave an index behind, which
## costs one null test and is dropped. See `_tend_the_promoted`.
var _afoot: Array[int] = []
var _promote_cursor := 0
## The `shown` the hidden tail was last put away for, and how far up the book
## the putting away has reached. `_hidden_at` is never a legal value of `shown`
## to begin with and `_hidden_to` is past the end of any book, so the first
## write collapses the whole tail and no write after it collapses twice. See
## `_write_transforms`.
var _hidden_at := -99
var _hidden_to := 1 << 30
var _written_y := 0.0
var _spread := 0.0
var _redeal_left := 0
var _born_head := 0
var _fear := 0.0
var _fed := 0.0
var _larder := 0.0
var _season_left := 0.0
var _watch_left := 0.0
## Members that are alight: rows of {"i": index, "left": seconds}. They are
## running, and in about eight seconds they go down.
var _burning: Array[Dictionary] = []
## WHAT THE LAST LOOK ROUND FOUND OF THEIR OWN KIND, kept so the season's
## reckoning can ask about the neighbourhood without walking the herd list a
## second time. `_joining` is a DECISION, not an observation: once a herd has
## settled on somebody to walk to it does not change its mind, which is what
## makes joining something that actually finishes.
var _kin: Herd = null
var _kin_gap := INF
var _kin_near := 0
## Head of this kind standing within GRAZED_WITHIN, not counting this herd's
## own — the neighbourhood's share of the grass. See HEAD_NEAR_MOST.
var _head_near := 0
var _joining: Herd = null
var _settle_left := 0.0
## How far out this herd's widest living head actually stands. See `hand_span`:
## the hand's early-out is measured against this rather than against a guess.
var _widest := 0.0


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
	# WHAT THEY ARE, said out loud over the herd.
	#
	# `hover_text` has always known — "A herd of 46 reindeer, thriving" — and
	# nothing could ever reach it, because a herd is a MultiMesh and a MultiMesh
	# has no collider for the hand's ray to land on. Only a PROMOTED member is
	# hoverable, and promotion is capped globally at Quality.herd_agents, so a
	# herd standing past PROMOTE_WITHIN, or one that lost the bidding for the
	# budget, is a field of unlabelled boxes with no way to ask what it is. This
	# is a Label3D, so it adds no collider and blocks nothing: the real animals
	# standing inside the herd can still be pointed at and picked up.
	_tag = Util.status_label("", 0.02)
	# FURTHER THAN A VILLAGER'S. `status_label` stops drawing at 34 metres,
	# which is right for a name over somebody's head and wrong for the one
	# label that says what a mass of animals a hundred metres off actually is —
	# a herd is a thing you identify from a distance or not at all.
	_tag.visibility_range_end = HERD_TAG_REACH
	_tag.position = Vector3(0, leg + body.y + 1.4, 0)
	add_child(_tag)
	_retag()
	_resample_grounds(GROUNDS_PER_TICK * 4)
	_write_transforms()          # in full: nothing is on screen until it is


func _process(delta: float) -> void:
	Ledger.open(&"Herd")
	# The herd itself thinks on the same distance stride everything else does:
	# a herd three hundred metres off does not need its formation rewritten
	# sixty times a second, or indeed five.
	#
	# AND IT NOW SKIPS THE FRAMES IT IS NOT DUE, rather than merely doing less
	# on each one. Every timer in here was counted down every single frame and
	# only the WORK was strided, so a world of thirty herds paid thirty drifts,
	# thirty route probes and thirty countdowns sixty times a second whatever
	# the stride said. Scheduler.turn gives each herd its own phase and charges
	# it the frames it missed, so the sums come out identical and the peak does
	# not. See Scheduler.
	var stride := Util.sim_stride(global_position)
	if stride > 1:
		var turn: int = Scheduler.turn(self, stride, _sim_last)
		if turn == 0:
			return
		delta *= float(turn)
	_sim_last = Scheduler.now()
	# ON THE HERD'S OWN TICK, not on the formation shuffle. `_tend_agents` runs
	# every SHUFFLE_EVERY seconds, and a third of a second between putting your
	# hand on a sheep and the sheep existing is the difference between reaching
	# working and reaching sometimes working. Costs one distance check on a herd
	# the hand is nowhere near, which is all of them but one.
	_reach_of_the_hand()
	_graze_left -= delta
	if _graze_left <= 0.0:
		_pick_pasture()
	_watch_left -= delta
	if _watch_left <= 0.0:
		_watch_left = WATCH_EVERY * float(stride)
		_look_about()
		_shed_strays()
	_season_left -= delta
	if _season_left <= 0.0:
		_season_left = SEASON
		_reckon()
	if not _burning.is_empty():
		_tick_burning(delta)
	_drift(delta)
	_shuffle_left -= delta
	if _shuffle_left <= 0.0:
		_shuffle_left = SHUFFLE_EVERY * stride
		_resample_grounds(_grounds_owed())
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
	var head_near := 0
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
				# AND HOW MANY MOUTHS, not just how many bands. See
				# HEAD_NEAR_MOST: the grass does not care how they are grouped.
				if d < GRAZED_WITHIN:
					head_near += other.alive()
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
	_head_near = head_near
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
		var agent := _living(m)
		if agent != null:
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
		_turning = false
		return
	set_mood("move")
	var dir := to.normalized()
	_heading = atan2(dir.x, dir.z)
	_turning = true
	# A HERD MUST NOT WALK INTO A LAKE, and nothing stopped it. `_pick_pasture`
	# checks that the GRAZING SPOT is dry and that is the whole of what was ever
	# checked: the straight line to it can cross a bay, a barn herd is steered
	# by its keeper, and a BOLTING herd sets its target by running directly away
	# from whatever frightened it, with no check at all. So a pig herd fleeing
	# wolves ran into the water, and the wolves followed it in, and both of them
	# stood out there in formation at water level.
	#
	# PROBED AT THE WIDTH OF THE HERD, not of an animal. The mass is `_spread`
	# across; asking whether the ground two metres ahead of its CENTRE is dry
	# tells you nothing about the flanks, which are the parts that end up
	# swimming. And `water_route` walks a body that is already in the water back
	# out of it, which is what recovers the ones already out there.
	if world != null:
		# CAPPED. `_spread` on a two-hundred-head herd is thirty metres, and
		# `_bad_step` looks a second probe-length beyond that again — so an
		# uncapped probe has a herd refusing every heading with water anywhere
		# within sixty metres, which on a coast is all of them, and it then pays
		# the full sixteen-way fallback sweep every time it moves.
		dir = NavField.water_route(self, global_position, dir, world,
			clampf(_spread, 3.0, 12.0))
	global_position += dir * minf(step * delta, to.length())


## Ground heights, a slice at a time. `height_at` is noise plus a walk over
## every scar in range, and calling it for two hundred head every tick would
## cost more than the animals it is standing in for.
## HOW MANY HEAD THIS HERD ACTUALLY SIMULATES.
##
## A wild herd simulates all of itself. A BARN'S BOOK DOES NOT, and the whole
## of why is that `shown` already says so: the barn puts a dozen head in the
## street and keeps the rest inside, and none at all once they are in for the
## night. Everything past that number is a row nobody can see, cannot point at,
## and will not be promoted — and it was being given a ground height several
## times a second, a fresh idea of what it was doing, and an instance transform
## set to zero on top of the zero already there.
##
## A hundred and sixty head in a barn cost a hundred and sixty heads' worth of
## that, for twelve animals of visible result. This is the number that ends it,
## and it is not a new budget — it is the one the barn was already keeping.
func _simulated() -> int:
	if shown < 0:
		return _members.size()
	return mini(shown, _members.size())


## HOW MANY WE OWE THIS SHUFFLE. However far the herd has walked since the last
## one, every head should have been re-read once per GROUND_DRIFT of it.
func _grounds_owed() -> int:
	var moved := Vector2(global_position.x - _ground_from.x,
		global_position.z - _ground_from.y).length()
	_ground_from = Vector2(global_position.x, global_position.z)
	if moved < 0.01:
		return GROUNDS_PER_TICK
	var sweeps := moved / GROUND_DRIFT
	return clampi(int(float(_simulated()) * sweeps),
		GROUNDS_PER_TICK, GROUNDS_MOST)


func _resample_grounds(how_many: int) -> void:
	var live := _simulated()
	if world == null or live <= 0:
		return
	for i in mini(how_many, live):
		var m := _members[_ground_cursor % live]
		var p := global_position + Vector3(m["offset"].x, 0.0, m["offset"].y)
		# SURFACE, not height. `height_at` is the rock; a head standing in a
		# pond was drawn at the bottom of it.
		m["ground"] = world.surface_at(p.x, p.z)
		_ground_cursor += 1


func _write_transforms(how_many := 0) -> void:
	if _mm == null or _members.is_empty():
		return
	# ONE TABLE FOR THE WHOLE WORLD, built by whichever herd ticks first this
	# frame. Everything below is a lookup and some adds — no trigonometry runs
	# per member, which is the difference between a herd of two hundred costing
	# what a herd of twenty costs and it costing ten times as much.
	HerdMotion.refresh(GameState.clock)
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
	# THE TAIL IS PUT AWAY ONCE, AND ONLY THE PART OF IT THAT IS NEW. Every row
	# past `shown` is drawn at zero scale, and the loop below used to walk into
	# them and set that same zero again several times a second — for a barn's
	# book, most of the work in this function was rewriting nothing as nothing.
	#
	# `_hidden_to` is how far the collapse has already reached, so a herd drawn
	# in for the night pays for the rows that just went indoors and not for the
	# hundred already there. It starts past the end of any book, which is what
	# makes the first write collapse the whole tail — once, which is the one
	# time it has to happen.
	var live := maxi(_simulated(), 0)
	if _hidden_at != shown:
		_hidden_at = shown
		for i in range(live, mini(_hidden_to, _members.size())):
			_mm.set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))
		_hidden_to = live
		_write_cursor = 0
	if live <= 0:
		_written_y = global_position.y
		return
	var todo := live if how_many <= 0 else mini(how_many, live)
	var here := global_position
	for step in todo:
		var i := (_write_cursor + step) % live
		var m := _members[i]
		# Collapsed to nothing in two cases: a real Animal is standing here
		# instead, or this one was eaten. Scaling the instance away beats
		# rebuilding the MultiMesh, which would mean reallocating it every time
		# anybody walked past a herd or a wolf took one.
		# ...and a village's stock is mostly INSIDE. A barn's book is four
		# hundred head and four hundred head standing in the street is a town
		# you cannot see, which is what five barns' worth looked like. The
		# number is right and wants keeping; what wants cutting is how many of
		# them are out at once. The barn says how many that is, and says none
		# when it has drawn them in for the night. See `shown`.
		if m["agent"] != null or m["dead"] or (shown >= 0 and i >= shown):
			_mm.set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))
			continue
		var p: Vector4 = HerdMotion.pose(m["motion"], m["slot"])
		var off: Vector2 = m["offset"]
		# WALKING ONE WAY AND POINTING ANOTHER. Every member was dealt a random
		# facing at birth and kept it for life, so a herd crossing a meadow was
		# nine animals travelling due north with three of them side-on and one
		# going backwards. They come round to the herd's heading here, a slice
		# at a time on the round-robin this loop already rides — which makes the
		# turn a ripple through the mass rather than a block snapping about.
		# Each keeps a small lean off true so it stays a herd and not a parade.
		if _turning:
			var lean := (float(int(m["slot"]) % 5) - 2.0) * LEAN_OFF
			m["facing"] = lerp_angle(float(m["facing"]), _heading + lean, TURN_TAKE)
		var turn := Basis.from_euler(Vector3(p.y, float(m["facing"]) + p.w, p.z))
		_mm.set_instance_transform(i, Transform3D(turn, Vector3(
			off.x, float(m["ground"]) - here.y + p.x, off.y)))
	_write_cursor = (_write_cursor + todo) % live
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
	var live := _simulated()
	if _redeal_left <= 0 or live <= 0:
		return
	for i in mini(how_many, _redeal_left):
		# Picked at random, not walked in order: a block of neighbours all
		# changing together is a wipe across the formation, which is exactly
		# the tell that gives away that these are not animals.
		var m := _members[randi() % live]
		if not m["dead"]:
			m["motion"] = HerdMotion.draw_motion(mood, randf())
		_redeal_left -= 1


## PROMOTION. The handful of head nearest the camera become real beasts, up to
## the device's budget; the rest stay numbers. Demotion runs first so a herd
## walking past you hands its budget on rather than hoarding it.
## Every promoted head in the world, counted rather than remembered.
static func _afoot_everywhere(tree: SceneTree) -> int:
	var total := 0
	for h in tree.get_nodes_in_group("herds"):
		var herd := h as Herd
		if herd != null and is_instance_valid(herd):
			total += herd._afoot_here
	return total


func _tend_agents() -> void:
	# TWO EYES ON THE WORLD, not one. Promotion followed the camera and nothing
	# else, so a creature left to itself a field away from where the player
	# parked stood in a herd of two hundred and could not touch one of them:
	# they were all numbers, and a number has no collider to grab, no body to
	# eat, and puts nothing in the "animals" group for the beast to notice.
	#
	# The budget is still one budget for the whole world. When the creature is
	# beside the camera — which is most of the time, because the player follows
	# it — the two foci are the same place and nothing changes at all. When it
	# is not, some of the allowance goes where the creature is, and that is
	# right: those are the animals the simulation actually needs bodies for.
	#
	# AND NEITHER HALF OF IT WALKS THE BOOK ANY MORE. This function was three
	# passes over every row in the herd, several times a second: one to count
	# the promoted, one to tend them, one to look for more. The file's own
	# header promises that every per-frame cost here is bounded by a constant,
	# and this was the line that made that untrue — a barn of a hundred and
	# sixty head paid three hundred and forty rows a second to find the same
	# dozen animals, and a caribou herd across the map paid two hundred to find
	# none at all.
	var focus := GameState.camera_focus
	var beast := GameState.creature_at
	_agents_afoot = _afoot_everywhere(get_tree())
	_tend_the_promoted(focus, beast)
	_look_for_more(focus, beast, Quality.herd_agents())


## THE ONES THAT ARE ALREADY REAL. Walked off the short list of rows holding a
## beast rather than off the herd — `_promote` is the only thing in the game
## that puts an agent in a row, so the list is complete by construction, and
## everything that takes one out may simply leave its index behind: a stale
## entry costs one null test and is dropped here.
func _tend_the_promoted(focus: Vector3, beast: Vector3) -> void:
	var still: Array[int] = []
	_afoot_here = 0
	for i in _afoot:
		if i >= _members.size():
			continue
		var m := _members[i]
		# UNTYPED ON PURPOSE, and this is the whole of why. Writing
		# `var agent: Animal = m["agent"]` looks harmless and is not: assigning
		# an ALREADY-FREED object to a TYPED variable is an error in Godot, and
		# it is thrown before the is_instance_valid() below it can ever run. A
		# promoted beast can be freed by anything at all — eaten, butchered,
		# burned, thrown into the sea, or carried off with its own chunk — so a
		# row holding a dead handle is the ordinary case here, not the strange
		# one. It hard locked the game a minute and a half into a session.
		var held = m["agent"]
		if held == null:
			continue
		var agent: Animal = null
		if is_instance_valid(held):
			agent = held as Animal
		if agent == null or agent.is_queued_for_deletion():
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
		# ON THE SPOT, not at the next look-round: this is a beast the player
		# was close enough to for it to have been real, so it is exactly the one
		# they are about to point at. See `hand_span`.
		_widest = maxf(_widest, (m["offset"] as Vector2).length())
		m["ground"] = agent.global_position.y
		# NEVER OUT OF SOMEBODY'S HAND. A beast that is held or in flight is the
		# one beast the player is certainly paying attention to, and demotion
		# frees the node — so a sheep carried or thrown past the demote range
		# simply vanished from the hand that was holding it. It is also the one
		# beast whose distance from the camera means nothing about whether it
		# matters.
		if agent.state != Animal.State.HELD and agent.state != Animal.State.FALLING \
				and _watched_from(agent.global_position, focus, beast) > DEMOTE_BEYOND:
			# And hands back what it was doing, so the seam is silent in both
			# directions: a beast that ran off keeps running as a number.
			m["motion"] = AS_MOTION.get(agent.state, mood if mood != "move" else "walk")
			agent.queue_free()
			m["agent"] = null
			_agents_afoot -= 1
			continue
		still.append(i)
		_afoot_here += 1
	_afoot = still


## AND WHETHER ANY MORE SHOULD BE.
##
## ONE CHECK BEFORE ANY THOUGHT OF WALKING THE ROWS. A member stands at most
## `_widest` from the heart, so a herd whose heart is further off than the
## promotion range plus its own reach cannot possibly hold a head worth
## promoting — which is nearly every herd in the world, nearly all of the time,
## and every one of them used to find that out one row at a time.
##
## When it does look, it looks at a SLICE, round-robin, the way the ground
## sweep and the transform writes already do. A herd standing in front of you
## fills its share of the budget inside a tick or two, and the beast actually
## under the cursor never waits for this at all — see `_reach_of_the_hand`.
func _look_for_more(focus: Vector3, beast: Vector3, budget: int) -> void:
	var live := _simulated()
	if _agents_afoot >= budget or live <= 0:
		return
	if _watched_from(global_position, focus, beast) - hand_span() > PROMOTE_WITHIN:
		return
	var scan := mini(PROMOTES_SCANNED, live)
	for step in scan:
		if _agents_afoot >= budget:
			break
		var i := (_promote_cursor + step) % live
		var m := _members[i]
		if m["agent"] != null or m["dead"]:
			continue
		var p := _stands_at(m)
		if _watched_from(p, focus, beast) > PROMOTE_WITHIN:
			continue
		_promote(i, p)
	_promote_cursor = (_promote_cursor + scan) % live


## WHAT THE PLAYER'S HAND IS OVER, WHATEVER ELSE IS GOING ON.
##
## Promotion is rationed because a thousand real animals is a thousand
## CharacterBody3Ds, and that ration is right — for the world at large. It is
## flatly wrong for the one beast a player has put their hand on. Reaching for a
## sheep and finding nothing there is not a performance trade-off the player
## agreed to; it is the game refusing an instruction, and which sheep you may
## pick up is not a question a frame budget gets to answer.
##
## So the hand takes its few come what may, ahead of everything, and they are
## still CHARGED to the budget — the ration goes on being honest, it simply
## spends itself somewhere less important first. The overshoot is bounded by
## HAND_TAKES against the one or two herds a six-metre reach can touch.
##
## Every species, no exceptions: nothing here asks what it is.
func _reach_of_the_hand() -> void:
	var hand := GameState.hand_at
	if is_inf(hand.x):
		return
	# THE WHOLE MASS, AT ARM'S LENGTH — one check before any thought of walking
	# two hundred rows, and deliberately a generous one.
	#
	# It used to be `_spread + HAND_REACH`, and `_spread` is recomputed from the
	# head count every time the herd changes size — while the members keep the
	# offsets they were dealt. A herd that has LOST head therefore has members
	# standing well outside its own `_spread`, and the guard turned the hand
	# away before it ever looked at them. That is why it was bison and horses:
	# the kinds that get hunted and taken.
	if _flat_gap(global_position, hand) > hand_span():
		return
	# THE NEAREST ONE FIRST, and one a tick. Taking the first three in row order
	# promoted whichever heads happened to be early in the book rather than the
	# one actually under the cursor — so the beast you were pointing at stayed a
	# box while three of its neighbours became real.
	var near := 0
	var best := -1
	var closest := INF
	# AND ONLY AT WHAT IS ACTUALLY STANDING THERE. A barn's book is mostly
	# indoors; you cannot point at a pig that is not in the street.
	for i in _simulated():
		var m := _members[i]
		if m["dead"]:
			continue
		var gap := _flat_gap(_stands_at(m), hand)
		if gap > HAND_REACH:
			continue
		if m["agent"] != null:
			near += 1
			if near >= HAND_TAKES:
				return          # the hand already has its few here
			continue
		if gap < closest:
			closest = gap
			best = i
	if best >= 0:
		_promote(best, _stands_at(_members[best]))


## THE SPAN A TIDY HERD OF THIS SIZE OCCUPIES — what the shedding measures
## against, and what the reach would be if nobody had ever strayed.
func tidy_span() -> float:
	return maxf(_spread, SPREAD_LEAST) * SPREAD_SLACK


## WHAT THE HAND MUST ACTUALLY TEST, and the point is that it is not a guess.
##
## The early-out exists so that pointing at one sheep does not walk two hundred
## rows of every herd in the world, and that is worth keeping. But it was a
## GUESS — a span reckoned off the head count, times a slack factor, hoping no
## member stood further out than that. Members do stand further out, shedding
## takes up to a look-round to notice, and in that window the game refuses to
## pick up a beast the player is pointing straight at.
##
## So the herd remembers how far out its widest head actually is, and the
## early-out is true by construction. `_widest` is refreshed every look-round
## and bumped on the spot by the only two things that push a row outward, so it
## is never stale in the direction that matters.
func hand_span() -> float:
	return maxf(tidy_span(), _widest) + HAND_REACH


## FLAT DISTANCE, and it has to be flat. The hand floats HOVER_HEIGHT above the
## ground and a row's stored height is whatever the last ground sweep wrote, so
## a straight 3D distance spent a third of the hand's reach on a vertical gap
## that means nothing about whether you are pointing at the thing.
static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Where a row is standing, in world space.
func _stands_at(m: Dictionary) -> Vector3:
	var p := global_position + Vector3(m["offset"].x, 0.0, m["offset"].y)
	p.y = float(m["ground"])
	return p


## A ROW BECOMES A BEAST.
## BY INDEX, not by the row itself. The row is what everything below wants, and
## the INDEX is what `_afoot` has to remember — and looking one up from the
## other is a walk over the book, which is the thing this whole pass exists to
## stop doing.
func _promote(i: int, p: Vector3) -> void:
	var m := _members[i]
	var born := Animal.create(species)
	# A BARN'S BEAST COMES BACK TAMED. Promotion has to restore what the animal
	# WAS, or every time you walked up to the barn its stock would turn feral in
	# front of you.
	if keeper != null and is_instance_valid(keeper):
		born.tamed_by = keeper
	# Parented to the world, not to the herd: it is a free animal now, and if it
	# runs off it should not be dragged about by the formation. Its place is set
	# AFTER it is in the tree — a Node3D with no parent has no global transform
	# to write to, and Godot says so, loudly, once per promoted beast.
	get_parent().add_child(born)
	born.global_position = p
	# IT CARRIES ON DOING WHAT IT WAS DOING. Without this a grazing member stands
	# up and wanders the moment it crosses forty metres, which is a visible seam
	# exactly where the player is closest and most likely to be looking. The
	# motion names are ModelAnimator's own vocabulary, so the far pose and the
	# near clip are the same word.
	born.state = AS_STATE.get(m["motion"], Animal.State.IDLE)
	# THE WAY HOME. A promoted beast carries a handle on the herd it came from,
	# so a kill can be credited to the killer's pack and charged to the
	# victim's — which is the whole food chain in one reference.
	born.set_meta("herd", self)
	m["agent"] = born
	_afoot.append(i)
	_agents_afoot += 1
	_afoot_here += 1


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
			_afoot_here = maxi(_afoot_here - 1, 0)
	# The beasts are going too — freed with the chunk — so this is a release of
	# SLOTS, not a demotion, and it does not care whether the node is still valid.
	_agents_afoot = maxi(_agents_afoot, 0)
	_afoot.clear()


## HOW FAR THIS SPOT IS FROM ANYBODY WHO MATTERS: the camera, or the creature,
## whichever is nearer. An infinite creature position means there is no creature
## in the world, and the camera answers alone.
static func _watched_from(spot: Vector3, focus: Vector3, beast: Vector3) -> float:
	var gap := spot.distance_to(focus)
	if not is_inf(beast.x):
		gap = minf(gap, spot.distance_to(beast))
	# AND THE HAND, which is the one that decides whether a thing is SELECTABLE.
	#
	# `focus` is the camera rig's pivot — where you are looking FROM, on the
	# ground. On any wide shot that is nowhere near what you are pointing at, so
	# a mob sixty metres up-screen had exactly one head within PROMOTE_WITHIN of
	# it and the other fifteen were numbers: no collider for the ray, nothing to
	# grab, nothing to pick up. You could see a herd perfectly well and take
	# hold of one animal in it.
	#
	# Pointing at a beast is now what makes it real, which is the only rule a
	# player could have guessed.
	if not is_inf(GameState.hand_at.x):
		gap = minf(gap, spot.distance_to(GameState.hand_at))
	return gap


## THE ANIMAL PROMOTED INTO THIS ROW, or null — including when it was there a
## moment ago and has since been freed. Every reader goes through here because
## the obvious `var agent: Animal = m["agent"]` throws on a freed handle before
## any guard can run; see _tend_agents.
static func _living(m: Dictionary) -> Animal:
	var held = m["agent"]
	if held == null or not is_instance_valid(held):
		return null
	return held as Animal


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
	# THEY GET HUNGRIER. Only a KEPT herd: a wild one feeds itself, and what
	# the country will carry is already said by `capacity`.
	if keeper != null:
		hunger = minf(hunger + HUNGER_PER_SEASON, HUNGER_MOST)
		if hunger >= STARVES_ABOVE:
			var gone := maxi(int(float(n) * STARVE_SHARE), 1)
			_cull(gone)
			n = alive()
			if n <= 0:
				queue_free()
				return
	var ceiling := capacity()
	var room := 1.0 - float(n) / maxf(ceiling, 1.0)
	var calm := 1.0 - clampf(_fear, 0.0, 1.0)
	# AND A HUNGRY HERD DOES NOT CALVE, which is the part that matters: growth
	# stops long before anything starves, so an overstocked barn levels off
	# rather than boom-and-busting.
	var well_fed := clampf(1.0 - hunger, 0.0, 1.0)
	var change := BREED * float(n) * room * calm * well_fed
	# Over its ceiling the herd thins whether it is calm or not — hunger does
	# not care how safe you feel — so the calm factor only ever helps growth.
	if room < 0.0:
		change = BREED * float(n) * room
	var whole := int(change)
	# The fraction is a chance rather than a rounding, or a herd of six with a
	# gain of 0.4 head a season would never breed at all.
	if randf() < absf(change - float(whole)):
		whole += 1 if change > 0.0 else -1
	# THE COUNTRY IS FULL, whoever is standing in it. A herd under its own
	# ceiling still stops breeding when the neighbourhood has run out of grass,
	# which is the thing that keeps a rich meadow from carrying three full
	# herds of deer at once. It does not CULL for this — nothing starves for
	# being in a crowd it did not choose — it simply stops adding.
	if whole > 0 and n + _head_near >= HEAD_NEAR_MOST:
		whole = 0
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


## THE STRAYS LEAVE AND FOUND THEIR OWN. See STRAY_FAR for why they exist at
## all and why widening the hand's reach is not the answer.
##
## One band a look-round, built on the FARTHEST head out and everything that has
## drifted near it — so a scatter on two sides of the mass becomes two herds
## over two look-rounds rather than one absurd herd straddling the old one.
##
## A lone stray founds a herd of one, and that is correct: it is a proper Herd
## node with its own heart, its own span and its own place in the "herds" group,
## so the hand reaches it, the miracles reach it, it grazes, it breeds back up
## toward what the land will feed, and the kin-joining in `_look_about` walks it
## into the next herd it meets. A row standing alone inside somebody else's herd
## has none of that.
##
## A BARN'S STOCK NEVER SHEDS. Penned beasts belong to a keeper who is counting
## them, and a herd that split itself in the yard would take half the village's
## livestock out of the village's books.
func _shed_strays() -> void:
	if keeper != null and is_instance_valid(keeper):
		return
	# Measured against the TIDY span, not hand_span() — which now stretches to
	# cover the strays, and measuring against it would shed nobody, ever.
	var limit := tidy_span()
	var gather := SPREAD_LEAST * SPREAD_SLACK * STRAY_GATHER_SHARE
	var anchor := Vector3.INF
	var worst := limit
	for m in _members:
		if m["dead"]:
			continue
		var at := _stands_at(m)
		var gap := _flat_gap(at, global_position)
		if gap > worst:
			worst = gap
			anchor = at
	if is_inf(anchor.x):
		return
	var taken: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	var left_alive := 0
	for m in _members:
		if not m["dead"] and _flat_gap(_stands_at(m), global_position) > limit \
				and _flat_gap(_stands_at(m), anchor) < gather:
			taken.append(m)
		else:
			kept.append(m)
			if not m["dead"]:
				left_alive += 1
	# A herd cannot shed itself. If everything living is out at the anchor then
	# the mass has simply walked and its heart has not caught up, which `_drift`
	# fixes on its own and a split would only make two of.
	if taken.is_empty() or left_alive == 0:
		return
	var band := Herd.create(species, taken.size(), world)
	band.position = position + (anchor - global_position)
	get_parent().add_child(band)
	# After it is in the tree: `_ready` reads its own head count as the land's
	# worth and deals itself a formation, and both are about to be replaced.
	# FOUNDED ON WHAT WALKED, NOT ON WHAT THE LAND IS WORTH — and this is the
	# one line that separates shedding a stray from calving off a band.
	#
	# `_calve_off` hands its daughter the parent's `_born_head` on purpose: a
	# party of eight setting out for new country deserves the country's worth,
	# or it would starve back to eight on the day it was born. Copying that
	# here was catastrophic. A stray is ONE animal that drifted, and giving it
	# the worth of a forty-head range meant every accidental outlier founded a
	# herd that then bred up to forty. Over an evening the wild country fills
	# with bands that were each a single wandering deer, and the map is a
	# forest of "1 deer" tags becoming forty each.
	#
	# Founded on its own size, it stays a stray: too small to breed away from,
	# and `_consider_company` walks it into the next herd it meets, which is
	# what should have happened to it all along.
	band.founded_by(taken.size(), SETTLE)
	band.settled_with(taken, global_position)
	_members = kept
	head = _members.size()
	_spread = maxf(SPACING * sqrt(float(alive())), SPREAD_LEAST)
	_afoot_here = 0
	for m in _members:
		if _living(m) != null:
			_afoot_here += 1
	if _mm != null:
		_mm.instance_count = _members.size()
	_recentre()


## THE HEART GOES WHERE THE HEAD ACTUALLY IS.
##
## Shedding alone is not enough and tools/herd_stray.py is what said so. It
## cannot help the case it most needs to: a herd of ONE whose single head drifts
## away has nothing to leave behind, so the split refuses — and a lone bison
## wandering off from a hunted-out remnant is precisely the animal the player
## walks up to and cannot pick up. Splitting a herd of one is not the answer
## either; it is already its own herd. Its HEART is simply in the wrong place.
##
## So the mass is re-reckoned about the middle of what is left of it. Nothing
## moves: every offset is shifted by exactly what the heart moved, so each head
## stands on the same grass it stood on before — this is bookkeeping, and the
## point of it is that `_spread`, the hand's reach, the miracle reaches and the
## pasture steering are all measured off a heart that means something again.
##
## It also quietly repairs the older half of the same complaint, where a herd
## that has walked while its heart lagged behind answers the hand from where it
## used to be.
func _recentre() -> void:
	var middle := Vector2.ZERO
	var living := 0
	for m in _members:
		if m["dead"]:
			continue
		middle += m["offset"] as Vector2
		living += 1
	if living == 0:
		return
	middle /= float(living)
	if middle.length() >= RECENTRE_LEAST:
		for m in _members:
			m["offset"] -= middle
		global_position += Vector3(middle.x, 0.0, middle.y)
	# `_home` and `_target` are where the herd means to GO and are untouched on
	# purpose: the mass has not moved and has not changed its mind about the
	# pasture. Only our idea of where it is standing has been corrected.
	_remeasure()
	if _mm != null:
		_write_transforms()


## How far out the widest living head stands. Walked once a look-round, which is
## a walk this herd was making anyway.
func _remeasure() -> void:
	_widest = 0.0
	for m in _members:
		if not m["dead"]:
			_widest = maxf(_widest, (m["offset"] as Vector2).length())


## FOUNDED ON PARTICULAR HEAD rather than on a count of them. `_ready` has
## already dealt this herd a formation out of its head count; these rows replace
## it wholesale, keeping what each one was doing and — the point of the whole
## exercise — exactly where it was standing. `from` is the heart of the herd the
## rows came out of, since their offsets are still reckoned against it.
func settled_with(rows: Array[Dictionary], from: Vector3) -> void:
	var shift := from - global_position
	_members = []
	_afoot_here = 0
	for m in rows:
		m["offset"] += Vector2(shift.x, shift.z)
		var agent := _living(m)
		if agent != null:
			# THE WAY HOME, REPOINTED. A promoted beast carries a handle on its
			# herd so a kill can be credited and charged; left pointing at the
			# herd it just left, every one of these would have paid its debts to
			# the wrong mass.
			agent.set_meta("herd", self)
			_afoot_here += 1
		_members.append(m)
	head = _members.size()
	_spread = maxf(SPACING * sqrt(float(alive())), SPREAD_LEAST)
	_home = global_position
	_target = _home
	if _mm != null:
		_mm.instance_count = _members.size()
		_write_transforms()


## WHAT THE GROUND WILL FEED, in head. Bushes in reach are the lever the player
## and the creature actually have: plant them and the ceiling rises, and the
## herd fills the room over the following seasons.
func capacity() -> float:
	# PENNED STOCK IS LIMITED BY THE TOWN AND NOTHING ELSE. Counting bushes for
	# a village's livestock would be the same error as counting them for a wolf:
	# these animals are fed from the store by people whose job that is.
	#
	# AND THE LIMIT IS ONE POOL FOR THE WHOLE VILLAGE. This returned the full
	# stall count to EVERY herd a barn kept — and a barn opens a separate herd
	# per species — so pigs got the town's entire allowance, and so did the
	# sheep, and so did the chickens. The cap was silently multiplied by the
	# number of kinds kept, which is why a village of eighty had a thousand head
	# and then five thousand: growth is proportional to the number already
	# standing, so the run at a ceiling that far off is a sprint.
	#
	# What is left is the town's room minus everything else it is already
	# keeping, so the kinds compete for one allowance the way they would over
	# one yard.
	if keeper != null and is_instance_valid(keeper):
		var others := keeper.tamed_count() - alive()
		return maxf(float(Workshop.stalls(keeper)) - float(maxi(others, 0)), 1.0)
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
	_retag()   # a calf is a head more
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


## ONE CUT OUT OF THE HERD, ALIVE, as a real beast for somebody to keep.
##
## The other way a head leaves a herd. `take_one` is for the table and never
## builds anything; this builds the animal, because whoever asked for it means
## to walk it home — a villager cutting a heifer out of wild cattle, which until
## now they could not do at all. Taming looked through the "animals" group, and
## a herd puts at most a couple of dozen head in it out of however many hundred,
## so a village could stand beside two hundred caribou and own none of them.
##
## It prefers a head nobody is promoted into, the same as everything else here,
## so a beast the player is watching is never swapped out from under them. The
## herd is one smaller and frightened by it: a hand reaching in and carrying one
## off is not a thing the rest of them shrug at.
func give_one(at: Vector3) -> Animal:
	_retag.call_deferred()   # one head lighter, once it has actually gone
	for m in _members:
		if m["dead"] or m["agent"] != null:
			continue
		m["dead"] = true
		lost_one()
		_spread = maxf(SPACING * sqrt(float(alive())), SPREAD_LEAST)
		var won := Animal.create(species)
		get_parent().add_child(won)
		won.global_position = at
		return won
	return null


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
	_retag()


## Kept in step with the count rather than written every tick: a herd's number
## changes when something is born, taken or eaten, and not otherwise.
func _retag() -> void:
	if _tag == null or not is_instance_valid(_tag):
		return
	# A TAG IS FOR A MASS. One deer standing in a field is a deer — you can see
	# it, it is the same size as the label over it, and a countryside of "1
	# deer" floating over single animals is clutter that says nothing. The
	# number earns its place once there are enough of them to be worth counting.
	var many := alive()
	_tag.visible = many >= TAG_WORTH_IT
	_tag.text = "%d %s" % [many, species]


## THE TROUGH WAS FILLED. `share` is how good the feed was — a full trough is
## Drove.A_GOOD_FEED — and it comes off the one hunger the whole herd shares.
func fed(share: float) -> void:
	hunger = maxf(hunger - share, 0.0)


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


## FORM UP FOR THE NEXT LEG — the barn's one order, and the only thing in a
## kept herd's whole day that touches a row.
##
## `many` is how many of them are actually out (the rest are indoors) and
## `toward` is where they are going. The column is laid out once, here, and then
## nobody in it decides anything until the next order twenty-six seconds later.
## A wild herd is not a drove and keeps the scatter it was dealt.
##
## The walk over the members past `many` is the one O(book) pass a barn herd
## makes, once a leg: it puts the ones who stayed inside at the barn's own spot,
## which is where they are. Six rows a second for a book of a hundred and sixty.
func form_up(many: int, toward: Vector3) -> void:
	if keeper == null or _members.is_empty():
		return
	var to := toward - global_position
	to.y = 0.0
	if to.length() > 0.5:
		_heading = atan2(to.x, to.z)
	_turning = true
	Drove.form_up(_members, many if many >= 0 else _members.size(), _heading)
	_remeasure()
	if _mm != null:
		_write_transforms()


## FIRE LANDS IN THE HERD. Returns how many head it caught.
##
## `reach` is where it burns and `kill` is the core that kills outright — a
## fireblast has one, a gout has none (pass zero). The two radii are the same
## ones a real Animal is judged by, which is the point: a head standing five
## metres from a blast catches fire whether or not it happens to be one of the
## few the world has promoted into a body, and a herd must not be a crueller or
## a kinder place to stand than the grass beside it.
##
## Everything further out than the burning, as far as FIRE_FLEES times it,
## simply runs: an animal that can see fire goes, which is the whole reason a
## gout thrown at the EDGE of a herd is worth throwing.
##
func scorched(at: Vector3, reach: float, kill := 0.0) -> int:
	var caught := 0
	for i in _members.size():
		var m := _members[i]
		if m["dead"]:
			continue
		var here := global_position + Vector3(m["offset"].x, 0.0, m["offset"].y)
		here.y = float(m["ground"])
		var d := here.distance_to(at)
		if d > reach:
			continue
		caught += 1
		var agent := _living(m)
		if agent != null:
			# Left to the Animal, which burns visibly and dies through its own
			# clock and the usual demotion bookkeeping. Counting it here as well
			# would kill it twice.
			if d < kill:
				agent.die()
			else:
				agent.ignite()
			continue
		if d < kill:
			m["dead"] = true
			lost_one()
		elif not _already_alight(i):
			_burning.append({"i": i, "left": BURN_SECONDS})
	# THEY ALL RUN, burned or not, and much further out than the fire reaches.
	bolt_from(at, reach * FIRE_FLEES)
	return caught


## Already burning? A ball rolls past laying flame the whole way and then bursts
## where it stops, so the same head can be reached twice in a second, and a beast
## alight twice is not alight twice as fast.
func _already_alight(i: int) -> bool:
	for row in _burning:
		if int(row["i"]) == i:
			return true
	return false


## BLOWN. A gust takes the whole herd off its feet at once.
##
## There is no body to shove for most of them, so the shove is done to the
## FORMATION: every head in reach is moved bodily downwind, by a little more or
## a little less, and the herd's own pasture goes with them so they carry on
## that way rather than trotting straight back. The few that are real animals
## are genuinely thrown, which is what makes the near edge of the mass read as
## a scatter of tumbling beasts and the far edge as the whole hillside lurching.
##
## It is a shove and not an injury: nobody is hurt by wind, they are only moved
## and badly frightened.
func blown(from: Vector3, push: Vector3, reach: float) -> void:
	if alive() <= 0:
		return
	if global_position.distance_to(from) - _spread > reach:
		return
	var flat := Vector3(push.x, 0.0, push.z)
	if flat.length() < 0.5:
		return
	# The same arc the thrown beasts fly: launch speed times seconds aloft, and
	# a body thrown up at BLOWN_LIFT is back on the ground in twice that over
	# gravity. Derived rather than chosen, so the two can never drift apart.
	var aloft := BLOWN_LIFT * 2.0 / Animal.GRAVITY
	var carry := flat.length() * BLOWN_THROW * aloft
	var downwind := flat.normalized()
	for m in _members:
		if m["dead"]:
			continue
		var here := global_position + Vector3(m["offset"].x, 0.0, m["offset"].y)
		if here.distance_to(from) > reach:
			continue
		var agent := _living(m)
		if agent != null and agent.state != Animal.State.HELD:
			agent.drop(flat * BLOWN_THROW + Vector3.UP * BLOWN_LIFT, true)
			continue
		# Not all the same distance, or the mass slides like one sheet of ice.
		var went := downwind * carry \
			* randf_range(BLOWN_SCATTER_LEAST, BLOWN_SCATTER_MOST)
		m["offset"] += Vector2(went.x, went.z)
		_widest = maxf(_widest, (m["offset"] as Vector2).length())
	# FRIGHT FIRST, THEN THE DIRECTION. `scattered` picks a random bearing to
	# run on, which is right for a botched drive and wrong here — a herd that
	# has just been blown across a field goes the way the wind sent it. Setting
	# the target before the fright meant the fright threw it away again.
	scattered(FIRE_FEAR * 0.6)
	_home += downwind * carry
	_target = _home
	_graze_left = GRAZE_LEAST
	_spread = maxf(SPACING * sqrt(float(alive())), SPREAD_LEAST)
	_write_transforms()


## RUN FROM IT. Anything frightening at a point, whether or not it touched
## anybody — a fire the herd can see, a thunderclap, a twister coming over the
## hill, a bolt into the next field.
##
## Separate from `scorched` on purpose, and cheap on purpose: a rolling fireball
## lays flame eleven times a second down its whole track, and every one of those
## is a chance for a herd to bolt — but none of them may walk two hundred
## members to work it out. This looks at the herd's own position and its spread
## and nothing else, and turns back at the door if the thing is nowhere near.
## `within` is the whole distance at which it matters; the caller decides how
## much wider than its own effect that is.
func bolt_from(at: Vector3, within: float) -> void:
	if alive() <= 0 or keeper != null:
		return
	if global_position.distance_to(at) - _spread > within:
		return
	scattered(FIRE_FEAR)
	# Away from the thing itself, not anywhere: `scattered` picks a random
	# bearing, which is right for a botched drive and wrong for this.
	var away := global_position - at
	away.y = 0.0
	if away.length() < 0.5:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	_target = global_position + away.normalized() * ROAM
	_graze_left = GRAZE_LEAST


## RAIN ON IT. The flames go out and the beasts live.
##
## Fire could not reach a herd's numbered mass until today, and neither could
## the thing that puts fire out — which is the same bug wearing the other face,
## and the worse of the two, because it is the mercy. A god who burns a herd
## and then calls down a cloudburst to save what is left of it should get to
## save it. Their fright is left alone: they have still just been set on fire.
func doused(at: Vector3, reach: float) -> int:
	var out := 0
	var still: Array[Dictionary] = []
	for row in _burning:
		var i: int = row["i"]
		if i >= _members.size():
			continue
		var m := _members[i]
		var here := global_position + Vector3(m["offset"].x, 0.0, m["offset"].y)
		if here.distance_to(at) <= reach:
			out += 1
			continue
		still.append(row)
	_burning = still
	return out


## THE ONES STILL ALIGHT. They are numbers, so there is no flame to draw on
## them; what there is instead is a herd that keeps running while any of it is
## burning, and thins as they go down one after another rather than all at once.
func _tick_burning(delta: float) -> void:
	var still: Array[Dictionary] = []
	for row in _burning:
		row["left"] = float(row["left"]) - delta
		var i: int = row["i"]
		if i >= _members.size() or _members[i]["dead"]:
			continue          # something else got to it first
		if float(row["left"]) > 0.0:
			still.append(row)
			continue
		_members[i]["dead"] = true
		lost_one()
	_burning = still
	if not _burning.is_empty():
		set_mood("flee")


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
