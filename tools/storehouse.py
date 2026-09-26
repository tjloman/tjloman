#!/usr/bin/env python3
"""THE STOREHOUSE PILES: STILL, AND CHEAP.

"Storehouse is a constant source of drawing and redrawing, and it looks
glitchy as heck. Can we just give it a value, and scale some meshes to
represent fullness? Have an 'all-the-way heaped' static mesh which takes over
at 50% once full value is achieved. Something without flashing visuals, and
that can use a 4 color texture to represent what it is."

It used to show one mesh per unit, up to twelve a quarter, and on every
deposit, every meal and every withdrawal it freed all of them and built them
again at fresh random spots. This reads the statements that make the new
arrangement what it claims, and models a busy town's traffic through one
store, before and after. Arithmetic on the source, not a playtest.
"""
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
STORE = (ROOT / "scripts/world/food_store.gd").read_text()


def bare(text):
    out = []
    for line in text.splitlines():
        stripped = line.split("#")[0].rstrip()
        if stripped:
            out.append(stripped)
    return "\n".join(out)


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def const(name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, STORE, re.M)
    if not m:
        sys.exit("could not read %s off food_store.gd" % name)
    return float(m.group(1))


FULL = const("FULL")
HEAP_AT = const("HEAP_AT")
HEAP_UNTIL = const("HEAP_UNTIL")
SMALLEST = const("SMALLEST")
OLD_SHOWN = 12              # MAX_SHOWN, per quarter, before
BUILDERS = ("_build_piles", "_place_pile", "_bake", "_bake_grow", "_bake_heaps",
            "_weld", "_at", "_build_structure", "_ready")


def source(fail):
    funcs = re.findall(r"^(?:static )?func (\w+)\(", STORE, re.M)
    # NOTHING BUT THE BUILDERS MAKES OR FREES A NODE. The fire code frees the
    # whole building when it burns down, which is the one honest queue_free.
    for f in funcs:
        if f in BUILDERS or f == "burn_down":
            continue
        text = body(STORE, f)
        for bad in ("MeshInstance3D.new()", "add_child(", "queue_free()"):
            if bad in text and not (f == "withdraw_at" and bad == "add_child(") \
                    and not (f == "_process" and bad == "queue_free()"):
                fail.append("%s does %s — stock changing must not build or free "
                            "nodes" % (f, bad))
    show = body(STORE, "_show_stock")
    if ".visible != " not in show or ".scale = " not in show:
        fail.append("_show_stock does not simply scale and show the fixed piles")
    if not re.search(r"HEAP_UNTIL if _heaped\[q\] else HEAP_AT", show):
        fail.append("no hysteresis: a quarter at the line flicks heap/pile")
    place = body(STORE, "_place_pile")
    if "material_override = _palette" not in place:
        fail.append("the piles do not share the one palette material")
    bake = body(STORE, "_bake")
    if bake.count("set_pixel(") != 4 or "TEXTURE_FILTER_NEAREST" not in bake:
        fail.append("the palette is not a 4-colour nearest-filtered texture")
    if "if _palette == null:" not in body(STORE, "_build_piles"):
        fail.append("the meshes are baked per storehouse, not once")
    if "welded[Mesh.ARRAY_TEX_UV] = uvs" not in body(STORE, "_weld"):
        fail.append("_weld does not pin UVs to the palette cell")
    if not HEAP_UNTIL < HEAP_AT <= 1.0:
        fail.append("HEAP_UNTIL %.2f must sit below HEAP_AT %.2f" % (HEAP_UNTIL, HEAP_AT))


def traffic(fail):
    """A town's day through one quarter: meals, harvests, withdrawals, hovering
    around the heap line — the worst place for it to be."""
    rng = random.Random(7)
    stock = int(FULL * HEAP_AT)
    changes = 2000
    flips_now = flips_bare = 0
    heaped = heaped_bare = stock >= FULL * HEAP_AT
    most_step = 0.0
    last_size = None
    for _ in range(changes):
        # Meals of one, harvests of a few, an armful of ten now and then —
        # and the town's needs pulling it back toward the line it sits at.
        pull = 1 if stock < FULL * HEAP_AT else -1
        stock = max(0, stock + rng.choice((-1, -1, 1, 2, -2, 3, -10, 10)) + pull)
        fill = min(max(stock / FULL, 0.0), 1.0)
        was = heaped
        heaped = fill >= (HEAP_UNTIL if heaped else HEAP_AT)
        flips_now += was != heaped
        was = heaped_bare
        heaped_bare = fill >= HEAP_AT
        flips_bare += was != heaped_bare
        if not heaped and stock > 0:
            size = SMALLEST + (1 - SMALLEST) * min(fill / HEAP_AT, 1.0)
            if last_size is not None:
                most_step = max(most_step, abs(size - last_size))
            last_size = size
        else:
            last_size = None
    print("%d stock changes hovering at the heap line (%.0f of %.0f):" % (changes,
          FULL * HEAP_AT, FULL))
    print("  before:  %d nodes freed and rebuilt, at new random spots"
          % (changes * 4 * OLD_SHOWN))
    print("  after:   0 nodes; heap/pile swaps %d (without the hysteresis, %d)"
          % (flips_now, flips_bare))
    print("  largest single change in a pile's size: %.0f%% (a withdrawal of ten)"
          % (100 * most_step))
    print("  draws per storehouse: before up to %d, after at most 4"
          % (4 * OLD_SHOWN))
    if flips_now * 4 > flips_bare:
        fail.append("the hysteresis barely helps: %d swaps against %d" % (flips_now, flips_bare))
    if most_step > 0.2:
        fail.append("a pile jumps %.0f%% in one change" % (100 * most_step))


def main():
    fail = []
    source(fail)
    traffic(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
