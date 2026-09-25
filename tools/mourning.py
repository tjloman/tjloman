#!/usr/bin/env python3
"""THE DEAD ARE WEPT OVER, AND THE BEASTS ARE CUT UP.

A death used to be a line of text and a body nobody looked at. The hive
registered it, the god was told, and every soul in the village carried on
hauling stone past their neighbour lying in the road. Grief that nothing DOES
is not grief, it is bookkeeping.

And a carcass in a field was meat with the killing already done that no village
had any way to notice — it simply fell apart into loose joints on its own clock
and the town got what the ground gave it.

NEITHER WOULD FIT. villager.gd was thirty lines under its ceiling, so this
began by moving two things out of it that were never behaviour at all: every
"find me the nearest X" (VillagerSearch) and every word a villager is called
(VillagerWords). Between them that is a quarter of a thousand lines of a file
that has to keep room for a villager to do something NEW.

What this checks, beyond the arithmetic:

  1. THE SPLIT IS REAL. Not forwarders — the functions live in exactly one
     place, and the file has genuine headroom rather than having been shaved.

  2. EVERY STATE HAS A NAME. Two match blocks in VillagerWords are now the
     only place a State is turned into words, so a new one that nobody names
     shows up over somebody's head as "?". This walks the enum.

  3. NOBODY WEEPS OVER DINNER. A town that eats its dead must never queue
     grief behind butchery — for them a body is a job, and the gate is on the
     villager rather than on the village, because a decent soul in a cannibal
     town is still a decent soul.

  4. A CROWD DOES NOT EMPTY THE VILLAGE. The job board docks a job by how many
     are already at it, and that is the ONLY thing between one death and the
     whole town standing in a ring. It works by NAME, so a state missing from
     `current_job` is a job nobody is counted as doing.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
V = (ROOT / "scripts/villager/villager.gd").read_text()
WORDS = (ROOT / "scripts/villager/villager_words.gd").read_text()
SEARCH = (ROOT / "scripts/villager/villager_search.gd").read_text()
WATCH = (ROOT / "scripts/world/village_watch.gd").read_text()
SOUND = (ROOT / "scripts/audio/sound_bank.gd").read_text()
CARCASS = (ROOT / "scripts/world/carcass.gd").read_text()

## gdlint's ceiling. A file at it cannot take another behaviour.
FILE_LINES = 2500


def bare(text):
    out = []
    for line in text.splitlines():
        if line.split("#")[0].rstrip():
            out.append(line.split("#")[0].rstrip())
    return "\n".join(out)


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return bare(rest[:nxt.start()] if nxt else rest)


def const(text, name, where):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


MOURN_SECONDS = const(V, "MOURN_SECONDS", "villager.gd")
SKIN_SECONDS = const(V, "SKIN_SECONDS", "villager.gd")


def states():
    blk = V[V.index("enum State {"):]
    blk = blk[:blk.index("}")]
    return [x.strip() for x in blk.split("{")[1].replace("\n", " ").split(",") if x.strip()]


def the_split(fail):
    print("THE SPLIT")
    lines = len(V.splitlines())
    print("  villager.gd is %d lines, %d under the %d-line ceiling"
          % (lines, FILE_LINES - lines, FILE_LINES))
    if lines >= FILE_LINES:
        fail.append("villager.gd is over the ceiling at %d lines" % lines)
    elif FILE_LINES - lines < 100:
        fail.append("villager.gd has %d lines of headroom. The whole point of "
                    "the split was room for the NEXT thing a villager learns to "
                    "do; under a hundred there is none." % (FILE_LINES - lines))
    for name, where, home in (
            ("VillagerSearch", SEARCH, "the finders"),
            ("VillagerWords", WORDS, "the naming")):
        print("  %-15s %4d lines — %s" % (name, len(where.splitlines()), home))
    # Moved, not copied. A forwarder left behind is the split not having
    # happened, and it is the shape this most easily degrades back into.
    stale = [n for n in ("_nearest_corpse", "_nearest_tamable", "_nearest_in_group",
                         "_find_shore", "_find_damaged_house", "_nearest_heathen",
                         "_consider", "_my_pick", "_status_word", "_morality_word",
                         "_status_text")
             if ("func %s(" % n) in V]
    if stale:
        fail.append("villager.gd still defines %s — moved means moved, and a "
                    "forwarder costs the same lines the split was for"
                    % ", ".join(stale))
    else:
        print("  nothing was left behind as a forwarder ......... yes")


def every_state_named(fail):
    print()
    print("EVERY STATE HAS A NAME")
    all_states = states()
    missing = [s for s in all_states if ("Villager.State.%s" % s) not in WORDS]
    print("  %d states, %d named in VillagerWords" % (len(all_states), len(all_states) - len(missing)))
    if missing:
        fail.append("%s %s no word in VillagerWords, so %s over somebody's head "
                    "as '?'" % (", ".join(missing),
                                "has" if len(missing) == 1 else "have",
                                "it shows" if len(missing) == 1 else "they show"))
    else:
        print("  none of them shows as '?' ...................... yes")


def grief(fail):
    print()
    print("GRIEF")
    print("  they stand over the body for %.0fs" % MOURN_SECONDS)
    pick = body(V, "_pick_job")
    if 'scores["mourn"]' not in pick:
        fail.append("nothing puts mourning on the job board")
        return
    line = [ln for ln in pick.splitlines() if 'scores["mourn"]' in ln]
    # THE WHOLE CONDITION, not the line above it. The `if` runs over two lines
    # now, and reading only the nearer one found the continuation and failed a
    # gate that was there.
    above = pick[:pick.index(line[0])].splitlines()
    cond = [above[-1]]
    for ln in reversed(above[:-1]):
        if not ln.rstrip().endswith("\\"):
            break
        cond.insert(0, ln)
    before = " ".join(c.strip() for c in cond)
    if "will_eat_flesh" not in before:
        # A town that eats its dead must not queue grief behind dinner, and the
        # gate is on the VILLAGER because a decent soul in a cannibal town is
        # still a decent soul.
        fail.append("mourning is no longer gated on the villager not eating "
                    "flesh: `%s`" % before.strip())
    else:
        print("  a flesh-eater does not weep over the meat ...... yes")
    st = body(V, "_physics_process")
    grieving = st.split("State.MOURNING:")[-1].split("State.GO_CHOP:")[0]
    for what, why in (
            ('_work_noise("weep"', "they weep openly — it has to be heard"),
            ("is_instance_valid(_target_corpse)",
             "the body can be lifted or eaten while they are still at it"),
            ("happiness = maxf", "grief costs something"),
            ("morality = minf", "and standing with your dead is decent")):
        if what not in grieving:
            fail.append("mourning no longer does this: %s" % why)
    if "weep" not in SOUND or '"weep"' not in SOUND:
        fail.append("there is no weeping sound to make")
    else:
        print("  there is a sound for it ........................ yes")
    job = body(V, "current_job")
    if "State.MOURNING" not in job:
        fail.append("mourners are not counted as doing a job, so the crowd "
                    "penalty cannot see them and one death empties the village")
    else:
        print("  mourners are counted, so a crowd thins itself .. yes")


def over_the_eaten(fail):
    """A decent man sobbing over a man who is being eaten beside him."""
    print()
    print("NOBODY WEEPS BESIDE SOMEBODY EATING")
    pick = body(V, "_pick_job")
    line = [ln for ln in pick.splitlines() if 'scores["mourn"]' in ln][0]
    gate = pick[:pick.index(line)].splitlines()
    gate = " ".join(gate[-2:])
    if "being_eaten(" not in gate:
        # Without it, `mourn` scores 34 for a body only an eater can reach, the
        # job start finds nothing, and the villager re-decides the same thing
        # forever.
        fail.append("the job board scores mourning over a body somebody is "
                    "eating, so the mourner sets out, finds nothing, and does "
                    "it again every decision")
    else:
        print("  the board does not offer a body being eaten ... yes")
    start = body(V, "_start_job")
    if "VillagerSearch.corpse(self, true)" not in start:
        fail.append("a mourner still sets out for a body somebody is eating")
    else:
        print("  a mourner never sets out for one ............... yes")
    st = body(V, "_physics_process")
    grieving = st.split("State.MOURNING:")[-1].split("State.GO_CHOP:")[0]
    if "being_eaten(get_tree(), _target_corpse, true)" not in grieving:
        fail.append("somebody can kneel down and start eating beside a mourner "
                    "and the mourner goes on sobbing")
    elif "witness_horror(" not in grieving or "scare(" not in grieving:
        fail.append("a mourner who sees it happen is neither horrified nor "
                    "gets up and runs")
    else:
        print("  and one who sees it start is horrified, and runs  yes")
    # ON THE SCALE, NOT OFF IT. witness_horror takes morality, and a mourner
    # tipped under VillagerFeeding.WICKED in one sighting goes from weeping over
    # the dead to eating them.
    horror = const(V, "HORROR_OF_IT", "villager.gd")
    worst = 0.0
    for path in ROOT.glob("scripts/**/*.gd"):
        if path.name == "villager.gd":
            continue
        for m in re.finditer(r"witness_horror\(([0-9.]+)\)", path.read_text()):
            worst = max(worst, float(m.group(1)))
    print("  seeing it costs %.0f morality; the worst the world already does "
          "is %.0f" % (horror, worst))
    if horror > worst:
        fail.append("seeing their dead eaten costs %.0f morality, off the top "
                    "of a scale that runs to %.0f — enough to tip a mourner "
                    "into eating the body themselves" % (horror, worst))


def butchery(fail):
    print()
    print("BUTCHERING A BEAST")
    print("  %.0fs over the body, then the meat is carried home" % SKIN_SECONDS)
    pick = body(V, "_pick_job")
    if 'scores["skin"]' not in pick:
        fail.append("nothing puts butchering a carcass on the job board")
    elif "watch.carcass" not in pick:
        fail.append("the job board does not ask the watch whether there IS a "
                    "carcass, so villagers set off for nothing")
    else:
        print("  the town notices a body in its fields .......... yes")
    if "func _look_for_carcass" not in WATCH or "is_spoiled()" not in WATCH:
        fail.append("the watch does not look for carcasses, or sends people to "
                    "burnt ones — a charred body feeds nobody")
    else:
        print("  and never to a burnt one ....................... yes")
    st = body(V, "_physics_process")
    skinning = st.split("State.SKINNING:")[-1].split("State.GO_MOURN:")[0]
    if "butcher()" not in skinning:
        fail.append("skinning no longer butchers anything")
    elif '_begin_haul("meat"' not in skinning:
        fail.append("the joints are not carried home, so a butcher cuts a "
                    "carcass up and the village never sees it")
    else:
        print("  the joints are shouldered and walked home ...... yes")
    if "is_spoiled" not in SEARCH:
        fail.append("VillagerSearch.carcass will send a butcher to a burnt body")
    if "func is_spoiled" not in CARCASS:
        fail.append("a carcass cannot say whether it is burnt")


def main():
    fail = []
    the_split(fail)
    every_state_named(fail)
    grief(fail)
    over_the_eaten(fail)
    butchery(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
