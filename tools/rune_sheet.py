#!/usr/bin/env python3
"""Regenerate the Rune Grammar reference sheet's data from the game's own source.

The casting reference is a published page listing EVERY drawing of one to three
runes and what each one actually casts. The point of it is that it is not
written by hand: it is derived from `spellbook.gd` and `miracle_manager.gd`, so
it cannot quietly drift from the build. Add a recipe to the game and this
regenerates the page around it.

Usage:
    python3 tools/rune_sheet.py                 # print the JSON blob
    python3 tools/rune_sheet.py --into PAGE     # splice it into a built page
    python3 tools/rune_sheet.py --summary       # what changed, in words

Everything here mirrors a specific function in the game, and the comments say
which. When one of those changes, this has to change with it — that is the
whole cost of the arrangement, and it is worth paying to never hand-maintain a
285-row table again.
"""

import argparse
import itertools
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPELLBOOK = os.path.join(ROOT, "scripts", "miracles", "spellbook.gd")
MANAGER = os.path.join(ROOT, "scripts", "miracles", "miracle_manager.gd")
GLYPHS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rune_glyphs.json")

## The longest drawing the table enumerates. Four-rune NAMED recipes are listed
## separately (there are only a handful); enumerating every 4-rune multiset
## would be 715 rows of mostly blends and would drown the interesting ones.
MAX_DRAWN = 3


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def strip_comments(text):
    """Drop `#` comments without touching a `#` inside a string literal."""
    out = []
    for line in text.splitlines():
        quote = None
        cut = len(line)
        for i, ch in enumerate(line):
            if quote:
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch == "#":
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def block(text, name):
    """The body of a `const NAME := { ... }` or `[ ... ]` declaration."""
    m = re.search(r"const\s+%s\s*:=\s*([\[{])" % re.escape(name), text)
    if not m:
        raise SystemExit("could not find const %s" % name)
    opener = m.group(1)
    closer = "}" if opener == "{" else "]"
    depth = 0
    start = m.end() - 1
    for i in range(start, len(text)):
        if text[i] in "[{":
            depth += 1
        elif text[i] in "]}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    raise SystemExit("unterminated const %s" % name)


def str_map(text, name):
    """A `const NAME := {"a": "b", ...}` read as a dict of strings."""
    body = block(text, name)
    return dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]*)"', body))


def str_lists(text, name):
    """A `const NAME := [["a","b"], ...]` read as a list of string lists."""
    body = block(text, name)
    return [re.findall(r'"([^"]+)"', row)
            for row in re.findall(r"\[([^\[\]]*)\]", body)]


def number_field(text, name, field):
    """`const NAME := {"key": {..., "field": 12.0, ...}}` -> {key: 12.0}."""
    body = block(text, name)
    out = {}
    for key, inner in re.findall(r'"([^"]+)"\s*:\s*\{([^{}]*)\}', body):
        m = re.search(r'"%s"\s*:\s*(-?[\d.]+)' % re.escape(field), inner)
        if m:
            out[key] = float(m.group(1))
    return out


def load():
    sb = strip_comments(read(SPELLBOOK))
    mm = strip_comments(read(MANAGER))
    combo = re.search(r"const\s+COMBO_MULTIPLIER\s*:=\s*([\d.]+)", sb)
    return {
        "gesture": {rune: g for g, rune in str_map(sb, "RUNE_OF").items()},
        "base": str_map(sb, "BASE"),
        "recipes": str_map(sb, "RECIPES"),
        "tiers": str_lists(sb, "RUNE_TIERS"),
        "combo": float(combo.group(1)) if combo else 0.8,
        "cost": number_field(mm, "MIRACLES", "cost"),
        "karma": number_field(mm, "KARMA", "player"),
    }


def interpret(runes, g):
    """Mirrors `Spellbook.interpret`. Returns (kind, outcome, parts).

    kind is "n" named, "s" one rune writ larger, "b" a blend; parts is
    [(miracle, potency), ...] for every kind, so costing is uniform.
    """
    key = "+".join(sorted(runes))
    if key in g["recipes"]:
        return "n", g["recipes"][key], [(g["recipes"][key], 1.0)]
    distinct = sorted(set(runes))
    if len(distinct) == 1:
        base = g["base"].get(distinct[0], "")
        potency = 1.0 + (len(runes) - 1) * 0.75
        return "s", base, [(base, potency)]
    # BLENDING: every rune's own miracle at once, each weakened for being one
    # voice among several. Nothing the player draws is ever a dead end.
    share = 1.0 / (len(distinct) ** 0.5)
    parts = []
    for rune in distinct:
        base = g["base"].get(rune, "")
        if not base:
            continue
        repeats = runes.count(rune)
        parts.append((base, share * (1.0 + (repeats - 1) * 0.6)))
    return "b", " + ".join(p[0] for p in parts), parts


def cost_of(kind, parts, g):
    """Mirrors `MiracleManager._cost_of`."""
    if kind in ("n", "s"):
        miracle, potency = parts[0]
        return g["cost"].get(miracle, 25.0) * (1.0 + (potency - 1.0) * 0.7)
    total = sum(g["cost"].get(m, 25.0) * p for m, p in parts)
    return total * g["combo"]


def karma_of(kind, parts, g):
    """What the drawing does to the player's alignment, blended by potency."""
    if kind in ("n", "s"):
        return g["karma"].get(parts[0][0], 0.0)
    return sum(g["karma"].get(m, 0.0) * p for m, p in parts)


def tier_of(runes, tier_of_rune):
    """The first village at which the whole drawing becomes castable: you need
    every rudiment in it, so it is the LAST one you are taught."""
    return max(tier_of_rune[r] for r in runes)


def build():
    g = load()
    tier_of_rune = {}
    for i, tier in enumerate(g["tiers"]):
        for rune in tier:
            tier_of_rune[rune] = i + 1
    runes = sorted(g["base"])

    rows = []
    for size in range(1, MAX_DRAWN + 1):
        for combo in itertools.combinations_with_replacement(runes, size):
            drawn = list(combo)
            kind, outcome, parts = interpret(drawn, g)
            if not outcome:
                continue
            row = {
                "r": drawn, "k": kind, "o": outcome,
                "c": round(cost_of(kind, parts, g)),
                "m": round(karma_of(kind, parts, g), 1),
                "t": tier_of(drawn, tier_of_rune),
            }
            if kind == "b":
                row["b"] = [[m, round(p, 2)] for m, p in parts]
            # What it actually casts, for the redundancy test below. Dropped
            # again before the data is written out.
            row["_sig"] = tuple(sorted((m, round(p, 2)) for m, p in parts))
            rows.append(row)

    # REDUNDANT: a drawing that casts EXACTLY what a shorter one already casts.
    #
    # The comparison has to be on what actually happens, not on the outcome's
    # name: `fire+fire` and `fire` are both "fireball", but the second is at
    # potency 1.75 and costs accordingly, so it is a bigger fireball and not a
    # waste of a stroke. The signature below is the miracle AND its potency, so
    # only a drawing that adds a rune and changes nothing is flagged — which is
    # the real complaint: `air+air+fury` is a tornado, and so is `air+air`.
    cheapest = {}
    for row in rows:
        sig = row["_sig"]
        seen = cheapest.get(sig)
        if seen is None or (len(row["r"]), row["c"]) < seen:
            cheapest[sig] = (len(row["r"]), row["c"])
    for row in rows:
        if (len(row["r"]), row["c"]) > cheapest[row["_sig"]]:
            row["x"] = 1
        del row["_sig"]

    # Named recipes too long to enumerate, listed on their own.
    long_rows = []
    for key, outcome in sorted(g["recipes"].items()):
        drawn = key.split("+")
        if len(drawn) <= MAX_DRAWN:
            continue
        long_rows.append({
            "r": drawn, "k": "n", "o": outcome,
            "c": round(g["cost"].get(outcome, 25.0)),
            "m": round(g["karma"].get(outcome, 0.0), 1),
            "t": tier_of(drawn, tier_of_rune),
        })

    with open(GLYPHS, encoding="utf-8") as fh:
        glyphs = json.load(fh)

    return {
        "rows": rows, "long": long_rows,
        "gesture": g["gesture"], "tier": tier_of_rune, "base": g["base"],
        "tiers": g["tiers"], "glyphs": glyphs,
    }


def summarize(data):
    kinds = {"n": 0, "s": 0, "b": 0}
    redundant = []
    for row in data["rows"]:
        kinds[row["k"]] += 1
        if row.get("x"):
            redundant.append("+".join(row["r"]) + " -> " + row["o"])
    outcomes = sorted({row["o"] for row in data["rows"] if row["k"] != "b"})
    fury = [r for r in data["rows"] + data["long"] if "fury" in r["r"]]
    fury_named = [r for r in fury if r["k"] == "n"]
    # Does the fury actually DO anything here? Cast the same drawing with the
    # fury taken out and see whether the outcome moves. This is the standing
    # complaint about the rune, and it should be measured rather than asserted.
    g = load()
    print("  fury changes the outcome in:")
    for r in fury_named:
        without = [x for x in r["r"] if x != "fury"]
        if not without:
            continue
        _, other, _ = interpret(without, g)
        mark = "yes" if other != r["o"] else "NO — same without it"
        print("    %-28s -> %-16s (%s)" % ("+".join(r["r"]), r["o"], mark))
    print("%d drawings of 1-%d runes" % (len(data["rows"]), MAX_DRAWN))
    print("  named    %d" % kinds["n"])
    print("  stronger %d" % kinds["s"])
    print("  blends   %d" % kinds["b"])
    print("  redundant %d:" % len(redundant))
    for line in redundant:
        print("    " + line)
    print("  %d named outcomes, %d longer named recipes" % (
        len(outcomes), len(data["long"])))
    print("  fury appears in %d drawings, named in %d:" % (len(fury), len(fury_named)))
    for r in fury_named:
        print("    " + "+".join(r["r"]) + " -> " + r["o"])


def splice(data, path):
    """Replace the __RUNES__ blob in a built page, leaving everything else."""
    page = read(path)
    marker = "window.__RUNES__="
    start = page.index(marker) + len(marker)
    end = page.index("</script>", start)
    blob = json.dumps(data, separators=(",", ":"))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(page[:start] + blob + ";" + page[end:])
    print("spliced %d bytes of data into %s" % (len(blob), path))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--into", help="a built page to splice the data into")
    ap.add_argument("--summary", action="store_true", help="describe the grammar")
    args = ap.parse_args()
    data = build()
    if args.summary:
        summarize(data)
        return 0
    if args.into:
        splice(data, args.into)
        return 0
    json.dump(data, sys.stdout, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
