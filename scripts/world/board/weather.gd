class_name Weather
extends RefCounted
## THE RAIN A TOWN OUT OF SIGHT GETS, for now.
##
## The sky is meant to be a layer of its own one day: a loose, fast fluid over
## the whole world, stepped every half minute, that storms and miracles paint
## into and that carries droughts from one country to the next. Until it exists,
## this is the one question the chessboard asks of it — how wet was this place
## on this day — answered from slow noise in space AND time, so a drought is a
## run of dry days over a whole region rather than a coin flipped each morning.
## When the sky layer comes, it answers the same question and nothing that asks
## has to change.

## How far a weather system reaches, in metres, and how long it lingers, in game
## days. A dry spell over a few kilometres for a week or so of days.
const REGION := 2400.0
const SPELL_DAYS := 5.0
## How far a spell strays from an ordinary day. Droughts and wet years, not a
## coin flipped between flood and dust: at this, a bad spell is half the rain.
const SWING := 0.9
## Each biome's own leaning: deserts mostly dry, rainforests mostly wet.
const WETNESS := {
	"desert": 0.35, "savanna": 0.75, "grassland": 1.0, "forest": 1.1,
	"rocky_hills": 0.9, "tundra": 0.8, "wetland": 1.3, "rainforest": 1.45,
}

static var _noise: FastNoiseLite = null
static var _seed := 0


## HOW WET THIS PLACE WAS ON THIS DAY: 0 parched, 1 an ordinary day, 2 a soaking.
## Days are game days, counted from the first (GameState.day_number); fractional
## days are fine. Deterministic in the world's seed, the place and the day, so a
## town's alibi comes out the same however late it is asked for.
static func rain(world_seed: int, at: Vector2, day: float, biome := "grassland") -> float:
	if _noise == null or _seed != world_seed:
		_noise = FastNoiseLite.new()
		_noise.seed = world_seed ^ 0x5eed
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0
		_noise.fractal_octaves = 2
		_seed = world_seed
	var spell := _noise.get_noise_3d(at.x / REGION, at.y / REGION, day / SPELL_DAYS)
	return clampf((1.0 + spell * SWING) * float(WETNESS.get(biome, 1.0)), 0.0, 2.0)
