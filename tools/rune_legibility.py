#!/usr/bin/env python3
"""CAN THE RUNES STILL BE TOLD APART WHEN THE PHONE IS STRUGGLING?

A faithful Python port of `GestureRecognizer`, plus a model of what a touch
digitizer does to a stroke when the device is hot or nearly flat, plus a model
of how a hand actually draws rather than how a compass does.

WHY THIS EXISTS. A phone under thermal or battery stress drops its touch scan
rate and coarsens its reported coordinates. A stroke that arrived as ninety
points on a cool phone arrives as a dozen on a hot one, snapped to a grid. That
is precisely when a player is most likely to be mid-fight and least able to
afford a miracle going astray -- and a misread rune does not fail, it casts
SOMETHING ELSE.

WHAT IT MODELS, and what it deliberately does not:

  * SAMPLE RATE and COORDINATE QUANTIZATION -- the thermal effect.
  * HAND WOBBLE -- a slow correlated waver, not white noise. This is the thing
    that broke the original heuristic recognizer: a slow wobble reads as real
    curvature however hard you smooth it.
  * HOW A LOOP GETS CLOSED -- lifted early, overshot, drawn as an oval. This is
    where the circle actually fails, and no amount of thermal headroom helps.

  * NOT ORIENTATION. An early version of this tool tilted every shape and
    reported the whole alphabet as fragile. That was the tool being wrong, not
    the alphabet: this recognizer has NO rotation normalisation on purpose,
    because a vertical line and a horizontal line are different runes. A
    tilted `force` becoming `fire` is the recognizer working, not failing.

Usage:
    python3 tools/rune_legibility.py            # the whole report
    python3 tools/rune_legibility.py --hand     # just the loop-closing test
    python3 tools/rune_legibility.py --thermal  # just the degradation test
"""
import argparse

import math
import random

SAMPLES = 48
REF_SIZE = 200.0
MATCH_LIMIT = 68.0
MIN_PATH_LENGTH = 60.0
TAU = math.tau


def path_length(pts):
    return sum(math.dist(pts[i - 1], pts[i]) for i in range(1, len(pts)))


def resample(points, n):
    total = path_length(points)
    if total <= 0.0:
        return [points[0]] * n
    interval = total / (n - 1)
    result = [points[0]]
    accum = 0.0
    pts = list(points)
    i = 1
    while i < len(pts):
        seg = math.dist(pts[i - 1], pts[i])
        if accum + seg >= interval and seg > 0.0:
            t = (interval - accum) / seg
            np = (pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * t,
                  pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * t)
            result.append(np)
            pts.insert(i, np)
            accum = 0.0
        else:
            accum += seg
        i += 1
    while len(result) < n:
        result.append(pts[-1])
    return result[:n]


def normalize(points):
    path = resample(points, SAMPLES)
    lox = min(p[0] for p in path); hix = max(p[0] for p in path)
    loy = min(p[1] for p in path); hiy = max(p[1] for p in path)
    cx = sum(p[0] for p in path) / len(path)
    cy = sum(p[1] for p in path) / len(path)
    span = REF_SIZE / max(max(hix - lox, hiy - loy), 0.001)
    return [((p[0] - cx) * span, (p[1] - cy) * span) for p in path]


def distance(a, b):
    return sum(math.dist(a[i], b[i]) for i in range(len(a))) / len(a)


TEMPLATES = {}


def add(name, shape):
    raw = [shape(i / (SAMPLES - 1)) for i in range(SAMPLES)]
    TEMPLATES.setdefault(name, []).append(normalize(raw))


def build_templates():
    if TEMPLATES:
        return
    add("vline", lambda t: (0.0, t * 200.0))
    add("hline", lambda t: (t * 200.0, 0.0))
    add("dline", lambda t: (t * 200.0, t * 200.0))
    add("dline", lambda t: (t * 200.0, 200.0 - t * 200.0))
    for start in range(4):
        ph = start / 4.0
        add("circle", lambda t, ph=ph: (math.cos(TAU * (t + ph)) * 100.0,
                                        math.sin(TAU * (t + ph)) * 100.0))
    for turns in (1.5, 2.0, 2.5, 3.0):
        for start in (0.0, 0.5):
            add("spiral", lambda t, T=turns, S=start: (
                math.cos(TAU * (t * T + S)) * (18.0 + t * 112.0),
                math.sin(TAU * (t * T + S)) * (18.0 + t * 112.0)))
            add("rev_spiral", lambda t, T=turns, S=start: (
                math.cos(-TAU * (t * T + S)) * (18.0 + t * 112.0),
                math.sin(-TAU * (t * T + S)) * (18.0 + t * 112.0)))
    for flip in (1.0, -1.0):
        add("wave", lambda t, f=flip: (t * 200.0, f * math.sin(t * TAU) * 70.0))
        add("wave", lambda t, f=flip: (f * math.sin(t * TAU) * 70.0, t * 200.0))
        add("wave", lambda t, f=flip: (t * 200.0, f * math.sin(t * TAU) * 80.0))
        add("wave", lambda t, f=flip: (f * math.sin(t * TAU) * 80.0, t * 200.0))
    # FURY IS A SHARP Z, and CANCEL IS A SWEEP — mirroring GestureRecognizer,
    # which dropped the twenty zigzag templates for these six. The harness had
    # drifted back to the old alphabet, which meant every candidate above was
    # being scored against a set the game no longer has.
    for tall in (0.62, 1.0, 1.55):
        def zed(t, T=tall):
            run = 200.0 / max(T, 0.4)
            drop = 200.0 * T
            if t < 1.0 / 3.0:
                return (t * 3.0 * run, 0.0)
            if t < 2.0 / 3.0:
                k = (t - 1.0 / 3.0) * 3.0
                return (run - k * run, k * drop)
            return ((t - 2.0 / 3.0) * 3.0 * run, drop)
        add("zed", zed)
    for hook in (0.55, 0.8, 1.05):
        def sweep(t, H=hook):
            if t < 0.62:
                return (0.0, t / 0.62 * 200.0)
            a = -math.pi * 0.5 * ((t - 0.62) / 0.38)
            return (-math.sin(-a) * 95.0 * H, 200.0 + (1.0 - math.cos(a)) * 55.0 * H)
        add("sweep", sweep)
    for slant in (math.pi / 4.0, -math.pi / 4.0):
        for flip in (1.0, -1.0):
            def sl(t, S=slant, F=flip):
                x = t * 200.0 - 100.0
                y = F * math.sin(t * TAU) * 70.0
                return (x * math.cos(S) - y * math.sin(S), x * math.sin(S) + y * math.cos(S))
            add("wave", sl)
    add("caret", lambda t: (t * 200.0, -140.0 * (1.0 - abs(2.0 * t - 1.0))))
    add("caret", lambda t: (t * 200.0, 140.0 * (1.0 - abs(2.0 * t - 1.0))))
    add("caret", lambda t: (-140.0 * (1.0 - abs(2.0 * t - 1.0)), t * 200.0))
    add("caret", lambda t: (140.0 * (1.0 - abs(2.0 * t - 1.0)), t * 200.0))
    for quarter in range(4):
        turn = quarter * math.pi / 2.0
        add("arc", lambda t, T=turn: (
            math.cos(-math.pi / 2.0 - math.pi * 0.45 + math.pi * 0.9 * t + T) * 110.0,
            math.sin(-math.pi / 2.0 - math.pi * 0.45 + math.pi * 0.9 * t + T) * 110.0))


def classify(points, want_margin=False):
    if len(points) < 6 or path_length(points) < MIN_PATH_LENGTH:
        return ("none", 0.0) if want_margin else "none"
    build_templates()
    drawn = normalize(points)
    backwards = drawn[::-1]
    scores = {}
    for name, tpls in TEMPLATES.items():
        best = min(min(distance(drawn, t), distance(backwards, t)) for t in tpls)
        scores[name] = best
    order = sorted(scores.items(), key=lambda kv: kv[1])
    if order[0][1] >= MATCH_LIMIT:
        return ("none", 0.0) if want_margin else "none"
    if want_margin:
        return order[0][0], order[1][1] - order[0][1]
    return order[0][0]


def peek(points, templates=None):
    """Mirrors `GestureRecognizer.peek`: the reading, AND how sure it is.

    Confidence is two things multiplied out — how well the best template FITS,
    and how far it LEADS whatever came second. A stroke sitting between two
    shapes reads as uncertain even when its nearest match is close, which is
    what lets the on-screen readout show indecision instead of flickering
    between confident wrong answers.
    """
    T = templates if templates is not None else TEMPLATES
    if len(points) < 6 or path_length(points) < MIN_PATH_LENGTH:
        return "none", 0.0
    drawn = normalize(points)
    backwards = drawn[::-1]
    best = second = MATCH_LIMIT * 2.0
    name = "none"
    for shape, tpls in T.items():
        near = min(min(distance(drawn, t), distance(backwards, t)) for t in tpls)
        if near < best:
            second, best, name = best, near, shape
        elif near < second:
            second = near
    if best >= MATCH_LIMIT:
        return "none", 0.0
    fit = 1.0 - best / MATCH_LIMIT
    lead = max(0.0, min((second - best) / 22.0, 1.0))
    return name, max(0.0, min(fit * 0.45 + lead * 0.55, 1.0))


# ---- how a person draws, and what a struggling phone does to it -------------

SHAPES = {
    "vline": lambda t: (400, 120 + t * 300),
    "hline": lambda t: (120 + t * 300, 300),
    "dline": lambda t: (120 + t * 260, 120 + t * 250),
    "circle": lambda t: (400 + math.cos(t * TAU) * 100.0, 300 + math.sin(t * TAU) * 100.0),
    "spiral": lambda t: (400 + math.cos(t * TAU * 2.5) * (20 + t * 130),
                         300 + math.sin(t * TAU * 2.5) * (20 + t * 130)),
    "rev_spiral": lambda t: (400 + math.cos(-t * TAU * 2.5) * (20 + t * 130),
                             300 + math.sin(-t * TAU * 2.5) * (20 + t * 130)),
    "wave": lambda t: (120 + t * 300, 300 + math.sin(t * TAU) * 90),
    "zed": lambda t: ((120 + t * 3.0 * 300, 180) if t < 1 / 3 else
                      ((420 - (t - 1 / 3) * 3.0 * 300, 180 + (t - 1 / 3) * 3.0 * 240)
                       if t < 2 / 3 else
                       (120 + (t - 2 / 3) * 3.0 * 300, 420))),
    "sweep": lambda t: ((330, 160 + t / 0.62 * 220) if t < 0.62 else
                        (330 - math.sin(math.pi * 0.5 * ((t - 0.62) / 0.38)) * 95.0,
                         380 + (1.0 - math.cos(math.pi * 0.5 * ((t - 0.62) / 0.38)))
                         * 55.0)),
    "caret": lambda t: (120 + t * 240, 330 - 170.0 * (1.0 - abs(2.0 * t - 1.0))),
    "arc": lambda t: (400 + math.cos(-math.pi / 2 - math.pi * 0.45 + math.pi * 0.9 * t) * 130.0,
                      300 + math.sin(-math.pi / 2 - math.pi * 0.45 + math.pi * 0.9 * t) * 130.0),
}


def stroke(shape, seed, points=90, grid=0.0, jitter=0.0, wobble=9.0):
    """A hand-drawn stroke, optionally as a struggling digitizer would report it.

    points  how many samples the digitizer actually delivered (a hot phone
            drops its touch scan rate, so a stroke arrives as fewer points)
    grid    coordinate quantization in pixels (the "reduced DPI" effect)
    jitter  extra uncorrelated noise, in pixels
    """
    rng = random.Random(seed)
    ph1 = rng.uniform(0, TAU)
    ph2 = rng.uniform(0, TAU)
    pts = []
    for i in range(points):
        t = i / (points - 1)
        x, y = shape(t)
        x += math.sin(t * 2.5 * TAU + ph1) * wobble + rng.uniform(-1.5, 1.5)
        y += math.cos(t * 2.5 * TAU + ph2) * wobble + rng.uniform(-1.5, 1.5)
        if jitter:
            x += rng.uniform(-jitter, jitter)
            y += rng.uniform(-jitter, jitter)
        if grid:
            x = round(x / grid) * grid
            y = round(y / grid) * grid
        pts.append((x, y))
    # A quantized stroke repeats points where the finger moved less than one
    # grid cell; a real driver coalesces those into one event.
    out = [pts[0]]
    for p in pts[1:]:
        if p != out[-1]:
            out.append(p)
    return out


CONDITIONS = [
    ("healthy        (90 pts, no grid)", dict(points=90, grid=0.0, jitter=0.0)),
    ("warm           (45 pts, 4px)   ", dict(points=45, grid=4.0, jitter=1.0)),
    ("hot            (24 pts, 8px)   ", dict(points=24, grid=8.0, jitter=2.0)),
    ("throttled hard (14 pts, 14px)  ", dict(points=14, grid=14.0, jitter=3.0)),
    ("worst seen     (10 pts, 20px)  ", dict(points=10, grid=20.0, jitter=4.0)),
]

TRIALS = 40


def run():
    build_templates()
    print("Templates: %d shapes, %d reference drawings\n" % (
        len(TEMPLATES), sum(len(v) for v in TEMPLATES.values())))
    for label, cond in CONDITIONS:
        hits = 0
        total = 0
        confusion = {}
        margins = []
        for want, shape in SHAPES.items():
            for seed in range(TRIALS):
                pts = stroke(shape, seed, **cond)
                got, margin = classify(pts, want_margin=True)
                total += 1
                if got == want:
                    hits += 1
                    margins.append(margin)
                else:
                    confusion[(want, got)] = confusion.get((want, got), 0) + 1
        worst = sorted(confusion.items(), key=lambda kv: -kv[1])[:6]
        print("%s  %3d/%3d (%5.1f%%)  median margin %.1f" % (
            label, hits, total, 100.0 * hits / total,
            sorted(margins)[len(margins) // 2] if margins else 0.0))
        for (want, got), n in worst:
            print("        %-11s read as %-11s x%d" % (want, got, n))
        print()


def per_rune():
    """Which individual runes fail first, across all conditions."""
    build_templates()
    print("Per-rune survival (%% correct at each condition):")
    print("  %-11s %s" % ("rune", "  ".join("%-6s" % c[0].split()[0] for c in CONDITIONS)))
    for want, shape in SHAPES.items():
        row = []
        for _label, cond in CONDITIONS:
            hits = sum(1 for s in range(TRIALS)
                       if classify(stroke(shape, s, **cond)) == want)
            row.append(100.0 * hits / TRIALS)
        flag = "  <-- fails" if min(row) < 80 else ""
        print("  %-11s %s%s" % (want, "  ".join("%5.0f%%" % v for v in row), flag))




# ---- how a hand closes a loop ------------------------------------------------
#
# The circle is drawn by sweeping round; where a hand stops is the whole
# question. These vary ONLY the sweep and the roundness, never the orientation.

def ring(sweep=1.0, ecc=1.0, r=100.0):
    return lambda t: (400 + math.cos(t * TAU * sweep) * r * ecc,
                      300 + math.sin(t * TAU * sweep) * r)


LOOPS = [
    ("closed and round (the ideal)", ring()),
    ("lifted early  (85% round)", ring(sweep=0.85)),
    ("lifted early  (75% round)", ring(sweep=0.75)),
    ("overshot      (115%)", ring(sweep=1.15)),
    ("overshot      (130%)", ring(sweep=1.30)),
    ("oval          (0.45 wide)", ring(ecc=0.45)),
    ("small ring    (r=55)", ring(r=55.0)),
]

TRIES = 60


def _tally(shape, want, cond):
    got = {}
    for s in range(TRIES):
        g = classify(stroke(shape, s, **cond))
        got[g] = got.get(g, 0) + 1
    others = ", ".join("%s %d%%" % (k, 100 * v // TRIES)
                       for k, v in sorted(got.items(), key=lambda kv: -kv[1])
                       if k != want)
    return 100 * got.get(want, 0) // TRIES, others


def hand_report():
    build_templates()
    clean = dict(points=90, grid=0.0, jitter=0.0)
    print("HOW A HAND CLOSES A LOOP  (the `circle` rune, on a healthy screen)")
    print("  Sweep and roundness only -- orientation is left alone.\n")
    worst = 100
    for label, shape in LOOPS:
        pct, others = _tally(shape, "circle", clean)
        worst = min(worst, pct)
        print("    %-30s circle %3d%%   %s" % (label, pct, others))
    print("\n  Worst case: %d%%. A closed ring is unmistakable; a ring lifted a"
          "\n  quarter early is not a ring at all." % worst)
    return worst


def thermal_report():
    build_templates()
    print("AS THE TOUCH SCAN RATE DROPS  (same drawing, fewer samples, coarser grid)\n")
    print("  %-11s %s" % ("rune", "  ".join("%-9s" % c[0].split()[0] for c in CONDITIONS)))
    fragile = []
    for want, shape in SHAPES.items():
        row = []
        for _label, cond in CONDITIONS:
            pct, _ = _tally(shape, want, cond)
            row.append(pct)
        note = ""
        if min(row) < 85:
            _pct, others = _tally(shape, want, CONDITIONS[-2][1])
            note = "   <-- %s" % others
            fragile.append(want)
        print("  %-11s %s%s" % (want, "  ".join("%7d%%" % v for v in row), note))
    return fragile


# ---- WHAT HAPPENS IF WE SWAP A GLYPH IN -------------------------------------
#
# The first version of this scored a candidate by its DISTANCE to the nearest
# existing template — a static, geometric question. That ranked a closed box
# first and a sharp Z last, and it was wrong, because it never asked what
# happens when a PLAYER draws the thing.
#
# This asks that instead: add the candidate to the alphabet, have a hand draw
# it (including the ways a hand gets it wrong), and read it back with the same
# confidence measure the game now shows on screen. The ranking inverts.

def _poly(pts, closed=False):
    p = list(pts) + ([pts[0]] if closed else [])

    def f(t, off=0.0):
        u = (t + off) % 1.0 if closed else t
        n = len(p) - 1
        seg = min(int(u * n), n - 1)
        k = u * n - seg
        a, b = p[seg], p[seg + 1]
        return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)
    return f


def _heart(t, off=0.0):
    """One closed stroke from the top notch, down the left lobe, round."""
    a = ((t + off) % 1.0) * TAU - math.pi / 2.0
    x = 16.0 * math.sin(a) ** 3
    y = -(13.0 * math.cos(a) - 5.0 * math.cos(2 * a)
          - 2.0 * math.cos(3 * a) - math.cos(4 * a))
    return (400.0 + x * 6.2, 300.0 + y * 6.2)


def _bee(t, off=0.0):
    """Printed b: stem down, back UP the stem, then the bowl."""
    pts = [(330, 175), (330, 425), (330, 300)]
    for i in range(13):
        a = -math.pi / 2.0 + math.pi * (i / 12.0)
        pts.append((330 + math.sin(a) * 95.0, 362 - math.cos(a) * 62.0))
    pts.append((330, 425))
    return _poly(pts)(t)


def _bee_open(t, off=0.0):
    """b in one pass: the whole stem down, then a bowl swung off its FOOT, out
    to the right, and closed against the stem's middle. Same silhouette, no
    doubling back."""
    pts = [(330, 175), (330, 430)]
    for i in range(1, 17):
        a = math.pi * 0.5 - math.pi * (i / 16.0)
        pts.append((330 + math.cos(a) * 100.0, 365 + math.sin(a) * 65.0))
    return _poly(pts)(t)


def _cue(t, off=0.0):
    """q, and it needs no adjusting: the bowl anticlockwise from its top-right
    back to where it started, then straight down the tail."""
    pts = [(395 + math.cos(-math.pi / 4.0 - TAU * (i / 18.0)) * 82.0,
            265 + math.sin(-math.pi / 4.0 - TAU * (i / 18.0)) * 82.0)
           for i in range(19)]
    pts.append((453, 430))
    return _poly(pts)(t)


## HOW MUCH OF THE PATH IS DRAWN TWICE — the question that comes BEFORE
## legibility, and the one this tool used to get wrong.
##
## There is no pen lift here: one contact down, one path, one contact up. So a
## glyph whose ordinary construction needs the pen picked up (X, +) is out, and
## so is one that JOINS its parts by running back along a line it has already
## drawn (4, b, d, p). The second is the subtler failure and it is not merely
## cosmetic: `normalize` spreads its 48 points evenly along the PATH, so a stem
## drawn twice claims twice its share of them and drags the whole normalised
## shape toward the stem.
##
## The RUN is what tells a retrace from a cusp. A heart's two lobes meet at the
## notch and a circle closes on itself; both touch briefly and neither is a
## retrace. A `b` spends a sixth of its length in a row on a line it already
## drew. Measured on an arc-length-even resample, because that is what the
## recognizer sees.
def retrace_share(shape, n=160):
    try:
        raw = [shape(i / (n * 3 - 1), 0.0) for i in range(n * 3)]
    except TypeError:
        raw = [shape(i / (n * 3 - 1)) for i in range(n * 3)]
    pts = resample(raw, n)
    lox = min(p[0] for p in pts); hix = max(p[0] for p in pts)
    loy = min(p[1] for p in pts); hiy = max(p[1] for p in pts)
    near = math.hypot(hix - lox, hiy - loy) * 0.035
    on_top = [any(abs(i - j) > 8 and math.dist(pts[i], pts[j]) < near
                  for j in range(n)) for i in range(n)]
    run = best = 0
    for flag in on_top:
        run = run + 1 if flag else 0
        best = max(best, run)
    return sum(on_top) / n, best / n


CANDIDATES = {
    "heart": (_heart, True),
    "4": (_poly([(430, 190), (320, 330), (500, 330),
                 (455, 330), (455, 190), (455, 420)]), False),
    "4 open": (_poly([(430, 185), (315, 330), (495, 330), (495, 425)]), False),
    "b": (_bee, False),
    "b open": (_bee_open, False),
    "q": (_cue, False),
    "box": (_poly([(320, 220), (480, 220), (480, 380), (320, 380)], True), True),
    "triangle": (_poly([(400, 195), (487, 365), (313, 365)], True), True),
    "diamond": (_poly([(400, 190), (495, 300), (400, 410), (305, 300)], True), True),
    "zed": (_poly([(290, 190), (510, 190), (290, 405), (510, 405)]), False),
    "ell": (_poly([(330, 185), (330, 395), (505, 395)]), False),
    "tee": (_poly([(300, 205), (500, 205), (400, 205), (400, 410)]), False),
    "cross": (_poly([(400, 180), (400, 420), (400, 300), (275, 300), (525, 300)]), False),
    "staple": (_poly([(320, 200), (320, 390), (480, 390), (480, 200)]), False),
    "bolt": (_poly([(445, 165), (335, 300), (420, 300), (300, 440)]), False),
    "sq_spiral": (_poly([(430, 240), (340, 240), (340, 360), (460, 360),
                         (460, 220), (320, 220)]), False),
}

## How a hand gets a shape wrong. For a CLOSED shape the sloppiness is
## involuntary — nobody notices they did not quite meet the start — which is
## exactly why closure is the dangerous property. Truncating an open shape by a
## quarter removes a whole limb, and a player would know they had done it.
CLOSED_SLOPS = [("as intended", 1.0), ("lifted early", 0.82), ("overshot", 1.16)]


def swap_report():
    build_templates()
    print("SWAPPING A CANDIDATE INTO THE ALPHABET")
    print("  Added to the %d reference drawings the game ships, then drawn by a hand.\n"
          % sum(len(v) for v in TEMPLATES.values()) + "")
    print("  %-11s %-7s %-8s %-6s  %s" % (
        "candidate", "closed", "retrace", "conf", "how it reads when drawn"))
    rows = []
    for name, (shape, closed) in CANDIDATES.items():
        _touch, doubled = retrace_share(shape)
        offs = (0.0, 0.25, 0.5, 0.75) if closed else (0.0,)
        TEMPLATES["_c"] = [normalize([shape(i / (SAMPLES - 1), o)
                                      for i in range(SAMPLES)]) for o in offs]
        slops = CLOSED_SLOPS if closed else [("as intended", 1.0)]
        hits = tries = 0
        confs = []
        lost = {}
        for _lbl, sweep in slops:
            for cond in [c[1] for c in CONDITIONS[:4]]:
                for s in range(8):
                    got, conf = peek(stroke(
                        lambda t, sw=sweep: shape(t * sw, 0.0), s, **cond))
                    tries += 1
                    if got == "_c":
                        hits += 1
                        confs.append(conf)
                    else:
                        lost[got] = lost.get(got, 0) + 1
        del TEMPLATES["_c"]
        rate = 100 * hits / tries
        med = sorted(confs)[len(confs) // 2] if confs else 0.0
        top = max(lost.items(), key=lambda kv: kv[1])[0] if lost else ""
        rows.append((rate, med, name, closed, top, doubled))
    for rate, med, name, closed, top, doubled in sorted(rows, reverse=True):
        mark = "%3.0f%%%s" % (doubled * 100, "!" if doubled > 0.15 else " ")
        print("  %-11s %-7s %-8s %.2f   %3.0f%%%s" % (
            name, "yes" if closed else "no", mark, med, rate,
            ("   drawn loosely it becomes %s" % top) if top else ""))
    print("\n  TWO WAYS TO FAIL, and the read rate only shows one of them.")
    print("  RETRACE (marked !) is a glyph that cannot be DRAWN in one pass: a `4`")
    print("  spends a fifth of its length running back up the stem to reach the")
    print("  top, and a `b` a sixth. Both score 100% here, because the template")
    print("  was built from the same doubled path — which is exactly the trap. No")
    print("  player draws the join the same way twice. Open them up (`4 open`,")
    print("  `b open`) and the shape survives with nothing to reproduce.")
    print("  CLOSURE is the other, and it is not curvature. `life` is the")
    print("  alphabet's only closed shape, and not-quite-closing is what hands do")
    print("  without noticing. Every closed candidate inherits it: an open box")
    print("  reads as a circle, and a heart reads as a reverse spiral.")


def main():
    ap = argparse.ArgumentParser(description="Rune legibility under stress")
    ap.add_argument("--hand", action="store_true", help="only the loop test")
    ap.add_argument("--thermal", action="store_true", help="only the degradation test")
    ap.add_argument("--swap", action="store_true",
                    help="score candidate glyphs by swapping them in")
    args = ap.parse_args()
    if args.swap:
        swap_report()
        return 0
    if not args.thermal:
        hand_report()
        print()
    if not args.hand:
        fragile = thermal_report()
        if fragile:
            print("\n  Fragile under throttling: %s" % ", ".join(fragile))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
