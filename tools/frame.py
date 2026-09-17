#!/usr/bin/env python3
"""A SLOW DEVICE MUST NOT MAKE ITSELF SLOWER, AND SOMEBODY MUST BE ABLE TO SEE WHY.

A phone reported 133.1ms a frame -- seven and a half pictures a second -- and
there was no way to tell from here which half of the machine was spending it.
Everything after that question is guessing, and guessing is how a week goes into
making the fast half faster.

So two things ship together and this file guards both.

THE INSTRUMENT. FrameMeter prints the split: what GDScript cost, what was left
over for the driver and the fragment pass, and -- the number this was built for
-- how many physics ticks went into one drawn picture. It has to be openable on
a phone, which is the only machine whose frame time anybody needs to look at,
and F7 is not a key a phone has.

THE HOLE. Godot runs physics on a fixed clock: every drawn frame it works out
how many ticks it owes and runs them all, up to `max_physics_steps_per_frame`.
At the engine defaults -- sixty a second, ceiling of eight -- a frame of 133ms
owes eight, and runs eight: every villager, every animal, every rigid body,
simulated eight times for one picture. Which makes the frame longer, which owes
more ticks. It is not a slope, it is a hole, and the arithmetic below says how
deep.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
QUALITY = (ROOT / "scripts/quality.gd").read_text()
METER = (ROOT / "scripts/ui/frame_meter.gd").read_text()
HUD = (ROOT / "scripts/ui/hud.gd").read_text()
MAIN = (ROOT / "scripts/main.gd").read_text()


def code(text):
    """Source with its comments taken out. A note about a thing is not it."""
    return "\n".join(r.split("#")[0].rstrip() for r in text.split("\n")
                     if r.split("#")[0].strip())


def body_of(text, name):
    src = code(text)
    head = "func %s(" % name
    if head not in src:
        return []
    out = []
    for row in src[src.index(head):].split("\n")[1:]:
        if row and not row.startswith(("\t", " ")):
            break
        out.append(row)
    return out


def number(text, name):
    found = re.search(r"^const %s := ([-\d.]+)" % name, text, re.M)
    return float(found.group(1)) if found else None


fail = []

hz = number(QUALITY, "PHYSICS_HZ")
most = number(QUALITY, "STEPS_MOST")
if None in (hz, most):
    print("BROKEN: the fixed clock is not set anywhere in Quality")
    sys.exit(1)


def steps(frame_ms, rate, ceiling):
    """What Godot runs: the ticks owed since the last frame, up to the ceiling."""
    return min(math.floor(frame_ms / (1000.0 / rate)) or 1, ceiling)


# -- THE HOLE, MEASURED ------------------------------------------------------
print("HOW MANY TIMES THE WHOLE WORLD IS SIMULATED FOR ONE PICTURE:")
print("   %-12s %-22s %-22s" % ("frame", "60 Hz, ceiling 8 (was)",
                                "%d Hz, ceiling %d (now)" % (hz, most)))
for ms in (16.7, 33.3, 50.0, 66.7, 100.0, 151.0, 200.0):
    was = steps(ms, 60, 8)
    now = steps(ms, hz, most)
    print("   %-12s %-22s %-22s%s"
          % ("%.1f ms" % ms,
             "x%d%s" % (was, "  PINNED" if was >= 8 else ""),
             "x%d%s" % (now, "  pinned" if now >= most else ""),
             "   <- the desktop" if abs(ms - 151.0) < 0.1 else ""))
if most > 3:
    fail.append("the step ceiling is %d, so a machine that falls behind "
                "simulates the world %d times for one picture and every extra "
                "millisecond buys it more work — a DESKTOP was found pinned at "
                "the engine default of eight" % (most, most))
if hz >= 60:
    fail.append("the world still runs %d physics ticks a second — nothing in "
                "this game needs sixty, and the hand was taken off the physics "
                "tick long ago precisely so it would not wait for one" % hz)
# ONE CLOCK, NOT ONE PER MACHINE. The handheld-only version was written on the
# argument that a desk machine never falls behind, and a desktop screenshot at
# 151ms with the steps pinned at eight disproved it.
if any("has_feature" in r for r in body_of(QUALITY, "_set_the_clock")):
    fail.append("the fixed clock is still set per machine — the hole is not a "
                "property of slow hardware, it is a fixed clock with a high "
                "ceiling meeting a world with four hundred bodies in it, and a "
                "fast machine reaches it with a bigger world")

# WHAT IT IS WORTH, as a share of the physics work in a pinned frame. The split
# between the fixed work and the per-step work is exactly what nobody knows yet
# -- which is why the meter ships alongside this -- so it is shown for a range
# of splits rather than asserted at one.
print()
print("WHAT THAT IS WORTH at the desktop's 151.0ms, by how much is per-step.")
print("(The split is the thing nobody knows yet. That is what the meter is for.)")
print("   %-16s %-14s %-14s %s" % ("physics share", "one step", "new frame", "fps"))
best = 0.0
for share in (0.3, 0.5, 0.7):
    fixed = 151.0 * (1.0 - share)
    per_step = 151.0 * share / 8.0
    # Settle the loop: the frame decides the steps which decide the frame.
    frame = 151.0
    for _ in range(40):
        frame = fixed + steps(frame, hz, most) * per_step
    best = max(best, 1000.0 / frame)
    print("   %-16s %-14s %-14s %.1f"
          % ("%d%%" % (share * 100), "%.1f ms" % per_step,
             "%.0f ms" % frame, 1000.0 / frame))
print()
print("   ...so the clock alone is worth roughly %.1fx from 6.6 fps."
      % (best / 6.6))

# -- THE INSTRUMENT ----------------------------------------------------------
print()
says = {
    "the script/draw split": "TIME_PROCESS",
    "the physics time": "TIME_PHYSICS_PROCESS",
    "the draw calls": "RENDER_TOTAL_DRAW_CALLS_IN_FRAME",
    "when they are pinned": "max_physics_steps_per_frame",
}
print("THE METER REPORTS:")
for what, needle in says.items():
    there = needle in code(METER)
    print("   %-24s %s" % (what, "yes" if there else "NO"))
    if not there:
        fail.append("the frame meter does not report %s, which is one of the "
                    "things it exists to answer" % what)

# THE STEPS ARE COUNTED IN _physics_process, and counted means INCREMENTED.
# `_ticks` appearing in this file says nothing — it is declared once and zeroed
# once whether or not anything ever adds to it, so looking for the NAME is a
# check that cannot fail. Look for the statement.
ticked = any(re.search(r"_ticks (\+=|= _ticks \+)", r)
             for r in body_of(METER, "_physics_process"))
print("   %-24s %s" % ("the steps a frame", "yes" if ticked else "NO"))
if not ticked:
    fail.append("nothing in the meter's _physics_process counts a tick, so the "
                "steps-a-frame figure — the number it was built for — is zero "
                "for ever and reads as a healthy device")

# -- THE BILL, AND WHETHER ANYTHING IS GROWING -------------------------------
#
# The phone came back with ninety-one milliseconds in `_process` and none in the
# draw, which rules out the GPU and leaves forty classes. And it started near
# twenty frames and decayed to ten over one sitting, which is a different fact
# again: a game that gets slower the longer it is played is a game where
# something is GROWING. So the meter has to say what each numerous class cost
# AND HOW MANY OF THEM RAN, because a count climbing alongside its cost is the
# whole diagnosis.
LEDGER = (ROOT / "scripts/ledger.gd").read_text()
clocked = []
for path in sorted((ROOT / "scripts").rglob("*.gd")):
    text = code(path.read_text())
    for name in re.findall(r'Ledger\.open\(&"(\w+)"', text):
        clocked.append(name)
print()
print("CLOCKED BY NAME: %s" % (", ".join(sorted(clocked)) if clocked else "NOBODY"))
if len(clocked) < 8:
    fail.append("only %d classes clock themselves — the ledger cannot point at "
                "anything it was not told to measure, and a bill that lists two "
                "lines always blames one of them" % len(clocked))
if len(set(clocked)) != len(clocked):
    fail.append("two classes report into the ledger under the same name, so "
                "their costs are added together and neither can be read")

# A CLOCK IS OPENED AT THE TOP OF THE METHOD AND NOWHERE ELSE. Opened lower
# down, everything above it is charged to whoever ran before — which is a class
# being billed for another class's work, and it reads as a finding.
for path in sorted((ROOT / "scripts").rglob("*.gd")):
    rows_here = code(path.read_text()).split("\n")
    for n, row in enumerate(rows_here):
        if "Ledger.open(" not in row:
            continue
        above = rows_here[n - 1] if n else ""
        if not re.match(r"func _(physics_)?process\(", above.strip()):
            fail.append("%s:%d opens a ledger clock somewhere other than the "
                        "first line of a _process — everything above it is "
                        "billed to whichever class ran before"
                        % (path.name, n + 1))

# -- THE HOT QUESTION MUST NOT BE A WALK ------------------------------------
#
# `Herd.alive()` walked every row in the book. It is asked twenty-nine times in
# that file alone and from seven others, and one of those is `bolt_from`, which
# EVERY herd in the world runs eleven times a second for as long as a fireball
# is in the air. Forty-seven herds of a hundred and sixty is seven and a half
# thousand rows per call. "I see it when I throw down a fireball with 100+
# animals around" is that sentence, said from the other end.
HERD = (ROOT / "scripts/animals/herd.gd").read_text()
counting = body_of(HERD, "alive")
# The walk is allowed, ONCE, behind the staleness guard — that is what makes it
# a cache. What is not allowed is a walk on the common path. Measured by indent:
# the `for` has to sit deeper than the `if _living < 0:` that admits it.
guard = next((i for i, r in enumerate(counting) if "_alive_count < 0" in r), None)
walks = False
for i, r in enumerate(counting):
    if not (r.strip().startswith("for ") and "_members" in r):
        continue
    deep = len(r) - len(r.lstrip("\t"))
    if guard is None or i < guard \
            or deep <= len(counting[guard]) - len(counting[guard].lstrip("\t")):
        walks = True
cached = any("_alive_count" in r for r in counting)
print()
print("Herd.alive() %s." % ("is remembered, and walks only when stale"
                            if cached and not walks else "WALKS THE BOOK"))
if walks:
    fail.append("Herd.alive() walks every row every time it is asked, and it is "
                "asked from `bolt_from` — which every herd in the world runs "
                "eleven times a second while a fireball is in the air")
if not cached:
    fail.append("Herd.alive() keeps no remembered count at all")

# AND EVERY HAND THAT CHANGES THE BOOK SAYS SO. A cache nobody invalidates is
# not a cache, it is a number that was true once — a herd whose count drifts for
# the rest of the session, reported as fact by the tag over its head.
mutations = 0
told = 0
rows_herd = code(HERD).split("\n")
for n, row in enumerate(rows_herd):
    if not re.search(r'\["dead"\]\s*=\s*true|_members\s*=[^=]|_members\.append|_members\.clear', row):
        continue
    mutations += 1
    if any("_recount()" in r for r in rows_herd[n:n + 12]):
        told += 1
print("   %d of %d hands that change the book say so." % (told, mutations))
if told < mutations:
    fail.append("%d place(s) in Herd change the book without marking the count "
                "stale — a cache nobody invalidates is a number that was true "
                "once, and the tag over the herd goes on reporting it"
                % (mutations - told))

# AND A MISSED HAND HEALS. Fourteen places mark the count stale, and fourteen is
# a number that only shrinks with confidence — the fifteenth is written by
# somebody who has not read that file. A cache nobody invalidates is not wrong
# loudly; it is a herd whose tag, breeding, capacity and drove all quietly agree
# on a number that was true once. The season throws it away regardless.
healed = any("_recount()" in r for r in body_of(HERD, "_reckon"))
print("   a missed mark %s." % ("heals within a season" if healed
                                else "IS PERMANENT"))
if not healed:
    fail.append("nothing recounts the herd from scratch on its own clock, so "
                "the first hand that changes the book without saying so leaves "
                "that herd's count wrong for the rest of the session")

# AND THE NUMEROUS CLASSES ON THE PHYSICS TICK ARE ALL CLOCKED. An unclocked one
# interleaved with a clocked one is billed to its neighbour: Animal came back at
# 141.7ms out of a physics total of 33.2, which was Animal plus the two hundred
# and sixty villagers between one beast and the next.
for who, path in (("Animal", "scripts/animals/animal.gd"),
                  ("Villager", "scripts/villager/villager.gd")):
    if 'Ledger.open(&"%s")' % who not in code((ROOT / path).read_text()):
        fail.append("%s runs on the physics tick in its hundreds and is not "
                    "clocked, so whichever clocked class it is interleaved with "
                    "is billed for it" % who)

# AND IT IS ONLY ON WHILE SOMEBODY IS READING IT. A profiler left running is
# overhead every player pays for ever, to answer a question nobody is asking.
switched = [r.strip() for r in code(METER).split("\n") if "Ledger.on" in r]
if not switched or not all("visible" in r for r in switched):
    fail.append("the ledger is switched on by %s rather than by whether the "
                "meter is open — a profiler nobody is reading is overhead every "
                "player pays for ever"
                % (switched[0] if switched else "nothing"))

# -- AND THE ENGINE'S OWN WORK IS BILLED TO THE ENGINE -----------------------
#
# A clock is shut by the next one opening, so whatever ran LAST in a physics
# step keeps its clock through the engine's solve — collision, the heightmaps,
# every CharacterBody3D's move — and is billed for all of it. That is how
# `Animal 116.3ms` came back under a physics total of 84.9ms: a part larger than
# the whole, because it was not Animal, it was Animal plus the solver.
last_in_step = re.search(r"process_physics_priority = (\w+)", code(METER))
solver_row = any("ENGINE_ROW" in r for r in body_of(METER, "_physics_process"))
priority = number(METER, "ENGINE_LAST")
print()
print("THE ENGINE'S OWN WORK is billed %s."
      % ("to itself" if last_in_step and solver_row
         else "TO WHICHEVER CLASS RAN LAST"))
if not solver_row:
    fail.append("nothing opens a clock for the engine's own physics work, so "
                "the solver is charged to whichever class happened to run last "
                "and the biggest row on the bill is an artefact")
if not last_in_step or not priority or priority <= 0:
    fail.append("the meter does not put itself last in the physics step, so the "
                "clock it opens for the engine shuts somebody else's early and "
                "bills THEM for the rest of the step instead")

# AND NOTHING ELSE MAY CLAIM THAT SLOT. Two nodes fighting to be last is one of
# them silently not being it.
others = []
for path in sorted((ROOT / "scripts").rglob("*.gd")):
    if path.name == "frame_meter.gd":
        continue
    if "process_physics_priority" in code(path.read_text()):
        others.append(path.name)
if others:
    fail.append("%s also sets a physics priority — two nodes claiming the last "
                "slot means one of them is not last, and the bill quietly goes "
                "back to blaming whoever is" % ", ".join(others))

# AND THE PAGE IS TURNED, which is also what shuts the last clock of the frame.
turned = "Ledger.turn_the_page()" in code(METER)
shuts = any("shut()" in r for r in body_of(LEDGER, "turn_the_page"))
if not turned or not shuts:
    fail.append("the ledger's page is never turned, or turning it does not shut "
                "the clock left open by the last class of the frame — which is "
                "then charged the whole gap to the next frame")

# AND THE COUNT IS REPORTED ALONGSIDE THE COST.
bills = "row[2]" in code(METER) and "Ledger.rows()" in code(METER)
# NOT THE NAME `counted` — the COMPARISON. A meter that reads the total and
# prints it is not a meter that can tell you its rows are absorbing the solver;
# it has to say so when the bill passes what the engine charged.
gap = any("Ledger.counted()" in r for r in body_of(METER, "_readout")) \
    and any(re.search(r"billed > scripted", r) for r in body_of(METER, "_readout"))
grows = "OBJECT_ORPHAN_NODE_COUNT" in code(METER)
print("THE METER PRINTS the bill: %s, the unaccounted gap: %s, orphans: %s"
      % ("yes" if bills else "NO", "yes" if gap else "NO",
         "yes" if grows else "NO"))
if not bills:
    fail.append("the meter does not print how many of each class ran, so a "
                "population that is growing looks exactly like code that got "
                "slower")
if not gap:
    fail.append("the meter does not compare the bill against what the engine "
                "charged, so it cannot tell you when its own rows are absorbing "
                "the solver and each other — which is how `Animal 141.7ms` was "
                "printed under a physics total of 33.2")
if not grows:
    fail.append("the meter does not report orphaned nodes, which is the one "
                "counter that says outright whether something is being leaked")

# AND THE FRAME IS MEASURED ON THE WALL CLOCK. `delta` has been through
# Engine.time_scale, which this game runs at 0.75 while a rune is drawn — so a
# steady frame reads a quarter faster the moment anybody casts, and the script
# time exceeds the frame it is part of.
real = any("get_ticks_usec()" in r for r in body_of(METER, "_process"))
print("THE FRAME IS TIMED on %s." % ("the wall clock" if real else "`delta` — WORLD TIME"))
if not real:
    fail.append("the meter times the frame with `delta`, which has been through "
                "Engine.time_scale — so it reports a faster device the moment a "
                "rune is drawn, and the script time comes out larger than the "
                "frame it is part of")

# AND IT OPENS ON A PHONE. F7 is not a key a phone has, and a phone is the only
# machine whose frame time anybody needs to look at.
by_key = "toggle_frames" in code(MAIN) and "toggle_frames" in code(HUD)
by_hand = any("_frames_button" in r and "pressed.connect" in r
              for r in code(HUD).split("\n"))
print()
print("IT OPENS: %s%s" % ("by key" if by_key else "NOT BY KEY",
                          ", and by a button" if by_hand else ", AND BY NOTHING ELSE"))
if not by_key:
    fail.append("the frame meter has no key bound to it")
if not by_hand:
    fail.append("the frame meter can only be opened with a keyboard — which is "
                "the one thing the device it was built to measure does not have")

# AND IT COSTS ALMOST NOTHING TO LEAVE OPEN. A readout rewritten every frame is
# string formatting and a Label relayout inside the frame it is measuring.
every = number(METER, "EVERY")
rewrites = any("_next" in r for r in body_of(METER, "_process"))
print("IT REWRITES every %.1fs%s" % (every or 0.0,
                                     "" if rewrites else " — NO, EVERY FRAME"))
if not every or every < 0.15 or not rewrites:
    fail.append("the meter rewrites its readout every frame, so it is string "
                "formatting and a label relayout inside the frame it claims to "
                "be measuring")

# The counting must NOT be behind the visibility check, or the averages are
# wrong for the first half-second after it is opened — which is the half-second
# somebody holding a phone actually reads.
counts = body_of(METER, "_process")
hidden = next((i for i, r in enumerate(counts) if "if not visible:" in r), None)
tallied = next((i for i, r in enumerate(counts) if "_steps_seen = " in r), None)
print("IT COUNTS %s it is open."
      % ("whether or not" if hidden is not None and tallied is not None
         and tallied < hidden else "ONLY WHILE"))
if hidden is None or tallied is None or tallied > hidden:
    fail.append("the meter only counts while it is open, so every number in it "
                "is wrong for the first moments after it is opened — which is "
                "when somebody holding a phone reads it")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: the clock cannot run away, and the frame can be read on the device.")
