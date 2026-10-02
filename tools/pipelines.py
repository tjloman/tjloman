#!/usr/bin/env python3
"""NOTHING THE THERMOSTAT TOUCHES MAY REBUILD THE SCENE'S PIPELINES.

"It opens and immediately begins running fast. The moment I try to change
camera angle, it hangs 3 seconds then 'the world eases off' and the AI
simplifies." The worst frames that session were 2,253ms and 24,885ms, all but
a sliver of them BEFORE any script ran — which is the renderer.

MSAA is baked into the render pipeline of every material (and real-time
shadows were, before shadows were baked into the models — see Shade): switch
it and the GPU rebuilds all of them before it can draw again. Both used to
follow `effective_tier`, the tier minus the heat, so the thermostat easing a
struggling device down switched both mid-game, froze it, and read the freeze
as more struggling. Clear-versus-opaque water is the same kind of switch, one
chunk at a time.

This reads the statements: those three follow the tier the player chose, the
re-apply path writes them only when they differ, and the heat keeps the cheap
knobs. It also holds the creature's own meter rows and the head's fix in place.
Reading source, not a frame capture.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
QUALITY = (ROOT / "scripts/quality.gd").read_text()
MAIN = (ROOT / "scripts/main.gd").read_text()
CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()
HEAD = (ROOT / "scripts/creature/creature_head.gd").read_text()


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
    for knob in ("msaa_3d", "water_alpha"):
        text = body(QUALITY, knob)
        if "effective_tier()" in text or "heat" in text or "tier >=" not in text:
            fail.append("Quality.%s follows the heat: the thermostat would rebuild every "
                        "pipeline in the scene" % knob)
    # THE SUN CASTS NO SHADOW MAP AT ALL NOW — shadows are baked (Shade), so
    # there is no pipeline switch left to flip, and the heat's handle on them
    # is how far out they are drawn.
    if "effective_tier()" not in body(QUALITY, "shadow_reach"):
        fail.append("a hot device has no handle on shadows at all now")
    if re.search(r"Quality\.shadows\(|func shadows\(", MAIN + QUALITY):
        fail.append("the real-time shadow switch is back")
    changed = body(MAIN, "_on_quality_changed")
    if "if get_viewport().msaa_3d != Quality.msaa_3d():" not in changed:
        fail.append("MSAA is re-assigned on every quality change, not only when it differs")
    if "_sun.shadow_enabled = false" not in body(MAIN, "_build_environment") \
            or "shadow_enabled" in changed:
        fail.append("the sun casts a real-time shadow again, or a quality change can turn "
                    "one on and rebuild every pipeline in the scene")
    for cheap in ("scaling_3d_scale", "fog_density", "camera.far"):
        if cheap not in changed:
            fail.append("the heat lost its %s knob" % cheap)
    phys = body(CREATURE, "_physics_process")
    for row in ("Creature:feelings", "Creature:watching", "Creature:head",
                "Creature:hands", "Creature:trees", "Creature:look"):
        if 'Ledger.open(&"%s")' % row not in phys:
            fail.append("the creature's %s row is gone from the meter" % row)
    worth = body(HEAD, "_still_worth_it")
    if re.search(r"if subject == null:\s*\n\s*return at != Vector3\.INF", worth):
        fail.append("a creature looking at nothing re-picks every tick again — a walk "
                    "of every villager and animal thirty times a second")
    print("MSAA and clear water follow the tier; the sun casts no shadow map; the heat "
          "keeps pixels, baked-shadow reach, fog, far plane and glow.")
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
