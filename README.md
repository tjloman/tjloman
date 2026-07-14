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
| Release while moving mouse | Throw what you're holding |
| **Hold right mouse + draw** | **Cast a miracle gesture** |
| Mouse wheel | Zoom |
| Middle mouse drag | Rotate / tilt camera |
| WASD / arrows | Pan camera |
| Q / E | Rotate camera |
| 1 / 2 / 3 / 4 | Village diet: Vegan / Omnivore / Carnivore / Cannibal |
| F1 | Help panel |

### Miracle gestures (hold right mouse)

| Gesture | Miracle | Prayer cost |
|---|---|---|
| Circle | Food falls from the sky | 20 |
| Zigzag (W shape) | Rain — crops grow 4× | 25 |
| Vertical stroke | Lightning — terror converts too | 30 |
| Horizontal stroke | Healing wave | 15 |

## The core loop (what's simulated)

- **Villagers live whole lives**: they age (1 game year = 20 real seconds),
  come of age at 16, slow down as elders, and die at 60–85 — leaving a
  physical **corpse**. Adults courting at the totem conceive children;
  pregnancy lasts nine months (game time), then a child is born, plays
  instead of working, and grows up.
- **Needs drive behavior**: hunger / energy / social choose between farming,
  hunting, eating, sleeping, worship, play, and fleeing. Starvation is
  lethal — and the god who allowed it is judged.
- **Diet is policy** (keys 1–4): Vegan (plants only), Omnivore, Carnivore
  (hunt the sheep), or **Cannibal** — corpses are butchered for the granary.
  Eating human flesh corrodes a villager's soul; the good refuse until
  starvation breaks them.
- **Three karma systems, kept separate**:
  - **Player alignment** (−100…+100): moved by your miracles, throws, and
    what you let happen. Your hand and the influence ring shift from gold
    to blood-red.
  - **Creature morality**: independent. It drifts with what the creature
    *witnesses* you do. A gentle creature tends the farm; a vicious one
    eats corpses; a monstrous one hunts your own villagers when hungry.
  - **Villager morality**: shaped by diet, trauma witnessed, and worship.
    A virtuous flock prays with more conviction (more prayer power).
- **Belief** rises when villagers witness miracles — kindness or terror both
  work. It widens your **sphere of influence** and raises max prayer power.
- **Lightning is lethal** at the point of impact. The evil path is real.
- **Sheep** wander, breed slowly, get hunted, and are 100% throwable.

## Code map

```
scenes/main.tscn              Entry point (one node; world is built in code)
scripts/main.gd               Orchestrator: terrain, environment, wiring
scripts/game_state.gd         Autoload: prayer power + announcements
scripts/util.gd               Primitive-shape building helpers
scripts/player/
  camera_rig.gd               God-game camera (pan/rotate/zoom)
  divine_hand.gd              THE hand: hover, grab, throw, drag, gestures
  gesture_recognizer.gd       Mouse-trail → gesture classification
  gesture_trail.gd            Glowing trail drawn while gesturing
scripts/world/
  village.gd                  Belief, influence, diet policy, houses, births
  farm.gd                     Crop growth, tending, rain bonus, harvest
  food_store.gd               Granary: separate plant/meat stocks
  food_item.gd                Physical food (plant, mutton, ...other)
  sheep.gd                    Fauna: wandering, breeding, throwable meat
  corpse.gd                   The dead, as physical objects
scripts/villager/villager.gd  Full villager lives: needs, age, pregnancy,
                              morality, hunting, butchering (state machine)
scripts/creature/creature.gd  Creature needs + INDEPENDENT morality/behavior
scripts/miracles/
  miracle_manager.gd          Miracle catalog: costs, effects, gesture map
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
- Creature learning (reward/punish via petting/slapping), direct control
- Villager routines v2: jobs, festivals, music, dance, named relationships
  (lovers, parents/children as tracked bonds)
- Procedural endless terrain (chunked), multiple villages
- **The opponent**: a rival god with its own villages, creature, and
  temperament (village/creature/karma systems are already per-instance to
  make this possible)
- Miracle progression: unlocks, upgrades, mutually exclusive paths
- Full controller support
- Actual art, animation, and sound (someday)

## Team workflow

- `main` is always runnable. Work on feature branches
  (`feature/creature-learning`), merge via pull request.
- Scene files (`.tscn`) are text — but they merge badly. Avoid two people
  editing the same scene in the same sprint. (Building worlds in code, as we
  do now, largely sidesteps this.)
- Never commit the `.godot/` folder (already gitignored).
