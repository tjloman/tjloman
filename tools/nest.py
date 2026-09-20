#!/usr/bin/env python3
"""SOMEWHERE TO BE, FROM THE BEGINNING.

A nest was something a village came to deserve: converted, firm in its belief
past 45, with no house already going up, and ten stone in a granary that starts
with three. That is right for the second one and wrong for the first, because
by the time it is earned the creature has already spent its whole childhood
with nowhere of its own.

    "The first village built should immediately start building a nest."

And it has stopped being a shrine with a dashboard on it. It is where he
sleeps, where the village dances, where his way through the world stands, and —
once he can be knocked down — where the earth puts him back down. Every one of
those makes it an ANCHOR, and an anchor a player can burn off the map is a
player who can put their own creature beyond the reach of everything that mends
it.

So, four claims:

  THE FIRST ONE IS NOT EARNED. The player's own village wants it at once,
  without conversion, belief or an idle build queue standing in the way.

  AND IT CAN PAY FOR IT. A village that wants a thing it cannot afford is a
  village standing about looking keen. The granary begins with three stone and
  a nest is cut from ten, so the makings are part of the founding.

  ONE DOOR FOR WHAT IT COSTS. The wanting and the raising both used to carry
  their own copy of the price, which is two numbers to keep in step.

  AND IT CANNOT BE BURNT AWAY. It chars, the faces blacken, the bar shows it,
  and it stands.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NEST = (ROOT / "scripts/world/creature_nest.gd").read_text()
VILLAGE = (ROOT / "scripts/world/village.gd").read_text()
VILLAGER = (ROOT / "scripts/villager/villager.gd").read_text()
STORE = (ROOT / "scripts/world/food_store.gd").read_text()
AFFORDS = (ROOT / "scripts/affords.gd").read_text()


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
LUMBER = number(NEST, "LUMBER")
STONE = number(NEST, "STONE")
SCORCHED = number(NEST, "SCORCHED")
if LUMBER is None or STONE is None:
    print("FAIL: CreatureNest no longer says what a nest costs")
    sys.exit(1)

# -- THE FIRST ONE IS NOT EARNED ---------------------------------------------
wanting = body_of(NEST, "wanted_by")
at_once = False
for i, row in enumerate(wanting):
    if "town.is_player_home" in row:
        at_once = any("return true" in later for later in wanting[i:i + 3])
earned = any("town.belief" in r for r in wanting)
print("THE FIRST VILLAGE %s, and every other one %s."
      % ("starts at once" if at_once else "MUST EARN ITS NEST TOO",
         "still earns it" if earned else "NOW GETS ONE FOR NOTHING"))
if not at_once:
    fail.append("the player's own village is not exempted from the belief and "
                "conversion gates, so the creature spends its childhood with "
                "nowhere of its own while a meter fills")
if not earned:
    fail.append("no village earns a nest any more — the first one being free "
                "was the point, and every one being free empties the whole "
                "conversion beat")

# -- AND IT CAN PAY FOR IT ---------------------------------------------------
starts_with = {"lumber": number(STORE, "") or 0.0, "stone": 0.0}
for kind in ("lumber", "stone"):
    found = re.search(r"^var %s := (\d+)" % kind, STORE, re.M)
    starts_with[kind] = float(found.group(1)) if found else 0.0
founding = code(VILLAGE)
granted = {"lumber": 0.0, "stone": 0.0}
for kind, adder in (("lumber", "add_lumber"), ("stone", "add_stone")):
    for row in founding.split("\n"):
        if "CreatureNest.%s" % kind.upper() in row and adder in row:
            granted[kind] = LUMBER if kind == "lumber" else STONE
print()
print("WHAT A NEW VILLAGE HAS AGAINST WHAT A NEST COSTS:")
for kind, price in (("lumber", LUMBER), ("stone", STONE)):
    have = starts_with[kind] + granted[kind]
    print("   %-7s granary starts with %2.0f, founding adds %2.0f, a nest "
          "takes %2.0f  -> %s" % (kind, starts_with[kind], granted[kind],
                                  price, "enough" if have >= price else "SHORT"))
    if have < price:
        fail.append("a founding village has %.0f %s and a nest takes %.0f, so "
                    "it wants one it cannot pay for and nothing happens at all"
                    % (have, kind, price))

# -- ONE DOOR FOR WHAT IT COSTS ----------------------------------------------
raising = body_of(NEST, "raise_at")
spends = any("try_spend_materials(LUMBER, STONE)" in r for r in raising)
bare = [r for r in wanting + raising if re.search(r"\b(6|10)\b", r)]
print()
print("THE PRICE IS WRITTEN %s." % ("once" if spends and not bare
                                    else "IN MORE THAN ONE PLACE"))
if not spends or bare:
    fail.append("the raising does not spend the same constants the wanting "
                "checks (%s), so a village can want a nest it cannot pay for "
                "or pay a price nobody checked"
                % (bare[0].strip() if bare else "try_spend_materials"))

# -- AND IT CANNOT BE BURNT AWAY ---------------------------------------------
hurting = body_of(NEST, "damage")
floored = any("maxf(health - amount" in r and "SCORCHED" in r for r in hurting)
ends = [r for r in body_of(NEST, "burn_down") if "queue_free" in r]
kept = "burn_down" in AFFORDS
still_shows = any("RuinBar.over" in r for r in hurting)
print("A NEST ON FIRE %s, and the bar %s."
      % ("blackens and stands" if floored and not ends
         else "CAN STILL BE BURNT OFF THE MAP",
         "still shows it" if still_shows else "NO LONGER SHOWS IT"))
if not floored:
    fail.append("nest health is not floored, so a player can burn away the one "
                "place their creature sleeps, dances, revives and steps "
                "through the world")
if ends:
    fail.append("burn_down still frees the nest (%s) — the method has to stay, "
                "because Affords.BURNABLE names it and a burnable thing "
                "missing it crashes the moment a fire reaches it, but what it "
                "must no longer do is END the nest" % ends[0].strip())
if not kept:
    fail.append("Affords.BURNABLE no longer names burn_down, so this check is "
                "guarding a contract that has moved")
if not still_shows:
    fail.append("a nest that can be hurt without LOOKING hurt is one nobody "
                "can tell is being attacked — the floor is meant to keep it "
                "standing, not to make fire invisible")

# -- HOW SOON, IN PLAIN SECONDS ----------------------------------------------
job = re.search(r'scores\["build_nest"\] = ([\d.]+) if village.is_player_home',
                code(VILLAGER))
hammering = re.search(r"state = State.BUILDING_NEST\s*\n\s*_action_time = ([\d.]+)",
                      code(VILLAGER))
others = sorted({float(v) for v in re.findall(r'scores\["\w+"\] = ([\d.]+)',
                                              code(VILLAGER))}, reverse=True)
if job and hammering:
    first = float(job.group(1))
    print()
    print("A FOUNDING VILLAGER SCORES THE JOB AT %.0f, against %s for the next "
          "few." % (first, ", ".join("%.0f" % v for v in others[:4]
                                     if v != first)))
    print("   then walks to the spot and hammers for %.0fs."
          % float(hammering.group(1)))
    if others and first < others[0] and others[0] != first:
        pass   # something outranks it, which is fine if it keeps people alive
    if first <= 30.0:
        fail.append("the first nest is scored no higher than an ordinary job "
                    "(%.0f), so a founding village gets round to it after the "
                    "ploughing" % first)
else:
    fail.append("the build-nest job no longer scores the first village's nest "
                "separately, so 'immediately' is not expressed anywhere")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: the first village starts at once and can pay for it, the price is "
      "written once, and the nest cannot be burnt off the map.")
