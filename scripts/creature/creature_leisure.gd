class_name CreatureLeisure
extends RefCounted
## THE QUIET LIFE — lounging, dancing, praying, and holding court.
##
## These four are the deeds a creature does when nothing is pressing, and they
## are the ones that say most about how it was raised: a beast that is fed,
## unafraid and has somewhere to be spends its afternoons here, and a wretched
## one never gets the chance. None of them produces anything. That is the point
## of them.
##
## Lifted out of Creature because that file lives permanently on its line limit
## and these four sat together already, doing one thing.

static func lounge(who: Creature, delta: float) -> void:
	# IF HE HAS A BED, HE USES IT. Lounging used to happen wherever he was
	# standing, which meant a village could build him a lodge and watch him flop
	# down twelve metres short of it.
	if who._target != Vector3.INF and who.global_position.distance_to(who._target) > 2.0:
		who._move_toward(who._target, Creature.WALK_SPEED * 0.7, delta)
		return
	who._apply_gravity_only(delta)
	who._action_time -= delta
	who.energy = minf(who.energy + 1.4 * delta, 100.0)
	who.body.idle(delta)
	# It turns its head to whatever is nearby. This is where its opinions of
	# ordinary things quietly form.
	who._look_time -= delta
	if who._look_time <= 0.0:
		who._look_time = randf_range(2.0, 4.0)
		CreatureWatching.observe(who)
		var about := who._things_around(20.0)
		if not about.is_empty():
			who._face(about[randi() % about.size()].global_position)
	if who._action_time <= 0.0:
		who._last_deed = "lounge"
		who._finish_choice(0.5 + who.boredom / 300.0)


## DANCING — learned by watching villagers dance, and performed AT them. It is
## a spectacle, and a village that stops to watch its god's creature caper is a
## village warming to you.
static func dance(who: Creature, delta: float) -> void:
	who._apply_gravity_only(delta)
	who._action_time -= delta
	who.rotation.y += delta * 2.4
	who._body.scale.y = 1.0 + sin(Time.get_ticks_msec() / 120.0) * 0.12
	who._cheer_time -= delta
	if who._cheer_time <= 0.0:
		who._cheer_time = 1.0
		who._cheer_nearby(18.0, 1.2)
		var village := CreatureEyes.home_village(who.get_tree())
		if village != null:
			# AN INVITATION, not a summons. The crowd mind decides whether the
			# town takes it up, and a village that is frightened of the beast
			# will not — see VillageHive.invite.
			village.hive.invite("dance", who, who.global_position, 1.0)
			if who._audience(18.0) > 0:
				village.change_belief(0.35)
	if who._action_time <= 0.0:
		who._body.scale.y = 1.0
		who.body.exert(0.8, 0.4)
		who.boredom = maxf(who.boredom - 30.0, 0.0)
		who._last_deed = "dance"
		# The bigger the crowd, the better it felt. Nobody watching is a
		# lesson too — it may well decide dancing is not worth the effort.
		who._finish_choice(0.4 + who._audience(18.0) * 0.35)


## LEADING PRAYER. Sat still, eyes shut, arms out. The villagers at their totem
## pray harder with it there, and the prayer flows to you.
static func pray(who: Creature, delta: float) -> void:
	who._apply_gravity_only(delta)
	who._action_time -= delta
	who.express("love", 0.6)
	var faithful := 0
	for v in who.get_tree().get_nodes_in_group("villagers"):
		var villager := v as Villager
		if not is_instance_valid(villager) or villager.global_position \
				.distance_to(who.global_position) > 22.0:
			continue
		if villager.is_worshipping():
			faithful += 1
	var village := CreatureEyes.home_village(who.get_tree())
	if village != null:
		village.hive.invite("pray", who, who.global_position, 0.9)
	if faithful > 0:
		GameState.add_prayer_power(faithful * 1.6 * delta)
		if village != null:
			village.change_belief(0.22 * delta * faithful)
	if who._action_time <= 0.0:
		who.mood = minf(who.mood + 6.0, 100.0)
		who._last_deed = "pray"
		who._finish_choice(0.5 + faithful * 0.4)


## HOLDING COURT. It walks into the middle of the village and simply stands
## there being enormous, and the people turn and look. No violence, no miracle,
## no gift — just presence, and belief grows from it.
static func commune(who: Creature, delta: float) -> void:
	# AT THE POOL, if that is where he was headed: he drinks, and he is the one
	# thing in the world that can look into it. No village is needed for that —
	# communing at the nest is a thing he does alone.
	var nest := who.get_tree().get_first_node_in_group("creature_nest") as CreatureNest
	if nest != null and is_instance_valid(nest) \
			and who._target.distance_to(nest.water()) < 1.0:
		if who.global_position.distance_to(who._target) > 2.2:
			who._move_toward(who._target, Creature.WALK_SPEED * 0.7, delta)
			return
		who._apply_gravity_only(delta)
		who._action_time -= delta
		# IT HAS NO THIRST. This asked the creature to slake one and it has
		# never had one to slake — the word appears nowhere else in the game.
		# A phantom property: GDScript writes it down without a murmur and
		# raises only on the frame the line finally runs, which for a deed it
		# does now and then means minutes into a session.
		#
		# What drinking at your own reflecting pool actually IS here is the
		# quietest thing the creature can do, so that is what it does: it
		# comes away rested, and less tired of itself.
		who.energy = minf(who.energy + 2.0 * delta, 100.0)
		who.boredom = maxf(who.boredom - 4.0 * delta, 0.0)
		who.heart.stir("contentment", 0.04 * delta)
		if who._action_time <= 0.0:
			who._finish_choice(0.5)
		return
	var village := CreatureEyes.home_village(who.get_tree())
	if village == null:
		who._decide()
		return
	if who.global_position.distance_to(who._target) > village.influence_radius * 0.45:
		who._move_toward(who._target, Creature.WALK_SPEED * 0.8, delta)
		return
	who._apply_gravity_only(delta)
	who._action_time -= delta
	village.hive.invite("commune", who, who.global_position, 0.8)
	var audience := who._audience(20.0)
	if audience > 0:
		village.change_belief(0.3 * delta * minf(audience, 6))
		village.notice(0.4 * delta)
		who._cheer_time -= delta
		if who._cheer_time <= 0.0:
			who._cheer_time = 2.0
			for v in who.get_tree().get_nodes_in_group("villagers"):
				var villager := v as Villager
				if is_instance_valid(villager) and villager.global_position \
						.distance_to(who.global_position) < 20.0:
					villager.attend(who.global_position)
	if who._action_time <= 0.0:
		who._last_deed = "commune"
		who._finish_choice(0.4 + audience * 0.3)


## IT LOOKS UP AT YOU, AND STOPS.
##
## When the device underneath is genuinely struggling — sustained slow frames,
## which is what a throttling phone actually does to you — the creature quits
## whatever it was doing, turns to face the camera, and waits. Nothing else it
## does costs anything like a miracle of its own: an orb, its particles, its
## weather and everything the weather then touches. Dropping that one behaviour
## buys back more than every graphics knob put together.
##
## The point of doing it THIS way rather than silently is that a creature that
## stops and looks at you is not a glitch. It is the most legible thing in the
## game. The player reads "it noticed something" — and it did.
