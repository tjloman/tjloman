#!/usr/bin/env python3
"""THE TRAIL A CRASH LEAVES.

"It crashes during load at low percentage" — then loaded — then "it crashed
going to the creature." On a phone the log is behind a cable, so the game
writes down the last few steps it began, and the next launch says where the
last one stopped. This holds the three things that make that true:

  1. The start screen reads the last trail BEFORE this launch writes a step,
     or it only ever reports itself.
  2. Being closed or sent to the background ends a trail as LEFT, so a phone
     tidying away a paused game is not reported as a crash.
  3. The steps that matter are marked: every loading stage, and in play the
     heavy things a moving view sets off.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
READ = lambda p: (ROOT / p).read_text()


def bare(text):
    out = []
    for line in text.splitlines():
        stripped = line.split("#")[0].rstrip()
        if stripped:
            out.append(stripped)
    return "\n".join(out)


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def main():
    fail = []
    start = READ("scripts/ui/start_screen.gd")
    ready = body(start, "_ready")
    read_at = ready.find("BootTrail.where_last_stopped()")
    mark_at = ready.find("BootTrail.mark(")
    if read_at < 0 or mark_at < 0 or read_at > mark_at:
        fail.append("the start screen marks before it reads: it can only report itself")
    if "BootTrail.finish()" not in body(start, "_where_we_are"):
        fail.append("a launch that finishes loading never says so")
    if "BootTrail.mark(_warm_names[i])" not in body(start, "_warm"):
        fail.append("the warming stages are not on the trail")
    # THE LAST LAUNCH IS READ BEFORE THIS ONE WRITES: by the trail itself, on
    # first touch, so an autoload marking ahead of the start screen cannot wipe
    # the only record of how the last launch ended.
    trail = READ("scripts/boot_trail.gd")
    if not body(trail, "mark").lstrip().startswith("step: String) -> void:\n\t_remember()"):
        fail.append("BootTrail.mark writes before it has read the last launch's trail")
    for fn in ("where_last_stopped", "died"):
        if "_remember()" not in body(trail, fn):
            fail.append("BootTrail.%s reads a trail this launch may already have overwritten" % fn)
    if "!= LEFT" not in body(trail, "died"):
        fail.append("BootTrail.died does not treat everything but a clean exit as a death")
    # AND A LAUNCH THAT DIED ABOVE THIS DEVICE'S OWN TIER DOES NOT DIE AGAIN: the
    # choice is saved, so without this every launch after it crashed too.
    q = body(READ("scripts/quality.gd"), "_ready")
    if not re.search(r"if tier > detected and BootTrail\.died\(\):\n\t\tfell_back_from = tier\n"
                     r"\t\ttier = detected\n\t\t_save_override\(tier\)", q):
        fail.append("a device set above its own tier that crashed is put back there next launch")
    if "Quality.fell_back_from" not in READ("scripts/ui/start_screen.gd"):
        fail.append("falling back to the device's own tier is done silently")
    note = body(READ("scripts/main.gd"), "_notification")
    if "NOTIFICATION_APPLICATION_PAUSED" not in note or "BootTrail.left()" not in note:
        fail.append("a game sent to the background would be reported as a crash")
    for path, func, what in (
            ("scripts/world/world_gen.gd", "_spawn_chunk", "land being built"),
            ("scripts/world/world_gen.gd", "_make_whole", "land being filled in"),
            ("scripts/world/chunk.gd", "strip_down", "land being cleared"),
            ("scripts/world/chunk.gd", "restock", "herds coming back"),
            ("scripts/world/village.gd", "_ready", "a village being founded"),
            ("scripts/player/camera_rig.gd", "snap_to", "the camera being sent somewhere"),
            ("scripts/ui/touch_controls.gd", "_on_follow_toggled", "following the creature")):
        if "BootTrail.mark(" not in body(READ(path), func):
            fail.append("%s is not on the trail (%s:%s)" % (what, path, func))
    trail = READ("scripts/boot_trail.gd")
    if "f.close()" not in body(trail, "mark"):
        fail.append("a step is not closed to the file as soon as it is written")
    print("The trail: read first, marked through loading and play, closed on every step.")
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
