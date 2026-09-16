#!/usr/bin/env python3
"""WHAT TWO HUNDRED VILLAGERS COST, PER FRAME, WITHOUT ANYBODY DECIDING ANYTHING.

Decisions are bounded. Spool serves a fixed number a frame and always has, so a
whole town re-deciding at once costs latency, not frame time. That means every
time the game is slow in a crowd, the cause is on the OTHER path -- the one
every villager runs every frame whether it is thinking or not.

That path is invisible. It is a dozen small methods calling a dozen more, and
any one of them can quietly start walking the town: `population()` did, through
`at_capacity`, through `_try_conceive`, from a state that half the village was
in at once. Nothing about that reads as expensive at any single call site. It
is only expensive when you multiply it by two hundred, sixty times a second.

So this walks the call graph from Villager._physics_process, following every
call it can resolve into the villager scripts and into Village, and reports
every function on that path that does an O(n) thing:

    get_nodes_in_group(...)   -- walks a global group
    my_villagers()            -- walks and prunes the town's roster
    Util.prune(...)           -- walks an array checking validity
    for ... in village.<...>  -- walks one of the town's lists

`_choose` and everything under it are NOT followed: that is the spooled path,
it is allowed to be expensive, and bounding it is what Spool is for.

LIMITS, honestly. This resolves calls by NAME, so it cannot see through
`call()`, through a Callable, or through a match on a state that only some
villagers are in. It will miss things. Everything it DOES find is genuinely on
the per-frame path, which is what makes it worth running.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"

# The files a villager's frame can reach into. Village is here because half of
# what a villager asks, it asks its town.
WATCHED = [
    "villager/villager.gd", "villager/villager_needs.gd",
    "villager/villager_look.gd", "villager/villager_breeding.gd",
    "villager/child_safety.gd", "villager/mauling.gd", "villager/militia.gd",
    "world/village.gd", "world/village_jobs.gd", "world/village_hive.gd",
    "world/village_watch.gd", "world/village_party.gd", "world/agitation.gd",
]
# Where the frame begins, and where it is allowed to stop being cheap.
ENTRY = "_physics_process"
SPOOLED = {"_choose", "_pick_job", "_start_job", "idle", "_slots"}

WALKS = [
    (re.compile(r"get_nodes_in_group\("), "walks a global group"),
    (re.compile(r"my_villagers\(\)"), "walks and prunes the roster"),
    (re.compile(r"Util\.prune\("), "walks an array for validity"),
    # The town's actual LISTS, named. `for x in village.something()` caught
    # `allowed_food_types()`, which is three enum values -- a regex that flags
    # anything reached through `village.` is a regex that cries wolf.
    (re.compile(r"for \w+ in [\w.]*\.(?:houses|farms|workshops|tamed_animals|"
                r"_roster)\b"), "walks a town list"),
]


def functions(text):
    """name -> (body, is_static) for every function in one script."""
    out = {}
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"^(static )?func (\w+)\(", lines[i])
        if not m:
            i += 1
            continue
        name = m.group(2)
        body = []
        i += 1
        while i < len(lines) and (lines[i] == "" or lines[i].startswith(("\t", " "))):
            body.append(lines[i])
            i += 1
        out[name] = "\n".join(body)
    return out


# A function is (file, name). Keying on the name alone merged VillagerNeeds.tick
# with VillageWatch.tick and Militia.tick -- three different functions, one of
# which is per-villager and two of which are per-VILLAGE -- and reported six of
# the village's own once-a-frame scans as if every villager ran them.
ALL = {}
OWNER = {}          # class_name -> file
for rel in WATCHED:
    path = SCRIPTS / rel
    if not path.exists():
        sys.exit("crowd.py watches %s and it is not there" % rel)
    text = path.read_text()
    m = re.search(r"^class_name (\w+)", text, re.M)
    if m:
        OWNER[m.group(1)] = rel
    for name, body in functions(text).items():
        ALL[(rel, name)] = body

# `Thing.method(` is resolved through class_name; a bare `method(` is resolved
# in the file it was written in, which is what GDScript itself does.
QUALIFIED = re.compile(r"\b([A-Z]\w*)\.(\w+)\(")
BARE = re.compile(r"(?:^|[^\w.])(\w+)\(")
EXEMPT = "## O(N) BY DESIGN:"


def calls_from(rel, body):
    out = set()
    for owner, name in QUALIFIED.findall(body):
        if owner in OWNER and (OWNER[owner], name) in ALL:
            out.add((OWNER[owner], name))
    for name in BARE.findall(body):
        if (rel, name) in ALL:
            out.add((rel, name))
    return out


reached = {}
start = ("villager/villager.gd", ENTRY)
stack = [(start, [ENTRY])]
seen = set()
while stack:
    key, route = stack.pop()
    if key in seen:
        continue
    seen.add(key)
    body = ALL.get(key)
    if body is None:
        continue
    reached[key] = route
    for nxt in calls_from(key[0], body):
        if nxt in seen or nxt[1] in SPOOLED:
            continue
        stack.append((nxt, route + [nxt[1]]))

# The exemption, in the file rather than in a list here: a function that walks
# the town on purpose and knows why says so above itself.
EXEMPTED = set()
for rel in WATCHED:
    text = (SCRIPTS / rel).read_text()
    for chunk in text.split("\n" + EXEMPT):
        head = chunk.split("\n")
        for line in head[:12]:
            m = re.match(r"^(?:static )?func (\w+)\(", line)
            if m:
                EXEMPTED.add((rel, m.group(1)))
                break

fail = []
found = []
for key, route in sorted(reached.items()):
    for pattern, what in WALKS:
        if pattern.search(ALL[key]):
            found.append((key, what, route, key in EXEMPTED))
            break

print("FROM Villager.%s, %d functions are reachable every frame."
      % (ENTRY, len(reached)))
print("(%s and everything under them are excluded -- that is the spooled path.)"
      % ", ".join(sorted(SPOOLED)))
print()
if not found:
    print("NOTHING ON THE PER-FRAME PATH WALKS THE TOWN.")
else:
    print("THESE DO, and each one is multiplied by every villager in the town:")
    for (rel, name), what, route, excused in found:
        mark = "  (by design)" if excused else ""
        print("   %-34s %-28s %s%s"
              % (rel.split("/")[-1] + ":" + name, what,
                 " -> ".join(route[1:]) or "(entry)", mark))
        if not excused:
            fail.append("%s.%s is on the per-frame path and %s: at two hundred "
                        "villagers that is the frame, not the decision"
                        % (rel.split("/")[-1], name, what))
print()
print("A function that walks the town on purpose says so above itself with")
print("   %s <why>" % EXEMPT)

# -- AND THE CONSTANT FACTOR, WHICH IS THE OTHER HALF --------------------
#
# Nothing walking the town is necessary and not sufficient. Two hundred bodies
# each doing a fixed amount of work is still two hundred times that work, and
# `sim_stride` used to hand full rate to every one of them precisely when they
# were all standing together: a city fits inside the 130m near band.
UTIL = (SCRIPTS / "util.gd").read_text()
CROWD = (SCRIPTS / "crowd.gd").read_text()


def number(name, text, where):
    m = re.search(r"^const %s(?::\s*Array\[int\])?\s*:?=\s*\[?([0-9, ]+)\]?"
                  % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return [int(v) for v in m.group(1).split(",") if v.strip()]


at_full = number("AT_FULL", CROWD, "crowd.gd")
most = number("STRIDE_MOST", CROWD, "crowd.gd")[0]

print()
near_band = re.search(r"Crowd\.counted_near\(\)", UTIL) is not None
print("THE NEAR BAND %s itself."
      % ("counts" if near_band else "DOES NOT COUNT"))
if not near_band:
    fail.append("Util.sim_stride does not consult Crowd: the near band hands "
                "full rate to every body in it, and a city fits inside the near "
                "band -- which is the one case the band exists to protect")

middling = at_full[1] if len(at_full) > 1 else at_full[0]
print()
print("WHAT A FRAME CARRIES at the middling tier (%d at full rate, thinning to"
      % middling)
print("   one in %d at most):" % most)
for bodies in (30, 60, 120, 200, 400):
    stride = 1 if bodies <= middling else min(1 + (bodies - 1) // middling, most)
    print("   %3d bodies  ->  stride %d  ->  %3d ticked a frame"
          % (bodies, stride, -(-bodies // stride)))
holds_to = middling * most
print()
print("The budget holds to %d bodies. Past that the frame grows again, which is"
      % holds_to)
print("   a city to solve elsewhere rather than a stride to raise further.")
if holds_to < 200:
    fail.append("the crowd budget stops holding at %d bodies, and the town that "
                "prompted all this had more than two hundred" % holds_to)

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: a villager's frame is O(1) in the size of its town, and a crowd "
      "thins itself to fit.")
