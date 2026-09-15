#!/usr/bin/env python3
"""CAN YOU SKIP A STONE, AND DOES A BOULDER SINK?

A chunk's water is one MeshInstance3D quad with nothing behind it -- which is
right, a lake you can walk into wants no physics body -- and it meant a thrown
stone passed straight THROUGH the surface and landed on the seabed with a thump.
There was no such thing as hitting water.

Blow already rides every thrown rigid body and sees where it was last frame and
where it is now, which is all a skip needs. This walks a throw across a pond and
reports how many times it comes off, which is a thing that lives or dies on the
release angle and cannot be eyeballed from the constants.

Every number is read off scripts/world/blow.gd and the game's own gravity.
"""
import argparse
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BLOW = (ROOT / "scripts/world/blow.gd").read_text()
RES = (ROOT / "scripts/world/resource_item.gd").read_text()
ROCK = (ROOT / "scripts/world/rock_deposit.gd").read_text()


def const(name, text=BLOW, where="blow.gd"):
    m = re.search(r"^const %s\s*:?=\s*(?:deg_to_rad\()?([0-9.]+)" % name,
                  text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


SKIP_ANGLE = const("SKIP_ANGLE")            # already in DEGREES in the source
SKIP_ABOVE = const("SKIP_ABOVE")
SKIP_CARRY = const("SKIP_CARRY")
SKIP_BOUNCE = const("SKIP_BOUNCE")
SKIP_HEFT = const("SKIP_HEFT")
HEFT_BARE = const("HEFT_BARE", RES, "resource_item.gd")
HEFT_EACH = const("HEFT_EACH", RES, "resource_item.gd")
# Godot's default gravity, doubled — see Villager.GRAVITY and Sling.
GRAVITY = 19.6

SIZES = [(m.group(1), int(m.group(2))) for m in
         re.finditer(r'\{"kind": "(\w+)", "worth": (\d+)', ROCK)]


def heft(stone):
    return HEFT_BARE + max(stone - 1.0, 0.0) * HEFT_EACH


def walk(speed, angle_deg, mass, most=40):
    """Throw it flat across a pond. Returns (skips, how far it went)."""
    if mass > SKIP_HEFT:
        return 0, 0.0
    ang = math.radians(angle_deg)
    vx, vy = speed * math.cos(ang), -speed * math.sin(ang)
    x, skips = 0.0, 0
    for _ in range(most):
        s = math.hypot(vx, vy)
        if s < SKIP_ABOVE:
            break
        # The angle it meets the water at, measured off the water.
        if math.atan2(-vy, abs(vx)) > math.radians(SKIP_ANGLE):
            break
        skips += 1
        vx, vy = vx * SKIP_CARRY, -vy * SKIP_BOUNCE
        # Up, over, and back down to the surface: the hop.
        hop = 2.0 * vy / GRAVITY
        x += vx * hop
        vy = -vy
    return skips, x


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--speed", type=float, default=22.0)
    args = ap.parse_args()
    print("read off the source: a skip wants under %.0f° and over %.0f m/s,"
          "\nkeeps %.2f of its run and %.2f of its bounce, and nothing heavier"
          "\nthan %.1f skips at all.\n"
          % (SKIP_ANGLE, SKIP_ABOVE, SKIP_CARRY, SKIP_BOUNCE, SKIP_HEFT))

    print("A PEBBLE THROWN AT %.0f m/s, by release angle:" % args.speed)
    print("%-10s %8s %10s" % ("ANGLE", "SKIPS", "RUN"))
    bad = []
    best = 0
    for deg in (2, 5, 10, 15, 20, 25, 35, 50):
        n, run = walk(args.speed, deg, heft(1))
        best = max(best, n)
        print("%-9d° %8d %9.0fm" % (deg, n, run))
    if best < 3:
        bad.append("the best a pebble manages is %d skip(s); a stone that will "
                   "not walk is not worth throwing at a pond" % best)
    # AND IT HAS TO GO SOMEWHERE. Six skips across three metres is technically
    # a skip and invisible at any camera distance anybody plays at.
    run = walk(args.speed, 5, heft(1))[1]
    if run < 15.0:
        bad.append("a well-thrown pebble runs %.0fm; a skip nobody can see "
                   "from the camera is not a skip" % run)
    # A FLAT THROW MUST BEAT A STEEP ONE, which is the whole physical signature
    # of the thing and cannot be faked by tuning the count. If the water does
    # not lift the stone, the angle never steepens between hops and every throw
    # under the cutoff skips exactly the same number of times — which is the
    # shape the numbers had before, and reads as nothing at all.
    tally = [walk(args.speed, d, heft(1))[0] for d in (2, 10, 20)]
    if not (tally[0] > tally[1] > tally[2]):
        bad.append("skips by angle are %s — a flatter throw has to out-skip a "
                   "steeper one, or the release angle is not doing anything"
                   % tally)
    steep, _ = walk(args.speed, 50, heft(1))
    if steep > 0:
        bad.append("a pebble lobbed in at 50° still skips %d time(s) — the "
                   "angle is supposed to be the whole game" % steep)

    print("\nAT A GOOD ANGLE (5°), BY WHAT YOU THREW:")
    print("%-12s %7s %8s %10s" % ("", "STONE", "WEIGHT", "SKIPS"))
    for kind, worth in SIZES:
        mass = heft(min(worth, 24))
        n, _ = walk(args.speed, 5, mass)
        print("%-12s %7d %8.1f %10s"
              % (kind, worth, mass, n if n else "sinks"))
    if walk(args.speed, 5, heft(60))[0] > 0:
        bad.append("a boulder skips; it is supposed to be a splash")

    print("\nA skip lives on the RELEASE ANGLE, exactly as it does on a real"
          "\npond: lob it in and it sinks, send it out flat and it walks.")
    if bad:
        print("\nFAIL:")
        for line in bad:
            print("  " + line)
        return 1
    print("\nOK: a flat pebble walks, a lobbed one sinks, a boulder splashes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
