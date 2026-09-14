extends Node
## Autoload `SoundBank`: every sound in the game is synthesized here at
## startup — no audio assets needed. Sounds play positionally in 3D with
## random pitch variation so a field of sheep never sounds like a loop.

const SAMPLE_RATE := 22050
const MAX_CONCURRENT := 24
## How much of a looping voice is folded back over its own head to hide the
## join, in seconds. A loop that clicks is worse than no loop. See `_make_loop`.
const SPLICE := 0.25

## SPOKEN LINES live in files, unlike everything else here. See `say`.
const VOICE_DIR := "res://voices/"
const VOICE_EXTS: Array[String] = [".ogg", ".wav", ".mp3"]
## How many numbered takes of a line are looked for. Probed rather than listed:
## a directory walk at runtime is a filesystem hit per call, and this is
## bounded, predictable and cached after the first ask.
const MOST_TAKES := 8

## EVERY SOUND, AND HOW TO MAKE IT. Twenty-four waveforms synthesized from
## nothing, which is why there are no audio files in this project — and which
## used to happen in one lump before the first frame was ever drawn.
##
## They are a TABLE of recipes now rather than a run of assignments, so the
## work can be done a little at a time behind the opening screen while the
## player is still choosing things (see `warm_next`), and any sound asked for
## before its turn comes simply makes itself on the spot. Nothing has to know
## which of those two happened.
const ONE_SHOTS: Array[String] = [
	"baa", "cluck", "oink", "neigh", "bark", "howl", "croak", "saw", "pick",
	"hammer", "murmur", "chatter", "boom", "coo", "caw", "screech", "drum",
	"whisper", "roar", "scream",
]
## THE SMALL VOICES. Everything above is a one-shot; these are LOOPS, because
## a cricket is not an event. See `_make_loop` and `voice`.
const VOICES: Array[String] = [
	"crickets", "bees", "flies", "peepers", "chitter", "rustle",
]

## Recorded lines, by name: an Array of streams when there are any, an empty
## Array when the folder has been looked in and there was nothing. Both answers
## are kept so a chattering town never walks the filesystem twice. See `say`.
var _said := {}
var _bank := {}
var _active := 0
## The looping voices, kept apart from the one-shots because they are used
## completely differently: a caller HOLDS one of these in a player of its own
## and rides its volume, rather than firing and forgetting. See `voice`.
var _loops := {}


## MAKE ONE THAT IS NOT MADE YET, and say whether there was anything left to
## do. The opening screen calls this until it says no; everything else calls
## `_ensure`, which reaches the same place by another door.
func warm_next() -> bool:
	# `sound` and not `name`: every Node has a `name`, and a loop variable
	# called that shadows it.
	for sound: String in ONE_SHOTS:
		if not _bank.has(sound):
			_bank[sound] = call("_make_" + sound)
			return true
	for sound: String in VOICES:
		if not _loops.has(sound):
			_loops[sound] = call("_make_" + sound)
			return true
	return false


## How much of the bank is built, 0..1 — for the line under the opening screen.
func warmth() -> float:
	var done := float(_bank.size() + _loops.size())
	return clampf(done / float(ONE_SHOTS.size() + VOICES.size()), 0.0, 1.0)


## The sound, built if this is the first anyone has asked for it.
func _ensure(sound: String) -> void:
	if _bank.has(sound):
		return
	if sound in ONE_SHOTS:
		_bank[sound] = call("_make_" + sound)


## Plays a named sound at a world position, then cleans itself up.
## `pitch` is an ABSOLUTE multiplier on top of the jitter — for a voice that has
## to belong to a body. One roar waveform covers a creature that grows fifteen
## times over only if the thing sounding it can say how big it is.
func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.12,
		pitch := 1.0) -> void:
	if _active >= MAX_CONCURRENT:
		return
	# A RECORDING BEATS THE OSCILLATOR, for any cue, not only the spoken ones.
	# `res://voices/howl.ogg` replaces the synthesized howl everywhere it fires,
	# with the same volume and the same jitter the call site asked for — so the
	# whole of voices/aDIRECTIONcoaching.md is actionable a file at a time, and
	# deleting one puts the waveform back.
	var takes: Array = _takes(sound)
	_ensure(sound)
	if takes.is_empty() and not _bank.has(sound):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = takes[randi() % takes.size()] if not takes.is_empty() else _bank[sound]
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch + randf_range(-pitch_jitter, pitch_jitter), 0.05)
	p.max_distance = 50.0
	p.unit_size = 8.0
	scene.add_child(p)
	p.global_position = pos
	_active += 1
	p.finished.connect(func() -> void:
		_active -= 1
		p.queue_free())
	p.play()


## A SOUND THAT TRAVELS WITH THE THING MAKING IT.
##
## `play_at` puts a speaker on the ground and walks away, which is right for a
## hammer blow or a tree coming down — the event happened THERE — and wrong for
## anything that is still moving while it sounds. A villager hurled across a
## valley screamed from the spot they left, so the cry stayed behind while the
## body flew off in silence, and the one moment in the game that most wants to
## be followed by ear was the one that could not be.
##
## Parented to the body, so Godot moves the emitter for us and the panning,
## the Doppler and the falloff all come out of the thing actually travelling.
##
## AND IT CUTS WHEN THE BODY GOES, which is not a bug: a scream that outlives
## its owner is a joke, and one that stops the instant they hit the ground is
## the single most effective sound in this whole class of game.
func play_on(who: Node3D, sound: String, volume_db := 0.0, pitch_jitter := 0.12,
		pitch := 1.0, reach := 70.0) -> void:
	if who == null or not is_instance_valid(who) or _active >= MAX_CONCURRENT:
		return
	var takes: Array = _takes(sound)
	_ensure(sound)
	if takes.is_empty() and not _bank.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = takes[randi() % takes.size()] if not takes.is_empty() else _bank[sound]
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch + randf_range(-pitch_jitter, pitch_jitter), 0.05)
	# Further than a fixed sound carries. A cry is the one thing a god should
	# hear from across a valley, and the ear is on the ground now rather than
	# out in the sky behind the camera — see Ear.
	p.max_distance = reach
	p.unit_size = 10.0
	# THE DOPPLER IS THE WHOLE POINT for a thrown body, and it costs nothing:
	# the engine reads the emitter's own velocity between frames.
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	who.add_child(p)
	_active += 1
	p.finished.connect(func() -> void:
		_active -= 1
		p.queue_free())
	p.play()
	# A body freed mid-cry takes its speaker with it, and `finished` never
	# fires — so the budget has to be given back on the way out as well or the
	# world goes quiet after enough people have died in mid-air.
	p.tree_exiting.connect(func() -> void:
		if p.playing:
			_active = maxi(_active - 1, 0))


## A LOOPING VOICE, for something that is always making its noise — a cricket,
## a hive, flies over meat. The caller owns the player and rides its volume,
## which is what lets a chorus go from intermittent to continuous as the player
## draws a rune. Null for an unknown name.
func voice(voice_name: String) -> AudioStreamWAV:
	# Built on the spot if the warmer has not reached it yet — a chorus asked
	# for in the first seconds must not come back silent for ever after.
	if not _loops.has(voice_name) and voice_name in VOICES:
		_loops[voice_name] = call("_make_" + voice_name)
	return _loops.get(voice_name)


func has_voice(voice_name: String) -> bool:
	return voice_name in VOICES


## Synthesis core ------------------------------------------------------------

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


func _env(t: float, duration: float, attack: float, release: float) -> float:
	var a := clampf(t / maxf(attack, 0.001), 0.0, 1.0)
	var r := clampf((duration - t) / maxf(release, 0.001), 0.0, 1.0)
	return a * r


## Sounds --------------------------------------------------------------------

## A sheep bleat: a buzzy tone with tremolo — the "a-a-a-a" of a baa.
func _make_baa() -> AudioStreamWAV:
	var dur := 0.55
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var freq := 330.0 - t * 60.0 + sin(t * 9.0 * TAU) * 15.0
		phase += freq / SAMPLE_RATE
		var buzz := 2.0 * (phase - floorf(phase)) - 1.0  # sawtooth
		var tremolo := 0.65 + 0.35 * sin(t * 24.0 * TAU)
		samples[i] = buzz * tremolo * _env(t, dur, 0.06, 0.15) * 0.5
	return _make_wav(samples)


func _make_cluck() -> AudioStreamWAV:
	var dur := 0.14
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var tone := sin(t * (900.0 - t * 2500.0) * TAU)
		var noise := randf_range(-1, 1) * 0.4
		samples[i] = (tone * 0.6 + noise) * _env(t, dur, 0.005, 0.1) * 0.5
	return _make_wav(samples)


func _make_oink() -> AudioStreamWAV:
	var dur := 0.28
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var freq := 140.0 - t * 120.0
		phase += freq / SAMPLE_RATE
		var grunt := 2.0 * (phase - floorf(phase)) - 1.0
		var snort := randf_range(-1, 1) * 0.35 * (1.0 - t / dur)
		samples[i] = (grunt * 0.6 + snort) * _env(t, dur, 0.02, 0.1) * 0.55
	return _make_wav(samples)


func _make_neigh() -> AudioStreamWAV:
	var dur := 0.85
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var freq := 950.0 - t * 550.0 + sin(t * 16.0 * TAU) * 60.0
		phase += freq / SAMPLE_RATE
		var tone := sin(phase * TAU) + 0.3 * sin(phase * 2.0 * TAU)
		samples[i] = tone * _env(t, dur, 0.05, 0.35) * 0.4
	return _make_wav(samples)


func _make_bark() -> AudioStreamWAV:
	var dur := 0.16
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var tone := sin(t * (420.0 - t * 900.0) * TAU)
		var noise := randf_range(-1, 1) * 0.5
		samples[i] = (tone * 0.5 + noise * 0.5) * _env(t, dur, 0.008, 0.08) * 0.65
	return _make_wav(samples)


func _make_howl() -> AudioStreamWAV:
	var dur := 1.7
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var frac := t / dur
		var freq := 380.0 + 240.0 * sin(frac * PI) - frac * 60.0
		phase += freq / SAMPLE_RATE
		var tone := sin(phase * TAU) + 0.25 * sin(phase * 2.0 * TAU)
		samples[i] = tone * _env(t, dur, 0.35, 0.5) * 0.4
	return _make_wav(samples)


## THE CREATURE'S OWN VOICE, and it never had one — it borrowed a dog's bark to
## warn people off and a thunderclap to smash things, which is two things that
## are not a voice. This is the one sound in the bank that belongs to a single
## character, and it is deliberately the LOWEST: a fundamental under eighty
## hertz, three stacked harmonics to give it a chest, and a band of noise over
## the top for the rasp. Pitched down it is a giant; pitched up it is a whelp,
## which is how one waveform covers a creature that grows fifteenfold.
##
## It is sounded by the HEAD, on the head's own clock, whatever the hands are
## doing — see CreatureHead.
func _make_roar() -> AudioStreamWAV:
	var dur := 1.25
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	var rasp := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var frac := t / dur
		# Up into the shout, then down and away as the breath runs out.
		var freq := 62.0 + 46.0 * sin(minf(frac * 2.1, 1.0) * PI) - frac * 14.0
		phase += freq / SAMPLE_RATE
		var chest := sin(phase * TAU) \
			+ 0.55 * sin(phase * 2.0 * TAU) \
			+ 0.3 * sin(phase * 3.0 * TAU) \
			+ 0.14 * sin(phase * 5.0 * TAU)
		# The rasp: noise smoothed into a growl rather than left as hiss, and
		# loudest in the middle where the shout is.
		rasp = rasp * 0.82 + (randf() * 2.0 - 1.0) * 0.18
		var throat := rasp * (0.35 + 0.45 * sin(frac * PI))
		samples[i] = (chest * 0.34 + throat) * _env(t, dur, 0.06, 0.45) * 0.72
	return _make_wav(samples)


func _make_croak() -> AudioStreamWAV:
	var dur := 0.3
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		phase += 95.0 / SAMPLE_RATE
		var pulse := 1.0 if fmod(phase, 1.0) < 0.4 else -0.6
		var ratchet := 0.6 + 0.4 * sin(t * 34.0 * TAU)
		samples[i] = pulse * ratchet * _env(t, dur, 0.03, 0.1) * 0.4
	return _make_wav(samples)


## Two saw strokes through wood: shaped noise.
func _make_saw() -> AudioStreamWAV:
	var dur := 0.7
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var stroke := absf(sin(t * 3.0 * TAU))  # two strokes
		var noise := randf_range(-1, 1)
		last = last * 0.7 + noise * 0.3  # crude low-pass for a woody rasp
		samples[i] = last * stroke * _env(t, dur, 0.05, 0.1) * 0.5
	return _make_wav(samples)


## Pickaxe on stone: sharp ping with a click.
func _make_pick() -> AudioStreamWAV:
	var dur := 0.18
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var decay := exp(-t * 30.0)
		var ping := sin(t * 1900.0 * TAU) * decay
		var click := randf_range(-1, 1) * exp(-t * 90.0)
		samples[i] = (ping * 0.6 + click * 0.5) * 0.6
	return _make_wav(samples)


func _make_hammer() -> AudioStreamWAV:
	var dur := 0.15
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var thud := sin(t * 85.0 * TAU) * exp(-t * 25.0)
		var knock := randf_range(-1, 1) * exp(-t * 70.0) * 0.5
		samples[i] = (thud + knock) * 0.7
	return _make_wav(samples)


## Low worship murmur: slow syllable bumps of soft noise.
func _make_murmur() -> AudioStreamWAV:
	var dur := 1.1
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var syllables := 0.5 + 0.5 * sin(t * 5.0 * TAU + sin(t * 2.3 * TAU))
		last = last * 0.92 + randf_range(-1, 1) * 0.08  # heavy low-pass
		samples[i] = last * syllables * _env(t, dur, 0.2, 0.3) * 1.4
	return _make_wav(samples)


## A dove's coo: two soft, breathy descending tones.
func _make_coo() -> AudioStreamWAV:
	var dur := 0.5
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var freq := 520.0 - t * 90.0 + (40.0 if t > 0.25 else 0.0)
		var tone := sin(t * freq * TAU) * 0.6 + sin(t * freq * 2.0 * TAU) * 0.1
		samples[i] = tone * _env(t, dur, 0.05, 0.2) * 0.4
	return _make_wav(samples)


## A raven's caw: a harsh, buzzy squawk.
func _make_caw() -> AudioStreamWAV:
	var dur := 0.32
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var freq := 380.0 - t * 120.0
		phase += freq / SAMPLE_RATE
		var buzz := 2.0 * (phase - floorf(phase)) - 1.0
		var noise := randf_range(-1, 1) * 0.3
		samples[i] = (buzz * 0.6 + noise) * _env(t, dur, 0.02, 0.12) * 0.5
	return _make_wav(samples)


## A bat's screech: a thin, high, downward shriek.
func _make_screech() -> AudioStreamWAV:
	var dur := 0.28
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var freq := 2600.0 - t * 1400.0
		var tone := sin(t * freq * TAU)
		var noise := randf_range(-1, 1) * 0.2
		samples[i] = (tone * 0.7 + noise) * _env(t, dur, 0.01, 0.1) * 0.4
	return _make_wav(samples)


## A PERSON IN EXTREMITY. Alight, struck by lightning, or turning over and over
## in the air on their way down — the three things this game does to people that
## there was previously no sound for at all.
##
## Built from a voice rather than from a siren: two formants a fifth apart with
## the pitch breaking upward at the start and cracking downward at the end,
## which is the shape a shout has and a tone does not. The noise layer is the
## breath. Deliberately short — a scream that outlasts the fall is a comedy —
## and deliberately rough, because `say` will happily replace the whole thing
## with a recorded take the day one is dropped into res://voices/ (see
## voices/aDIRECTIONcoaching.md, cue `scream`).
func _make_scream() -> AudioStreamWAV:
	var dur := 0.62
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var k := t / dur
		# Up hard, hold, then break. The hold is what makes it a cry for help
		# rather than a yelp.
		var bend := 1.0 + 0.55 * clampf(k / 0.12, 0.0, 1.0) 			- 0.45 * clampf((k - 0.62) / 0.38, 0.0, 1.0)
		var base := 340.0 * bend
		var tone := sin(t * base * TAU) * 0.55 			+ sin(t * base * 1.5 * TAU) * 0.3 			+ sin(t * base * 2.0 * TAU) * 0.15
		# The throat tightening: the rasp comes IN as the cry goes on.
		var rasp := randf_range(-1.0, 1.0) * (0.08 + 0.22 * k)
		samples[i] = (tone + rasp) * _env(t, dur, 0.02, 0.22) * 0.5
	return _make_wav(samples)


## Fireball detonation: a deep sub-bass sweep under a crackling noise burst.
func _make_boom() -> AudioStreamWAV:
	var dur := 1.1
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	var last := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var freq := 110.0 * exp(-t * 3.0) + 28.0
		phase += freq / SAMPLE_RATE
		var thump := sin(phase * TAU) * exp(-t * 3.5)
		last = last * 0.82 + randf_range(-1, 1) * 0.18  # rumbling low-passed noise
		var crackle := last * exp(-t * 4.0)
		samples[i] = clampf(thump * 0.9 + crackle * 0.7, -1.0, 1.0) * _env(t, dur, 0.004, 0.4)
	return _make_wav(samples)


## Field chatter: brighter, bubblier than murmur.
func _make_chatter() -> AudioStreamWAV:
	var dur := 0.9
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var last := 0.0
	var pitch := 300.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		if i % 1800 == 0:
			pitch = randf_range(220.0, 420.0)
		var vowel := sin(t * pitch * TAU) * 0.4
		last = last * 0.85 + randf_range(-1, 1) * 0.15
		var syllables := 0.4 + 0.6 * absf(sin(t * 7.0 * TAU))
		samples[i] = (vowel + last * 0.5) * syllables * _env(t, dur, 0.1, 0.25) * 0.45
	return _make_wav(samples)


## THE SOUND OF CASTING ---------------------------------------------------------
##
## Drawing a rune used to be silent, which made the most consequential thing in
## the game the quietest. These two are what the casting session beats and
## breathes to (see DivineHand): a drum on every rune committed, and whispers
## flitting past somewhere out in the dark while the session is open.

## A WOODY DRUM. A hollow log, not a kit tom: the wood is the point, so it is a
## sharp knock over a low membrane tone whose pitch drops as the skin relaxes,
## and it is gone in a fifth of a second. Struck harder for each rune already
## on the slate — the caller does that with volume and pitch.
func _make_drum() -> AudioStreamWAV:
	var dur := 0.42
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var body := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		# The skin: a low tone bending down as it loses tension.
		var pitch := 96.0 - 34.0 * (1.0 - exp(-t * 11.0))
		var skin := sin(t * pitch * TAU) * exp(-t * 7.5)
		# The wood: a hard, dry knock, mostly gone within a few milliseconds.
		var knock := randf_range(-1, 1) * exp(-t * 130.0) * 0.55
		# A hollow resonance under it, low-passed so it reads as a log and not
		# as a click over a sine.
		body = body * 0.86 + skin * 0.14
		samples[i] = (skin * 0.62 + body * 0.8 + knock) * _env(t, dur, 0.001, 0.12)
	return _make_wav(samples)


## WHISPERS. Not words — the shape of words: breathy noise pinched into three
## or four syllables and bandpassed to sit where speech sits, so the ear insists
## it almost understood something. Quiet on purpose; it is meant to be caught
## rather than heard.
func _make_whisper() -> AudioStreamWAV:
	var dur := 1.4
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var low := 0.0
	var prev := 0.0
	var wander := randf_range(0.0, TAU)
	for i in n:
		var t := i / float(SAMPLE_RATE)
		# Syllables: an uneven pulse, so it never reads as a machine.
		var beat := t * 3.4 * TAU + sin(t * 1.15 * TAU + wander) * 1.6
		var syllable := pow(maxf(sin(beat), 0.0), 1.7)
		var noise := randf_range(-1, 1)
		# Bandpass by hand: a one-pole low-pass, then subtract the previous
		# sample to take the rumble out. What is left is breath.
		low = low * 0.72 + noise * 0.28
		var breath := low - prev
		prev = low
		samples[i] = breath * syllable * _env(t, dur, 0.35, 0.6) * 0.9
	return _make_wav(samples)


## The small voices -----------------------------------------------------------
##
## These are LOOPS, and a loop that clicks is worse than no loop at all, so
## every one of them is built to a whole number of cycles of its own rhythm and
## crossfaded head-to-tail by `_make_loop`. They are deliberately quiet and
## deliberately dull on their own: they are meant to be noticed only when you
## bring the hand down close, and to be almost subliminal otherwise.

## Wrap a generator into a seamless loop: the last SPLICE seconds are crossfaded
## back over the first, so the join has no edge. The returned stream is marked
## LOOP_FORWARD over the surviving length.
func _make_loop(samples: PackedFloat32Array) -> AudioStreamWAV:
	var fade := int(SPLICE * SAMPLE_RATE)
	var keep := samples.size() - fade
	if keep <= fade:
		return _make_wav(samples)
	var out := PackedFloat32Array()
	out.resize(keep)
	for i in keep:
		out[i] = samples[i]
	# The tail is folded back over the head, rising as the head falls.
	for i in fade:
		var k := i / float(fade)
		out[i] = out[i] * k + samples[keep + i] * (1.0 - k)
	var wav := _make_wav(out)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = out.size()
	return wav


## CRICKETS. A field of them, not one: several stridulators at slightly
## different rates, each a fast burst of a high tone, so they drift in and out
## of phase the way a real field does and never sound like a sample.
func _make_crickets() -> AudioStreamWAV:
	var dur := 4.0
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rates := [2.9, 3.3, 3.7, 4.3]
	var tones := [4200.0, 4600.0, 3900.0, 5100.0]
	var phases := [0.0, 1.7, 3.1, 4.9]
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var sum := 0.0
		for k in rates.size():
			var rate: float = rates[k]
			var chirp: float = fmod(t * rate + phases[k], 1.0)
			# Three quick pulses, then a long gap: that is the shape of a chirp.
			if chirp > 0.16:
				continue
			var pulse := pow(maxf(sin(chirp / 0.16 * PI * 3.0), 0.0), 2.0)
			sum += sin(t * float(tones[k]) * TAU) * pulse * 0.2
		samples[i] = sum
	return _make_loop(samples)


## BEES over flowers. A warm, thick drone — two close tones beating against
## each other, which is what makes a hive sound like many rather than one — with
## the odd one passing by nearer.
func _make_bees() -> AudioStreamWAV:
	var dur := 3.0
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var low := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var drone := sin(t * 214.0 * TAU) * 0.5 + sin(t * 227.0 * TAU) * 0.45
		# A body that wanders, so the swarm breathes.
		drone *= 0.7 + 0.3 * sin(t * 0.7 * TAU)
		# One bee passing close: a swell every second or so, higher and louder.
		var pass_by := pow(maxf(sin(t * 1.1 * TAU), 0.0), 6.0)
		drone += sin(t * 340.0 * TAU) * pass_by * 0.5
		# Softened, so it is a hum and not a buzzer.
		low = low * 0.55 + drone * 0.45
		samples[i] = low * 0.32
	return _make_loop(samples)


## FLIES over something dead. Thinner and more irritable than the bees, and
## never steady: it comes and goes as they land and lift.
func _make_flies() -> AudioStreamWAV:
	var dur := 2.5
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var low := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		# The pitch itself wobbles — a fly never holds a note.
		var wob := 1.0 + 0.09 * sin(t * 5.3 * TAU) + 0.05 * sin(t * 11.7 * TAU)
		var buzz := sin(t * 168.0 * wob * TAU) * 0.6 + sin(t * 249.0 * wob * TAU) * 0.3
		# Landing and lifting: mostly on, sometimes gone.
		var settled := 0.45 + 0.55 * pow(maxf(sin(t * 0.83 * TAU + 1.2), 0.0), 0.6)
		low = low * 0.45 + buzz * 0.55
		samples[i] = low * settled * 0.26
	return _make_loop(samples)


## SPRING PEEPERS. The frogs by the water — a chorus of short rising whistles at
## a rate that speeds and slows, which is the sound of standing water at dusk.
func _make_peepers() -> AudioStreamWAV:
	var dur := 4.5
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var voices := [1.55, 1.9, 2.4]
	var pitches := [1180.0, 1420.0, 980.0]
	var offs := [0.0, 0.9, 2.2]
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var sum := 0.0
		for k in voices.size():
			var peep: float = fmod(t * float(voices[k]) + offs[k], 1.0)
			if peep > 0.22:
				continue
			var k2 := peep / 0.22
			# Each note bends UP as it sounds, which is the whole character.
			var f: float = float(pitches[k]) * (1.0 + 0.16 * k2)
			sum += sin(t * f * TAU) * sin(k2 * PI) * 0.28
		samples[i] = sum
	return _make_loop(samples)


## A SQUIRREL SCOLDING. Dry, clattering, indignant — bursts of hard little
## clicks with a rasp under them, which is what they do when you get too near
## a tree they are working.
func _make_chitter() -> AudioStreamWAV:
	var dur := 3.2
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var low := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		# Bursts, with real silence between them.
		var burst := pow(maxf(sin(t * 0.62 * TAU), 0.0), 3.0)
		# Inside a burst, a fast clatter of individual ticks.
		var tick := pow(maxf(sin(t * 17.0 * TAU), 0.0), 8.0)
		var rasp := randf_range(-1, 1)
		low = low * 0.3 + rasp * 0.7
		var body := sin(t * 620.0 * TAU) * 0.4 + low * 0.6
		samples[i] = body * tick * burst * 0.4
	return _make_loop(samples)


## LEAVES. Not an animal at all — the sound a thing MAKES in a tree, used when
## something small moves in the canopy. Filtered noise that swells and falls.
func _make_rustle() -> AudioStreamWAV:
	var dur := 2.8
	var n := int(dur * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var low := 0.0
	var prev := 0.0
	for i in n:
		var t := i / float(SAMPLE_RATE)
		var noise := randf_range(-1, 1)
		low = low * 0.6 + noise * 0.4
		var hiss := low - prev      # take the rumble out: leaves, not wind
		prev = low
		var gust := 0.25 + 0.75 * pow(maxf(sin(t * 0.71 * TAU), 0.0), 1.5)
		samples[i] = hiss * gust * 0.5
	return _make_loop(samples)


## SPOKEN LINES ------------------------------------------------------------
##
## EVERYTHING ABOVE IS SYNTHESIZED AND THERE IS NOT AN AUDIO FILE IN THIS
## PROJECT. That is the right arrangement for a sheep and the wrong one for a
## voice: nobody is going to synthesize "good morning to ye" out of oscillators,
## and the day somebody records one it should just start playing.
##
## So this is the ModelBank arrangement for sound. Drop `res://voices/yawn.ogg`
## in and villagers yawn; delete it and they go back to a murmur. Nothing here
## is required and the game runs with the folder empty.
##
## TAKES, NOT A TAKE. `line.ogg` is played if it is the only one, but `line_1`,
## `line_2`, `line_3` and so on are looked for too and one is chosen at random.
## A single recording heard twice in a minute is worse than no recording at all,
## and a town says these things constantly.
## SAY IT, if there is anything to say it with. False when there is no recording
## of this line, which is the caller's cue to fall back on something synthesized
## — see VillagerLook.may_choose, which murmurs instead.
func say(line: String, pos: Vector3, volume_db := -3.0) -> bool:
	var takes: Array = _takes(line)
	if takes.is_empty():
		return false
	var stream: AudioStream = takes[randi() % takes.size()]
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = 12.0
	player.max_distance = 40.0
	# A voice is a person, not a machine: a little pitch either way so a town
	# does not sound like one man recorded once.
	player.pitch_scale = randf_range(0.94, 1.07)
	get_tree().current_scene.add_child(player)
	player.global_position = pos
	player.play()
	player.finished.connect(player.queue_free)
	return true


func _takes(line: String) -> Array:
	if _said.has(line):
		return _said[line]
	var found: Array = []
	for stem: String in [line] + _numbered(line):
		for ext: String in VOICE_EXTS:
			var path := VOICE_DIR + stem + ext
			if ResourceLoader.exists(path):
				var res := load(path)
				if res is AudioStream:
					found.append(res)
				break
	_said[line] = found
	return found


func _numbered(line: String) -> Array:
	var out: Array = []
	for i in range(1, MOST_TAKES + 1):
		out.append("%s_%d" % [line, i])
	return out
