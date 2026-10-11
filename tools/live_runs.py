#!/usr/bin/env python3
"""THE LIVE CHECKS NOTHING ELSE RUNS, and the source they rest on.

With GODOT set to a Godot binary, runs in a real engine, headless:

  tools/live/kill_live.gd         a beast killed is dead: its herd is told at
                                  once, and the dead row never stands again;
  tools/live/typing_live.gd       the map-name field lets go of the keyboard;
  tools/live/crowd_clock_live.gd  the crowd clock pays every villager, and
                                  walks nobody in a town held still;
  tools/live/seams_live.gd        no cliff where one country meets another.

And always, the statements:

  1. A BEAST'S DEATH IS TOLD TO ITS HERD (Animal.die -> Herd.release), and the
     herd never takes a freed handle for "no body": a freed object compares
     equal to null in Godot 4 (Herd._has_body).
  2. THE CROWD CLOCK WALKS NOBODY HELD STILL: a town being raised is switched
     off, and a switched-off body has no physics space.
  3. A TOWN THE WORLD FOUNDS WHERE ONE IS REMEMBERED is raised from its record
     a few pieces a frame (VillageRaise), not founded and overwritten in one.
  4. THE MAP-NAME FIELD LETS GO OF THE KEYS.
  5. THE LAND'S RUGGEDNESS IS BLENDED ACROSS BORDERS (WorldGen._rugged), never
     read off the biome, whose line made a step metres high.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIVE = ("kill_live.gd", "typing_live.gd", "crowd_clock_live.gd", "seams_live.gd")


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return "\n".join(ln.split("#")[0].rstrip() for ln in
                     (rest[:nxt.start()] if nxt else rest).splitlines()
                     if ln.split("#")[0].strip())


def source(fail):
    animal = (ROOT / "scripts/animals/animal.gd").read_text()
    herd = (ROOT / "scripts/animals/herd.gd").read_text()
    clock = (ROOT / "scripts/crowd_clock.gd").read_text()
    world = (ROOT / "scripts/world/world_gen.gd").read_text()
    menu = (ROOT / "scripts/ui/debug_menu.gd").read_text()
    if ".release(self)" not in body(animal, "die"):
        fail.append("a beast's death is not told to its herd: the dead row stands up again")
    code = "\n".join(ln.split("#")[0] for ln in herd.splitlines())
    if re.search(r'\["agent"\]\s*[!=]=\s*null', code) or "held == null" in body(herd, "_tend_the_promoted"):
        fail.append("the herd asks a row's beast `== null`, and a freed beast is null to that")
    if "can_process()" not in body(clock, "_serve"):
        fail.append("the crowd clock walks villagers of a town held still, with no physics space")
    if "village.from_memory = true" not in body(world, "_maybe_found_village"):
        fail.append("a town the world founds where one is remembered is overwritten in one frame")
    height = body(world, "_seeded_height")
    if "_rugged(" not in height or "biome_at(" in height:
        fail.append("the land's ruggedness is read off the biome again: a cliff at every border")
    if "_soft(" not in body(world, "_rugged"):
        fail.append("the ruggedness changes at a line, not across a band")
    if "release_focus()" not in body(menu, "_input"):
        fail.append("the map-name field never lets go of the keyboard")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    for test in LIVE:
        ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                              "tools/live/" + test], capture_output=True, text=True, timeout=600)
        checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
        print("  %s in Godot: %d checks, %s" % (test, len(checks),
                                                "all pass" if ran.returncode == 0 else "FAILING"))
        if ran.returncode != 0:
            fail.append("%s in Godot:\n" % test + "\n".join(
                ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("THE LIVE CHECKS")
    source(fail)
    live(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
