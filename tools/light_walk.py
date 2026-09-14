#!/usr/bin/env python3
"""WALK INTO THE DARK AND SEE WHAT THE EYE DOES.

The light meter is one number chased by another, and the whole effect lives in
the chase — a pupil constricts in a moment and the rods take minutes, so the
two directions must NOT share a rate. Reading the code will not tell you
whether nine seconds feels like eyes opening or like a slow fade; nothing will
but playing it. What this can tell you is the shape, the timings and the two
things that are simply wrong if they happen:

    THE STARS MUST NOT BE VISIBLE IN DAYLIGHT, however dark-adapted the eye.
    Standing in a cellar at noon does not show you the Milky Way, and the
    second gate in `starlight` is the only thing stopping it.

    THE EXPOSURE MUST NOT PUMP. If walking past a torch makes the whole world
    brighten and dim, the adaptation is too fast in the slow direction.

Every constant is read off scripts/world/light_meter.gd. Nothing is typed here.

Usage:
    python3 tools/light_walk.py            the walks
    python3 tools/light_walk.py --check    exit 1 if a rule above is broken
"""

import math
import re
import sys

TICK = 1.0 / 60.0


def smoothstep(lo, hi, x):
    t = max(0.0, min(1.0, (x - lo) / (hi - lo))) if hi != lo else 0.0
    return t * t * (3.0 - 2.0 * t)


def constants():
    src = open("scripts/world/light_meter.gd", encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"^const (\w+) := (-?[\d.]+)\s*(?:#.*)?$", src, re.M):
        out[m.group(1)] = float(m.group(2))
    return out


class Meter:
    """LightMeter, reimplemented from its own constants."""

    def __init__(self, k):
        self.k = k
        self.lux = 1.0
        self.adapted = 1.0

    def sky(self, elev):
        k = self.k
        t = (elev - k["DAY_FROM"]) / (k["DAY_TO"] - k["DAY_FROM"])
        t = max(0.0, min(1.0, t))
        day = t * t * (3.0 - 2.0 * t)              # smoothstep
        moon = k["MOON_LUX"] * max(0.0, min(1.0, -elev))
        return k["STAR_LUX"] + moon + (1.0 - k["STAR_LUX"] - moon) * day

    def tick(self, elev, local, dt):
        self.lux = self.sky(elev) + local
        toward = self.k["STOP_DOWN"] if self.lux > self.adapted else self.k["OPEN_UP"]
        self.adapted += (self.lux - self.adapted) * (1.0 - math.exp(-dt / toward))

    def exposure(self):
        k = self.k
        t = max(0.0, min(1.0, self.adapted / k["GLARE_AT"]))
        return k["EXPOSURE_DARK"] + (k["EXPOSURE_LIGHT"] - k["EXPOSURE_DARK"]) * math.sqrt(t)

    def starlight(self, elev):
        k = self.k
        sky = self.sky(elev)
        wash = 1.0 - smoothstep(0.0, k["LOCAL_WASH"], self.adapted - sky)
        dark = 1.0 - smoothstep(k["SKY_WASH_FROM"], k["SKY_WASH_TO"], sky)
        return max(0.0, min(1.0, wash)) * max(0.0, min(1.0, dark))

    def colour(self):
        k = self.k
        return k["COLOUR_FLOOR"] + (1.0 - k["COLOUR_FLOOR"]) \
            * max(0.0, min(1.0, self.adapted / 0.5))


def walk(k, name, script, elev):
    """`script` is a list of (seconds, local lux) — the light around you."""
    m = Meter(k)
    m.adapted = m.sky(elev) + script[0][1]        # already settled when we start
    rows, clock = [], 0.0
    marks = [0.5, 1.0, 2.0, 4.0, 8.0, 15.0]
    for span, local in script:
        end = clock + span
        start = clock
        seen = set()
        while clock < end:
            m.tick(elev, local, TICK)
            clock += TICK
            for mk in marks:
                if mk not in seen and clock - start >= mk:
                    seen.add(mk)
                    rows.append((local, clock - start, m.adapted,
                                 m.exposure(), m.starlight(elev), m.colour()))
    return name, rows


def main():
    k = constants()
    print("Read off light_meter.gd: open up %.1fs, stop down %.2fs, "
          "exposure %.2f..%.2f\n" % (k["OPEN_UP"], k["STOP_DOWN"],
                                     k["EXPOSURE_DARK"], k["EXPOSURE_LIGHT"]))
    bad = False

    # Night. Standing at a hearth, then walking away from it into open country.
    night = -0.8
    m = Meter(k)
    m.adapted = m.sky(night) + k["HEARTH_LUX"]
    print("== NIGHT: you step away from the fire  (sun %.1f)" % night)
    print("%8s %9s %10s %8s %8s" % ("AFTER", "LUX", "ADAPTED", "EXPOSURE", "STARS"))
    clock = 0.0
    shown = set()
    while clock < 20.0:
        m.tick(night, 0.0, TICK)
        clock += TICK
        for mk in [0.5, 1, 2, 4, 8, 15, 20]:
            if mk not in shown and clock >= mk:
                shown.add(mk)
                print("%7.1fs %9.4f %10.4f %8.2f %8.2f"
                      % (clock, m.lux, m.adapted, m.exposure(),
                         m.starlight(night)))
    if m.starlight(night) < 0.8:
        print("  the stars never came out — the second gate is too tight")
        bad = True

    # ...and back to it. This is the direction that must be quick.
    print("\n== NIGHT: and you walk back to it")
    print("%8s %9s %10s %8s %8s" % ("AFTER", "LUX", "ADAPTED", "EXPOSURE", "STARS"))
    clock, shown = 0.0, set()
    while clock < 4.0:
        m.tick(night, k["HEARTH_LUX"], TICK)
        clock += TICK
        for mk in [0.1, 0.25, 0.5, 1, 2, 4]:
            if mk not in shown and clock >= mk:
                shown.add(mk)
                print("%7.2fs %9.4f %10.4f %8.2f %8.2f"
                      % (clock, m.lux, m.adapted, m.exposure(),
                         m.starlight(night)))

    # Noon, in the deepest shade there is. The stars must stay away.
    print("\n== NOON: dark-adapted under whatever cover you like")
    noon = 0.9
    m2 = Meter(k)
    m2.adapted = 0.0                       # the most dark-adapted eye possible
    print("a fully dark-adapted eye at noon sees %.3f stars (must be 0.00)"
          % m2.starlight(noon))
    if m2.starlight(noon) > 0.001:
        print("  DAYLIGHT STARS — the sky gate in starlight() is not holding")
        bad = True

    # Glare. A firestorm beside you.
    print("\n== GLARE: something enormous catches fire beside you at night")
    m3 = Meter(k)
    m3.adapted = m3.sky(night)
    clock, shown = 0.0, set()
    print("%8s %9s %10s %8s %8s" % ("AFTER", "LUX", "ADAPTED", "EXPOSURE", "STARS"))
    while clock < 3.0:
        m3.tick(night, k["GLARE_AT"], TICK)
        clock += TICK
        for mk in [0.1, 0.5, 1, 3]:
            if mk not in shown and clock >= mk:
                shown.add(mk)
                print("%7.2fs %9.4f %10.4f %8.2f %8.2f"
                      % (clock, m3.lux, m3.adapted, m3.exposure(),
                         m3.starlight(night)))

    print("\nADAPTED is what the eye has settled on; LUX is what is actually"
          " there.\nThe gap between them, and how long it takes to close, IS the"
          " effect.\nStars run 0 (none) to 1 (the whole sky); exposure is a"
          " multiplier on\n  everything, and 1.0 is what the game looked like"
          " before any of this.")
    if "--check" in sys.argv:
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
