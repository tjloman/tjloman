class_name VillageWonder
extends RefCounted
## EVERYTHING THAT IS NOT A MIRACLE.
##
## Belief used to come from exactly two places: a miracle going off over their
## heads (Village.witness_miracle) and the slow drip of worship. Which meant the
## creature — the thing the whole game is about — could spend an afternoon
## dancing on the green, hurling oxen over the rooftops and filling the granary
## with its own two hands, and the village would feel precisely nothing about
## any of it. A god who never casts is not a god they have never seen. He is the
## one whose beast lives here.
##
## So this is the other door, and it takes anything:
##
##   A THING COMES DOWN OUT OF THE SKY. A sheep, a pine, a pig carcass, one of
##   their own neighbours. They did not see a spell; they saw an ox land in the
##   square, and an ox does not get up there by itself. Belief either way — the
##   difference between wonder and terror is only what it was and whether it was
##   on fire when it arrived.
##
##   A DEEP NEED IS ANSWERED. Food poured into a granary that had nothing in it
##   is worth many times the same food poured into a full one. This is the whole
##   of it: belief is not paid for tonnage, it is paid for MATTERING.
##
##   AND HOW IT ARRIVED COUNTS. Carried in and set down is a kindness. Lobbed in
##   from across the field, in an arc, by a creature that has worked out that
##   this is what the low round building is FOR — that is a thing people tell
##   their children about. Which is why the creature can learn to do it: see
##   Creature._hurl_carried and the "larder" knack.
##
## THE NOVELTY LEDGER is what keeps all of this from being a belief printing
## press. Every kind of spectacle carries HEAT; a fresh trick pays in full, the
## fourth ox in a minute pays almost nothing, and the heat bleeds off over a
## couple of minutes so the same trick is worth something again tomorrow. A
## village is impressed by wonders. It is not impressed by a habit.

## How fast a trick becomes old news, and how fast the town forgets it was.
const HEAT_PER := 1.0
const COOL_RATE := 0.055       # heat per second; ~18s to forget one showing
const LEAST_WORTH := 0.16      # below this they have stopped looking up

## How close a thing has to come down to count as "in town", as a share of the
## village's influence — plus a floor, so a small hamlet still has a square.
const NEAR_TOWN := 1.15
const TOWN_LEAST := 26.0

## Speeds. Under GENTLE nothing dramatic happened — a thing was set down. Over
## FAST it was THROWN, and that is a different event to watch.
const GENTLE := 5.0
const FAST := 18.0

## The multipliers, and they are the whole design in five numbers.
const AFIRE_PAY := 2.1         # it was burning when it landed
const HURLED_PAY := 1.6        # it came in hard, through the air
const HUNGRY_PAY := 3.0        # they had nothing, and now they have something
const CREATURE_PAY := 2.2      # and the creature did it, in front of them
const KIN_PAY := 1.5           # it was one of their own

## What the storehouse has to be down to before a gift counts as a deliverance:
## meals per head, matched to the number the job board calls fed.
const HUNGRY_AT := 1.0

## How near the storehouse a creature has to be to have SEEN the shot go in.
const WATCHING_FROM := 55.0

var _heat := {}


## Heat bleeds off. Called from the village's own clock.
func tick(delta: float) -> void:
	# A TOWN THAT HAS SEEN NOTHING COSTS NOTHING. `.keys()` builds a fresh Array
	# every call, and this runs once a frame for every village in the world —
	# so an empty ledger was allocating and freeing a throwaway array per town
	# per frame, forever, to iterate nothing.
	if _heat.is_empty():
		return
	for kind: String in _heat.keys():
		var left: float = float(_heat[kind]) - COOL_RATE * delta
		if left <= 0.0:
			_heat.erase(kind)
		else:
			_heat[kind] = left


## What this trick is still worth, 1.0 down to nearly nothing.
func novelty(kind: String) -> float:
	return 1.0 / (1.0 + float(_heat.get(kind, 0.0)))


## THE ONE DOOR. Everything below arrives here: a kind (which is what the
## novelty ledger counts), how the town should FEEL about it, and what it is
## worth before the ledger takes its cut.
## `who` is the thing it is happening to or because of — pass the creature
## whenever it is the creature, so the crowd follows it about instead of
## staring at the grass it was standing on. See VillageHive.looking_at.
func marvel(town: Village, kind: String, feel: String, where: Vector3,
		pay: float, say := "", who: Node3D = null) -> void:
	if town == null or not is_instance_valid(town):
		return
	var fresh := novelty(kind)
	if fresh < LEAST_WORTH:
		return
	_heat[kind] = float(_heat.get(kind, 0.0)) + HEAT_PER
	town.change_belief(pay * fresh)
	town.notice(8.0 * fresh)
	# The crowd takes it as ONE event, as it takes a miracle — the weight is the
	# belief it was worth, so a burning pine lands on the town's mood about as
	# hard as it lands on the square.
	town.hive.witness(feel, where, clampf(pay * fresh / 5.0, 0.15, 2.0), who)
	if say != "" and town.is_player_home and fresh > 0.5:
		GameState.announce(say)


## The village whose ground this is, if any.
static func town_at(tree: SceneTree, where: Vector3) -> Village:
	var best: Village = null
	var best_d := INF
	for n in tree.get_nodes_in_group("village"):
		var town := n as Village
		if not is_instance_valid(town):
			continue
		var d := town.global_position.distance_to(where)
		if d > maxf(town.influence_radius * NEAR_TOWN, TOWN_LEAST):
			continue
		if d < best_d:
			best_d = d
			best = town
	return best


## SOMETHING HIT THE GROUND IN TOWN. `kind` is what they would call it — a
## species, "tree", "corpse", "kin" — and everything else is how it arrived.
##
## Called from the landing handlers of the things that can be thrown, which is
## why it is static: a falling pine has no opinion about villages and should not
## have to go looking for one.
static func landed(tree: SceneTree, kind: String, where: Vector3,
		speed: float, afire := false) -> void:
	if speed < GENTLE and not afire:
		return   # set down gently: a kindness, not a spectacle
	var town := town_at(tree, where)
	if town == null:
		return
	var pay := 2.6
	var feel := "wonder"
	var word := "A %s comes down out of the sky over %s." % [kind, town.village_name]
	if kind == "kin":
		# ONE OF THEIR OWN. They do not marvel at this; they count it.
		pay *= KIN_PAY
		feel = "outrage"
		word = "One of %s's own people is thrown down among them." % town.village_name
	elif kind == "corpse":
		feel = "horror"
		word = "A body falls into %s out of a clear sky." % town.village_name
	if speed > FAST:
		pay *= HURLED_PAY
	if afire:
		# A BURNING THING IS STILL BELIEF. Nobody who watches a pine come down
		# on fire walks away thinking nothing is up there — they simply believe
		# something different about it.
		pay *= AFIRE_PAY
		feel = "horror"
		word = "A burning %s falls on %s. They scatter, and they believe." \
			% [kind, town.village_name]
	town.wonder.marvel(town, "fall_" + kind, feel, where, pay, word)


## THE CREATURE PUT ON A SHOW — a dance, a tantrum, a house kicked flat, a fit
## of grief in the middle of the square. `pay` is what that sort of thing is
## worth before the ledger; `feel` is how the town takes it.
static func spectacle(tree: SceneTree, kind: String, feel: String,
		where: Vector3, pay: float, say := "", who: Node3D = null) -> void:
	var town := town_at(tree, where)
	if town == null:
		return
	town.wonder.marvel(town, kind, feel, where, pay, say, who)


## PROVISION. Something edible or useful has gone into the storehouse, and this
## works out what it MEANT. Called by FoodStore the moment it takes a deposit.
##
## `flown` is how fast it was moving when the granary caught it, which is the
## difference between a careful gift and a shot from the halfway line.
func given(town: Village, what: String, amount: int, flown: float,
		by_creature := false, by_god := false) -> void:
	if town == null or not is_instance_valid(town) or amount <= 0:
		return
	# WHAT IT WAS WORTH TO THEM. A sack of grain into a full barn is a sack of
	# grain. The same sack into an empty one is the week they did not starve.
	var meals := 0.0
	if town.population() > 0:
		meals = float(town.store.total_food()) / float(town.population())
	var need := clampf(1.0 - meals / HUNGRY_AT, 0.0, 1.0)
	var pay := 0.5 + float(mini(amount, 12)) * 0.16
	pay *= lerpf(1.0, HUNGRY_PAY, need)
	var feel := "plenty"
	var word := ""
	# HOW IT ARRIVED, and the two do NOT stack: a creature's lob IS a throw, and
	# paying for both was paying twice for one fact. The bigger of the two wins.
	if by_creature:
		pay *= CREATURE_PAY
		feel = "wonder"
		word = "Your creature puts %d %s in %s's storehouse — from across the green." \
			% [amount, what, town.village_name]
		_teach_the_thrower(town)
	elif flown > FAST:
		# THE SHOT FROM THE HALFWAY LINE.
		pay *= HURLED_PAY
		feel = "wonder"
		word = "%s watches %d %s sail into the storehouse." % [town.village_name, amount, what]
	# YOUR OWN SHOT, AND SOMEBODY WAS WATCHING. A god who lobs an armful of
	# grain into the granary in front of their creature has just demonstrated
	# the one trick in the game the creature most wants to be shown — and it
	# picks up the technique the same way it picks up any other, by having seen
	# it done. See CreatureMind.watch_technique.
	if by_god and not by_creature:
		_teach_the_watcher(town)
	marvel(town, "given_" + what, feel, town.store.global_position, pay, word)
	# And it is a kindness on top of a wonder: the people who were hungry are
	# the ones cheering, and they are cheering at somebody in particular.
	if need > 0.4:
		town.hive.witness("kindness", town.store.global_position, need)


## THE LESSON THAT MAKES IT A LEARNED BEHAVIOUR. A creature that lands one in
## the granary is told, plainly and at once, that this went well — and the
## knack it practises here is the same one it rolls against next time it is
## holding something and standing in sight of a storehouse.
## IT SAW YOU DO IT. Nothing is given away: the knack climbs by watching at a
## third of the rate it climbs by doing, and only if the creature was near
## enough to see and trusts the hand it was watching.
func _teach_the_watcher(town: Village) -> void:
	var beast := town.get_tree().get_first_node_in_group("creature") as Creature
	if beast == null or not is_instance_valid(beast):
		return
	if beast.global_position.distance_to(town.store.global_position) > WATCHING_FROM:
		return
	beast.mind.watch_technique("larder", clampf(beast.trust / 100.0, 0.0, 1.0))
	beast.mind.watch_technique("throw", clampf(beast.trust / 100.0, 0.0, 1.0))
	beast.heart.stir("wonder", 0.15)


func _teach_the_thrower(town: Village) -> void:
	var beast := town.get_tree().get_first_node_in_group("creature") as Creature
	if beast == null or not is_instance_valid(beast):
		return
	beast.mind.practise("larder", true)
	beast.mind.experience("larder", 1.8)
	beast.heart.stir("pride", 0.5)
	beast.express("joy", 2.4)
