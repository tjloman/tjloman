class_name CreatureGreeting
extends RefCounted
## WHAT IT SAYS WHEN YOU HOLD YOUR HAND ON IT.
##
##     "...it greets the player by telling how it feels just now about what has
##      been going on around it. (Confused, angry, upset, frightened, calm,
##      excited, enthusiastic, bored, cruelly joking, etc.)"
##
## Everything here is READ, none of it is invented. The mood is whichever of
## its feelings is loudest (CreatureHeart), its fear, its boredom; the cause is
## what has just happened TO it (CreatureMind.lately), what it was last doing
## (the newest of its remembered episodes), and what it can see around it right
## now (CreatureEyes.circumstances). So a creature that says it is frightened
## of the men with spears was mobbed, and one that says nothing has happened
## has had nothing happen. A greeting that could be wrong about the creature
## would teach the player to stop listening to it.
##
## Asked once when the audience opens and once each time you tap it, never on
## a tick — `circumstances` walks the villagers.

## How long ago still counts as "just now", in seconds of the game's clock.
const RECENT := 90.0
## How strongly a feeling has to be held before it is the one it greets you
## with. Below FELT (CreatureHeart) it is not held at all.
const LOUD := 0.35
## Below this trust it greets you warily, whatever else it feels.
const WARY := 30.0
## Countable things are said in the plural ("hurling villagers about"); these
## are not.
const UNCOUNTED: Array[String] = ["sheep", "deer", "bison", "fish", "grain", "wood", "timber",
	"stone", "food", "meat", "things", "people"]

## The mood names, in the order they are tested. The first that holds is it.
const MOODS: Array[String] = ["frightened", "angry", "confused", "upset", "cruelly joking",
	"enthusiastic", "excited", "bored", "curious", "fond", "calm"]

## What happened, as it would put it. Keys are `CreatureMind.lately` tags.
const HAPPENED := {
	"mobbed": "They came at me with spears.",
	"hurt": "Something hurt me.",
	"praised": "You were pleased with me!",
	"scolded": "You told me off.",
	"spent": "I wore myself right out.",
	"forgiven": "They let me come home.",
	"feared": "They all ran from me.",
	"larder": "I filled the larder!",
}
## What it can see, worst first. Keys are `CreatureEyes.circumstances`.
const AROUND: Array[Array] = [
	["predator", "There's a hunter about."],
	["armed", "The people have their spears out."],
	["kin_afraid", "The people are frightened."],
	["kin_hurting", "Somebody here is suffering."],
	["kin_glad", "The people are happy today."],
	["alone", "There's nobody about."],
]


## The greeting: {"mood", "line"}. See the header for where each part comes from.
static func compose(who: Creature) -> Dictionary:
	var around := CreatureEyes.circumstances(who)
	var now := mood(who)
	return {"mood": now, "line": line(who, now, around)}


## HOW IT FEELS, in one of MOODS.
static func mood(who: Creature) -> String:
	var heart := who.heart
	var lately := recent(who)
	if who.fear >= 55.0 or heart.level("dread") >= LOUD:
		return "frightened"
	if heart.level("fury") >= LOUD:
		return "angry"
	# PRAISED AND SCOLDED inside the same minute and a half, and it cannot
	# tell which of you to believe.
	if "praised" in lately and "scolded" in lately:
		return "confused"
	if _sorest(who) != "":
		return "upset"
	var delight := heart.level("delight")
	var pride := heart.level("pride")
	if maxf(delight, pride) >= LOUD * 0.85:
		# GLAD ABOUT SOMETHING CRUEL, and it thinks it is funny. Asked of what
		# it did and what it is, so a gentle creature that is merely cheerful
		# is never written as a sadist.
		if cruel(who) and CreatureEthos.kindness(_last_verb(who)) < -0.3:
			return "cruelly joking"
		return "enthusiastic" if pride >= delight else "excited"
	if who.boredom >= 60.0:
		return "bored"
	if heart.level("wonder") >= LOUD:
		return "curious"
	if heart.level("affection") >= LOUD:
		return "fond"
	return "calm"


## WHAT IT SAYS, in its own few words: the feeling, then what brought it on,
## then what it needs. Short, because it is read off a phone over its head.
static func line(who: Creature, now: String, around: Dictionary) -> String:
	var lately := recent(who)
	var cause := _cause(lately)
	var seen := _around(around)
	var deed := _deed(who)
	var said := ""
	match now:
		"frightened":
			said = "I'm scared. " + _first([cause, seen, "Something isn't right."])
		"angry":
			said = "Grr! " + _first([cause, seen, "Everything's in my way!"])
		"confused":
			said = "I don't understand. You were pleased with me, and then you weren't."
		"upset":
			match _sorest(who):
				"pain": said = "It hurts. " + _first([cause, ""])
				"grief": said = "I feel heavy inside. " + _first([cause, seen])
				"shame": said = "I'm sorry. " + _first([cause, "I know I did wrong."])
				"loneliness": said = "Where is everyone? I've been alone so long."
				_: said = "Somebody's suffering, and I can't help."
		"cruelly joking":
			said = "Heh heh. " + _first([deed, cause]) + " Did you see them run?"
		"enthusiastic":
			said = "Did you see? " + _first([deed, cause, seen])
		"excited":
			said = "Oh! Oh! " + _first([_miracle(lately), deed, cause, seen])
		"bored":
			said = "There's nothing to do. Give me something" \
				+ (", or I'll break something." if cruel(who) else ", please?")
		"curious":
			said = "What was that? " + _first([_miracle(lately), seen])
		"fond":
			said = "There you are. I'm glad you came."
		_:
			said = "All's well. " + _first([deed, seen])
	said += _needs(who)
	if who.trust < WARY:
		said = "Oh. It's you. " + said
	return said.strip_edges()


## WHAT HAS JUST HAPPENED TO IT, newest first, within RECENT.
static func recent(who: Creature) -> Array:
	var out := []
	var lately: Array = who.mind.lately
	for i in range(lately.size() - 1, -1, -1):
		var entry: Array = lately[i]
		if GameState.clock - float(entry[1]) <= RECENT:
			out.append(String(entry[0]))
	return out


## Has it become a creature that hurts things? Either half of the compass that
## says so is enough.
static func cruel(who: Creature) -> bool:
	return who.mind.ethos.standing("mercy") <= -0.2 or who.morality <= -20.0


## The newest thing that happened to it that it has words for.
static func _cause(lately: Array) -> String:
	for tag: String in lately:
		if HAPPENED.has(tag):
			return String(HAPPENED[tag])
	return ""


## A miracle it has just watched, if it has.
static func _miracle(lately: Array) -> String:
	for tag: String in lately:
		if tag.begins_with("saw:"):
			return "I saw your %s!" % tag.trim_prefix("saw:").replace("_", " ")
	return ""


## The worst thing around it that it can see.
static func _around(around: Dictionary) -> String:
	for pair: Array in AROUND:
		if float(around.get(pair[0], 0.0)) >= 0.5:
			return String(pair[1])
	return ""


## What it was last doing, if lately: "I've been hurling villagers about."
static func _deed(who: Creature) -> String:
	var episodes: Array = who.mind.beliefs.episodes
	if episodes.is_empty():
		return ""
	var last: Dictionary = episodes[episodes.size() - 1]
	if GameState.clock - float(last.get("at", -INF)) > RECENT:
		return ""
	var parts := String(last.get("key", "")).split("|")
	var doing := String(CreatureBeliefs.VERB_PHRASE.get(parts[0], ""))
	if doing == "":
		return ""
	var what := parts[1] if parts.size() > 1 else ""
	if doing.contains("%s") and (what in ["", "none"] or parts[0] == "fish"):
		doing = doing.replace(" %s", "").replace("%s", "")
	elif doing.contains("%s"):
		doing = doing % (what if what in UNCOUNTED or what.ends_with("s") else what + "s")
	return "I've been %s." % doing


static func _last_verb(who: Creature) -> String:
	var episodes: Array = who.mind.beliefs.episodes
	if episodes.is_empty():
		return ""
	var last: Dictionary = episodes[episodes.size() - 1]
	return String(last.get("key", "")).split("|")[0]


## The feeling that hurts most, if any is held loudly enough to say.
static func _sorest(who: Creature) -> String:
	var worst := ""
	var most := LOUD
	for name: String in ["pain", "grief", "shame", "loneliness", "pity"]:
		if who.heart.level(name) >= most:
			most = who.heart.level(name)
			worst = name
	return worst


## And what it needs, said last because it is said every time it is true.
static func _needs(who: Creature) -> String:
	if who.hunger >= 70.0:
		return " And I'm starving."
	if who.energy <= 20.0:
		return " And I'm so tired."
	return ""


static func _first(choices: Array) -> String:
	for choice: String in choices:
		if choice != "":
			return choice
	return ""
