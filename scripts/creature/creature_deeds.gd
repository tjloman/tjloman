class_name CreatureDeeds
extends RefCounted
## THE RECORD OF A LIFE — 256 deeds he still remembers, and the canvas
## underneath them of everything he no longer does.
##
## Character used to be a running impression: one number an axis, nudged 5% by
## each deed, which is a memory of about twenty deeds. Twenty deeds is FIVE
## MINUTES. A creature could spend an afternoon hauling grain to a village and
## be indistinguishable, by teatime, from one that had never done it — and a
## creature that ate somebody at noon was innocent again by supper, because the
## only trace a deed left was a number the next deed moved.
##
## So deeds are CATALOGUED instead. Two hundred and fifty-six of them, each with
## its own weight in the range the rest of this game already speaks in:
##
##     00 .. FF     how much of himself went into it
##
## An hour of his conduct, deed by deed, kept as a record rather than boiled
## down to an impression — and because every one of them is still there to be
## read, "he has rescued four people and eaten one" and "he has rescued one
## person and eaten four" are finally different creatures instead of two
## averages that happen to land on the same number.
##
## THE RING TAPERS. The newest deed counts for all of itself, the oldest for a
## quarter, and everything between slides down that slope as it ages. Nothing
## drops off a cliff — which matters, because the 257th deed pushes the 1st out
## and what happens at that moment is the whole point of the file.
##
## WHAT FALLS OUT OF MEMORY PAINTS THE CANVAS. A deed he no longer remembers is
## not a deed that never happened: on its way out it lays down a little of its
## meaning permanently, and the canvas of those deposits shows through
## everything he does afterwards. He stops remembering the day he ate a man and
## starts BELIEVING that eating men is right — which is also the moment it goes
## up on the nest wall in words (see `_paint`), because a conviction a player
## cannot read is a number pretending to be a character.
##
## AND THE CANVAS CAN BE DILUTED, BUT NEVER SCRUBBED. Good years thin a bad one
## the way water thins ink, and they never take it out: the deepest few marks
## of a life — his worst and his best — are kept whole and go on tinting the
## reading forever. A creature nobody can ruin is not a character, and neither
## is one that can be laundered. The faults are what make him real.

## HOW MANY DEEDS HE CARRIES. One byte's worth, which is not a coincidence: the
## stature counter reads in hex on the same wall, and a life of 00..FF deeds
## each weighing 00..FF is the same idiom twice.
const MOST := 256
const FULL := 255.0
## HOW MUCH MORE A MOMENTOUS DEED COUNTS THAN A ROUTINE ONE. A record read as a
## plain average is a record that launders: a hundred chores with one killing
## among them averages out to a mildly useful afternoon, and four killings among
## them average out to very nearly the same afternoon. Measured, the two were
## 0.04 of alignment apart — the old twenty-deed impression told them further
## apart than that, which would have made this whole file a downgrade.
##
## So a deed's say in the reading goes as the SQUARE ROOT OF ITS CUBE — eating
## somebody (1.2 on mercy) weighs eleven times what tending a field does (0.2),
## rather than six. At 1.5 the same two lives read 0.62 of alignment apart, and
## a man who rescued four and killed one is no longer arithmetically the same
## man as one who rescued one and killed four.
const GRAVITY := 1.5
## And every deed still takes up room in the record whether or not it had
## anything to say on this axis. Without this, a creature that had done nothing
## all hour but tend fields would read as FULLY merciful — unanimity in trifles
## is not sainthood, and this is the term that says so.
const VOICE := 0.10
## What the oldest deed in the ring still counts for, and the shape of the slide
## down to it. Nothing leaves the record by falling off the end of it.
const TAIL := 0.25
const TAPER := 1.5
## How much of a deed survives being forgotten, as a share of what it weighed.
## Small on purpose: a life is thousands of deeds and the canvas is all of them,
## so each one may only ever be a brushstroke.
const PAINT := 0.09
const CANVAS_LIMIT := 1.2
## HOW MUCH OF THE READING IS RECENT CONDUCT, the rest being the canvas. Two
## thirds, so what he has been doing this hour is most of who he is — and a
## third of him is who he has been.
const RING_SHARE := 0.65
## THE MARKS HE NEVER LOSES: the deepest few of his life each way. They are kept
## whole, they are readable, and they tint the reading forever at this share —
## enough that a man-eater never quite reads clean however good he becomes.
const MARKS := 4
const REMEMBERED := 0.12
## Below this a deed is too slight to be worth remembering as a mark at all.
const WORTH_MARKING := 0.35

## No verb: a moral shape assembled on the spot rather than one of his own
## deeds — watching his god, mostly. It still weighs; it simply has no name.
const NAMELESS := 255

## The ring, one lane a fact. Meaning is stored in hundredths as a signed byte,
## which is exactly the precision CreatureEthos.MEANING is written to.
var verb := PackedByteArray()
var force := PackedByteArray()
var mean := PackedByteArray()
var head := 0
var many := 0
## What has fallen out of memory, per axis, and the deepest marks of his life.
var canvas := {}
var scars: Array = []
var graces: Array = []
## WHERE A FORGOTTEN DEED GOES TO BE SAID OUT LOUD. Set by the mind, the same
## way it hands the welfare over — a record that only moved numbers would be a
## character the player has no way of hearing about.
var beliefs: CreatureBeliefs = null
var _names: Array = []


func _init() -> void:
	verb.resize(MOST)
	force.resize(MOST)
	mean.resize(MOST * CreatureEthos.AXES.size())
	for a: String in CreatureEthos.AXES:
		canvas[a] = 0.0


## A DEED IS DONE. `profile` is what it meant, `weight` how much of a whole deed
## this was (see CreatureMind's pacing), and `named` the verb if it had one.
func add(profile: Dictionary, weight: float, named := "") -> void:
	var w := clampf(weight, 0.0, 1.0)
	if w <= 0.0:
		return
	if many >= MOST:
		_forget(head)      # the 257th deed pushes the 1st out, and it paints
	verb[head] = _index_of(named)
	force[head] = int(round(w * FULL))
	var axes := CreatureEthos.AXES
	for i in axes.size():
		mean[head * axes.size() + i] = _to_byte(float(profile.get(axes[i], 0.0)))
	head = (head + 1) % MOST
	many = mini(many + 1, MOST)


## WHERE HE STANDS ON ONE AXIS: the recent record, the canvas showing through
## it, and the marks he never loses tinting both.
func standing(which: String) -> float:
	var at := CreatureEthos.AXES.find(which)
	if at < 0:
		return 0.0
	return clampf(_ring(at) * RING_SHARE + float(canvas.get(which, 0.0)) * (1.0 - RING_SHARE)
		+ _marked(at) * REMEMBERED, -CANVAS_LIMIT, CANVAS_LIMIT)


## Every axis at once, which is what the reading actually wants.
func reading() -> Dictionary:
	var out := {}
	for a: String in CreatureEthos.AXES:
		out[a] = standing(a)
	return out


## How much of his record is filled in — 0 at birth, 1 after an hour of conduct.
func fullness() -> float:
	return float(many) / float(MOST)


## THE DEEDS HE WILL NEVER BE RID OF, worst first, in the form the nest wall and
## his dreams want them: the verb, what it weighed, and which way it cut.
func marks() -> Array:
	var out := scars.duplicate()
	out.append_array(graces)
	out.sort_custom(func(a, b): return absf(a["weight"]) > absf(b["weight"]))
	return out


## The weighted read of the ring alone, for anything that wants to know what he
## has been doing LATELY as against what he is.
func lately(which: String) -> float:
	var at := CreatureEthos.AXES.find(which)
	return _ring(at) if at >= 0 else 0.0


func _ring(at: int) -> float:
	if many == 0:
		return 0.0
	var axes := CreatureEthos.AXES.size()
	var total := 0.0
	var spread := 0.0
	for age in many:
		var slot := posmod(head - 1 - age, MOST)
		var w := float(force[slot]) / FULL * _taper(age)
		if w <= 0.0:
			continue
		var m := _from_byte(mean[slot * axes + at])
		var say := pow(absf(m), GRAVITY)
		total += signf(m) * say * w
		spread += (say + VOICE) * w
	return total / spread if spread > 0.0 else 0.0


## How much an age-old deed still counts for: all of itself when it is the last
## thing he did, a quarter of itself when it is the oldest thing he remembers.
func _taper(age: int) -> float:
	return 1.0 - pow(float(age) / float(MOST), TAPER) * (1.0 - TAIL)


## FORGOTTEN, AND THEREFORE PERMANENT. The slot about to be overwritten lays
## what is left of its meaning onto the canvas, is weighed for a mark, and — if
## it had a name — becomes something he can be heard to believe.
func _forget(slot: int) -> void:
	var axes := CreatureEthos.AXES.size()
	var w := float(force[slot]) / FULL * TAIL
	if w <= 0.0:
		return
	var named := _name_of(int(verb[slot]))
	var meant: Dictionary = CreatureEthos.MEANING.get(named, {})
	var worst := 0.0
	# WAS IT HIS? A scolding goes into the record meaning the REVERSE of the act
	# (see CreatureEthos.push), and the difference decides what he takes away
	# from having forgotten it: a deed he stood by becomes a thing he believes
	# is right, and one he was told off for becomes a thing he believes is
	# wrong of him. Nothing else in the file can tell those two apart.
	var his := 0.0
	for i in axes:
		var amount := _from_byte(mean[slot * axes + i]) * w
		var a: String = CreatureEthos.AXES[i]
		canvas[a] = clampf(float(canvas.get(a, 0.0)) + amount * PAINT,
			-CANVAS_LIMIT, CANVAS_LIMIT)
		worst += amount * float(CreatureEthos.GOOD.get(a, 0.0))
		his += amount * float(meant.get(a, 0.0))
	_mark(int(verb[slot]), worst, his >= 0.0)
	if beliefs != null and verb[slot] != NAMELESS:
		beliefs.conviction(named, absf(worst) * (1.0 if his >= 0.0 else -1.0))


## A deed deep enough to outlive its own memory. Kept whole, both ways: the
## darkest few things he ever did and the brightest few, because a life is not
## characterised by either alone.
func _mark(which: int, worth: float, his: bool) -> void:
	if absf(worth) < WORTH_MARKING * PAINT or which == NAMELESS:
		return
	var into := scars if worth < 0.0 else graces
	into.append({"verb": _name_of(which), "weight": worth, "his": his})
	into.sort_custom(func(a, b): return absf(a["weight"]) > absf(b["weight"]))
	while into.size() > MARKS:
		into.pop_back()


## What the marks do to one axis forever: the deepest thing he ever did that way
## still shows, however much has been painted over it since.
func _marked(at: int) -> float:
	var a: String = CreatureEthos.AXES[at]
	var out := 0.0
	for mark: Dictionary in marks():
		var profile: Dictionary = CreatureEthos.MEANING.get(mark["verb"], {})
		# The deed's own meaning, the way HE did it. Reading the sign off the
		# mark's worth instead had a man-eater's worst scar making him read
		# MORE merciful, because a cruel deed and a cruel worth are both
		# already negative and the two cancelled.
		if profile.has(a):
			out += float(profile[a]) * (1.0 if bool(mark.get("his", true)) else -1.0)
	return clampf(out / float(MARKS * 2), -1.0, 1.0)


func _index_of(named: String) -> int:
	if named == "":
		return NAMELESS
	var at := _catalogue().find(named)
	return at if at >= 0 and at < NAMELESS else NAMELESS


func _name_of(which: int) -> String:
	var all := _catalogue()
	return String(all[which]) if which < all.size() else ""


## The verb order the bytes are written against, kept once and taken straight
## from the meanings — a second list of verbs would only drift from the first.
func _catalogue() -> Array:
	if _names.is_empty():
		_names = CreatureEthos.MEANING.keys()
	return _names


func _to_byte(value: float) -> int:
	return int(round(clampf(value, -1.27, 1.27) * 100.0)) & 0xFF


func _from_byte(raw: int) -> float:
	return float(raw - 256 if raw > 127 else raw) / 100.0


## Persistence. The ring goes out as hex, one byte a pair of characters, which
## is both the most compact thing JSON will hold and the same way his stature is
## written on his own wall. The verb names ride along in the order the bytes
## were written against, so a later build that adds a deed cannot make an old
## save mean something else.
func to_dict() -> Dictionary:
	return {
		"verb": verb.hex_encode(), "force": force.hex_encode(),
		"mean": mean.hex_encode(), "head": head, "many": many,
		"canvas": canvas.duplicate(), "scars": scars.duplicate(true),
		"graces": graces.duplicate(true), "key": _catalogue().duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	var was: Array = data.get("key", [])
	verb = _unhex(String(data.get("verb", "")), MOST)
	force = _unhex(String(data.get("force", "")), MOST)
	mean = _unhex(String(data.get("mean", "")), MOST * CreatureEthos.AXES.size())
	head = clampi(int(data.get("head", 0)), 0, MOST - 1)
	many = clampi(int(data.get("many", 0)), 0, MOST)
	for a: String in CreatureEthos.AXES:
		canvas[a] = clampf(float(data.get("canvas", {}).get(a, 0.0)),
			-CANVAS_LIMIT, CANVAS_LIMIT)
	scars = data.get("scars", []).duplicate(true)
	graces = data.get("graces", []).duplicate(true)
	if not was.is_empty() and was != _catalogue():
		_restamp(was)


## The saved deeds were written against THAT order of verbs; put them back
## against this one. Anything the build has since dropped becomes nameless
## rather than becoming somebody else's deed.
func _restamp(was: Array) -> void:
	for slot in MOST:
		var old := int(verb[slot])
		verb[slot] = _index_of(String(was[old]) if old < was.size() else "")


func _unhex(text: String, size: int) -> PackedByteArray:
	var out := text.hex_decode()
	out.resize(size)
	return out


## SEEDED FROM AN OLD SAVE, which has six numbers and no record behind them.
## They go on the canvas: it is exactly what the canvas is for, and it means a
## creature loaded from a save before this file existed keeps the character his
## player raised instead of waking up blank.
func inherit(axes: Dictionary) -> void:
	for a: String in CreatureEthos.AXES:
		canvas[a] = clampf(float(axes.get(a, 0.0)), -CANVAS_LIMIT, CANVAS_LIMIT)
