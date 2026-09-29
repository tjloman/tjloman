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


## Starting this step. Written only when it changes, and closed at once so it is
## on the device whatever happens next.
static func mark(step: String) -> void:
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
## ended well or there was none. Read BEFORE this launch marks anything.
static func where_last_stopped() -> PackedStringArray:
	if not FileAccess.file_exists(PATH):
		return PackedStringArray()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var steps := f.get_as_text().strip_edges().split("\n", false)
	f.close()
	if steps.is_empty() or steps[steps.size() - 1] in [READY, LEFT]:
		return PackedStringArray()
	return steps
