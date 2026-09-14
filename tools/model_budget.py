#!/usr/bin/env python3
"""WHAT YOUR BLENDER MODELS ACTUALLY COST, read straight out of the .glb.

tri_budget.py counts the PRIMITIVE FALLBACKS — the capsules and boxes the game
welds together when res://models/ has nothing for a thing. The moment you drop
a model in there the fallback stops running and every figure it reports for
that thing becomes fiction. This reads the real file.

It needs no Godot and no Blender. A .glb is a JSON chunk describing the scene
followed by a binary blob; the triangle count is in the JSON, in the accessors
each mesh primitive indexes. So this runs on your machine, against the models
that are on your machine, and says whether each one is inside the ceilings
models/README.md sets — and, more usefully, how many DRAW CALLS it will cost,
which on a phone matters more than its triangles.

WHY DRAW CALLS ARE THE NUMBER. A procedural villager is a capsule node plus a
sphere node: two meshes, two draws, 368 triangles. A hundred and eight of them
is 216 draws. The same villager as one mesh with one material is 108 draws for
the same crowd — and that, not the triangle count, is what a one-mesh export
buys you. A model exported as six objects with four materials costs SIX draws
an instance and is slower than the primitive it replaced, however good it looks.

Usage:
    python3 tools/model_budget.py                  read res://models/
    python3 tools/model_budget.py ~/art/export     read somewhere else
    python3 tools/model_budget.py --check          exit 1 on anything over
"""

import json
import os
import struct
import sys

# The ceilings models/README.md publishes, kept here so --check can enforce
# what the README promises. If they disagree, the README is the document a
# person reads and this is the one that stops a build: change both.
CEILING = {
    "villager": 400, "villager_male": 400, "villager_female": 400,
    "creature": 6000, "tree": 150, "tree_forest": 150, "tree_grassland": 150,
    "tree_savanna": 150, "tree_wetland": 150, "bush": 400, "rock": 350,
    "house": 300, "school": 500, "store": 1800, "hand": 600, "flower": 150,
    "nest": 800,
}
BEASTS = ("sheep wolf deer horse ox pig chicken dog llama giraffe bear lion "
          "tiger frog caribou reindeer bison elk anteater coati").split()
for _b in BEASTS:
    CEILING[_b] = 300

## A herd is ONE MultiMesh of ONE mesh, so a beast split across several meshes
## simply loses its other parts at herd range. For everything else a second
## mesh is a cost; for these it is a missing head.
ONE_MESH_REQUIRED = set(BEASTS) | {"flower"}

## Textures: the README asks for 512 (1024 for the creature). Stated in bytes
## of uncompressed RGBA8 so the figure is comparable with tools/gpu_budget.py.
TEXTURE_SIDE = {"creature": 1024}
TEXTURE_DEFAULT = 512


def read_glb(path):
    """The JSON chunk of a .glb, or of a .gltf read directly."""
    with open(path, "rb") as fh:
        head = fh.read(12)
        if head[:4] != b"glTF":
            fh.seek(0)
            return json.load(fh)
        length = struct.unpack("<I", head[8:12])[0]
        while fh.tell() < length:
            size, kind = struct.unpack("<I4s", fh.read(8))
            blob = fh.read(size)
            if kind == b"JSON":
                return json.loads(blob.decode("utf-8"))
    raise ValueError("no JSON chunk in %s" % path)


def tally(doc):
    """Triangles, meshes, materials, textures and bones, from the glTF JSON.

    A mesh's `primitives` are its draw-submissions: each has its own material,
    so a mesh with three primitives is three draws however it looks in Blender.
    That is the number this reports as `draws`, not the mesh count — an artist
    can merge six objects into one mesh and still ship six materials on it.
    """
    meshes = doc.get("meshes", [])
    accessors = doc.get("accessors", [])
    tris, draws, used_mats = 0, 0, set()
    for mesh in meshes:
        for prim in mesh.get("primitives", []):
            draws += 1
            if "material" in prim:
                used_mats.add(prim["material"])
            mode = prim.get("mode", 4)          # 4 = TRIANGLES
            if "indices" in prim:
                count = accessors[prim["indices"]].get("count", 0)
            else:
                pos = prim.get("attributes", {}).get("POSITION")
                count = accessors[pos].get("count", 0) if pos is not None else 0
            if mode == 4:
                tris += count // 3
            elif mode in (5, 6):                # strip, fan
                tris += max(count - 2, 0)
    bones = max((len(s.get("joints", [])) for s in doc.get("skins", [])),
                default=0)
    return dict(tris=tris, meshes=len(meshes), draws=draws,
                materials=len(used_mats), textures=len(doc.get("images", [])),
                bones=bones,
                clips=[a.get("name", "?") for a in doc.get("animations", [])])


def look(folder):
    exts = (".glb", ".gltf")
    out = {}
    if not os.path.isdir(folder):
        return out
    for name in sorted(os.listdir(folder)):
        stem, ext = os.path.splitext(name)
        if ext.lower() not in exts:
            continue
        path = os.path.join(folder, name)
        try:
            out[stem] = tally(read_glb(path))
        except (ValueError, KeyError, struct.error, json.JSONDecodeError) as err:
            out[stem] = dict(error=str(err))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    folder = args[0] if args else "models"
    found = look(folder)
    if not found:
        print("No .glb or .gltf in %s/." % folder)
        print("\nThis reads models where they LIVE. If yours are on your own"
              "\nmachine and not in the repo — which is the usual arrangement,"
              "\nsince a 30 MB export does not belong in git — run it there:"
              "\n    python3 tools/model_budget.py /path/to/your/models")
        return 0

    print("%-18s %8s %7s %6s %5s %5s %6s  %s"
          % ("MODEL", "TRIS", "CEILING", "DRAWS", "MATS", "TEX", "BONES",
             "VERDICT"))
    over = 0
    for name, m in found.items():
        if "error" in m:
            print("%-18s  unreadable: %s" % (name, m["error"]))
            over += 1
            continue
        cap = CEILING.get(name)
        says = []
        if cap and m["tris"] > cap:
            says.append("%d over the ceiling" % (m["tris"] - cap))
        if m["draws"] > 1:
            says.append("%d draws an instance" % m["draws"])
        if name in ONE_MESH_REQUIRED and m["meshes"] > 1:
            says.append("MUST be one mesh — a herd draws only the first")
        side = TEXTURE_SIDE.get(name, TEXTURE_DEFAULT)
        if m["textures"] > 1:
            says.append("%d images; one atlas" % m["textures"])
        if m["bones"] > 30 and name != "creature":
            says.append("%d bones, over the ~30 a crowd affords" % m["bones"])
        if says:
            over += 1
        print("%-18s %8s %7s %6d %5d %5d %6d  %s"
              % (name, "{:,}".format(m["tris"]), cap or "-", m["draws"],
                 m["materials"], m["textures"], m["bones"],
                 "; ".join(says) if says else "ok"))
        if m["clips"]:
            print("%-18s   clips: %s" % ("", ", ".join(m["clips"])))

    print("\nDRAWS is the number that decides the framerate on a phone, and it"
          "\n  is primitives-per-mesh summed, not meshes: one mesh carrying three"
          "\n  materials is still three submissions. One draw an instance is the"
          "\n  whole point of modelling these — it is what collapses a villager's"
          "\n  two nodes, an animal's six and the creature's eight into one each."
          "\n\nTRIS beside CEILING is models/README.md's published budget. Going"
          "\n  over is a decision, not a crime — but it should be one somebody"
          "\n  made on purpose, which is what this is for.")
    if "--check" in sys.argv:
        return 1 if over else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
