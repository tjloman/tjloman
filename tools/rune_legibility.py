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
    for teeth in (3.0, 4.0, 5.0, 6.0, 7.0):
        for depth in (60.0, 95.0):
            for flip in (1.0, -1.0):
                def zz(t, T=teeth, D=depth, F=flip):
                    n = t * T
                    up = 1.0 if int(n) % 2 == 1 else -1.0
                    return (t * 200.0, F * up * abs((n % 1.0) * 2.0 - 1.0) * D)
                add("zigzag", zz)
                def zz2(t, T=teeth, D=depth, F=flip):
                    n = t * T
                    up = 1.0 if int(n) % 2 == 1 else -1.0
                    return (F * up * abs((n % 1.0) * 2.0 - 1.0) * D, t * 200.0)
                add("zigzag", zz2)
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
    "zigzag": lambda t: (120 + t * 300,
                         300 - (1.0 if int(t * 5.0) % 2 == 1 else -1.0)
                         * abs((t * 5.0 % 1.0) * 2.0 - 1.0) * 80.0),
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


def main():
    ap = argparse.ArgumentParser(description="Rune legibility under stress")
    ap.add_argument("--hand", action="store_true", help="only the loop test")
    ap.add_argument("--thermal", action="store_true", help="only the degradation test")
    args = ap.parse_args()
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
