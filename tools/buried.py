#!/usr/bin/env python3
"""NOTHING ENDS UP UNDER THE LAND.

"I feel like it was RELEASED under ground, and didn't end up there after
physics took over." It was, both ways, and once it was there it stayed for
ever: a carcass only falls apart once it lies still, and one falling through
the void under the world never lies still.

The ways in, and what closes each:

  1. CARRIED THROUGH A HILL. A held body is frozen and goes where the hand puts
     it; a heavy one lags in a straight line, which runs under a ridge, and a
     hand pointed at far ground with no collision rests on the sea-level plane,
     which under a hill is inside it. The carry keeps it over the land.
  2. LET GO INSIDE THE LAND, OR INSIDE A HOUSE. A body half in a house is
     pushed out of it the shortest way, which is often down through the
     ground's one-sided skin. A release puts it on top of whatever is there.
  3. THROWN THROUGH. At the hand's full speed a carcass went clean through on 3
     of 15 throws, some of them on the ticks after a hard landing. A thrown
     thing is watched for it in flight and for a second after it lands.
  4. AND IF ANY CARCASS IS UNDER THE WORLD ANYWAY, falling, it is brought back.

Each is put back on top by Footing.lift_out, which looks down from above, so a
body is never put back into the house that pushed it under.

With GODOT set, tools/live/buried_live.gd does all of it in a real engine.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()
BLOW = (ROOT / "scripts/world/blow.gd").read_text()
CARCASS = (ROOT / "scripts/world/carcass.gd").read_text()
FOOTING = (ROOT / "scripts/world/footing.gd").read_text()


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return [ln.split("#")[0].rstrip() for ln in (rest[:nxt.start()] if nxt else rest).splitlines()
            if ln.split("#")[0].strip()]


def first(lines, needle):
    return next((i for i, ln in enumerate(lines) if needle in ln), None)


def source(fail):
    carry = body(HAND, "_carry_held")
    follow = first(carry, "Sling.follow(")
    clamp = first(carry, "_held_at.y = maxf(_held_at.y, world.height_at(")
    placed = first(carry, "held_body.global_position = _held_at")
    ok = None not in (follow, clamp, placed) and follow < clamp < placed
    print("  carried: %s" % ("kept over the land" if ok else "ALLOWED INTO THE HILL"))
    if not ok:
        fail.append("a carried body can be put inside the land")
    release = body(HAND, "_release_body")
    lifted = first(release, "Footing.lift_out(body, _world(), RELEASE_SLACK, true)")
    unfrozen = first(release, "rb.freeze = false")
    ok = lifted is not None and unfrozen is not None and lifted < unfrozen
    print("  released: %s" % ("on top, of the land and of houses" if ok else "WHEREVER IT WAS"))
    if not ok:
        fail.append("a body is let go of inside the land or a house before anything "
                    "checks — physics takes it over underground")
    tick = body(BLOW, "_physics_process")
    caught = first(tick, "Footing.lift_out(thing, _land, BURIED)")
    landing = first(tick, "lands(thing,")
    after = tick[landing:landing + 4] if landing is not None else []
    stays = any("_landed = true" in ln for ln in after) and not any("queue_free()" in ln for ln in after)
    print("  thrown: %s" % ("watched through the flight and after it lands"
                            if caught is not None and (landing is None or caught < landing) and stays
                            else "LOST THROUGH THE GROUND"))
    if caught is None or (landing is not None and landing < caught):
        fail.append("nothing catches a throw that goes through the ground")
    if not stays:
        fail.append("a throw stops being watched the tick it lands, and slips through after")
    lying = body(CARCASS, "_process")
    if not any("Footing.lift_out(self" in ln for ln in lying):
        fail.append("a carcass falling under the world is never brought back, and never "
                    "falls apart either")
    top = body(FOOTING, "_set_on_top")
    if not any("intersect_ray(" in ln for ln in top):
        fail.append("a body is put back on the land under a house, and pushed under again")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "tools/live/buried_live.gd"], capture_output=True, text=True,
                         timeout=300)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  in Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0 else "FAILING"))
    if ran.returncode != 0:
        fail.append("in Godot:\n" + "\n".join(ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("NOTHING ENDS UP UNDER THE LAND")
    source(fail)
    live(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
