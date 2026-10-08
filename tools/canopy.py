#!/usr/bin/env python3
"""ONLY UNDER THE CANOPY.

"They need to be simply doing nothing unless the player's camera is beneath a
certain altitude. Literally, drawn and doing nothing at all. Nothing in the
game notices them." Every critter moved, flickered and sang every frame, and
the shy ones looked about for people four times a second — for small things
nobody can see from the height the camera nearly always is.

Now TreeFriends reads the camera's height over the ground beneath it: below
WAKE_BELOW the wood is alive; above STILL_ABOVE every critter stops where it
is, still drawn, gives up its voice, and the census stops too.

Statements here; with GODOT set, tools/live/critters_live.gd checks it in a
real engine (high: still; low: awake and moving; high again: still, silent,
still drawn).
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WOOD = (ROOT / "scripts/world/tree_friends.gd").read_text()
TREE = (ROOT / "scripts/world/wild_tree.gd").read_text()


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


def const(text, name):
    return float(re.search(r"^const %s := ([0-9.]+)" % name, text, re.M).group(1))


def source(fail):
    proc = body(WOOD, "_process")
    gate = proc.find("if not _awake:")
    census = proc.find("_cull()")
    if "camera_height() < (STILL_ABOVE if _awake else WAKE_BELOW)" not in proc \
            or gate < 0 or census < 0 or gate > census:
        fail.append("the wood runs its census whatever the camera's height")
    stir = body(WOOD, "_stir")
    if "c.set_process(awake)" not in stir or "c.listen(false)" not in stir:
        fail.append("stilling the wood does not stop every critter and silence it")
    if "queue_free" in stir:
        fail.append("stilling the wood frees its critters — they are to stay drawn")
    height = body(WOOD, "camera_height")
    if "world.drawn_height_at(" not in height or "get_camera_3d()" not in height:
        fail.append("the camera's height is not read over the drawn ground beneath it")
    wake = const(WOOD, "WAKE_BELOW")
    still = const(WOOD, "STILL_ABOVE")
    # A medium tree: half the way from sapling to full grown, its crown's foot.
    trunk = 3.5
    mature = const(TREE, "MATURE_SCALE")
    sapling = const(TREE, "SAPLING_SCALE")
    medium = sapling + (mature - sapling) * 0.5
    print("  awake below %.0fm, still above %.0fm; a medium tree's crown begins %.0fm up"
          % (wake, still, trunk * medium))
    if not 5.0 <= wake < still <= 16.0:
        fail.append("the canopy line is not between five and fifteen metres, with a gap")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "tools/live/critters_live.gd"], capture_output=True, text=True,
                         timeout=300)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  in Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0 else "FAILING"))
    if ran.returncode != 0:
        fail.append("in Godot:\n" + "\n".join(ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("ONLY UNDER THE CANOPY")
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
