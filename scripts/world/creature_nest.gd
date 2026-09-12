class_name CreatureNest
extends StaticBody3D
## THE CREATURE'S OWN PLACE — a lodge, a fire, a pool, and a wall of carved
## stone that is slowly a portrait of him.
##
## Every other building in the village is FOR something: the store holds food,
## the mill grinds, the school teaches. This one is for somebody. A village
## raises it because it has come to think of the beast as one of its own, and
## what it does is give him somewhere to be that is his — to lounge by, to sleep
## at, to drink from and see himself in.
##
## AND IT IS WHERE HIS DASHBOARD GOES TO DIE. The creature panel lists his
## character in words on a slab of UI; the six axes his character is actually
## made of are carved here as six stone faces instead, cut deeper the further he
## has gone down each one. A player who knows the wall can read their creature
## across the clearing by torchlight, without opening anything — and the effigy
## at the centre is cut to his ACTUAL SIZE, so a beast somebody has starved
## stands small among his own idols.
##
## The village dances here in the evening whether the creature comes or not,
## which is the part that makes it a shrine rather than a kennel. What is
## offered at a place somebody loves is worth more than what is offered at a
## post, so the circle gathers prayer faster than the totem does.

## THE SIX FACES, in the order they are cut into the wall — the same six axes
## CreatureEthos keeps, because they ARE the creature's character and a second
## list would only drift from the first.
const FACES := ["mercy", "bounty", "order", "fellowship", "daring", "devotion"]

## How wide the clearing is, how far the dance stands from the fire, and how
## many may join a circle before it is full.
const GROUNDS := 13.0
const RING := 4.2
const DANCERS := 8

## What an evening of dancing is worth, per second per dancer. A circle of eight
## brings in rather more than a lone villager at a totem, which is the point:
## worship is a thing people do TOGETHER here.
const PRAYER_PER_DANCER := 0.5
const BELIEF_PER_DANCER := 0.012

## How often the wall is re-cut to match what he has become. Slow: a character
## is a long average and the stone should feel like it was always that way.
const RECARVE := 6.0

## Torchlight. The flicker is shared by every flame here so a wall of them
## breathes together instead of sparkling like a fairground.
const FLICKER := 1.0 / 9.0

## How often the circle reports itself to the crowd mind. Not every frame: the
## hive's feelings are stirred in lumps and sixty lumps a second would peg it.
const CHEER_EVERY := 3.0

var village: Village
var creature: Creature

var _effigy: Node3D = null
var _faces: Array[MeshInstance3D] = []
var _scratches: Array[Node3D] = []
var _flames: Array[Node3D] = []
var _recarve_left := 0.0
var _flicker_left := 0.0
var _cheer_left := 0.0


## A NEST IS RAISED FOR SOMEBODY, not for something — so a village only wants one
## once it has come to BELIEVE, and there must be a beast to raise it for. It is
## the last thing a town builds and the only one that is a gift.
##
## Asked here rather than on the village for the same reason Workshop.short_of
## is: it is entirely a question about nests.
static func wanted_by(village: Village) -> bool:
	return village.nest == null and village.converted and village.belief > 45.0 \
		and village.construction_site == null \
		and village.store.lumber >= 6 and village.store.stone >= 10


## RAISED. Kept here with `wanted_by` rather than on the village, which was
## already sitting exactly on its public-method limit — and this is a question
## about nests either way.
static func raise_at(village: Village, world_spot: Vector3, beast: Creature) -> void:
	if village.nest != null or beast == null \
			or not village.store.try_spend_materials(6, 10):
		return
	var n := CreatureNest.new()
	n.village = village
	n.creature = beast
	n.position = village.to_local(world_spot)
	village.add_child(n)
	village.nest = n
	if village.is_player_home:
		GameState.announce(
			"%s has raised a nest for your creature." % village.village_name)


func _ready() -> void:
	add_to_group("creature_nest")
	set_meta("hover_name", "The Nest")
	collision_layer = 4
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.0, 3.0, 2.0)
	col.shape = shape
	col.position = Vector3(0, 1.5, -3.4)
	add_child(col)
	var custom := ModelBank.instantiate("nest")
	if custom != null:
		add_child(custom)
	else:
		_build_lodge()
		_build_wall()
		_build_effigy()
	_build_pool()
	_build_fire()
	_recarve_left = randf() * RECARVE
	recarve()


## THE LODGE: a long low hall open to the fire, banked with the comfortable
## things — bushes to flop into and a couple of trees for shade.
func _build_lodge() -> void:
	add_child(Util.box(Vector3(7.0, 0.5, 4.4), Color(0.42, 0.4, 0.38), Vector3(0, 0.25, -3.0)))
	add_child(Util.box(Vector3(7.0, 2.6, 0.5), Color(0.5, 0.47, 0.43), Vector3(0, 1.5, -5.0)))
	for x: float in [-3.3, 3.3]:
		add_child(Util.box(Vector3(0.5, 2.6, 4.4), Color(0.5, 0.47, 0.43), Vector3(x, 1.5, -3.0)))
	add_child(Util.box(Vector3(7.6, 0.4, 5.0), Color(0.38, 0.3, 0.22), Vector3(0, 3.0, -3.0)))
	# The comfortable part. A bed of moss and two bolsters of bush, because the
	# thing he mostly does here is lie down.
	add_child(Util.box(Vector3(4.4, 0.3, 2.4), Color(0.3, 0.42, 0.26), Vector3(0, 0.65, -3.0)))
	for x: float in [-2.0, 2.0]:
		add_child(Util.lite_sphere(0.9, Color(0.24, 0.38, 0.22), Vector3(x, 0.9, -1.2)))


## THE WALL OF FACES. Six stones, and each is cut deeper and set prouder the
## further the creature has gone down that axis of himself. They are not labelled
## and never will be: the point is that a player comes to know which stone is
## which by watching which one grows.
##
## UNDER EACH ONE, SCRATCHES. Tally marks hacked into the rock — the oldest
## writing there is, and the only kind a village this age would have. They are
## not decoration: there is one scratch per notch of that axis, so the wall is
## literally a record kept in the obvious way, and a player standing back from it
## reads their creature off the stone the way you read a prison wall.
##
## Hold a press on the wall and it says the whole of it in words. See `chronicle`.
func _build_wall() -> void:
	for i in FACES.size():
		var x := -2.6 + float(i) * 1.04
		var face := Util.box(Vector3(0.8, 0.9, 0.25),
			Color(0.54, 0.5, 0.45), Vector3(x, 1.7, -4.7))
		add_child(face)
		_faces.append(face)
		var marks := Node3D.new()
		marks.position = Vector3(x, 0.95, -4.66)
		add_child(marks)
		_scratches.append(marks)


## RE-SCRATCH ONE STONE. A mark per notch, in fives with the fifth struck
## across the other four, because that is how anybody who has ever counted
## anything on a wall has done it.
func _scratch(marks: Node3D, how: float) -> void:
	for old in marks.get_children():
		old.queue_free()
	var count := int(round(absf(how) * 9.0))
	var pale := Color(0.78, 0.74, 0.66) if how >= 0.0 else Color(0.2, 0.17, 0.15)
	for i in count:
		var group := i / 5
		var within := i % 5
		var x := -0.28 + float(group) * 0.24 + float(within) * 0.045
		if within == 4:
			# The one struck across the other four.
			var bar := Util.lite_box(Vector3(0.02, 0.24, 0.02), pale,
				Vector3(x - 0.09, 0.0, 0.0))
			bar.rotation_degrees.z = 62.0
			marks.add_child(bar)
		else:
			marks.add_child(Util.lite_box(Vector3(0.018, 0.2, 0.02), pale,
				Vector3(x, 0.0, 0.0)))


## HIS OWN LIKENESS, at his own size. A hatchling gets a stone the height of a
## milk jug; a giant gets one that shows over the lodge roof — and a beast that
## somebody has starved down watches his idol shrink with him.
func _build_effigy() -> void:
	_effigy = Node3D.new()
	_effigy.position = Vector3(0, 0.5, -3.0)
	_effigy.add_child(Util.lite_capsule(0.42, 1.1, Color(0.46, 0.42, 0.4), Vector3(0, 0.85, 0)))
	_effigy.add_child(Util.lite_sphere(0.34, Color(0.5, 0.46, 0.43), Vector3(0, 1.65, 0)))
	for x: float in [-0.2, 0.2]:
		_effigy.add_child(Util.lite_box(Vector3(0.12, 0.5, 0.12),
			Color(0.4, 0.36, 0.34), Vector3(x, 0.25, 0)))
	add_child(_effigy)


## THE POOL he drinks from and sees himself in. Shallow, still, and dark enough
## to hold a reflection — which is all the mirror this game needs.
func _build_pool() -> void:
	var pool := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(5.0, 4.0)
	pool.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.26, 0.32, 0.86)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if Quality.water_alpha() \
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.metallic = 0.5
	mat.roughness = 0.12
	pool.material_override = mat
	pool.position = Vector3(5.4, 0.06, 2.2)
	add_child(pool)


## THE FIRE they dance around, and the torches along the wall that make the
## faces move. Both are the cheap pooled flame the rest of the world uses.
func _build_fire() -> void:
	var hearth := Util.lite_cylinder(1.1, 0.3, Color(0.3, 0.28, 0.26), Vector3(0, 0.15, 0))
	add_child(hearth)
	var fire := Util.small_flame(1.9)
	fire.position = Vector3(0, 0.2, 0)
	add_child(fire)
	_flames.append(fire)
	for x: float in [-3.0, -1.0, 1.0, 3.0]:
		var torch := Util.small_flame(0.7)
		torch.position = Vector3(x, 2.3, -4.4)
		add_child(torch)
		_flames.append(torch)
		add_child(Util.lite_box(Vector3(0.12, 1.0, 0.12),
			Color(0.35, 0.26, 0.18), Vector3(x, 1.9, -4.4)))


func _process(delta: float) -> void:
	if Util.sim_stride(global_position) > 4:
		return
	_flicker_left -= delta
	if _flicker_left <= 0.0:
		_flicker_left = FLICKER
		# One shared breath across every flame, so the wall moves as one fire
		# rather than as six independent sparkles.
		var beat := 0.88 + randf() * 0.3
		for f in _flames:
			if is_instance_valid(f):
				f.scale = Vector3(beat, 0.85 + randf() * 0.4, beat)
	_recarve_left -= delta
	if _recarve_left <= 0.0:
		_recarve_left = RECARVE
		recarve()


## CUT THE WALL TO MATCH HIM. Each face stands out from the stone by how far he
## has gone down that axis, and darkens when he has gone the other way — so a
## merciless creature has a sunken, black-eyed mercy stone, and nobody had to
## write the word "cruel" anywhere.
func recarve() -> void:
	if creature == null or not is_instance_valid(creature):
		return
	for i in mini(_faces.size(), FACES.size()):
		var face := _faces[i]
		if not is_instance_valid(face):
			continue
		var how: float = creature.mind.ethos.standing(FACES[i])
		face.position.z = -4.7 + clampf(how, -0.4, 1.0) * 0.22
		face.scale = Vector3.ONE * (1.0 + clampf(how, -0.5, 1.0) * 0.35)
		var stone := Color(0.54, 0.5, 0.45)
		face.material_override = Util.shared_mat(
			stone.lightened(maxf(how, 0.0) * 0.3).darkened(maxf(-how, 0.0) * 0.55))
		if i < _scratches.size() and is_instance_valid(_scratches[i]):
			_scratch(_scratches[i], how)
	if _effigy != null and is_instance_valid(_effigy):
		# Cut to his true size, which is the one readout a player cannot argue
		# with: a starved creature's idol is small.
		_effigy.scale = Vector3.ONE * lerpf(0.5, 2.6, creature.growth)


## WHAT HE CAN DO HERE, offered like everything else and recommended like
## nothing else. He is told only that the place exists; whether he ever comes is
## between him and what he has learned — a beast raised badly may never use the
## house his village built him, and that is a thing worth being able to see.
static func offer(who: Creature, opts: Dictionary) -> void:
	var nest := who.get_tree().get_first_node_in_group("creature_nest") as CreatureNest
	if nest == null or not is_instance_valid(nest):
		return
	if nest.global_position.distance_to(who.global_position) > GROUNDS:
		return
	who.offer_option(opts, "lounge", "nest", nest)
	who.offer_option(opts, "rest", "nest", nest)
	# The pool. He drinks from it, and he is the only thing in the game that
	# can look into it — which is not a mechanic so much as somewhere to be.
	who.offer_option(opts, "commune", "nest", nest)


## Where the circle forms, for a dancer of this number.
func ring_spot(which: int) -> Vector3:
	var a := float(which) / float(DANCERS) * TAU
	return global_position + Vector3(cos(a), 0.0, sin(a)) * RING


## Where he lies down, and where he drinks.
func bed() -> Vector3:
	return global_position + Vector3(0, 0, -3.0)


func water() -> Vector3:
	return global_position + Vector3(5.4, 0, 2.2)


## AN EVENING OF IT. Called once a second by the village while a circle is
## dancing; the prayer is the village's, not the creature's, and it is gathered
## whether he deigns to turn up or not.
func dance_tick(dancers: int, delta: float) -> void:
	if dancers <= 0:
		return
	GameState.add_prayer_power(PRAYER_PER_DANCER * float(dancers) * delta)
	if village == null or not is_instance_valid(village):
		return
	village.belief = minf(
		village.belief + BELIEF_PER_DANCER * float(dancers) * delta, 100.0)
	# AND THE TOWN FEELS IT. The crowd mind knew nothing of any of this — it
	# could watch its own village dance round a fire all evening and record no
	# joy at all. Stirred at a rate rather than per dancer per frame, so a long
	# circle warms the town and a circle of two barely registers.
	_cheer_left -= delta
	if _cheer_left <= 0.0:
		_cheer_left = CHEER_EVERY
		village.hive.witness("circle", global_position,
			clampf(float(dancers) / float(DANCERS), 0.2, 1.5))


## THE WHOLE WALL, IN WORDS — what a long press on the stone brings up.
##
## TWO COLUMNS: WHAT HE HOLDS, AND WHAT IS SO. That is the whole idea and it is
## worth stating plainly, because a single list of statistics is what the
## creature panel already was and this is meant to be a different kind of
## knowing. The left column is the world as he has it: what he believes, what he
## thinks he needs, what he reckons you are. The right is the world as it
## actually stands.
##
## THE GAP BETWEEN THE COLUMNS IS HIM. A creature that believes the woods are
## deadly because he was mobbed there once, standing beside a line saying the
## woods are empty, is a thing you can only say this way — and a creature who
## trusts you completely, beside a count of how many times you have struck him,
## is the hardest line in the game to look at.
##
## It is also why the wall is somewhere you walk to and hold still in front of,
## rather than a key you press. You are getting closer to him to read it.
func chronicle() -> String:
	if creature == null or not is_instance_valid(creature):
		return "The stone is blank. Nobody has been read here yet."
	var lines := PackedStringArray()
	lines.append("SCRATCHED INTO THE STONE")
	lines.append("")
	lines.append("%-34s %s" % ["WHAT HE HOLDS", "WHAT IS SO"])
	lines.append("%-34s %s" % ["-------------", "----------"])
	for pair: Array in _columns():
		# Trimmed to the column rather than allowed to shove the right-hand side
		# along — two columns that do not line up are one column.
		var held: String = String(pair[0])
		if held.length() > 33:
			held = held.substr(0, 32) + "…"
		lines.append("%-34s %s" % [held, pair[1]])
	lines.append("")
	lines.append("CUT INTO THE SIX STONES")
	for which: String in FACES:
		var how: float = creature.mind.ethos.standing(which)
		var bar := ""
		for i in 9:
			bar += "|" if float(i) < absf(how) * 9.0 else "."
		lines.append("  %-11s %s  %s" % [which, bar,
			"" if absf(how) < 0.12 else ("much" if how > 0.0 else "against")])
	return "\n".join(lines)


## THE PAIRS. Each is one thing he carries and the same thing as it really is.
func _columns() -> Array:
	var mind := creature.mind
	var body := creature.body
	var out := []
	out.append(["they have made a %s of him" % mind.ethos.reading(),
		"he is %s" % creature.welfare.account()])
	# Hunger is the plainest gap there is: appetite is a feeling, a full belly
	# is a fact, and a badly-raised creature routinely has both at once.
	out.append(["he feels %s" % _hunger_word(creature.hunger),
		"his belly is %d%% full" % int(body.fullness(creature.growth) * 100.0)])
	out.append(["he trusts you %s" % _trust_word(creature.trust),
		"you have struck him %d times" % creature.welfare.struck])
	# THE ROW THAT MATTERS MOST. What he has concluded about the world, set
	# beside what is actually standing around him — because a creature that
	# believes the woods are deadly, next to a line saying nothing has hunted
	# here all day, is the whole of what this wall is for.
	var creed: Array = mind.beliefs.creed(1)
	out.append(["he believes %s" % (
		"nothing firmly yet" if creed.is_empty() else String(creed[0])),
		_what_is_out_there()])
	var habits: Array = mind.character_account()
	out.append(["he is given to %s" % (
		"nothing settled" if habits.is_empty() else String(habits[0])),
		"his hands know %s" % _best_skill()])
	return out


## WHAT IS ACTUALLY PROWLING, right now, within sight of this place. The plainest
## fact available to set against whatever he has decided the world is like.
func _what_is_out_there() -> String:
	var hunters := 0
	for a in get_tree().get_nodes_in_group("animals"):
		var beast := a as Animal
		if is_instance_valid(beast) and beast.spec.get("predator", false) \
				and beast.global_position.distance_to(global_position) < 70.0:
			hunters += 1
	if hunters == 0:
		return "nothing is hunting near here"
	return "%d hunt within sight of the fire" % hunters


func _hunger_word(hunger: float) -> String:
	if hunger > 75.0:
		return "ravenous"
	if hunger > 45.0:
		return "hungry"
	return "no want of food"


func _trust_word(trust: float) -> String:
	if trust > 70.0:
		return "entirely"
	if trust > 35.0:
		return "well enough"
	if trust > 10.0:
		return "warily"
	return "not at all"


func _best_skill() -> String:
	var best := ""
	var level := 0
	for verb: String in creature.mind.skill:
		var got: int = creature.mind.skill_level(verb)
		if got > level:
			level = got
			best = verb
	return "nothing yet" if best == "" else "%s, %d of 9" % [best, level]


func hover_text() -> String:
	if creature == null or not is_instance_valid(creature):
		return "The Nest — waiting for somebody"
	return "The Nest — %s  (hold to read the stone)" % creature.mind.ethos.reading()
