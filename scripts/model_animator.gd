class_name ModelAnimator
extends RefCounted
## Drives a rigged model's AnimationPlayer from the game's semantic states.
##
## It stays a complete no-op until art actually ships clips: `create()` returns
## null when the instanced model has no AnimationPlayer, and `play()` ignores
## any state whose clip is missing (leaving whatever is playing). So the game
## runs identically with a primitive body, a static model, or a rigged one.
##
## Semantic states an entity may ask for (map your Blender clip names to these,
## or use a listed alias): idle · walk · run · work · eat · sleep · carry ·
## fall · attack · play · pray · swim · graze · guard · drink. Mark locomotion
## clips as looping in Blender, or rely on the loop defaults below.

const BLEND := 0.15

## States treated as looping; anything else plays once and holds its last pose.
const LOOPING := {
	"idle": true, "walk": true, "run": true, "sleep": true, "swim": true,
	"graze": true, "carry": true, "fly": true, "pray": true, "guard": true,
	"work": true, "fall": true,
}

## Clip-name aliases per semantic state, tried in order. The last entries give
## graceful fallbacks (e.g. run -> walk) when a specific clip is absent.
const ALIASES := {
	"idle": ["idle", "rest", "stand"],
	"walk": ["walk", "walking", "move"],
	"run": ["run", "sprint", "gallop", "flee", "walk"],
	"work": ["work", "chop", "farm", "build", "dig", "hammer", "labor"],
	"eat": ["eat", "eating", "feed", "graze"],
	"sleep": ["sleep", "rest"],
	"carry": ["carry", "hold", "haul"],
	"fall": ["fall", "tumble", "thrown", "flail"],
	"attack": ["attack", "kick", "hit", "strike", "smash"],
	"play": ["play", "cheer", "dance", "jump"],
	"pray": ["pray", "worship", "kneel"],
	"swim": ["swim", "wade"],
	"graze": ["graze", "eat", "feed"],
	"guard": ["guard", "alert", "watch"],
	"drink": ["drink", "graze", "eat"],
}

var _player: AnimationPlayer
var _resolved := {}   # semantic state -> actual clip name ("" when none exists)
var _current := ""


## Build an animator for a freshly instanced model, or null if it has no
## AnimationPlayer (the caller then leaves procedural/static behaviour alone).
static func create(root: Node) -> ModelAnimator:
	var player := _find_player(root)
	if player == null:
		return null
	var anim := ModelAnimator.new()
	anim._player = player
	# When a one-shot (non-looping) clip ends, settle back so the entity's
	# next play() re-decides — returning to idle/walk if the action is over,
	# or repeating it if the entity is still in that state.
	player.animation_finished.connect(anim._on_finished)
	return anim


static func _find_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for c in root.find_children("*", "AnimationPlayer", true, false):
		return c as AnimationPlayer
	return null


## Ask for a semantic state. Switches clips only when the state changes, sets
## the loop mode, and cross-fades; silently does nothing for a missing clip.
func play(state: String) -> void:
	if state == _current or not is_instance_valid(_player):
		return
	var clip := _resolve(state)
	if clip == "":
		return   # this model has no such clip — keep the current one playing
	_current = state
	var anim := _player.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if LOOPING.get(state, false) else Animation.LOOP_NONE
	_player.play(clip, BLEND)


## Root motion for one-shot actions (a lunge, kick, pounce). Returns the
## model-local position delta the current clip moved its root THIS frame, or
## zero unless the model's AnimationPlayer has a `root_motion_track` set (the
## modeller opts in). The caller rotates it into world space and applies it
## only during the discrete action — ordinary walking stays game-driven.
func root_motion() -> Vector3:
	if not is_instance_valid(_player) or _player.root_motion_track == NodePath(""):
		return Vector3.ZERO
	return _player.get_root_motion_position()


## A one-shot finished (looping clips never emit this — we force their loop
## mode). Clear the tracked state so the entity's per-frame play() drives the
## next clip: idle when the deed is done, or the same action again if it's a
## sustained one (a creature still mid-rampage keeps swinging).
func _on_finished(_anim_name: StringName) -> void:
	_current = ""


## Resolve (and cache) a semantic state to an actual clip name on this model.
func _resolve(state: String) -> String:
	if _resolved.has(state):
		return _resolved[state]
	var candidates: Array = ALIASES.get(state, [state])
	var list := _player.get_animation_list()
	var found := ""
	for cand: String in candidates:
		if _player.has_animation(cand):
			found = cand
			break
		var lc := cand.to_lower()
		for actual: String in list:
			var la := actual.to_lower()
			# Exact, or a library/rig-qualified match like "Armature|Walk".
			if la == lc or la.ends_with("/" + lc) or la.ends_with("|" + lc) \
					or la.ends_with("-" + lc) or la.ends_with("_" + lc):
				found = actual
				break
		if found != "":
			break
	_resolved[state] = found
	return found
