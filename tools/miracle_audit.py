#!/usr/bin/env python3
"""WHAT EVERY COMBINATION OF RUNES ACTUALLY DOES, RIGHT NOW.

Read out of spellbook.gd and miracle_manager.gd, so it is the game's own
answer rather than anyone's recollection of it. Written for the session where
it gets decided what the miracles SHOULD do — you cannot have that argument
without a list of what they currently do, and the list is longer and stranger
than it looks from the recipe table.

Every drawing lands in one of three buckets:

  NAMED       a RECIPES entry: a hand-written miracle with its own effect.
  AMPLIFIED   all one rune, so the base miracle writ larger by potency.
  BLEND       everything else: every rune's own miracle at once, each weakened
              by 1/sqrt(n). This is the multi-cast, and it is most of the space.

Usage:
    python3 tools/miracle_audit.py              # the report
    python3 tools/miracle_audit.py --json       # the same, machine-readable
    python3 tools/miracle_audit.py --depth 4    # go deeper than three runes
"""
import argparse
import itertools
import json
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPELLBOOK = os.path.join(ROOT, "scripts", "miracles", "spellbook.gd")
MANAGER = os.path.join(ROOT, "scripts", "miracles", "miracle_manager.gd")


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def const_block(text, name):
    """The body of `const NAME := { ... }`, comments stripped."""
    start = text.index("const %s := {" % name) + len("const %s := {" % name)
    depth, i = 1, start
    while depth:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    body = text[start:i - 1]
    return re.sub(r"#.*", "", body)


def str_map(text, name):
    return dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', const_block(text, name)))


def cost_map(text):
    out = {}
    for m in re.finditer(r'"([a-z_]+)"\s*:\s*\{\s*"cost"\s*:\s*([\d.]+)',
                         const_block(text, "MIRACLES")):
        out[m.group(1)] = float(m.group(2))
    return out


def tiers(text):
    block = re.search(r"const RUNE_TIERS := \[(.*?)\n\]", text, re.S).group(1)
    return [re.findall(r'"([a-z_]+)"', row)
            for row in re.findall(r"\[(.*?)\]", block)]


def resolved(text):
    """The outcomes `resolve()` actually has a match arm for. Anything a recipe
    names that is missing here falls through the `_:` and silently does
    NOTHING — which is the failure worth finding."""
    body = text[text.index("func resolve("):]
    body = body[:body.index("\n\nfunc ")]
    return set(re.findall(r'^\s*"([a-z_]+)":', body, re.M))


def karma(text):
    out = {}
    for m in re.finditer(r'"([a-z_]+)"\s*:\s*\{\s*"player"\s*:\s*(-?[\d.]+)',
                         const_block(text, "KARMA")):
        out[m.group(1)] = float(m.group(2))
    return out


class Book:
    def __init__(self):
        sb, mm = read(SPELLBOOK), read(MANAGER)
        self.rune_of = str_map(sb, "RUNE_OF")
        self.base = str_map(sb, "BASE")
        self.recipes = str_map(sb, "RECIPES")
        self.tiers = tiers(sb)
        self.combo_mult = float(
            re.search(r"const COMBO_MULTIPLIER := ([\d.]+)", sb).group(1))
        self.costs = cost_map(mm)
        self.resolved = resolved(mm)
        self.karma = karma(mm)
        self.runes = [r for tier in self.tiers for r in tier]
        self.tier_of = {r: i + 1 for i, tier in enumerate(self.tiers) for r in tier}

    def key(self, draw):
        return "+".join(sorted(draw))

    def interpret(self, draw):
        """Mirrors Spellbook.interpret."""
        k = self.key(draw)
        if k in self.recipes:
            return {"how": "NAMED", "miracle": self.recipes[k], "potency": 1.0}
        distinct = sorted(set(draw))
        if len(distinct) == 1:
            base = self.base.get(distinct[0])
            if not base:
                return {"how": "NOTHING"}
            return {"how": "AMPLIFIED", "miracle": base,
                    "potency": 1.0 + (len(draw) - 1) * 0.75}
        share = 1.0 / math.sqrt(len(distinct))
        parts = []
        for r in distinct:
            base = self.base.get(r)
            if base:
                parts.append((base, share * (1.0 + (draw.count(r) - 1) * 0.6)))
        if not parts:
            return {"how": "NOTHING"}
        return {"how": "BLEND", "parts": parts}

    def cost(self, draw):
        """Mirrors MiracleManager._cost_of, which is NOT what it looks like.

        A NAMED or AMPLIFIED drawing is charged the OUTCOME'S price, eased by
        potency — so `air + air` costs a tornado (110), not the sum of two
        gusts. Only a BLEND is priced from its parts, and then discounted.
        Getting this wrong the first time made hurricanes look cheaper than
        water-walking, which is the sort of thing a room would then spend an
        hour arguing about.
        """
        r = self.interpret(draw)
        if "miracle" in r:
            base = self.costs.get(r["miracle"], 25.0)
            return base * (1.0 + (r["potency"] - 1.0) * 0.7)
        total = sum(self.costs.get(m, 25.0) * p for m, p in r.get("parts", []))
        return total * self.combo_mult

    def tier_needed(self, draw):
        return max(self.tier_of.get(r, 9) for r in draw)


def draws(runes, depth):
    for n in range(1, depth + 1):
        for combo in itertools.combinations_with_replacement(runes, n):
            yield list(combo)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--depth", type=int, default=3)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    book = Book()

    rows = []
    for draw in draws(book.runes, args.depth):
        r = book.interpret(draw)
        rows.append({
            "runes": draw, "key": book.key(draw), "how": r["how"],
            "miracle": r.get("miracle", ""),
            "parts": [{"miracle": m, "potency": round(p, 2)} for m, p in
                      r.get("parts", [])],
            "potency": round(r.get("potency", 0.0), 2),
            "cost": round(book.cost(draw), 1),
            "tier": book.tier_needed(draw),
            "works": r.get("miracle", "") in book.resolved if r["how"] != "BLEND"
                     else all(m in book.resolved for m, _ in r.get("parts", [])),
        })

    if args.json:
        print(json.dumps({"runes": book.runes, "rows": rows}, indent=1))
        return 0

    total = len(rows)
    by_how = {}
    for row in rows:
        by_how.setdefault(row["how"], []).append(row)

    print(__doc__.split("Usage:")[0])
    print("=" * 76)
    print("THE WHOLE SPACE, to %d runes" % args.depth)
    print("=" * 76)
    print("  %d distinct drawings (order never matters; repeats do)\n" % total)
    for how in ("NAMED", "AMPLIFIED", "BLEND", "NOTHING"):
        n = len(by_how.get(how, []))
        if n:
            print("    %-10s %4d   %4.1f%%" % (how, n, 100.0 * n / total))

    # ---- what is hand-written, and what it costs -------------------------
    print("\n" + "=" * 76)
    print("HAND-WRITTEN MIRACLES — %d recipes, %d distinct outcomes"
          % (len(book.recipes), len(set(book.recipes.values()))))
    print("=" * 76)
    print("  %-26s %-18s %6s %5s %6s  %s"
          % ("drawing", "becomes", "cost", "tier", "karma", ""))
    seen = {}
    for key, out in sorted(book.recipes.items(),
                           key=lambda kv: (kv[1], len(kv[0]))):
        draw = key.split("+")
        k = book.karma.get(out)
        note = ""
        if out in seen:
            note = "same as %s" % " + ".join(seen[out])
        else:
            seen[out] = draw
        if out not in book.resolved:
            note = "!! NOT IMPLEMENTED — resolve() has no arm, this does nothing"
        print("  %-26s %-18s %6.0f %5d %6s  %s"
              % (" + ".join(draw), out, book.cost(draw), book.tier_needed(draw),
                 ("%+.0f" % k) if k is not None else "-", note))

    # ---- runes that are along for the ride --------------------------------
    print("\n" + "=" * 76)
    print("RUNES THAT CHANGE NOTHING")
    print("=" * 76)
    print("  A recipe where dropping a rune gives the same outcome. The rune is")
    print("  paid for and drawn and does nothing — which is the clearest kind of")
    print("  thing to either give a meaning or delete.\n")
    idle = 0
    for key, out in sorted(book.recipes.items()):
        draw = key.split("+")
        for i, rune in enumerate(draw):
            shorter = draw[:i] + draw[i + 1:]
            if not shorter:
                continue
            other = book.interpret(shorter)
            if other.get("miracle") == out:
                print("  %-26s -> %-16s  '%s' is doing nothing (%s alone is the same)"
                      % (" + ".join(draw), out, rune, " + ".join(shorter)))
                idle += 1
                break
    if not idle:
        print("  (none)")

    # ---- the multi-casts ---------------------------------------------------
    print("\n" + "=" * 76)
    print("THE MULTI-CASTS — %d drawings, %.0f%% of the space"
          % (len(by_how.get("BLEND", [])),
             100.0 * len(by_how.get("BLEND", [])) / total))
    print("=" * 76)
    print("  Every rune's own miracle at once, each at 1/sqrt(n) strength. These")
    print("  need no design to WORK — they already do something sensible — but")
    print("  none of them has a name, so the readout calls every one of them")
    print("  'a working of your own'. A sample, by how many runes:\n")
    for n in range(2, args.depth + 1):
        pool = [r for r in by_how.get("BLEND", []) if len(r["runes"]) == n]
        if not pool:
            continue
        print("  %d runes — %d drawings, e.g." % (n, len(pool)))
        for row in pool[::max(len(pool) // 4, 1)][:4]:
            parts = ", ".join("%s x%.2f" % (p["miracle"], p["potency"])
                              for p in row["parts"])
            print("      %-22s %3.0f prayer, tier %d  ->  %s"
                  % (" + ".join(row["runes"]), row["cost"], row["tier"], parts))

    # ---- what you can reach, when ------------------------------------------
    print("\n" + "=" * 76)
    print("WHAT OPENS WHEN — rudiments are taught a tier at a time")
    print("=" * 76)
    for t in range(1, len(book.tiers) + 1):
        held = [r for r in book.runes if book.tier_of[r] <= t]
        reach = [r for r in rows if r["tier"] <= t]
        named = [r for r in reach if r["how"] == "NAMED"]
        print("  tier %d (%-38s) %4d drawings, %2d named"
              % (t, ", ".join(held), len(reach), len(named)))

    # ---- the questions the room has to answer ------------------------------
    print("\n" + "=" * 76)
    print("WHAT NEEDS DECIDING")
    print("=" * 76)
    missing = [o for o in set(book.recipes.values()) if o not in book.resolved]
    print("  * %d recipes name an outcome resolve() cannot cast: %s"
          % (len(missing), ", ".join(sorted(missing)) or "none"))
    dupes = {}
    for key, out in book.recipes.items():
        dupes.setdefault(out, []).append(key)
    many = {o: ks for o, ks in dupes.items() if len(ks) > 1}
    print("  * %d outcomes are reachable by more than one drawing" % len(many))
    for out, keys in sorted(many.items()):
        print("      %-16s %s" % (out, "  |  ".join(keys)))
    print("  * %d drawings resolve to a multi-cast with no name of its own"
          % len(by_how.get("BLEND", [])))
    unused = [r for r in book.runes
              if not any(r in k.split("+") for k in book.recipes)]
    print("  * runes that appear in NO named recipe: %s"
          % (", ".join(unused) or "none"))
    print("  * %d of %d miracles carry a karma weight; the rest are neutral"
          % (len(book.karma), len(book.costs)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
