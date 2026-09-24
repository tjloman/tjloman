#!/usr/bin/env python3
"""WHERE THE FORTY-THREE MILLISECONDS WENT.

A frame meter read `script 55.7ms` with the named classes adding up to about
twelve of it and a line at the bottom saying `(everything else) 43.1`. Three
quarters of a frame with no name on it is not a measurement, it is a shrug --
and the classes that DO have names are then read as culprits, which is how an
evening gets spent optimising Villager while the answer is somewhere else
entirely.

WHAT THAT ROW ACTUALLY IS, which took reading the Ledger to establish and is
not what it looks like. The baton is continuous: `open` shuts whoever was open,
nothing calls `shut` but the page turning, so from the first clock of a page
until the page turns SOMEBODY is always being charged. The gap is therefore NOT
"the unclocked classes", scattered through the frame. It is the HEAD of the
frame: everything between the page turning and the first `open` of the next
one.

Which means the row has two very different populations in it, and they want
opposite responses:

  UNCLOCKED CALLBACKS THAT RUN EARLY. Autoloads process first, so an unclocked
  NavField, GameState or Main sat in front of every clocked node in the game
  and went into that row anonymously. These are a bug in the instrument.

  AND THE ENGINE'S OWN STEP. The physics server's broadphase and solver and the
  transform propagation run before any script does. That is real work, it is
  often most of the row, and it is not a class anybody can go and optimise.

So every per-frame callback in the game is clocked now, and this file keeps it
so: the moment one goes unclocked, the row stops meaning "the engine" and goes
back to meaning "we do not know", silently, with the number looking much the
same either way.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "scripts"

## Screens and instruments that are allowed to run unclocked, each for a reason
## that has to survive being read out loud.
EXCUSED = {
    "scripts/ui/frame_meter.gd": "the meter itself — it turns the page, and a "
                                 "clock on the page-turner would be charged to "
                                 "whoever came after it",
    "scripts/ui/start_screen.gd": "runs only before a world exists",
    "scripts/ui/logo_game.gd": "runs only before a world exists",
    "scripts/ui/profile_menu.gd": "runs only while the menu is up",
    "scripts/ui/debug_menu.gd": "runs only while the menu is up",
    "scripts/ui/temple_pool.gd": "runs only while the temple is open",
    "scripts/ui/temple_room.gd": "runs only while the temple is open",
    "scripts/ui/cast_overlay.gd": "runs only while a rune is being drawn",
    "scripts/ui/rune_readout.gd": "runs only while a rune is being drawn",
    "scripts/ui/touch_controls.gd": "runs only on a touch device, and is two "
                                    "button rects",
    "scripts/ui/tutorial.gd": "runs only while the tutorial is unfinished",
}

CALLBACKS = ("_process", "_physics_process")
fail = []
clocked, bare, excused = [], [], []

for path in sorted(SRC.glob("**/*.gd")):
    short = str(path.relative_to(ROOT))
    text = path.read_text()
    for cb in CALLBACKS:
        head = re.search(r"^func %s\([^)]*\) -> void:\n" % cb, text, re.M)
        if head is None:
            continue
        after = text[head.end():head.end() + 220]
        opens = re.search(r"Ledger\.open\(&\"(\w+)\"\)", after)
        if opens:
            clocked.append((short, cb, opens.group(1)))
        elif short in EXCUSED:
            excused.append((short, cb))
        else:
            bare.append((short, cb))

print("EVERY PER-FRAME CALLBACK IN THE GAME:")
print("   %-6s clocked" % len(clocked))
print("   %-6s excused (screens and the meter itself)" % len(excused))
print("   %-6s unclocked" % len(bare))
for short, cb in bare:
    print("      %s %s" % (short, cb))
    fail.append("%s.%s runs every frame and is not clocked, so its cost goes "
                "into the meter's leftover row without a name — and that row "
                "is supposed to mean the engine's own step by now, not "
                "'somebody forgot'" % (short, cb))

# -- THE ROW HAS TO SAY WHAT IT IS -------------------------------------------
meter = (ROOT / "scripts/ui/frame_meter.gd").read_text()
names_it = "(the engine, before any script)" in meter
print()
print("THE LEFTOVER ROW %s."
      % ("says what it is" if names_it else "IS STILL CALLED SOMETHING VAGUE"))
if not names_it:
    fail.append("the meter's leftover row does not say that it is the engine's "
                "own head-of-frame work, so the next person to read it will "
                "look for a class to blame")

# -- AND THE LEDGER'S OWN STORY HAS TO BE TRUE -------------------------------
ledger = (ROOT / "scripts/ledger.gd").read_text()
stale = "Villager and Creature are not" in ledger
print("THE LEDGER'S OWN NOTE %s."
      % ("matches what is clocked" if not stale
         else "STILL SAYS VILLAGER AND CREATURE ARE UNCLOCKED"))
if stale:
    fail.append("ledger.gd still explains why Villager and Creature cannot be "
                "clocked, and both are — a comment that is wrong about the "
                "code is worse than no comment, because it is believed")

# -- WHAT THE BILL CAN NOW ACCOUNT FOR ---------------------------------------
#
# The screenshot that started this: 55.7ms of script, ~12.4ms named across ten
# rows, 43.1ms anonymous. Every one of these thirty callbacks was in that row.
print()
print("WHAT WAS IN THAT ROW, by where it runs in a frame:")
early = [c for c in clocked if c[0] in (
    "scripts/game_state.gd", "scripts/nav_field.gd", "scripts/quality.gd",
    "scripts/save_game.gd", "scripts/main.gd")]
print("   %d of the newly clocked run BEFORE any previously clocked node "
      "(autoloads and Main), which is the front of the frame and therefore "
      "exactly what that row was made of." % len(early))
for short, cb, name in early:
    print("      %-28s %s" % (name, short))

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: %d callbacks clocked, %d excused by name, none anonymous — the "
      "leftover row is the engine and says so." % (len(clocked), len(excused)))
