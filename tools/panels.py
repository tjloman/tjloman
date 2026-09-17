#!/usr/bin/env python3
"""A PANEL ANCHORED TO AN EDGE MUST GROW ONTO THE SCREEN, AND MUST HAVE A SIZE.

Two ways for a Godot panel to end up somewhere nobody can read it, and this
codebase has now found both of them.

A PLAIN Control LAYS NOTHING OUT. It has no minimum size of its own however much
is inside it — that is what a Container is FOR — so anchoring one with
PRESET_MODE_MINSIZE pins a rect of zero width and height at the corner. Anything
added inside that rect is not positioned by it at all: it sits at the corner and
grows whichever way it likes. From a RIGHT edge, that is off the screen. The
frame meter was built this way and ran off the right-hand side of a desktop
display, which is how it was found.

AND THE DEFAULT GROWS THE WRONG WAY AT TWO OF THE FOUR EDGES. `grow_horizontal`
defaults to END and `grow_vertical` to END, which from a LEFT or TOP edge point
onto the screen and from a RIGHT or BOTTOM edge point off it. HUD._build_roster
carries the note: "Right by luck until now... the same omission on a
right-anchored panel put the workshop drawer off it."

So: twice, in two different files, the same two lines. That is what a tool is
for.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = sorted((ROOT / "scripts").rglob("*.gd"))

## The presets whose edge points OFF the screen under the default growth.
LEANS_RIGHT = ("PRESET_TOP_RIGHT", "PRESET_BOTTOM_RIGHT", "PRESET_CENTER_RIGHT")
LEANS_DOWN = ("PRESET_BOTTOM_LEFT", "PRESET_BOTTOM_RIGHT", "PRESET_CENTER_BOTTOM")
## Growth that reaches back onto the screen from such an edge.
INWARD = ("GROW_DIRECTION_BEGIN", "GROW_DIRECTION_BOTH")


def code(text):
    """Source with its comments taken out. A note about a thing is not it."""
    return "\n".join(r.split("#")[0].rstrip() for r in text.split("\n")
                     if r.split("#")[0].strip())


def is_a_container(kind):
    """Does this class work out its own minimum size from what is inside it?

    Every Container in Godot is named for it, which is the whole convention —
    and the ones that are NOT (Control, Panel, ColorRect) are exactly the ones
    that lay nothing out. A `Panel` is a Control with a background, not a box
    that holds things.
    """
    return kind.endswith("Container")


def kind_of(text, who, extends):
    """What class the thing being anchored actually is.

    `who` is the receiver, or "" for a bare call — which means `self`, and self
    is whatever the file extends. Anything else is a variable, and its class is
    read off however it was declared or built in this same file.
    """
    if who == "":
        return extends
    said = re.search(r"var %s\s*:\s*(\w+)" % re.escape(who), text)
    if said:
        return said.group(1)
    built = re.search(r"%s\s*:?=\s*(\w+)\.new\(\)" % re.escape(who), text)
    if built:
        return built.group(1)
    made = re.search(r"var %s\s*:?=\s*(\w+)\.new\(\)" % re.escape(who), text)
    return made.group(1) if made else "?"


def statement_at(rows, i):
    """The whole call, which is routinely wrapped over two or three lines."""
    whole = rows[i]
    j = i
    while whole.count("(") > whole.count(")") and j + 1 < len(rows):
        j += 1
        whole += " " + rows[j].strip()
    return whole, j


fail = []
seen = 0
print("%-34s %-22s %-18s %s" % ("WHERE", "ANCHORED", "IS A", "GROWS"))
for path in FILES:
    raw = path.read_text()
    text = code(raw)
    rows = text.split("\n")
    extends = (re.search(r"^extends (\w+)", text, re.M) or [None, "?"])[1] \
        if re.search(r"^extends (\w+)", text, re.M) else "?"
    i = 0
    while i < len(rows):
        if "set_anchors_and_offsets_preset(" not in rows[i]:
            i += 1
            continue
        whole, end = statement_at(rows, i)
        i = end + 1
        seen += 1
        who = (re.search(r"(\w+)\.set_anchors_and_offsets_preset\(", whole)
               or [None, ""])[1] if "." in whole.split("set_anchors")[0] else ""
        preset = (re.search(r"(PRESET_[A-Z_]+)", whole) or [None, "?"])[1]
        kind = kind_of(text, who, extends)
        # WHICH WAY IT IS TOLD TO GROW, read off the same object nearby — the
        # two lines are always written together and a grow set on a different
        # control is not this control's growth.
        near = "\n".join(rows[max(0, end - 6):end + 7])
        want = (re.search(r"%sgrow_horizontal = Control\.(\w+)"
                          % (re.escape(who) + r"\." if who else ""), near)
                or [None, "GROW_DIRECTION_END"])[1]
        down = (re.search(r"%sgrow_vertical = Control\.(\w+)"
                          % (re.escape(who) + r"\." if who else ""), near)
                or [None, "GROW_DIRECTION_END"])[1]
        where = "%s:%s" % (path.relative_to(ROOT / "scripts"), who or "self")
        print("%-34s %-22s %-18s %s / %s"
              % (where[:34], preset.replace("PRESET_", ""), kind,
                 want.replace("GROW_DIRECTION_", ""),
                 down.replace("GROW_DIRECTION_", "")))
        # 1. MINSIZE NEEDS A MINIMUM SIZE.
        if "PRESET_MODE_MINSIZE" in whole and not is_a_container(kind):
            fail.append("%s is a %s and is anchored with PRESET_MODE_MINSIZE — "
                        "a %s lays nothing out and has no minimum size however "
                        "much is inside it, so this pins a rect of ZERO WIDTH "
                        "at the corner and whatever is in it is unpositioned"
                        % (where, kind, kind))
        # 2. AN EDGE-ANCHORED PANEL MUST REACH BACK ONTO THE SCREEN.
        if preset in LEANS_RIGHT and want not in INWARD:
            fail.append("%s is anchored to the RIGHT edge and grows %s, which "
                        "points off the screen — the default is END and it has "
                        "to be said out loud here" % (where, want))
        if preset in LEANS_DOWN and down not in INWARD:
            fail.append("%s is anchored to the BOTTOM edge and grows %s, which "
                        "points off the screen" % (where, down))

print()
print("%d anchored panel(s) read." % seen)
if seen < 8:
    fail.append("only %d anchored panels were found, which is fewer than this "
                "game has — the reader has stopped matching how they are "
                "written" % seen)
print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: every anchored panel has a size and grows onto the screen.")
