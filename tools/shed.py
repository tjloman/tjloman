#!/usr/bin/env python3
"""THE OLD GROUND IS PUT AWAY A LITTLE AT A TIME.

After a warp across the map the world freed every chunk it had loaded, stripped
every chunk beyond walking range and re-boarded every wood — all in one frame.
None of that is script time: `queue_free` tears nodes down at the END of the
frame, so the whole bill landed in the next frame's head, where the meter read
"5680 ms before any script ran" and could not say why. The loading side had a
budget from the start; the unloading side never did.

Now a chunk out of sight is hidden and switched off at once (free) and torn down
SHEDS_PER_FRAME at a time, sharing that allowance with stripping and boarding.
This checks _shed by its statements and says how long a warp takes to clear.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
W = (ROOT / "scripts/world/world_gen.gd").read_text()
LEDGER = (ROOT / "scripts/ledger.gd").read_text()


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if m is None:
        return ""
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return "\n".join(l.split("#")[0].rstrip() for l in (rest[:nxt.start()] if nxt else rest).splitlines())


def main():
    fail = []
    found = re.search(r"^const SHEDS_PER_FRAME := (\d+)", W, re.M)
    if found is None:
        print("FAIL: there is no SHEDS_PER_FRAME — putting the old ground away "
              "has no allowance, and a warp tears it all down in one frame")
        return 1
    per = int(found.group(1))
    warp = 70
    print("A WARP ACROSS THE MAP LEAVES ABOUT %d CHUNKS BEHIND" % warp)
    print("  before: all %d torn down in ONE frame's head" % warp)
    print("  now:    hidden at once, %d torn down a frame — %d frames, "
          "about %.1fs at 30 fps" % (per, (warp + per - 1) // per, warp / per / 30.0))
    shed = body(W, "_shed")
    frees = [ln for ln in shed.splitlines() if "queue_free()" in ln]
    if len(frees) != 1 or "_doomed" not in shed:
        fail.append("_shed frees chunks outside the doomed trickle — a warp is "
                    "one frame of teardown again")
    loop = shed[shed.index("while shed < SHEDS_PER_FRAME"):] if "while shed < SHEDS_PER_FRAME" in shed else ""
    if "queue_free()" not in loop:
        fail.append("the doomed chunks are never freed at all")
    for call in ("chunk.board_the_wood()", "chunk.strip_down()"):
        # The line ABOVE the call — the text before it on its own line is
        # only its indentation.
        guard = shed[:shed.index(call)].rstrip().splitlines()[-1] if call in shed else ""
        if "shed < SHEDS_PER_FRAME" not in guard:
            fail.append("%s is not counted against SHEDS_PER_FRAME" % call)
    if "visible = false" not in shed or "PROCESS_MODE_DISABLED" not in shed:
        fail.append("a chunk out of sight goes on drawing and thinking until its "
                    "turn to be freed")
    else:
        print("  out of sight is hidden and switched off at once .. yes")
    if "OBJECT_NODE_COUNT" not in body(LEDGER, "turn_the_page"):
        fail.append("the meter can no longer see nodes vanish in the worst frame")
    else:
        print("  the worst frame says how many nodes it lost ...... yes")
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
