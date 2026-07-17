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
| Left mouse on things | Pick up food / rocks / villagers |
| Release while moving mouse | Throw — your hand's momentum carries; flick hard to hurl far |
| **Hold right mouse + draw** | **Cast a miracle gesture** |
| Mouse wheel | Zoom |
| Middle mouse drag | Rotate / tilt camera (tilts above the horizon for skyward throws) |
| WASD / arrows | Pan camera |
| Q / E | Rotate camera |
| 1 / 2 / 3 / 4 | Village diet: Vegan / Omnivore / Carnivore / Cannibal |
| P / L (hand near creature) | **Pet** (reward) / **scold** (discourage) its last deed |
| C | Jump the camera to your creature |
| F1 | Help panel |

### Miracle gestures (hold right mouse)

| Gesture | Miracle | Prayer cost |
|---|---|---|
| Circle | Food falls from the sky | 20 |
| Zigzag (W shape) | Rain — crops grow 4× | 25 |
| Vertical stroke | Lightning — terror converts too | 30 |
| Horizontal stroke | Healing wave | 15 |
| Diagonal slash | **Fireball** — conjured into your hand; throw it. Explodes on impact, converts where it lands | 25 |

## The world

- **Endless, chunked terrain**: 48m chunks stream in around the camera.
  Elevation from layered noise, lakes below the water table, and five
  biomes — grassland, forest, savanna, rocky hills, wetland — each with
  its own colors, trees, and wildlife. Everything is deterministic from
  the world seed.
- **Neutral villages** generate out in the world. They run the full
  simulation (farming, building, families) but believe in nothing until
  your miracles convert them (belief ≥ 40) — then their prayers feed you.
- **Day/night cycle**: one full cycle per 16 villager years (~5⅓ real
  minutes). Sun, moon, dawn/dusk skies. Villagers sleep at night; house
  windows glow; wolves prowl — preferring villages gone wicked.
- **Sound**: every sound is synthesized in code at startup (no assets) and
  played positionally — bleating, clucking, sawing, quarry picks, hammers,
  worship murmur, barks, howls, frog croaks, and the boom of a fireball.
- **Rendering**: the Mobile renderer + MSAA. Good and plain — meant to look
  right on a phone, no advanced GPU required (yet).

## The core loop (what's simulated)

- **Villagers live whole lives**: they age (1 game year = 20 real seconds),
  come of age at 16, slow down as elders, and die at 60–85 — leaving a
  physical **corpse**. Adults courting at the totem conceive children;
  pregnancy lasts nine months (game time), then a child is born, plays
  instead of working, and grows up.
- **Jobs are chosen, not assigned**: every adult scores what the village
  lacks — food, lumber, stone, housing, repairs, livestock — and takes the
  most urgent work: farming, hunting, felling timber, quarrying, building,
  taming. Starvation is lethal — and the god who allowed it is judged.
- **Houses are mortal too**: hut / house / longhouse (sleeps 2/4/6), each
  with health and age. They decay past 30 years and collapse; builders
  raise new ones (lumber + stone, placement checked for slope, water, and
  clearance) and repair old ones. The homeless sleep rough by the totem,
  recover poorly, and grow miserable. One diligent builder can house a
  whole town — if the loggers and quarriers keep up.
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
    what you let happen. Your hand and the influence ring shift from gold
    to blood-red.
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
  miracle_manager.gd          Miracle catalog: costs, effects, gesture map
  fireball.gd                 The throwable miracle: ballistic, explosive
scripts/ui/hud.gd             Bars, legend, tooltips, help
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
