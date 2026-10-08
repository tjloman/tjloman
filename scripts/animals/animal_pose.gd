class_name AnimalPose
extends RefCounted
## ONE POSE AT A TIME, BY NUMBER — for a beast. See VillagerPose for the why.
##
## A beast's body was hardly posed at all: a rigged model picked a clip, and a
## thrown one was tumbled by turning the WHOLE ANIMAL, collision box included,
## put straight again only if it landed while still FALLING — and then facing
## north, its heading thrown away with the tilt. Caught in the hand mid-tumble,
## it stayed at whatever angle it had reached.
##
## Now the beast's looks hang on a figure of their own (Animal._figure), and
## the figure is the one part this file poses: the throw turns it while the pose
## is FALL; every other pose puts it back — and the body that walks, faces and
## collides is never tipped at all.
##
## THE CODES, high nibble the band:
##   0x0_  ON ITS FEET   00 idle  01 walk  02 run  03 graze  04 drink  05 maul
##   0x3_  FALLEN        30 fall (in the air: the throw turns the figure)
##   0x4_  IN THE HAND   40 held

const IDLE := 0x00
const WALK := 0x01
const RUN := 0x02
const GRAZE := 0x03
const DRINK := 0x04
const MAUL := 0x05
const FALL := 0x30
const HELD := 0x40

## Head down to the grass, the water or the kill: the figure pitched forward
## about its feet. Enough to read from across a field, not a somersault.
const HEAD_DOWN := 12.0

## CODE -> [clip, figure pitch]. NAN: the throw has the figure.
const LOOK := {
	IDLE: ["idle", 0.0],
	WALK: ["walk", 0.0],
	RUN: ["run", 0.0],
	GRAZE: ["graze", HEAD_DOWN],
	DRINK: ["drink", HEAD_DOWN],
	MAUL: ["graze", HEAD_DOWN],    # head down over a body; the nearest clip there is
	FALL: ["fall", NAN],
	HELD: ["idle", 0.0],
}


static func of(who: Animal) -> int:
	match who.state:
		Animal.State.FALLING: return FALL
		Animal.State.HELD: return HELD
		Animal.State.FLEE, Animal.State.CHASE: return RUN
		Animal.State.MAUL: return MAUL
		Animal.State.DRINKING: return DRINK
		Animal.State.GRAZE: return GRAZE
	return WALK if Vector2(who.velocity.x, who.velocity.z).length() > 0.3 else IDLE


static func clip(who: Animal) -> String:
	return String((LOOK[of(who)] as Array)[0])


## Every tick the beast is processed: one comparison when nothing has changed.
## A rigged model is told its clip; a plain one has its figure set — and the
## clip is played every time for a rig, which keeps it in step with its own
## loops exactly as before.
static func apply(who: Animal) -> void:
	var code := of(who)
	if who._animator != null:
		who.pose_code = code
		who._animator.play(clip(who))
		return
	if code == who.pose_code:
		return
	who.pose_code = code
	var figure := float((LOOK[code] as Array)[1])
	if who._figure != null and not is_nan(figure):
		who._figure.rotation = Vector3(deg_to_rad(figure), 0.0, 0.0)
