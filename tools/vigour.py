#!/usr/bin/env python3
"""WHETHER HE IS UP FOR ANYTHING.

Nothing in this creature said how ACTIVE it was. Its character said what it
liked doing and its welfare said what it could learn, and the only thing
standing for get-up-and-go was `laziness()`, which was `fat / 100`. Read that
the other way round: a starving creature has no fat, therefore no laziness,
therefore it is the keenest thing on the map. A creature wasting away was
modelled as full of beans.

    "I feel like active/lazy should be an axiom figured - not like the other
     axioms, but from how well he is kept (100 and 0 fatness BOTH read as lazy,
     6-50 is PEAK activity, with a sharp falloff below 5, and a gentle curve
     above 50 toward lazy.) Similarly, having 0 energy should make the creature
     very lazy. It's less of an independent stat, instead being entirely
     derived from the creature's self-care regimen."

So this file holds the curve to exactly that shape, and holds it to being
DERIVED -- the moment anything gives the creature an activity number of its
own, the thing the player is being asked to manage stops being the creature's
care and starts being a stat.

  BOTH ENDS READ LAZY. Nothing in reserve and stuffed to the gills are both
  torpid, and they are torpid for different reasons.
  SIX TO FIFTY IS FLAT, and it is the whole of an animal at its best.
  BELOW FIVE IT FALLS OFF A CLIFF; above fifty it slides gently.
  NO ENERGY IS NO ENERGY, whatever his condition -- it multiplies, so a spent
  creature is torpid at a perfect weight.
  AND IT IS SPENT, not merely computed: the mind's ballot reads it, and a
  torpid creature takes longer over nothing.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BODY = (ROOT / "scripts/creature/creature_body.gd").read_text()
CREATURE = (ROOT / "scripts/creature/creature.gd").read_text()
MIND = (ROOT / "scripts/creature/creature_mind.gd").read_text()


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


def number(name):
    found = re.search(r"^const %s := ([-\d.]+)" % name, BODY, re.M)
    return float(found.group(1)) if found else None


C = {n: number(n) for n in ["PEAK_FROM", "PEAK_TO", "GAUNT", "GAUNT_CURVE",
                            "STUFFED_LEFT", "STUFFED_CURVE", "SPENT_LEFT",
                            "RESTED_AT", "SPENT_CURVE"]}
fail = []
if any(v is None for v in C.values()):
    print("FAIL: the vigour curve's constants are gone from CreatureBody")
    sys.exit(1)


def from_reserve(fat):
    if fat < C["PEAK_FROM"]:
        return C["GAUNT"] + (fat / C["PEAK_FROM"]) ** C["GAUNT_CURVE"] * (1 - C["GAUNT"])
    if fat <= C["PEAK_TO"]:
        return 1.0
    return 1.0 - ((fat - C["PEAK_TO"]) / (100.0 - C["PEAK_TO"])) ** C["STUFFED_CURVE"] \
        * (1 - C["STUFFED_LEFT"])


def from_energy(e):
    return min(C["SPENT_LEFT"] + (max(e, 0.0) / C["RESTED_AT"]) ** C["SPENT_CURVE"]
               * (1 - C["SPENT_LEFT"]), 1.0)


def vigour(fat, e):
    return max(0.0, min(1.0, from_reserve(fat) * from_energy(e)))


FATS = [0, 2, 4, 5, 6, 12, 25, 40, 50, 60, 75, 90, 100]
print("WHAT IS IN RESERVE  " + "".join("%6d" % f for f in FATS))
print("up for it           " + "".join("%6.2f" % from_reserve(f) for f in FATS))
ENERGIES = [0, 5, 10, 20, 30, 40, 60, 100]
print("WHAT IS IN THE TANK " + "".join("%6d" % e for e in ENERGIES))
print("up for it           " + "".join("%6.2f" % from_energy(e) for e in ENERGIES))

# -- BOTH ENDS READ LAZY -----------------------------------------------------
peak = from_reserve((C["PEAK_FROM"] + C["PEAK_TO"]) / 2)
for label, at in [("nothing in reserve", 0.0), ("stuffed", 100.0)]:
    if from_reserve(at) > peak * 0.55:
        fail.append("a creature with %s reads %.2f against a peak of %.2f, so "
                    "it is not lazy at that end and the curve only has one"
                    % (label, from_reserve(at), peak))
# -- THE PLATEAU IS FLAT AND IT IS WHERE HE SAID ------------------------------
#
# The band is written out here, from the request, and NOT read from the
# constants it is checking. Measured across range(PEAK_FROM, PEAK_TO) it is
# flat by construction: narrow the plateau to a single point and the check
# sails through, which is how a test comes to certify whatever it finds.
BAND = (6.0, 50.0)          # "6-50 is PEAK activity"
flat = {round(from_reserve(f), 3) for f in range(int(BAND[0]), int(BAND[1]) + 1)}
if flat != {1.0}:
    fail.append("the creature is not simply at its best right across %d-%d "
                "(%d different readings in there, best %.2f) — that band was "
                "the whole of what peak condition means here"
                % (BAND[0], BAND[1], len(flat), max(flat)))
if from_reserve(BAND[0] - 1.0) >= 1.0 or from_reserve(BAND[1] + 10.0) >= 1.0:
    fail.append("the plateau does not end where it was meant to: %.2f just "
                "below it and %.2f ten past it, so it is not a band, it is "
                "everywhere" % (from_reserve(BAND[0] - 1.0), from_reserve(BAND[1] + 10.0)))
# -- A CLIFF BELOW FIVE, A SLIDE ABOVE FIFTY ---------------------------------
cliff = from_reserve(C["PEAK_FROM"]) - from_reserve(1.0)
slide = from_reserve(C["PEAK_TO"]) - from_reserve(C["PEAK_TO"] + 10.0)
print()
print("FALLING OFF THE BOTTOM costs %.2f in the first five; DRIFTING PAST THE "
      "TOP costs %.2f in the first ten." % (cliff, slide))
if cliff <= slide * 2.0:
    fail.append("starving costs %.2f and getting plump costs %.2f — the bottom "
                "was meant to be a cliff and the top a gentle curve, and these "
                "two are the same shape" % (cliff, slide))
# -- NO ENERGY IS NO ENERGY --------------------------------------------------
if from_energy(0.0) > 0.2 or vigour(25.0, 0.0) > 0.2:
    fail.append("a creature with nothing left reads %.2f at a perfect weight, "
                "so being run into the ground does not make it torpid"
                % vigour(25.0, 0.0))

print()
print("THE READINGS A PLAYER MEETS:")
for label, fat, e in [("starved and spent", 1, 5), ("lean and rested", 20, 90),
                      ("sleek, working", 35, 55), ("well fed, rested", 48, 95),
                      ("plump, rested", 70, 90), ("obese, rested", 95, 90),
                      ("obese, exhausted", 95, 8)]:
    v = vigour(fat, e)
    word = ("torpid" if v < 0.25 else "sluggish" if v < 0.5
            else "willing" if v < 0.8 else "tireless")
    print("   %-18s reserve %3d  energy %3d  ->  %.2f  (%s)" % (label, fat, e, v, word))

# -- AND IT IS DERIVED, AND IT IS SPENT --------------------------------------
own_stat = [r for r in code(BODY).split("\n")
            if re.match(r"var (vigour|activity|laziness)\b", r.strip())]
in_ballot = "body.laziness(energy)" in code(CREATURE)
dawdles = "body.dawdle(" in code(CREATURE)
reads_it = any('drive.get("lazy"' in r for r in body_of(MIND, "_drive_fit"))
print()
print("IT IS %s, AND IT %s."
      % ("derived from his care" if not own_stat else "A STAT OF ITS OWN",
         "steers what he does and how long he takes over it"
         if in_ballot and dawdles and reads_it else "IS COMPUTED AND IGNORED"))
if own_stat:
    fail.append("the body carries an activity variable of its own (%s) — this "
                "was to be derived from how he is kept, not another number to "
                "manage" % own_stat[0].strip())
if not in_ballot or not reads_it:
    fail.append("the creature's ballot no longer reads how up for it he is, so "
                "vigour is arithmetic nothing acts on")
if not dawdles:
    fail.append("nothing paces how long he takes over nothing, so a torpid "
                "creature is as busy as a keen one and merely prefers "
                "different things")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: both ends read lazy, six to fifty is flat, an empty tank is an "
      "empty tank — and all of it comes off how he has been kept.")
