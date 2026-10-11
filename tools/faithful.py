#!/usr/bin/env python3
"""A TOWN THAT BELIEVES IS NEVER LOST, NEAR OR FAR.

It used to be raised whole as the game loaded, wherever it was, so that its
prayers came in and a colony (founded by a wagon on no site the world founds
towns on) came back at all. Towns out of sight are numbers now (Chessboard), so
a believing town far off stays folded -- and must still pray, still count, and
still be there, once.

What holds that in place:
  1. THE CHESSBOARD COMES WITH THE WORLD: main adds it as the land is raised.
  2. IT RAISES ANY REMEMBERED TOWN, colony or not, AS THE LAND COMES BACK TO IT
     (WorldGen.raise_record) -- never home, never one already standing -- and
     the raised town's cell is marked so the streaming land does not found it
     twice.
  3. IT TAKES BACK ITS OWN PAST the way any town does: SaveGame.recall, by
     position, when the town opens for business -- caught up to now first.
  4. A FOLDED TOWN THAT BELIEVES PRAYS, and counts toward the prayer the god
     can hold.
  5. A TOWN STILL BEING RAISED IS NOT WRITTEN DOWN: a save in its first few
     seconds would hold fresh strangers beside the real record.
  6. And with GODOT set to a Godot binary, both launches are run for real
     (tools/saves/faithful_live.gd): found a believing town past the horizon,
     save, launch again, and find it kept -- once, believing, praying.
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
    if "add_child(Chessboard.new())" not in ready:
        fail.append("the chessboard does not come with the world")
    board = (ROOT / "scripts/world/board/chessboard.gd").read_text()
    near = body(board, "_unfold_the_near")
    if "world.raise_record(record)" not in near or 'bool(record.get("home", false))' not in near \
            or "standing" not in near:
        fail.append("remembered towns are not raised as the land comes back, or home or a "
                    "standing town is raised again")
    if "_village_cells[cell] = town" not in body(WORLD, "raise_record"):
        fail.append("a raised town's cell is not marked: the land streaming in founds it twice")
    if "SaveGame.recall(self)" not in body(VILLAGE, "_deal_the_work"):
        fail.append("a town no longer takes back its own past when it opens for business")
    if "Chessboard.bring_up_to_date(" not in body(SAVE, "take_back") or "take_back(village)" not in body(SAVE, "recall"):
        fail.append("a town is taken back without its years away")
    if "founded = true" not in body(VILLAGE, "_open_for_business"):
        fail.append("a town never says it is whole")
    pray = body(board, "_pray")
    if "GameState.add_prayer_power(" not in pray or '"converted"' not in pray:
        fail.append("a folded town that believes no longer prays")
    if "Chessboard.remembered_believers()" not in body(VILLAGE, "_update_influence"):
        fail.append("a folded town that believes no longer counts toward the prayer the god can hold")
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
    print("BELIEVING TOWNS, NEVER LOST")
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
