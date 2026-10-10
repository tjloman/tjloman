#!/usr/bin/env python3
"""THE CHESSBOARD: towns out of sight, as numbers, held to the three rules.

    "they don't do the 3 things most common in rushed designs: go extinct,
     balloon in growth, or endlessly crash."

What holds it there, in the source:

  1. THE FLOOR: the board never takes a town below TownRules.VESTIGE, and the
     vestige stays grown people; only the hand ends a town.
  2. ROOM: births need beds (plus the few a town crowds in, more for a ruin),
     never past MOST_SOULS, AND what the land feeds year in, year out
     (TownRules.land_feeds) -- the foresight that stops a town growing on a full
     larder and starving on the one it has left.
  3. THE LARDERS ARE KEPT: wild food is never taken below KEEP_STOCK.
  4. THE GRANARY: two years put by, the work falling away sharply past it, and
     nothing kept past five (RESERVE_CAP_YEARS).
  5. THE BEASTS CAN BE KEPT IN CHECK: a town's guard culls them.
  6. ONE SOURCE FOR THE LAND: a chunk scatters bushes and beasts from the very
     tables TownLand reckons a town's land from (Chunk.BUSHES, BEASTS, STAND).
  7. And with GODOT set, tools/live/century_live.gd runs the rules over 280
     towns for 180 game years and judges every one.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RULES = (ROOT / "scripts/world/board/town_rules.gd").read_text()
LAND = (ROOT / "scripts/world/board/town_land.gd").read_text()
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return "\n".join(ln.split("#")[0].rstrip() for ln in
                     (rest[:nxt.start()] if nxt else rest).splitlines()
                     if ln.split("#")[0].strip())


def const(name):
    m = re.search(r"^const %s := ([0-9.]+)" % name, RULES, re.M)
    return float(m.group(1)) if m else None


def source(fail):
    lives = body(RULES, "_lives")
    if "pop - died < floor_at" not in lives or "minf(VESTIGE, pop)" not in lives:
        fail.append("the board can take a town below the vestige")
    if "grow_old = 0.0" not in lives:
        fail.append("a vestige ages into elders who can have no children")
    if "land_feeds(book, land)" not in lives or "book.beds()" not in lives:
        fail.append("births do not listen to the beds and to what the land feeds")
    if "KEEP_STOCK" not in body(RULES, "_spare"):
        fail.append("the wild larders can be stripped")
    reserve, cap = const("RESERVE_YEARS"), const("RESERVE_CAP_YEARS")
    print("  granary: %s years put by, nothing kept past %s" % (reserve, cap))
    if reserve != 2.0 or cap != 5.0:
        fail.append("the granary is not two years kept and five at most")
    if "RESERVE_CAP_YEARS" not in body(RULES, "step") or "food_wanted(" not in body(RULES, "step"):
        fail.append("the granary has no ceiling, or the work does not ease off as it fills")
    if "cull" not in body(RULES, "step") or "_guard(book)" not in body(RULES, "step"):
        fail.append("the beasts cannot be kept in check")
    scatter = "\n".join(ln.split("#")[0] for ln in CHUNK.splitlines())
    if re.search(r"_scatter_animals\(rng, \{", scatter) or "BEASTS[biome]" not in scatter \
            or "_bushes(rng, biome)" not in scatter:
        fail.append("a chunk scatters from literals again, not the tables a town reads its land from")
    for table in ("Chunk.STAND", "Chunk.BUSHES", "Chunk.BEASTS", "herds_remembered"):
        if table not in LAND:
            fail.append("TownLand does not read %s" % table)


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "tools/live/century_live.gd"], capture_output=True, text=True,
                         timeout=600)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  in Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0 else "FAILING"))
    if ran.returncode != 0:
        fail.append("in Godot:\n" + "\n".join(ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("THE CHESSBOARD")
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
