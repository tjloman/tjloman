#!/bin/sh
# Packs builds into builds/ (git-ignored).
#
#   ./build.sh            # Linux, for developing against the simulator
#   ./build.sh Android    # debug-signed APK for the phone
#
# GODOT can point at your editor binary (default: `godot` on PATH):
#   GODOT=~/Apps/godot ./build.sh Android
#
# Android needs the export template AND the plugin .aar in android/plugins/ —
# see android/README.md. Exporting without it produces an app that runs on the
# simulated sensors and logs nothing real.

set -e
GODOT="${GODOT:-godot}"
mkdir -p builds

case "${1:-Linux}" in
    Linux*)
        "$GODOT" --headless --export-release "Linux x86_64" builds/trip-logbook.x86_64
        ;;
    Android)
        # Debug-signed: installs on any phone with "install unknown apps"
        # allowed, no release keystore needed.
        "$GODOT" --headless --export-debug "Android" builds/trip-logbook.apk
        ;;
    *)
        echo "Unknown preset: $1 (use Linux or Android)"
        exit 1
        ;;
esac
echo "Done — see builds/"
