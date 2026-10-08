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
## How often the audience at a communing is counted, in seconds.
const AUDIENCE_EVERY := 0.5
## SPENT, TIRED AND RESTED, in energy. At SPENT it drops where it stands,
## whatever it was doing and whoever holds the lead; under TIRED it rests before
## it obeys the lead; and asleep, it is woken by a call on the lead only once it
## is past ROUSED — short of that, the order waits for it to wake.
const SPENT := 0.5
const TIRED := 15.0
const ROUSED := 40.0
## How often the drop is said aloud, in game seconds: a spent beast struck awake
## drops again at once, and the line would come with every blow.
const SPENT_SAID_EVERY := 30.0

static var _audience := 0
static var _audience_in := 0.0
static var _spent_said_at := -INF

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
	var audience := _audience_of(who, delta)
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


## WHO IS WATCHING, counted twice a second rather than every tick: it is a walk
## of every villager in the world, and a crowd does not come and go that fast.
static func _audience_of(who: Creature, delta: float) -> int:
	_audience_in -= delta
	if _audience_in <= 0.0:
		_audience_in = AUDIENCE_EVERY
		_audience = CreatureEyes.audience(who, 20.0)
	return _audience


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
	# AND HE IS DREAMING. The day is gone over while he is under, deeply or
	# barely, according to how well he has been kept — see CreatureDreams.
	who.mind.dreams.drift(who, delta)
	if who.energy > lerpf(55.0, 92.0, depth):
		who.mind.dreams.wake(who)
		who._decide()
	return false


## IT DROPS WHERE IT STANDS. A creature run to nothing went on hauling, juggling
## and following the lead at zero energy, because nothing it was doing ever asked
## — and a beast on the lead never got to choose to rest at all, since the lead
## decides for it. Spent is not a choice: whatever is in its arms goes down,
## whatever is in the air comes down, and it is asleep, here, now. Asked every
## tick. True on the tick it drops.
static func pass_out_if_spent(who: Creature) -> bool:
	if who.energy > SPENT or who.state == Creature.State.SLEEPING:
		return false
	who.release_carried()
	if who.throwing.busy():
		who.throwing.spill(who)
	who._target = Vector3.INF          # where it stands: no walk to a bed
	who.state = Creature.State.SLEEPING
	if GameState.clock - _spent_said_at > SPENT_SAID_EVERY:
		_spent_said_at = GameState.clock
		GameState.announce("%s drops where it stands, spent, and sleeps."
			% GameState.creature_name)
	return true


## REST BEFORE THE LEAD. A tired creature that is called still lies down first
## — it obeys when it wakes, since the order is kept. True if it lay down.
static func rest_before_the_lead(who: Creature) -> bool:
	if who.energy > TIRED:
		return false
	who._target = Vector3.INF
	who.state = Creature.State.SLEEPING
	return true


## DOES A CALL ON THE LEAD WAIT? While it sleeps and is not yet rested enough to
## be roused — a held rope tugs every second or so, and each tug used to drag it
## out of its sleep, so a creature on the lead could never sleep at all.
static func lead_waits(who: Creature) -> bool:
	return who.state == Creature.State.SLEEPING and who.energy < ROUSED


## The last metre of it: into the middle of the bed, and square to it.
static func _bed_down(who: Creature, home: Vector3, delta: float) -> void:
	var take := clampf(BED_SETTLE * delta, 0.0, 1.0)
	who.global_position.x = lerpf(who.global_position.x, home.x, take)
	who.global_position.z = lerpf(who.global_position.z, home.z, take)
	var nest := CreatureNest.holding(who)
	if nest != null and is_instance_valid(nest):
		who.rotation.y = lerp_angle(who.rotation.y, nest.bed_facing(), take)
