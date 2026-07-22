# Custom models

Drop a model file here and it automatically replaces that thing's procedural
(primitive) version in-game. Delete it and the primitive version comes back.
Nothing here is required — the game ships and runs with this folder empty.

## Filenames the game looks for

| File (any extension below) | Replaces |
|---|---|
| `villager_female` / `villager_male` | a villager's body, by sex (falls back to `villager`) |
| `villager` | any villager, when no sex-specific model is present |
| `creature` | your creature |
| `tree` | any tree (or `tree_forest`, `tree_grassland`, `tree_savanna`, `tree_wetland` for per-biome art) |
| `bush` | a forage bush |
| `rock` | a rock deposit |
| `house` | a village house |
| `school` | the Edubba (schoolhouse) |
| `store` | the food store / granary |
| `hand` | the divine hand |
| `sheep`, `wolf`, `deer`, `horse`, `ox`, `pig`, `chicken`, `dog`, `llama`, `giraffe`, `bear`, `lion`, `tiger`, `frog` | that animal species |

Extensions checked, in order: `.glb` `.gltf` `.obj` `.scn` `.tscn` `.tres` `.res`
(`.glb` is the usual Blender export.)

## Rules so the framerate holds and everything lines up

- **One mesh, one material per model** — that's one draw call. This matters
  more than triangle count on mobile.
- **Triangle ceilings** (staying under these keeps the current framerate):
  villager 400 · animal 300 · creature 6000 · tree 150 · bush 400 · rock 350 ·
  house 300 · school 500 · store 1800 · hand 600.
- **Pivot at the feet** (model sits on Y=0), **+Z is forward** (the way it
  walks / the front of a building's door), scaled to roughly match the
  primitive it replaces so physics capsules and the throw arc still fit.
- **Avoid transparency** unless essential — alpha blending is the most
  expensive thing on a phone GPU.
- **Textures ≤ 512×512** (1024 for the creature); one atlas per model. Vertex
  colours are cheapest of all.

Distance-LOD culling, aftertouch spin, and the day/night lighting all apply to
your model automatically — no extra work.

## Animations (optional)

Rig your model and add an `AnimationPlayer` (a `.glb` exported from Blender
with actions gets one automatically). The game plays clips **by name** from
each entity's behaviour — you don't wire anything. Missing clips are ignored,
so a model with only `walk` + `idle` still works; a model with none animates
via the old procedural bob.

Name your clips (or a listed alias) to match these semantic states:

| Clip | Played when | Aliases accepted |
|---|---|---|
| `idle` | standing around | rest, stand |
| `walk` | moving | walking, move |
| `run` | fleeing / chasing / creature catching | sprint, gallop, flee → falls back to `walk` |
| `work` | farming, chopping, quarrying, building, fishing, teaching (villager); tending/fishing (creature) | chop, farm, build, dig, hammer |
| `eat` | eating | eating, feed |
| `sleep` | sleeping | rest |
| `carry` | creature hauling something | hold, haul |
| `fall` | thrown, mid-air | tumble, thrown, flail |
| `attack` | creature rampaging / kicking a house | kick, hit, smash |
| `play` | villager/creature playing | cheer, dance, jump |
| `pray` | worshipping / preaching | worship, kneel |
| `graze` | animal grazing | eat, feed |
| `drink` | animal drinking | graze, eat |
| `guard` | creature guarding | alert, watch |

Names match case-insensitively and tolerate Blender's rig prefixes
(`Armature|Walk`, `rig/walk`, etc.). Mark locomotion/idle/sleep clips as
**looping** in Blender (the game also forces a sensible loop mode as a
backstop). Keep rigs modest — **≤ ~30 bones** for villagers/animals — so a
crowd stays smooth on a phone; the creature (one instance) can be richer.

One-shot clips (`attack`, `play`, etc.) play once and then **settle back on
their own** — to `idle`/`walk` if the deed is done, or repeat if the entity
is still in that action (a creature mid-rampage keeps swinging). You don't
need a "return to idle" frame at the end of the clip.
