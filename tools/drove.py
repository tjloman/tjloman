#!/usr/bin/env python3
"""A BARN'S BOOK MUST COST WHAT A DOZEN ANIMALS COST, AND EAT LIKE A HUNDRED.

Village stock are not wildlife. A wild herd DECIDES things -- where to graze,
what to run from, whether to split, who to join -- and every one of those
decisions is a reason to look at the world. A barn's book decides nothing at
all: it is let out, walked down a street, watered, put on grass and drawn back
in, on a route settled once each morning, and between those six places the whole
herd takes one instruction.

That is the design, and it only pays if nothing in the per-frame path walks the
book. Herd's own header has promised for a long time that every per-frame cost
in it is bounded by a constant. It was not true. `_tend_agents` made three
passes over every row several times a second, the ground sweep re-read heights
under animals that were standing inside a barn, and the transform writer spent
most of its budget setting zero on top of zero for rows nobody draws. A hundred
and sixty head cost a hundred and sixty heads' worth of all three, for twelve
animals of visible result.

The number that ends it is not a new budget. It is `shown` -- the one the barn
was already keeping -- and this file exists to check that every one of those
loops is bounded by it and stays that way.

AND THE OTHER HALF: a herd that costs nothing is a herd that grows without
limit. Twelve villagers were found keeping a hundred and sixty head, which
crowded the town's own growth out. So there is one barn to a town, a flat
ceiling over the stalls, and -- the part that actually closes it -- STOCK EAT.
Grain out of the town's own store, every morning, against one hunger shared by
the whole herd. A farm too big for its village empties the granary and then
becomes a farm the village can feed.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HERD = (ROOT / "scripts/animals/herd.gd").read_text()
DROVE = (ROOT / "scripts/animals/drove.gd").read_text()
SHOP = (ROOT / "scripts/world/workshop.gd").read_text()
TOWN = (ROOT / "scripts/world/village.gd").read_text()


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


def _to_its_bound(rows, loop):
    """A loop counting to a local, resolved to what that local was set to.

    One hop, inside the same function, and no further: `for step in todo` says
    nothing about what it costs until you know what `todo` is, and `todo` is
    three lines up. Following it further than that is how a check stops being
    able to fail.
    """
    said = re.match(r"for \w+ in (\w+):$", loop)
    if not said:
        return loop
    for row in rows:
        set_to = re.match(r"\s*var %s :?= (.+)$" % said.group(1), row)
        if set_to:
            return "%s   (%s = %s)" % (loop, said.group(1), set_to.group(1))
    return loop


fail = []

# -- NOTHING IN THE PER-FRAME PATH WALKS THE BOOK ---------------------------
#
# Asked of the LOOP, not of the function. `_members.size()` appearing somewhere
# in a function says nothing; what matters is what the `for` counts to.
print("WHAT THE PER-FRAME PASSES COUNT TO:")
bounded = {
    "_resample_grounds": "live",
    "_write_transforms": "live",
    "_redeal": "_redeal_left",
    "_reach_of_the_hand": "_simulated()",
    "_look_for_more": "scan",
}
for name, want in bounded.items():
    rows = body_of(HERD, name)
    loops = [r.strip() for r in rows if r.strip().startswith("for ")]
    # THE ONE ALLOWED WALK OF THE BOOK: putting the hidden tail away. It is
    # allowed because it is WATERMARKED — `_hidden_to` says how far the
    # collapsing has already got, so it happens once and never again. Excused
    # here only when that guard is what it sits under; a bare walk is not.
    kept = [_to_its_bound(rows, r) for r in loops if "_hidden_to" not in r]
    walks = [r for r in kept if "_members.size()" in r or "in _members" in r]
    held = any(want in r for r in kept)
    print("   %-20s %s" % (name, "; ".join(loops) if loops else "(no loop)"))
    if walks:
        fail.append("%s still walks the whole book (`%s`) — a barn of a hundred "
                    "and sixty head pays a hundred and sixty rows for twelve "
                    "animals of result" % (name, walks[0]))
    elif not held:
        fail.append("%s no longer walks the book but is not bounded by `%s` "
                    "either, so what it costs is anybody's guess" % (name, want))

# AND THE TAIL IS PUT AWAY UNDER THE WATERMARK, not merely near one.
tail = body_of(HERD, "_write_transforms")
guard = next((i for i, r in enumerate(tail) if "_hidden_at != shown" in r), None)
sweep = next((i for i, r in enumerate(tail) if "_hidden_to" in r
              and r.strip().startswith("for ")), None)
moves = any("_hidden_to = " in r for r in tail)
print("   %-20s %s" % ("(the tail)",
                       "collapsed once, under the watermark"
                       if guard is not None and sweep is not None
                       and guard < sweep and moves else "NOT WATERMARKED"))
if guard is None or sweep is None or guard > sweep or not moves:
    fail.append("the hidden tail is collapsed without a watermark that moves, "
                "so every change of `shown` rewrites zero over zero for the "
                "whole book")

tend = body_of(HERD, "_tend_the_promoted")
over_list = any(r.strip().startswith("for ") and "in _afoot" in r for r in tend)
print("   %-20s %s" % ("_tend_the_promoted",
                       "for i in _afoot" if over_list else "WALKS THE BOOK"))
if not over_list:
    fail.append("_tend_the_promoted walks the herd rather than the short list "
                "of rows that actually hold a beast")

# AND THE SHORT LIST IS COMPLETE. It is only safe to walk `_afoot` instead of
# the book because `_promote` is the ONLY thing that ever puts an agent in a
# row. A second one, anywhere, and promoted beasts start going untended:
# never demoted, never freed, holding the world's agent budget for ever.
# THE ASSIGNMENT, not the comparison: `m["agent"] == beast` is a question.
puts = [r.strip() for r in code(HERD).split("\n")
        if re.search(r'\["agent"\]\s*=(?!=)', r) and "= null" not in r]
appends = any("_afoot.append(" in r for r in body_of(HERD, "_promote"))
print()
print("ROWS ARE GIVEN A BEAST IN %d place(s); the list is appended in _promote: %s"
      % (len(puts), "yes" if appends else "NO"))
if len(puts) != 1:
    fail.append("%d places put a beast in a row — `_afoot` is only complete "
                "while `_promote` is the only one, so the others' beasts are "
                "never tended, never demoted, and hold the agent budget for "
                "ever" % len(puts))
if not appends:
    fail.append("_promote does not add the row to `_afoot`, so a promoted beast "
                "is never tended again")

# -- THE DAY IS PLOTTED ONCE ------------------------------------------------
plot = body_of(SHOP, "_plot_the_day")
once = any("_plotted" in r and "return" in r for r in plot) \
    or (any("_plotted" in r for r in plot)
        and any(r.strip() == "return" for r in plot))
print()
print("THE DAY IS PLOTTED %s." % ("once, at dawn" if once else "EVERY LEG"))
if not once:
    fail.append("the barn replots its route every leg, so it is six routes a "
                "day rather than one and the stock take a different street "
                "every twenty-six seconds")

# -- ONE ORDER PER LEG, AND THE COLUMN IS LAID ONCE -------------------------
tick = body_of(SHOP, "_process")
per_herd = [r.strip() for r in tick if "drive_toward" in r or "form_up" in r]
print("PER LEG, EACH HERD IS TOLD: %s" % ("; ".join(per_herd) or "NOTHING"))
if not any("drive_toward" in r for r in per_herd):
    fail.append("the barn never tells its herds where to go")
if not any("form_up" in r for r in per_herd):
    fail.append("the barn never forms its stock up, so a drove is the blob the "
                "herd was dealt on the day it was born")
laid = body_of(HERD, "form_up")
in_process = any("form_up" in r for r in body_of(HERD, "_process"))
print("THE COLUMN IS LAID %s."
      % ("on the order" if laid and not in_process else "EVERY FRAME"))
if not laid:
    fail.append("Herd.form_up does not exist, so nothing lays the column")
if in_process:
    fail.append("the column is relaid from Herd._process — it is a per-frame "
                "walk of the rows, which is the whole thing this avoids")

# -- ONE BARN TO A TOWN -----------------------------------------------------
# The row, read to its own closing brace — and `takes`/`makes` are dicts inside
# it, so "up to the first }" reads four lines and stops.
barn_row = re.search(r'\t"barn": \{.*?\n\t\},', SHOP, re.S)
capped = barn_row is not None and '"most": 1' in barn_row.group(0)
at_door = any("barn" in r for r in body_of(TOWN, "spawn_workshop_at"))
print()
print("BARNS PER TOWN: %s, and the second is %s at the door."
      % ("1" if capped else "AS MANY AS IT LIKES",
         "refused" if at_door else "NOT REFUSED"))
if not capped:
    fail.append("the barn has no ceiling in TRADES, so a town raises one per "
                "twenty-five souls and each one doubles the room")
if not at_door:
    fail.append("Village.spawn_workshop_at does not refuse a second barn — the "
                "dock was found standing twice through a path its own rules "
                "did not watch, and this is the same door")

# -- THE HERD CANNOT OUTGROW THE VILLAGE ------------------------------------
per_keeper = number(TOWN, "HEAD_PER_KEEPER")
most = number(TOWN, "HEAD_AT_MOST")
loose = number(TOWN, "MAX_TAMED")
stalls = number(TOWN, "BARN_STALLS")
flat = any("HEAD_AT_MOST" in r for r in body_of(SHOP, "stalls"))
print()
print("WHAT A TOWN MAY KEEP, with a barn standing:")
print("   %-12s %-10s %-10s %s" % ("villagers", "hands", "stalls", "kept"))
for souls in (12, 25, 40, 80, 200):
    hands = loose + souls * per_keeper
    built = loose + stalls
    kept = min(min(hands, built), most if flat else 1e9)
    print("   %-12d %-10.0f %-10.0f %.0f%s" % (souls, hands, built, kept,
          "   <- the run that crowded a town out" if souls == 12 else ""))
    if kept > souls * 4:
        fail.append("%d villagers may keep %.0f head — that is not a village "
                    "with a farm, it is a feedlot with %d staff"
                    % (souls, kept, souls))
if not flat:
    fail.append("Workshop.stalls has no flat ceiling, and everything else in it "
                "is a RATIO — a town of two hundred would keep eight hundred "
                "head by the same rule that gives twelve souls twenty-four")

# -- AND THEY EAT -----------------------------------------------------------
feed = number(DROVE, "FEED_PER_HEAD")
yield_share = number(DROVE, "TO_THE_STORE")
dressed = number(DROVE, "DRESSED_OUT")
takes = any("store.take(" in r for r in body_of(SHOP, "_fill_the_trough"))
feeds = any(".fed(" in r for r in body_of(SHOP, "_fill_the_trough"))
gives = any("store.add(" in r for r in body_of(SHOP, "_send_to_the_store"))
print()
print("THE TROUGH %s the town's grain, and %s the herd."
      % ("takes" if takes else "TAKES NOTHING OF", "feeds" if feeds else "DOES NOT FEED"))
print("THE DAY'S YIELD %s the storehouse."
      % ("goes to" if gives else "GOES NOWHERE — the barn keeps stock for nothing"))
if not takes:
    fail.append("the trough costs the town no grain, so a herd of any size is "
                "free to keep and will grow to the ceiling beside starving people")
if not feeds:
    fail.append("filling the trough does not feed the herd, so hunger only ever "
                "rises and every barn starves")
if not gives:
    fail.append("nothing of the herd ever reaches the storehouse, so a barn is "
                "a building that eats grain and returns nothing")

# ONE HUNGER FOR THE WHOLE HERD, and not one per beast.
shared = re.search(r"^var hunger := ", HERD, re.M) is not None
print("HUNGER IS %s." % ("one number for the whole herd"
                         if shared else "NOT SHARED"))
if not shared:
    fail.append("the herd has no shared hunger, so being fed means nothing")

# -- THE LEDGER: A FED HERD MUST NOT LOSE GROUND ----------------------------
#
# The one that was wrong. A herd gets hungrier every season and there are eight
# seasons in a day, so a trough worth half a season's hunger starved every barn
# in the game in a day and a half however much grain the town had — and nothing
# would have said so except a village full of dead cattle an hour in.
per_season = number(HERD, "HUNGER_PER_SEASON")
season = number(HERD, "SEASON")
a_feed = number(DROVE, "A_GOOD_FEED")
starves = number(HERD, "STARVES_ABOVE")
day_len = number((ROOT / "scripts/game_state.gd").read_text(), "DAY_SECONDS")
seasons = day_len / season
per_day = per_season * seasons
print()
print("THE HUNGER LEDGER, per day (%.0fs, %.1f seasons):" % (day_len, seasons))
print("   appetite      +%.2f" % per_day)
print("   a full trough -%.2f" % a_feed)
for got, what in ((1.0, "fed"), (0.5, "half fed"), (0.0, "not fed")):
    net = per_day - a_feed * got
    when = ("never" if net <= 0.0 else "%.1f days" % (starves / net))
    print("   %-13s %+.2f a day  ->  starves in %s" % (what, net, when))
if per_day - a_feed >= 0.0:
    fail.append("a FULLY FED herd still gains %+.2f hunger a day, so every barn "
                "in the game starves its stock in %.1f days however much grain "
                "the town has" % (per_day - a_feed, starves / (per_day - a_feed)))
if per_day <= 0.0:
    fail.append("stock never get hungry at all, so the trough is decoration and "
                "a herd of any size is free to keep")
if per_day - a_feed * 0.5 <= 0.0:
    fail.append("half a trough still keeps a herd indefinitely, so running out "
                "of grain costs a farm nothing")

# AND THE TROUGH IS FILLED WHEREVER THE PLAYER IS. A barn only fed while the
# camera was near would starve every herd in every village walked away from.
tick = body_of(SHOP, "_process")
gate = next((i for i, r in enumerate(tick) if "sim_stride" in r), None)
fed_at = next((i for i, r in enumerate(tick) if "_plot_the_day()" in r), None)
print("   the day runs %s the distance gate."
      % ("above" if gate is not None and fed_at is not None and fed_at < gate
         else "BELOW"))
if gate is None or fed_at is None or fed_at > gate:
    fail.append("the barn's day is behind the distance gate, so a village the "
                "player has walked away from never fills its trough and starves "
                "its herd while nobody is looking")

print()
print("A DAY AT A BARN of 32 head (the twelve-villager town above):")
asks = max(int(32 * feed), 1)
sent = int(32 * yield_share)
print("   trough   %d grain out of the store" % asks)
print("   yield    %d head in, worth %d meat plus %d dressed each"
      % (sent, sent, dressed))
print("   route    %d legs of %.0fs — %.0fs of droving out of a %.0fs day"
      % (len(re.findall(r'"\w+"', re.search(r"const DAY: Array\[String\] = \[(.*?)\]",
                                            DROVE, re.S).group(1))),
         number(DROVE, "LEG_SECONDS"),
         len(re.findall(r'"\w+"', re.search(r"const DAY: Array\[String\] = \[(.*?)\]",
                                            DROVE, re.S).group(1)))
         * number(DROVE, "LEG_SECONDS"), 320.0))

# -- WHAT IT ALL COSTS ------------------------------------------------------
shuffle = number(HERD, "SHUFFLE_EVERY")
writes = number(HERD, "WRITES_PER_TICK")
grounds_most = number(HERD, "GROUNDS_MOST")
grounds_tick = number(HERD, "GROUNDS_PER_TICK")
scanned = number(HERD, "PROMOTES_SCANNED")
yard = number(SHOP, "IN_THE_YARD")
ticks = 1.0 / shuffle
print()
print("ROWS TOUCHED PER SECOND by one barn herd, at full rate:")
print("   %-8s %12s %12s" % ("head", "walking the book", "bounded by shown"))
for book in (40, 160, 400):
    was = (min(grounds_most, max(grounds_tick, book * 0.27))
           + min(writes, book) + 3.0 * book) * ticks
    now = (min(yard, book) * 2.0 + min(scanned, yard)) * ticks
    print("   %-8d %12.0f %12.0f" % (book, was, now))
    if now > was:
        fail.append("a book of %d costs MORE bounded than unbounded" % book)
print("   ...and none of it at all once they are in for the night (shown = 0).")

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: one order a leg, one hunger, one barn, and a book that costs what "
      "the yard costs.")
