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
const FACES: Array[String] = ["mercy", "bounty", "order", "fellowship", "daring", "devotion"]

## HOW BIG THE NEST IS: big enough for the biggest creature there can ever BE,
## from the day the village raises it.
##
## It used to be a seven-metre hut, which fitted the creature you had on the
## afternoon you got it and nothing after. A creature at full growth stands
## CreatureBody.FULL_HEIGHT tall — and a thing that tall lying down is about
## that long — so the bed is measured off that and everything else is measured
## off the bed. Nobody ever outgrows their own home, and a village that raises
## one is making a promise about what its god's beast may become.
##
## It is also why there is NO ROOF. A lodge with a ceiling has a height the
## creature can exceed; an open bed under the sky has none, and a den is what
## this was always meant to be rather than a house.
const BED_LONG := CreatureBody.FULL_HEIGHT * 1.1
const BED_DEEP := BED_LONG * 0.5
const BED_MID := -(BED_DEEP * 0.5 + 5.0)
const WALL_HIGH := 4.2
const WALL_AT := BED_MID - BED_DEEP * 0.5 - 0.8
const POOL_R := BED_DEEP * 0.18
## How wide one cell of the draped floor is. Three metres gives a forty-two
## metre bed fourteen cells across — enough to follow a hillside honestly, few
## enough that the whole nest is a couple of hundred triangles.
const DRAPE_CELL := 3.0

## How wide the clearing is, how far the dance stands from the fire, and how
## many may join a circle before it is full. The clearing follows the bed; the
## DANCE does not, because a dance is villager-sized whatever the creature is —
## eight people round a fire stand the same distance apart in any world.
const GROUNDS := BED_LONG * 0.8
## What other buildings must keep clear of. Smaller than the grounds on purpose:
## the grounds are how far away you still count as BEING here, and that is a
## social question, not a question of what the bed is standing on.
const FOOTPRINT := BED_LONG * 0.55
const RING := 4.2
const DANCERS := 8

## THE VIEW FROM THE FRONT — see `viewing`. A shade above level so sky and
## ground both show; far enough back that the whole stone wall is in frame and
## near enough that the faces on it can be told apart; and an eye height that
## clears a creature lying down without looking over the top of him.
const VIEW_PITCH := 7.0
const VIEW_BACK := 34.0
const VIEW_EYE := 6.0

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
static func wanted_by(town: Village) -> bool:
	return town.nest == null and town.converted and town.belief > 45.0 \
		and town.construction_site == null \
		and town.store.lumber >= 6 and town.store.stone >= 10


## RAISED. Kept here with `wanted_by` rather than on the village, which was
## already sitting exactly on its public-method limit — and this is a question
## about nests either way.
static func raise_at(town: Village, world_spot: Vector3, beast: Creature) -> void:
	if town.nest != null or beast == null \
			or not town.store.try_spend_materials(6, 10):
		return
	var n := CreatureNest.new()
	n.village = town
	n.creature = beast
	n.position = town.to_local(world_spot)
	town.add_child(n)
	town.nest = n
	if town.is_player_home:
		GameState.announce(
			"%s has raised a nest for your creature." % town.village_name)


func _ready() -> void:
	add_to_group("creature_nest")
	set_meta("hover_name", "The Nest")
	collision_layer = 4
	collision_mask = 0
	# THE WALL IS THE THING YOU TOUCH. The collider is the whole stone face and
	# nothing else — it is what a long press reads, and at seven metres it was a
	# hard thing to put a thumb on. It is the length of the bed now.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BED_LONG, WALL_HIGH, 1.8)
	col.shape = shape
	col.position = Vector3(0, _ground_local(0.0, WALL_AT) + WALL_HIGH * 0.5, WALL_AT)
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
## A BROAD OPEN BED WITH A STONE WALL BEHIND IT, and nothing over it. No roof
## and no side walls: a creature that may end up thirty-eight metres tall does
## not want a hut, it wants somewhere to lie down that is unmistakably HIS, and
## walls it would have to step over are only an insult at that size.
func _build_lodge() -> void:
	# THE FLOOR IS DRAPED OVER THE LAND, not laid across it.
	#
	# It was two boxes forty-two metres long, and a box is flat. So the nest cut
	# into every hillside it was built on and hung out over the water on the
	# other side — a grey slab floating above a valley, which is what it looked
	# like because it is what it was. The bed of a creature that lies down
	# outdoors should be a hollow in the ground, and it is now: a grid of
	# triangles whose every corner sits on the real height of the land under it.
	add_child(_drape(BED_LONG * 1.1, BED_DEEP * 1.2, BED_MID, 0.12,
		Color(0.42, 0.4, 0.38)))
	# The comfortable part, draped over the same ground a hand's breadth higher.
	add_child(_drape(BED_LONG, BED_DEEP, BED_MID, 0.34, Color(0.3, 0.42, 0.26)))
	# The wall of faces stands at the back of it, the full width of the bed, in
	# segments that step with the ground rather than one long level lintel.
	_build_back_wall()
	var bolster := BED_DEEP * 0.11
	for x: float in [-BED_LONG * 0.28, BED_LONG * 0.28]:
		var at := BED_MID + BED_DEEP * 0.36
		add_child(Util.lite_sphere(bolster, Color(0.24, 0.38, 0.22),
			Vector3(x, _ground_local(x, at) + 0.5 + bolster * 0.4, at)))


## THE GROUND UNDER A LOCAL POINT, in this node's own space. The nest may be
## turned to any heading and parented anywhere, so the sample has to go out to
## the world and come back rather than assume the two frames agree.
func _ground_local(x: float, z: float) -> float:
	var world := get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world == null:
		return 0.0
	var out := to_global(Vector3(x, 0.0, z))
	return to_local(Vector3(out.x, world.surface_at(out.x, out.z), out.z)).y


## A SHEET OF TRIANGLES LAID ON THE LAND. One cell every DRAPE_CELL metres, each
## corner on the real ground, flat-shaded so it reads as the same faceted
## country everything else here is made of.
func _drape(long: float, deep: float, at_z: float, lift: float,
		color: Color) -> MeshInstance3D:
	var across := maxi(int(long / DRAPE_CELL), 2)
	var along := maxi(int(deep / DRAPE_CELL), 2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)     # flat shading: one normal per face
	for i in across:
		for j in along:
			var x0 := -long * 0.5 + long * float(i) / float(across)
			var x1 := -long * 0.5 + long * float(i + 1) / float(across)
			var z0 := at_z - deep * 0.5 + deep * float(j) / float(along)
			var z1 := at_z - deep * 0.5 + deep * float(j + 1) / float(along)
			var a := Vector3(x0, _ground_local(x0, z0) + lift, z0)
			var b := Vector3(x1, _ground_local(x1, z0) + lift, z0)
			var c := Vector3(x1, _ground_local(x1, z1) + lift, z1)
			var d := Vector3(x0, _ground_local(x0, z1) + lift, z1)
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var sheet := MeshInstance3D.new()
	sheet.mesh = st.commit()
	sheet.material_override = Util.shared_mat(color)
	return sheet


## THE BACK WALL, in segments. One long box across a slope buries one end and
## leaves the other in the air; a row of them each standing on its own ground
## reads as a wall somebody built on a hillside.
func _build_back_wall() -> void:
	var bays := maxi(int(BED_LONG / DRAPE_CELL), 3)
	var wide := BED_LONG / float(bays)
	for i in bays:
		var x := -BED_LONG * 0.5 + wide * (float(i) + 0.5)
		var base := _ground_local(x, WALL_AT)
		add_child(Util.box(Vector3(wide * 1.02, WALL_HIGH, 0.7),
			Color(0.5, 0.47, 0.43), Vector3(x, base + WALL_HIGH * 0.5, WALL_AT)))


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
	# Spread across the whole wall, and cut at a size you can read from the fire
	# rather than at a size that suited a seven-metre hut.
	var step := BED_LONG * 0.8 / float(FACES.size())
	var wide := step * 0.62
	var front := WALL_AT + 0.45
	for i in FACES.size():
		var x := (float(i) - (FACES.size() - 1) * 0.5) * step
		var base := _ground_local(x, front)
		var face := Util.box(Vector3(wide, wide * 1.1, 0.25),
			Color(0.54, 0.5, 0.45), Vector3(x, base + WALL_HIGH * 0.58, front))
		add_child(face)
		_faces.append(face)
		var marks := Node3D.new()
		marks.position = Vector3(x, base + WALL_HIGH * 0.25, front + 0.04)
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
		@warning_ignore("integer_division")
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
	plane.size = Vector2(POOL_R * 2.0, POOL_R * 1.6)
	pool.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.26, 0.32, 0.86)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if Quality.water_alpha() \
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.metallic = 0.5
	mat.roughness = 0.12
	pool.material_override = mat
	var pool_z := POOL_R * 0.9
	var pool_x := BED_LONG * 0.32
	pool.position = Vector3(pool_x, _ground_local(pool_x, pool_z) + 0.1, pool_z)
	add_child(pool)


## WHERE THE TORCHES STAND, evenly along the wall however wide the wall is.
## More of them than the old four, because four spread over forty metres is not
## torchlight, it is four torches.
func _torch_line() -> Array[float]:
	var out: Array[float] = []
	var many := maxi(int(BED_LONG / 5.0), 4)
	for i in many:
		out.append((float(i) - (many - 1) * 0.5) * (BED_LONG * 0.9 / float(many)))
	return out


## THE FIRE they dance around, and the torches along the wall that make the
## faces move. Both are the cheap pooled flame the rest of the world uses.
func _build_fire() -> void:
	var hearth := Util.lite_cylinder(1.1, 0.3, Color(0.3, 0.28, 0.26), Vector3(0, 0.15, 0))
	add_child(hearth)
	var fire := Util.small_flame(1.9)
	fire.position = Vector3(0, 0.2, 0)
	add_child(fire)
	_flames.append(fire)
	for x: float in _torch_line():
		var torch := Util.small_flame(0.7)
		torch.position = Vector3(x, WALL_HIGH * 0.78, WALL_AT + 0.6)
		add_child(torch)
		_flames.append(torch)
		add_child(Util.lite_box(Vector3(0.12, 1.0, 0.12),
			Color(0.35, 0.26, 0.18), Vector3(x, WALL_HIGH * 0.6, WALL_AT + 0.6)))


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
## THE NEST THE CREATURE IS STANDING ON THE GROUNDS OF, or null.
static func holding(beast: Node3D) -> CreatureNest:
	if beast == null or not is_instance_valid(beast):
		return null
	for n in beast.get_tree().get_nodes_in_group("creature_nest"):
		var nest := n as CreatureNest
		if nest != null and is_instance_valid(nest) \
				and nest.global_position.distance_to(beast.global_position) <= GROUNDS:
			return nest
	return null


## WHERE TO STAND TO SEE ALL OF IT: a villager's eye view from the front of the
## grounds, low to the earth and looking up into the place.
##
## Deliberately not a lock-on. A lock-on centres the beast and orbits him, which
## at forty metres tall is a wall of creature and nothing else — no stones
## behind him, no fire, no dancers, no torches, no trees. What is wanted when
## you ask to see him at home is the SHOT: everything that makes the nest what
## it is, in one frame, from where somebody walking past the front of it stands.
##
## The aim sits between his bed and the wall so the stones read over his back
## rather than being hidden behind him — and they are the thing you have to be
## able to put a thumb on.
func viewing() -> Dictionary:
	return {
		"aim": global_position + basis * Vector3(0.0, VIEW_EYE, BED_MID * 0.55),
		"yaw": global_rotation.y,
		"pitch": VIEW_PITCH,
		"zoom": VIEW_BACK,
	}


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
## IS THIS SPOT INSIDE THE NEST? Asked by Village._spot_blocked before it puts
## a building down.
##
## IT WAS A RADIUS FROM THE NODE'S ORIGIN, AND THE NEST IS NOT ROUND AND NOT
## CENTRED ON ITS ORIGIN. The bed is BED_LONG by BED_DEEP — forty-two metres by
## twenty-one — and it sits BED_MID behind the origin, with the wall of faces a
## further BED_DEEP/2 + 0.8 back again. So the far edge of the stonework is 27.7
## metres from the origin while FOOTPRINT, the circle builders were told to keep
## out of, is 23.1. Four and a half metres of the nest was fair ground to build
## on, and it is the deepest part of it — which is why a town would put a hut
## through the back wall and a mill in the fire pit.
##
## The real shape is a rectangle in the nest's own frame, so this asks it in the
## nest's own frame. Cheap, exact, and it turns with the nest.
func covers(world_spot: Vector3, room := 0.0) -> bool:
	var here := to_local(world_spot)
	var half_long := BED_LONG * 0.55 + room
	var near_z := BED_MID + BED_DEEP * 0.6 + room
	var far_z := WALL_AT - 0.9 - room
	return absf(here.x) <= half_long and here.z <= near_z and here.z >= far_z


func bed() -> Vector3:
	return global_position + Vector3(0, 0, BED_MID)


func water() -> Vector3:
	return global_position + Vector3(BED_LONG * 0.32, 0, POOL_R * 0.9)


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
