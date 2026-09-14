#!/usr/bin/env python3
"""CAN THE GOD HEAR WHAT THEY ARE LOOKING AT?

Godot's default audio listener is the current Camera3D, which is right for
almost every game because the camera is roughly the player's head. This camera
is not a head: CameraRig orbits a point on the ground from between MIN_ZOOM and
MAX_ZOOM metres out, and a sound placed with SoundBank.play_at carries about
fifty before its hard cutoff.

Which means the game got quieter the further you pulled back, and at a survey
zoom -- which is where a god game is actually played -- a village burning in
front of you made no sound at all. Not muffled: past max_distance a source is
silent, full stop.

This reports the EAR-TO-SOURCE distance at each zoom against the cutoff, under
the camera as listener and under Ear, which stands on the ground the god is
looking at and leans toward their hand. It reasons only about the hard cutoff,
not about the attenuation curve inside it: the curve is Godot's and guessing at
its exact shape here would make this lie confidently, which is worse than not
having it.

Every number is read off the source.
"""
import argparse
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RIG = (ROOT / "scripts/player/camera_rig.gd").read_text()
EAR = (ROOT / "scripts/audio/ear.gd").read_text()
BANK = (ROOT / "scripts/audio/sound_bank.gd").read_text()
AGIT = (ROOT / "scripts/world/agitation.gd").read_text()


def const(text, name, where):
    m = re.search(r"^const %s\s*:?=\s*(-?[0-9.]+)" % name, text, re.M)
    if not m:
        sys.exit("could not read %s off %s" % (name, where))
    return float(m.group(1))


MIN_ZOOM = const(RIG, "MIN_ZOOM", "camera_rig.gd")
MAX_ZOOM = const(RIG, "MAX_ZOOM", "camera_rig.gd")
TOWARD_HAND = const(EAR, "TOWARD_HAND", "ear.gd")
EAR_HEIGHT = const(EAR, "EAR_HEIGHT", "ear.gd")
HEARD_WITHIN = const(AGIT, "HEARD_WITHIN", "agitation.gd")

# The two ways a sound gets made, and how far each carries before its cutoff.
FIXED = float(re.search(r"p\.max_distance = ([0-9.]+)", BANK).group(1))
RIDES = float(re.search(r"reach := ([0-9.]+)", BANK).group(1))


def camera_at(zoom):
    """CameraRig puts the camera at local +Z * zoom_distance from the rig, so
    its distance from the point it orbits is the zoom, whatever the pitch."""
    return zoom


def ear_at(hand_out):
    """Ear stands on the focus point and leans TOWARD_HAND of the way to the
    hand. `hand_out` is how far the hand is from that point."""
    flat = hand_out * TOWARD_HAND
    return math.hypot(flat, EAR_HEIGHT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hand-out", type=float, default=12.0,
                    help="how far the hand is from the point the camera orbits")
    args = ap.parse_args()

    print("read off the source: zoom %.1f..%.0fm, TOWARD_HAND %.2f, "
          "fixed sound carries %.0fm, a sound that rides its body %.0fm\n"
          % (MIN_ZOOM, MAX_ZOOM, TOWARD_HAND, FIXED, RIDES))
    print("A cry is made at the point the camera is looking at; the hand is "
          "%.0fm off it.\n" % args.hand_out)
    print("%-8s %14s %12s %14s %12s"
          % ("ZOOM", "CAMERA AS EAR", "HEARD?", "Ear", "HEARD?"))

    bad = []
    zooms = [MIN_ZOOM, 10.0, 20.0, 35.0, 50.0, MAX_ZOOM]
    for zoom in zooms:
        cam = camera_at(zoom)
        ear = ear_at(args.hand_out)
        cam_ok = cam <= FIXED
        ear_ok = ear <= RIDES
        if not ear_ok:
            bad.append("at %.0fm zoom the ear is %.0fm from the cry, past its "
                       "%.0fm reach" % (zoom, ear, RIDES))
        print("%-7.0fm %13.0fm %12s %13.0fm %12s"
              % (zoom, cam, "yes" if cam_ok else "SILENT",
                 ear, "yes" if ear_ok else "SILENT"))

    # And the gate that decides whether the cry is worth making at all has to
    # be no tighter than the mixer, or it refuses audible sounds.
    if HEARD_WITHIN > RIDES:
        bad.append("Agitation.HEARD_WITHIN (%.0fm) is wider than the reach a "
                   "cry is given (%.0fm), so cries are made that cannot be "
                   "heard" % (HEARD_WITHIN, RIDES))

    print("\nHEARD? is the HARD CUTOFF only — past max_distance a source is"
          "\nsilent outright. How loud it is inside that is Godot's curve and"
          "\nis deliberately not guessed at here."
          "\n\nThe camera column is what the game did before Ear existed: at a"
          "\nsurvey zoom a village burning in front of you made no sound.")
    if bad:
        print("\nFAIL:")
        for line in bad:
            print("  " + line)
        return 1
    print("\nOK: the god hears what they are looking at at every zoom.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
