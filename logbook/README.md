# Trip Logbook

A logbook for a long ride. It records where you were, continuously, whether or
not there is signal — and pins everything else that happened (photos, notes,
calls, messages, what was playing, what the battery was doing, what the sky was
doing) to that line on the map. Months later the timeline is the thing you cut
a vlog from: scrub to a moment and it tells you where you were, what the
weather was, who called, and what was in your ears.

Godot 4.7 draws it. An Android foreground service does the actual logging, so
the phone can be locked in the trailer on a charger and the journey still gets
written down.

---

## The shape of it

```
                    ┌──────────────────────────────┐
   the phone ──────▶│  LogService (Kotlin)         │
   GPS, BLE, calls, │  foreground, wake-locked,    │
   notifications,   │  survives reboot and OOM     │
   media session    └───────────────┬──────────────┘
                                    │ appends, never reads
                       ┌────────────▼─────────────┐
                       │  track.ndjson            │
                       │  sensor.ndjson           │   append-only, one
                       └────────────┬─────────────┘   record per line
                                    │ tails, never writes
                    ┌───────────────▼──────────────┐
                    │  Godot front end             │
                    │  map · timeline · journal    │──▶ events.ndjson
                    │  weather · bike · stops      │    (the app's own file)
                    └──────────────────────────────┘
```

One writer per file. No database, no locking, no coordination: Godot seeks to
the last byte offset it read, takes whole lines, and stops at the last newline.
A phone that dies mid-write costs you one truncated line, and the next launch
skips it.

Half a million fixes is a slow file to re-parse at every launch, so the app
folds what it has read into a binary snapshot (`track.bin`) and only parses the
tail after it. Opening a two-month trip is instant.

**Without the Android plugin the app still runs** — `platform_bridge.gd` falls
back to a simulator that rides a plausible route, drains a plausible battery,
and occasionally gets a phone call. That is how you develop the map, timeline
and journal on a laptop. Settings says plainly which mode you are in.

## What it does

**Position, always.** A fix is kept when it is accurate enough *and* far enough
or old enough — a stationary hour costs 30 records, not 3,600. Standing still
long enough is an auto-pause, so "moving time" means something. Crossing local
midnight closes the day with its own summary.

**A map that works with no data.** Slippy raster tiles drawn straight into a
`Control` — a day's track is thousands of points, and as nodes that is a
stuttering mess. Missing tiles borrow the matching quadrant of a coarser one
that is already decoded, so panning into unseen country greys out instead of
going blank. Before you leave, the prefetcher walks a corridor around your
route and pins every tile it needs; the corridor narrows as the zoom rises,
because doubling zoom quadruples tiles. An interrupted download resumes at the
tile it stopped on, even across a relaunch.

**A timeline you scrub.** The day's speed drawn as a sparkline, every entry as
a pip along it. Drag the playhead and the map follows. "Where was I when Dana
called" is a gesture, not a query.

**Journal.** Bluetooth keyboard or the in-app one (the OS keyboard resizes the
whole app and makes the layout jump; this one does not). Entries autosave, are
stamped with where you were when you started them, and there is a button that
drops the current weather and battery into the text — six months later "it was
hot" means nothing, "94°F, 18 mph headwind" is the day you remember.

**The bike.** BLE profiles for smart BMS boards (JBD/Xiaoxiang — voltage,
current, per-cell voltages, temperature, cycles, and the protection bits that
explain a cut-out), the standard Battery Service, and the standardized cycling
sensors. Range left is measured — watt-hours actually pulled per mile on this
trip — not claimed. A device nothing recognizes still lists its whole GATT
table, which is exactly what writing a new profile needs.

**Stops.** Not "where is the diner" but "will it be open when I get there, at
the speed I am actually going". Hours are free text per day the way they are
written on the door (`07:00-21:00`, `6:30-14:00,17:00-22:00`, `24h`, `closed`),
and each stop can carry one photo pulled down in advance so you recognize the
driveway at dusk.

**Weather.** Conditions and an hourly forecast (Open-Meteo, worldwide), active
watches and warnings (NWS, US), and animated radar (RainViewer). All keyless.
Everything is cached and labelled with its age, because most of the time the
honest answer is "this is two hours old".

**Music.** Play/pause and skip go through Android's MediaSession — the channel
the lock screen uses — so it drives Spotify (or anything else) with the phone
locked and no account, no API key, no network. Every track change is logged
against your position.

## Running it

**On a laptop:** Godot 4.7 → Import → `logbook/project.godot` → F5. The
simulator starts riding. Everything works except the things that need a phone.

**On the phone:** build the plugin (`android/README.md`), then export for
Android with the TripLogbook plugin ticked. First launch asks for location,
then — separately, because Android insists — background location. Grant
notification access from Settings if you want messenger entries or the media
controls.

## Map tiles, honestly

OpenStreetMap's tile servers are donated infrastructure and their usage policy
forbids bulk downloading. Browsing pulls tiles as you look at them, which is
fine. Prefetching a 2,000-mile corridor is not, and would get you blocked
before you left the driveway.

So tile sources carry a `bulk` flag, and the corridor prefetcher refuses to run
against one that does not allow it, saying why. Point the "Custom" source at
your own tile server or a provider you have a key with and the offline map
works properly. Same principle for stop photos: Street View Static needs your
own Google key, and caching one image per stop for a trip is inside their
terms — mirroring their imagery is not.

## Where the data lives

`user://trips/<trip id>/` — on Android, inside the app's private storage.

```
trip.json       name, start, planned route and stops
track.ndjson    [t, lat, lon, alt, spd, hdg, acc]   ← service writes
track.bin       pre-parsed snapshot of the above
sensor.ndjson   calls, messages, music, photos      ← service writes
events.ndjson   notes, waypoints, edits             ← app writes
media/          stop photos, voice memos
```

Events are append-only including edits: an edit appends a record with the same
id and the reader keeps the last one it sees. The history is recoverable from
the raw file if you ever want it.

Nothing here is uploaded. The only outbound traffic in the whole app is map
tiles, weather, and stop photos, all of it through `scripts/autoload/net.gd`,
which knows whether the link is metered and holds bulk work for wifi. Export
(Settings → Export) writes `track.gpx`, `journal.md`, and `events.csv` for the
video edit.

## Layout

```
scripts/
  autoload/   config · log_store · platform_bridge · net · trip · now_playing
  core/       geo · events · stops · exporter
  map/        tile_source · tile_cache · map_view · prefetch
  ble/        ble_manager · ble_profile · profiles/{jbd_bms,battery_service,cycling}
  weather/    weather
  ui/         app · status_bar · timeline · keyboard · sheet · ui · panels/
android/
  plugin/     the Kotlin foreground service and its bridge
```

Autoload order matters and is documented in `project.godot`: each one may only
touch the ones above it during `_ready()`.

## Keyboard

`J` journal · `N` new note · `D` days · `P` stops · `W` weather · `B` bike ·
`L` back to live · `space` play/pause · `[` `]` skip · `esc` close.
