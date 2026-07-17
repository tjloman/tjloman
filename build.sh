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
#   GODOT=~/Apps/godot ./build.sh

set -e
GODOT="${GODOT:-godot}"

build() {
    echo "==> Exporting: $1 -> $2"
    "$GODOT" --headless --export-release "$1" "$2"
}

mkdir -p builds/web

if [ -n "$1" ]; then
    case "$1" in
        Linux*) build "Linux x86_64" builds/hand-of-heavens-demo.x86_64 ;;
        Win*)   build "Windows Desktop" builds/hand-of-heavens-demo.exe ;;
        Web)    build "Web" builds/web/index.html ;;
        *) echo "Unknown preset: $1 (use Linux, Windows, or Web)"; exit 1 ;;
    esac
else
    build "Linux x86_64" builds/hand-of-heavens-demo.x86_64
    build "Windows Desktop" builds/hand-of-heavens-demo.exe
    build "Web" builds/web/index.html
fi

# Zip what shipped, ready to upload/send.
cd builds
[ -f hand-of-heavens-demo.x86_64 ] && zip -q -j hand-of-heavens-demo-linux.zip hand-of-heavens-demo.x86_64 && echo "==> builds/hand-of-heavens-demo-linux.zip"
[ -f hand-of-heavens-demo.exe ] && zip -q -j hand-of-heavens-demo-windows.zip hand-of-heavens-demo.exe && echo "==> builds/hand-of-heavens-demo-windows.zip"
[ -f web/index.html ] && (cd web && zip -q -r ../hand-of-heavens-demo-web.zip .) && echo "==> builds/hand-of-heavens-demo-web.zip"
echo "Done."
