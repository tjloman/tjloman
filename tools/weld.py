#!/usr/bin/env python3
"""ONE DRAW A THING: WHAT WELDING BUYS, AND WHAT KEEPS IT HONEST.

"The game is still lagging too quickly. Can we please figure out ways to make
it run buttery smooth even on a potato?"

The screenshots: 1,534 draw calls, 506 souls, 143 houses, 94 workshops, and
the script rows the meter can time adding up to about 25ms of a 69ms frame.
The rest is the engine, and on a phone the engine's bill is set by the number
of draw calls, not triangles. Everything in this game is assembled out of
primitive meshes, one MeshInstance3D and one draw per part: a house was six,
a workshop up to thirteen, a field of crops thirteen, a villager three (with
the name over their head), a beast six or seven.

Weld bakes a finished thing's still parts into ONE surface with vertex colours
and one shared material. This reads the statements that make that safe, and
prices the screenshot's town before and after. Arithmetic on the source and
on counts from the screenshot; not a frame capture.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import tri_budget  # noqa: E402 — a sibling in tools/, found by the line above
WELD = (ROOT / "scripts/weld.gd").read_text()
HOUSE = (ROOT / "scripts/world/house.gd").read_text()
SHOP = (ROOT / "scripts/world/workshop.gd").read_text()
MAN = (ROOT / "scripts/villager/villager.gd").read_text()
FARM = (ROOT / "scripts/world/farm.gd").read_text()
QUALITY = (ROOT / "scripts/quality.gd").read_text()


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


def tier_list(name):
    m = re.search(r"func %s\(\) -> float:\s*\n\s*return \[([^\]]+)\]" % name, QUALITY)
    if not m:
        sys.exit("could not read Quality.%s" % name)
    return [float(v) for v in m.group(1).split(",")]


def source(fail):
    statics = body(WELD, "statics")
    if "keep.has(part)" not in statics:
        fail.append("Weld.statics does not honour `keep`: it would free a part its "
                    "owner still holds")
    if "mutable.has(skin)" not in statics:
        fail.append("Weld.statics folds a material the owner changes later into the "
                    "plain surface — the windows would never light")
    if "parts <= surfaces" not in statics:
        fail.append("Weld.statics welds even when there is nothing to gain")
    still = body(WELD, "_still")
    for need in ("get_script() == null", "get_child_count() == 0", "get_surface_count() == 1"):
        if need not in still:
            fail.append("Weld._still no longer requires %s" % need)
    plain = body(WELD, "_is_plain")
    for need in ("albedo_texture == null", "not m.emission_enabled", "TRANSPARENCY_DISABLED"):
        if need not in plain:
            fail.append("Weld._is_plain no longer requires %s" % need)
    if "vertex_color_is_srgb = true" not in body(WELD, "_plain_skin"):
        fail.append("welded colours are read as linear: every building would wash out")
    drop = body(WELD, "_drop")
    if "remove_child(part)" not in drop or "part.free()" not in drop:
        fail.append("a welded-away part lingers a frame under its own copy")
    if "Weld.statics(self, [], [_window_mat])" not in body(HOUSE, "_build_visuals"):
        fail.append("the house welds without keeping its window material apart")
    if "Weld.statics(self, [_lamp, _feed])" not in body(SHOP, "_ready"):
        fail.append("the workshop welds without keeping the lamp and the feed")
    if "Quality.label_distance()" not in body(MAN, "_physics_process"):
        fail.append("villager labels no longer shrink with the tier")
    if "REDRAW_EVERY" not in body(FARM, "_show_crop"):
        fail.append("the crop rewrites twelve transforms every frame again")
    # And every weld the draw chart credits must still be there.
    for (path, func), entry in tri_budget.WELDED.items():
        if not tri_budget.welded_in(str(ROOT / path), entry, func):
            fail.append("tri_budget credits %s:%s with %d draws, and the weld is gone"
                        % (path, func, entry["draws"]))


def town(fail):
    """THE SCREENSHOT'S TOWN, if everything in it were in view at once."""
    labels_low = tier_list("label_distance")[0]
    rows = [
        # what, how many, draws before, draws after
        ("houses", 143, 6, 2),
        ("workshops (a well, most of them)", 94, 5, 1),
        ("fields of crops", 18, 13, 2),
        ("storehouses", 2, 16 + 48, 5 + 4),
        ("stock pens", 2, 21, 1),
        ("beasts afoot", 8, 6, 1),
        ("villagers, bodies", 506, 2, 1),
    ]
    print("THE SCREENSHOT'S TOWNS, everything in view (the real count is less —")
    print("the far one is past the far plane in part):")
    print("  %-34s %6s %8s %8s" % ("", "how many", "before", "after"))
    before = after = 0
    for what, many, was, now in rows:
        before += many * was
        after += many * now
        print("  %-34s %6d %8d %8d" % (what, many, many * was, many * now))
    # THE NAMES OVER THEIR HEADS: a label is a draw, and they were written
    # inside 38m; on the LOW tier now inside the first entry of label_distance.
    # By area, in a town at the density of the screenshot's (roughly one soul
    # per 60 square metres near the middle).
    per_m2 = 1.0 / 60.0
    was_labels = int(3.14159 * 38.0 ** 2 * per_m2)
    now_labels = int(3.14159 * labels_low ** 2 * per_m2)
    before += was_labels
    after += now_labels
    print("  %-34s %6s %8d %8d" % ("name labels in reach", "", was_labels, now_labels))
    print("  %-34s %6s %8d %8d" % ("total", "", before, after))
    if after * 2 > before:
        fail.append("welding saves less than half the draws (%d -> %d)" % (before, after))


def main():
    fail = []
    source(fail)
    town(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
