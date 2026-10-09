#!/usr/bin/env python3
"""NO SCRIPT WARNINGS: what the editor says when it loads the game, said here first.

Two "Integer division" warnings shipped and were found in the editor's output on
the player's own machine, because nothing here ran the game the way the editor
does. A debug launch does: every script is compiled with its warnings on, and
each one is printed with the file and line it came from.

With GODOT set to a Godot binary this launches the game headless with --debug
for a few dozen frames and fails on any warning raised by a script
(`at: GDScript::...`). Engine warnings that are not about a script — a missing
.uid file re-made from cache, say — are not this tool's business.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    godot = os.environ.get("GODOT", "")
    print("NO SCRIPT WARNINGS")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        print("\nSuccess: no problems found")
        return 0
    ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--debug",
                          "--quit-after", "40"], capture_output=True, text=True, timeout=300)
    lines = (ran.stdout + ran.stderr).splitlines()
    found = []
    for i, line in enumerate(lines[:-1]):
        if line.startswith("WARNING:") and "GDScript::" in lines[i + 1]:
            where = re.search(r"\((res://[^)]+)\)", lines[i + 1])
            found.append("%s  %s" % (where.group(1) if where else lines[i + 1].strip(),
                                     line[len("WARNING:"):].strip()))
    for f in found:
        print("  " + f)
    print("  %d script warning(s) on a debug launch" % len(found))
    print()
    if found:
        print("FAIL: scripts raise warnings — the editor shows every one of these")
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
