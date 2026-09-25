class_name Militia
extends RefCounted
## WHAT A VILLAGE DOES ABOUT SOMETHING WITH TEETH.
##
## Arming, counting the neighbours, finding the nerve, closing, striking, and —
## the part that is new — ANSWERING A SCREAM. Lifted out of Villager because
## that file lives permanently on its line limit and because all of this was
## already one subject sitting together under one heading.
##
## THE NERVE IS THE WHOLE BALANCE. A villager alone runs and is run down; a
## villager with neighbours turns and kills. Everything about how dangerous a
## wolf is comes out of `dares_fight`, and the one thing that overrides all of
## it is somebody already on the ground with the jaws on them — see Mauling.
##
## Villager is named directly in these signatures. Villager reaches Militia and
## Militia reaches back, which is the same two-way pair Creature and
## CreatureLeisure have had since they were split, and it resolves for the same
## reason: it is a pair, not a ring. (The ring that does NOT resolve is the one
## Edubba fell into — see the note on Edubba.seat_of.)

## How far the panic of a scream carries to the frail, as a share of how far it
## carries to the able. Children and expecting mothers hear it further off,
## because they are listening for it.
const FRAIL_REACH := 1.4

## NOBODY THIS CLOSE TURNS AROUND AND WALKS TO THE STOREHOUSE. Arming is the
## right answer from across the village and the wrong one from four metres: the
## round trip is twenty seconds and the whole thing is over in thirty. Inside
## this, they go in with their hands.
const ARMS_WORTH_IT := 9.0

## HOW LONG A COUNT OF YOUR FRIENDS IS GOOD FOR, in seconds. Far shorter than it
## takes a line to break, and long enough that `allies_near` stops being a walk
## over the town on every frame of every fight.
const ALLY_MEMORY := 0.4
## And how many such counts are kept before the whole ledger is thrown away. It
## only ever holds people who have been in a fight, and fights end.
const MEMORIES_MOST := 512

## villager id -> [when it was counted, how many]. See ALLY_MEMORY.
static var _counted := {}


## Draw a weapon from the storehouse (paying its materials). Bare hands if the
## village is too poor — a mob is still a mob.
static func take_up_arms(who: Villager) -> void:
	if who.weapon != "" or who.village == null:
		return
	var made := Weapon.forge(who.village.store)
	if made == "":
		return
	who.weapon = made
	if is_instance_valid(who._weapon_visual):
		who._weapon_visual.queue_free()
	who._weapon_visual = Weapon.build_visual(who.weapon)
	who._visuals.add_child(who._weapon_visual)


## How many of my people are close enough to fight alongside me.
## O(N) BY DESIGN: counting who is standing with you means looking at who is
## standing with you, and there is no tally of "near ME" a town could keep. It
## is not paid every frame, though — see ALLY_MEMORY. A battle is the moment
## the game is already busiest, and twenty people each walking two hundred
## every frame is the cost of a battle rather than the cost of a fight.
static func allies_near(who: Villager) -> int:
	if who.village == null:
		return 0
	# NOBODY COUNTS THEIR FRIENDS SIXTY TIMES A SECOND. Held for a moment, which
	# is far shorter than it takes a line to break and long enough to take the
	# walk off the frame.
	var id := who.get_instance_id()
	var now := GameState.clock
	var held: Array = _counted.get(id, [])
	if not held.is_empty() and now - float(held[0]) < ALLY_MEMORY:
		return int(held[1])
	var n := 0
	for v in who.village.my_villagers():
		if v == who or not v.is_adult() or v.state == Villager.State.DYING:
			continue
		if v.global_position.distance_to(who.global_position) < Villager.ALLY_RADIUS:
			n += 1
	# The ledger is only ever as big as the number of people who have been in a
	# fight, and a fight ends. Emptied wholesale rather than swept, because a
	# stale entry is worth nothing and finding it costs more than forgetting
	# everybody and counting again.
	if _counted.size() > MEMORIES_MOST:
		_counted.clear()
	_counted[id] = [now, n]
	return n


## Will this villager stand and fight, or run? Alone, they run — and a wolf runs
## them down. Together, they turn and kill it.
##
## TWO THINGS OVERRIDE THE ARITHMETIC, and both are the same thing: some fights
## are not weighed at all.
##
##   - A NEIGHBOUR IS BEING EATEN. Nobody stands at the edge of that counting
##     heads. This is what makes the thirty seconds of a mauling worth anything
##     to the village — without it the pack still wins, more slowly.
##   - THE TOWN HAS SWORN ON THIS SPECIES. A village that has buried three of
##     its own under the same jaws does not debate the next wolf it sees.
static func dares_fight(who: Villager, foe: Node3D = null) -> bool:
	if who.health < Villager.RETREAT_HEALTH:
		return false
	if sworn_on(who, foe):
		return true
	var needed := Villager.COURAGE_ARMED if who.weapon != "" else Villager.COURAGE_BARE
	return allies_near(who) >= needed


## IS THIS A FIGHT NOBODY WEIGHS? Somebody screaming nearby, or a beast of a
## kind this town has already buried people to. Asked about a NAMED foe, not
## about whatever the villager happens to be doing — a villager deciding whether
## to take up a spear has not started fighting yet, so reading their own state
## here would have meant only people already fighting were brave enough to.
static func sworn_on(who: Villager, foe: Node3D) -> bool:
	var town := who.village
	if town == null or not is_instance_valid(town):
		return false
	if town.feud.outraged(who.global_position):
		return true
	return foe is Animal and town.feud.is_sworn((foe as Animal).species)


## Close with the enemy and strike it on the weapon's cooldown. Breaks off if
## the target dies, if the villager is badly hurt, or if their nerve fails.
static func fight(who: Villager, delta: float) -> void:
	var foe := who._fight_target
	if foe == null or not is_instance_valid(foe) or foe.is_queued_for_deletion():
		who._fight_target = null
		who._rethink()
		return
	if who.health < Villager.RETREAT_HEALTH or not dares_fight(who, foe):
		# Nerve broken: run, and let the fear spread the alarm further.
		var flee_from := foe.global_position
		who._fight_target = null
		who.scare(flee_from)
		return
	var reach: float = Weapon.reach(who.weapon)
	if who.global_position.distance_to(foe.global_position) > reach:
		who._move_toward(foe.global_position, Villager.FLEE_SPEED * 0.85, delta, reach * 0.8)
		return
	who._apply_gravity_only(delta)
	# Face the enemy while trading blows.
	var to_foe := foe.global_position - who.global_position
	to_foe.y = 0.0
	if to_foe.length() > 0.05:
		who.look_at(who.global_position - to_foe.normalized(), Vector3.UP)
	who._attack_cd -= delta
	if who._attack_cd > 0.0:
		return
	who._attack_cd = Weapon.cooldown(who.weapon)
	strike(who, foe)


## Land a blow (Weapon resolves the damage) and settle up if the foe drops.
##
## A BLOW AGAINST A BEAST THE TOWN HAS SWORN ON LANDS HARDER. Not because the
## spear is sharper, but because they have done this before, they know where to
## stand, and they are not hesitating — which is what "with good success" means
## for people who have already buried somebody. See VillageFeud.wrath.
static func strike(who: Villager, foe_given: Variant) -> void:
	# Untyped until proved alive: a freed object handed to a typed parameter
	# is the error, raised before any check below could run. Gone is null.
	var foe: Node3D = (foe_given as Node3D) if is_instance_valid(foe_given) else null
	var town := who.village
	var fury := 1.0
	if not is_instance_valid(foe):
		return          # it died between being chosen and being struck
	if town != null and is_instance_valid(town) and foe is Animal:
		fury = town.feud.wrath((foe as Animal).species)
	var killed := Weapon.strike(who, foe, who.weapon, fury)
	if killed and foe is Animal:
		if town != null:
			town.remember_battle(true)   # standing together WORKED
			town.vendetta.erase(foe)
			town.feud.avenged((foe as Animal).species)
			if town.is_player_home:
				GameState.announce("%s and their neighbours have killed the beast."
					% who.villager_name)
		who._fight_target = null
		who.happiness = minf(who.happiness + 12.0, 100.0)
		who._rethink()
	elif foe is Creature:
		# A mob is a lesson. The creature is left to work out for ITSELF which
		# of its recent deeds brought this on — perhaps eating one of them.
		(foe as Creature).mind.experience("mobbed", -1.4)
		if town != null and town.is_player_home:
			GameState.announce("%s strikes at your creature with %s!"
				% [who.villager_name, Weapon.label(who.weapon)])


## Fleeing from the creature TEACHES IT that terror works — the mirror of the
## lesson a mob teaches. Which one it learns depends on what the people do.
static func report_terror(foe: Node3D) -> void:
	if foe is Creature:
		(foe as Creature).mind.experience("feared", 0.8)


## What this villager should be fighting right now, if anything: a marked beast
## or a predator inside the bounds — or the creature itself, once the village
## has taken enough from it.
static func find_foe(who: Villager) -> Node3D:
	if who.village == null:
		return null
	var beast := who.village.fight_target(who.global_position)
	if beast != null:
		return beast
	if who.village.hates_creature():
		var c := who.get_tree().get_first_node_in_group("creature") as Creature
		if c != null and c.global_position.distance_to(who.global_position) < 30.0:
			return c
	return null


## SOMEBODY IS SCREAMING, and this is everyone who can hear it deciding what
## kind of person they are about it.
##
## Two answers, and which one you get is not a temperament roll — it is who you
## are. A grown villager goes TOWARD it with whatever the storehouse can arm
## them with. A child, or a woman carrying one, goes the other way, and goes
## LOUDLY: not off into the wild, but in among the houses, where the screaming
## fetches more people than the running loses.
##
## Called once per scream (a couple of seconds apart) for as long as it lasts,
## so help that was too far off at the start is not too far off at the end.
static func rally(victim: Villager, reach: float) -> void:
	var town := victim.village
	if town == null or not is_instance_valid(town):
		return
	var here := victim.global_position
	for v in town.my_villagers():
		if v == victim or v.is_dying() or v.pin != null:
			continue
		var d := v.global_position.distance_to(here)
		var frail := not v.is_adult() or v.pregnant
		if d > reach * (FRAIL_REACH if frail else 1.0):
			continue
		if frail:
			flee_screaming(v, here)
		else:
			answer(v, victim)


## THE FRAIL. They run for the middle of town rather than blindly away, which is
## both what a frightened child actually does and the mechanically useful thing:
## it carries the alarm INTO the village instead of out of it.
static func flee_screaming(who: Villager, from: Vector3) -> void:
	if who.state in [Villager.State.HELD, Villager.State.FALLING,
			Villager.State.DYING, Villager.State.PINNED]:
		return
	who.witness_horror(0.6)
	who.happiness = maxf(who.happiness - 14.0, 0.0)
	if who.state == Villager.State.HIDE:
		return   # already running; don't restart the clock every scream
	var town := who.village
	who.state = Villager.State.HIDE
	who._action_time = randf_range(7.0, 12.0)
	var bolt := who.global_position + (who.global_position - from).normalized() * 12.0
	who._target = bolt
	if town != null:
		# Toward the houses — UNLESS the houses are past the thing screaming
		# at them, in which case even a child knows better.
		var refuge: Vector3 = town.refuge(who.global_position)
		if refuge.distance_to(from) > who.global_position.distance_to(from):
			who._target = refuge
	if randf() < 0.35:
		SoundBank.play_at("screech", who.global_position, -8.0)
	if town != null and town.is_player_home and randf() < 0.12:
		GameState.announce("%s runs screaming through %s."
			% [who.villager_name, town.village_name])


## THE ABLE. Arm if there is anything to arm with and they are empty-handed,
## otherwise go straight for whatever has hold of their neighbour. Nobody
## already in a fight is pulled out of it.
static func answer(who: Villager, victim: Villager) -> void:
	if who.state in [Villager.State.FIGHT, Villager.State.GO_ARM,
			Villager.State.HELD, Villager.State.FALLING, Villager.State.DYING]:
		return
	var foe := _nearest_jaws(who, victim)
	if foe == null:
		return
	if who.weapon == "" and Weapon.affordable(who.village.store) != "" \
			and who.global_position.distance_to(victim.global_position) > ARMS_WORTH_IT:
		who.state = Villager.State.GO_ARM
		return
	who._fight_target = foe
	who.state = Villager.State.FIGHT
	who._attack_cd = 0.3


## Which of the pack this one goes for: the nearest mouth on their neighbour.
static func _nearest_jaws(who: Villager, victim: Villager) -> Animal:
	if victim.pin == null:
		return null
	var best: Animal = null
	var best_d := INF
	for beast in victim.pin.jaws:
		if not is_instance_valid(beast):
			continue
		var d := who.global_position.distance_to(beast.global_position)
		if d < best_d:
			best_d = d
			best = beast
	return best
