#!/usr/bin/env python3
"""EVERY KNOB THE QUALITY TIER TURNS, read out of the source.

    python3 tools/tiers.py            the table
    python3 tools/tiers.py -v         and each knob's own first line of doc

A list written by hand goes stale the first time somebody changes a number, so
this reads scripts/quality.gd (and the one tier table that lives elsewhere,
Crowd.AT_FULL) and prints what LOW, MEDIUM and HIGH each get, whether the
thermostat may turn it down mid-game ("heat": it follows effective_tier) or
only a deliberate change of tier may ("fixed": it rebuilds every material's
pipeline, see the note above Quality.shadow_reach), and how many places in the game ask for it.

It fails only if it cannot read a knob it knows is there — a table that
silently drops a row is worse than no table.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
QUALITY = (ROOT / "scripts/quality.gd").read_text()
CROWD = (ROOT / "scripts/crowd.gd").read_text()
SOURCES = [p for p in (ROOT / "scripts").rglob("*.gd") if p.name != "quality.gd"]
ALL = "\n".join(p.read_text() for p in SOURCES)

# Where each knob is spent: the GPU, the CPU, or both. Judgement, not source.
SPENT = {
    "glow": "GPU", "shadow_reach": "GPU", "water_alpha": "GPU",
    "msaa_3d": "GPU", "render_scale": "GPU", "chunk_cells": "CPU+GPU",
    "far_cells": "CPU+GPU", "decisions": "CPU", "think_usec": "CPU",
    "critters": "CPU", "herd_agents": "CPU", "load_radius": "CPU+GPU",
    "unload_radius": "RAM", "wood_beyond": "CPU+GPU", "sight_radius": "CPU+GPU",
    "camera_far": "GPU", "clutter_distance": "GPU", "actor_distance": "GPU",
    "label_distance": "GPU", "building_distance": "GPU", "particle_scale": "CPU+GPU",
    "fog_density": "look", "night_lights": "GPU", "AT_FULL": "CPU",
}


def doc_line(name):
    """The first line of the ## block above a func, without the ##."""
    m = re.search(r"((?:^##.*\n)+)func %s\(" % name, QUALITY, re.M)
    if not m:
        return ""
    first = m.group(1).splitlines()[0].lstrip("#").strip()
    return first


def knobs():
    rows = []
    for m in re.finditer(r"^func (\w+)\(\) -> [\w.]+:\n((?:\t.*\n|\n)+?)(?=^\S)", QUALITY, re.M):
        name, text = m.group(1), m.group(2)
        code = "\n".join(ln.split("#")[0] for ln in text.splitlines())
        table = re.search(r"return \[([^\]]+)\]\[(effective_tier|tier)\(\)\]", code)
        if table:
            vals = [v.strip() for v in table.group(1).split(",")]
            how = "heat" if table.group(2) == "effective_tier" else "fixed"
        else:
            cmp = re.search(r"(effective_tier\(\)|tier) >= Tier\.(MEDIUM|HIGH)", code)
            top = re.search(r"return (\S+) if effective_tier\(\) == Tier\.HIGH else (\S+)", code)
            if top and not cmp:
                # Only HIGH differs; the rest share the other value.
                rows.append((name, [top.group(2), top.group(2), top.group(1)], "heat",
                             len(re.findall(r"Quality\.%s\(" % name, ALL))))
                continue
            if not cmp:
                continue
            at = ["LOW", "MEDIUM", "HIGH"].index(cmp.group(2))
            on = re.search(r"return (\S+) if .*? else (\S+)", code)
            if on:
                vals = [on.group(2) if i < at else on.group(1) for i in range(3)]
            else:
                vals = ["off" if i < at else "on" for i in range(3)]
            how = "heat" if cmp.group(1).startswith("effective") else "fixed"
        uses = len(re.findall(r"Quality\.%s\(" % name, ALL))
        rows.append((name, vals, how, uses))
    full = re.search(r"^const AT_FULL: Array\[int\] = \[([^\]]+)\]", CROWD, re.M)
    if full:
        rows.append(("AT_FULL", [v.strip() for v in full.group(1).split(",")], "heat",
                     len(re.findall(r"AT_FULL", CROWD)) - 1))
    return rows


def main():
    verbose = "-v" in sys.argv
    rows = knobs()
    want = {"render_scale", "chunk_cells", "decisions",
            "glow", "AT_FULL", "shadow_reach"}
    missing = want - {r[0] for r in rows}
    print("%-18s %-8s %-8s %-8s %-6s %-8s %s" % ("knob", "LOW", "MEDIUM", "HIGH",
                                                  "turns", "spends", "asked by"))
    for name, vals, how, uses in rows:
        vals = [v.replace("Viewport.MSAA_", "").replace("DISABLED", "off") for v in vals]
        print("%-18s %-8s %-8s %-8s %-6s %-8s %d" % (name, *vals, how, SPENT.get(name, "?"),
                                                    uses))
        if verbose and doc_line(name):
            print("    %s" % doc_line(name))
    print()
    print("turns: 'heat' = the thermostat may lower it mid-game; 'fixed' = only a "
          "change of tier does")
    # THE PLAYER'S OWN, which no tier turns: read off Quality the same way, so
    # a slider whose ends move is a table that moves with it.
    print()
    print("THE PLAYER'S OWN (no tier turns these):")
    found = {k: re.search(r"^const RINGS_%s := (\d+)" % k, QUALITY, re.M)
             for k in ("LEAST", "MOST", "ADVISED", "CAUTION")}
    msaa = re.search(r"return Viewport\.MSAA_2X if msaa else", QUALITY)
    if all(found.values()):
        n = {k: int(v.group(1)) for k, v in found.items()}
        print("  rings of land       %d to %d, starts and recommended at %d, warns past %d"
              % (n["LEAST"], n["MOST"], n["ADVISED"], n["CAUTION"]))
        print("  far plane and fog   follow the rings (Quality.camera_far, fog_density)")
    else:
        missing.add("the rings slider")
    if msaa:
        print("  2x MSAA             on or off; starts on where the tier is MEDIUM or more")
    else:
        missing.add("the MSAA setting")
    if missing:
        print("FAIL: could not read %s" % ", ".join(sorted(missing)))
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
