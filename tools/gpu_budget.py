#!/usr/bin/env python3
"""WHERE THE GPU MEMORY ACTUALLY GOES, and how much is left to spend.

THERE IS NO VIDEO RAM ON A PHONE. Every mobile GPU in use — Adreno, Mali,
PowerVR, Apple's — is a unified-memory design: the GPU reads the same physical
DRAM the CPU does, through the same controller. So "how much VRAM do we have"
is really "how much of the phone's ONE pool of RAM will the OS let this process
hold before it kills it", and the answer is a budget, not a spec.

WHAT THAT BUDGET IS. On Android the process is killed by the low-memory killer
on total resident size, and GPU allocations count toward it. The working figure
used here is a mid-tier device with 6-8 GB of RAM, of which the system and
whatever else is resident hold roughly half, and an app that stays under about
1 GB resident survives being backgrounded and coming back. Of that, the engine
and the game's own CPU-side state want a good share, which leaves ROUGHLY
300-400 MB for everything the renderer holds. That band is a judgement, not a
measurement, and it is the one number here that should be checked against a
real device with `adb shell dumpsys meminfo`.

Everything BELOW that line is counted from this project's own settings, and
that is the part worth trusting.

Usage:
    python3 tools/gpu_budget.py               # the whole report
    python3 tools/gpu_budget.py --screen 2400x1080
"""
import argparse
import re
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MB = 1024.0 * 1024.0

## The panels a mid-tier phone actually ships, landscape. The renderer draws at
## the NATIVE resolution: `window/stretch/mode="canvas_items"` scales the 2D UI
## only, so the 3D pass gets every physical pixel unless scaling_3d says else.
SCREENS = {
    "720p phone   (1600x720)": (1600, 720),
    "1080p phone  (2400x1080)": (2400, 1080),
    "1.5K phone   (2712x1220)": (2712, 1220),
    "1440p phone  (3200x1440)": (3200, 1440),
}

## Godot 4 packs a mesh vertex as position (3 x f32) plus an octahedral normal
## and tangent (4 B each), with colour as RGBA8 and UVs as two f32 in the
## attribute buffer. Terrain here carries position + normal + colour and no UV.
VERT_TERRAIN = 12 + 4 + 4          # position, packed normal, RGBA8 colour
VERT_PRIMITIVE = 12 + 4 + 4 + 8    # ...plus a tangent and a UV pair
INDEX = 2                          # 16-bit indices below 65k vertices


def setting(text, key, default):
    m = re.search(r"^%s=(.+)$" % re.escape(key), text, re.M)
    return m.group(1).strip() if m else default


def project():
    with open(os.path.join(ROOT, "project.godot")) as f:
        text = f.read()
    return {
        "renderer": setting(text, "renderer/rendering_method", '"forward_plus"'),
        "msaa": int(setting(text, "anti_aliasing/quality/msaa_3d", "0")),
        "scale": float(setting(text, "scaling_3d/scale", "1.0")),
        "stretch": setting(text, "window/stretch/mode", '"disabled"'),
    }


def quality():
    """The per-tier numbers, read out of quality.gd so this cannot drift."""
    with open(os.path.join(ROOT, "scripts", "quality.gd")) as f:
        text = f.read()

    def row(fn):
        m = re.search(r"func %s\(\)[^\n]*\n\treturn \[([^\]]+)\]" % fn, text)
        return [x.strip() for x in m.group(1).split(",")] if m else None

    return {
        "chunk_cells": [int(x) for x in row("chunk_cells")],
        "load_radius": [int(x) for x in row("load_radius")],
        "unload_radius": [int(x) for x in row("unload_radius")],
        "render_scale": [float(x) for x in row("render_scale")],
    }


def world():
    with open(os.path.join(ROOT, "scripts", "world", "world_gen.gd")) as f:
        text = f.read()
    return float(setting(text, "const CHUNK_SIZE ", "48.0").lstrip(":= "))


## RENDER TARGETS -------------------------------------------------------------
##
## The single biggest allocation in the game, and nothing about it depends on
## how much world there is. The mobile renderer keeps a colour target and a
## depth target at the 3D resolution, plus a 2D canvas target at the full
## window size for the HUD.
##
## MSAA is charged at a QUARTER weight here rather than in full: on a tiled
## mobile GPU the multisampled attachments are transient — they live in tile
## memory and are resolved before ever being written out — and Godot asks for
## them as lazily-allocated, so on most drivers they cost far less than their
## nominal size. A quarter is a guess in the safe direction.
def render_targets(w, h, msaa_index, scale):
    rw, rh = int(w * scale), int(h * scale)
    px = rw * rh
    colour = px * 4                       # RGBA8
    depth = px * 4                        # D24S8 / D32
    canvas = w * h * 4                    # the 2D target, always native
    samples = [1, 2, 4, 8][min(msaa_index, 3)]
    extra = (colour + depth) * (samples - 1) * 0.25 if samples > 1 else 0
    return {
        "3D colour": colour, "3D depth": depth,
        "MSAA %dx (transient)" % samples: extra,
        "2D canvas": canvas,
    }


## SHADOW ATLASES -------------------------------------------------------------
##
## Godot's mobile overrides: a 2048 directional atlas and a 2048 positional
## one, both 32-bit depth. Fixed cost, allocated whether or not anything is
## casting — which is why turning shadows off on the budget tier is worth 17 MB
## on its own, and why the night's light budget being FIXED matters: the
## positional atlas does not grow with the number of lamps, it just divides.
DIRECTIONAL_ATLAS = 2048
POSITIONAL_ATLAS = 2048


def shadows(on, positional=True):
    out = {}
    if on:
        out["directional atlas %d^2" % DIRECTIONAL_ATLAS] = DIRECTIONAL_ATLAS ** 2 * 4
    if positional:
        out["positional atlas %d^2" % POSITIONAL_ATLAS] = POSITIONAL_ATLAS ** 2 * 4
    return out


## TERRAIN --------------------------------------------------------------------
##
## The only thing here that scales with the size of the world. Unindexed: six
## vertices a quad, because `generate_normals` without an index buffer is what
## gives the land its faceted look.
def terrain(cells, radius, chunk_size):
    chunks = (radius * 2 + 1) ** 2
    verts = cells * cells * 6
    mesh = verts * VERT_TERRAIN
    water = 4 * VERT_TERRAIN + 6 * INDEX          # one quad, when drawn at all
    return {
        "terrain mesh (%d chunks x %dx%d)" % (chunks, cells, cells): mesh * chunks,
        "water planes": water * chunks,
    }


## POOLED PRIMITIVES ----------------------------------------------------------
##
## Villagers, animals, trees, houses and the creature are all built from
## `Util.lite_*`, which hands back a SHARED mesh out of `_mesh_pool`, keyed on
## a size bucket. So the geometry cost is set by how many DISTINCT part sizes
## the game asks for, not by how many bodies are walking around — a hundred
## villagers and one villager cost the same.
##
## The pool is generous here on purpose: an upper bound.
POOL_SHAPES = 220         # distinct bucketed meshes across every entity
POOL_SEGS = 8             # lite_* tessellation


def pooled_meshes():
    verts = (POOL_SEGS + 1) * (POOL_SEGS // 2 + 1)
    tris = POOL_SEGS * (POOL_SEGS // 2) * 2
    one = verts * VERT_PRIMITIVE + tris * 3 * INDEX + 1024   # + resource overhead
    return {"pooled part meshes (%d distinct)" % POOL_SHAPES: one * POOL_SHAPES}


def show(title, items, total_ref=None):
    print("  %s" % title)
    for name, size in items.items():
        if size <= 0:
            continue
        print("      %-42s %8.2f MB" % (name, size / MB))
    return sum(items.values())


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--screen", help="WxH, e.g. 2400x1080")
    ap.add_argument("--budget", type=float, default=350.0,
                    help="MB of renderer memory assumed available (default 350)")
    args = ap.parse_args()

    proj = project()
    qual = quality()
    chunk_size = world()
    tiers = ["LOW (budget)", "MEDIUM (mid-tier)", "HIGH (flagship)"]

    print(__doc__.split("Usage:")[0])
    print("=" * 78)
    print("WHAT THIS PROJECT ASKS FOR")
    print("=" * 78)
    print("  renderer            %s" % proj["renderer"])
    print("  msaa_3d             %s  (0 none, 1 = 2x, 2 = 4x, 3 = 8x)" % proj["msaa"])
    print("  scaling_3d/scale    %.2f   %s" % (
        proj["scale"],
        "<- 3D renders at FULL native resolution" if proj["scale"] >= 1.0 else ""))
    print("  stretch mode        %s  (2D only; the 3D pass is native either way)"
          % proj["stretch"])
    print("  texture assets      none — every surface is a vertex colour")
    print()

    screens = ({args.screen: tuple(int(v) for v in args.screen.split("x"))}
               if args.screen else SCREENS)

    for tier in (0, 1, 2):
        cells = qual["chunk_cells"][tier]
        radius = qual["load_radius"][tier]
        shadow_on = tier >= 1
        msaa = 1 if tier >= 1 else 0        # Quality.msaa_3d: 2x on medium+
        scale = qual["render_scale"][tier]
        print("=" * 78)
        print("%s   grid %dx%d (%.2fm cells), %dx%d chunks, 3D at %.0f%%"
              % (tiers[tier], cells, cells, chunk_size / cells,
                 radius * 2 + 1, radius * 2 + 1, scale * 100))
        print("=" * 78)

        content = {}
        content.update(terrain(cells, radius, chunk_size))
        content.update(pooled_meshes())
        c_total = show("CONTENT — scales with the world:", content)

        s_total = show("FIXED — allocated whether or not anything uses it:",
                       shadows(shadow_on))
        print()

        for label, (w, h) in screens.items():
            rt = render_targets(w, h, msaa, scale)
            r_total = sum(rt.values())
            total = c_total + s_total + r_total
            print("      %-26s targets %6.2f  + fixed %6.2f  + content %5.2f"
                  "  = %6.2f MB  (%3.0f%% of %.0f)"
                  % (label, r_total / MB, s_total / MB, c_total / MB,
                     total / MB, 100 * total / MB / args.budget, args.budget))
        print()

    # ---- what the headroom is actually for ---------------------------------
    print("=" * 78)
    print("WHAT A METRE OF DETAIL COSTS")
    print("=" * 78)
    print("  Terrain grid, at a 7x7 of loaded chunks:")
    for cells in (12, 16, 24, 32, 48, 64):
        m = terrain(cells, 3, chunk_size)
        print("      %2dx%2d  %5.2fm cells  %6d tris a chunk   %7.2f MB"
              % (cells, cells, chunk_size / cells, cells * cells * 2,
                 sum(m.values()) / MB))
    print()
    print("  A 4096 shadow atlas instead of 2048:      +50.3 MB (4x the area)")
    print("  Rendering 3D at 0.8 scale on a 1080p panel: -7.5 MB, and 36% of")
    print("      the fragment work — the single biggest lever in the list, and")
    print("      it is a bandwidth and heat lever far more than a memory one.")
    print("  One 2048x2048 RGBA8 texture, were there any:  16.8 MB (+5.6 mipped)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
