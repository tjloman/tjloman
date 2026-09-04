class_name CreatureRelief
extends RefCounted
## WHERE A CREATURE DECIDES TO GO, and what it does to the ground.
##
## Digestion leaves something behind (CreatureBody.waste), and the creature can
## HOLD IT. Below CreatureBody.WASTE_EASY it does not care at all; past that a
## rising pull toward doing something about it, and past WASTE_PRESSING it stops
## being fussy about where.
##
## THE CREATURE IS NEVER TOLD WHICH PLACES ARE GOOD. Each kind of ground is
## offered as a DIFFERENT DEED — `relieve|field`, `relieve|house` — so the mind's
## own value table learns which it likes, its conscience judges each on its
## merits, and the village's approval or annoyance teaches the rest. A gentle
## beast comes to manure the fields; a mischievous one waits until it is
## standing on somebody's roof. Neither is written down anywhere.
##
## Only what is actually underfoot is offered, so choosing WHERE means going
## there first — which is what "he holds it and goes where he thinks it is
## right" amounts to in a creature that decides one deed at a time.

## How close counts as standing on something.
const UNDERFOOT := 6.0

## What each place is worth to the creature that used it, and to your standing
## with the people who have to live there. Fields and woods are a kindness;
## a doorstep is mischief rather than cruelty, and is priced like one.
const WORTH := {
	"field": {"reward": 0.6, "karma": 0.4, "deed": "kind"},
	"tree": {"reward": 0.5, "karma": 0.2, "deed": "kind"},
	"house": {"reward": 0.35, "karma": -0.8, "deed": "mischief"},
	"store": {"reward": 0.4, "karma": -1.2, "deed": "mischief"},
	"open": {"reward": 0.25, "karma": 0.0, "deed": "none"},
}


## Everything it could do about it from where it stands.
static func offer(who: Creature, opts: Dictionary) -> void:
	if who.body.pressed() <= 0.0:
		return
	var farm := CreatureEyes.nearest_farm(who.get_tree(), who.global_position, UNDERFOOT)
	if farm != null:
		who.offer_option(opts, "relieve", "field", farm)
	for pair: Array in [["trees", "tree"], ["houses", "house"], ["stores", "store"]]:
		var near := CreatureEyes.nearest_in_group(
			who.get_tree(), who.global_position, String(pair[0]), UNDERFOOT)
		if near != null:
			who.offer_option(opts, "relieve", String(pair[1]), near)
	# Anywhere at all — but only once it can no longer afford to be choosy.
	if who.body.bursting():
		who.offer_option(opts, "relieve", "open", null)


## And it goes.
static func go(who: Creature, place: String) -> void:
	var load := who.body.relieve()
	if load <= 0.01:
		return
	var spec: Dictionary = WORTH.get(place, WORTH["open"])
	var muck := Poop.new()
	muck.load = load
	var scene := who.get_tree().current_scene
	if scene == null:
		return
	scene.add_child(muck)
	# Behind it, and on the ground rather than at the height of its belly.
	var behind := -who.global_transform.basis.z * 1.2 * who.scale.y
	muck.global_position = who.global_position + behind
	var world := who.get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		muck.global_position.y = world.surface_at(
			muck.global_position.x, muck.global_position.z)

	# THE LESSON. The deed's own reward teaches the creature whether it liked
	# doing it here; the karma is yours, because a beast that fouls the store
	# is a beast the village blames its god for.
	who.mind.reinforce(float(spec["reward"]) * load)
	var karma := float(spec["karma"]) * load
	if not is_zero_approx(karma):
		GameState.shift_alignment(karma)
	if String(spec["deed"]) == "mischief":
		GameState.announce(GameState.named(
			"Your creature has fouled the %s. The village is not amused."
			% ("granary" if place == "store" else "doorstep")))
