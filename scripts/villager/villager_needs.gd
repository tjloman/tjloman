class_name VillagerNeeds
extends RefCounted
## HUNGER, TIREDNESS, LONELINESS AND THE HARM THEY DO — the clock every villager
## runs whether or not anybody is watching.
##
## Lifted out of Villager because that file lives permanently on its line limit,
## and because this is one self-contained question: what does simply being alive
## cost, and what happens when it is not paid.


## WHAT A DEATH COSTS THE GOD WHO LET IT HAPPEN.
##
## ONE PLACE, because it used to be several and they did not agree. Starving
## charged three; burning to death from a fireball charged nothing at all,
## since the miracle only paid for the people its core killed outright and a
## man set alight and dead eight seconds later was free. Every early death is
## answered for here, and nowhere else.
##
## THE SCALE IS HOW MUCH OF IT WAS YOURS. A wolf is the world being what it is
## and costs a god very little. Hunger in your own town is neglect, and neglect
## is the one thing a god is unambiguously for. Fire is almost never the
## world's doing — it is a miracle or it is your creature, and either way it is
## you.
const DEATH_UNLOOKED_FOR := -0.5    # a beast, a fall, the sea
const DEATH_BY_NEGLECT := -3.0      # starved, in a town that was yours to feed
const DEATH_BY_FIRE := -2.5         # yours, or your creature's, nearly always
## A GOD'S OWN HAND: a bolt, a fireball's core, a stone through a roof. The
## same price as fire because it is the same act — you meant it, and the
## difference between burning a man and stoning him is a matter of taste.
const DEATH_BY_YOUR_HAND := -2.5

## And how far a death carries to the creature, which learns cruelty from what
## it watches its god allow.
const GRIEF_REACH := 40.0


static func live(who: Villager, delta: float) -> void:
	# NO CHILD IS EVER HUNGRY. Not fed first, not fed cheaply — not hungry at
	# all, so the question never reaches the granary, the job board, or the
	# player. There are no starving children in this game under any
	# circumstances, and the way to guarantee that is not to balance the food
	# economy carefully enough; it is to take children out of it. A famine
	# starves the adults who chose how the town was run.
	if not who.is_adult():
		who.hunger = 0.0
		who.energy = minf(who.energy + 4.0 * delta, 100.0)
		who.social = maxf(who.social - 0.3 * delta, 0.0)
		if who.health < 100.0:
			who.health = minf(who.health + 1.5 * delta, 100.0)
		return
	# Bellies empty at HALF the old rate: with hauling, militia duty and spread
	# job priorities all competing for hands, the village could not out-farm the
	# old appetite and starved. A slower burn lets the granary keep ahead.
	var hunger_rate := 0.25 * (1.4 if who.pregnant else 1.0)
	if who.state == Villager.State.SLEEPING:
		hunger_rate *= 0.4  # a sleeping body burns slow
	who.hunger = minf(who.hunger + hunger_rate * delta, 100.0)
	if who.state != Villager.State.SLEEPING:
		var working := who.state in [
			Villager.State.FARMING, Villager.State.HUNTING,
			Villager.State.CHOPPING, Villager.State.QUARRYING,
			Villager.State.BUILDING]
		who.energy = maxf(who.energy - (0.5 if working else 0.25) * delta, 0.0)
	who.social = maxf(who.social - 0.3 * delta, 0.0)
	who._breed_cooldown = maxf(who._breed_cooldown - delta, 0.0)
	# A fed body knits itself back together — small wounds heal.
	if who.hunger < 70.0 and who.health < 100.0:
		who.health = minf(who.health + 1.5 * delta, 100.0)
	if who.hunger > 85.0:
		who.happiness = maxf(who.happiness - 1.5 * delta, 0.0)
	if who.hunger >= 100.0:
		# A starving child goes to family elsewhere, before the announcement —
		# which would otherwise be said over them. See ChildSafety.spared.
		if ChildSafety.spared(who):
			return
		who.health -= 2.0 * delta
		if who.health <= 0.0:
			if who.village.is_player_home:
				GameState.announce("%s starved to death. The heavens stayed silent." % who.villager_name)
			who.die(false)


## Bury one, and settle what it cost. Old age settles nothing: the creature is
## reading its god's hand in the world, and there is no hand in an old man
## dying full of years.
static func mourn(who: Villager, of_old_age: bool) -> void:
	# THE REGISTER FIRST, and before the old-age door below, because a chart of
	# what kills people here is worthless if it omits the one thing that kills
	# everybody eventually. See Chronicle.
	var ledger := Chronicle.of(who.get_tree())
	if ledger != null:
		ledger.inter(_cause_of(who, of_old_age), who.age)
	if of_old_age:
		return
	var creature := who.get_tree().get_first_node_in_group("creature") as Creature
	if creature != null \
			and creature.global_position.distance_to(who.global_position) < GRIEF_REACH:
		creature.witness(-2.0)
	var cause := _cause_of(who, false)
	var karma := DEATH_UNLOOKED_FOR
	if who.burning:
		karma = DEATH_BY_FIRE
	elif cause == "divine":
		karma = DEATH_BY_YOUR_HAND
	elif who.hunger >= 100.0:
		karma = DEATH_BY_NEGLECT
	# YOU ARE JUDGED FOR YOUR OWN FLOCK — unless you did it. A wolf in a village
	# on the far side of the world is not a god's business; a man you set alight
	# there is, wherever he lived.
	#
	# AND SO IS A MAN YOU STONED. That rule was written about wolves and famine,
	# where "not your business" is exactly right — but it was also letting
	# through every death a god CAUSED outside their own village. Hurling a rock
	# through a heathen family's roof and killing them where they slept cost
	# nothing at all, which is not a judgement about distance, it is a hole.
	var mine := who.village != null and is_instance_valid(who.village) \
		and who.village.is_player_home
	if mine or karma == DEATH_BY_FIRE or cause == "divine":
		GameState.shift_alignment(karma)


## WHAT THE EVIDENCE ON THE BODY SAYS. Tested in the order a god is answerable
## for: a man on fire who was also starving is recorded as burnt.
static func _cause_of(who: Villager, of_old_age: bool) -> String:
	if of_old_age:
		return "age"
	if who.burning:
		return "fire"
	if who.hunger >= 100.0:
		return "hunger"
	if is_instance_valid(who._last_attacker):
		return "war" if who._last_attacker is Villager else "beast"
	# A GOD'S OWN HAND. `take_damage` has always been told whether the harm came
	# from a god — a bolt, a fireball's core, a hurled stone — and that flag had
	# nowhere to live, so every one of those deaths came out as "sudden" and was
	# indistinguishable from a fall. It is a meta on the body now, set at the
	# blow and read here.
	if who.has_meta("struck_by_god"):
		return "divine"
	return "sudden"
