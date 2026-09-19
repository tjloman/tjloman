#!/usr/bin/env python3
"""A THROWN TREE GOES OVER THE GROUND, NOT THROUGH IT.

A tree does not fly on Godot's physics — it integrates its own arc, because a
thirty-metre trunk with a collision capsule on it costs more than every animal
in the world put together. What it flew as was a POINT: its own origin, which
is the foot of the trunk. So the only part of a tree that could ever touch the
ground was the stump, and for half of every turn the crown was inside the
hillside. It cut through the land like a knife.

    "they need another point of collision detection at the top, so that it
     tumbles across the terrain, bouncing like a humongous tumbleweed end over
     end above the terrain"

Three things had to change together and none of them works alone:

  BOTH ENDS ARE ASKED, and the deeper one is the one that struck.
  IT TURNS ABOUT ITS MIDDLE, not its stump — `global_rotate` can only turn a
  body about its own origin, which swung the crown through an arc as long as
  the tree while the foot rode the parabola.
  AND IT GOES OVER FORWARD. The old spin axis was the right line in the wrong
  sense: the crown went over backwards, against the direction of travel.

And then a fourth, which the simulation below is what found: the arc is cut
into slices of its own rather than taken a frame at a time. An end sweeping
fifteen metres about the middle crosses two metres between two tests on a
tenth-of-a-second frame, and a tenth of a second is exactly the frame a god is
throwing trees on.

So this file checks the three, and then throws a thirty-metre spruce down a
hillside and measures how far into the ground either end ever gets.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TREE = (ROOT / "scripts/world/wild_tree.gd").read_text()


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
    found = re.search(r"^const %s := ([-\d.]+)" % name, TREE, re.M)
    return float(found.group(1)) if found else None


fail = []
# BOTH HALVES OF THE FLIGHT. `_fly` cuts the frame into slices and `_fly_step`
# is one of them, and which half a given line sits in is not the point of any
# check below — reading only the one the code happened to be in last week is
# how tools/stuck.py came to call a healthy state a dead end.
flying = body_of(TREE, "_fly") + body_of(TREE, "_fly_step")
bouncing = body_of(TREE, "_bounce")

# -- THE THREE STATEMENTS ----------------------------------------------------
two_ends = any("under_crown" in r for r in flying) \
    and any("under_foot" in r for r in flying) \
    and any("maxf(under_foot, under_crown)" in r for r in flying)
print("A FLYING TREE %s."
      % ("is two ends" if two_ends else "IS ONE POINT, AND IT IS THE STUMP"))
if not two_ends:
    fail.append("only one end of the trunk is tested against the ground, so the "
                "other one goes through the hillside for half of every turn")

about_middle = any("_turn_about(_middle()" in r for r in flying) \
    and not any("global_rotate(" in r for r in flying)
print("IT TURNS %s."
      % ("about its middle" if about_middle else "ABOUT ITS OWN STUMP"))
if not about_middle:
    fail.append("the tree turns about its origin, which is the foot of the "
                "trunk — so the crown swings through an arc as long as the tree "
                "while the foot rides the parabola, and nothing that tests the "
                "ends can keep up with it")

forward = any("Vector3.UP.cross(along)" in r for r in bouncing)
print("AND IT GOES OVER %s."
      % ("the way it is going" if forward else "BACKWARDS, AGAINST ITS TRAVEL"))
if not forward:
    fail.append("the tumble axis tips the crown against the direction of "
                "travel: the tree rolls backwards, which nothing thrown has "
                "ever done")

sliced = any("FLIGHT_STEP" in r for r in flying) \
    and any("while " in r for r in flying)
print("AND THE ARC IS %s."
      % ("cut into slices of its own" if sliced else "TAKEN A FRAME AT A TIME"))
if not sliced:
    fail.append("the flight is integrated a frame at a time, so how far a "
                "swinging end steps between two ground tests is decided by how "
                "well the machine happens to be running")

# AND THE TRUNK IS MEASURED ALONG A UNIT AXIS. A Basis carries the node's
# SCALE, and a tree's scale is how big it is — `basis.y` on a full-grown spruce
# is five units long and `current_height()` already has that five in it, so the
# unnormalized version puts the crown twenty-five times its own length away and
# tests the ground somewhere over the next valley.
along = body_of(TREE, "_up_the_trunk")
unit = any("normalized()" in r for r in along)
crowned = all(any("_up_the_trunk()" in r for r in body_of(TREE, f))
              for f in ("_crown", "_middle"))
print("THE TRUNK IS MEASURED %s."
      % ("along a unit axis" if unit and crowned else "IN UNITS OF ITS OWN SCALE, SQUARED"))
if not unit or not crowned:
    fail.append("the far end of the trunk is found by multiplying the basis Y "
                "(which carries the scale) by a height that already carries the "
                "scale — so the crown of a grown tree is computed at twenty-five "
                "times its own length and nothing about the tumble is real")

lifts = any("global_position.y += buried" in r for r in bouncing)
if not lifts:
    fail.append("the bounce sets the ORIGIN on the ground rather than lifting "
                "the trunk by however deep the struck end was — which puts the "
                "foot on the grass and leaves the crown exactly as far under it "
                "as it was")
# THE ASSIGNMENTS, not the word `_middle`, which also appears on the line that
# turns the tree — so looking for the name said the settling was handled while
# it was being deleted.
rests = any("global_position.x = " in r for r in flying) \
    and any("global_position.z = " in r for r in flying)
if not rests:
    fail.append("a tree that comes to rest is stood up at its origin, and its "
                "origin is the foot — so a trunk that stopped lying across a "
                "slope springs upright metres from where it was watched to stop")

# -- AND THEN THROW ONE ------------------------------------------------------
G = number("TREE_GRAVITY") or 20.0
SETTLE = number("SETTLE_UNDER") or 5.5
KEEP = number("BOUNCE_KEEP") or 0.34
SLIDE = number("BOUNCE_SLIDE") or 0.72
PER_SPEED = number("TUMBLE_PER_SPEED") or 0.09
MOST = number("TUMBLE_MOST") or 7.0
KICK = number("CROWN_KICK") or 1.0
SLICE = number("FLIGHT_STEP") or 1.0
MOST_FLIGHT = number("FLIGHT_MOST") or 1.0
HEIGHT = 30.0                      # a full-grown spruce


def ground(x, z):
    """Rolling country with a hill in it."""
    return 3.0 * math.sin(x / 12.0) + 2.0 * math.cos(z / 9.0) - x * 0.06


def rotate(v, axis, rad):
    """Rodrigues, so the simulation turns things the way Basis(axis, rad) does."""
    ax, ay, az = axis
    n = math.sqrt(ax * ax + ay * ay + az * az) or 1.0
    ax, ay, az = ax / n, ay / n, az / n
    c, s = math.cos(rad), math.sin(rad)
    dot = v[0] * ax + v[1] * ay + v[2] * az
    cross = (ay * v[2] - az * v[1], az * v[0] - ax * v[2], ax * v[1] - ay * v[0])
    return tuple(v[i] * c + cross[i] * s + (ax, ay, az)[i] * dot * (1.0 - c)
                 for i in range(3))


def throw(two_ends=True, about_middle=True, forward=True, sliced=True,
          fps=60.0, speed=18.0):
    """One flight, with each of the four changes switchable — so the before and
    after below are the same code rather than two stories."""
    frame = 1.0 / fps
    step = min(frame, SLICE) if sliced else frame
    pos = [0.0, ground(0.0, 0.0) + 2.0, 0.0]
    up = (0.0, 1.0, 0.0)                    # local +Y: up the trunk
    vel = [speed, speed * 0.5, 0.0]
    spin_axis, spin_rate = (0.0, 0.0, -1.0), math.radians(220.0)
    worst, bounces, flying, lived = 0.0, 0, True, 0.0
    while flying and lived < 30.0:
        left = min(frame, MOST_FLIGHT) if sliced else frame
        lived += frame
        while left > 0.0 and flying:
            dt = min(left, step)
            left -= dt
            vel[1] -= G * dt
            for i in range(3):
                pos[i] += vel[i] * dt
            if spin_rate > 0.001:
                # About the middle of the trunk, or about the foot, which is
                # what `global_rotate` can do and all it can do.
                arm_len = HEIGHT * (0.5 if about_middle else 0.0)
                pivot = [pos[i] + up[i] * arm_len for i in range(3)]
                up = rotate(up, spin_axis, spin_rate * dt)
                arm = rotate(tuple(pos[i] - pivot[i] for i in range(3)),
                             spin_axis, spin_rate * dt)
                pos = [pivot[i] + arm[i] for i in range(3)]
            foot = pos[1] - ground(pos[0], pos[2])
            tip = [pos[i] + up[i] * HEIGHT for i in range(3)]
            crown = tip[1] - ground(tip[0], tip[2])
            # What the code SEES, against what is actually true of the tree.
            seen = min(foot, crown) if two_ends else foot
            worst = max(worst, -min(foot, crown))
            if seen > 0.0:
                continue
            fast = math.sqrt(sum(v * v for v in vel))
            if fast <= SETTLE:
                flying = False
                break
            bounces += 1
            pos[1] += -seen + 0.05
            flat = math.hypot(vel[0], vel[2])
            along = (vel[0] / flat, 0.0, vel[2] / flat) if flat > 0.5 \
                else (0.0, 0.0, -1.0)
            # UP x along tips it the way it is going; along x UP is the old sense.
            spin_axis = ((-along[2], 0.0, along[0]) if forward
                         else (along[2], 0.0, -along[0]))
            spin_rate = min(max(fast * PER_SPEED, 0.6), MOST)
            if two_ends and crown < foot:
                spin_rate *= KICK
            vel = [vel[0] * SLIDE, abs(vel[1]) * KEEP, vel[2] * SLIDE]
    return worst, bounces, pos[0], lived


print()
print("A THIRTY-METRE SPRUCE thrown at 18 m/s down a hillside, at 60 frames:")
print("   %-24s %-9s %-8s %-9s %s"
      % ("", "deepest", "bounces", "carried", "flight"))
for label, kw in [("as it flew before", dict(two_ends=False, about_middle=False,
                                             forward=False, sliced=False)),
                  ("with both ends", dict(about_middle=False, forward=False,
                                          sliced=False)),
                  ("and about its middle", dict(forward=False, sliced=False)),
                  ("and going over forward", dict(sliced=False)),
                  ("and sliced", dict())]:
    worst, bounces, carried, secs = throw(**kw)
    print("   %-24s %6.1fm %8d %8.1fm %5.1fs" % (label, worst, bounces, carried, secs))
print()
print("   'deepest' is how far the worse end of the trunk ever got BELOW the")
print("   ground. Half a tree is what it looks like when a thirty-metre trunk")
print("   pivots on its stump; a few centimetres is a tree touching the earth.")

print()
print("AND ON A FRAME THAT IS STRUGGLING, which is when a god throws things:")
print("   %-10s %-14s %s" % ("frames", "a frame at a time", "sliced"))
for fps in (60, 30, 15, 9):
    rough = throw(sliced=False, fps=fps)[0]
    fine = throw(fps=fps)[0]
    print("   %-10d %11.1fm %12.1fm" % (fps, rough, fine))

worst, bounces, carried, _s = throw()
if worst > 1.0:
    fail.append("a thrown tree still ends up %.1fm inside the hillside at its "
                "worst, which is what this was meant to stop" % worst)
if bounces < 2:
    fail.append("it does not tumble: %d bounce before it settles, and a "
                "tumbleweed is the several after the first" % bounces)
for fps in (30, 15, 9):
    fine = throw(fps=fps)[0]
    rough = throw(sliced=False, fps=fps)[0]
    if fine > 1.5 or fine >= rough:
        fail.append("at %d frames a second the trunk gets %.1fm into the ground "
                    "against %.1f taking the frame whole — the slicing is not "
                    "holding where it matters, which is a machine in trouble"
                    % (fps, fine, rough))
        break

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: it goes over the ground, end over end, the way it is travelling.")
