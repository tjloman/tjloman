#!/usr/bin/env python3
"""EVERY LAZY CACHE IN THE GAME IS WARMED BEFORE THE GAME STARTS.

Half a dozen things in this codebase build themselves the first time anything
asks for them and are kept forever after: twenty-six synthesized waveforms, a
1024x512 star field drawn pixel by pixel, the rune templates, the cloud sheet,
the blossom, the ground material. Every one of them is the right design -- and
every one of them, left alone, lands in the middle of play. The star field
lands on the first nightfall. The waveforms land on the first wolf.

StartScreen warms them while somebody is deciding what kind of session this is
going to be. THE FAILURE THIS GUARDS IS NOT A BUG, IT IS AN OMISSION: somebody
adds the seventh lazy cache, never touches the start screen, and the hitch
comes back on a machine they do not own. Nothing errors, nothing is slower in
the editor, and the only symptom is a frame drop the first time some particular
thing is looked at.

So: every PUBLIC static function in scripts/ that lazily builds one kept value
must be named in start_screen.gd. Private ones are excused -- they are reached
through a public door, and the door is what gets warmed.

Also holds the three numbers that decide whether the screen is bearable: the
frame's share, the honesty of the bar, and the limit on how long anybody is
held behind a disabled button.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
SCREEN_FILE = SCRIPTS / "ui/start_screen.gd"
SCREEN = SCREEN_FILE.read_text()

# `static func name() -> T:` whose very next line is a guard returning a cached
# value -- `if _kept != null: return _kept`, or the emptiness form the rune
# templates use. That shape, and only that shape, is a lazy singleton.
LAZY = re.compile(
    r"^static func (\w+)\([^)]*\)[^:\n]*:\n"
    r"\tif (?:(_\w+) != null|not (_\w+)\.is_empty\(\)|(_\w+)\.is_empty\(\) == false):\n",
    re.M)
CLASS = re.compile(r"^class_name (\w+)", re.M)


def const(name, text=SCREEN, where="start_screen.gd"):
    m = re.search(r"^const %s\s*:?=\s*([0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


fail = []

# -- EVERY LAZY CACHE IS WARMED ---------------------------------------------
found = []
for path in sorted(SCRIPTS.rglob("*.gd")):
    if path == SCREEN_FILE:
        continue
    text = path.read_text()
    owner = CLASS.search(text)
    owner = owner.group(1) if owner else ""
    for match in LAZY.finditer(text):
        found.append((path.relative_to(SCRIPTS).as_posix(), owner, match.group(1)))

public = [row for row in found if not row[2].startswith("_")]
private = [row for row in found if row[2].startswith("_")]

print("LAZY CACHES IN THE GAME -- built once, on whatever frame first asks:")
for where, owner, name in found:
    if name.startswith("_"):
        print("   %-34s %-20s (private: warmed through its door)" % (where, name))
        continue
    # The CALL, not the bare name. `"texture" in SCREEN` is true the moment any
    # other warm job mentions `vapour_texture`, which is how the first version
    # of this check passed while SkyCover.texture was not warmed at all.
    call = "%s.%s(" % (owner, name)
    warmed = call in SCREEN
    print("   %-34s %-20s %s" % (where, call + ")", "warmed" if warmed else "NOT WARMED"))
    if not warmed:
        fail.append("%s builds itself once and is never warmed: it will land "
                    "on whatever frame first asks for it" % call.rstrip("("))
print()
print("   %d public, %d private." % (len(public), len(private)))

# -- AND THE THREE NUMBERS --------------------------------------------------
millis = const("WARM_MILLIS")
caches = const("CACHES_WORTH")
patience = const("PATIENCE")
FRAME_60 = 1000.0 / 60.0

print()
print("THE FRAME'S SHARE is %.1fms, out of the %.1fms a 60fps frame has."
      % (millis, FRAME_60))
if millis <= 0.0:
    fail.append("the warming budget is %.1fms: nothing is warmed at all" % millis)
elif millis >= FRAME_60:
    fail.append("the warming budget is %.1fms of a %.1fms frame: the loading "
                "screen stutters while it promises smoothness"
                % (millis, FRAME_60))

print("THE BAR gives the caches %.0f%% and the land the rest." % (caches * 100.0))
if not 0.0 < caches < 1.0:
    fail.append("CACHES_WORTH is %.2f: the bar cannot reach both ends" % caches)

print("THE WAIT ENDS after %.0f real seconds whatever the loader thinks."
      % patience)
if patience <= 0.0:
    fail.append("PATIENCE is %.0fs: the gate never closes" % patience)
if "PATIENCE" not in re.search(
        r"func _ready_to_begin\(\) -> bool:\n((?:\t.*\n)+)", SCREEN).group(1):
    fail.append("_ready_to_begin does not consult PATIENCE: a far ring that "
                "never reports itself full locks the player out of their own "
                "game with no way to say so")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: every lazy cache is warmed, and nobody is held longer than they "
      "should be.")
