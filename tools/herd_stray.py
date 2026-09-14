#!/usr/bin/env python3
"""CAN THE HAND ALWAYS REACH A BEAST YOU CAN SEE?

A herd is one node and a MultiMesh; only a couple of dozen head anywhere in the
world are real `Animal` bodies. The hand promotes a row into a beast when you
point at it -- but first it asks one question about the WHOLE herd, `is the hand
within the mass's span`, and walks away if not. That check is measured off the
herd's heart, so it can only ever be as good as the assumption that members
stand near their heart.

THEY DO NOT, AND IT GETS WORSE AS THE HERD GETS SMALLER. A row's offset is
dealt once and then only ever pushed OUTWARD: `blown` shoves rows downwind when
a gust hits, and `_tend_agents` writes back wherever a promoted animal actually
walked to before it was demoted. `_redeal` re-rolls what a row is DOING and
never where it stands. Nothing pulls one home.

And the span the hand tests is computed from `_spread`, which is recomputed from
the LIVING head count every time the herd changes size -- while the members keep
the places they were dealt when it was big. So a two-hundred-head herd hunted
down to twenty keeps heads thirty metres out and shrinks the span it answers the
hand within to about thirty. That is the whole bug, and it is why the report was
always bison and horses: the kinds that get hunted and taken.

So this walks a herd through an evening of exactly those two forces and reports
the worst distance any head reaches from its own heart -- with the shedding in
`_shed_strays` and without it. The number that matters is whether the worst case
stays inside the span the hand actually tests.

Constants are read off scripts/animals/herd.gd. --hours sets the session length.
"""
import argparse
import math
import pathlib
import random
import re
import sys

SRC = pathlib.Path(__file__).resolve().parent.parent / "scripts/animals/herd.gd"
TEXT = SRC.read_text()


def const(name, default=None):
    m = re.search(r"^const %s\s*:?=\s*([0-9.]+)" % name, TEXT, re.M)
    if not m:
        if default is None:
            sys.exit("could not read %s off herd.gd" % name)
        return default
    return float(m.group(1))


SPACING = const("SPACING")
SPREAD_LEAST = const("SPREAD_LEAST")
SPREAD_SLACK = const("SPREAD_SLACK")
HAND_REACH = const("HAND_REACH")
STRAY_GATHER_SHARE = const("STRAY_GATHER_SHARE")
RECENTRE_LEAST = const("RECENTRE_LEAST")
WATCH_EVERY = const("WATCH_EVERY")
PROMOTE_WITHIN = const("PROMOTE_WITHIN")
# How far a demoted animal tends to have wandered from where its row sat, and
# how far a gust throws one. Both are shaped by the game rather than read from
# it -- an animal walks at a couple of metres a second and a gust is violent.
WANDER = 14.0
GUST = 18.0
# How far past a tidy herd's own span the hand's early-out may stretch before it
# has stopped being an early-out. A quarter over is generous; without shedding
# it reaches a third over inside four hours and keeps climbing.
SPAN_SLACK = 1.25


def source_says():
    """WHAT THE TREE ACTUALLY DOES, so the last row of the table is this build
    and not a description of it. Reading these off means deleting the shedding,
    or quietly dropping `_widest` back out of the reach, fails here."""
    body = re.search(r"func hand_span\(\) -> float:\n((?:\t.*\n)+)", TEXT)
    exact = bool(body) and "_widest" in body.group(1)
    sheds = "func _shed_strays()" in TEXT and "_shed_strays()" in re.sub(
        r"func _shed_strays\(\).*", "", TEXT, flags=re.S)
    return sheds, exact


def spread(alive):
    return max(SPACING * math.sqrt(max(alive, 1)), SPREAD_LEAST)


class Band:
    """One herd: heads as offsets from a heart, and the two forces on them."""

    exact = True

    def __init__(self, heads):
        self.at = [(0.0, 0.0)] * 0
        s = spread(heads)
        for _ in range(heads):
            a = random.random() * math.tau
            r = math.sqrt(random.random()) * s
            self.at.append((math.cos(a) * r, math.sin(a) * r))

    def tidy(self):
        return max(spread(len(self.at)), SPREAD_LEAST) * SPREAD_SLACK

    def span(self):
        """What _reach_of_the_hand tests before it will look at a herd's rows.

        `exact` is the fix: the tidy span OR the widest head this herd actually
        has, whichever is greater, so the early-out is true by construction.
        Without it the span is a GUESS off the head count -- which is how the
        game shipped, and is the third row of the table."""
        if self.exact:
            return max(self.tidy(), self.worst()) + HAND_REACH
        return self.tidy() + HAND_REACH

    def worst(self):
        return max((math.hypot(x, y) for x, y in self.at), default=0.0)

    def take(self):
        """One head killed or carried off. `_cull` prefers rows nobody is
        promoted into, which are the ones standing in formation -- so hunting
        thins the MIDDLE and leaves the outliers, which is the unkind way
        round and is what the game actually does."""
        if len(self.at) <= 1:
            return
        near = min(range(len(self.at)), key=lambda i: math.hypot(*self.at[i]))
        self.at.pop(near)

    def recentre(self):
        """_recentre: the heart moves to the middle of what is left, and every
        offset shifts by the same amount, so nothing on the grass moves."""
        if not self.at:
            return
        mx = sum(x for x, _ in self.at) / len(self.at)
        my = sum(y for _, y in self.at) / len(self.at)
        if math.hypot(mx, my) < RECENTRE_LEAST:
            return
        self.at = [(x - mx, y - my) for x, y in self.at]

    def shove(self, how_many, how_far):
        for _ in range(how_many):
            if not self.at:
                return
            i = random.randrange(len(self.at))
            a = random.random() * math.tau
            r = random.random() * how_far
            x, y = self.at[i]
            self.at[i] = (x + math.cos(a) * r, y + math.sin(a) * r)

    def shed(self):
        """_shed_strays, transcribed: one band a look-round, off the farthest."""
        limit = self.tidy()
        gather = SPREAD_LEAST * SPREAD_SLACK * STRAY_GATHER_SHARE
        far, worst = None, limit
        for x, y in self.at:
            if math.hypot(x, y) > worst:
                worst, far = math.hypot(x, y), (x, y)
        if far is None:
            return None
        taken, kept = [], []
        for x, y in self.at:
            out = math.hypot(x, y) > limit
            near = math.hypot(x - far[0], y - far[1]) < gather
            (taken if out and near else kept).append((x, y))
        if not taken or not kept:
            self.recentre()
            return None
        self.at = kept
        self.recentre()
        born = Band(0)
        # The daughter's heart is the anchor; her rows keep their real places.
        born.at = [(x - far[0], y - far[1]) for x, y in taken]
        return born


def evening(hours, shedding, exact):
    """The worst head-to-heart gap over a session, against the span at the time.

    Reported as the worst OVERHANG -- how far past its own herd's tested span a
    head stood -- because that is the quantity that decides whether the hand
    refuses. A big herd can have heads thirty metres out and be perfectly
    reachable; a hunted remnant cannot.
    """
    random.seed(20260714)
    Band.exact = exact
    bands = [Band(180)]
    ticks = int(hours * 3600.0 / WATCH_EVERY)
    overhang = 0.0
    widest = 0.0
    tidiest = 0.0
    for tick in range(ticks):
        for b in list(bands):
            # Harried: a promoted beast walks off and is demoted where it got
            # to, which is the commonest of the two and happens wherever the
            # player is.
            if random.random() < 0.25:
                b.shove(1, WANDER)
            if random.random() < 0.01:
                b.shove(max(len(b.at) // 8, 1), GUST)
            # AND HUNTED. Wolves, villagers and the creature take head all
            # evening; the herd ends the session a fraction of what it was, and
            # every loss shrinks the span it answers the hand within while the
            # outliers stay exactly where they were standing.
            if random.random() < 0.03:
                b.take()
            if shedding:
                born = b.shed()
                if born is not None and len(bands) < 400:
                    bands.append(born)
            if b.at:
                overhang = max(overhang, b.worst() - b.span())
                widest = max(widest, b.span())
                tidiest = max(tidiest, b.tidy() + HAND_REACH)
    return overhang, widest, tidiest, len(bands)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=4.0)
    args = ap.parse_args()
    print("read off herd.gd: SPACING=%.1f  SPREAD_LEAST=%.0f  SPREAD_SLACK=%.1f"
          "  HAND_REACH=%.0f  STRAY_GATHER_SHARE=%.2f\n"
          % (SPACING, SPREAD_LEAST, SPREAD_SLACK, HAND_REACH, STRAY_GATHER_SHARE))
    print("%-20s %10s %10s %10s %7s"
          % ("", "OVERHANG", "SPAN", "IF TIDY", "HERDS"))
    bad = []
    rows = [
        ("as it shipped", False, False),
        ("shedding only", True, False),
        ("as the source stands",) + source_says(),
    ]
    for label, shedding, exact in rows:
        over, span, tidy, herds = evening(args.hours, shedding, exact)
        note = ""
        final = label == "as the source stands"
        # ONE: no head may stand further out than the span its herd answers
        # within, or the hand refuses a beast the player is pointing at. This
        # holds by construction now -- hand_span() takes the widest head -- and
        # is checked anyway, because that is the property the player feels.
        if over > 0.0:
            note = "  <-- UNREACHABLE by %.0fm" % over
            if final:
                bad.append("%s: a head stood %.0fm outside its herd's reach"
                           % (label, over))
        # TWO: and the early-out must stay an early-out. A herd whose span has
        # stretched to cover a stray a hundred metres off answers the hand from
        # a hundred metres off -- so pointing at one sheep walks the rows of
        # every herd for streets around, which is the cost the early-out exists
        # to avoid. This is what the shedding actually buys.
        if final and span > tidy * SPAN_SLACK:
            note += "  <-- span %.0fx what a tidy herd needs" % (span / tidy)
            bad.append("%s: reach stretched to %.0fm against a tidy %.0fm"
                       % (label, span, tidy))
        print("%-20s %9.0fm %9.0fm %9.0fm %7d%s"
              % (label, max(over, 0.0), span, tidy, herds, note))
    print("\nOVERHANG is how far past its own herd's tested reach a beast stood"
          "\nover %.0f hours of being harried and hunted; above zero the game"
          "\nrefuses an animal the player is pointing straight at."
          "\n\nSPAN is how far out the widest herd ends up answering the hand"
          "\nfrom, against IF TIDY, what a herd of that size actually needs."
          "\nThe early-out exists so that pointing at one sheep does not walk"
          "\nevery row of every herd nearby; a herd stretched to cover a stray"
          "\na hundred metres off has given that up. Shedding is what keeps the"
          "\ntwo numbers together." % args.hours)
    if bad:
        print("\nFAIL:")
        for line in bad:
            print("  " + line)
        return 1
    print("\nOK: every head reachable, and the reach stayed near a tidy herd's.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
