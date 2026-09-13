class_name VillagerNeeds
extends RefCounted
## HUNGER, TIREDNESS, LONELINESS AND THE HARM THEY DO — the clock every villager
## runs whether or not anybody is watching.
##
## Lifted out of Villager because that file lives permanently on its line limit,
## and because this is one self-contained question: what does simply being alive
## cost, and what happens when it is not paid.


static func tick(who: Villager, delta: float) -> void:
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
		who.health -= 2.0 * delta
		if who.health <= 0.0:
			# You are judged for your own flock, not for strangers far away.
			if who.village.is_player_home:
				GameState.shift_alignment(-3.0)
				GameState.announce("%s starved to death. The heavens stayed silent." % who.villager_name)
			who.die(false)
