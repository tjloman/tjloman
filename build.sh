#!/bin/sh
# Packs builds into builds/ (git-ignored), ready to send.
#
# One-time setup: open the project in the Godot editor once, then
# Editor -> Manage Export Templates -> Download and Install (must match
# the editor version, 4.7-stable). Android also needs the SDK and a debug
# keystore set in the editor (README.md, "Android (.apk)").
#
# Usage:
#   ./build.sh                  # what the testers get: Android, Windows, Linux
#   ./build.sh Windows          # just one
#   ./build.sh Android Linux    # or a few, by name: Android, Windows, Linux, Web
#
# Godot is $GODOT if set, else `godot` on PATH, else the editor kept in
# ~/Apps/godot (README.md, "Linux note"). To point at another — fish does not
# expand ~ after =, so use $HOME:
#   env GODOT=$HOME/somewhere/Godot_v4.7-stable_linux.x86_64 ./build.sh
#
# One platform failing does not stop the others: what failed is said at the
# end, and the script exits non-zero.

if [ -z "${GODOT:-}" ]; then
    if command -v godot >/dev/null 2>&1; then
        GODOT=godot
    else
        GODOT="$HOME/Apps/godot/Godot_v4.7-stable_linux.x86_64"
    fi
fi
if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "Can't run Godot as '$GODOT'. Point GODOT at the editor binary, e.g."
    echo "  env GODOT=\$HOME/Apps/godot/Godot_v4.7-stable_linux.x86_64 ./build.sh"
    exit 1
fi

# What this run exported (`made`): only those are zipped, never an older build
# an earlier run left in builds/. And what failed (`failed`), to say at the end.
made=""
failed=""

# ONE EXPORT. What an earlier export left is cleared first — the build, its
# zip, the library beside it — so a failed export leaves nothing old in
# builds/ to be sent as if it were new, and a build without a library is not
# zipped with a stale one.
#   $1 name, $2 preset, $3 output, $4 tag (libshade.<tag>.*, *-<tag>.zip),
#   $5 release|debug
export_one() {
    echo "==> Exporting: $1 -> $3"
    rm -f builds/libshade."$4".* builds/hand-of-heavens-demo-"$4".zip "$3"
    if "$GODOT" --headless --export-"$5" "$2" "$3" && [ -f "$3" ]; then
        made="$made $4"
    else
        echo "==> $1 FAILED"
        failed="$failed $1"
    fi
}

# THE BAKED SHADOWS GO WITH A BUILD ONLY IF THEIR LIBRARY WAS BUILT for that
# platform (native/README.md). Without it the game runs the same, shadowless —
# said here, because nothing else would say it until a tester's screenshot.
#   $1 name, $2 the library in bin/shade, $3 the scons line that builds it
shadows() {
    [ -f "bin/shade/$2" ] && return
    echo "    note: $1 goes without baked shadows — bin/shade/$2 is not built."
    echo "    To build it, in native/: scons $3"
}

build() {
    case "$1" in
        Android)
            shadows Android libshade.android.template_debug.arm64.so \
                "platform=android arch=arm64 target=template_debug"
            # A DEBUG build: it signs itself with the debug keystore (no
            # release keys needed) and installs on any phone with "install
            # unknown apps" allowed. Fine for testers, not for a store.
            export_one Android "Android" builds/hand-of-heavens-demo.apk android debug ;;
        Win*)
            shadows Windows libshade.windows.template_release.x86_64.dll \
                "platform=windows target=template_release use_mingw=yes"
            export_one Windows "Windows Desktop" builds/hand-of-heavens-demo.exe windows release ;;
        Linux*)
            shadows Linux libshade.linux.template_release.x86_64.so \
                "platform=linux target=template_release"
            export_one Linux "Linux x86_64" builds/hand-of-heavens-demo.x86_64 linux release ;;
        Web)
            # No library for the browser at all: the web build is shadowless.
            export_one Web "Web" builds/web/index.html web release ;;
        *)
            echo "==> Unknown platform: $1 (use Android, Windows, Linux or Web)"
            failed="$failed $1" ;;
    esac
}

mkdir -p builds/web
if [ $# -eq 0 ]; then
    set -- Android Windows Linux
fi
for platform in "$@"; do
    build "$platform"
done

# Zip what this run exported, ready to upload/send. The baked-shadow library
# is not embedded: the export puts it NEXT TO the executable, so it goes in the
# zip beside it, or the game runs without shadows (native/README.md). The APK
# needs no zip: it is one file, the library inside it.
cd builds || exit 1
ready=""
case " $made " in *" android "*)
    ready="$ready hand-of-heavens-demo.apk" ;;
esac
case " $made " in *" windows "*)
    rm -f hand-of-heavens-demo-windows.zip
    zip -q -j hand-of-heavens-demo-windows.zip hand-of-heavens-demo.exe $(ls libshade.windows.*.dll 2>/dev/null) \
        && ready="$ready hand-of-heavens-demo-windows.zip" ;;
esac
case " $made " in *" linux "*)
    rm -f hand-of-heavens-demo-linux.zip
    zip -q -j hand-of-heavens-demo-linux.zip hand-of-heavens-demo.x86_64 $(ls libshade.linux.*.so 2>/dev/null) \
        && ready="$ready hand-of-heavens-demo-linux.zip" ;;
esac
case " $made " in *" web "*)
    rm -f hand-of-heavens-demo-web.zip
    (cd web && zip -q -r ../hand-of-heavens-demo-web.zip .) \
        && ready="$ready hand-of-heavens-demo-web.zip" ;;
esac

echo
if [ -n "$ready" ]; then
    echo "Ready to send, in builds/:"
    for file in $ready; do
        echo "   $file  ($(du -h "$file" | cut -f1))"
    done
fi
if [ -n "$failed" ]; then
    echo "FAILED:$failed — see above. Nothing old is left in builds/ for it."
    exit 1
fi
echo "Done."
