#!/usr/bin/env python3
"""A TOWN GATHERS ALL OVER ITSELF, NOT ON ONE PATCH OF DIRT.

Worship, the homeless and the evening dance all went to one point — the totem,
or the nest — so a town of four hundred had a hundred and fifty people standing
on the same few square metres. Villagers do not collide with one another, so
that crowd cost nothing in the physics solver; what it cost was SCRIPT. Every
one of them greets, murmurs and steers round the neighbours near it, and in a
crowd of k people that is on the order of k-squared looks. A crowd of 150 is
11,175 pairs. Fifteen crowds of ten is 675.

This draws a town's evening off the real weights and reports the biggest crowd
and the pairs, before and after. It is a model of WHERE people go, not of the
frame: the frame is on the meter. And it checks that no gathering statement in
villager.gd still points at the totem alone.
"""
import pathlib
import random
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
G = (ROOT / "scripts/world/village_gathering.gd").read_text()
V = (ROOT / "scripts/villager/villager.gd").read_text()
VILLAGE = (ROOT / "scripts/world/village.gd").read_text()


def const(name):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, G, re.M)
    if not m:
        sys.exit("could not read %s off village_gathering.gd" % name)
    return float(m.group(1))


def bare(text):
    return "\n".join(l.split("#")[0].rstrip() for l in text.splitlines()
                     if l.split("#")[0].strip())


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


TOTEM, NEST, SHRINE, DOORSTEP = (const(n) for n in ("TOTEM", "NEST", "SHRINE", "DOORSTEP"))


def evening(people, houses, shrines, has_nest, homes, rng):
    """Each gatherer draws a KIND, then a place of it, as VillageGathering.spot."""
    crowd = {}
    for i in range(people):
        kinds = [("totem", TOTEM)]
        if has_nest:
            kinds.append(("nest", NEST))
        if shrines:
            kinds.append(("shrine", SHRINE))
        kinds.append(("door", DOORSTEP))
        total = sum(w for _, w in kinds)
        roll = rng.random() * total
        kind = kinds[-1][0]
        for name, w in kinds:
            roll -= w
            if roll <= 0:
                kind = name
                break
        if kind == "shrine":
            name = "shrine%d" % rng.randrange(shrines)
        elif kind == "door":
            name = "house%d" % (i % houses if i < homes else rng.randrange(houses))
        else:
            name = kind
        crowd[name] = crowd.get(name, 0) + 1
    return crowd


def pairs(crowd):
    return sum(k * (k - 1) // 2 for k in crowd.values())


def main():
    fail = []
    rng = random.Random(2026)
    # Oakwick, off the screenshot: 445 souls, about a hundred roofs, a nest.
    people, houses, shrines = 150, 100, 4
    before = {"totem": people}
    after = evening(people, houses, shrines, True, homes=110, rng=rng)
    print("AN EVENING IN A TOWN OF FOUR HUNDRED, %d out and gathering" % people)
    print("  %-22s %8s %10s" % ("", "biggest", "pairs"))
    print("  %-22s %8d %10d" % ("all at the totem", max(before.values()), pairs(before)))
    print("  %-22s %8d %10d" % ("all over the town", max(after.values()), pairs(after)))
    share = after.get("totem", 0) / float(people)
    print("  %.0f%% of them at the totem, %d at the nest, %d at the shrines, "
          "the rest on doorsteps"
          % (share * 100.0, after.get("nest", 0),
             sum(v for k, v in after.items() if k.startswith("shrine"))))
    if max(after.values()) > people // 4:
        fail.append("one place still draws %d of %d — the crowd moved, it did "
                    "not spread" % (max(after.values()), people))
    if pairs(after) * 10 > pairs(before):
        fail.append("spreading the town saves less than nine tenths of the "
                    "neighbour-looking a crowd costs")
    if share > 0.12:
        fail.append("%.0f%% still gather at the totem — it is meant to be the "
                    "rare place" % (share * 100.0))

    print()
    print("WHAT THE SOURCE ACTUALLY DOES")
    pick = body(V, "_pick_job") + body(V, "_choose") + body(V, "_go_sleep") \
        + body(V, "_start_job")
    for what, marker in (("the lonely", "State.GO_WORSHIP"),
                         ("the dance", "State.GO_CIRCLE")):
        seg = pick[:pick.find(marker) + 1] if marker in pick else ""
        tail = seg.splitlines()[-4:] if seg else []
        near = pick[max(pick.find(marker) - 400, 0):pick.find(marker) + 200]
        if "VillageGathering.spot(" not in near:
            fail.append("%s no longer go wherever the town gathers" % what)
        else:
            print("  %-12s go wherever the town gathers ....... yes" % what)
    sleep = body(V, "_go_sleep")
    if "VillageGathering.spot(" not in sleep or "totem.global_position" in sleep:
        fail.append("the homeless still all sleep in the square")
    else:
        print("  the homeless sleep on doorsteps ................. yes")
    circ = V[V.index("State.CIRCLING:"):][:900]
    if "_dance_mid" not in circ:
        fail.append("a dancer away from the nest still circles the nest's fire "
                    "from across the town")
    else:
        print("  a dancer circles what they are dancing round .... yes")
    if "v.state == Villager.State.CIRCLING" not in bare(VILLAGE):
        fail.append("the nest counts only the dancers at the nest, so dancing "
                    "anywhere else raises no prayer")
    else:
        print("  every dancer counts toward the nest's prayer ..... yes")
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
