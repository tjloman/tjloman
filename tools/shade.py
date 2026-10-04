#!/usr/bin/env python3
"""THE BAKED SHADOWS: C++ ON ONE SIDE, GDSCRIPT AND A SHADER ON THE OTHER.

The sun's shadow map drew the whole scene a second time every frame and looked
bad. Shadows are baked now: every model carries its convex hull (ShadowBaker,
native/), flattened onto the ground by shaders/baked_shadow.gdshader along a
sun that the C++ ShadowSky moves every few seconds, and every light a miracle
makes overrules the sun near it.

The system spans four languages and a build step, so what holds it together is
held here:

  1. THE CONVERSATION: the six global shader values have the same names in
     project.godot, in the shader, and in the C++ that writes them.
  2. THE DOOR: the entry symbol and library names agree between
     bin/shade/shade.gdextension, register_types.cpp and native/SConstruct, and
     the API version agrees with the engine the game is built on.
  3. IT STILL RUNS WITHOUT IT: no script names the C++ classes, so a machine
     that has not built the library parses and plays exactly as before.
  4. NO SHADOW MAP: the sun never casts a real-time shadow again.
  5. EVERY MIRACLE LIGHT throws shadows: nothing under scripts/miracles makes
     an OmniLight3D except through Shade.light, nor do the fires miracles
     start; the few other lights in the game are a list that may only shrink.
  6. THE MODELS cast: each kind of thing that should have a shadow asks for it.
  7. THE CORE WORKS: the C++ arithmetic (hull, sun steps, light picking) is
     compiled and its tests run, wherever a C++ compiler is on the path; and
     with GODOT set to a Godot binary, the built library is loaded into the
     engine and checked there (native/tests/shade_live.gd).
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHADE = (ROOT / "scripts/shade.gd").read_text()
GROUND = (ROOT / "scripts/shade_ground.gd").read_text()
SHADER = (ROOT / "shaders/baked_shadow.gdshader").read_text()
PROJECT = (ROOT / "project.godot").read_text()
MAIN = (ROOT / "scripts/main.gd").read_text()
EXT = (ROOT / "bin/shade/shade.gdextension").read_text()
SKY_CPP = (ROOT / "native/src/shadow_sky.cpp").read_text()
REG_CPP = (ROOT / "native/src/register_types.cpp").read_text()
CORE = (ROOT / "native/src/shade_core.hpp").read_text()
SCONS = (ROOT / "native/SConstruct").read_text()
README = (ROOT / "README.md").read_text()

# THE OTHER LIGHTS, which are not a miracle's and may make their own. This list
# may only shrink: a new light is a miracle's until somebody argues otherwise.
OTHER_LIGHTS = {
    "scripts/ui/temple_room.gd": 2,     # the temple, a room of its own
    "scripts/world/workshop.gd": 1,     # a forge's glow
    "scripts/world/nightfall.gd": 1,    # the towns' pooled night lights
    "scripts/player/divine_hand.gd": 1,  # the hand's own glow
    "scripts/shade.gd": 1,              # the door itself
}
# Who must cast a shadow, and by which call.
CASTERS = {
    "scripts/villager/villager.gd": "Shade.cast_parts(_visuals",
    "scripts/animals/animal.gd": "Shade.cast(whole",
    "scripts/creature/creature.gd": "Shade.cast_parts(_body",
    "scripts/world/house.gd": "Shade.cast(Weld.statics(self, [], [_window_mat])",
    "scripts/world/edubba.gd": "Shade.cast(Weld.statics(self)",
    "scripts/world/food_store.gd": "Shade.cast(Weld.statics(self)",
    "scripts/world/wild_tree.gd": "Shade.cast_parts(self",
}
# The fires a miracle starts, which are a miracle's light.
FIRES = {
    "scripts/world/wild_tree.gd": "_build_fire_visual",
    "scripts/world/rock_deposit.gd": "_build_flames",
}


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


def conversation(fail):
    in_project = set(re.findall(r"^(shade_\w+)=\{", PROJECT, re.M))
    in_shader = set(re.findall(r"^global uniform \w+ (shade_\w+)\b", SHADER, re.M))
    in_cpp = set(re.findall(r'"(shade_\w+)"', SKY_CPP))
    # The ground under the shadows is read in GDScript (it is the land, which
    # lives there): its two values are written by ShadeGround, the rest by C++.
    in_ground = set(re.findall(r'&"(shade_\w+)"', GROUND))
    print("  global shader values: project %d, shader %d, written by C++ %d and "
          "ShadeGround %d" % (len(in_project), len(in_shader), len(in_cpp), len(in_ground)))
    if not in_shader or in_project != in_shader or in_shader != in_cpp | in_ground \
            or in_cpp & in_ground:
        fail.append("the shader globals disagree — project.godot %s, shader %s, C++ %s, "
                    "ShadeGround %s" % (sorted(in_project), sorted(in_shader), sorted(in_cpp),
                                        sorted(in_ground)))
    slots = int(re.search(r"constexpr int SLOTS = (\d+);", CORE).group(1))
    lights = [n for n in in_shader if re.fullmatch(r"shade_light_\d", n)]
    if len(lights) != slots:
        fail.append("the C++ hands over %d lights and the shader reads %d" % (slots, len(lights)))


def door(fail):
    entry = re.search(r'entry_symbol = "(\w+)"', EXT)
    if not entry or not re.search(r"GDE_EXPORT %s\(" % entry.group(1), REG_CPP):
        fail.append("shade.gdextension's entry_symbol is not the function register_types.cpp exports")
    for path in re.findall(r'= "res://bin/shade/([^"]+)"', EXT):
        if not path.startswith("libshade.") and not path.startswith("libgodot-cpp."):
            fail.append("shade.gdextension names %s, which the SConstruct never builds" % path)
    if 'out + "libshade{}{}".format(env["suffix"], env["SHLIBSUFFIX"])' not in SCONS \
            or 'out = "../bin/shade/"' not in SCONS:
        fail.append("the SConstruct no longer builds libshade<suffix> into bin/shade/")
    engine = re.search(r"\*\*Godot (\d+\.\d+)-stable\*\*", README)
    api = re.search(r'"api_version": "(\d+\.\d+)"', SCONS)
    least = re.search(r'compatibility_minimum = "(\d+\.\d+)"', EXT)
    if not (engine and api and least) or not engine.group(1) == api.group(1) == least.group(1):
        fail.append("the engine (%s), the API the C++ is built against (%s) and the "
                    "extension's minimum (%s) are not one version"
                    % (engine and engine.group(1), api and api.group(1), least and least.group(1)))
    print("  the door: entry %s, API %s" % (entry and entry.group(1), api and api.group(1)))


def runs_without(fail):
    named = []
    for path in (ROOT / "scripts").rglob("*.gd"):
        text = bare(path.read_text())
        for m in re.finditer(r"\b(ShadowSky|ShadowBaker)\b", text):
            # A name in quotes is only a name (ClassDB.instantiate(&"ShadowSky"),
            # a node called "ShadowSky"); bare, it is a type the parser needs.
            if text[m.start() - 1:m.start()] != '"':
                named.append(path.relative_to(ROOT).as_posix())
    if named:
        fail.append("the C++ classes are named outright in %s — a machine without the "
                    "library would not parse the game" % sorted(set(named)))
    start = body(SHADE, "start")
    if 'ClassDB.class_exists(&"ShadowSky")' not in start or "ClassDB.instantiate(" not in start:
        fail.append("Shade.start no longer checks the library is there before making the sky")
    for fn in ("day", "cast", "cast_parts"):
        if "on()" not in body(SHADE, fn):
            fail.append("Shade.%s does not stand down when the library is missing" % fn)
    ready = body(MAIN, "_ready")
    if ready.find("Shade.start(self)") < 0 or ready.find("Shade.start(self)") > ready.find("WorldGen.new()"):
        fail.append("the sky is made after the world, so the first towns are built without shadows")


def no_shadow_map(fail):
    for path in (ROOT / "scripts").rglob("*.gd"):
        if re.search(r"shadow_enabled = true", bare(path.read_text())):
            fail.append("%s turns a real-time shadow on" % path.relative_to(ROOT))
    if "_sun.shadow_enabled = false" not in body(MAIN, "_build_environment"):
        fail.append("the sun is not told it casts no shadow map")
    if "Shade.day(df)" not in body(MAIN, "_update_daylight") \
            or "Shade.SUN_YAW" not in body(MAIN, "_update_daylight"):
        fail.append("the baked shadows no longer read the sun Main turns")
    yaw_cpp = float(re.search(r"double yaw_degrees = ([0-9.]+);", CORE).group(1))
    yaw_gd = float(re.search(r"^const SUN_YAW := ([0-9.]+)", SHADE, re.M).group(1))
    if yaw_cpp != yaw_gd:
        fail.append("the C++ sun's yaw (%.0f) is not the drawn sun's (%.0f)" % (yaw_cpp, yaw_gd))


def miracle_lights(fail):
    made = {}
    for path in (ROOT / "scripts").rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        n = bare(path.read_text()).count("OmniLight3D.new()")
        if n:
            made[rel] = n
    for rel, n in sorted(made.items()):
        if rel.startswith("scripts/miracles/"):
            fail.append("%s makes %d light(s) of its own — a miracle's light goes through "
                        "Shade.light, or it throws no shadows" % (rel, n))
        elif n > OTHER_LIGHTS.get(rel, 0):
            fail.append("%s makes %d light(s) of its own (allowed %d): is it a miracle's?"
                        % (rel, n, OTHER_LIGHTS.get(rel, 0)))
    for rel, fn in FIRES.items():
        text = body((ROOT / rel).read_text(), fn)
        if "Shade.light(" not in text:
            fail.append("the fire in %s (%s) lights the world without throwing shadows" % (rel, fn))
    through = sum(bare(p.read_text()).count("Shade.light(")
                  for p in (ROOT / "scripts").rglob("*.gd"))
    print("  %d lights made through Shade.light; %d others, on a list that only shrinks"
          % (through, sum(v for k, v in made.items() if k != "scripts/shade.gd")))
    light = body(SHADE, "light")
    if '_sky.call(&"follow", lamp)' not in light or "lamp.shadow_enabled = false" not in light:
        fail.append("Shade.light no longer hands the light to the sky, or lets it cast a shadow map")


def casters(fail):
    for rel, call in CASTERS.items():
        if call not in bare((ROOT / rel).read_text()):
            fail.append("%s no longer casts its baked shadow (%s)" % (rel, call))


def ground(fail):
    """THE SHADOWS LIE ON THE GROUND: every vertex set down on a height map of
    the land round the camera, read once for all of them, a few rows a frame."""
    vertex = SHADER[SHADER.index("void vertex()"):SHADER.index("void fragment()")]
    if "w.y = ground_at(w.xz, origin.y) + LIFT;" not in vertex:
        fail.append("the shadows are laid on a flat plane through the foot again, not "
                    "on the ground they fall on")
    reads = body(GROUND, "step")
    if "Time.get_ticks_usec() - began > BUDGET_USEC" not in reads \
            or "world.drawn_height_at(" not in reads or "_show()" not in reads:
        fail.append("ShadeGround reads the land without a budget, or not the drawn land")
    if re.search(r"(?<!drawn_)height_at\(", reads):
        fail.append("ShadeGround asks the costly land, not the drawn ground")
    if "_ground.step(" not in body(SHADE, "day") or 'Ledger.swap(&"Shade:ground")' not in body(SHADE, "day"):
        fail.append("nothing reads the ground under the shadows, or the meter cannot see it")
    size = int(re.search(r"^const SIZE := (\d+)", GROUND, re.M).group(1))
    cell = float(re.search(r"^const CELL := ([0-9.]+)", GROUND, re.M).group(1))
    budget = int(re.search(r"^const BUDGET_USEC := (\d+)", GROUND, re.M).group(1))
    reread = float(re.search(r"^const REREAD := ([0-9.]+)", GROUND, re.M).group(1))
    step = float(re.search(r"^const STEP_SECONDS := ([0-9.]+)", SHADE, re.M).group(1))
    reach = max(float(v) for v in re.search(
        r"func shadow_reach\(\) -> float:\s*\n\s*return \[([^\]]+)\]",
        (ROOT / "scripts/quality.gd").read_text()).group(1).split(","))
    print("  the ground: %dx%d at %.0fm (%.0fm across), %d lookups a map at %.1fms a frame, "
          "every %.0fs" % (size, size, cell, size * cell, size * size, budget / 1000.0, reread))
    if size * cell / 2.0 < reach:
        fail.append("the ground map (%.0fm each way) is narrower than the farthest shadow "
                    "drawn (%.0fm)" % (size * cell / 2.0, reach))
    if reread > step:
        fail.append("the ground is read less often than the sun moves")


def core(fail):
    cxx = shutil.which("g++") or shutil.which("clang++")
    if cxx is None:
        print("  no C++ compiler here: the core's tests were not run")
        return
    with tempfile.TemporaryDirectory() as tmp:
        exe = pathlib.Path(tmp) / "shade_test"
        built = subprocess.run([cxx, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                                "-I", str(ROOT / "native/src"),
                                str(ROOT / "native/tests/test_core.cpp"), "-o", str(exe)],
                               capture_output=True, text=True)
        if built.returncode != 0:
            fail.append("the C++ core does not compile:\n" + built.stderr[-1500:])
            return
        ran = subprocess.run([str(exe)], capture_output=True, text=True)
        lines = [ln for ln in ran.stdout.splitlines() if ln.strip()]
        print("  the C++ core's tests: %d checks, %s"
              % (sum(1 for ln in lines if ln.rstrip().endswith(("yes", "NO"))),
                 "all pass" if ran.returncode == 0 else "FAILING"))
        if ran.returncode != 0:
            fail.append("the C++ core's tests fail:\n" + "\n".join(
                ln for ln in lines if ln.rstrip().endswith("NO")))


def live(fail):
    """The built library inside a real engine, when there is one to hand: set
    GODOT to a Godot 4.7 binary. Skipped (and said so) otherwise."""
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: the library was not loaded into an engine here")
        return
    if not list((ROOT / "bin/shade").glob("libshade.*")):
        print("  no library built in bin/shade/: nothing to load")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "native/tests/shade_live.gd"], capture_output=True, text=True,
                         timeout=120)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  inside Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0
                                               else "FAILING"))
    if ran.returncode != 0:
        fail.append("the library fails inside Godot:\n" + "\n".join(
            ln for ln in checks if ln.rstrip().endswith("NO")) + ran.stderr[-800:])


def main():
    fail = []
    print("BAKED SHADOWS")
    conversation(fail)
    door(fail)
    runs_without(fail)
    no_shadow_map(fail)
    miracle_lights(fail)
    casters(fail)
    ground(fail)
    core(fail)
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
