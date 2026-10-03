# native/ — the baked shadows, in C++

This folder is a small **GDExtension**: C++ that Godot loads as a shared library
and that GDScript can call. It holds the game's shadows.

- **Source** lives here (`src/`, `tests/`).
- **Built libraries** land in `../bin/shade/`, next to `shade.gdextension`. That
  manifest tells Godot which library to load on which platform.
- **The editor ignores this folder** because of the empty `.gdignore` file, so
  it never scans thousands of C++ files.

> **Nothing here is required to run the game.** If the library for your platform
> has not been built, Godot prints one line about it at startup and the game runs
> exactly as before, just without baked shadows. `Shade.on()` is false and every
> `Shade` call does nothing. Build the library and the shadows appear.

---

## Part 1 — How it works (the tutorial)

### The problem it solves

A real-time shadow (the `shadow_enabled` switch on a light) works like this:
every frame, the GPU draws the whole scene a second time from the sun into a
depth texture called a shadow map. Then every pixel of the real frame looks that
map up. On a phone that second pass was the most expensive thing the game asked
of the GPU, and the blurry, flickering result looked bad.

### The idea: bake the shape, move the sun in steps

A shadow is just a model's shape, squashed flat onto the ground along the
direction the light travels. So:

1. **Bake the shape once.** When a model is built, `ShadowBaker` (C++) takes its
   vertices and computes their **convex hull**: the tightest convex shell around
   them, like shrink-wrap. It first keeps only the furthest point in each of 122
   fixed directions (its "support points"). That caps every hull at about 240
   triangles, whether the model had fifty vertices or fifty thousand. The hull is
   hung under the model as a child `MeshInstance3D` named `Shadow`.

2. **Flatten it on the GPU.** The shadow's material is
   `shaders/baked_shadow.gdshader`. Its vertex shader moves every vertex of the
   hull down onto the ground along the light. It's one small, dark,
   see-through draw per model. There is no shadow map and no second pass, and no
   CPU work after the bake.

   *Why a convex hull?* Flatten a convex shape and its sun-facing faces cover the
   shadow exactly once; its other faces cover it exactly once more, wound the
   opposite way. Culling one winding (`cull_back`) leaves it covered **exactly
   once**: no stencil buffer, and no darker patches where parts overlap.

3. **Move the sun in steps.** `ShadowSky` (C++, one node) is told the time of
   day every frame. It moves the sun only every `Shade.STEP_SECONDS` (4 s of a
   320 s day, about 4.5°) and eases into each new place over half a second. The
   whole world's shadows are steered by **one global shader value** (`shade_sun`),
   so a step costs the same whether there are ten shadows or ten thousand.

4. **Miracle lights overrule the sun.** Every light a miracle makes goes through
   `Shade.light()`. The sky follows each one (its place, energy and range are
   read live, so a flash fading out fades its shadows too) and hands the four that
   matter most to the camera to the shader (`shade_light_0..3`). A model near one
   throws its shadow away from the fire instead of away from the sun. A model with
   the light *inside* it (a burning tree, the creature's glow) keeps the sun's
   shadow, so it doesn't splay out from its own middle.

### Who does what

| Piece | Language | Job |
|---|---|---|
| `src/shade_core.hpp` | C++ (no Godot) | The arithmetic: hull, support points, sun direction, stepping, choosing lights. Tested on its own. |
| `src/shadow_baker.*` | C++ / godot-cpp | `ShadowBaker.bake(mesh)`, `bake_points(points)`: returns the hull as an `ArrayMesh`. |
| `src/shadow_sky.*` | C++ / godot-cpp | `ShadowSky` node: `set_day`, `follow(light)`, `flash(...)`; writes the globals. |
| `src/register_types.*` | C++ / godot-cpp | The entry point (`shade_library_init`) that registers both classes. |
| `../bin/shade/shade.gdextension` | config | Which library file Godot loads on which platform. |
| `../shaders/baked_shadow.gdshader` | Godot shader | Flattens a hull onto the ground along the sun or a nearby light. |
| `../project.godot` `[shader_globals]` | config | Declares the six global values the C++ writes and the shader reads. |
| `../scripts/shade.gd` | GDScript | `Shade`: the only GDScript that talks to the C++. It names the classes only as strings, so the game parses without the library. |
| `../tools/shade.py` | Python | Holds the system together: names agree, every miracle light goes through `Shade.light`, the core tests pass. |

### Doing things with it

**Give a new model a shadow.** One call, once, when the model is built:

```gdscript
# One mesh (a welded building, a shared body):
Shade.cast(mesh_instance, Quality.shadow_reach())
# A thing made of several parts, gathered into root's space, remembered by a key
# so a crowd of identical things is baked once:
Shade.cast_parts(root, Quality.shadow_reach(), "my_thing|" + kind)
```

The shadow lies on the plane through the node's **origin**, so the node's origin
should be where the model meets the ground (it is, for everything in this game).

**Make a light for a new miracle.** Never `OmniLight3D.new()` under
`scripts/miracles/`; `tools/shade.py` fails the build if you do. Instead:

```gdscript
var glow := Shade.light(self, Color(1.0, 0.5, 0.1), 3.0, 12.0, Vector3(0, 2, 0))
# Tween glow.light_energy down and queue_free it as usual; its shadows follow.
```

**Tune it.** In `scripts/shade.gd`: `STEP_SECONDS` (how often the sun moves),
`EASE_SECONDS`, `BUILDING_REACH`. In `scripts/quality.gd`: `shadow_reach()` (how
far out shadows are drawn, by tier). In the shader: `LONGEST` (the longest a
shadow may get, as a multiple of the caster's height) and `LIFT`. How dark a full
sun's shadow is: `SunStepper::darkest` in `shade_core.hpp` (0.45), which can also
be set from GDScript as the `darkest` property of the sky.

---

## Part 2 — Building it

You build **godot-cpp** (Godot's C++ bindings) and this library together with
**SCons**, a Python build tool. The first build of each platform and target
compiles all of godot-cpp, which takes a few minutes. After that, only the
handful of files here are recompiled.

### Once, on any machine

1. **Python 3.8+** and **SCons**. Take SCons from your system's package
   manager where it has one. Arch, Debian 12+, Ubuntu 23.04+ and Fedora protect
   their system Python from `pip` (PEP 668: "externally-managed-environment"):
   ```
   sudo pacman -S scons            # Arch, Manjaro, shanios
   sudo apt install scons          # Debian, Ubuntu
   sudo dnf install scons          # Fedora
   brew install scons              # macOS
   pipx install scons              # anywhere, in its own environment
   python -m pip install scons     # Windows, where pip is yours to use
   ```
2. **The godot-cpp source.** It is a git submodule of this repository at
   `native/godot-cpp`:
   ```
   git submodule update --init --recursive
   ```
   (Or clone with `git clone --recursive ...`.) It is pinned to a godot-cpp
   commit (`507ed9d`) that ships the Godot **4.7** API. `native/SConstruct` asks
   for `api_version 4.7`, matching the engine version in the top-level README.
   **When the team upgrades Godot, change `api_version` in `SConstruct` and
   `compatibility_minimum` in `bin/shade/shade.gdextension` in the same commit.**
   `tools/shade.py` checks that the three agree.

   *Using a checkout of godot-cpp somewhere else:* set the environment variable
   `GODOT_CPP` to its path before running `scons`.

   *Exactly matching a custom engine build:* dump its API and build against that:
   ```
   godot --headless --dump-extension-api      # writes extension_api.json
   scons platform=... custom_api_file=path/to/extension_api.json
   ```

3. **Every build command is run from this folder:**
   ```
   cd native
   ```

**Debug or release?** The editor and debug exports load `template_debug`
builds; release exports load `template_release`. Build both for any platform you
export to. There is no separate `editor` build; the debug library works in the
editor.

### Windows (desktop)

Install **Visual Studio 2022** (or just the *Build Tools*) with the *Desktop
development with C++* workload. Open the **x64 Native Tools Command Prompt for
VS 2022** (from the Start menu, so the compiler is on the path), then:

```
cd path\to\repo\native
scons platform=windows target=template_debug
scons platform=windows target=template_release
```

That gives `bin\shade\libshade.windows.template_debug.x86_64.dll` and its release
twin. No Visual Studio? Install **MinGW-w64** (e.g. via MSYS2), put its `bin` on
`PATH` and add `use_mingw=yes` to each command.

### Android (your phone)

The phone build happens on your desktop with Android's C++ compiler, the **NDK**.

1. Install **Android Studio** (or the command-line SDK tools). In *SDK Manager →
   SDK Tools*, tick **Show Package Details**, and under **NDK (Side by side)**
   install **28.1.13356709**, the version godot-cpp expects.
2. Point `ANDROID_HOME` at the SDK folder (the one that contains `ndk/`):
   - Windows (Command Prompt): `set ANDROID_HOME=C:\Users\you\AppData\Local\Android\Sdk`
   - Linux / macOS: `export ANDROID_HOME=$HOME/Android/Sdk` (macOS: `$HOME/Library/Android/sdk`)

   Already have a different NDK? Add `ndk_version=<the folder name under ndk/>`
   to the commands.

   **No SDK, or one without `cmdline-tools`?** The build needs only the NDK.
   Download it on its own (r28b is 28.1.13356709), unpack it, and point
   `ANDROID_NDK_ROOT` at it. Then pass `ANDROID_HOME=` **empty** on every scons
   command: godot-cpp reads `ANDROID_HOME` before `ANDROID_NDK_ROOT`, and
   crashes (`KeyError: 'ANDROID_HOME'`) if it isn't there at all.
   ```
   curl -LO https://dl.google.com/android/repository/android-ndk-r28b-linux.zip
   unzip -q android-ndk-r28b-linux.zip
   export ANDROID_NDK_ROOT=$PWD/android-ndk-r28b     # fish: set -x ANDROID_NDK_ROOT $PWD/android-ndk-r28b
   scons platform=android arch=arm64 target=template_debug ANDROID_HOME=
   ```
3. Build for 64-bit ARM, which is every phone from the last decade:
   ```
   scons platform=android arch=arm64 target=template_debug
   scons platform=android arch=arm64 target=template_release
   ```
   Optional, for the Android emulator: the same with `arch=x86_64`.
4. **Export from the editor as usual.** The Android export picks up
   `libshade.android.template_*.arm64.so` from `bin/shade/` and packs it into
   the APK by itself. No Gradle or custom build template is needed.

### Immutable Linux (Shanios, Fedora Silverblue, SteamOS, Bazzite…)

The root filesystem is read-only, so `pacman`/`dnf` cannot install the
compilers on the host. Build inside a **Distrobox** container instead: it
shares your home folder, so the repository and the built library are the same
files the host's Godot sees.

```
distrobox create --name godot-build --image debian:12
distrobox enter godot-build
sudo apt update && sudo apt install -y build-essential scons git python3
cd ~/path/to/repo/native
scons platform=linux target=template_debug -j$(nproc)
scons platform=linux target=template_release -j$(nproc)
```

**Why Debian 12 and not Arch, on an Arch-based system:** a Linux library only
loads under a C library (glibc) at least as new as the one it was built
against. Debian 12's is older than Arch's, Fedora's or the Flatpak Godot's, so
what it builds loads everywhere: in the official Godot binary, in Godot from
Flathub, and on the host. An `archlinux:latest` box works too, but only for a
Godot running on an equally new glibc; a Flatpak Godot then refuses the
library with `GLIBC_2.xx not found`.

The Android build can run in the same box. The NDK brings its own compiler,
so glibc does not matter there. Point `ANDROID_HOME` at the SDK in your home
folder (the one Godot's Android export already uses) and follow **Android**
below. If your Godot is the Flatpak, the headless check is
`flatpak run org.godotengine.Godot --headless --path . --script native/tests/shade_live.gd`.

### Linux

```
sudo pacman -S base-devel scons            # Arch; Debian/Ubuntu: sudo apt install build-essential scons
cd native
scons platform=linux target=template_debug
scons platform=linux target=template_release
```

### macOS

Install the Xcode command-line tools (`xcode-select --install`) and SCons, then:

```
scons platform=macos target=template_debug
scons platform=macos target=template_release
```

Each build is a `.framework` folder. Add `arch=universal` for one library that
runs on both Apple Silicon and Intel.

### iOS

iOS links statically and needs Xcode on a Mac:

```
scons platform=ios target=template_debug
scons platform=ios target=template_release
scons platform=ios target=template_debug ios_simulator=yes      # optional
```

Wrap each `.a` (and godot-cpp's own `.a` from `godot-cpp/bin/`) in an
`.xcframework`, named as `shade.gdextension` expects:

```
xcodebuild -create-xcframework \
  -library ../bin/shade/libshade.ios.template_debug.a \
  -output ../bin/shade/libshade.ios.template_debug.xcframework
xcodebuild -create-xcframework \
  -library godot-cpp/bin/libgodot-cpp.ios.template_debug.arm64.a \
  -output ../bin/shade/libgodot-cpp.ios.template_debug.xcframework
```

(and the same for `template_release`). Then export from the editor as usual.

### Checking it worked

1. **The C++ core on its own** (any machine with a C++ compiler, no Godot needed):
   ```
   g++ -std=c++17 -O2 -Wall -Wextra -I src tests/test_core.cpp -o shade_test && ./shade_test
   ```
   (On Windows: `cl /std:c++17 /EHsc /I src tests\test_core.cpp`, then `test_core.exe`.)
   It should end with `Success: no problems found`. `python3 tools/shade.py` from
   the repository root does this too, along with every other check.
2. **Inside Godot, headless** (after building for the machine you are on):
   ```
   godot --headless --path . --script native/tests/shade_live.gd
   ```
   from the repository root. This loads the library into the engine, bakes a
   capsule, a box and a plane, follows a light, and runs a flash and a midnight.
   It ends with `Success`. `GODOT=/path/to/godot python3 tools/shade.py` runs it
   along with everything else.
3. **In the editor:** open the project. A missing library is reported in the
   Output panel as `GDExtension dynamic library not found`. If that line is
   absent, the library loaded. Run the game: shadows lie under the villagers,
   houses and trees, and swing round a fireball as it lands.
4. **On the phone:** `adb logcat | grep -i gdextension` while the game starts
   shows the same line if the `.so` didn't make it into the APK.

### When it goes wrong

| Symptom | Cause, and fix |
|---|---|
| `GDExtension dynamic library not found` | Not built for this platform/target, or built under another name. Compare the file in `bin/shade/` with the line in `shade.gdextension`. |
| Editor error that the extension needs a newer Godot | `compatibility_minimum` is above your engine. Use Godot 4.7, as the README says. |
| `api_version` error from scons | godot-cpp is too old for 4.7: `git submodule update --init` again. |
| scons can't find the Android NDK | `ANDROID_HOME` is not set in *this* terminal, or that NDK version is missing. See Android, step 2. |
| `cl` / `link` not found on Windows | Use the *x64 Native Tools Command Prompt*, not a plain one. Or use `use_mingw=yes`. |
| Shadows don't move with the sun | The `[shader_globals]` in `project.godot` must name the same six values as the shader and `shadow_sky.cpp`. `tools/shade.py` checks this. |
| A villager's shadow hangs in the air while held | Expected: it lies at the model's own feet, wherever they are. |

### Cleaning

`scons -c` (with the same `platform=`/`target=`) removes what that command
built. Built libraries are never committed: `bin/shade/.gitignore` keeps only
the manifest.
