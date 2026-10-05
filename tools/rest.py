#!/usr/bin/env python3
"""UP AFTER SLEEP, AND DOWN WHEN SPENT.

"People are like... crawling? After they awaken up, they go about their day
crawling on the ground." Sleep pitches a villager's body over; only some of
the ways out of bed stood it back up, so the rest went about the day lying
down. Now a villager is in one pose at a time, worked out from what they are
doing and written whole whenever it changes (VillagerPose; see tools/pose.py).

"Creature having 0 energy, he should literally pass out and immediately rest.
The leash has been making him unable to sleep." The lead decides for a creature
on it, so it never chose rest, and every tug of a held rope woke it. Now:
spent, it drops where it stands, whatever it was doing; tired, it rests before
it obeys; asleep, a call on the lead is kept for when it wakes.

Statements here; with GODOT set to a Godot binary, tools/live/rest_live.gd runs
it all in a real engine.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VILLAGER = (ROOT / "scripts/villager/villager.gd").read_text()
CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()
LEAD = (ROOT / "scripts/creature/creature_lead.gd").read_text()
LEISURE = (ROOT / "scripts/creature/creature_leisure.gd").read_text()


def bare(text):
    return "\n".join(ln.split("#")[0].rstrip() for ln in text.splitlines()
                     if ln.split("#")[0].strip())


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def source(fail):
    if "VillagerPose.apply(self)" not in body(VILLAGER, "_physics_process"):
        fail.append("nothing puts a villager's body in its pose")
    feel = body(CREATURE, "_tick_feelings")
    if "CreatureLeisure.pass_out_if_spent(self)" not in feel:
        fail.append("a spent creature does not drop where it stands")
    spent = body(LEISURE, "pass_out_if_spent")
    for need in ("who.release_carried()", "who.throwing.spill(who)",
                 "who._target = Vector3.INF", "who.state = Creature.State.SLEEPING"):
        if need not in spent:
            fail.append("pass_out_if_spent no longer does: %s" % need)
    decide = body(CREATURE, "_decide")
    leash = decide.find("if leash_target != Vector3.INF:")
    rest = decide.find("if CreatureLeisure.rest_before_the_lead(self):")
    obey = decide.find("state = State.LEASHED")
    if not 0 <= leash < rest < obey:
        fail.append("the lead decides before a tired creature can rest")
    to_spot = body(LEAD, "to_spot")
    if to_spot.find("if CreatureLeisure.lead_waits(who):") < 0 \
            or to_spot.find("if CreatureLeisure.lead_waits(who):") > to_spot.find("who.state = Creature.State.LEASHED"):
        fail.append("a tug on the lead still wakes a sleeping creature")
    spent_at = float(re.search(r"^const SPENT := ([0-9.]+)", LEISURE, re.M).group(1))
    tired = float(re.search(r"^const TIRED := ([0-9.]+)", LEISURE, re.M).group(1))
    roused = float(re.search(r"^const ROUSED := ([0-9.]+)", LEISURE, re.M).group(1))
    print("  drops at %.1f energy, rests before the lead under %.0f, roused by it past %.0f"
          % (spent_at, tired, roused))
    if not spent_at < tired < roused:
        fail.append("spent, tired and roused are out of order")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "tools/live/rest_live.gd"], capture_output=True, text=True, timeout=300)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  in Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0 else "FAILING"))
    if ran.returncode != 0:
        fail.append("in Godot:\n" + "\n".join(ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("UP AFTER SLEEP, DOWN WHEN SPENT")
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
