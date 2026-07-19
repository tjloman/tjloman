# Hand of the Heavens (working title)

A ground-up, **Black & White**-inspired god game built in Godot. You are a
divine hand over a living world: villagers with real needs and desires, a
creature that learns, belief as your currency, and miracles cast with mouse
gestures.

This is the **ugly proof of concept** stage. Everything is primitive shapes on
purpose — we are building *systems first, art later*.

## Requirements

- **Godot 4.7-stable** — https://godotengine.org/download
  - ⚠️ Everyone on the team uses this exact version. When we upgrade, we all
    upgrade in one commit.
- Git

No other dependencies. No plugins, no assets to download — the whole world is
generated from code.

## Getting started

1. Clone the repo.
2. Open Godot → **Import** → select `project.godot` in the repo root.
3. Press **F5** (Run Project).

### Linux note (incl. ShaniOS / immutable distros)

The Godot editor is a single portable binary — keep it in `~/Apps/godot` and
you're done. No system install required.

## Controls

| Input | Action |
|---|---|
| Left mouse on land (drag) | Grab and drag the world (B&W style) |
| Left mouse on things | Pick up food / villagers / animals — even **trees** (uproot any; gentle drop replants, hard throw splinters, dropped on a storehouse banks full lumber; your creature uproots trees smaller than itself) |
| Gentle release **at your creature** | **Hand it the object** — innate; raises its attention and bond |
| Throw **to your creature** | With attention and practice it **catches** — praise catches to train the skill |
| Release with a **still** hand | **Place gently** — no fear, no harm. Placing a villager in another village makes them a **missionary** (yours → heathen town) or a **convert** (anyone → a faithful town) |
| Release while moving mouse | Throw — your hand's momentum carries; flick hard to hurl far |
| **Hold right mouse + draw** | **Cast a miracle gesture** |
| Mouse wheel | Zoom |
| Middle mouse drag | Rotate / tilt camera (tilts above the horizon for skyward throws) |
| WASD / arrows | Pan camera |
| Q / E | Rotate camera |
| 1 / 2 / 3 / 4 | Village diet: Vegan / Omnivore / Carnivore / Cannibal |
| P / L (hand near creature) | **Pet** (reward) / **scold** (discourage) its last deed |
| C | **Lock** the camera onto your creature — centered, orbitable; C again (or pan) releases |
| F1 | Help panel |

### Miracles — two gestures, then throw (hold right mouse)

Casting is two steps. First draw a **menu opener**; then draw a **selector**
inside it. The miracle is conjured as a glowing **orb into your hand** —
**throw or place it**, and it unleashes wherever it lands. (Selectors are
namespaced per menu, so the same simple shape means different things in
different menus.)

| Menu (opener) | Selector → Miracle | Cost |
|---|---|---|
| **Spiral** — Nature | Circle → Food · Vertical → Forest seed (13 trees) · Horizontal → Forage thicket · Diagonal → Rain | 20 / 45 / 30 / 25 |
| **Reverse-spiral** — Wrath | Vertical → Lightning · Circle → Lightning **storm** · Diagonal → Fireball · Horizontal → **Tornado** | 30 / 90 / 25 / 110 |
| **Wave** — Sky | Horizontal → Heal · Circle → **Bird flock** (doves/ravens/bats by alignment) · Vertical → Rain | 15 / 40 / 25 |

The mightiest miracles need a **wide reservoir of prayer** — each converted
village raises your cap (+120) and widens the fury of storms and flocks.
Everything you conjure is a throwable you place where you choose.

## The world

- **Endless, chunked terrain**: 48m chunks stream in around the camera.
  Elevation from layered noise, lakes below the water table, and five
  biomes — grassland, forest, savanna, rocky hills, wetland — each with
  its own colors, trees, and wildlife. Everything is deterministic from
  the world seed.
- **Neutral villages** generate out in the world. They run the full
  simulation (farming, building, families) but believe in nothing until
  your miracles convert them (belief ≥ 40) — then their prayers feed you.
- **Day/night cycle**: ~5⅓ real minutes per day. Sun, moon, dawn/dusk
  skies. Villagers sleep at night; house windows glow; wolves prowl —
  preferring villages gone wicked. A villager's whole life spans about
  **40 days** — time enough to grow up, raise a family, and grow old.
- **Fire spreads** — and is contained by default. Lightning (and its
  storm) and fireballs set trees ablaze; a blaze leaps only to close
  neighbours and burns out in seconds, so it runs through a dense stand
  and gutters out at gaps and water — a **tool for clearing forest that
  would otherwise creep across the map**. Rain douses it; a thrown
  burning tree is a firebrand. Fire scares off villagers and beasts but
  spares buildings.
- **Water is real**: villagers and animals cannot cross it (frogs
  excepted); nothing builds beneath it. The **shoreline feeds**: villagers
  and the creature go **fishing** — fish counts as meat, with its own
  silvery model. The creature **wades** at half speed (a future miracle
  will let it walk on water).
- **The world is the interface**: each village's ring shows its
  **population as size** and **belief as color** (gray → gold; converted
  rings wear your alignment color); the totem orb **glows with prayer
  power**. Hover a house for the census, a farm for harvest progress, the
  storehouse for stocks. **Grab a quarter of the storehouse** to withdraw
  that resource as a physical item; drop food/lumber/stone onto any
  storehouse to bank it.
- **A living ecology**: wild animals have hunger and thirst — they trek
  to water to drink, browse forage bushes, graze, breed when fed and
  watered, and die of old age way out in the woods. Forage bushes with
  regrowing berries dot every biome (villagers forage them too when the
  granary runs dry). Trees grow from 1-lumber saplings to 30-lumber
  giants — the model scales with maturity — and mature trees replant
  themselves. Rock deposits hold 300 stone and visibly wear down.
- **Sound**: every sound is synthesized in code at startup (no assets) and
  played positionally — bleating, clucking, sawing, quarry picks, hammers,
  worship murmur, barks, howls, frog croaks, and the boom of a fireball.
- **Rendering**: the Mobile renderer + MSAA. Good and plain — meant to look
  right on a phone, no advanced GPU required (yet).

## The core loop (what's simulated)

- **Villagers live whole lives**: they age, come of age at 16, slow down
  as elders, and die at 60–85 (about 40 day/night cycles) — leaving a
  physical **corpse**. Adults courting at the totem conceive children;
  pregnancy lasts nine months (game time), then a child is born, plays
  instead of working, and grows up. Births are bounded by shelter —
  build houses to grow the flock.
- **Jobs are chosen, not assigned**: every adult scores what the village
  lacks — food, lumber, stone, housing, repairs, livestock — and takes the
  most urgent work: farming, hunting, felling timber, quarrying, building,
  taming. Starvation is lethal — and the god who allowed it is judged.
- **Houses are mortal too**: hut / house / longhouse (sleeps 2/4/6), each
  with health and age. A **lived-in house is a kept house** — only empty
  ones decay with age and collapse. Builders raise new ones (lumber +
  stone, placement checked for slope, water, and clearance) and repair
  old ones. The homeless sleep rough by the totem, recover poorly, and
  grow miserable. Villagers also **break new fields** when the village
  goes hungry, and **feed the penned livestock** from the granary; the
  pen has a **well** so tamed animals can drink.
- **Livestock and taming, gated by virtue**: benevolent villagers tame
  horses (ridden on long trips), oxen and llamas (hauling: +1 to every
  harvest), and dogs (guarding, herding, and ambient joy). Wolves avoid
  villages with dogs. Monstrous villages can't tame — they abandon
  agriculture entirely, hunt, and butcher whatever is in the pen.
- **Wild things**: deer, bears, wolves and tigers in the forests; lions,
  giraffes and llamas on the savanna; frogs in the wetlands. Predators
  hunt prey — and occasionally people.
- **Diet is policy** (keys 1–4): Vegan (plants only), Omnivore, Carnivore
  (hunt the sheep), or **Cannibal** — corpses are butchered for the granary.
  Eating human flesh corrodes a villager's soul; the good refuse until
  starvation breaks them.
- **Three karma systems, kept separate**:
  - **Player alignment** (−100…+100): moved by your miracles, throws, and
    what you let happen. There is no bar: **your hand is the gauge**,
    shifting gold to blood-red — and **the sky itself is your
    conscience**, gilding warm for the saintly, bruising ash-and-blood
    for the monstrous. Converted village rings wear the same color.
  - **Creature morality**: independent. It drifts with what the creature
    *witnesses* you do — and with what you praise. A gentle creature tends
    the farm; a vicious one eats corpses; a monstrous one hunts your own
    villagers when hungry.
- **The creature observes, learns, and feels.** It has mood, boredom, and
  a bond with your hand. It *watches* villagers work and grows curious
  about their jobs; its desires (tending, hauling food to the granary,
  playing, guarding at night, mischief) are learned weights you shape by
  petting (P) or scolding (L) its last deed — praise cruelty and you are
  raising a monster. It plays with the sheep, dances for the children,
  spooks villagers when bored and mean, and sulks when told off. Hover it
  to read its heart; press C when you lose track of it.
  - **Villager morality**: shaped by diet, trauma witnessed, and worship.
    A virtuous flock prays with more conviction (more prayer power).
- **Belief** rises when villagers witness miracles — kindness or terror both
  work. It widens your **sphere of influence** and raises max prayer power.
- **Lightning is lethal** at the point of impact. The evil path is real.
- **Sheep** wander, breed slowly, get hunted, and are 100% throwable.

## Code map

```
scenes/main.tscn              Entry point (one node; world is built in code)
scripts/main.gd               Orchestrator: sky, day/night clock, wiring
scripts/game_state.gd         Autoload: prayer, alignment, game time
scripts/audio/sound_bank.gd   Autoload: all sounds, synthesized in code
scripts/util.gd               Primitive-shape building helpers
scripts/player/
  camera_rig.gd               God-game camera (pan/rotate/zoom)
  divine_hand.gd              THE hand: hover, grab, throw, drag, gestures
  gesture_recognizer.gd       Mouse-trail → gesture classification
  gesture_trail.gd            Glowing trail drawn while gesturing
scripts/world/
  world_gen.gd                Endless world: chunks, noise, biomes, villages
  chunk.gd                    One 48m tile: mesh, collision, water, scatter
  village.gd                  Belief/conversion, diet, housing, pen, jobs
  house.gd                    Dwellings: sizes, health, age, collapse
  edubba.gd                   The schoolhouse: gathers children, frees mothers
  wild_tree.gd                Harvestable trees (biome-styled)
  rock_deposit.gd             Harvestable stone
  farm.gd                     Crop growth, tending, rain bonus, harvest
  food_store.gd               Storehouse: plants, meat, lumber, stone
  food_item.gd                Physical food: grain sheaves & species-named meat
  corpse.gd                   The dead, as physical objects
scripts/animals/animal.gd     EVERY beast, one data table: livestock, pets,
                              predators, prey — taming, riding, guarding
scripts/villager/villager.gd  Full villager lives: needs, age, pregnancy,
                              morality, demand-driven jobs (state machine)
scripts/creature/creature.gd  The creature: feelings (mood/bond/boredom),
                              learned desires, pet/scold training, observation
scripts/miracles/
  miracle_manager.gd          Two-step menus, catalog, effects, power scaling
  miracle_orb.gd              Generic conjured-and-thrown miracle carrier
  fireball.gd                 The throwable fire miracle: ballistic, explosive
scripts/ui/hud.gd             Bars, legend, tooltips, help
scripts/ui/touch_controls.gd  Touchscreen-only buttons: Cast/Move mode,
                              follow-the-creature camera lock
```

### Architecture principles (read before adding systems)

1. **Systems first.** Every mechanic is a plain-code system with a narrow
   interface. No logic buried in editor-only scene configuration.
2. **Extend at the seams.** New miracles go in `MiracleManager.MIRACLES` +
   one `_cast_*` method. New villager behaviors go in the `Villager.State`
   machine + `_decide()`. New needs are one variable + one decay line + one
   action that satisfies them.
3. **Groups over hard references.** Systems find each other via node groups
   (`villagers`, `creature`, `food`, `farms`, `pickable`, `village`) so
   features stay decoupled.
4. **Everything tunable lives in `const`s at the top of its file.**

## Packing a demo build

Export presets for **Linux**, **Windows**, and **Web** are committed in
`export_presets.cfg`, and everything lands in `builds/` (git-ignored).

**One-time setup** (per machine): open the project in the editor, then
*Editor → Manage Export Templates → Download and Install*. Templates must
match the editor version exactly (4.7-stable).

Then either export from the editor (*Project → Export… → Export Project*),
or pack everything from the terminal:

```sh
./build.sh              # Linux + Windows + Web, zipped in builds/
./build.sh Web          # just one platform
GODOT=~/Apps/godot ./build.sh   # if godot isn't on your PATH
```

Notes:
- Desktop builds are **single-file** (the game data is embedded in the
  executable) — send the zip, they unzip and run. No installer.
- The Web build is exported **without threads**, so it runs from any
  static host — itch.io (upload `hand-of-heavens-demo-web.zip`, mark
  "played in browser"), GitHub Pages, or locally with
  `python -m http.server -d builds/web`. No special headers needed.
- The whole game is generated from code — no assets — so a demo zip is
  only as big as the engine runtime (~40 MB desktop, ~30 MB web).
- Cross-exporting Windows builds from Linux works out of the box; icons
  and code signing are left unset (fine for a demo).

### Android (.apk)

An **Android** preset is committed too (arm64, debug-signed — installable
on any phone, not store-ready). One-time setup on your machine:

1. **JDK 17** — e.g. `sudo apt install openjdk-17-jdk` (or your distro's
   equivalent; on an immutable distro, a toolbox/distrobox works fine).
   Find the path Godot wants with
   `java -XshowSettings:properties -version 2>&1 | grep java.home`.
   ⚠️ **Distrobox users**: a JDK installed in the box lives at
   `/usr/lib/jvm/...` *inside the container* — Godot can only use it if
   Godot also runs inside that box. If you run Godot on the host, use a
   tarball JDK in your home directory instead (both sides see `$HOME`):
   extract [Temurin 17](https://adoptium.net/temurin/releases/?version=17)
   to `~/Apps/jdk-17` and point Godot there. (`~/Android/Sdk` is in
   `$HOME` already, so the Android SDK has no such problem.)
2. **Android SDK** — easiest is [Android Studio](https://developer.android.com/studio)
   (installs the SDK to `~/Android/Sdk`); or the standalone
   `cmdline-tools` + `sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34"`,
   then `sdkmanager --licenses` to accept licenses.
3. **Debug keystore** — Android Studio creates `~/.android/debug.keystore`
   on first launch. Without Android Studio, make one yourself:
   ```sh
   keytool -keyalg RSA -genkeypair -alias androiddebugkey \
     -keypass android -keystore ~/.android/debug.keystore -storepass android \
     -dname "CN=Android Debug,O=Android,C=US" -validity 9999
   ```
4. **Point Godot at all three** — *Editor → Editor Settings → Export →
   Android*: set *Java SDK Path* (the JDK 17 folder), *Android SDK Path*
   (e.g. `~/Android/Sdk`), and *Debug Keystore*
   (`~/.android/debug.keystore`, user `androiddebugkey`, password `android`).
5. Export templates installed (same dialog as the desktop platforms).

Then:

```sh
./build.sh Android          # -> builds/hand-of-heavens-demo.apk
adb install builds/hand-of-heavens-demo.apk   # or copy to the phone and tap it
```

(Installing by tapping the file requires allowing "install unknown apps"
for your file manager — normal for any demo APK.)

**Touch controls** (appear automatically on touchscreens):

| Touch | Action |
|---|---|
| One finger | Everything the left mouse does — governed by the Mode button |
| **Mode** button | Toggle **Move** (drag land / pick / place / throw) ↔ **Cast** (one-finger gesture drawing) |
| **Creature** button | Camera locks to and follows your creature (pan to release) |
| Pinch | Zoom |
| Two-finger drag | Orbit the camera freely (yaw + tilt) |

The UI scales to the device (900-line logical height, width expands to
the phone's aspect). Not yet touchable: creature pet/scold and diet
policy — they still need P/L and 1–4 on a keyboard.

## Headless smoke test

CI-friendly check that the whole world boots, gestures classify, and all four
miracles cast without script errors:

```sh
godot --headless --path . -- --smoke-test
```

## Roadmap (after the PoC)

- ~~Villager lifecycle: age, death, children~~ ✔
- ~~Diet policies incl. cannibalism~~ ✔
- ~~Good/evil karma for player, creature, and villagers~~ ✔
- ~~Endless chunked terrain, biomes, elevation, water~~ ✔
- ~~Neutral villages + conversion~~ ✔
- ~~Jobs: builder/lumberjack/quarrier; housing with decay; homelessness~~ ✔
- ~~Day/night cycle (16 years per day)~~ ✔
- ~~Livestock, taming, riding, guard dogs, predators~~ ✔
- ~~Procedural sound~~ ✔
- ~~Creature learning (reward/punish via petting/scolding)~~ ✔ — next: direct control, leashes
- Festivals, music, dance, named relationships (lovers, parents, friends)
- **The opponent**: a rival god with its own villages, creature, and
  temperament (all systems are per-instance already to make this possible)
- Miracle progression: unlocks, upgrades, mutually exclusive paths
- Full controller support
- Real art and animation (someday; the sound is already ours)

## Team workflow

- `main` is always runnable. Work on feature branches
  (`feature/creature-learning`), merge via pull request.
- Scene files (`.tscn`) are text — but they merge badly. Avoid two people
  editing the same scene in the same sprint. (Building worlds in code, as we
  do now, largely sidesteps this.)
- Never commit the `.godot/` folder (already gitignored).
