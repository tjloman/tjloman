#!/usr/bin/env python3
"""A KILLED BEAST STAYS KILLED.

"When villagers or I kill animals they instantly respawn, and the herd count
doesn't decrease. Death needs consequence."

The herd's own books were right: a death marks the row dead, the drawing
collapses it, the tag counts the living. What undid it was the CHUNK. The near
ring on LOW is two chunks, ninety-six metres; step the camera out of it and the
chunk is stripped, its herds freed with everything else living there; step back
in and `flesh_out` scattered them again FROM THE SEED — every herd back to the
size it was born. Trees had long remembered what survived; herds never did.

Now a stripped chunk writes down its wild herds (kind, how many are left, how
many the land bore, where they had got to), a chunk dropped whole on a warp
does the same, the save carries it, and a chunk fleshed out again is restocked
from that instead of from the seed.

THE ONE TRAP: `_scatter` draws every tree, rock, bush and beast off ONE seeded
stream, and the great stone is drawn after the animals. Skip a roll for a
remembered herd and every stone after it in that chunk moves. So the rolls are
all still drawn, in the same order, stopping at the same place; only the making
is skipped. This models both paths and counts the draws.
"""
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()
WORLD = (ROOT / "scripts/world/world_gen.gd").read_text()
SAVE = (ROOT / "scripts/save_game.gd").read_text()
HERD = (ROOT / "scripts/animals/herd.gd").read_text()


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


class Stream:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.draws = 0

    def randf(self):
        self.draws += 1
        return self.r.random()


def scatter(stream, table, remembered, spot_ok=lambda: True):
    """Chunk._scatter_animals, as the source now has it."""
    herds, full, made = 0, False, 0
    for species, chance in table:
        if full:
            break
        many = int(chance) + (1 if stream.randf() < chance % 1.0 else 0)
        for _ in range(many):
            if herds >= 2:
                full = True
                break
            stream.randf()
            stream.randf()                 # _random_spot: x and z
            if not spot_ok():
                continue
            stream.randf()                 # Herd.roll_for
            if not remembered:
                made += 1
            herds += 1
    return made


def source(fail):
    anim = body(CHUNK, "_scatter_animals")
    roll = anim.find("var count := Herd.roll_for(species, rng)")
    guard = anim.find("if known == null:")
    if roll < 0 or guard < 0 or roll > guard:
        fail.append("a remembered chunk skips the herd rolls — every stone after them would move")
    if not re.search(r"if herds >= 2:\s*\n\s*full = true[^\n]*\n\s*break", anim) \
            or "if full:" not in anim:
        fail.append("the two-herd stop no longer ends the draws where it always did")
    if "restock(known)" not in anim:
        fail.append("a chunk that remembers its herds is not restocked from them")
    if "world.remember_herds(cell, herd_rows())" not in body(CHUNK, "strip_down"):
        fail.append("a stripped chunk forgets what was living on it")
    if "remember_herds(cell, gone.herd_rows())" not in body(WORLD, "_shed"):
        fail.append("a chunk dropped whole on a warp forgets what was living on it")
    rows = body(CHUNK, "herd_rows")
    if "herd.keeper != null" not in rows or "herd.alive()" not in rows:
        fail.append("herd_rows keeps the barn's stock, or counts the dead")
    if '"herds": world.herds_to_save()' not in SAVE or "world.herds_from_save(" not in SAVE:
        fail.append("the save does not carry the herds")
    if "remembered_born if remembered_born > 0 else head" not in body(HERD, "_ready"):
        fail.append("a remembered herd forgets what the land bore it, and grows back only to its remnant")


def model(fail):
    tables = [[("deer", 0.22), ("elk", 0.18), ("bear", 0.05), ("wolf", 0.05), ("tiger", 0.02)],
              [("coati", 0.2), ("anteater", 0.16), ("deer", 0.14), ("frog", 0.7), ("tiger", 0.05),
               ("chicken", 0.14), ("pig", 0.12)],
              [("frog", 1.9), ("pig", 1.12), ("anteater", 0.12)]]
    differ = 0
    trials = 0
    for t in tables:
        for seed in range(2000):
            a, b = Stream(seed), Stream(seed)
            flip = random.Random(seed * 7)
            oks = [flip.random() < 0.8 for _ in range(40)]
            ia, ib = iter(oks), iter(oks)
            scatter(a, t, False, lambda: next(ia))
            scatter(b, t, True, lambda: next(ib))
            trials += 1
            if a.draws != b.draws:
                differ += 1
    print("Seeded vs remembered, %d chunks across three biome tables:" % trials)
    print("   the stream drawn to the same place in all but %d" % differ)
    if differ:
        fail.append("%d chunks draw a different number of rolls when they remember "
                    "their herds — their stones would move" % differ)
    print()
    print("A herd of 12 bison, 5 hunted, camera away and back:")
    print("   before: 12 again (rolled from the seed)")
    print("   now:    7, growing back toward 12 by the season")


def main():
    fail = []
    source(fail)
    model(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
