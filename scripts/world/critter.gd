class_name Critter
extends Node3D
## ONE SMALL LIFE. A bee over a flower, a squirrel on a limb, flies over meat.
##
## These are not animals in the game's sense: they have no needs, no health, no
## routing, and nothing in the simulation is allowed to depend on them. They eat
## nothing, they cannot be picked up, and killing every one of them would change
## no number anywhere. That is deliberate — it is what lets them be turned off
## entirely (see TreeFriends) without the world behaving differently.
##
## What they have instead is CONDUCT. A squirrel works an acorn on a limb and
## bolts for the trunk when a villager comes near. Flies lift off meat and
## settle back. Bees work a patch of flowers and drift between them. It is all
## motion and noise, and it is all local: a critter never leaves its host.
##
## A FLAT PLATE THAT FACES YOU. One billboarded quad, an unlit hand-drawn frame,
## alpha-scissored so it needs no sorting — the picture-book look, and about as
## cheap as a thing on screen can be.

## How the plate flips: seconds of world time, so the whole flipbook slows with
## everything else when the hand comes down to cast.
var kind := "fly"
var host: Node3D = null            # the tree, the meat, the flower patch
var anchor := Vector3.ZERO         # where it lives, in world space
var roam := 0.6                    # how far it strays from that

## STARTLE. The distance at which people and beasts scare it, and how long it
## stays hidden. Squirrels are the point of this; a fly does not care.
var shy := 0.0
var hide_seconds := 6.0

var _frames: Array[ImageTexture] = []
var _plate: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _voice: AudioStreamPlayer3D = null
var _frame := 0
var _flip := 0.0
var _fps := 6.0
var _size := 0.2
var _wander := 0.0
var _hidden := 0.0
var _gate := 0.0                   # the intermittent-chorus phase
var _gate_rate := 0.35
var _startle_check := 0.0


func _ready() -> void:
	add_to_group("critters")
	var spec: Dictionary = CritterArt.PLATES.get(kind, CritterArt.PLATES["fly"])
	_fps = float(spec["fps"])
	_size = float(spec["size"])
	_frames = CritterArt.frames_for(kind)
	_wander = randf() * TAU
	_gate = randf() * TAU
	_gate_rate = randf_range(0.22, 0.5)
	_build_plate()


## The plate. Unshaded because a hand-drawn animal carries its own light and
## shading it would only muddy the ink; alpha-scissor rather than blended alpha
## so it writes depth and never has to be sorted against the foliage.
func _build_plate() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(_size, _size)
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = _frames[0]
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_mat.alpha_scissor_threshold = 0.45
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.billboard_keep_scale = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.disable_receive_shadows = true
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = _mat
	_plate = MeshInstance3D.new()
	_plate.mesh = quad
	_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plate)


## GIVE IT A VOICE. Only a handful of critters get one at a time — see
## TreeFriends, which hands them out to the nearest few and takes them back.
## The player is always running; it is the VOLUME that opens and closes, which
## is what lets a chorus swell smoothly rather than clicking in and out.
func listen(on: bool, sound := "") -> void:
	if not on:
		if _voice != null and is_instance_valid(_voice):
			_voice.queue_free()
		_voice = null
		return
	if _voice != null and is_instance_valid(_voice):
		return
	var stream := SoundBank.voice(sound)
	if stream == null:
		return
	_voice = AudioStreamPlayer3D.new()
	_voice.stream = stream
	_voice.max_distance = 26.0
	_voice.unit_size = 3.0
	_voice.volume_db = -60.0
	_voice.pitch_scale = randf_range(0.92, 1.08)
	# Audio does NOT slow with the world. When the hand comes down and time
	# stretches, the crickets keep their pitch and simply come forward — which
	# is the whole effect: the world goes quiet and slow, and the small things
	# get louder.
	add_child(_voice)
	_voice.play()


## Is this one being heard right now? Only the nearest few are.
func has_voice() -> bool:
	return _voice != null and is_instance_valid(_voice)


func _process(delta: float) -> void:
	_flip += delta * _fps
	if _frames.size() > 1 and _flip >= 1.0:
		_flip = 0.0
		_frame = (_frame + 1) % _frames.size()
		_mat.albedo_texture = _frames[_frame]
	_move(delta)
	_tick_voice(delta)
	_tick_startle(delta)


## Everything a critter does with itself. Each kind moves in the one way that
## makes it recognisable from across a clearing, and no more than that.
func _move(delta: float) -> void:
	if _hidden > 0.0:
		_hidden -= delta
		if _hidden <= 0.0:
			_plate.visible = true
		return
	_wander += delta
	match kind:
		"bee", "fly", "moth":
			# In the air, never still: a fast tight orbit with a slow drift
			# under it, so it reads as flight rather than as a floating decal.
			var fast := _wander * (7.0 if kind == "fly" else 3.4)
			position = anchor + Vector3(
				cos(fast) * roam * 0.4 + sin(_wander * 0.7) * roam,
				0.18 + sin(fast * 1.7) * roam * 0.35 + sin(_wander * 0.9) * 0.1,
				sin(fast * 0.9) * roam * 0.4 + cos(_wander * 0.6) * roam)
		"squirrel", "possum":
			# Along a limb, in stops and starts. The pauses are the character:
			# a squirrel that moves smoothly reads as a toy on a wire.
			var step := sin(_wander * 0.8)
			var held := signf(step) * pow(absf(step), 0.35)
			position = anchor + Vector3(held * roam, 0.0, cos(_wander * 0.3) * roam * 0.3)
		"frog":
			# Mostly sitting. Every few seconds, one hop.
			var hop := pow(maxf(sin(_wander * 0.55), 0.0), 8.0)
			position = anchor + Vector3(
				sin(_wander * 0.55) * roam, hop * 0.28, cos(_wander * 0.41) * roam)
		_:
			# Crickets and anything else: they sit in the grass and sing.
			position = anchor + Vector3(0, 0.02 + sin(_wander * 2.0) * 0.01, 0)


## INTERMITTENT, UNTIL YOU START DRAWING.
##
## Left alone, a critter's voice comes and goes — a slow gate that is open maybe
## a third of the time, at its own rate, so a wood full of them is a scatter of
## sounds rather than a wall of one. As `GameState.focus` rises (the hand down,
## a rune being drawn) the gate opens all the way and stays open, and the whole
## chorus goes continuous. That transition IS the feature.
func _tick_voice(delta: float) -> void:
	if _voice == null or not is_instance_valid(_voice):
		return
	_gate += delta * _gate_rate * TAU
	var focus := GameState.focus
	# The natural gate: mostly shut, and shaped so it swells rather than switches.
	var intermittent := pow(maxf(sin(_gate), 0.0), 2.2)
	var open := lerpf(intermittent, 1.0, focus)
	# Hidden things go quiet; a squirrel that has bolted is not scolding.
	if _hidden > 0.0:
		open *= 0.15
	# -34 dB is barely there at a few paces, which is the point of the quiet
	# end; the loud end is still under the game's ordinary sounds.
	var want := lerpf(-34.0, -8.0, open)
	_voice.volume_db = lerpf(_voice.volume_db, want, clampf(delta * 6.0, 0.0, 1.0))


## SCURRYING FOR COVER. Squirrels and possums only, and only against the things
## that would actually alarm them — people, beasts, the creature, the hand.
## Checked four times a second rather than every frame, because there is no
## version of this that has to be exact.
func _tick_startle(delta: float) -> void:
	if shy <= 0.0 or _hidden > 0.0:
		return
	_startle_check -= delta
	if _startle_check > 0.0:
		return
	_startle_check = 0.25
	var here := global_position
	for group in ["villagers", "animals", "creature"]:
		for n in get_tree().get_nodes_in_group(group):
			var body := n as Node3D
			if is_instance_valid(body) and body.global_position.distance_to(here) < shy:
				bolt()
				return


## Gone — behind the trunk, into the leaves, under the log. It simply stops
## being drawn, which at this size reads exactly as "it went round the back".
func bolt() -> void:
	if _hidden > 0.0:
		return
	_hidden = hide_seconds * randf_range(0.7, 1.4)
	_plate.visible = false
	if kind == "squirrel":
		SoundBank.play_at("chatter", global_position, -16.0, 0.25)
