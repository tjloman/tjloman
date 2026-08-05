# The Android half

Godot draws the app. This directory is everything Godot cannot do itself:
keeping a GPS log running with the screen off, talking to the bike's BMS over
Bluetooth LE, reading the call log, seeing other apps' notifications, and
driving whatever is playing music.

## Why it is a service and not just plugin methods

The requirement is a journey that keeps being recorded while the phone is
locked in a trailer on a charger. That rules out doing the work inside the
game loop — Godot is suspended within seconds of the screen going off. So the
logging lives in `LogService`, an Android foreground service that:

* holds a partial wake lock and a location-type foreground notification, which
  is the only combination Android will let keep a GPS stream alive indefinitely;
* writes `track.ndjson` and `sensor.ndjson` directly into the trip directory;
* is restarted by the OS if it is killed (`START_STICKY`) and by
  `BootReceiver` after a reboot;
* keeps the ebike's GATT connection, so battery samples continue without the
  app.

Godot never writes those two files. It tails them — seek to the last byte
offset, read whole lines, stop at the last newline. One writer per file, no
locking, and a phone that dies mid-write costs one line.

## Building

You need Android Studio (or a standalone SDK + Gradle) and the Godot Android
build template installed in the project (Project → Install Android Build
Template).

    cd android
    ./gradlew :plugin:assembleRelease
    cp plugin/build/outputs/aar/plugin-release.aar plugins/TripLogbook.aar

Then export the project for Android from Godot with the TripLogbook plugin
ticked in the export preset.

`build.gradle` pins `org.godotengine:godot` — that version must match the
engine version you export with, or the plugin loads and then fails at the
first signal.

## Permissions, in the order the app asks for them

| What | Why | Notes |
|---|---|---|
| Fine location | The track | Refusing it leaves you with a map and nothing else |
| Background location | The track with the screen off | Android insists this be a *second*, separate prompt after fine location is already granted |
| Bluetooth scan/connect | Battery telemetry | `neverForLocation` is declared: we are not using BLE to infer position |
| Call log | Calls on the timeline | Optional; off leaves a gap, nothing breaks |
| Media images | Placing photos on the track | We read timestamps and paths, never copy your library |
| Notification listener | Messenger entries **and** media controls | Not a runtime prompt — a settings toggle. Also the thing that makes the Spotify buttons work |
| Post notifications | Weather and battery alerts | |

Message *bodies* are only stored if you turn that on in Settings; the default
records the app, the sender, and the time.

## What leaves the phone

Nothing from the logbook. The only outbound traffic in the whole app is map
tiles, weather, and stop photos — all from `Net`, all in GDScript. This
directory does no networking at all.
