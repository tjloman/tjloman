#!/usr/bin/env python3
"""THE GROUND'S GRAIN: a texture on the land that costs almost nothing.

    "I sort of think the ground textures would be great."

What holds it to that:

  1. NO FILES: the grain and the patches are made from noise at the first ask
     (GroundGrit), never loaded from disk.
  2. ONE MATERIAL STILL: the grain is placed by WORLD position written into the
     ground's vertices (Chunk._grain), not by a per-chunk material and not by a
     triplanar projection (three fetches a pixel where one does).
  3. BY TIER, NEVER BY HEAT: LOW none, MEDIUM the grain, HIGH grain and patches
     — the one ground material is built once with the layers it has.
  4. THE LAND'S OWN COLOURS, AS WRITTEN: the ground reads its vertex colours as
     sRGB, as WorldGen.ground_color writes them; read as linear they came out a
     good deal paler, which was most of the washed-out look.
  5. And with GODOT set, tools/live/grit_live.gd: the layers, the world UVs, a
     seamless border, LOW plain, the darkening held to "a little", the cost.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GRIT = (ROOT / "scripts/world/ground_grit.gd").read_text()
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()
UTIL = (ROOT / "scripts/util.gd").read_text()
QUALITY = (ROOT / "scripts/quality.gd").read_text()
FOOTING = (ROOT / "scripts/world/footing.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return "\n".join(ln.split("#")[0].rstrip() for ln in
                     (rest[:nxt.start()] if nxt else rest).splitlines()
                     if ln.split("#")[0].strip())


def source(fail):
    code = "\n".join(ln.split("#")[0] for ln in GRIT.splitlines())
    if re.search(r"\bload\(|preload\(|\.png|\.jpg|\.webp", code):
        fail.append("the grain is loaded from a file")
    if "get_seamless_image" not in code:
        fail.append("the grain is not made tileable, so its repeat shows as a seam")
    grain = body(CHUNK, "_grain")
    if "set_uv(" not in grain or "position.x + gx * step" not in body(CHUNK, "_cut_mesh"):
        fail.append("the ground's grain is not placed by world position")
    cut = body(CHUNK, "_cut_mesh")
    if "_grain(st" not in cut:
        fail.append("the ground mesh is cut without its grain")
    mat = body(UTIL, "ground_material")
    if re.search(r"triplanar", mat):
        fail.append("the ground reads its grain three times a pixel (triplanar)")
    if "vertex_color_is_srgb = true" not in mat:
        fail.append("the ground reads its colours as linear: the whole land comes out pale")
    if "GroundGrit.grit()" not in mat:
        fail.append("the ground material carries no grain")
    # THE GROUND A SHADE DARKER ROUND WHAT STANDS ON IT, and foam at the water.
    if "world.shade_ground(" not in body(CHUNK, "_place"):
        fail.append("a tree, bush or stone leaves the ground under it untouched")
    if "world.shade_ground(" not in body(FOOTING, "settle"):
        fail.append("a new building leaves the ground round it untouched")
    if "shade_ground(" not in body(WORLD, "reseat_over"):
        fail.append("ground cut again forgets the shade of the buildings on it")
    if "FOAM" not in body(CHUNK, "water_tint"):
        fail.append("there is no foam at the water's edge")
    detail = body(QUALITY, "ground_detail")
    print("  ground_detail: %s" % detail.strip().replace("\n", " "))
    if "[0, 1, 2][tier]" not in detail:
        fail.append("the grain is not none / grain / grain and patches by tier, or follows the heat")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "tools/live/grit_live.gd"], capture_output=True, text=True,
                         timeout=400)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  in Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0 else "FAILING"))
    if ran.returncode != 0:
        fail.append("in Godot:\n" + "\n".join(ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("THE GROUND'S GRAIN")
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
