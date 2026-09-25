#!/usr/bin/env python3
"""A THROWN TREE IS STILL A TREE.

It was not. A trunk that came to rest either stood back up where it stopped —
roots and all, growth resumed — or, if it had been going over fourteen metres a
second, burst into bundles of lumber and vanished. So the best thing in the
game, "throw a tree, follow it, kick it, follow it some more", lasted exactly
one throw, and there was no such object as a log.

Now it lies where it stops and stays a tree: pick it back up, set it alight,
boot it down a hill, throw it again. Walk away and in half a minute it is
firewood, which is the honest end for a trunk nobody came back for.

Three things here are worth arithmetic rather than assertion.

  1. WHAT A FELLED TRUNK IS WORTH depends on how hard it landed, and the curve
     has to be a curve: full value for one set down whole, a quarter for one
     driven into a hillside, and a straight line between. A step function is
     what the old fourteen-metre threshold was, and it meant 13.9 m/s was worth
     four times 14.1.

  2. A BURNING TREE OUTLASTS THE ROT CLOCK. A tree burns for what it is worth
     in seconds (WildTree.ignite), and if that were shorter than LIES_FOR the
     rot timer would fire mid-blaze and turn a burning tree into lumber.

  3. THE FIREBRAND ACTUALLY WORKS. Carrying a lit tree through a wood has to
     light the wood, and the burn — which is where the spreading lives — was
     skipped entirely while a tree was held.

Every number is read off the source.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TREE = (ROOT / "scripts/world/wild_tree.gd").read_text()
NAV = (ROOT / "scripts/nav_field.gd").read_text()
WATCH = (ROOT / "scripts/world/village_watch.gd").read_text()


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


def const(text, name, where="wild_tree.gd"):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


TIMBER = [int(v) for v in re.search(
    r"^const TIMBER: Array\[int\] = \[([0-9,\s]+)\]", TREE, re.M).group(1).split(",")]
LIES_FOR = const(TREE, "LIES_FOR")
SPLINTER_SHARE = const(TREE, "SPLINTER_SHARE")
SPLINTER_MOST = const(TREE, "SPLINTER_MOST")
SPLINTERS_ABOVE = const(TREE, "SPLINTERS_ABOVE")
SETTLE_UNDER = const(TREE, "SETTLE_UNDER")
BOUNCE_KEEP = const(TREE, "BOUNCE_KEEP")
BOUNCE_SLIDE = const(TREE, "BOUNCE_SLIDE")


def worth(size, impact):
    """WildTree._break_up, mirrored."""
    spoiled = min(max(impact / SPLINTERS_ABOVE, 0.0), 1.0)
    return max(int(round(TIMBER[size - 1] * (1.0 + (SPLINTER_SHARE - 1.0) * spoiled))), 1)


def yields(fail):
    print("WHAT A TRUNK ON THE GROUND IS WORTH, by how hard it landed")
    speeds = [0.0, 4.0, 8.0, 12.0, SPLINTERS_ABOVE, 30.0]
    print("  %-8s %s" % ("size", "".join("%8.0f" % v for v in speeds)))
    print("  %-8s %s" % ("", "".join("%8s" % "m/s" for _ in speeds)))
    for size in (1, 5, 9, 10):
        row = [worth(size, v) for v in speeds]
        print("  %-8d %s   (a woodcutter gets %d)"
              % (size, "".join("%8d" % v for v in row), TIMBER[size - 1]))
        if any(b > a for a, b in zip(row, row[1:])):
            fail.append("a size %d tree is worth MORE for being thrown "
                        "harder — the spoil curve runs backwards" % size)
        if row[0] != TIMBER[size - 1]:
            fail.append("a size %d tree set down whole is worth %d of its %d — "
                        "nothing was wasted, so nothing should be taken"
                        % (size, row[0], TIMBER[size - 1]))
    smashed = worth(10, SPLINTERS_ABOVE * 2.0)
    if smashed != max(int(round(TIMBER[9] * SPLINTER_SHARE)), 1):
        fail.append("a trunk driven into a hillside is not taxed at the "
                    "splinter share any more")
    print()
    print("  a giant set down whole is worth %d; the same giant hurled into a "
          "cliff, %d" % (worth(10, 0.0), smashed))


def clocks(fail):
    print()
    print("THE CLOCKS ON A FELLED TRUNK, in seconds")
    print("  %-22s %6.0f" % ("nobody comes back", LIES_FOR))
    for size in (1, 5, 9, 10):
        burn = TIMBER[size - 1]
        print("  %-22s %6d   %s" % (
            "a size %d burns for" % size, burn,
            "outlasts the rot clock" if burn > LIES_FOR else "burns out first"))
    # A tree that burns for longer than the rot clock must not rot mid-blaze.
    if "if burning:" not in body(TREE, "_process").split("if _down:")[-1][:200]:
        fail.append("a burning trunk on the ground no longer burns instead of "
                    "rotting — the biggest tree in the game burns for %ds and "
                    "would turn into lumber %ds into it" % (TIMBER[-1], LIES_FOR))
    else:
        print("  a burning trunk burns instead of rotting, whatever its size")


def source(fail):
    print()
    print("WHAT THE SOURCE ACTUALLY DOES")

    land = body(TREE, "_land")
    lie = body(TREE, "_lie_down")

    # The re-rooting line must survive, but ONLY behind the `planted` branch.
    if "planted" not in land or "rotation = Vector3(0.0, _plant_yaw, 0.0)" not in land:
        fail.append("a tree can no longer be PLANTED — setting one down gently "
                    "is the one way left to put a tree somewhere on purpose")
    else:
        print("  a tree set down gently still takes root ......... yes")
    if land.index("if planted:") > land.index("rotation = Vector3(0.0, _plant_yaw"):
        fail.append("a thrown tree is stood back upright before it is asked "
                    "whether it was planted")
    if "_lie_down(" not in land:
        fail.append("a thrown tree no longer lies down")
    else:
        print("  a thrown tree lies where it stops ............... yes")
    if "queue_free" in lie:
        fail.append("_lie_down frees the tree — the whole point is that it stays")
    if "_down = true" not in lie:
        fail.append("_lie_down does not leave the tree down")

    proc = body(TREE, "_process")
    held = proc.split("if _held:")[1].split("if _flying:")[0]
    if "_burn(delta)" not in held:
        # This is the firebrand. `_spread` lives inside `_burn`, so a held tree
        # that does not burn cannot set anything alight.
        fail.append("a held tree no longer burns, so carrying a lit pine "
                    "through a wood lights nothing — that IS the mechanic")
    else:
        print("  a tree in your hand goes on burning ............. yes")

    refusal = next((ln for ln in body(TREE, "ignite").splitlines()
                    if ln.strip().startswith("if ") and "burning" in ln), "")
    if "_held" in refusal:
        fail.append("ignite() refuses a held tree again, so you cannot set "
                    "light to the thing you are carrying")
    else:
        print("  you can light the tree you are holding .......... yes")

    if "_lying_for >= LIES_FOR" not in proc or "_break_up()" not in proc:
        fail.append("nothing turns an abandoned trunk into lumber any more")
    else:
        print("  an abandoned trunk is firewood in %.0fs .......... yes" % LIES_FOR)

    for what, where, name in (("routing", NAV, "is_down()"),
                              ("a woodcutter", WATCH, "is_down()")):
        if name not in bare(where):
            fail.append("%s does not know a log from a standing tree" % what)
    print("  routing steps over a log ....................... yes")
    print("  a woodcutter crosses the clearing for one ...... yes")

    if "func touched" not in TREE or bare(TREE).count("touched()") < 2:
        fail.append("nothing resets the half-minute, so a trunk being chased "
                    "down a hill rots out from under the chase")
    else:
        print("  playing with it starts the clock over ........... yes")


def main():
    fail = []
    yields(fail)
    clocks(fail)
    source(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
