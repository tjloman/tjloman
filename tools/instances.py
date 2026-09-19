#!/usr/bin/env python3
"""NOTHING IS DRAWN THAT NOBODY WROTE.

A MultiMesh is the one thing in this game that can hold a transform NOBODY PUT
THERE. `instance_count` allocates a buffer; the transforms are written one at a
time afterwards; and whatever an unwritten instance holds is whatever the buffer
had when it was resized. One of those is one mesh — an animal, a tree, a flower
— drawn somewhere nobody chose at a scale nobody chose, which is the shape of
the artifact that came and went in this world for a fortnight:

    a flat-shaded surface across half the screen, in the colour of something,
    that goes away when you walk far enough for the thing to be rebuilt, and
    comes back a moment later

Every MultiMesh in the game allocates and then writes every instance in the same
breath, and is safe by construction. Except one. A herd's book is four hundred
head and the transforms are written for the ones actually OUT, a slice a tick on
a round robin, so everything from `_simulated()` up to the book has to be put
somewhere by hand — and the collapse that did it only ran when the barn changed
how many it was showing. A calf born in a barn herd grows the book without
changing that, and barns breed all day.

So: two rules, and the second one is the one that cannot be got round.

  EVERY ALLOCATION WRITES WHAT IT ALLOCATED. Either every instance in the same
  function, or through a door that collapses the new ones.

  AND THE RENDERER CANNOT REACH PAST WHAT WAS WRITTEN. `visible_instance_count`
  is what the field is for, it costs nothing, and it makes the first rule
  structural rather than a habit.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def code(text):
    return "\n".join(r.split("#")[0].rstrip() for r in text.split("\n")
                     if r.split("#")[0].strip())


def func_at(src, lineno):
    """The name of the function a given line of stripped source sits in."""
    here = "(top level)"
    for n, row in enumerate(src.split("\n"), 1):
        found = re.match(r"^(?:static )?func (\w+)\(", row)
        if found:
            here = found.group(1)
        if n >= lineno:
            return here
    return here


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
sites = []
for path in sorted((ROOT / "scripts").rglob("*.gd")):
    src = code(path.read_text())
    for n, row in enumerate(src.split("\n"), 1):
        if not re.search(r"\.instance_count\s*=", row):
            continue
        if "visible_instance_count" in row:
            continue
        # Allocating NOTHING is the one allocation with nothing to write.
        if re.search(r"instance_count\s*=\s*0\s*$", row):
            continue
        sites.append((path, func_at(src, n), row.strip()))

print("%d place(s) allocate a MultiMesh:" % len(sites))
for path, fn, row in sites:
    body = body_of(path.read_text(), fn)
    # Written in the same breath: every instance, right here.
    writes_all = any("set_instance_transform(i" in r for r in body) \
        or any("_write_layers()" in r for r in body)
    # Or through a door that collapses whatever it just added.
    through_a_door = "_book_is(" in row or any(
        "set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))" in r
        for r in body)
    # Or the renderer is held to what was written.
    capped = any("visible_instance_count" in r for r in body)
    ok = writes_all or through_a_door or capped
    print("   %-26s %-22s %s"
          % (path.name, fn + "()",
             "writes what it allocates" if ok else "LEAVES INSTANCES UNWRITTEN"))
    if not ok:
        fail.append("%s:%s allocates MultiMesh instances and does not write "
                    "them, cap them with visible_instance_count, or hand them "
                    "to a door that collapses them — so whatever the buffer had "
                    "is drawn as a mesh, somewhere, at some size"
                    % (path.name, fn))

# -- AND THE ONE THAT WRITES IN SLICES IS HELD TO WHAT IT HAS WRITTEN --------
HERD = (ROOT / "scripts/animals/herd.gd").read_text()
book = body_of(HERD, "_book_is")
collapses = any("for i in range(was, count)" in r for r in book)
writing = body_of(HERD, "_write_transforms")
held = any("visible_instance_count = live" in r for r in writing)
print()
print("A HERD'S BOOK %s, and the renderer %s."
      % ("collapses every head it adds" if collapses else "ADDS HEADS NOBODY WRITES",
         "sees only what is out" if held else "SEES THE WHOLE BOOK"))
if not collapses:
    fail.append("growing a herd's book leaves the new indices unwritten, and a "
                "calf is born in a barn herd every few seconds")
if not held:
    fail.append("a herd draws its whole book rather than the head that are "
                "actually out — which is both the artifact's only way onto the "
                "screen and four hundred instances of drawing where twelve "
                "would do")

# AND THE BOOK IS SIZED AFTER THE MESH IS ON IT.
#
# Writing a transform makes the server rebuild the MultiMesh's bounding box,
# which it cannot do with no mesh — so sizing the book before assigning the mesh
# printed a C++ error once per herd per chunk, thousands of times, on every
# load. It is harmless and it is still an error nobody can then read past.
build = code(HERD)
build = build[build.index("func _build_multimesh("):]
build = build[:build.index("\nfunc ", 1)] if "\nfunc " in build[1:] else build
mesh_at = build.index("_mm.mesh =") if "_mm.mesh =" in build else -1
book_at = build.index("_book_is(") if "_book_is(" in build else -1
ordered = mesh_at >= 0 and book_at >= 0 and mesh_at < book_at
print("THE BOOK IS SIZED %s."
      % ("once there is a mesh on it" if ordered else "BEFORE THERE IS ANYTHING TO DRAW"))
if not ordered:
    fail.append("the herd sizes its book before putting a mesh on it, and "
                "writing a transform then asks the server to rebuild a bounding "
                "box it has nothing to build one from — one C++ error per herd "
                "per chunk, on every load")

# AND A MODEL STANDS ON ITS FEET, wherever its pivot happens to be. The README
# asks for one at the feet; a model nobody moved off its centre is buried to the
# waist, and a herd is forty of them.
BANK = (ROOT / "scripts/model_bank.gd").read_text()
ANIMAL = (ROOT / "scripts/animals/animal.gd").read_text()
measured = any("bounds(model_name).position.y" in r
               for r in body_of(BANK, "footing"))
seated = "ModelBank.footing(" in code(HERD) and "ModelBank.footing(" in code(ANIMAL)
print("A MODELLED BEAST STANDS %s."
      % ("on its feet, measured" if measured and seated
         else "WHEREVER ITS PIVOT HAPPENS TO BE"))
if not measured:
    fail.append("nothing measures how far a model's pivot sits above its lowest "
                "point, so every caller is trusting a line in a README about "
                "files it has never seen")
if not seated:
    fail.append("a herd and a single beast do not seat their model the same "
                "way, so a promoted animal stands at a different height from "
                "the herd it came out of")

# AND EVERY DOOR IN THAT FILE IS THE SAME DOOR.
# The door's own line is the door, so it does not count against it.
raw = [r for r in code(HERD).split("\n")
       if re.search(r"_mm\.instance_count\s*=", r) and r not in book]
print("IT IS SAID IN %d place(s) outside the door." % len(raw))
if raw:
    fail.append("%d place(s) in herd.gd still set `instance_count` directly, "
                "so the collapse is a thing that happens at some of them"
                % len(raw))

print()
if fail:
    for line in fail:
        print("BROKEN: " + line)
    sys.exit(1)
print("OK: every instance drawn is one somebody put there.")
