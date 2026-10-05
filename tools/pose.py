#!/usr/bin/env python3
"""ONE POSE AT A TIME, BY NUMBER.

"I feel like we need to assign animations a code (like a hexadecimal 00-FF)
and make those like a status which villagers may only be in one animation at
a time." A body was posed from a dozen places, each writing its own part of
it and trusting somebody else to put it back; some never did, and a town
crawled about its day after sleep. Now a villager has one pose byte, worked out
from what it is doing (VillagerPose.of), and the byte is the whole body:
VillagerPose.apply writes every part from one table whenever it changes.

What holds that in place:

  1. ONE WRITER. Outside villager_pose.gd nothing writes a villager's body
     pitch, its figure's rotation or drop, or the pose byte — except the throw,
     which turns the figure in the air while the pose is FALL (the one part the
     table hands away, NAN).
  2. THE TABLE IS WHOLE: every code has a row, every row has every part, codes
     are unique bytes, and each sits in the band its high nibble names.
  3. A POSE COMES FROM WHAT THEY ARE DOING, not from a flag: lying only while
     asleep, low only while eating a person or seated in school.
  4. It is applied every tick a villager is processed.
  5. With GODOT set: in a real engine, a body put to bed, taken out of it by
     any route, seated in school and moved out of it, and thrown and landed,
     is in the right pose each time (tools/live/pose_live.gd).
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
POSE = (ROOT / "scripts/villager/villager_pose.gd").read_text()
VILLAGER = (ROOT / "scripts/villager/villager.gd").read_text()
BANDS = {0x0: "ON ITS FEET", 0x1: "LOW", 0x2: "LYING", 0x3: "FALLEN", 0x4: "IN THE HAND"}
WRITES = re.compile(
    r"(_body_mesh\.rotation\w*(\.\w+)?\s*=|_visuals\.(rotation|position)\w*(\.\w+)?\s*=|"
    r"_visuals\.(global_)?rotate\w*\(|\bpose_code\s*=)")


def bare(text):
    return "\n".join(ln.split("#")[0].rstrip() for ln in text.splitlines())


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def one_writer(fail):
    allowed = 0
    for path in (ROOT / "scripts").rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        if rel == "scripts/villager/villager_pose.gd":
            continue
        for n, line in enumerate(bare(path.read_text()).splitlines(), 1):
            if not WRITES.search(line):
                continue
            # THE THROW'S TURN: the figure tumbles in the air, while FALL.
            if rel == "scripts/villager/villager.gd" and "_visuals.global_rotate(_spin_ang" in line:
                allowed += 1
                continue
            # A body that is not a villager's is not this file's business.
            if not rel.startswith("scripts/villager/"):
                continue
            fail.append("%s:%d writes a villager's pose outside VillagerPose: %s"
                        % (rel, n, line.strip()))
    if allowed != 1:
        fail.append("the throw's tumble is gone or doubled (%d)" % allowed)


def table(fail):
    codes = {m.group(1): int(m.group(2), 16)
             for m in re.finditer(r"^const ([A-Z]+) := 0x([0-9A-Fa-f]{2})$", POSE, re.M)}
    rows = dict(re.findall(r"^\t([A-Z]+): \[(.+)\],", POSE, re.M))
    if len(set(codes.values())) != len(codes):
        fail.append("two poses share a code")
    if set(codes) != set(rows):
        fail.append("codes without a row, or rows without a code: %s"
                    % sorted(set(codes) ^ set(rows)))
    for name, row in rows.items():
        if len([p for p in row.split(",") if p.strip()]) != 4:
            fail.append("%s's row does not say every part of the body" % name)
    print("  %d poses:" % len(codes))
    for band in sorted(BANDS):
        names = [n for n, c in sorted(codes.items(), key=lambda kv: kv[1]) if c >> 4 == band]
        print("    0x%X_ %-12s %s" % (band, BANDS[band],
                                      " ".join("%02X %s" % (codes[n], n.lower()) for n in names)))
    for name in ("SLEEP",):
        if codes.get(name, 0) >> 4 != 0x2:
            fail.append("%s is not in the LYING band" % name)
    for name in ("FALL", "PINNED", "DYING"):
        if codes.get(name, 0) >> 4 != 0x3:
            fail.append("%s is not in the FALLEN band" % name)
    for name in ("SIT", "FEED"):
        if codes.get(name, 0) >> 4 != 0x1:
            fail.append("%s is not in the LOW band" % name)
    if "FALL: [" not in POSE or "NAN]" not in POSE.split("FALL: [")[1].split("\n")[0]:
        fail.append("FALL no longer hands the figure to the throw")


def derived(fail):
    of = body(POSE, "of")
    if "State.SLEEPING: return SLEEP" not in of:
        fail.append("asleep is not the only way to lie down")
    if "Villager.State.AT_SCHOOL: return SIT if who._seated else IDLE" not in of \
            or of.count("_seated") != 1:
        fail.append("a seat is honoured outside school, and a child sits on after it")
    if not re.search(r"State\.EATING and VillagerLook\.eating_a_person\(who\):\s*\n\s*return FEED", of):
        fail.append("feeding over a body is not read from what they are eating")
    if "VillagerPose.apply(self)" not in body(VILLAGER, "_physics_process"):
        fail.append("the pose is never applied")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                          "tools/live/pose_live.gd"], capture_output=True, text=True, timeout=300)
    checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
    print("  in Godot: %d checks, %s" % (len(checks), "all pass" if ran.returncode == 0 else "FAILING"))
    if ran.returncode != 0:
        fail.append("in Godot:\n" + "\n".join(ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("ONE POSE AT A TIME")
    one_writer(fail)
    table(fail)
    derived(fail)
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
