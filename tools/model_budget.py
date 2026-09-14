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

## Textures: the README asks for 512 (1024 for the creature).
TEXTURE_SIDE = {"creature": 1024}
TEXTURE_DEFAULT = 512

## HOW FAR A MODEL MAY SIT OFF ITS OWN ORIGIN before it is worth saying so.
##
## A pivot is not a style question here. Everything is planted by its origin and
## then SCALED by how grown it is — a tree by up to five — so a base 0.4m below
## zero is two metres of trunk underground on a full-grown one, and a trunk
## 0.3m off centre leans that much times five out of its own collision capsule.
## Four centimetres at rest is the most that can go unremarked.
PIVOT_SLACK = 0.04
## And what the game multiplies a tree by at full growth. WildTree's
## MATURE_SCALE, kept here so the in-game figures below are the real ones.
FULL_GROWTH = 5.0


def read_glb(path):
    """The JSON chunk of a .glb and its binary blob, or a .gltf read directly."""
    with open(path, "rb") as fh:
        head = fh.read(12)
        if head[:4] != b"glTF":
            fh.seek(0)
            return json.load(fh), b""
        length = struct.unpack("<I", head[8:12])[0]
        doc, blob = None, b""
        while fh.tell() < length:
            size, kind = struct.unpack("<I4s", fh.read(8))
            chunk = fh.read(size)
            if kind == b"JSON":
                doc = json.loads(chunk.decode("utf-8"))
            elif kind == b"BIN\x00":
                blob = chunk
        if doc is not None:
            return doc, blob
    raise ValueError("no JSON chunk in %s" % path)


## ---------------------------------------------------------------- geometry
##
## WHAT THE TRIANGLE COUNT WILL NOT TELL YOU. Two models can both be 150
## triangles and one of them sits on the ground while the other floats or sinks.
## The game scales every tree by its growth — up to five times — so a pivot that
## is 0.4m out at rest is two metres of trunk underground on a full-grown one,
## and a silhouette 30% short at rest is a wood that is 30% short everywhere.
##
## This walks the node tree accumulating transforms and takes the union of every
## mesh's declared min/max, which glTF stores on the POSITION accessor — so no
## vertex data has to be decoded to get an exact box.


def _matrix(node):
    if "matrix" in node:
        m = node["matrix"]                       # glTF matrices are column-major
        return [[m[0], m[4], m[8], m[12]], [m[1], m[5], m[9], m[13]],
                [m[2], m[6], m[10], m[14]], [m[3], m[7], m[11], m[15]]]
    t = node.get("translation", [0, 0, 0])
    sc = node.get("scale", [1, 1, 1])
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    rot = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
           [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
           [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    out = [[rot[r][c] * sc[c] for c in range(3)] + [t[r]] for r in range(3)]
    return out + [[0, 0, 0, 1]]


def _mul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)]
            for r in range(4)]


def _at(m, p):
    return [sum(m[r][c] * p[c] for c in range(3)) + m[r][3] for r in range(3)]


def bounds(doc):
    """(low, high) in the model's own space, or None if it has no geometry."""
    lo, hi = [1e30] * 3, [-1e30] * 3
    found = [False]

    def walk(idx, parent):
        node = doc["nodes"][idx]
        here = _mul(parent, _matrix(node))
        if "mesh" in node:
            for prim in doc["meshes"][node["mesh"]].get("primitives", []):
                acc = doc["accessors"][prim.get("attributes", {}).get("POSITION", -1)] \
                    if "POSITION" in prim.get("attributes", {}) else None
                if acc is None or "min" not in acc:
                    continue
                found[0] = True
                a, b = acc["min"], acc["max"]
                for cx in (a[0], b[0]):
                    for cy in (a[1], b[1]):
                        for cz in (a[2], b[2]):
                            p = _at(here, [cx, cy, cz])
                            for i in range(3):
                                lo[i] = min(lo[i], p[i])
                                hi[i] = max(hi[i], p[i])
        for kid in node.get("children", []):
            walk(kid, here)

    ident = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    for scene in doc.get("scenes", []):
        for root in scene.get("nodes", []):
            walk(root, ident)
    return (lo, hi) if found[0] else None


def image_sizes(doc, blob):
    """Every embedded image's pixel size, off the PNG/JPEG header alone."""
    out = []
    views = doc.get("bufferViews", [])
    for img in doc.get("images", []):
        if "bufferView" not in img:
            out.append(None)
            continue
        bv = views[img["bufferView"]]
        start = bv.get("byteOffset", 0)
        data = blob[start:start + bv.get("byteLength", 0)]
        if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
            out.append(struct.unpack(">II", data[16:24]))
        elif data[:2] == b"\xff\xd8":
            i = 2
            got = None
            while i + 9 < len(data):
                if data[i] != 0xFF:
                    i += 1
                    continue
                marker = data[i + 1]
                if marker in (0xC0, 0xC1, 0xC2):
                    got = struct.unpack(">HH", data[i + 5:i + 9])[::-1]
                    break
                i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
            out.append(got)
        else:
            out.append(None)
    return out


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
            doc, blob = read_glb(path)
            got = tally(doc)
            got["bounds"] = bounds(doc)
            got["images"] = image_sizes(doc, blob)
            out[stem] = got
        except (ValueError, KeyError, struct.error, json.JSONDecodeError,
                IndexError) as err:
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
        side = TEXTURE_SIDE.get(name, TEXTURE_DEFAULT)
        says = []
        if cap and m["tris"] > cap:
            says.append("%d over the ceiling" % (m["tris"] - cap))
        if m["draws"] > 1:
            says.append("%d draws an instance" % m["draws"])
        if name in ONE_MESH_REQUIRED and m["meshes"] > 1:
            says.append("MUST be one mesh — a herd draws only the first")
        if m["textures"] > 1:
            says.append("%d images; one atlas" % m["textures"])
        if m["bones"] > 30 and name != "creature":
            says.append("%d bones, over the ~30 a crowd affords" % m["bones"])
        box = m.get("bounds")
        if box is not None:
            lo, hi = box
            size = [hi[i] - lo[i] for i in range(3)]
            if abs(lo[1]) > PIVOT_SLACK:
                says.append("pivot %.2fm %s the origin — it will sit %.1fm %s "
                            "at full growth"
                            % (abs(lo[1]), "below" if lo[1] < 0 else "above",
                               abs(lo[1]) * FULL_GROWTH,
                               "buried" if lo[1] < 0 else "in the air"))
            lean = max(abs(lo[0] + hi[0]) / 2.0, abs(lo[2] + hi[2]) / 2.0)
            if lean > PIVOT_SLACK * 4.0:
                says.append("stands %.2fm off its own centre (%.1fm at full "
                            "growth, and the collider does not move)"
                            % (lean, lean * FULL_GROWTH))
        for wh in m.get("images", []):
            if wh is not None and max(wh) > side:
                says.append("texture %dx%d, over the %d asked for"
                            % (wh[0], wh[1], side))
        if says:
            over += 1
        print("%-18s %8s %7s %6d %5d %5d %6d  %s"
              % (name, "{:,}".format(m["tris"]), cap or "-", m["draws"],
                 m["materials"], m["textures"], m["bones"],
                 "; ".join(says) if says else "ok"))
        if box is not None:
            lo, hi = box
            size = [hi[i] - lo[i] for i in range(3)]
            print("%-18s   %.2fw x %.2fh x %.2fd at rest; %.1fm tall and %.1fm "
                  "across at full growth"
                  % ("", size[0], size[1], size[2], size[1] * FULL_GROWTH,
                     max(size[0], size[2]) * FULL_GROWTH))
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
    print("\nTHE PIVOT IS SCALED, which is why it is measured here rather than"
          "\n  left to the eye. A tree is multiplied by up to %.0f as it grows, so"
          "\n  every centimetre a model sits off its own origin at rest is %.0f of"
          "\n  them on a full-grown one — buried, floating, or leaning out of a"
          "\n  collision capsule that did not move with it."
          % (FULL_GROWTH, FULL_GROWTH))
    if "--check" in sys.argv:
        return 1 if over else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
