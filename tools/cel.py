#!/usr/bin/env python3
"""THE LIGHT CUT INTO BANDS, AND THE REGISTER THAT MAKES IT A TOGGLE.

    "I think we need to add a cel-shading render filter... It should be
     toggle-able in-menu."

The obvious way to do this is a full-screen filter, and this game cannot have
one: it runs on the MOBILE renderer, where `hint_normal_roughness_texture`
fails to compile outright, so the usual depth-and-normal edge detect is not
available at all. Screen texture is, but sampling it forces the shader into the
transparent pipeline and pays for a full screen copy -- on the phones and iPads
this is built for, that is the wrong place to spend fill rate.

So the light is banded per material instead. And there is no one material here:
water that goes opaque on a budget phone, foliage on scissor-cut billboards,
crops coloured per vertex, critters drawn deliberately unlit, and a hundred
ordinary painted parts -- seventeen places that each build their own. None of
them can be funnelled through a single builder without losing what makes it
itself. So they are REGISTERED instead, and this file guards the four things
about that register that go silently wrong.

  EVERY MATERIAL IS IN IT. One site that builds its own and never registers is
  one object that stays smooth while the world goes banded -- and it will be
  the water, or the trees, because those are the ones with settings worth
  writing by hand.

  THE REFERENCES ARE WEAK, AND IT SWEEPS. Terrain streams: a register holding
  chunk materials by the hand keeps every material of every chunk the player
  ever walked through alive for the session.

  TURNING IT OFF PUTS BACK WHAT WAS THERE, not a default this code guessed at.
  Naming the engine's default diffuse mode would be a guess that compiles.

  AND NOTHING UNLIT IS TOUCHED. A critter and a storm cloud have no lighting to
  band, and re-lighting them is a different bug in each.

WHAT THIS FILE CANNOT TELL YOU, and nobody should pretend otherwise: whether
the Mobile renderer honours StandardMaterial3D's built-in toon modes at all.
Forward+ does. That wants one minute in the editor, and if the answer is no,
the fix is `Util._cel_one` and nothing else -- which is the whole reason the
feature is built as a register rather than around a shader.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
UTIL = (ROOT / "scripts/util.gd").read_text()
STATE = (ROOT / "scripts/game_state.gd").read_text()
RITES = (ROOT / "scripts/ui/temple_rites.gd").read_text()


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


fail = []

# -- EVERY MATERIAL IS IN THE REGISTER ---------------------------------------
#
# Counted per FILE rather than per line, because a site may hand its material
# on in a dozen ways; what may not happen is a file that builds one and never
# says so.
print("WHO BUILDS MATERIALS, AND WHETHER THEY REGISTER THEM:")
total, registered = 0, 0
for path in sorted(ROOT.glob("scripts/**/*.gd")):
    text = code(path.read_text())
    made = text.count("StandardMaterial3D.new()")
    if not made:
        continue
    marks = len(re.findall(r"(?<!func )\blit\(", text))
    total += made
    registered += min(marks, made)
    print("   %-38s builds %d, registers %d  %s"
          % (path.relative_to(ROOT), made, marks,
             "" if marks >= made else "<-- ONE GOES UNMARKED"))
    if marks < made:
        fail.append("%s builds %d materials and registers %d — whatever it "
                    "builds stays smooth while the rest of the world goes "
                    "banded, and it will be noticed as 'the water looks wrong'"
                    % (path.relative_to(ROOT), made, marks))
print("   %d materials built across the game, all of them registered." % total)

# -- WEAK, AND IT SWEEPS -----------------------------------------------------
keeping = body_of(UTIL, "lit")
weak = any("weakref(m)" in r for r in keeping)
sweeps = any("_sweep()" in r for r in keeping)
sweeping = body_of(UTIL, "_sweep")
drops = any("get_ref() != null" in r for r in sweeping)
print()
print("THE REGISTER HOLDS MATERIALS %s and %s."
      % ("weakly" if weak else "BY THE HAND",
         "sweeps itself" if sweeps and drops else "NEVER LETS GO"))
if not weak:
    fail.append("the register keeps a strong reference to every material ever "
                "built, so every chunk the player walks through stays in "
                "memory for the session — terrain streams, and this is how a "
                "walk across the world becomes a leak")
if not sweeps or not drops:
    fail.append("nothing sweeps the dead out of the register as it grows, so "
                "it keeps a row per material ever made even once they are all "
                "empty")

# -- OFF PUTS BACK WHAT WAS THERE --------------------------------------------
marking = body_of(UTIL, "_cel_one")
restores = any("was_diffuse" in r for r in marking)
guessed = [r for r in marking if re.search(r"DIFFUSE_(BURLEY|LAMBERT)", r)]
skips_unlit = any("SHADING_MODE_UNSHADED" in r for r in marking)
bands = any("DIFFUSE_TOON" in r for r in marking)
print("TURNING IT OFF %s, and unlit things %s."
      % ("puts back what each material was born with" if restores and not guessed
         else "SETS A DEFAULT THIS CODE GUESSED AT",
         "are left alone" if skips_unlit else "GET RE-LIT"))
if not restores or guessed:
    fail.append("turning cel shading off writes a named default (%s) instead "
                "of what each material was born with — a guess that compiles, "
                "and one that quietly overrides any part that chose its own "
                "lighting" % (guessed[0].strip() if guessed else "no original kept"))
if not skips_unlit:
    fail.append("_cel_one does not skip unshaded materials, so critters and "
                "storm clouds — drawn unlit on purpose — get lighting they "
                "were never meant to have")
if not bands:
    fail.append("_cel_one no longer bands anything, so the toggle is a "
                "preference that does nothing")

# -- AND IT IS A TOGGLE, SAVED, APPLIED AT STARTUP ---------------------------
in_menu = "cel.toggled.connect(_set_cel)" in code(RITES)
setter = any("Util.cel_shading(value)" in r for r in
             code(STATE).split("\n"))
saved = 'cfg.set_value("look", "cel_shading"' in code(STATE)
at_start = any("load_settings()" in r for r in body_of(STATE, "_ready"))
reads = any("cel_shading" in r for r in body_of(STATE, "load_settings"))
print()
print("IT IS %s, %s, and %s."
      % ("in the menu" if in_menu else "NOT IN THE MENU",
         "saved" if saved else "NOT SAVED",
         "applied at startup" if at_start and reads else "APPLIED ONLY ONCE "
         "SOMEBODY OPENS THE SETTINGS SCREEN"))
if not in_menu:
    fail.append("there is no checkbox for it, and the request was for "
                "something toggle-able in-menu")
if not setter:
    fail.append("setting GameState.cel_shading does not reach Util, so the "
                "flag moves and the world does not")
if not saved:
    fail.append("the choice is not written to the settings file, so it is "
                "forgotten every time the game closes")
if not at_start or not reads:
    fail.append("the settings file is not read at startup — the screen that "
                "used to read it is only built when somebody walks into that "
                "room of the temple, so a saved preference applied on the day "
                "the player went and looked at it")

print()
if fail:
    for why in fail:
        print("FAIL: %s" % why)
    sys.exit(1)
print("PASS: every material registered, held weakly and swept, put back the "
      "way it was, and the choice is saved and applied before anyone asks.")
