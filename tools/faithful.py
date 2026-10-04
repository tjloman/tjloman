#!/usr/bin/env python3
"""A TOWN THAT BELIEVES COMES BACK WITH THE GAME.

A saved town came back only when its ground streamed in again: a town that
believed in you a kilometre away did not exist until you went there, and a
colony (founded by a wagon wherever it stopped, on no site the world founds
towns on) never came back at all, its record waiting in memory forever.

What holds that in place:

  1. EVERY CONVERTED TOWN IS RAISED AS THE GAME LOADS, at its saved spot, right
     after home — and only converted, non-home ones (the rest still wait to be
     walked to); its cell is marked so the streaming land does not found it
     again.
  2. IT TAKES BACK ITS OWN PAST the way any town does: SaveGame.recall, by
     position, when the town opens for business.
  3. A TOWN STILL BEING RAISED IS NOT WRITTEN DOWN: a save in its first few
     seconds would hold fresh strangers beside the real record.
  4. And with GODOT set to a Godot binary, both launches are run for real
     (tools/saves/faithful_live.gd): found a believing town past the horizon,
     save, launch again, and find it standing, once, believing, before the
     camera has gone near it.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAIN = (ROOT / "scripts/main.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()
VILLAGE = (ROOT / "scripts/world/village.gd").read_text()
SAVE = (ROOT / "scripts/save_game.gd").read_text()


def bare(text):
    return "\n".join(ln.split("#")[0].rstrip() for ln in text.splitlines()
                     if ln.split("#")[0].strip())


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def source(fail):
    ready = body(MAIN, "_ready")
    home = ready.find("world_gen.player_village = village")
    raise_at = ready.find("world_gen.raise_the_faithful(SaveGame.village_memory)")
    beast = ready.find("creature = Creature.new()")
    if raise_at < 0 or not home < raise_at < beast:
        fail.append("believing towns are not raised as the game loads, right after home")
    faithful = body(WORLD, "raise_the_faithful")
    if 'not bool(record.get("converted", false))' not in faithful \
            or 'bool(record.get("home", false))' not in faithful:
        fail.append("raise_the_faithful raises towns that do not believe, or home again")
    if "_village_cells[cell] = town" not in faithful:
        fail.append("a raised town's cell is not marked: the land streaming in founds it twice")
    if "SaveGame.recall(self)" not in body(VILLAGE, "_deal_the_work"):
        fail.append("a town no longer takes back its own past when it opens for business")
    if "founded = true" not in body(VILLAGE, "_open_for_business"):
        fail.append("a town never says it is whole")
    snap = body(SAVE, "snapshot")
    if "if not (v as Village).founded:" not in snap or "for remembered: Dictionary in village_memory" not in snap:
        fail.append("a save writes down a town still being raised, beside its real record")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: the two launches were not run here")
        return
    for mode in ("write", "read"):
        ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                              "tools/saves/faithful_live.gd", "--", mode],
                             capture_output=True, text=True, timeout=300)
        checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
        print("  launch '%s': %d checks, %s" % (mode, len(checks),
                                               "all pass" if ran.returncode == 0 else "FAILING"))
        if ran.returncode != 0:
            fail.append("the '%s' launch fails:\n%s" % (mode, "\n".join(
                ln for ln in checks if ln.rstrip().endswith("NO"))))
            return


def main():
    fail = []
    print("BELIEVING TOWNS, BACK WITH THE GAME")
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
