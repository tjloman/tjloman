class_name CreatureWatching
extends RefCounted
## WHAT A CREATURE PICKS UP BY WATCHING, which is most of what it ever becomes.
##
## Three different kinds of learning happen here and it is worth keeping them
## apart, because they answer different questions and are taught by different
## things.
##
##  * THE PRACTICES. A creature cannot dance until it has seen dancing, and
##    cannot lead a prayer it has never heard said. Villages that celebrate and
##    worship raise creatures that celebrate and worship; a grim village raises
##    a creature that knows neither. This is `repertoire`, and it is the only
##    one of the three that gates whether a deed can be attempted at all.
##  * THE TRADES. Watching people farm, fish, haul and tame nudges what it
##    expects those deeds to be worth, gently — far more gently than doing one
##    itself, and far more gently again than your praise.
##  * WHAT A MOMENT FEELS LIKE. Whatever is true of its situation gets
##    associated with whatever it is feeling, and over a lifetime that becomes
##    the only account it has of what hunger, darkness or a crowd actually IS.
##
## Lifted out of Creature because that file sits exactly on its line limit and
## this is the most self-contained thing in it — and because naming the thing
## made it obvious that all three of the above were living in one unlabelled
## block.


static func observe(who: Creature) -> void:
	var watched_work := false
	var souls := 0
	for v in who.get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager):
			continue
		if villager.global_position.distance_to(who.global_position) > 16.0:
			continue
		souls += 1
		# Close enough to READ. What it makes of them is entirely its own
		# business: a creature whose every memory of hunger is a bad one feels
		# for a starving man, and one that has never gone hungry feels nothing.
		who.heart.attend(Creature.OBSERVE_PERIOD)
		# HOW MUCH OF THEM GETS IN. Emotional availability is the first thing
		# hardship takes: a cherished creature reads a starving man and is moved,
		# a wretched one looks straight through him.
		who.heart.sympathise(CreatureEyes.plight_of(villager),
			who.welfare.openness() / maxf(souls, 1.0))
		# And it notices WHO. Not "a villager" — this one, by name (CreatureBonds).
		who.mind.bonds.meet(villager)
		match villager.state:
			Villager.State.FARMING:
				who.mind.teach("tend", "farm", 1.0, 0.02)
				watched_work = true
			Villager.State.FISHING:
				who.mind.teach("fish", "water", 1.0, 0.02)
				watched_work = true
			Villager.State.BUILDING, Villager.State.CHOPPING, Villager.State.QUARRYING:
				who.mind.teach("gather", "goods", 1.0, 0.015)
				watched_work = true
			Villager.State.GO_FEED, Villager.State.TAMING:
				who.mind.teach("gift", "sheep", 1.0, 0.01)
				watched_work = true
			# THE PRACTICES. A creature cannot dance until it has seen dancing,
			# and cannot lead a prayer it has never watched anyone say. This is
			# the whole of how its repertoire widens: villages that celebrate
			# and worship raise creatures that celebrate and worship, and a
			# grim, joyless village raises a creature that knows neither.
			Villager.State.PLAY:
				who.mind.witness_practice("dance")
			Villager.State.WORSHIPPING, Villager.State.PREACHING:
				who.mind.witness_practice("pray")
	if watched_work:
		# Curiosity about the villagers' work keeps it engaged and alert.
		who.attention = minf(who.attention + 5.0, 100.0)
		who.boredom = maxf(who.boredom - 4.0, 0.0)
		who.feel("wonder", 0.12, 0.0)
	# NOBODY ABOUT. Loneliness is the one feeling that barely cools on its own;
	# it needs company to lift, which is what gives a solitary life its weight.
	if souls == 0:
		who.heart.stir("loneliness", 0.03)
	else:
		who.heart.stir("contentment", 0.03 * minf(souls, 3))
	# AND IT LEARNS WHAT ALL THIS FEELS LIKE. Whatever is true of its situation
	# right now gets quietly associated with whatever it is feeling right now,
	# and over a lifetime that becomes the only account it has of what hunger,
	# darkness or a crowd is actually like.
	var now := CreatureEyes.circumstances(who)
	who.heart.learn(now)
	# DOES THIS BRING SOMETHING BACK? A moment much like one it felt strongly
	# about — especially standing in the very spot — returns a shadow of the old
	# feeling, and it will never be able to say why it does not like it here.
	var back := who.mind.beliefs.reminder(now, who.global_position)
	if not back.is_empty():
		who.heart.stir(String(back["felt"]), float(back["strength"]))
	if GameState.is_night():
		for a in who.get_tree().get_nodes_in_group("animals"):
			var animal := a as Animal
			if is_instance_valid(animal) and animal.species == "wolf" \
					and animal.global_position.distance_to(who.global_position) < 25.0:
				who.mind.teach("guard", "village", 1.0, 0.05)
