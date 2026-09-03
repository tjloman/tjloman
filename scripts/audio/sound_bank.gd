extends Node
## Autoload `SoundBank`: every sound in the game is synthesized here at
## startup — no audio assets needed. Sounds play positionally in 3D with
## random pitch variation so a field of sheep never sounds like a loop.

const SAMPLE_RATE := 22050
const MAX_CONCURRENT := 24

var _bank := {}
var _active := 0


func _ready() -> void:
	_bank["baa"] = _make_baa()
	_bank["cluck"] = _make_cluck()
	_bank["oink"] = _make_oink()
	_bank["neigh"] = _make_neigh()
	_bank["bark"] = _make_bark()
	_bank["howl"] = _make_howl()
	_bank["croak"] = _make_croak()
	_bank["saw"] = _make_saw()
	_bank["pick"] = _make_pick()
	_bank["hammer"] = _make_hammer()
	_bank["murmur"] = _make_murmur()
	_bank["chatter"] = _make_chatter()
	_bank["boom"] = _make_boom()
	_bank["coo"] = _make_coo()
	_bank["caw"] = _make_caw()
	_bank["screech"] = _make_screech()
	_bank["drum"] = _make_drum()
	_bank["whisper"] = _make_whisper()


## Plays a named sound at a world position, then cleans itself up.
func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.12) -> void:
	if not _bank.has(sound) or _active >= MAX_CONCURRENT:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _bank[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.max_distance = 50.0
	p.unit_size = 8.0
	scene.add_child(p)
	p.global_position = pos
	_active += 1
	p.finished.connect(func() -> void:
		_active -= 1
		p.queue_free())
	p.play()


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
