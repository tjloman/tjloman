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
## AND IT MUST BE GENUINELY FINE BEFORE IT EASES OFF AGAIN.
##
## This was 0.019 — three milliseconds under the WARM line. That is not
## hysteresis, it is a hair, and any machine sitting anywhere near 45fps drifts
## straight through it: four seconds over, announce; four seconds under,
## announce; forever. On a desktop that was perfectly healthy the world spent
## the whole session breathing out and working hard by turns.
##
## Sixteen and a half milliseconds is sixty frames a second. If it is easing
## off, it is because the device is actually keeping up.
const FRAME_COOL := 0.0165
## How long a condition must hold before anything changes. A chunk streaming in,
## a scene reload or a tornado is a HITCH, not a hot phone, and must never be
## mistaken for one.
const HEAT_HOLD := 4.0
## AND EASING OFF IS SLOWER THAN CLAMPING DOWN, on purpose. Protecting the frame
## should be quick; believing the trouble has passed should take real evidence.
const COOL_HOLD := 14.0
## And nothing is judged at all for the first few seconds after a load, when the
## world is being built and slow frames are expected.
const SETTLE := 8.0
## How heavily the frame-time average leans on the frame just past. Slow on
## purpose — this is a trend, not a measurement.
const FRAME_BLEND := 0.02
## What a full hand costs the far half of the world, in simulation strides.
const HANDS_RELIEF := 1

## RESISTANCE TO EASING OFF, because most slow frames are not the device.
##
## A thermostat that believes every slow patch has spent this game's whole
## development being wrong in the same direction: something happens OUTSIDE the
## game — the editor spewing four thousand errors into its own log, a compile,
## the OS deciding to index something, a window losing focus — the frames go to
## pieces for a few seconds, and the world dims. Turning the graphics down would
## not have bought a single millisecond of that back, and the player is left
## with a worse-looking game and no idea why.
##
##     "Sometimes something happens in the background, and changing quality
##      wouldn't have fixed it one bit."
##
## Three things have to be true before anything is turned down now, and each
## rules out a different way of being fooled.
##
## A STALL IS NOT A SLOW DEVICE. A frame far out of line with the ones around it
## is something blocking, not something rendering, and it does not belong in an
## average that is supposed to describe a machine. Measured against the running
## average rather than against a fixed ceiling, so a genuinely slow device —
## where every frame is slow and none is out of line — is not protected by this
## at all.
const SPIKE := 4.0
const STALL_OVER := 0.1

## IT HAS TO BE MOST OF THE FRAMES, not an average a burst dragged up. Twenty
## dreadful frames in a quiet minute will lift a mean over the line while
## fifty-nine frames in sixty were fine. A share is not fooled by that: it asks
## how many of them were bad, not how bad the bad ones were.
const MOSTLY := 0.6
const SHARE_BLEND := 0.02

## AND THE LAST ONE HAD TO HAVE HELPED. If the world was turned down and the
## frame did not improve, the trouble is not in anything the tier controls —
## and the next step down is even less likely to be. It is not refused, because
## a device really can be sinking; it is made to wait far longer for it.
const HELPED_BY := 0.05
const STUBBORN_HOLD := 4.0

## THE FIXED CLOCK, AND THE HOLE A SLOW DEVICE FALLS DOWN IT -----------------
##
## Godot runs physics on a clock of its own. Every drawn frame it works out how
## many ticks it owes since the last one and runs them all, up to
## `max_physics_steps_per_frame`. At the engine defaults — sixty ticks a second
## and a ceiling of eight — a phone drawing at 133ms owes eight ticks by the
## time the frame ends and runs every one of them: every villager, every
## animal, every rigid body, simulated EIGHT TIMES for one picture.
##
## Which makes the frame longer. Which owes more ticks. A device that falls
## behind this clock does not degrade gently, it falls down a hole, and from
## inside the hole it looks like the whole game is slow rather than like one
## number being pinned at its ceiling. See FrameMeter, which prints the steps a
## frame and says PINNED when they are.
##
## THIRTY TICKS, AND A CEILING OF TWO, ON EVERY MACHINE THERE IS.
##
## This was a handheld rule first, on the argument that "a desk machine never
## falls behind either number". That argument was wrong, and a screenshot
## settled it: a desktop far beefier than any phone, sitting at 151ms a frame
## with `x8.0 steps/frame PINNED` — the engine ceiling, met exactly, on the
## machine that was supposed to be immune. The hole is not a property of slow
## hardware. It is a property of a fixed clock with a high ceiling meeting a
## world with four hundred bodies in it, and a fast machine reaches it with a
## bigger world rather than not reaching it.
##
## Nothing in this game needs sixty ticks: villagers walk, beasts graze, and the
## one thing that genuinely wants to feel instant — the hand — was taken off the
## physics tick long ago precisely so it would not wait for one. Half the ticks
## is half of every `_physics_process` in the world AND half of the engine's own
## solver, which is the larger half and does not show up in any script timing.
##
## AND A CEILING OF TWO. Past two the machine stops trying to keep up with real
## time and the world runs a little slow instead, which is the right way round:
## a smooth twenty frames of slightly slow time beats six and a half frames of
## the correct time. Two ticks at thirty a second covers sixty-six milliseconds,
## so nothing above about fifteen frames a second ever meets it.
const PHYSICS_HZ := 30
const STEPS_MOST := 2

var tier := Tier.MEDIUM
## Plain int rather than the enum's own type, so every comparison, subtraction
## and array index below is unambiguously legal.
var heat: int = Heat.EASY

## TRUE WHILE THE PLAYER HAS SOMETHING IN THEIR HAND. Set by DivineHand; read
## only by `sim_relief`. Nothing else in the game is allowed to care.
var hands_busy := false

var _frame := 0.016
var _pressure := 0.0     # seconds the current condition has held
var _grace := SETTLE
## The share of recent frames over the line, 0..1, and what the average was when
## the world was last turned down — see the note by SPIKE.
var _over := 0.0
var _dropped_at := 0.0
var _stalls := 0
## Which heat levels have already explained themselves this session.
var _announced := {}


func _ready() -> void:
	_set_the_clock()
	var saved := _load_override()
	if saved >= 0:
		tier = saved as Tier
	else:
		tier = _detect_tier()
	print("Quality: %s (GPU: %s)" % [Tier.keys()[tier], _adapter_name()])


## SET THE FIXED CLOCK. See the note by PHYSICS_HZ: this is the difference
## between a slow frame and a frame that makes itself slower, and it is asked of
## NEITHER the machine nor the graphics tier, because it turned out to be a
## question about neither.
func _set_the_clock() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.max_physics_steps_per_frame = STEPS_MOST


## Watch the frames go by. Three floats a frame; nothing here is measured with
## anything more expensive than the delta the engine already handed us.
func _process(delta: float) -> void:
	Ledger.open(&"Quality")
	# IN REAL SECONDS, NOT THE WORLD'S. `delta` here has already been through
	# Engine.time_scale, and the casting session runs the world at 0.75 (see
	# DivineHand._tick_focus). So the instant a rune is drawn, a perfectly
	# healthy 16.6ms frame is handed to this function as 12.5ms — under
	# FRAME_COOL — and the thermostat concludes the device just got faster.
	# It eases a band, every stride in Util.sim_stride changes underneath
	# everything that walks, and the whole thing happens again in reverse when
	# the session closes. The frame time is a measurement of the DEVICE and
	# must not be measured in a clock the game itself is bending.
	var real := delta / maxf(Engine.time_scale, 0.01)
	if _grace > 0.0:
		_grace -= real
		return
	# A STALL IS NOT A SLOW DEVICE, and does not get a vote. Out of line with
	# the frames around it AND long in absolute terms, which together mean
	# something blocked rather than something took a while to draw.
	if real > STALL_OVER and real > _frame * SPIKE:
		_stalls += 1
		return
	_frame = lerpf(_frame, real, FRAME_BLEND)
	# How MANY of them are bad, as against how bad the average is. See MOSTLY.
	_over = lerpf(_over, 1.0 if real > FRAME_WARM else 0.0, SHARE_BLEND)
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
	# TURNING DOWN NEEDS MOST OF THE FRAMES, not a mean a burst lifted.
	if want > heat and _over < MOSTLY:
		_pressure = 0.0
		return
	_pressure += real
	var hold := COOL_HOLD
	if want > heat:
		# AND IF THE LAST ONE BOUGHT NOTHING, this one waits. `_dropped_at` is
		# what the average was when the world was last turned down; if it has
		# not come down since, the trouble is not in anything the tier holds.
		var helped := _dropped_at <= 0.0 or _frame < _dropped_at * (1.0 - HELPED_BY)
		hold = HEAT_HOLD if helped else HEAT_HOLD * STUBBORN_HOLD
	if _pressure < hold:
		return
	_pressure = 0.0
	if want > heat:
		_dropped_at = _frame
	else:
		_dropped_at = 0.0
	heat = want
	heat_changed.emit(heat)
	# Everything that reads a knob reads it through `effective_tier`, so the
	# existing re-apply path does the whole job.
	quality_changed.emit()
	# SAID ONCE, NOT EVERY TIME. A player is owed an explanation the first time
	# the game visibly changes under them; after that it is a machine narrating
	# its own thermostat, and it was doing it every few seconds.
	if _announced.has(heat):
		return
	_announced[heat] = true
	if heat == Heat.HOT:
		GameState.announce("The world eases off — your device is working hard.")
	elif heat == Heat.EASY:
		GameState.announce("The world breathes out again.")


## HOW MANY FRAMES WERE THROWN OUT as stalls rather than counted as slowness,
## and the share of recent frames that were genuinely over the line. The meter
## prints both: a thermostat that quietly ignores things has to say how often,
## or the next person to wonder why the world did not ease off has nothing to
## read.
func stalls_ignored() -> int:
	return _stalls


func share_over() -> float:
	return _over


## Start the grace period again — called after a scene reload, when slow frames
## mean the world is being built rather than that anything is wrong.
func settle() -> void:
	_grace = SETTLE
	_frame = 0.016
	_pressure = 0.0
	_over = 0.0
	_dropped_at = 0.0
	# Nobody is holding anything in a world that has just been rebuilt, and a
	# flag left set here would cost the far world a stride for good.
	hands_busy = false


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
##
## AND THEY TAKE ANOTHER ONE WHILE THE HAND IS FULL. Input delay is never the
## answer to a struggling device: if a hot phone cannot do everything, the
## thing it stops doing is simulating a village over the hill, not answering
## the finger. So a wind-up costs the far world a stride and buys the hand the
## frames — see `hands_busy` and DivineHand._on_pointer_motion, which no longer
## waits for a physics tick to move what you are holding.
func sim_relief() -> int:
	return [1, 2, 3][heat] + (HANDS_RELIEF if hands_busy else 0)


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
	return tier_for(_adapter_name())


## THE TIER A GPU NAME DESERVES. It takes the name as an ARGUMENT rather than
## reading the live adapter, which is the whole point: it can be TESTED against
## a table of real parts instead of against one developer's own phone, and that
## table is where this was found to be wrong. (Not `static` — Quality is an
## autoload, and Godot warns about reaching a static through an instance.)
##
## IT WAS WRONG TWICE, AND BOTH TIMES FOR THE MID-RANGE ANDROID MARKET this game
## is actually aimed at, because both families number their parts in ways a
## plain numeric comparison reads backwards.
##
## ADRENO 7xx IS NOT ONE THING. The old rule said 700-and-up meant a flagship,
## so the Adreno 710 in a Snapdragon 6 Gen 1 or 7s Gen 2 — a squarely mid-range
## phone, and one of the commonest classes of device this game will ever run on
## — was seated on HIGH and asked for shadows, glow and 4x MSAA. The split is at
## 730: 710/720/725 are the mid parts, 730 and up are the flagships.
##
## AND MALI NUMBERS ITS PARTS IN TWO INCOMPATIBLE GENERATIONS. The older Valhall
## names are two digits (G57, G68, G76, G78) and the newer ones are three (G310,
## G510, G610, G715). A plain `>= 610` therefore rated a Mali-G68 — the Exynos
## 1280/1380, a perfectly capable mid part — BELOW a Mali-G310, which is an
## entry-level chip, and dropped it to LOW. Two digits and three are read on
## their own scales now.
func tier_for(adapter: String) -> Tier:
	var gpu := adapter.to_lower()
	var num := _first_number(gpu)
	if "immortalis" in gpu:
		return Tier.HIGH            # Arm's flagship line, whatever the number
	if "adreno" in gpu:
		if num >= 800:
			return Tier.HIGH        # 8xx: the current flagships
		if num >= 730:
			return Tier.HIGH        # 730-750: flagship 7xx
		if num >= 700:
			return Tier.MEDIUM      # 710/720/725: the mid-range 7xx
		if num >= 640:
			return Tier.MEDIUM      # 640/650: yesterday's flagships
		return Tier.LOW             # 610/612/613/619 and below: budget
	if "mali" in gpu:
		if num >= 100:
			# Three-digit Valhall: G310 entry, G510 low-mid, G6xx mid, G7xx high.
			if num >= 700:
				return Tier.HIGH
			if num >= 600:
				return Tier.MEDIUM
			return Tier.LOW
		# Two-digit Valhall and older: G76/G77/G78 were flagships, G68 is a fair
		# mid part, G57 and below are entry.
		if num >= 76:
			return Tier.HIGH
		if num >= 68:
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


## HOW MANY PIXELS THE 3D PASS ACTUALLY DRAWS, as a share of the panel's.
##
## The one knob nobody had touched, and by a distance the biggest. The window
## stretch mode is `canvas_items`, which scales the UI and NOTHING else: the 3D
## pass was rendering at the phone's full native resolution, which on a 1080p
## panel is 2.6 megapixels a frame and on a 1.5K one is 3.3.
##
## Memory is not the reason to turn it down — 0.8 saves about 7 MB, which is
## noise. FRAGMENT WORK is: cost goes with the square, so 0.8 is 64% of the
## shading, the overdraw, and the bandwidth, and bandwidth is what makes a
## phone hot, and heat is what makes it throttle its touch digitizer, which is
## the failure this whole project keeps designing around.
##
## And it costs this art style almost nothing. Everything on screen is an
## untextured primitive in a flat colour; there is no texture detail for the
## upscale to smear, and the MSAA above already softens the edges that are the
## only high-frequency thing in the frame.
func render_scale() -> float:
	return [0.75, 0.85, 1.0][effective_tier()]


## HOW FINE THE GROUND IS CUT, in quads along a 48m chunk. The mesh and the
## collision heightmap are both built from this grid, so it is the resolution of
## the world you can see AND the one you walk on and dig into.
##
## It was a flat 12 — four-metre triangles — because building a chunk was
## expensive. It was expensive because it was doing the same work five times
## over (see Chunk._build_terrain), and it is not any more, so this can be what
## the shape of the land deserves rather than what the noise budget allowed.
## Triangles were never the constraint: even 24 is 1,152 a chunk, and a phone
## draws a million a frame without noticing.
## TWICE the old 12, and no further. Not because it costs anything — a 32x32
## grid was measured at half the build price of the 12x12 that shipped, and 5.7
## MB of a ~300 MB budget — but because the ground is about to be re-textured
## anyway, with a lushness that answers to fire, rain, drought and lava. Detail
## bought now is detail spent twice, so this is deliberately the modest step:
## 2.00m cells, 1,152 triangles a chunk, and the room to go further is there
## whenever the surfacing has settled.
func chunk_cells() -> int:
	return [16, 24, 24][effective_tier()]


## HOW FINELY A CHUNK IS CUT WHEN IT IS ONLY EVER LOOKED AT.
##
## The land is the budget — 83% of every triangle in a full town — and nearly
## all of it is ground the player can never reach this session. Past
## `load_radius` a chunk is scenery: no collision, no water, nothing scattered,
## nothing to walk on. It does not need three-metre cells, and at a hundred and
## fifty metres through fog it cannot be seen to have them.
##
## Eight cells is six metres a sample and 128 triangles; with its skirt, 192.
## That is a sixth of the 1,152 a near chunk costs, and — because a grid is
## sampled as (cells+1)^2 and every sample is five noise evaluations plus a walk
## of the scars — it is an eighth of the work to BUILD, which matters more. The
## far ring is built while the player is walking, and that is where hitches come
## from.
##
## A budget device goes coarser still: 6 cells is 72 triangles and 120 with the
## skirt, and its far ring is only five chunks deep anyway.
func far_cells() -> int:
	return [6, 8, 8][effective_tier()]


## HOW MANY DECISIONS A FRAME the whole world is allowed to make.
##
## The hard ceiling on the spool. A villager's `_choose` walks the job board,
## scores seventeen kinds of work and asks the village several questions, and it
## is the most expensive thing a crowd does — but it is bursty rather than
## constant, so the average was never the problem and capping the average was
## never the fix. This caps the PEAK, which is what a player feels.
##
## A town of two hundred re-deciding at once clears in 200/this frames: about a
## third of a second at the top tier, two thirds on a budget phone. Everybody
## goes on walking or standing where they were until their turn comes.
##
## The creature is not counted here and never waits — see Spool.
func decisions() -> int:
	return [4, 8, 14][effective_tier()]


## HOW MANY TREE FRIENDS may be alive at once. Each is one billboarded quad
## with a shared texture, so the plates are nearly free; what this really
## bounds is the per-frame work of moving and startling them. Voices are
## capped separately and far lower (TreeFriends.VOICES).
func critters() -> int:
	return [10, 22, 34][effective_tier()]


## HOW MANY HEAD OF A HERD ARE REAL ANIMALS at once, across the whole world.
##
## This is the number that decides whether herds are affordable at all. Drawing
## them is nearly free — one MultiMesh instance a head, so two hundred reindeer
## are one draw call — but an Animal is a CharacterBody3D that runs physics
## every frame and thinks every second, and that cost is per beast. So the mass
## is numbers and only the nearest few are animals: the ones close enough to
## pick up, throw, hunt or butcher. Past this many, a herd is scenery, which up
## a hillside is all it ever was.
func herd_agents() -> int:
	return [8, 16, 24][effective_tier()]


func load_radius() -> int:
	return [2, 3, 3][effective_tier()]


func unload_radius() -> int:
	return [3, 4, 4][effective_tier()]


## HOW MANY RINGS OF REAL WOOD STAND BEYOND THE RING THAT IS A PLACE.
##
## Past `load_radius` a chunk carries nothing but its billboards: one painted
## quad a tree, two triangles, no node. The quads stand exactly where the trunks
## would (both are placed off the analytic ground, off the same seeded stand),
## so nothing MOVES when one becomes the other — but a quad is a quad, and the
## line where the wood turns real is the most visible seam left in the world.
##
## One ring further out on the tier that can hold it. What that buys is the seam
## pushed from about 150 metres to about 190; what it costs is the trunks
## themselves — thirty-two chunks' worth of WildTree nodes, each one a body in
## every `get_nodes_in_group("trees")` scan in the game, which is precisely what
## the billboards exist to avoid. A desktop can afford that. A phone cannot, and
## keeps the seam.
func wood_beyond() -> int:
	return [0, 0, 1][effective_tier()]


## HOW FAR THE LAND ITSELF IS HELD, in chunks — much wider than `load_radius`,
## because these two rings answer different questions. Inside `load_radius` a
## chunk is a place: collision to walk on, water to drown in, trees, herds,
## villages. Out here it is only the shape of the ground, built once and left
## standing, so that the hills you can see are hills instead of a fog bank that
## grows a ridge the moment you turn towards it.
##
## SIZED FROM `camera_far` AND NOTHING ELSE. A chunk is 48m and the camera may
## be standing on the far edge of its own cell, so covering D metres in the
## worst case needs ceil(D / 48) rings: 220 -> 5, 300 -> 7, 380 -> 8. Fog does
## not let us stop short of that — at these densities the land is still a sixth
## visible at the far plane on every tier (see `fog_density`).
func sight_radius() -> int:
	return [5, 7, 8][effective_tier()]


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


## HOW MANY REAL LIGHTS the night is allowed on the ground, over and above the
## creature's own radiance (see Nightfall). Point lights are what a tiled
## mobile GPU minds most, and there may be hundreds of villages, so the pool is
## small and fixed and the nearest towns get it. A hot device lets them go out
## one at a time and keeps only the beast you are watching.
func night_lights() -> int:
	return [2, 4, 6][effective_tier()]


## Manual override -------------------------------------------------------------

## Cycle LOW -> MEDIUM -> HIGH, persist it, and re-apply what can change
## live. Radius and water rebuild on the next world reload.
func cycle() -> void:
	tier = ((tier + 1) % 3) as Tier
	_save_override(tier)
	GameState.announce("Graphics quality: %s (some parts apply on restart)"
		% Tier.keys()[tier].capitalize())
	quality_changed.emit()


## PICK ONE OUTRIGHT, which is what a settings wall with three buttons on it
## needs — `cycle` is for the F2 key, where stepping round is the only gesture
## a single key has. Same persistence, same live re-apply.
func choose(want: Tier) -> void:
	if want == tier:
		return
	tier = want
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
