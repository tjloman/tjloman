# Custom models

Drop a model file here and it automatically replaces that thing's procedural
(primitive) version in-game. Delete it and the primitive version comes back.
Nothing here is required — the game ships and runs with this folder empty.

## Filenames the game looks for

| File (any extension below) | Replaces |
|---|---|
| `villager` | a villager's body |
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
