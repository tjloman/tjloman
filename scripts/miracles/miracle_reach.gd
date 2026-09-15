class_name MiracleReach
extends RefCounted
## WHERE YOUR POWER ACTUALLY REACHES.
##
## Until now a god could conjure a storm and hurl it anywhere the hand could
## be flung, which is the whole map. That makes the map one undifferentiated
## surface: nothing is far, nothing is near, and converting a village buys you
## prayer and nothing else. Black & White solved this with the influence
## circle — you could only work inside the ground your faith held — and it
## worked because its maps were drawn by hand, with every circle placed where
## a designer wanted it.
##
## This map is generated. So the circles have to come from things that MOVE
## and GROW rather than from a level designer:
##
##   A FAITHFUL VILLAGE holds the ground around it, out to the ring already
##   drawn on the grass. Its size is the population, so a town you have fed
##   and housed reaches further than a hamlet.
##
##   A WAGON ON THE ROAD holds a little ground of its own, because a settling
##   party is a town that has not arrived yet. See Caravan.
##
##   YOUR CREATURE CARRIES A CIRCLE WITH IT, and this is the important one.
##   It is how you get anywhere: a whelp holds fourteen metres and a grown
##   beast holds forty, and wherever you walk it, you can work. Leading the
##   animal across the map to a heathen town, so that you can call down
##   enough of a miracle to convert it, is the expedition this game did not
##   previously have a reason for.
##
## IT IS A LIMIT ON WHERE YOU CAST FROM, NOT ON WHERE IT LANDS — and getting
## that backwards is the most instructive mistake this file has made.
##
## The first version gated the LANDING: a miracle that came down outside every
## circle guttered out and gave the prayer back. Which is defensible on paper
## and awful in the hand, because the best thing in this game is winding up and
## hurling a working across a valley, and every good throw came back "beyond
## your reach by 88 metres". The rule read as a punishment for throwing well.
##
## So the gate is on the DRAWING. You may only open a casting session standing
## over ground you hold (DivineHand._open_casting, judged on `cast_from` — the
## spot where the hand was planted when the stroke began). Once a working is in
## your hand it is yours: throw it over the mountain if you can throw that far,
## and it goes off where it lands. That is also what Black & White actually did
## — the circle bounded the hand, not the shot.
##
## THE HAND ITSELF IS NOT LIMITED. You may still pick up a rock in the far
## mountains and drop it on anything you like; the hand is your arm, and an arm
## has no faith in it. Nor is a fire already burning: lighting a thing is a
## miracle, a thing being alight is weather, and a torch carried out of your
## country goes on burning what it touches.
##
## THE CREATURE'S OWN WORKINGS ARE NOT GATED, and that is deliberate rather
## than an oversight. It pays for those out of its own energy rather than out of
## your prayer (see Creature._process_cast), so they are not your power reaching
## somewhere -- they are its power, and it is standing right there. A god whose
## reach has run out can still ask the animal, which is the relationship the
## whole game is about.
##
## Anything else that comes to hold ground — a creature's yoked wagon, a new
## settlement, an encampment — extends the reach by adding one more row to
## `circles`, and nothing else in the game has to know.

## WHAT THE BEAST CARRIES, whelp to giant. A young creature is almost no help
## and a full-grown one nearly matches a small town, which is the shape of the
## whole relationship.
const AT_A_WHELP := 14.0
const AT_A_GIANT := 40.0
## And how much of that it keeps when it is asleep. Not zero, and not small
## either: your reach must not collapse every night, and an early game whose
## only circle is a whelp would otherwise go dark at dusk. tools/reach.py holds
## the floor -- at 0.45 a sleeping whelp was a six-metre dot, narrow enough that
## the slack below was a quarter of it.
const WHILE_ASLEEP := 0.7

## A hair of slack on every edge, so that a miracle landing ON the ring works
## rather than fizzling on a rounding error the player cannot see. It has to
## stay a HAIR: the moment it is a visible fraction of the smallest circle in
## the game, the ring drawn on the grass stops being the rule.
const GRACE := 0.75


## EVERY CIRCLE YOU HOLD, as {"at": Vector3 (flat), "r": float, "why": String}.
## The one list, so that the ring drawn on the ground and the rule that fizzles
## a miracle can never disagree about where your power ends.
static func circles(tree: SceneTree) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if tree == null:
		return found
	for v in tree.get_nodes_in_group("village"):
		var town := v as Village
		if town == null or not is_instance_valid(town) or not town.converted:
			continue
		found.append({
			"at": _flat(town.global_position),
			"r": town.influence_radius,
			"why": town.village_name,
		})
	var beast := tree.get_first_node_in_group("creature") as Creature
	if beast != null and is_instance_valid(beast):
		found.append({
			"at": _flat(beast.global_position),
			"r": beast_reach(beast),
			"why": GameState.named("your creature"),
		})
	# AND EVERY WAGON ON THE ROAD. A settling party is a town that has not
	# arrived yet, and it holds ground on the way — so leading one across the
	# map carries your power with it, and the moment it unpacks the circle it
	# was holding becomes the town's own.
	for c in tree.get_nodes_in_group("caravans"):
		var cart := c as Caravan
		if cart == null or not is_instance_valid(cart):
			continue
		found.append({
			"at": _flat(cart.global_position),
			"r": Caravan.REACH,
			"why": "the wagon out of %s" % cart.from_name,
		})
	return found


## HOW FAR A CREATURE HOLDS. Its growth, and rather less of it while it is
## asleep — a god whose whole reach is a dozing animal should feel that.
static func beast_reach(who: Creature) -> float:
	if who == null or not is_instance_valid(who):
		return 0.0
	var span := lerpf(AT_A_WHELP, AT_A_GIANT, clampf(who.growth, 0.0, 1.0))
	if who.state == Creature.State.SLEEPING:
		span *= WHILE_ASLEEP
	return span


## CAN YOU WORK HERE? The question every miracle asks before it happens.
static func reaches(tree: SceneTree, pos: Vector3) -> bool:
	return how_short(tree, pos) <= 0.0


## BY HOW MUCH DID YOU MISS, in metres past the nearest edge. Zero or less
## means you are inside something. Kept apart from `reaches` so that the hint
## can tell the player how badly they overreached rather than merely that they
## did.
static func how_short(tree: SceneTree, pos: Vector3) -> float:
	var flat := _flat(pos)
	var least := INF
	for ring in circles(tree):
		var over: float = flat.distance_to(ring["at"]) - (float(ring["r"]) + GRACE)
		least = minf(least, over)
	return least


## AND WHOSE EDGE IT WAS. The nearest circle by how far outside it you are, so
## the hint can name the thing you should have stood nearer to.
static func nearest_holder(tree: SceneTree, pos: Vector3) -> String:
	var flat := _flat(pos)
	var least := INF
	var holder := ""
	for ring in circles(tree):
		var over: float = flat.distance_to(ring["at"]) - float(ring["r"])
		if over < least:
			least = over
			holder = String(ring["why"])
	return holder


## WHY IT DID NOT WORK, in one line a player can act on. Named separately
## because three callers say it and they must all say the same thing.
static func short_hint(tree: SceneTree, pos: Vector3) -> String:
	var holder := nearest_holder(tree, pos)
	if holder == "":
		return "You hold no ground at all — your creature and your faithful " \
			+ "are your reach, and you have neither here."
	var over := how_short(tree, pos)
	return "Beyond your reach by %dm — %s is the nearest ground you hold." \
		% [int(ceilf(over)), holder]


## THE WIDEST THING YOU HOLD, for anything that wants one number.
static func widest(tree: SceneTree) -> float:
	var most := 0.0
	for ring in circles(tree):
		most = maxf(most, float(ring["r"]))
	return most


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
