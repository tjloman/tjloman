#!/usr/bin/env python3
"""A FLEET, NOT A SINGULARITY.

    "Screenshots show boats all going to the same point... they need to spread
     out in the water, not all occupy the same singularity."

A harbour works out where the fishing is once, off the end of its own jetty,
and caches it. That part is right -- it is the same bay for everybody, and
probing it per boat would be terrain reads for an answer that does not change.
What was wrong was handing that one spot to every hull it ever built: three
boats rowed to the same square metre and sat inside one another, which from the
shore is a single flat slab where a village's entire fishing industry should
be.

Two things fix it and they cover different failures:

  A BERTH OF ONE'S OWN, dealt out by the harbour. A phyllotaxis -- each boat
  turned by the golden angle from the last and set a little further out, the
  way a sunflower packs seeds without any of them touching. It needs no
  knowledge of where the other boats actually are, which is what makes it safe
  to hand out one at a time over the life of a town.

  AND GIVING WAY, which covers everything the dealing cannot know about: a
  second harbour fishing the same bay, a boat thrown across the map and
  re-moored where it came down, and the jetty itself, where moorings are two
  metres apart by design.

THE CASE THAT MATTERS MOST is two boats at EXACTLY the same position, because
there is no direction between them to push along. That is not a hypothetical --
it is what the shared spot produced every single time, and it is the case a
separation rule is most likely to be asked about and least likely to have been
written for.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WATERS = (ROOT / "scripts/world/waters.gd").read_text()
BOAT = (ROOT / "scripts/world/fishing_boat.gd").read_text()
SHOP = (ROOT / "scripts/world/workshop.gd").read_text()


def code(text):
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
APART = number(WATERS, "APART")
GOLDEN = number(WATERS, "GOLDEN")
CLEARS = number(BOAT, "CLEARS")
GIVES_WAY = number(BOAT, "GIVES_WAY")
MOST = number(SHOP, "BOATS_MOST")
HULL = 4.0          # a boat is about four metres of hull

# -- A BERTH OF ONE'S OWN ----------------------------------------------------
def berth(which):
    if which <= 0:
        return (0.0, 0.0)
    angle = which * GOLDEN
    reach = APART * math.sqrt(which)
    return (math.cos(angle) * reach, math.sin(angle) * reach)


print("WHERE A FLEET SITS, berth by berth:")
spots = [berth(i) for i in range(8)]
for i, p in enumerate(spots):
    print("   boat %d  %6.1f, %6.1f  (%.1fm out from the fishing)"
          % (i, p[0], p[1], math.hypot(*p)))
worst = min(math.dist(a, b) for i, a in enumerate(spots) for b in spots[i + 1:])
print("   the closest two of eight are %.1fm apart; a hull is about %.0fm."
      % (worst, HULL))
if worst < HULL:
    fail.append("two of eight berths are %.1fm apart and a hull is %.0fm, so "
                "boats still overlap — the spread has stopped spreading"
                % (worst, HULL))

# -- AND THE HARBOUR DEALS THEM OUT ------------------------------------------
launching = body_of(SHOP, "_launch")
deals = any("Waters.a_berth(" in r for r in launching)
shared = [r for r in launching if re.search(r"grounds = _grounds\b", r)]
print()
print("THE HARBOUR %s."
      % ("deals each hull its own berth" if deals and not shared
         else "STILL HANDS EVERY HULL THE SAME SPOT"))
if not deals or shared:
    fail.append("_launch gives every boat the harbour's one cached fishing "
                "spot (%s), which is the singularity itself — three hulls in "
                "the same square metre"
                % (shared[0].strip() if shared else "no a_berth call"))

# -- AND GIVING WAY ----------------------------------------------------------
rowing = body_of(BOAT, "_row")
leans = any("_give_way(" in r for r in rowing)
giving = body_of(BOAT, "_give_way")
handles_pile = any("apart < 0.01" in r for r in giving)
print("A BOAT %s, and two in exactly the same place %s."
      % ("leans out of the way of the others" if leans else "ROWS THROUGH THEM",
         "come apart" if handles_pile else "DIVIDE BY ZERO AND STAY THERE"))
if not leans:
    fail.append("nothing keeps boats apart while they row, so the berths are "
                "the only thing between a second harbour's fleet and this "
                "one's, and they know nothing about each other")
if not handles_pile:
    fail.append("two boats at exactly the same position have no direction "
                "between them, and _give_way does not say what to do about it "
                "— which is the one arrangement the old bug produced every "
                "single time")

# -- THE PILE COMES APART, MEASURED ------------------------------------------
#
# The state the old code actually shipped: a whole fleet on one spot. Rowed
# forward with nothing but the separation, because that is what has to get them
# out of it -- their berths are all the same point in this test on purpose.
print()
print("A FLEET OF %d STARTED IN A HEAP, given only the leaning:" % MOST)
boats = [[0.0, 0.0] for _ in range(int(MOST))]
bearings = [i * 1.13 for i in range(int(MOST))]      # each hull's own, as in the game
for tick in range(600):                              # ten seconds at 60Hz
    pushes = []
    for i, a in enumerate(boats):
        push = [0.0, 0.0]
        for j, b in enumerate(boats):
            if i == j:
                continue
            dx, dz = a[0] - b[0], a[1] - b[1]
            gap = math.hypot(dx, dz)
            if gap >= CLEARS:
                continue
            if gap < 0.01:
                push[0] += math.cos(bearings[i]) * CLEARS
                push[1] += math.sin(bearings[i]) * CLEARS
            else:
                push[0] += dx / gap * (CLEARS - gap)
                push[1] += dz / gap * (CLEARS - gap)
        pushes.append(push)
    for a, push in zip(boats, pushes):
        a[0] += push[0] * GIVES_WAY / 60.0
        a[1] += push[1] * GIVES_WAY / 60.0
    if tick in (59, 179, 599):
        least = min(math.dist(a, b) for i, a in enumerate(boats)
                    for b in boats[i + 1:])
        print("   after %2ds: the closest two are %.1fm apart" % ((tick + 1) / 60, least))
settled = min(math.dist(a, b) for i, a in enumerate(boats) for b in boats[i + 1:])
if settled < HULL:
    fail.append("a fleet started in a heap is still %.1fm from nose to nose "
                "after ten seconds, and a hull is %.0fm — the leaning does not "
                "get them out of the pile it was written for" % (settled, HULL))

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: every hull gets water of its own, and a heap comes apart on its "
      "own within seconds.")
