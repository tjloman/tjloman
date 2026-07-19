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

enum Tier { LOW, MEDIUM, HIGH }

const SAVE_PATH := "user://quality.cfg"

var tier := Tier.MEDIUM


func _ready() -> void:
	var saved := _load_override()
	if saved >= 0:
		tier = saved as Tier
	else:
		tier = _detect_tier()
	print("Quality: %s (GPU: %s)" % [Tier.keys()[tier], _adapter_name()])


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
	return tier >= Tier.MEDIUM


func shadows() -> bool:
	return tier >= Tier.MEDIUM


func shadow_distance() -> float:
	return 120.0 if tier == Tier.HIGH else 70.0


func water_alpha() -> bool:
	return tier >= Tier.MEDIUM


## MSAA multiplies the per-pixel cost of the opaque pass. Budget GPUs that
## already flirt with a frame timeout get none; capable devices get a cheap
## 2x to smooth our hard primitive edges.
func msaa_3d() -> Viewport.MSAA:
	return Viewport.MSAA_2X if tier >= Tier.MEDIUM else Viewport.MSAA_DISABLED


func load_radius() -> int:
	return [2, 3, 3][tier]


func unload_radius() -> int:
	return [3, 4, 4][tier]


func camera_far() -> float:
	return [220.0, 300.0, 380.0][tier]


## How far out the scattered wilderness clutter (trees, bushes, rocks,
## flowers) keeps drawing. Budget devices cull it tight — under the fog
## line — so the far ring of the world is terrain and silhouette only;
## capable devices render clutter most of the way to the horizon.
func clutter_distance() -> float:
	return [70.0, 120.0, 180.0][tier]


func fog_density() -> float:
	# A leaner world (LOW) needs thicker fog to hide the near horizon.
	return [0.008, 0.006, 0.004][tier]


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
