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

## HOW FAR OFF THE BED STILL COUNTS AS WALKING TO IT — scaled, because a flat
## two metres is a stride for a whelp and a whisker for a fifteen-times giant,
## and the giant is the one that ends up asleep with its head through a wall.
const BED_SLOP := 1.2
## And how quickly it settles into place once it is there. Slow enough to read
## as an animal lying down and shuffling about; fast enough to be square before
## it is properly under.
const BED_SETTLE := 1.1
## How far a sleeping creature tips onto its side, and roughly how thick it is
## lying down as a share of its standing half-height. See `_lie_down`.
const LIE_ROLL := 80.0
const LIE_THICK := 0.30

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
		CreatureEyes.cheer_near(who, 18.0, 1.2)
		var village := CreatureEyes.home_village(who.get_tree())
		if village != null:
			# AN INVITATION, not a summons. The crowd mind decides whether the
			# town takes it up, and a village that is frightened of the beast
			# will not — see VillageHive.invite.
			village.hive.invite("dance", who, who.global_position, 1.0)
			if CreatureEyes.audience(who, 18.0) > 0:
				village.change_belief(0.35)
	if who._action_time <= 0.0:
		who._body.scale.y = 1.0
		who.body.exert(0.8, 0.4)
		who.boredom = maxf(who.boredom - 30.0, 0.0)
		# A FINISHED DANCE IS ONE EVENT, not only the drip while it went on. A
		# village that watched the god's beast dance the whole thing through
		# has SEEN something, and the ledger makes sure the fourth one in five
		# minutes is merely a creature capering. See VillageWonder.
		if CreatureEyes.audience(who, 18.0) > 0:
			VillageWonder.spectacle(who.get_tree(), "dance", "wonder",
				who.global_position, 2.8,
				"Your creature dances for them, and they will not look away.", who)
		who._last_deed = "dance"
		# The bigger the crowd, the better it felt. Nobody watching is a
		# lesson too — it may well decide dancing is not worth the effort.
		who._finish_choice(0.4 + CreatureEyes.audience(who, 18.0) * 0.35)


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
		if faithful > 0:
			VillageWonder.spectacle(who.get_tree(), "pray", "wonder",
				who.global_position, 1.8 + float(mini(faithful, 6)) * 0.5,
				"Your creature kneels and prays with them.", who)
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
	var audience: int = CreatureEyes.audience(who, 20.0)
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


## ASLEEP. Returns true when it is still walking to bed and the caller should do
## nothing else this frame.
##
## LYING IN THE BED, NOT NEAR IT. It used to stop the moment it was within two
## metres of the bed's centre and tip onto its side wherever it happened to be
## standing, at whatever heading it had walked in on. Two metres is nothing to a
## creature forty metres long, and a heading nobody set is a creature lying
## diagonally across its own bed with its legs out over the wall. So once it is
## home it eases the last of the way in and turns to lie ALONG the bed.
##
## Eased rather than snapped: a beast that teleports square the instant it
## arrives is a prop being placed, and everything else this creature does is
## something it is seen to do.
static func sleep(who: Creature, delta: float) -> bool:
	var home := who._target
	if home != Vector3.INF:
		var reach := 2.0 + who.scale.x * BED_SLOP
		if who.global_position.distance_to(home) > reach:
			who._move_toward(home, Creature.WALK_SPEED * 0.7, delta)
			return true
		_bed_down(who, home, delta)
	who._apply_gravity_only(delta)
	# HEAVY OR LIGHT. A content, well-fed creature sleeps like a stone and gets
	# the good of it. One that is hungry, spent, or braced for the next blow
	# sleeps thin — it rests more slowly AND wakes sooner, which is why
	# mistreatment compounds: it can never catch up.
	var depth := who.welfare.sleep_depth()
	who.energy = minf(who.energy + (2.0 + 5.0 * depth) * delta, 100.0)
	_lie_down(who, true)
	# AND HE IS DREAMING. The day is gone over while he is under, deeply or
	# barely, according to how well he has been kept — see CreatureDreams.
	who.mind.dreams.drift(who, delta)
	if who.energy > lerpf(55.0, 92.0, depth):
		_lie_down(who, false)
		who.mind.dreams.wake(who)
		who._decide()
	return false


## ON ITS SIDE, AND STILL WHERE IT WAS STANDING.
##
## Tipping the visual over is a roll about its Z — and the visual's origin is at
## the creature's FEET, so the roll swings the whole body out sideways by nearly
## its own height. On a full-grown creature that is eighteen metres: it lay down
## in its bed and its body ended up on the grass beside it, which is what
## "doesn't line up" looked like and is nothing to do with the yaw.
##
## So the roll is paid for. The body is pushed back along its own X by what the
## tip took away, leaving the middle of it over the spot it was standing on, and
## dropped to about the thickness of a creature lying down. The lying height is
## an estimate from CreatureBody.STANDING; a rigged model plays its own clip and
## none of this touches it.
static func _lie_down(who: Creature, down: bool) -> void:
	if who._animator != null or who._body == null:
		return
	if not down:
		who._body.rotation_degrees.z = 0.0
		who._body.position = Vector3.ZERO
		return
	var a := deg_to_rad(LIE_ROLL)
	var mid := CreatureBody.STANDING * 0.5
	who._body.rotation_degrees.z = LIE_ROLL
	who._body.position = Vector3(mid * sin(a), mid * (LIE_THICK - cos(a)), 0.0)


## The last metre of it: into the middle of the bed, and square to it.
static func _bed_down(who: Creature, home: Vector3, delta: float) -> void:
	var take := clampf(BED_SETTLE * delta, 0.0, 1.0)
	who.global_position.x = lerpf(who.global_position.x, home.x, take)
	who.global_position.z = lerpf(who.global_position.z, home.z, take)
	var nest := CreatureNest.holding(who)
	if nest != null and is_instance_valid(nest):
		who.rotation.y = lerp_angle(who.rotation.y, nest.bed_facing(), take)
