#!/usr/bin/env python3
"""THE PLAYER'S GRAPHICS: what is the tier's, what is theirs, and what loads first.

    "the 2xMSAA should be its own separate option. Let's also put our 'Glow'
     feature strictly on 'HIGH' setting. ...transparency is an important part of
     the game on medium and high, but we should also color by depth (Pale blue
     shallows, deep blue deeps). ...the camera pointing in a direction should
     determine that those chunks are loaded in before any other chunks (behind
     or to the side). The NUMBER of chunk rings should be on a slider (3-12
     individually notched, with a caution against going beyond 7, and a
     recommended setting of 5)"

What holds each in place:

  1. MSAA IS ITS OWN SWITCH: Quality.msaa_3d reads the player's `msaa`, never
     the tier and never the heat; the settings wall has a box for it.
  2. GLOW ON HIGH ALONE.
  3. CLEAR WATER STAYS THE TIER'S (MEDIUM and up), and every tier's water is
     coloured by its depth — from the heights the chunk already measured, once,
     not from a depth buffer read every frame.
  4. WHAT THE CAMERA FACES IS BUILT FIRST, in the near ring and the far ring:
     each is walked twice, ahead and then the rest.
  5. THE RINGS ARE A SLIDER: 3 to 12, a notch a ring, 5 recommended, a caution
     past 7 — and the far plane and the fog follow it, live.
  6. And with GODOT set, tools/live/graphics_live.gd does all of it in a real
     engine, the settings wall included.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
QUALITY = (ROOT / "scripts/quality.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()
RITES = (ROOT / "scripts/ui/temple_rites.gd").read_text()


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return "\n".join(ln.split("#")[0].rstrip() for ln in
                     (rest[:nxt.start()] if nxt else rest).splitlines()
                     if ln.split("#")[0].strip())


def const(text, name):
    m = re.search(r"^const %s := (\d+)" % name, text, re.M)
    return int(m.group(1)) if m else None


def source(fail):
    msaa = body(QUALITY, "msaa_3d")
    if "if msaa" not in msaa or "tier" in msaa or "heat" in msaa:
        fail.append("MSAA is not the player's own switch")
    if "Quality.set_msaa(" not in RITES:
        fail.append("the settings wall has no MSAA box")
    if "effective_tier() >= Tier.HIGH" not in body(QUALITY, "glow"):
        fail.append("glow is on below HIGH")
    if "tier >= Tier.MEDIUM" not in body(QUALITY, "water_alpha"):
        fail.append("clear water is not MEDIUM and up")
    tint = body(CHUNK, "water_tint")
    if "depth" not in tint or "SHALLOW_WATER" not in tint or "DEEP_WATER" not in tint:
        fail.append("the sea is not coloured by its depth")
    if re.search(r"hint_depth_texture|DEPTH_TEXTURE", CHUNK):
        fail.append("the sea reads the depth buffer every frame")
    for fill in ("_fill_near", "_fill_sight"):
        text = body(WORLD, fill)
        if "for facing: bool in [true, false]:" not in text or "_ahead(center, cell)" not in text:
            fail.append("%s does not build what the camera faces first" % fill)
    want = {"RINGS_LEAST": 3, "RINGS_MOST": 12, "RINGS_ADVISED": 5, "RINGS_CAUTION": 7}
    got = {k: const(QUALITY, k) for k in want}
    print("  rings: %s to %s, %s recommended, caution past %s"
          % (got["RINGS_LEAST"], got["RINGS_MOST"], got["RINGS_ADVISED"], got["RINGS_CAUTION"]))
    if got != want:
        fail.append("the rings slider is not 3-12, recommended 5, caution past 7: %s" % got)
    if "return rings" not in body(QUALITY, "sight_radius") \
            or "rings" not in body(QUALITY, "camera_far") \
            or "camera_far()" not in body(QUALITY, "fog_begins"):
        fail.append("the land, the far plane and the fog do not follow the rings")
    if "Quality.set_fog(" not in RITES:
        fail.append("the fog cannot be switched off")
    if "Quality.sight_radius()" not in body(WORLD, "_stream_chunks"):
        fail.append("the rings wait for the next world instead of applying as they move")
    caps = re.search(r"^const FPS_CAPS: Array\[int\] = \[([^\]]*)\]", QUALITY, re.M)
    print("  frame caps: %s" % (caps.group(1) if caps else "NONE"))
    if not caps or [int(v) for v in caps.group(1).split(",")] != [20, 30, 60, 0]:
        fail.append("the frame cap is not 20, 30, 60 and uncapped")
    if "Engine.max_fps = fps_cap" not in body(QUALITY, "set_fps_cap"):
        fail.append("the frame cap is not applied when it is set")
    proc = body(QUALITY, "_process")
    if "_line(FRAME_WARM" not in proc or "_line(FRAME_HOT" not in proc:
        fail.append("the thermostat reads a capped frame as strain: held to 30, it turns the world down")
    if "Quality.set_fps_cap(" not in RITES or "caution" not in body(RITES, "_say_cap"):
        fail.append("the frame-rate slider, or its warning against uncapped, is missing")
    for need in ("tick_count", "Quality.RINGS_CAUTION", "Quality.RINGS_ADVISED", "Quality.set_rings("):
        if need not in RITES:
            fail.append("the rings slider is missing %s" % need)


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "tools/live/graphics_live.gd"], capture_output=True, text=True,
                         timeout=600)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  in Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0 else "FAILING"))
    if ran.returncode != 0:
        fail.append("in Godot:\n" + "\n".join(ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("THE PLAYER'S GRAPHICS")
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
