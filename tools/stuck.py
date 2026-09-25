#!/usr/bin/env python3
"""A STATE WITH NO WAY OUT IS A VILLAGER WHO HAS STOPPED LIVING.

A villager is a state machine with fifty-two states, and each one is a case in
one long `match` in one long file. Every case has to do one of three things
before it is finished: ask for a new plan (`_rethink`), decide on the spot
(`_choose` / `_decide`), or move to another state itself. A case that does none
of them is a body that walks into that state and stands in it for the rest of
its life -- not frozen, not erroring, just permanently busy with something that
never ends.

That is what "the villagers stopped taking care of themselves" looks like from
outside, and there is nothing in the log to find. They are alive. They are
ticking. Their hunger is climbing. They are simply never going to ask what to
do next, because the arm they are in never asks.

AND A THIRD SHAPE, which is the same illness wearing a different coat: a GATE
NOBODY CAN PASS. A child's energy climbs four a second and is never spent, so
it sits pinned at a hundred -- and the rule that sends a villager to bed asks
whether they are TIRED. Children therefore never slept. Not once, in any
village, ever. They stood in the school yard reciting their letters all night
and the teachers stood over them doing it, and every number involved was
correct.

TWO SHAPES OF IT, and this looks for both:

  A STATE WITH NO CASE AT ALL. Fifty-two states and however many cases; a
  state added without an arm falls through to the default, or to nothing.

  A CASE WITH NO EXIT. The arm runs for ever and never yields.

WHAT IT CANNOT SEE: an exit that is real but UNREACHABLE -- a `_rethink()`
behind a condition that is never true, or behind a timer nothing decrements.
That is a harder question than this answers, and it is worth knowing that the
cheap version does not cover it: a break written to test exactly that case went
undetected, correctly, and looked for a moment like a hole in the tool.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = (ROOT / "scripts/villager/villager.gd").read_text()

# The ways out. `_rethink` asks for a plan; `_choose` and `_decide` take one;
# assigning `state` moves along by itself; and a handful of helpers exist
# precisely to end an arm.
# `queue_free()` is the body ending without a death — a child gone to family
# elsewhere (ChildSafety). The failure below already names "ends the body" as a
# way out; this is the other spelling of it.
EXITS = ("_rethink()", "_choose()", "_decide()", "state = State.",
         "_set_out()", "die(", "scare(", "queue_free()")


def bodies(src):
    """Every function in a script, by name AND by Class.name, so an arm that
    delegates can be followed.

    Most arms are one line and the way out is inside it; a tool that could not
    see through that reported five perfectly healthy states as dead ends. It
    then did it again the day `_process_go_eat` was lifted out of Villager into
    a file of its own: the arm still ended itself, in a body this tool was no
    longer reading. Hence both keys — the qualified one is exact, so
    `VillagerFeeding.go` cannot be answered by somebody else's `go`.
    """
    out, name, lines = {}, "", []
    found = re.search(r"^class_name (\w+)", src, re.M)
    cls = found.group(1) if found else ""
    def keep():
        if not name:
            return
        out[name] = "\n".join(lines)
        if cls:
            out[cls + "." + name] = "\n".join(lines)
    for line in src.split("\n"):
        m = re.match(r"^(?:static )?func (\w+)\(", line)
        if m:
            keep()
            name, lines = m.group(1), []
            continue
        if name:
            lines.append(line)
    keep()
    return out


# EVERY FILE A VILLAGER'S ARM CAN DELEGATE INTO, and the villager files are
# taken as a DIRECTORY rather than as a list. The list was the bug: the day the
# eating code was lifted into a file of its own, the tool went on reading the
# five files somebody had thought of in 2025 and called a healthy state a dead
# end. A directory cannot be forgotten to be updated.
FUNCS = {}
for path in sorted((ROOT / "scripts/villager").glob("*.gd")):
    FUNCS.update(bodies(path.read_text()))
for rel in ("scripts/world/village_jobs.gd", "scripts/world/edubba.gd"):
    FUNCS.update(bodies((ROOT / rel).read_text()))

CALL = re.compile(r"(?:^|[^\w.])(([A-Z]\w*)\.)?(\w+)\(")


def reaches_an_exit(body):
    """Does this arm, or a helper it calls DIRECTLY, yield the body back to the
    decision-maker?

    ONE LEVEL, and that is a correction rather than a limitation. Following
    calls three deep through a file where everything calls everything found an
    exit from absolutely anywhere -- `_apply_gravity_only` reaches something
    that assigns `state` if you are willing to walk far enough -- so the check
    went from over-strict to unfalsifiable, which is the same failure the last
    three checks in this toolbox had in a different costume.

    One level is the real shape anyway: an arm is either a few lines that end
    themselves, or a single call to a `_process_*` helper that does. Nothing
    legitimate hides its exit two hops down."""
    if any(door in body for door in EXITS):
        return True
    for m in CALL.finditer(body):
        # The qualified name when the arm gave one, so a call to somebody
        # else's `go` cannot be answered by this one's.
        key = (m.group(2) + "." + m.group(3)) if m.group(2) else m.group(3)
        if key in FUNCS and any(door in FUNCS[key] for door in EXITS):
            return True
    return False

# Arms that END THE BODY or hand it to somebody else, and so cannot be expected
# to ask for a plan. Each says why, here, where it can be argued with.
BY_DESIGN = {
    "HELD": "in a god's hand; the hand decides when it is over",
    "FALLING": "in the air; landing is what ends it",
    "PINNED": "under a beast's jaws; the Mauling's clock is the only one",
    "DYING": "the window is run by _process_dying, above the match",
}


def code(text):
    """Source with its COMMENTS TAKEN OUT. A note about a thing is not the
    thing, and three checks in this toolbox have now tripped over that."""
    out = []
    for row in text.split("\n"):
        bare = row.split("#")[0].rstrip()
        if bare:
            out.append(bare)
    return "\n".join(out)


def states():
    block = SRC[SRC.index("enum State {"):]
    block = block[:block.index("}")]
    block = block[block.index("{") + 1:]
    return [w.strip() for w in block.replace("\n", " ").split(",") if w.strip()]


def arms():
    """State name -> the body of its case in the big match."""
    body = SRC[SRC.index("\tmatch state:"):]
    out, here, lines = {}, [], []
    for line in body.split("\n")[1:]:
        m = re.match(r"^\t\t(State\.[A-Za-z_, .]+|_):$", line.rstrip())
        if m:
            for name in here:
                out[name] = "\n".join(lines)
            lines = []
            here = [w.strip().replace("State.", "")
                    for w in m.group(1).split(",")]
            continue
        if line and not line.startswith("\t\t"):
            break                      # out of the match
        lines.append(line)
    for name in here:
        out[name] = "\n".join(lines)
    return out


ALL = states()
ARMS = arms()
fail = []

missing = [s for s in ALL if s not in ARMS and s not in BY_DESIGN]
print("%d states, %d with an arm of their own." % (len(ALL), len(ARMS) - (1 if "_" in ARMS else 0)))
print()
if missing:
    has_default = "_" in ARMS
    print("NO ARM AT ALL:")
    for name in missing:
        print("   %-18s %s" % (name, "falls to the default" if has_default
                               else "FALLS THROUGH TO NOTHING"))
        if not has_default:
            fail.append("State.%s has no case in the match and there is no "
                        "default: a villager in it does nothing at all, for "
                        "ever, while its hunger goes on climbing" % name)

stuck = []
for name in ALL:
    arm = ARMS.get(name)
    if arm is None or name in BY_DESIGN:
        continue
    if not reaches_an_exit(arm):
        stuck.append(name)

print("NO WAY OUT:" if stuck else "EVERY ARM HAS A WAY OUT.")
for name in stuck:
    print("   %-18s never asks for a new plan" % name)
    fail.append("State.%s runs for ever: nothing in its arm asks for a new "
                "plan, changes the state, or ends the body. A villager who "
                "enters it is alive, ticking, getting hungrier, and never "
                "going to decide anything again" % name)

print()
print("EXEMPT, because the body is not its own to end:")
for name, why in sorted(BY_DESIGN.items()):
    mark = "" if name in ARMS else "   (no arm)"
    print("   %-10s %s%s" % (name, why, mark))

# -- AND A GATE NOBODY CAN PASS --------------------------------------------
#
# VillagerNeeds.live gives a child energy and never takes any, so anything
# gating on a child's tiredness gates on a number that is always a hundred.
NEEDS = code((ROOT / "scripts/villager/villager_needs.gd").read_text())
child = NEEDS[NEEDS.index("if not who.is_adult():"):]
child = child[:child.index("return")]
spends = "who.energy = maxf" in child or "who.energy -=" in child
print()
print("A CHILD'S ENERGY %s." % ("rises and falls" if spends else "only ever rises"))

# THE GATE THAT PRECEDES GOING TO BED, which is not merely "a line mentioning
# the night". The first version of this took the WAKE-UP condition, a few
# hundred lines away, and reported on it confidently.
bed = ""
rows = code(SRC).split("\n")
for i, row in enumerate(rows[:-1]):
    if "is_night()" in row and "_go_sleep()" in rows[i + 1]:
        bed = row
        break
print("GOING TO BED reads: %s" % bed.strip())
if not spends and bed and "is_adult" not in bed and "Edubba" not in bed:
    fail.append("a child's energy only ever rises, and the rule that sends a "
                "villager to bed asks whether they are tired. Children never "
                "sleep — not once, in any village, ever — and every number "
                "involved is correct")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: every state has a way out, and every gate can be passed.")
