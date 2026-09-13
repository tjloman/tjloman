class_name CreatureStake
extends Node3D
## THE POST AND THE ROPE, and the first thing your creature ever knows.
##
## A young creature was loosed on the world the moment it existed, with a mind
## that had no opinion about anything and a village full of people forty metres
## away. So the first thing every creature in this game ever did was walk into
## town and eat somebody, and the player — who had not yet been told the beast
## could be led, praised or forbidden — watched it happen. Nothing about that is
## the player's fault and nothing about it is the creature's.
##
## So it starts on a rope. A post in the ground, a tether about twenty metres
## long, and a creature that can do ABSOLUTELY EVERYTHING within it: eat, sleep,
## look about, learn, be handed things, be praised, be scolded, be shown what a
## granary is for. What it cannot do is wander off and find out what a villager
## tastes like before anyone has told it not to.
##
## THE ROPE COMES OFF WHEN YOU LEARN TO LEAD IT. Not on a timer and not when the
## creature has behaved well enough — when the PLAYER has been taught the leash,
## which is the tool that replaces the rope. That is the whole bargain: you are
## given a creature you cannot lose, and you get to keep it loose the moment you
## can steer it. See Tutorial's lead step, which calls `pull_up`.
##
## IT IS NOT A CAGE. Nothing about being staked teaches the creature anything —
## it is not punished for reaching the end, its welfare does not suffer, and it
## does not learn that the world is small. It simply cannot get further. A rope
## is a fact about the world, and a creature that has never known anything else
## has nothing to resent.

## How much ground it has. Twenty-two metres is a wide circle to stand in — room
## to run, room for the player to throw it food and watch it fetch — and far too
## small to reach a village that was placed a good way off on purpose.
const TETHER := 22.0
## How far past the rope it may drift before being brought up short, so a run at
## the end reads as a rope going taut rather than a wall.
const GIVE := 1.4

const POST_HIGH := 2.4
const POST_WIDE := 0.22
const ROPE_BORE := 0.07


## Found once. `hold` runs every frame on the creature's own tick.
static var _here: CreatureStake = null

var creature: Creature = null

var _rope: MeshInstance3D = null


## DRIVE ONE, where the creature stands. Called when the creature is first
## raised; does nothing if there is already one in the world.
static func plant(who: Creature) -> CreatureStake:
	if _here != null and is_instance_valid(_here):
		return _here
	var stake := CreatureStake.new()
	stake.creature = who
	var parent := who.get_parent()
	if parent == null:
		return null
	parent.add_child(stake)
	stake.global_position = who.global_position
	var world := who.get_tree().get_first_node_in_group("world_gen") as WorldGen
	if world != null:
		stake.global_position.y = world.surface_at(
			stake.global_position.x, stake.global_position.z)
	_here = stake
	GameState.announce("Your creature is tethered here until you have learned to lead it.")
	return stake


## The stake in the world, if there is one.
static func of(tree: SceneTree) -> CreatureStake:
	if _here != null and is_instance_valid(_here):
		return _here
	_here = null
	if tree != null:
		_here = tree.get_first_node_in_group("creature_stake") as CreatureStake
	return _here


## THE ROPE PULLS. Called from the creature's own tick, every frame, and costs
## one null check on a world with no stake in it — which is every world after
## the lesson is learned.
static func hold(who: Creature) -> void:
	var stake := of(who.get_tree())
	if stake == null or stake.creature != who:
		return
	stake.pull_in(who)


## THE ROPE COMES OFF. The tutorial's lead step calls this; so does anything
## else that decides the player is ready.
static func pull_up(tree: SceneTree) -> void:
	var stake := of(tree)
	if stake == null:
		return
	GameState.announce("You pull the stake from the ground. Your creature is yours to lead now.")
	_here = null
	stake.queue_free()


## Is this spot within the rope? Used to keep the creature from CHOOSING to walk
## somewhere it cannot get to, which is the difference between a tether and a
## creature that spends its life straining at one.
static func reachable(tree: SceneTree, spot: Vector3) -> bool:
	var stake := of(tree)
	if stake == null:
		return true
	return stake.global_position.distance_to(spot) <= TETHER


## And the nearest point on the rope to somewhere it wanted to go — so a
## leashed-off target becomes "as near to that as I can get" rather than
## nothing at all.
static func nearest_within(tree: SceneTree, spot: Vector3) -> Vector3:
	var stake := of(tree)
	if stake == null:
		return spot
	var from := stake.global_position
	var out := spot - from
	out.y = 0.0
	if out.length() <= TETHER:
		return spot
	return from + out.normalized() * TETHER


func _ready() -> void:
	add_to_group("creature_stake")
	var post := Util.box(Vector3(POST_WIDE, POST_HIGH, POST_WIDE),
		Color(0.42, 0.31, 0.19), Vector3(0, POST_HIGH * 0.5, 0))
	add_child(post)
	# A collar of stones round the foot, so it reads as something somebody drove
	# in rather than a stick that happens to be there.
	for i in 5:
		var a := TAU * i / 5.0
		add_child(Util.lite_sphere(0.22, Color(0.55, 0.54, 0.5),
			Vector3(cos(a) * 0.55, 0.06, sin(a) * 0.55), 5))
	var cord := BoxMesh.new()
	cord.size = Vector3(ROPE_BORE, ROPE_BORE, 1.0)
	_rope = Util.mesh_node(cord, Color(0.72, 0.62, 0.42), Vector3.ZERO) as MeshInstance3D
	add_child(_rope)


## BRING IT UP SHORT, and draw the rope between. The creature keeps whatever it
## was doing; it simply does not get any further away.
func pull_in(who: Creature) -> void:
	var out := who.global_position - global_position
	out.y = 0.0
	var span := out.length()
	if span > TETHER + GIVE:
		var held := global_position + out.normalized() * (TETHER + GIVE)
		who.global_position.x = held.x
		who.global_position.z = held.z
	_draw_rope(who)


func _draw_rope(who: Creature) -> void:
	if not is_instance_valid(_rope):
		return
	var from := global_position + Vector3.UP * (POST_HIGH * 0.8)
	var to := who.global_position + Vector3.UP * (0.9 * who.scale.y)
	var span := from.distance_to(to)
	if span < 0.3:
		_rope.visible = false
		return
	_rope.visible = true
	_rope.global_position = from.lerp(to, 0.5)
	_rope.look_at(to, Vector3.UP)
	# Taut when it is at the end of its reach, slack and dipped when it is not.
	_rope.scale = Vector3(1.0, 1.0, span)
	_rope.global_position.y -= (1.0 - clampf(span / TETHER, 0.0, 1.0)) * 0.9


func hover_text() -> String:
	return "The stake — your creature's tether, until you have learned to lead it"
