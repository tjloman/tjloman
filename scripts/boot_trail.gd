class_name BootTrail
extends RefCounted
## WHERE THE LAST LAUNCH GOT TO.
##
## "I exported to .apk, downloaded it, and it crashes during load at low
## percentage" — then loaded fine — then "it crashed going to the creature."
## A phone that dies leaves nothing a player can read: the log is in logcat,
## behind a cable. So the game writes down each step it starts — the loading
## stages, and in play the heavy things that happen when the view moves (land
## built and let go, herds brought back, villages founded, the camera sent
## somewhere) — the last few of them, to one small file, before it starts each.
##
## A launch that is left normally ends its trail with LEFT. One that dies ends
## it with whatever it was doing, and the NEXT launch reads that and puts it on
## the start screen.

const PATH := "user://boot_trail.txt"
## How many steps are kept: enough to see what led up to it.
const KEEP := 8
## A trail ending in either of these ended well.
const READY := "loaded"
const LEFT := "left the game"

static var _steps := PackedStringArray()
## THE LAST LAUNCH'S TRAIL, read once, before this launch writes a word. Read
## lazily rather than by whoever asks first: an autoload ahead of the start screen
## (SoundBank, synthesizing) can mark a step before anybody has looked, and that
## mark overwrote the only record of how the last launch ended.
static var _before := PackedStringArray()
static var _remembered := false


## Starting this step. Written only when it changes, and closed at once so it is
## on the device whatever happens next.
static func mark(step: String) -> void:
	_remember()
	if not _steps.is_empty() and _steps[_steps.size() - 1] == step:
		return
	_steps.append(step)
	if _steps.size() > KEEP:
		_steps = _steps.slice(_steps.size() - KEEP)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("\n".join(_steps))
	f.close()


## Loading finished.
static func finish() -> void:
	mark(READY)


## The game was put away — closed, or sent to the background, where the system
## may end it without it being a crash.
static func left() -> void:
	mark(LEFT)


## The last steps of the last launch, oldest first, if it DIED — empty if it
## ended well or there was none.
static func where_last_stopped() -> PackedStringArray:
	_remember()
	if _before.is_empty() or _before[_before.size() - 1] in [READY, LEFT]:
		return PackedStringArray()
	return _before


## DID THE LAST LAUNCH DIE AT ANY POINT — loading or playing? A launch that is
## left normally (closed, or put in the background) ends its trail with LEFT;
## anything else stopped mid-step. Stricter than `where_last_stopped`, which
## lets "loaded" pass so the start screen does not report a crash during play as
## one during loading. See Quality._ready, which needs to know either way.
static func died() -> bool:
	_remember()
	return not _before.is_empty() and _before[_before.size() - 1] != LEFT


static func _remember() -> void:
	if _remembered:
		return
	_remembered = true
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	_before = f.get_as_text().strip_edges().split("\n", false)
	f.close()
