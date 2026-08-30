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

### Validating changes without running the game

```
gdparse scripts/**/*.gd          # syntax
gdlint scripts/                  # style
python3 tools/check_calls.py     # calls to methods that DON'T EXIST
```

That last one matters: `gdparse` only checks syntax and `gdlint` only checks
style, so a call like `(v as Villager).hurt_by(...)` to a method that was never
written passes both and then crashes the moment that code path runs.
`check_calls.py` resolves `ClassName.foo()` and `(x as ClassName).foo()` against
what each `class_name` script actually declares (following `extends`), and fails
the build if a member is missing.

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
| G | **Lead your creature** to where your hand points — it goes there and waits (G again releases) |
| C | **Lock** the camera onto your creature — centered, orbitable; C again (or pan) releases |
| V | **Villages roster** — list your faithful villages (population, distance) and **snap the camera** to any of them |
| F1 | Help panel |
| F3 | **Workshop** — save, load, regenerate the world, new game, and a few test cheats |

### Miracles — two gestures, then throw (hold right mouse)

Casting is two steps. First draw a **menu opener**; then draw a **selector**
inside it. The miracle is conjured as a glowing **orb into your hand** —
**throw or place it**, and it unleashes wherever it lands. (Selectors are
namespaced per menu, so the same simple shape means different things in
different menus.)

| Menu (opener) | Selector → Miracle | Cost |
|---|---|---|
| **Spiral** — Nature | Circle → Food · Vertical → Forest seed (13 trees) · Horizontal → Forage thicket · Diagonal → Rain · Wave → **Strength** | 20 / 45 / 30 / 25 / 35 |
| **Reverse-spiral** — Wrath | Vertical → Lightning · Circle → Lightning **storm** · Diagonal → Fireball · Horizontal → **Tornado** | 30 / 90 / 25 / 110 |
| **Wave** — Sky | Horizontal → Heal · Circle → **Bird flock** · Vertical → **Flight** (your creature soars) · Diagonal → **Portal** | 15 / 40 / 55 / 70 |

**Your dominion is your spellbook.** Miracles are **unlocked by villages** —
each village that comes to believe teaches you the next set of wonders. Once
known, a miracle is paid for with the **pooled prayer of every town you hold**.

| Villages | Unlocks |
|---|---|
| 1 | Food · Heal · Rain |
| 2 | Forest seed · Forage thicket · Lightning · **Strength** |
| 3 | Fireball · Bird flock · **Flight** |
| 4 | **Portal** · Lightning storm · Tornado |

**Portals** are cast in **pairs**: the first gate hangs open and waiting, the
second links to it — and from then on villagers, livestock, your creature and
anything you throw can step through and cross the world. Casting a third
begins a fresh pair. **Flight** lifts your creature into the air, where it
soars over water, wood and hill alike — the sane way to keep it beside you on
a map this size.

The mightiest miracles also need a **wide reservoir of prayer** — each
converted village raises your cap (+120) and widens the fury of storms and
flocks. Everything you conjure is a throwable you place where you choose.

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
  giants — the model scales with maturity. **Woods do not swallow the map**:
  growth is a lottery (a tree only *might* thicken on any given tick), only a
  **fully grown** tree drops seed, and crowding cuts both the growing and the
  seeding odds — so a stand thins at its own edges and creeps instead of
  marching. Rock deposits hold 300 stone and visibly wear down.
- **Sound**: every sound is synthesized in code at startup (no assets) and
  played positionally — bleating, clucking, sawing, quarry picks, hammers,
  worship murmur, barks, howls, frog croaks, and the boom of a fireball.
- **Rendering**: the Mobile renderer + MSAA. Good and plain — meant to look
  right on a phone, no advanced GPU required (yet).

## What your creature BELIEVES

Its learned action-values answer *"is this worth doing?"*. Its **beliefs**
answer the far more interesting question — ***"worth doing when?"*** — and this
is what makes one creature genuinely a different person from another.

- **Episodes.** Every deed is remembered with the **circumstances** around it.
  Not "I ate a villager" but "I was starving, in their village, at night, with
  armed men about, and my god was nowhere near."
- **Credit.** Consequences arrive *late*. When a mob drives it off, or its god
  praises it, or it is wounded, the blame is spread back over the deeds that
  led up to it. **Nothing tells it that being chased comes from eating people**
  — it works that out because being chased keeps following having eaten one.
- **Contextual weights.** Each action carries a small learned model over the
  circumstances, so the lesson attaches to the *situation*, not the deed alone.

The result is that the **same act teaches opposite lessons** depending on what
actually follows it:

| What happens after it eats a villager | What it comes to believe |
|---|---|
| The village mobs it | Recoils from crowds — but will still take a **lone** shepherd |
| You kill the mob and praise it | **Unrepentant.** It learns to stand its ground |
| The villagers flee and hide | Terror **works**. A tyrant is born |

**Villages learn too.** They do not only fight back. A village that stands and
wins grows **resolve**; one that buries its dead **loses its nerve and hides
indoors instead** — so one settlement becomes a militia and its neighbour a
people who bar their doors, out of their own history rather than any rule. And
a village that hides is the very thing that teaches your creature that terror
pays.

Lock onto your creature (**C**) and the dashboard tells you what it currently
believes, in plain words.

## Your creature's body

It does not simply eat and grow. It has a **real stomach** whose size follows
its own: a chicken half-fills a hatchling, and a hatchling **cannot finish a
cow** — it swallows what fits and leaves the rest. Food then **digests over
time** (about 45 seconds for a hatchling's bellyful, ~100 for a grown beast's),
and where it goes depends on whether the body wanted it:

- **hungry** → nourishment, and a little growth
- **not hungry** → **fat**

Fat makes it slow, heavy and disinclined to exert itself — and a lazy creature
only gets fatter, because work is what burns it off. **Muscle** is the mirror
image: it comes from *exertion* (hauling, smashing, running), decays when
unused, and decides **what it can lift**. A hatchling wrestles saplings; only a
grown, well-worked beast can uproot a forest giant. The **Strength** miracle
(NATURE, `~`) lends it a giant's grip for a while, enough to carry trees far
beyond its own muscle — a loan against strength it hasn't earned.

Watch all of it in the creature dashboard (lock on with **C**): belly fullness,
whether it's digesting, and whether it's *lean*, *sturdy*, *powerful*, *fat*
or *obese*.

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
  taming. Choices are **pooled and spread** — a job the flock is already
  crowding onto is discouraged, so villagers fan out across the village's
  needs instead of conga-lining to one resource. Starvation is lethal —
  and the god who allowed it is judged.
- **Villages grow where you tend them**: a village left alone barely
  multiplies — conception is slow by default. **Divine attention** quickens a
  people: miracles cast over them, your hand setting someone down among them,
  your creature working in their fields. Attention fades over a minute or so,
  so a kingdom expands where you actually *spend time*, not everywhere at
  once. Hover a village to read whether it is thriving or merely quiet.
- **The militia — villagers fight back**: predators no longer farm defenceless
  people. When one villager is hurt, the whole village is ROUSED: the able
  arm themselves at the storehouse (club · spear · bow · sword, paid for in
  lumber and stone — they make the best they can afford) and go for the
  threat. Courage comes from NUMBERS: a villager caught **alone** will not
  stand — they run, and a wolf usually runs them down. Two or three together
  turn and kill it. If a villager **dies**, the village swears a blood debt
  against that specific beast and hunts it wherever it goes, and clears any
  predator inside its bounds. Hurt (or eat) their people with your creature
  and their **grudge** grows — push it far enough and they will take up arms
  against your creature too, wounding it and driving it off. A creature hurt
  this way learns to fear them.
- **Nothing teleports**: a gathered catch, harvest, timber, or stone must be
  **carried home on foot** to the storehouse (you can see the load in their
  hands) before it counts. A load abandoned in fright is dropped and lost.
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

## Saving, and the workshop (F3)

The land is **never written down**. Every hill, shore, forest and town site
grows back exactly from the world's **seed**, so a save holds only what *play*
has changed: your standing with the heavens and the clock, each village's
name, faith, diet, stocks, hard-won doctrine and full roster of people, and —
the part no seed could ever reproduce — your creature's whole **mind, beliefs
and body**.

Loading works by handing the next scene a parcel and rebuilding around it,
so there is never a half-torn-down world. Because the world **streams**, a
town forty chunks away does not exist at load time; its saved life waits in
memory and is handed back **the moment that village is born**, whenever you
wander into it. A town you never revisit keeps its memory — and is written
out again on the next save, unchanged.

That parcel is what makes the workshop's two levers possible:

- **New land, same creature** — a fresh seed, a stranger's world, but your
  creature walks into it carrying every habit, belief, appetite, pound of fat
  and lesson it ever earned. The perfect way to see what a mind you have
  actually raised.
- **New game** — a new seed and a newborn creature, remembering nothing.

Both ask twice before they fire, and the arming lapses after a few seconds.
The workshop also holds test cheats: prayer, instant growth, instant
conversion, and a printout of what the creature currently believes.

## The quiet life, and how you shape it

Most of what a creature does is neither kind nor cruel, and a creature offered
only saintly and monstrous options will pick one and become it. So the ballot
is mostly ordinary: it can **lounge** in the grass watching the world go by,
**run** for the joy of running (with a tree on its back, which is how muscle is
actually earned), **dance**, **lead the village's prayers**, or simply **stand
among the people and be looked at** — which wins belief without a drop of blood,
and is a complete non-violent road to unlocking miracles.

It cannot dance or pray until it has **watched someone** dance or pray. A
village that celebrates and worships raises a creature with a wider life than a
grim one does.

**Drives pull on traits, never on verbs.** The body knows only broad needs —
hunger, tiredness, boredom, loneliness, fear — and boredom asks for
*stimulation* without any opinion on whether that turns out to be dancing,
sprinting, showing off or flattening a house; those score identically until
experience separates them. Adding a verb means describing what it is *like*,
not writing a rule about when to do it. The single most important consequence:
nothing in the design gives violence a head start, and a creature with an
appetite for people learned it from a tie.

### Ritual

The belief engine remembers **order**, not just deeds. Every time one act
follows another and things go well, that *pairing* firms up a little — so a
creature that has found fishing-then-miracles rewarding will start fishing
first, and reach for a miracle after fishing rather than cold.

Nothing decides which sequences are meaningful. The creature simply notices
that when it does these two things in this order the day tends to go well, and
it is very often wrong about why — which is exactly what a ritual is. A habit
of order reaches the point of steering a choice after two or three repeats and
firms up to about +0.9 by a dozen; that is enough to tilt a decision and never
enough to railroad one. Rituals also fade if life stops confirming them, so a
creature can outgrow one.

This is also what keeps a life from flattening into whichever single deed
scores highest. The order matters, so the days take on a shape the creature
invented for itself — and it is a shape you can read in the workshop panel:
*"likes to fish before it casts bird_flock"*.

### Trust, and being watched

**Trust** is kept apart from bond on purpose — bond is attachment, trust is
whether your judgement is worth anything. A creature can be desperately
attached to a god it has learned to flinch from.

Praise, gifts and healing earn trust. Hurting it with your own miracles spends
it fast. So does **scolding it for something that was not cruel** — it knows
the difference between a correction and a god being unfair, and an unjust
telling-off costs you roughly fourteen times what a deserved one does.

Trust is the valve on your whole influence:

- **It copies you.** Every act of your hand near it is a lesson — what you lift,
  what you set down gently, what you hurl, who you mend — landing on the very
  same learned values it uses to choose its own deeds. There is deliberately no
  list of deeds worth copying; whatever you do is what you are teaching.
- **Below ~35 trust it stops copying you** and takes its cues elsewhere.
- **Below ~20 it keeps its distance**, sulking and shunning your hand.
- **A creature that has grown kinder than you may leave.** Low trust plus a
  temperament better than your own puts *walking away* on the ballot: it turns
  its back and goes to live by its own lights somewhere you are not.

**Exile is a condition, not an ending.** It lives out there, keeps its
distance, and will not come when called — the one command it refuses. It is
always recoverable, but it cannot be bought: coming home needs **both** trust
regained **and** a long stretch with no repeat of the thing it left over. It
remembers what you did, and every fresh offence puts the reckoning back to the
beginning. A god who pets the creature between beatings never gets it back.

## Code map

```
scenes/main.tscn              Entry point (one node; world is built in code)
scripts/main.gd               Orchestrator: sky, day/night clock, wiring
scripts/game_state.gd         Autoload: prayer, alignment, game time
scripts/save_game.gd          Autoload: seed-based saves, and the F3 levers
scripts/audio/sound_bank.gd   Autoload: all sounds, synthesized in code
scripts/util.gd               Primitive-shape building helpers
scripts/nav_field.gd          Autoload: periodic obstacle field for steering
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
scripts/creature/
  creature.gd                 The creature itself: feelings, states, deeds,
                              pet/scold training — it coordinates the modules
  creature_mind.gd            The learning brain: action values, curiosity,
                              conscience, satiation, emergent character
  creature_beliefs.gd         Episodes, credit assignment, contextual weights —
                              what it believes, and in WHICH circumstances
  creature_body.gd            Stomach, digestion, fat and muscle
  creature_eyes.gd            Perception only: what is the nearest X
  creature_look.gd            Alignment colour, expressions, blend shapes
scripts/miracles/
  miracle_manager.gd          Two-step menus, catalog, effects, power scaling
  miracle_orb.gd              Generic conjured-and-thrown miracle carrier
  fireball.gd                 The throwable fire miracle: ballistic, explosive
scripts/ui/hud.gd             Bars, legend, tooltips, help
scripts/ui/debug_menu.gd      The F3 workshop: save/load/regenerate + cheats
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
