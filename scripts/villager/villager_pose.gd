class_name VillagerPose
extends RefCounted
## ONE POSE AT A TIME, BY NUMBER.
##
## A body used to be posed from a dozen places — tipped over for bed, dropped to
## the dirt for school, pitched over a corpse, laid prone when pinned or dying,
## tumbled when thrown — each one writing its own part of the body and trusting
## somebody else to put it back. Some ways out of bed never did, and hours into
## a game half a town crawled on its bellies from chore to chore.
##
## So a villager is in exactly ONE pose, named by a byte, and the byte is all
## the body shows. `apply` works the code out from what the villager is doing
## and, whenever it changes, writes EVERY part of the body from the table — the
## parts this pose leaves alone included, back to rest. Nothing else in the game
## moves those parts (tools/pose.py fails anything that does), so a pose cannot
## outlive the thing it was for: there is nothing left to forget to undo.
##
## THE CODES. The high nibble is how the body is held, the low one which of it:
##
##   0x0_  ON ITS FEET    00 idle  01 walk  02 run  03 work  04 carry  05 play
##                        06 pray  07 eat  08 attack  09 stretch
##   0x1_  LOW            10 sit (a class on the dirt)  11 feed (over a body)
##   0x2_  LYING          20 sleep
##   0x3_  FALLEN         30 fall (in the air: the throw turns the body)
##                        31 pinned (held down)  32 dying
##   0x4_  IN THE HAND    40 held

const IDLE := 0x00
const WALK := 0x01
const RUN := 0x02
const WORK := 0x03
const CARRY := 0x04
const PLAY := 0x05
const PRAY := 0x06
const EAT := 0x07
const ATTACK := 0x08
const STRETCH := 0x09
const SIT := 0x10
const FEED := 0x11
const SLEEP := 0x20
const FALL := 0x30
const PINNED := 0x31
const DYING := 0x32
const HELD := 0x40

## How far a body drops to sit on the dirt, and how far it pitches forward over
## a body it is eating — on its knees and its hands, the way an animal feeds.
const SIT_DROP := 0.42
const FEED_PITCH := 74.0
## Lying down, by the body; fallen, by the whole figure.
const SLEEP_PITCH := 80.0
const PRONE := 88.0

## CODE -> [clip, body pitch, drop, figure pitch]. The clip is what a rigged
## model plays (it owns its own pose, and none of the rest is written for it).
## A figure pitch of NAN is a part this pose hands to somebody else: in the air,
## the throw turns the whole figure (Villager.set_flight_spin).
const LOOK := {
	IDLE: ["idle", 0.0, 0.0, 0.0],
	WALK: ["walk", 0.0, 0.0, 0.0],
	RUN: ["run", 0.0, 0.0, 0.0],
	WORK: ["work", 0.0, 0.0, 0.0],
	CARRY: ["carry", 0.0, 0.0, 0.0],
	PLAY: ["play", 0.0, 0.0, 0.0],
	PRAY: ["pray", 0.0, 0.0, 0.0],
	EAT: ["eat", 0.0, 0.0, 0.0],
	ATTACK: ["attack", 0.0, 0.0, 0.0],
	STRETCH: ["stretch", 0.0, 0.0, 0.0],
	SIT: ["sit", 0.0, SIT_DROP, 0.0],
	FEED: ["feed", FEED_PITCH, SIT_DROP, 0.0],
	SLEEP: ["sleep", SLEEP_PITCH, 0.0, 0.0],
	FALL: ["fall", 0.0, 0.0, NAN],
	PINNED: ["fall", 0.0, 0.0, PRONE],     # no rig here has a clip for this
	DYING: ["dying", 0.0, 0.0, PRONE],
	HELD: ["idle", 0.0, 0.0, 0.0],
}


## WHAT POSE THIS IS, from what the villager is doing — never from a flag that
## something set and something else must clear.
static func of(who: Villager) -> int:
	# ON ALL FOURS outranks everything: the one meal in the game that is not a
	# meal. Asked of what they are eating, so there is nothing to leave set.
	if who.state == Villager.State.EATING and VillagerLook.eating_a_person(who):
		return FEED
	match who.state:
		# SEATED ONLY IN SCHOOL, and only when the school says so: a class on
		# its feet and a class on the dirt are the same state. A seat asked for
		# anywhere else is ignored — which is what stops a child who leaves the
		# yard sitting down sitting down for good.
		Villager.State.AT_SCHOOL: return SIT if who._seated else IDLE
		Villager.State.PINNED: return PINNED
		Villager.State.DYING: return DYING
		Villager.State.FALLING: return FALL
		Villager.State.HELD: return HELD
		Villager.State.SLEEPING: return SLEEP
		Villager.State.HAULING: return CARRY
		Villager.State.CIRCLING, Villager.State.PLAY: return PLAY
		Villager.State.GO_ARM, Villager.State.FLEE: return RUN
		Villager.State.FIGHT: return ATTACK
		Villager.State.EATING: return EAT
		Villager.State.WORSHIPPING, Villager.State.PREACHING: return PRAY
		Villager.State.FARMING, Villager.State.CHOPPING, Villager.State.QUARRYING, \
		Villager.State.BUILDING, Villager.State.BUILDING_FARM, \
		Villager.State.BUILDING_EDUBBA, Villager.State.BUTCHERING, Villager.State.TAMING, \
		Villager.State.HUNTING, Villager.State.FISHING, Villager.State.TEACH, \
		Villager.State.BUILDING_NEST, Villager.State.BUILDING_SHOP, Villager.State.WORKING:
			return WORK
	if Vector2(who.velocity.x, who.velocity.z).length() > 0.3:
		return WALK
	# STANDING STILL — AND WAITING ON A THOUGHT, if the wait has gone on long
	# enough to see. Last of all: somebody mid-haul who is waiting for their
	# next plan goes on hauling.
	if Spool.stalled_for(who) >= VillagerLook.DITHER:
		return STRETCH
	return IDLE


## The clip a rigged model plays for this villager now.
static func clip(who: Villager) -> String:
	return String((LOOK[of(who)] as Array)[0])


## PUT THE BODY IN ITS POSE. Cheap when nothing has changed — one comparison —
## and when it has, every part is written, whether this pose moves it or not.
static func apply(who: Villager) -> void:
	var code := of(who)
	if code == who.pose_code:
		return
	who.pose_code = code
	if who._animator != null:
		return              # a rigged model's clips own its body; see Villager
	var look: Array = LOOK[code]
	if who._body_mesh != null and is_instance_valid(who._body_mesh):
		who._body_mesh.rotation_degrees.x = float(look[1])
	if who._visuals != null and is_instance_valid(who._visuals):
		who._visuals.position.y = -float(look[2])
		var figure := float(look[3])
		if not is_nan(figure):
			who._visuals.rotation = Vector3(deg_to_rad(figure), 0.0, 0.0)
