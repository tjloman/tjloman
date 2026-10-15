#!/bin/sh
# Packs demonstration builds into builds/ (git-ignored).
#
# One-time setup: open the project in the Godot editor once, then
# Editor -> Manage Export Templates -> Download and Install (must match
# the editor version, 4.7-stable).
#
# Usage:
#   ./build.sh            # all three: Linux, Windows, Web
#   ./build.sh Web        # just one preset by name
#
# GODOT can point at your editor binary (default: `godot` on PATH), e.g.
#   GODOT=$HOME/Apps/godot/Godot_v4.7-stable_linux.x86_64 ./build.sh
# (fish does not expand ~ after =: use $HOME, and `env GODOT=... ./build.sh`)

set -e
GODOT="${GODOT:-godot}"

# What this run exported (`made`): only those are zipped, never an older build
# an earlier run left in builds/. A library left by an earlier export is
# cleared first, so a build without one is not zipped with a stale one.
made=""
build() {
    echo "==> Exporting: $1 -> $2"
    rm -f builds/libshade."$3".*
    "$GODOT" --headless --export-release "$1" "$2"
    made="$made $3"
}

mkdir -p builds/web

# Android is exported as a DEBUG build: it signs itself with the debug
# keystore (no release keys needed) and installs on any phone with
# "install unknown apps" allowed. Perfect for a demo, not for a store.
build_android() {
    echo "==> Exporting: Android (debug-signed) -> builds/hand-of-heavens-demo.apk"
    "$GODOT" --headless --export-debug "Android" builds/hand-of-heavens-demo.apk
}

if [ -n "$1" ]; then
    case "$1" in
        Linux*)   build "Linux x86_64" builds/hand-of-heavens-demo.x86_64 linux ;;
        Win*)     build "Windows Desktop" builds/hand-of-heavens-demo.exe windows ;;
        Web)      build "Web" builds/web/index.html web ;;
        Android)  build_android ;;
        *) echo "Unknown preset: $1 (use Linux, Windows, Web, or Android)"; exit 1 ;;
    esac
else
    build "Linux x86_64" builds/hand-of-heavens-demo.x86_64 linux
    build "Windows Desktop" builds/hand-of-heavens-demo.exe windows
    build "Web" builds/web/index.html web
    # Android is opt-in (./build.sh Android) — it needs the SDK installed.
fi

# Zip what this run exported, ready to upload/send. The baked-shadow library
# is not embedded: the export puts it NEXT TO the executable, so it goes in the
# zip beside it, or the game runs without shadows (native/README.md). The web
# build has none: the library is not built for the browser.
cd builds
case " $made " in *" linux "*)
    rm -f hand-of-heavens-demo-linux.zip
    zip -q -j hand-of-heavens-demo-linux.zip hand-of-heavens-demo.x86_64 $(ls libshade.linux.*.so 2>/dev/null)
    echo "==> builds/hand-of-heavens-demo-linux.zip" ;;
esac
case " $made " in *" windows "*)
    rm -f hand-of-heavens-demo-windows.zip
    zip -q -j hand-of-heavens-demo-windows.zip hand-of-heavens-demo.exe $(ls libshade.windows.*.dll 2>/dev/null)
    echo "==> builds/hand-of-heavens-demo-windows.zip" ;;
esac
case " $made " in *" web "*)
    rm -f hand-of-heavens-demo-web.zip
    (cd web && zip -q -r ../hand-of-heavens-demo-web.zip .)
    echo "==> builds/hand-of-heavens-demo-web.zip" ;;
esac
echo "Done."
