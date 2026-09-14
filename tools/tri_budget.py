#!/usr/bin/env python3
"""EVERY MODEL IN THE GAME, AND WHAT IT COSTS IN TRIANGLES.

Nothing here is modelled in Blender. Every body, building, tool and miracle is
assembled at runtime out of Godot's primitive meshes, which means the triangle
budget of this game is not in an asset folder anybody can inspect — it is
spread across eighty-odd builder functions, and the only way anyone has ever
known what a sheep costs is by guessing.

So this counts them. It reads the shipped source, finds every primitive that is
ever built, resolves the tessellation actually asked for, multiplies by the
loops around it, and adds the parts up per model.

THE FORMULAS ARE GODOT'S, not estimates. Every one below was read off
scene/resources/3d/primitive_meshes.cpp, and each cites the loop it came from.
A primitive generator emits two triangles per (i>0 && j>0) cell of an i x j
sweep; the whole job is knowing what i and j are for each shape.

    Sphere      2 * radial * (rings+1)            one sweep
    Capsule     6 * radial * (rings+1)            three sweeps: cap, barrel, cap
    Cylinder    2 * radial * (rings+1) + a fan per capped end with a radius
    Box         4 * [(w+1)(h+1) + (d+1)(h+1) + (w+1)(d+1)]   both faces per sweep
    Prism       (w+1)(2+4h) + 4(d+1)(h+1) + 2(w+1)(d+1)      the tip row halves
    Torus       2 * rings * ring_segments
    Plane/Quad  2 * (w+1) * (d+1)

The defaults matter more than anything the game sets, because a default is what
you get when nobody thought about it: a bare SphereMesh is 64x32 = 4,224
triangles, which is how a shower of 400 raindrops once cost 1.7 million (see
Util.speck_mesh). The one number in this file that is corroborated by something
other than arithmetic is that one — 4,224 is the figure in Util.sphere's note,
arrived at independently and years apart.

WHAT THIS IS NOT: a frame capture. It counts the geometry of one of a thing,
as built. It does not know how many are on screen, and it does not know what
the GPU actually retires after culling. For the second question see
tools/gpu_budget.py; for how many, see the INSTANCES column, which is read off
the caps the game enforces rather than off any particular save.

Usage:
    python3 tools/tri_budget.py            the chart
    python3 tools/tri_budget.py --check    exit 1 if anything is unresolved,
                                           or a model breaks its budget
    python3 tools/tri_budget.py --json     machine-readable, for the artifact
"""

import json
import os
import re
import sys

SRC = "scripts"


# ---------------------------------------------------------------- the formulas


def sphere_tris(radial=64, rings=32):
    """SphereMesh: one j-sweep of rings+1 bands, i-sweep of radial. 2/cell."""
    return 2 * radial * (rings + 1)


def capsule_tris(radial=64, rings=8):
    """CapsuleMesh: THREE identical sweeps — top cap, barrel, bottom cap — and
    the barrel is subdivided by `rings` too, which is the part people miss."""
    return 3 * 2 * radial * (rings + 1)


def cylinder_tris(radial=64, rings=4, top_r=1.0, bottom_r=1.0):
    """CylinderMesh: the side, plus a triangle fan for each end that is capped
    AND has a radius above zero — which is why a cone is cheaper than a tube."""
    tris = 2 * radial * (rings + 1)
    if top_r > 0.0:
        tris += radial
    if bottom_r > 0.0:
        tris += radial
    return tris


def box_tris(sw=0, sh=0, sd=0):
    """BoxMesh: three sweeps, each emitting BOTH opposing faces — 4 triangles
    per cell, not 2."""
    return 4 * ((sw + 1) * (sh + 1) + (sd + 1) * (sh + 1) + (sw + 1) * (sd + 1))


def prism_tris(sw=0, sh=0, sd=0):
    """PrismMesh: the front/back sweep's first row is the tip, and emits one
    triangle a cell instead of two. Everything else is a box's arithmetic."""
    return (sw + 1) * (2 + 4 * sh) + 4 * (sd + 1) * (sh + 1) + 2 * (sw + 1) * (sd + 1)


def torus_tris(rings=64, ring_segments=32):
    """TorusMesh: rings around the hole, ring_segments around the tube."""
    return 2 * rings * ring_segments


def plane_tris(sw=0, sd=0):
    """PlaneMesh, and QuadMesh which is a PlaneMesh stood up."""
    return 2 * (sw + 1) * (sd + 1)


DEFAULTS = {
    "SphereMesh": dict(radial_segments=64, rings=32),
    "CapsuleMesh": dict(radial_segments=64, rings=8),
    "CylinderMesh": dict(radial_segments=64, rings=4, top_radius=1.0, bottom_radius=1.0),
    "BoxMesh": dict(subdivide_w=0, subdivide_h=0, subdivide_d=0),
    "PrismMesh": dict(subdivide_w=0, subdivide_h=0, subdivide_d=0),
    "TorusMesh": dict(rings=64, ring_segments=32),
    "PlaneMesh": dict(subdivide_w=0, subdivide_d=0),
    "QuadMesh": dict(subdivide_w=0, subdivide_d=0),
}


def raw_tris(kind, props):
    p = dict(DEFAULTS[kind])
    p.update(props)
    if kind == "SphereMesh":
        return sphere_tris(p["radial_segments"], p["rings"])
    if kind == "CapsuleMesh":
        return capsule_tris(p["radial_segments"], p["rings"])
    if kind == "CylinderMesh":
        return cylinder_tris(
            p["radial_segments"], p["rings"], p["top_radius"], p["bottom_radius"])
    if kind == "BoxMesh":
        return box_tris(p["subdivide_w"], p["subdivide_h"], p["subdivide_d"])
    if kind == "PrismMesh":
        return prism_tris(p["subdivide_w"], p["subdivide_h"], p["subdivide_d"])
    if kind == "TorusMesh":
        return torus_tris(p["rings"], p["ring_segments"])
    return plane_tris(p["subdivide_w"], p.get("subdivide_d", 0))


# -------------------------------------------------- what Util's helpers build
#
# These mirror scripts/util.gd exactly. When a helper's tessellation changes
# there, it must change here, and check_calls' rule keeps the two in step.


def util_tris(helper, args):
    """Triangles for one Util.<helper>(...) call, given its argument texts."""

    def arg(i, default):
        if i < len(args) and args[i] != "":
            return args[i]
        return default

    if helper in ("box", "lite_box"):
        return box_tris()
    if helper == "prism":
        return prism_tris()
    if helper == "sphere":
        return sphere_tris(16, 8)
    if helper == "capsule":
        return capsule_tris(16, 4)
    if helper == "cylinder":
        return cylinder_tris(12, 0)
    if helper == "lite_sphere":
        segs = as_int(arg(3, "8"), 8)
        return sphere_tris(segs, max(int(segs / 2), 3))
    if helper == "lite_capsule":
        segs = as_int(arg(4, "12"), 12)
        return capsule_tris(segs, max(int(segs / 4), 2))
    if helper == "lite_cylinder":
        top = as_float(arg(4, "-1.0"), -1.0)
        segs = as_int(arg(5, "8"), 8)
        # top < 0 means "same as the bottom"; top == 0 is a cone, and a cone
        # has no top fan to pay for.
        return cylinder_tris(segs, 0, 1.0 if top < 0.0 else top, 1.0)
    if helper == "small_flame":
        # Three emissive cones, hard-coded: lite_cylinder(..., 0.0, 6, true).
        return 3 * cylinder_tris(6, 0, 0.0, 1.0)
    if helper in ("speck_mesh", "flame_mesh", "dot_mesh", "dot_node"):
        return plane_tris()
    if helper == "blossom_mesh":
        return 4            # two crossed quads, built by hand in SurfaceTool
    if helper == "status_label":
        return 0            # a Label3D: text, not model geometry
    # The pooled builders, reached directly where a MultiMesh needs the raw
    # mesh rather than a node.
    if helper == "_pooled_box_mesh":
        return box_tris()
    if helper == "_pooled_sphere_mesh":
        segs = as_int(arg(1, "8"), 8)
        return sphere_tris(segs, max(int(segs / 2), 3))
    if helper == "_pooled_capsule_mesh":
        segs = as_int(arg(2, "12"), 12)
        return capsule_tris(segs, max(int(segs / 4), 2))
    if helper == "_pooled_cylinder_mesh":
        segs = as_int(arg(3, "8"), 8)
        return cylinder_tris(segs, 0, as_float(arg(0, "1.0"), 1.0), 1.0)
    raise KeyError(helper)


UTIL_HELPERS = (
    "box sphere capsule cylinder prism lite_box lite_sphere lite_capsule "
    "lite_cylinder small_flame speck_mesh flame_mesh blossom_mesh status_label "
    "dot_mesh dot_node "
    "_pooled_box_mesh _pooled_sphere_mesh _pooled_capsule_mesh _pooled_cylinder_mesh"
).split()


def as_int(text, fallback):
    try:
        return int(float(text))
    except ValueError:
        return fallback


def as_float(text, fallback):
    try:
        return float(text)
    except ValueError:
        return fallback


# ------------------------------------------------------------- reading source


def split_args(text):
    """Top-level comma split, so Vector3(1, 0, 1) counts as one argument."""
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    out.append(cur.strip())
    return out


def call_args(line, start):
    """The argument text of a call whose '(' is at or after `start`."""
    i = line.index("(", start)
    depth, j = 0, i
    while j < len(line):
        if line[j] == "(":
            depth += 1
        elif line[j] == ")":
            depth -= 1
            if depth == 0:
                return split_args(line[i + 1:j])
        j += 1
    return split_args(line[i + 1:])


def logical_lines(path):
    """(line number, indent, joined text) — continuations folded onto the line
    they started on, so a call split over four lines is read as one call and
    still reported where a person will find it."""
    out = []
    held, start, indent, depth = "", 0, 0, 0
    for n, raw in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        code = raw.split("#", 1)[0].rstrip()
        if code.strip() == "":
            continue
        if held == "":
            start = n
            indent = len(code) - len(code.lstrip("\t"))
        cont = code.endswith("\\")
        body = code[:-1] if cont else code
        held += body.strip() + " "
        depth += body.count("(") + body.count("[") + body.count("{")
        depth -= body.count(")") + body.count("]") + body.count("}")
        if cont or depth > 0:
            continue
        out.append((start, indent, held.strip()))
        held, depth = "", 0
    return out


LOOP = re.compile(r"^for\s+\w+(?:\s*:\s*[\w.\[\]]+)?\s+in\s+(.+?):\s*$")


def loop_count(expr, consts):
    """How many times a `for` body runs, when that is knowable from the text."""
    expr = expr.strip()
    if re.fullmatch(r"\d+", expr):
        return int(expr)
    m = re.fullmatch(r"range\(\s*(\d+)\s*\)", expr)
    if m:
        return int(m.group(1))
    m = re.fullmatch(r"range\(\s*(\d+)\s*,\s*(\d+)\s*\)", expr)
    if m:
        return max(int(m.group(2)) - int(m.group(1)), 0)
    if expr.startswith("[") and expr.endswith("]"):
        inner = expr[1:-1].strip()
        return 0 if inner == "" else len(split_args(inner))
    if expr in consts:
        return consts[expr]
    return None


CONST_INT = re.compile(r"^const (\w+)\s*(?::\s*int\s*)?:?=\s*(\d+)\s*$")
CONST_ARR = re.compile(r"^const (\w+).*:?=\s*\[(.*)\]\s*$")
MESH_NEW = re.compile(r"\b(\w+Mesh)\.new\(\)")
UTIL_CALL = re.compile(r"\bUtil\.(%s)\(" % "|".join(UTIL_HELPERS))
NUM = re.compile(r"^-?\d+(?:\.\d+)?$")


## THE SHAPES WHOSE DEFAULTS ARE EXPENSIVE. A BoxMesh, PrismMesh or PlaneMesh
## left alone is 12, 8 and 2 triangles — the defaults ARE the right answer and
## setting them would be noise. These four are not: stock they are 64 segments
## round, which is a decision this game makes nowhere else, so leaving them
## alone is always an oversight rather than a choice.
ROUND = ("SphereMesh", "CapsuleMesh", "CylinderMesh", "TorusMesh")
TESS = ("radial_segments", "rings", "ring_segments")


def scan(path):
    """Every mesh built in this file."""
    lines = logical_lines(path)
    consts = {}
    for _, _, text in lines:
        m = CONST_INT.match(text)
        if m:
            consts[m.group(1)] = int(m.group(2))
            continue
        m = CONST_ARR.match(text)
        if m and m.group(2).strip():
            consts[m.group(1)] = len(split_args(m.group(2)))
    # Property writes, so `var t := TorusMesh.new()` picks up `t.rings = 48`.
    props = {}
    for _, _, text in lines:
        m = re.match(r"^(\w+)\.(\w+)\s*=\s*(.+)$", text)
        if m and NUM.match(m.group(3).strip()):
            props.setdefault(m.group(1), {})[m.group(2)] = float(m.group(3))

    stack = []          # (indent, multiplier or None)
    func = "<file>"
    found, blind = [], []
    for num, indent, text in lines:
        while stack and indent <= stack[-1][0]:
            stack.pop()
        m = re.match(r"^(?:static )?func (\w+)", text)
        if m:
            func, stack = m.group(1), []
            continue
        times, unknown = 1, False
        for _, mult in stack:
            if mult is None:
                unknown = True
            else:
                times *= mult
        m = LOOP.match(text)
        if m:
            stack.append((indent, loop_count(m.group(1), consts)))
            continue
        if re.match(r"^(if|elif|else|while|match|for)\b", text):
            stack.append((indent, 1))

        for hit in UTIL_CALL.finditer(text):
            helper = hit.group(1)
            args = call_args(text, hit.start())
            found.append(dict(line=num, func=func, what="Util." + helper,
                              tris=util_tris(helper, args), times=times,
                              unsure=unknown, stock=False))
        for hit in MESH_NEW.finditer(text):
            kind = hit.group(1)
            if kind not in DEFAULTS:
                blind.append((num, func, kind))
                continue
            var = re.match(r"^(?:var )?(\w+)\s*:?=", text)
            tuned = props.get(var.group(1), {}) if var else {}
            found.append(dict(line=num, func=func, what=kind,
                              tris=raw_tris(kind, tuned), times=times,
                              unsure=unknown,
                              stock=(kind in ROUND
                                     and not any(k in tuned for k in TESS))))
    return found, blind


# ----------------------------------------------- what the scanner cannot read
#
# Two kinds of mesh have no primitive to find: the ones welded by hand in a
# SurfaceTool, and the ones a MultiMesh draws N copies of. Both are declared
# here, by hand, each with the line of shipped source its figure comes from.
# A hand-written entry is a debt — it goes stale silently — so every one of
# them names what it is reading, and --check re-reads the numbers it can.

HAND_BUILT = {
    ("scripts/world/chunk.gd", "_cut_mesh"): dict(
        tris=lambda: 2 * 24 * 24, parts=1,
        note="2 per cell, chunk_cells^2 cells; 24 on a capable device, 16 on a "
             "budget one (Quality.chunk_cells) — so 512 triangles a chunk there"),
    # The same function, cutting the same land at the resolution a chunk nobody
    # can reach is worth. Declared separately because one builder makes two
    # models here and the scanner has no way to know it.
    ("scripts/world/chunk.gd", "_cut_mesh:far"): dict(
        tris=lambda: 2 * 8 * 8 + 8 * 8, parts=1,
        note="Quality.far_cells = 8 (6 on a budget device, which is 120 with "
             "its skirt); plus 8 per cell of skirt — see Chunk.SKIRT_DROP"),
    ("scripts/util.gd", "blossom_mesh"): dict(
        tris=lambda: 4, parts=2,
        note="two crossed quads, welded in SurfaceTool"),
}

## `already` is how many copies of the per-instance mesh the SCANNER already
## counted in this same function — usually one, because the function builds the
## mesh before handing it to the MultiMesh. Without it the instance total either
## double-counts that one or swallows everything else the function builds (the
## sling's rope, the herd's name tag).
MULTI = {
    ("scripts/animals/herd.gd", "_build_multimesh"): dict(
        each=12, most=200, already=1,
        note="one pooled box a head; Herd.SOCIAL rolls caribou 2d100, and "
             "nothing else in the table reaches half that"),
    ("scripts/world/chunk.gd", "_scatter_flowers"): dict(
        each=4, most=12, already=1,
        note="Chunk._plant_meadow scatters 6-12 on a meadow, 4-8 on wetland"),
    ("scripts/world/village.gd", "_build_torches"): dict(
        each=2, most=24, already=1,
        note="Village.TORCH_MOST — the most flames one town ever draws"),
    ("scripts/player/sling.gd", "_ready"): dict(
        each=2, most=26, already=1,
        note="Sling.ARC_STEPS billboarded dots, one draw; the rope's box is "
             "counted with them"),
    ("scripts/miracles/storm_cloud.gd", "brew"): dict(
        each=2, most=22, already=0,
        note="StormCloud.LAYERS_FIERCE, thinned by Quality.particle_scale"),
}


# --------------------------------------------------------------- the naming
#
# A builder function is not a model's name. This says what each one actually
# makes, and which part of the world it belongs to, so the chart reads as a
# list of things rather than a list of functions. Anything missing is named
# loudly at the bottom rather than quietly left out.

NAMES = {
    ("world/chunk.gd", "_cut_mesh"): ("LAND", "Ground, one near chunk (48m)"),
    ("world/chunk.gd", "_cut_mesh:far"): ("LAND", "Ground, one far chunk, skirted"),
    ("world/chunk.gd", "_build_water"): ("LAND", "Water sheet, one chunk"),
    ("world/chunk.gd", "_scatter_flowers"): ("LAND", "Meadow of flowers, one chunk"),
    ("util.gd", "blossom_mesh"): ("LAND", "Flower"),
    ("world/world_gen.gd", "_show_pond"): ("LAND", "Pond marker"),

    ("creature/creature.gd", "_ready"): ("ACTORS", "The Creature"),
    ("villager/villager.gd", "_ready"): ("ACTORS", "Villager"),
    ("villager/villager.gd", "_make_carry_visual"): ("ACTORS", "Villager's load"),
    ("player/divine_hand.gd", "_build_hand_mesh"): ("ACTORS", "The Hand"),
    ("world/corpse.gd", "_ready"): ("ACTORS", "Corpse"),
    ("world/poop.gd", "_ready"): ("ACTORS", "Dung"),
    ("world/critter.gd", "_build_plate"): ("ACTORS", "Tree friend (bee, moth, bird)"),

    ("animals/animal.gd", "_build_body"): ("BEASTS", "Beast afoot (see the species table)"),
    ("animals/herd.gd", "_build_multimesh"): ("BEASTS", "Herd, drawn as numbers"),

    ("world/house.gd", "_build_visuals"): ("BUILDINGS", "House"),
    ("world/house.gd", "_build_scaffold_visuals"): ("BUILDINGS", "House under construction"),
    ("world/house.gd", "_collapse"): ("BUILDINGS", "House, fallen"),
    ("world/edubba.gd", "_ready"): ("BUILDINGS", "Edubba (school)"),
    ("world/workshop.gd", "_build_stand_in"): ("BUILDINGS", "Workshop"),
    ("world/food_store.gd", "_build_structure"): ("BUILDINGS", "Granary"),
    ("world/food_store.gd", "_refresh_stack"): ("BUILDINGS", "Granary's stores, full"),
    ("world/farm.gd", "_ready"): ("BUILDINGS", "Farm plot"),
    ("world/creature_nest.gd", "_build_lodge"): ("BUILDINGS", "Nest lodge"),
    ("world/creature_nest.gd", "_build_wall"): ("BUILDINGS", "Nest wall, one stone"),
    ("world/creature_nest.gd", "_build_back_wall"): ("BUILDINGS", "Nest back wall"),
    ("world/creature_nest.gd", "_build_effigy"): ("BUILDINGS", "Nest effigy"),
    ("world/creature_nest.gd", "_build_pool"): ("BUILDINGS", "Nest pool"),
    ("world/creature_nest.gd", "_build_fire"): ("BUILDINGS", "Nest fire"),
    ("world/creature_nest.gd", "_scratch"): ("BUILDINGS", "Nest tally scratch"),

    ("world/village.gd", "_build_totem"): ("VILLAGE", "Totem"),
    ("world/village.gd", "_build_pen"): ("VILLAGE", "Stock pen"),
    ("world/village.gd", "_build_influence_ring"): ("VILLAGE", "Influence ring"),
    ("world/village.gd", "_build_torches"): ("VILLAGE", "Torchlight, one town"),
    ("world/creature_stake.gd", "_ready"): ("VILLAGE", "Creature stake"),
    ("story/storyboard.gd", "_plant_marker"): ("VILLAGE", "Story marker"),

    ("world/wild_tree.gd", "_ready"): ("WILDERNESS", "Tree"),
    ("world/forage_bush.gd", "_ready"): ("WILDERNESS", "Berry bush"),
    ("world/rock_deposit.gd", "_ready"): ("WILDERNESS", "Rock"),

    ("world/food_item.gd", "_build_fish"): ("CARRIED", "Fish"),
    ("world/food_item.gd", "_build_meat"): ("CARRIED", "Joint of meat"),
    ("world/food_item.gd", "_build_sheaf"): ("CARRIED", "Sheaf of grain"),
    ("world/resource_item.gd", "_ready"): ("CARRIED", "Log / stone / bundle"),
    ("villager/weapon.gd", "build_visual"): ("CARRIED", "Weapon (any of six)"),
    ("miracles/miracle_orb.gd", "_ready"): ("CARRIED", "Miracle orb"),
    ("player/sling.gd", "_ready"): ("CARRIED", "Sling"),

    ("miracles/fireball.gd", "_ready"): ("MIRACLES", "Fireball"),
    ("miracles/fireball.gd", "_blast_visuals"): ("MIRACLES", "Fireball's blast"),
    ("miracles/fireball.gd", "_ember_mesh"): ("MIRACLES", "Ember"),
    ("miracles/fireball.gd", "_lay_trail"): ("MIRACLES", "Fire left burning"),
    ("miracles/eye_volcano.gd", "_throw_blob"): ("MIRACLES", "Volcano blob"),
    ("miracles/portal.gd", "_ready"): ("MIRACLES", "Portal"),
    ("miracles/storm_cloud.gd", "_sheet_mesh"): ("MIRACLES", "Storm sheet"),
    ("miracles/storm_cloud.gd", "brew"): ("MIRACLES", "Storm cloud, whole"),
    ("miracles/storm_shroud.gd", "_build"): ("MIRACLES", "Storm shroud"),
    ("miracles/storm_shroud.gd", "_strike_between"): ("MIRACLES", "Lightning arc"),
    ("miracles/mercy_shroud.gd", "_build"): ("MIRACLES", "Mercy shroud"),
    ("miracles/mercy_shroud.gd", "_tick_waves"): ("MIRACLES", "Mercy wave"),
    ("miracles/miracle_manager.gd", "_cast_heal"): ("MIRACLES", "Healing ring"),
    ("miracles/miracle_manager.gd", "_cast_water_walk"): ("MIRACLES", "Water-walk halo"),
    ("miracles/miracle_manager.gd", "_cast_lightning"): ("MIRACLES", "Lightning bolt"),
    ("miracles/miracle_manager.gd", "_cast_tornado"): ("MIRACLES", "Tornado"),
    ("miracles/miracle_manager.gd", "_hurl_glob"): ("MIRACLES", "Lava glob"),
    ("miracles/miracle_manager.gd", "_add_bird"): ("MIRACLES", "Bird of the flock"),
    ("miracles/miracle_manager.gd", "_drop_mesh"): ("MIRACLES", "Rain drop"),
    ("miracles/miracle_manager.gd", "_lava_splash"): ("MIRACLES", "Lava splash"),
    ("miracles/miracle_manager.gd", "_cast_healing_shower"): ("MIRACLES", "Healing mote"),
    ("miracles/miracle_manager.gd", "_cast_flight"): ("MIRACLES", "Flight mote"),
    ("miracles/miracle_manager.gd", "_cast_strength"): ("MIRACLES", "Strength mote"),

    ("animals/animal.gd", "ignite"): ("FIRE", "Beast alight"),
    ("villager/villager.gd", "ignite"): ("FIRE", "Villager alight"),
    ("world/farm.gd", "_build_fire"): ("FIRE", "Farm alight"),
    ("world/kindling.gd", "light"): ("FIRE", "Building alight"),
    ("world/wild_tree.gd", "_build_fire_visual"): ("FIRE", "Tree alight"),
}

ORDER = ["LAND", "ACTORS", "BEASTS", "BUILDINGS", "VILLAGE",
         "WILDERNESS", "CARRIED", "MIRACLES", "FIRE"]


def beasts():
    """Every species' body, priced off Animal.SPECIES itself.

    A beast is not one model, it is twenty, and they differ: the four with a
    neck carry an extra box, and the frog's legs are under the threshold that
    grows any. Reading the table is the only way this stays true when a
    species is added."""
    src = open("scripts/animals/animal.gd", encoding="utf-8").read()
    body = src[src.index("const SPECIES := {"):]
    body = body[:body.index("\n}\n")]
    out = []
    for m in re.finditer(r'"(\w+)":\s*\{(.+?)\}\s*,?\s*\n', body, re.S):
        name, fields = m.group(1), m.group(2)
        leg = float(re.search(r'"leg":\s*([\d.]+)', fields).group(1))
        neck = re.search(r'"neck":\s*([\d.]+)', fields)
        parts, tris = 1, box_tris()                       # the trunk
        if leg > 0.1:
            parts, tris = parts + 4, tris + 4 * box_tris()
        if neck:
            parts, tris = parts + 1, tris + box_tris()
        parts, tris = parts + 1, tris + sphere_tris(8, 4)  # the head
        out.append((name, parts, tris))
    return sorted(out, key=lambda r: (-r[2], r[0]))


def path_of(row):
    return row["file"][len(SRC) + 1:]


def models():
    """The chart's rows: every model, named, with its parts and triangles."""
    rows, blind = [], []
    for root, _, files in os.walk(SRC):
        for name in sorted(files):
            if not name.endswith(".gd"):
                continue
            path = os.path.join(root, name)
            got, miss = scan(path)
            for r in got:
                r["file"] = path
                rows.append(r)
            # A MultiMesh the MULTI table already accounts for is priced, not
            # blind; anything else by that name is a new one nobody has counted.
            blind += [(path,) + b for b in miss
                      if (path, b[1]) not in MULTI]

    by = {}
    for r in rows:
        if r["file"].endswith("util.gd"):
            continue                # the helpers themselves, priced at callers
        key = (r["file"], r["func"])
        slot = by.setdefault(key, dict(parts=0, tris=0, line=r["line"],
                                       unsure=False, stock=0, stock_at=[], notes=[]))
        slot["parts"] += r["times"]
        slot["tris"] += int(r["tris"]) * r["times"]
        slot["unsure"] = slot["unsure"] or r["unsure"]
        if r["stock"]:
            slot["stock"] += r["times"]
            slot["stock_at"].append("%s:%d %s" % (path_of(r), r["line"], r["what"]))
        slot["notes"].append("%s x%d = %d" % (r["what"], r["times"],
                                              int(r["tris"]) * r["times"]))
    for key, hand in HAND_BUILT.items():
        slot = by.setdefault(key, dict(parts=0, tris=0, line=0, unsure=False,
                                       stock=0, stock_at=[], notes=[]))
        slot["parts"] += hand["parts"]
        slot["tris"] += hand["tris"]()
        slot["notes"].append(hand["note"])
    for key, many in MULTI.items():
        slot = by.setdefault(key, dict(parts=0, tris=0, line=0, unsure=False,
                                       stock=0, stock_at=[], notes=[]))
        fresh = many["most"] - many["already"]
        slot["parts"] += fresh
        slot["tris"] += many["each"] * fresh
        slot["notes"].append("%d x %d — %s" % (many["most"], many["each"],
                                               many["note"]))

    out, unnamed = [], []
    for (path, func), v in by.items():
        short = path[len(SRC) + 1:]
        named = NAMES.get((short, func))
        if named is None:
            unnamed.append("%s:%s" % (short, func))
            named = ("UNNAMED", func)
        out.append(dict(group=named[0], model=named[1], file=short, func=func,
                        line=v["line"], parts=v["parts"], tris=v["tris"],
                        unsure=v["unsure"], stock=v["stock"],
                        stock_at=v["stock_at"], made_of=v["notes"]))
    out.sort(key=lambda r: (ORDER.index(r["group"]) if r["group"] in ORDER
                            else len(ORDER), -r["tris"]))
    return out, blind, unnamed


KNOB = re.compile(r"^return \[([\d.,\s]+)\]\[effective_tier\(\)\]$")


def knobs():
    """The per-tier numbers Quality actually ships, read off Quality itself —
    never copied here, because a copy of a tuning knob is a knob that stops
    being tuned."""
    out, func = {}, ""
    for _, _, text in logical_lines("scripts/quality.gd"):
        m = re.match(r"^func (\w+)\(", text)
        if m:
            func = m.group(1)
            continue
        m = KNOB.match(text)
        if m:
            out[func] = [float(v) for v in m.group(1).split(",")]
    return out


def land(rows):
    """WHAT THE LAND COSTS, which is the answer to the whole question.

    Every model in the chart above is a rounding error beside this. The sight
    ring is seventeen chunks across, and until the far ring was cut coarse every
    one of them was 1,152 triangles whether you could reach it or not.

    TWO BANDS NOW. Inside `load_radius` a chunk is a place and is cut fine,
    because the grid is also the collision heightmap. Outside it a chunk is
    scenery: `far_cells` a side, plus a skirt of 8 per cell to cover the cracks
    where a coarse edge meets a fine one."""
    k = knobs()
    per_tier = []
    for tier, label in enumerate(["LOW", "MEDIUM", "HIGH"]):
        cells = int(k["chunk_cells"][tier])
        far = int(k["far_cells"][tier])
        ring = int(k["sight_radius"][tier])
        near_ring = int(k["load_radius"][tier])
        chunks = (2 * ring + 1) ** 2
        near_lot = (2 * near_ring + 1) ** 2
        far_lot = chunks - near_lot
        per_near = 2 * cells * cells
        per_far = 2 * far * far + 8 * far
        per_tier.append(dict(tier=label, cells=cells, far=far, ring=ring,
                             chunks=chunks, near_lot=near_lot, far_lot=far_lot,
                             per_chunk=per_near, per_far=per_far,
                             tris=near_lot * per_near + far_lot * per_far,
                             was=chunks * per_near,
                             herd_agents=int(k["herd_agents"][tier]),
                             actor_dist=k["actor_distance"][tier]))
    return per_tier


def town(rows):
    """A WORKED TOWN, at the size the game actually reaches: 108 souls and 430
    head of livestock, which are numbers off a real session rather than off a
    spreadsheet. Answers the only question the chart cannot: which of these
    models is the one there are enough of to matter."""
    look = {r["model"]: r["tris"] for r in rows}
    herd_each = MULTI[("scripts/animals/herd.gd", "_build_multimesh")]["each"]
    afoot = 24                    # Quality.herd_agents at the top tier
    return [
        ("108 villagers", 108, look["Villager"]),
        ("406 head as numbers", 406, herd_each),
        ("24 head afoot as beasts", afoot, 140),
        ("40 houses", 40, look["House"]),
        ("5 granaries, full", 5, look["Granary"] + look["Granary's stores, full"]),
        ("5 barns' worth of pens", 5, look["Stock pen"]),
        ("3 workshops", 3, look["Workshop"]),
        ("1 edubba", 1, look["Edubba (school)"]),
        ("1 totem + ring + torches", 1,
         look["Totem"] + look["Influence ring"] + look["Torchlight, one town"]),
        ("1 nest, whole", 1,
         look["Nest lodge"] + look["Nest effigy"] + look["Nest fire"]
         + look["Nest pool"] + 6 * look["Nest wall, one stone"]),
        ("1 Creature", 1, look["The Creature"]),
    ]


def main():
    rows, blind, unnamed = models()
    if "--json" in sys.argv:
        print(json.dumps(dict(models=rows, species=beasts(),
                              blind=blind, unnamed=unnamed), indent=1))
        return 0

    group = None
    print("%-38s %6s %9s  %s" % ("MODEL", "PARTS", "TRIS", "BUILT BY"))
    for r in rows:
        if r["group"] != group:
            group = r["group"]
            print("\n== %s" % group)
        flag = "!" if r["stock"] else (" ?" if r["unsure"] else "")
        print("%-38s %6d %9s%-2s %s:%s"
              % (r["model"], r["parts"], "{:,}".format(r["tris"]), flag,
                 r["file"], r["func"]))

    print("\n== EVERY BEAST'S BODY (Animal.SPECIES, one box a limb)")
    print("%-38s %6s %9s" % ("SPECIES", "PARTS", "TRIS"))
    for name, parts, tris in beasts():
        print("%-38s %6d %9s" % (name, parts, tris))

    total = sum(r["tris"] for r in rows)
    print("\n%d models, %s triangles with one of everything standing in a row."
          % (len(rows), "{:,}".format(total)))

    print("\n== THE LAND, which is the budget")
    print("%-8s %7s %7s %8s %8s %10s %12s %12s %6s"
          % ("TIER", "NEAR", "FAR", "CHUNKS", "FAR LOT", "EACH FAR",
             "ONE BAND", "TWO BANDS", "CUT"))
    for t in land(rows):
        print("%-8s %7s %7s %8d %8d %10s %12s %12s %5.1fx"
              % (t["tier"], "{:,}".format(t["per_chunk"]),
                 "%dx%d" % (t["far"], t["far"]), t["chunks"], t["far_lot"],
                 "{:,}".format(t["per_far"]), "{:,}".format(t["was"]),
                 "{:,}".format(t["tris"]), float(t["was"]) / t["tris"]))

    print("\n== A TOWN OF 108 SOULS AND 430 HEAD, standing on it")
    rolled = town(rows)
    print("%-30s %6s %9s %12s" % ("", "HOW MANY", "EACH", "TRIANGLES"))
    for what, many, each in rolled:
        print("%-30s %6d %9s %12s"
              % (what, many, "{:,}".format(each), "{:,}".format(many * each)))
    built = sum(m * e for _, m, e in rolled)
    ground = land(rows)[2]["tris"]
    print("%-30s %6s %9s %12s" % ("everything the town built", "", "",
                                  "{:,}".format(built)))
    print("%-30s %6s %9s %12s" % ("the ground it stands on", "", "",
                                  "{:,}".format(ground)))
    print("\nThe land is %.0f%% of it. Every model in the chart above is the "
          "change." % (100.0 * ground / (ground + built)))
    stock = [r for r in rows if r["stock"]]
    if stock:
        print("\n! STOCK TESSELLATION — a primitive built with nobody setting its "
              "segments.\n  Godot's defaults are 64x32, which is a decision this "
              "game makes nowhere else:")
        for r in stock:
            print("    %-34s %8s in %d part(s)"
                  % (r["model"], "{:,}".format(r["tris"]), r["stock"]))
            for at in r["stock_at"]:
                print("        " + at)
    if unnamed:
        print("\nBUILDERS WITH NO NAME IN THE CHART — name them in NAMES:")
        for u in unnamed:
            print("    " + u)
    if blind:
        print("\nMESHES THIS TOOL CANNOT PRICE — teach it, or it lies by omission:")
        for path, num, func, kind in blind:
            print("    %s:%d %s builds a %s" % (path, num, func, kind))
    print("\n? a loop whose count is not a literal — the figure is one pass.")
    if "--check" in sys.argv:
        return 1 if (blind or unnamed or stock) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
