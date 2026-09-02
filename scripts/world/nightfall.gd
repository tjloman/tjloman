class_name Nightfall
extends Node3D
## NIGHT YOU CAN ACTUALLY SEE.
##
## Night used to be a black screen with a few emissive window panes in it. On a
## phone in daylight it was unreadable — you could not find your own creature.
## The fix is not "turn the brightness up": it is to give the dark some real
## sources of light, and let the eye read shape by them.
##
## There are four, and this file owns the one that costs anything:
##
##   THE MOON AND STARS  — a directional fill and an ambient floor, set in
##     main.gd where the sky already lives. Free.
##   WINDOWS AND TORCHES — emissive panes on houses (House) and a MultiMesh of
##     flames over the villagers who are out after dark (Village). One draw
##     call a town, no lights at all.
##   THE CREATURE'S RADIANCE — one omni light on the beast itself, coloured by
##     what it has become (Creature). Always worth its cost: it is the thing
##     you are looking at.
##   HEARTHS — THIS FILE. Real omni lights, which are the only thing here that
##     actually pools light onto the ground.
##
## THE PROBLEM WITH HEARTHS is that there may be hundreds of villages, and a
## tiled mobile GPU wants very few lights per tile. So the count is FIXED. A
## small pool of omni lights is kept, and every second or so they are handed to
## the nearest warm places to the camera — a village totem, a bonfire. Walk
## across the map and the same four lights follow you from town to town,
## easing up as they are claimed and down as they are let go, so nothing ever
## snaps on. Add a thousand villages and the light budget does not move.
##
## The pool size runs through the graphics tier, and so through the thermal
## band: a device that is getting hot lets its hearths go out one by one and
## keeps only the creature's own glow.

## How far a hearth still counts as worth lighting.
const REACH := 130.0
## How often the pool is re-dealt. Lights ease between assignments, so this can
## be slow and lazy — it is a scan over every village.
const REDEAL := 1.4

## A hearth's light: warm, wide, and soft enough to read as firelight pooling
## rather than a spotlight.
const HEARTH_COLOR := Color(1.0, 0.66, 0.32)
const HEARTH_RANGE := 26.0
const HEARTH_ENERGY := 2.2
## How fast a light comes up when claimed and goes down when released. Slow
## enough that a hearth changing hands looks like a fire dying down.
const EASE := 1.6

## How much of the fire's flicker shows in the light. Small — a pool of light
## that pulses hard looks like a bug, not a bonfire.
const FLICKER := 0.12

var camera_rig: CameraRig

var _lights: Array[OmniLight3D] = []
var _claims: Array[Vector3] = []      # where each light is trying to be
var _held: Array[bool] = []           # is this light claimed right now
var _energy: Array[float] = []        # the steady value, before flicker
var _flicker_phase: Array[float] = []
var _redeal := 0.0


func _ready() -> void:
	_resize_pool(Quality.night_lights())
	Quality.quality_changed.connect(_on_quality_changed)
	Quality.heat_changed.connect(_on_heat_changed)


func _on_quality_changed() -> void:
	_resize_pool(Quality.night_lights())


func _on_heat_changed(_level: int) -> void:
	# A hot phone gives its hearths up before it gives up anything you are
	# looking at. The creature's own radiance is not in this pool.
	_resize_pool(Quality.night_lights())


## Grow or shrink the pool. Lights are made dark and unclaimed; the next deal
## puts them to work.
func _resize_pool(want: int) -> void:
	want = maxi(want, 0)
	while _lights.size() > want:
		var gone := _lights.pop_back()
		_claims.pop_back()
		_held.pop_back()
		_energy.pop_back()
		_flicker_phase.pop_back()
		if is_instance_valid(gone):
			gone.queue_free()
	while _lights.size() < want:
		var light := OmniLight3D.new()
		light.light_color = HEARTH_COLOR
		light.omni_range = HEARTH_RANGE
		light.light_energy = 0.0
		light.shadow_enabled = false   # a shadowed point light is a phone-killer
		light.light_specular = 0.15
		light.visible = false
		add_child(light)
		_lights.append(light)
		_claims.append(Vector3.ZERO)
		_held.append(false)
		_energy.append(0.0)
		_flicker_phase.append(randf() * TAU)


func _process(delta: float) -> void:
	if _lights.is_empty():
		return
	_redeal -= delta
	if _redeal <= 0.0:
		_redeal = REDEAL
		_deal()
	_ease(delta)


## Hand the pool out to the nearest hearths. Off during the day, so the whole
## thing costs nothing at all while the sun is up.
func _deal() -> void:
	if not GameState.is_night():
		for i in _held.size():
			_held[i] = false
		return
	var eye := _eye()
	var near := _hearths_near(eye)
	for i in _lights.size():
		if i < near.size():
			_claims[i] = near[i]
			_held[i] = true
		else:
			_held[i] = false


## Every warm place worth lighting, nearest first, capped at the pool size.
## A village's totem is its hearth: it is the middle of town and the thing
## everybody gathers around.
func _hearths_near(eye: Vector3) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var ranked: Array[Array] = []
	for n in get_tree().get_nodes_in_group("village"):
		var vil := n as Village
		if not is_instance_valid(vil) or vil.population() <= 0:
			continue
		var where := vil.global_position
		var d := where.distance_to(eye)
		if d > REACH:
			continue
		ranked.append([d, where])
	# Untyped lambda parameters on purpose: a typed one against a typed Array
	# fails to bind at call time (the same trap that broke _hold_cloud).
	ranked.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in mini(ranked.size(), _lights.size()):
		found.append(ranked[i][1] as Vector3)
	return found


## Bring claimed lights up and let released ones down, and move a light to its
## claim only while it is dark — so a hearth changing hands fades out here and
## fades in there, never slides across the field.
func _ease(delta: float) -> void:
	for i in _lights.size():
		var light := _lights[i]
		if not is_instance_valid(light):
			continue
		var want := HEARTH_ENERGY if _held[i] else 0.0
		_energy[i] = move_toward(_energy[i], want, EASE * delta)
		if _energy[i] <= 0.02:
			_energy[i] = 0.0
			light.light_energy = 0.0
			light.visible = false
			if _held[i]:
				# Dark and wanted somewhere: this is the moment to move it.
				light.global_position = _claims[i] + Vector3(0, 2.6, 0)
				light.visible = true
			continue
		# Two waves out of step: one flame's worth of unsteadiness, without the
		# regular pulse a single sine would give.
		_flicker_phase[i] += delta * 5.3
		var flicker := 1.0 + sin(_flicker_phase[i]) * FLICKER \
			+ sin(_flicker_phase[i] * 2.7) * FLICKER * 0.5
		light.light_energy = _energy[i] * flicker
		light.visible = true


## How many hearths are actually burning right now. For the readouts and the
## smoke test: the point of the pool is that this can never exceed the budget,
## however many towns the world grows.
func lights_lit() -> int:
	var lit := 0
	for light in _lights:
		if is_instance_valid(light) and light.visible and light.light_energy > 0.01:
			lit += 1
	return lit


func _eye() -> Vector3:
	if is_instance_valid(camera_rig) and camera_rig.camera != null:
		return camera_rig.camera.global_position
	return global_position
