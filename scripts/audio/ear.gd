class_name Ear
extends AudioListener3D
## WHERE THE GOD IS LISTENING FROM, which is not where the camera is.
##
## Godot's default listener is the current Camera3D, and for almost every game
## that is right because the camera is roughly the player's head. This camera is
## not a head. It is a rig that orbits a point on the ground from anywhere
## between one and SEVENTY metres out (CameraRig.MAX_ZOOM), and every sound in
## the game falls off over about fifty.
##
## So the game got quieter the further you pulled back, and at a survey zoom —
## which is where a god game is actually PLAYED — a village burning in front of
## you made no sound at all. Not muffled. Silent, because everything in it was
## past the falloff of a listener sitting out in the sky behind your shoulder.
##
## THE GOD LISTENS FROM THE GROUND THEY ARE LOOKING AT, and a little from
## whatever their hand is over. The second half is the interesting one: in a
## game whose whole verb is a hand reaching into the world, the hand is where
## your attention IS. Reach into a burning street and it gets louder, because
## you have leaned in — and that costs nothing, needs no UI, and is true.
##
## THE ORIENTATION IS THE CAMERA'S, always. Position decides how loud a thing
## is; the BASIS decides which side of your head it is on, and that has to
## agree with which side of the screen it is on or the game feels broken in a
## way nobody can name.

## How far toward the hand the ear leans, 0..1. Not all the way: at 1.0 a god
## whose hand is resting on a hilltop hears nothing of the battle in the valley
## they are staring at, which is worse than the problem it solves.
const TOWARD_HAND := 0.45

## How high off the point the ear floats. A listener exactly on the ground
## hears a villager standing on it as a sound coming from inside itself, and
## the panning goes to nonsense at close range.
const EAR_HEIGHT := 2.0

## How fast the ear follows. Eased rather than snapped: the hand teleports
## across the map when the pointer crosses a hill, and an ear that went with it
## would swing the whole mix sideways in one frame.
const FOLLOW := 6.0

## Where the world should reckon "near the player" from. Static so that anything
## deciding whether a sound is worth making at all asks the same question the
## mixer will — see Agitation.cry, which used the camera's own point and so
## refused to make sounds that would have been perfectly audible.
static var _at := Vector3.ZERO

var camera_rig: CameraRig


func _ready() -> void:
	# THE LISTENER IS A THING YOU CLAIM. Without this the camera stays the ear
	# and every line above is a comment on a node nobody is listening through.
	make_current()


static func where() -> Vector3:
	return _at


func _process(delta: float) -> void:
	Ledger.open(&"Ear")
	var focus := GameState.camera_focus
	if not is_finite(focus.x):
		return
	var want := focus
	var hand := GameState.hand_at
	# The hand is Vector3.INF until the pointer has been over the world once,
	# and INF in a lerp poisons the whole transform.
	if is_finite(hand.x):
		want = focus.lerp(hand, TOWARD_HAND)
	want.y += EAR_HEIGHT
	global_position = global_position.lerp(want, minf(FOLLOW * delta, 1.0))
	_at = global_position
	if camera_rig != null and is_instance_valid(camera_rig) \
			and camera_rig.camera != null:
		# Which side of your head a thing is on has to agree with which side of
		# the screen it is on. Position is loudness; basis is direction.
		global_transform.basis = camera_rig.camera.global_transform.basis
