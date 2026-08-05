# Drop the built plugin here

Godot looks for Android plugins in this project's `android/plugins/` folder,
as a pair of files:

    TripLogbook.gdap    the manifest (already here)
    TripLogbook.aar     the compiled plugin — build it, see ../plugin

Without the `.aar`, the app still runs: `platform_bridge.gd` falls back to its
simulator, and the Settings panel says so plainly ("No background service").
That build is fine for developing the map, timeline, and journal on a laptop —
it just cannot log anything real.
