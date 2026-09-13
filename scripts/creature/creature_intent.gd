class_name CreatureIntent
extends RefCounted
## THE BEAT BEFORE IT DOES THE THING.
##
## Praise and scold both landed on `_deed_verb` — what it had ALREADY DONE. So
## the only way to teach a creature not to eat somebody was to let it eat
## somebody and then tell it off, and since a fresh creature has no opinion
## about anything, the first thing every creature in this game ever did was eat
## a villager and get run out of town. The player watched it happen and was
## handed a Scold button afterwards. That is not teaching; that is a post-mortem.
##
## So a momentous deed is now ANNOUNCED before it is done. The creature stops,
## looks at what it means to do, and holds there for a few seconds:
##
##   PRAISE and it goes ahead, and learns that this is a thing you want.
##   SCOLD and it drops it on the spot, and learns that it is not.
##   SAY NOTHING and it does it anyway — this is a pause, not a permission
##   system, and a god who will not look up does not get a veto.
##
## WHAT IT WEIGHS. Everything whose consequences cannot be taken back, and
## everything it has not done enough times to have an opinion of its own about.
## Eating a person is on the list FOREVER, however old and however settled the
## creature is, because that is the one the player must never simply be shown
## after the fact. The rest it stops weighing once it has been through it a few
## times and formed a view — a creature that has to be asked about every sheep
## for the rest of its life is not learning, it is being operated.

## How long it holds, and how long a player has to actually answer.
const PAUSE := 3.2
## How many times it must have done a deed before it stops asking about it. The
## grave ones (below) ignore this.
const SETTLED_AFTER := 3

## THE DEEDS THAT ALWAYS WEIGH, however many times it has done them.
const GRAVE: Array[String] = ["eat_kin"]
## And the ones that weigh until it has formed a habit either way.
const WEIGHED: Array[String] = ["eat", "smash", "throw", "cull", "gift", "rescue"]

## How hard the answer lands. Heavier than a word about a finished deed,
## because it is arriving at the moment the creature is actually deciding —
## which is the only moment teaching has ever worked.
const TAUGHT_YES := 4.0
const TAUGHT_NO := -4.5

## What it is thinking of doing, in words a player can act on.
const SAID := {
	"eat_kin": "is eyeing %s, and it is hungry",
	"eat": "is about to eat %s",
	"smash": "is squaring up to %s",
	"throw": "has taken hold of %s and means to throw it",
	"cull": "is about to take %s out of the herd",
	"gift": "means to carry %s to the village",
	"rescue": "means to pick %s up and carry them to safety",
}


var verb := ""
var type := ""
var target: Node3D = null

var _left := 0.0
var _asked := false


## SHOULD IT STOP AND ASK? Called with the deed the mind has just chosen.
static func weighs(who: Creature, chosen: Dictionary) -> bool:
	var v := String(chosen.get("verb", ""))
	if v in GRAVE:
		return true
	if not (v in WEIGHED):
		return false
	# A creature that has done this a few times has its own opinion and does
	# not need asking again.
	var key := v + "|" + String(chosen.get("type", "none"))
	return int(who.mind.seen.get(key, 0)) < SETTLED_AFTER


## HOLD, AND SHOW WHAT IT MEANS TO DO.
func begin(who: Creature, chosen: Dictionary) -> void:
	verb = String(chosen.get("verb", ""))
	type = String(chosen.get("type", "none"))
	target = chosen.get("target", null) as Node3D
	_left = PAUSE
	_asked = false
	who.state = Creature.State.WEIGHING
	# It LOOKS at what it is thinking about, which is the whole tell — and the
	# head does that without the body stopping what it was doing. See
	# CreatureHead.
	if target != null and is_instance_valid(target):
		who.head.subject = target
	who.express("curious", PAUSE)


func holding() -> bool:
	return _left > 0.0


## The line the player is given, or "" if there is nothing worth saying.
func said(who: Creature) -> String:
	if not SAID.has(verb):
		return ""
	var what := "something"
	if target != null and is_instance_valid(target):
		what = CreatureLook.carriable_word(target)
		if target is Villager:
			what = (target as Villager).villager_name
	return "%s %s. Praise it, or scold it, NOW." % [who.called(), SAID[verb] % what]


## Runs while it is weighing. Nothing else about the creature is suspended: it
## is standing there thinking, not frozen.
func tick(who: Creature, delta: float) -> void:
	who._apply_gravity_only(delta)
	if not _asked:
		_asked = true
		var line := said(who)
		if line != "":
			GameState.announce(line)
			GameState.hint("Praise [P] or Scold [L] — it is deciding.")
	if target != null and is_instance_valid(target):
		who._face(target.global_position)
	_left -= delta
	if _left <= 0.0:
		# Nobody said anything. It does what it was going to do, and takes the
		# silence as its own answer — which is how a neglected creature ends up
		# with a character its god never chose.
		go_ahead(who, 0.0)


## YES. Praise during the pause: it learns the deed is wanted, hard, and then
## does it — so your approval is on the record BEFORE the thing happens rather
## than being an opinion about a corpse.
func approve(who: Creature) -> bool:
	if not holding():
		return false
	who.mind.teach(verb, type, TAUGHT_YES)
	who.mind.judge(verb, 0.25, false)
	who.morality = who.mind.temperament
	who.heart.stir("pride", 0.5)
	GameState.announce("%s takes that as a blessing." % who.called())
	go_ahead(who, 1.0)
	return true


## NO. Scold during the pause: it drops the deed where it stands and learns
## that it is not wanted — and it has not done anything yet, so there is nothing
## to forgive and no village to placate. This is the whole point of the pause.
func forbid(who: Creature) -> bool:
	if not holding():
		return false
	who.mind.teach(verb, type, TAUGHT_NO)
	who.mind.judge(verb, 0.22, false, -1.0)
	who.morality = who.mind.temperament
	who.heart.stir("shame", 0.35)
	who.express("sad", 1.6)
	GameState.announce("%s thinks better of it." % who.called())
	_left = 0.0
	verb = ""
	target = null
	who._decide()
	return true


## Go and do the thing that was being weighed. `blessed` is 1 when the god
## actually said yes, which the creature remembers as a different sort of day.
func go_ahead(who: Creature, blessed: float) -> void:
	var chosen := {"verb": verb, "type": type, "target": target}
	_left = 0.0
	verb = ""
	target = null
	if blessed > 0.0:
		who.mood = minf(who.mood + 8.0, 100.0)
	who.enact_chosen(chosen)
