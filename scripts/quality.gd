extends Node
## Autoload `Quality`: a per-device graphics tier, the way every shipping
## mobile title scales — a flagship gets shadows, glow, and reflective
## water; a budget Adreno gets a plain-but-solid look that actually runs.
## Auto-detected from the GPU at boot, with a persisted manual override
## (cycle with F2) so it can be forced for testing or preference.
##
## Every renderer consumer (main's environment, the camera, the chunk
## water) reads its knobs from here — one place to tune the whole ladder.

signal quality_changed
## The device has started struggling, or stopped. Everything that wants to do
## less work listens for this.
signal heat_changed(level: int)

enum Tier { LOW, MEDIUM, HIGH }
## HOW HARD THE DEVICE IS BREATHING.
##
## Godot exposes no thermal sensor on any platform, so this is NOT a temperature
## reading and is not dressed up as one. It is sustained FRAME TIME, which is
## the thing that actually matters and the thing a throttling chip actually does
## to you: when the SoC pulls its clocks back, frames get longer, and they stay
## longer. A phone that has been in a warm hand for twenty minutes and one that
## simply has too much on screen both arrive here, and both want the same
## answer — do less — so the distinction costs the player nothing.
enum Heat { EASY, WARM, HOT }

const SAVE_PATH := "user://quality.cfg"

## Sustained frame times, in seconds. WARM is about 45fps, HOT about 30, and it
## must fall back well under WARM before easing off again so the game does not
## oscillate between two looks every few seconds.
const FRAME_WARM := 0.022
const FRAME_HOT := 0.033
const FRAME_COOL := 0.019
## How long a condition must hold before anything changes. A chunk streaming in,
## a scene reload or a tornado is a HITCH, not a hot phone, and must never be
## mistaken for one.
const HEAT_HOLD := 4.0
## And nothing is judged at all for the first few seconds after a load, when the
## world is being built and slow frames are expected.
const SETTLE := 8.0
## How heavily the frame-time average leans on the frame just past. Slow on
## purpose — this is a trend, not a measurement.
const FRAME_BLEND := 0.02

var tier := Tier.MEDIUM
## Plain int rather than the enum's own type, so every comparison, subtraction
## and array index below is unambiguously legal.
var heat: int = Heat.EASY

var _frame := 0.016
var _pressure := 0.0     # seconds the current condition has held
var _grace := SETTLE


func _ready() -> void:
	var saved := _load_override()
	if saved >= 0:
		tier = saved as Tier
	else:
		tier = _detect_tier()
	print("Quality: %s (GPU: %s)" % [Tier.keys()[tier], _adapter_name()])


## Watch the frames go by. Three floats a frame; nothing here is measured with
## anything more expensive than the delta the engine already handed us.
func _process(delta: float) -> void:
	if _grace > 0.0:
		_grace -= delta
		return
	_frame = lerpf(_frame, delta, FRAME_BLEND)
	# Climbing is immediate to the band the frames deserve; EASING OFF is one
	# band at a time, so a device that recovers does not have shadows, glow,
	# MSAA and every draw distance all snap back in the same frame.
	var want := heat
	if _frame > FRAME_HOT:
		want = Heat.HOT
	elif _frame > FRAME_WARM:
		want = maxi(heat, Heat.WARM)
	elif _frame < FRAME_COOL:
		want = maxi(heat - 1, Heat.EASY)
	if want == heat:
		_pressure = 0.0
		return
	_pressure += delta
	if _pressure < HEAT_HOLD:
		return
	_pressure = 0.0
	heat = want
	heat_changed.emit(heat)
	# Everything that reads a knob reads it through `effective_tier`, so the
	# existing re-apply path does the whole job.
	quality_changed.emit()
	if heat == Heat.HOT:
		GameState.announce("The world eases off — your device is working hard.")
	elif heat == Heat.EASY:
		GameState.announce("The world breathes out again.")


## Start the grace period again — called after a scene reload, when slow frames
## mean the world is being built rather than that anything is wrong.
func settle() -> void:
	_grace = SETTLE
	_frame = 0.016
	_pressure = 0.0


## THE TIER EVERY KNOB ACTUALLY READS. A struggling device is treated as a
## lesser one for as long as it struggles, which means one line here quietly
## turns off shadows, glow and MSAA, pulls in the draw distances and thickens
## the fog — through exactly the paths that already existed for a budget phone.
func effective_tier() -> int:
	return maxi(tier - heat, Tier.LOW)


func hot() -> bool:
	return heat == Heat.HOT


func struggling() -> bool:
	return heat != Heat.EASY


## How much less often the far half of the world should be simulated. Distant
## villagers and beasts are the cheapest thing to slow down and the least
## noticeable, so they take the first cut.
func sim_relief() -> int:
	return [1, 2, 3][heat]


func frame_ms() -> float:
	return _frame * 1000.0


func heat_word() -> String:
	return ["easy", "working hard", "struggling"][heat]


func _adapter_name() -> String:
	return RenderingServer.get_video_adapter_name()


## A rough capability guess from the GPU name. Not exact — no API gives a
## real perf score — but enough to seat a device in the right tier, and
## the manual override is the safety valve.
func _detect_tier() -> Tier:
	if not OS.has_feature("mobile"):
		return Tier.HIGH   # desktop/laptop GPUs: full quality
	var gpu := _adapter_name().to_lower()
	var num := _first_number(gpu)
	if "adreno" in gpu:
		if num >= 700:
			return Tier.HIGH        # 7xx flagships
		if num >= 640:
			return Tier.MEDIUM      # upper 6xx
		return Tier.LOW             # 610/619/6xx budget
	if "immortalis" in gpu:
		return Tier.HIGH
	if "mali" in gpu:
		if num >= 710:
			return Tier.HIGH
		if num >= 610:
			return Tier.MEDIUM
		return Tier.LOW
	if "apple" in gpu or "powervr" in gpu:
		return Tier.HIGH            # iOS GPUs punch above their weight
	return Tier.LOW                 # unknown mobile part: play it safe


func _first_number(s: String) -> int:
	var digits := ""
	for c: String in s:
		if c >= "0" and c <= "9":
			digits += c
		elif digits != "":
			break
	return int(digits) if digits != "" else 0


## Feature knobs by tier -------------------------------------------------------

func glow() -> bool:
	return effective_tier() >= Tier.MEDIUM


func shadows() -> bool:
	return effective_tier() >= Tier.MEDIUM


func shadow_distance() -> float:
	return 120.0 if effective_tier() == Tier.HIGH else 70.0


func water_alpha() -> bool:
	return effective_tier() >= Tier.MEDIUM


## MSAA multiplies the per-pixel cost of the opaque pass. Budget GPUs that
## already flirt with a frame timeout get none; capable devices get a cheap
## 2x to smooth our hard primitive edges.
func msaa_3d() -> Viewport.MSAA:
	return Viewport.MSAA_2X if effective_tier() >= Tier.MEDIUM else Viewport.MSAA_DISABLED


func load_radius() -> int:
	return [2, 3, 3][effective_tier()]


func unload_radius() -> int:
	return [3, 4, 4][effective_tier()]


func camera_far() -> float:
	return [220.0, 300.0, 380.0][effective_tier()]


## How far out the scattered wilderness clutter (trees, bushes, rocks,
## flowers) keeps drawing. Budget devices cull it tight — under the fog
## line — so the far ring of the world is terrain and silhouette only;
## capable devices render clutter most of the way to the horizon.
func clutter_distance() -> float:
	return [70.0, 120.0, 180.0][effective_tier()]


## How far out villagers, animals, and the creature keep drawing. Generous
## (they are what you watch), but past it a distant crowd is a speck in the
## fog not worth the draw calls — and a big village stops rendering dozens of
## bodies at once on a budget device.
func actor_distance() -> float:
	return [95.0, 150.0, 220.0][effective_tier()]


## HOW MANY PARTICLES a burst is allowed. Reads the effective tier, so a
## struggling device thins the rain along with everything else — and because
## particles are the one thing here that can run to hundreds at once, this is
## the knob with the most give in it.
func particle_scale() -> float:
	return [0.4, 0.7, 1.0][effective_tier()]


## How many of a burst to actually spawn, never fewer than a handful — a
## four-droplet shower is worse than none.
func particles(most: int) -> int:
	return maxi(int(most * particle_scale()), 6)


func fog_density() -> float:
	# A leaner world (LOW) needs thicker fog to hide the near horizon.
	return [0.008, 0.006, 0.004][effective_tier()]


## Manual override -------------------------------------------------------------

## Cycle LOW -> MEDIUM -> HIGH, persist it, and re-apply what can change
## live. Radius and water rebuild on the next world reload.
func cycle() -> void:
	tier = ((tier + 1) % 3) as Tier
	_save_override(tier)
	GameState.announce("Graphics quality: %s (some parts apply on restart)"
		% Tier.keys()[tier].capitalize())
	quality_changed.emit()


func _save_override(t: Tier) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_32(t)
		f.close()


func _load_override() -> int:
	if not FileAccess.file_exists(SAVE_PATH):
		return -1
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return -1
	var t := f.get_32()
	f.close()
	return t if t >= 0 and t <= 2 else -1
