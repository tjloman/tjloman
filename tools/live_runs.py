#!/usr/bin/env python3
"""THE LIVE CHECKS NOTHING ELSE RUNS, and the source they rest on.

With GODOT set to a Godot binary, runs in a real engine, headless:

  tools/live/kill_live.gd         a beast killed is dead: its herd is told at
                                  once, and the dead row never stands again;
  tools/live/typing_live.gd       the map-name field lets go of the keyboard;
  tools/live/crowd_clock_live.gd  the crowd clock pays every villager, and
                                  walks nobody in a town held still;
  tools/live/seams_live.gd        no cliff where one country meets another;
  tools/live/brush_live.gd        a forage bush burns, by every fire there is;
  tools/live/catch_live.gd        a thrown rock is caught in the air, strikes
                                  what is in its way and lies down in seconds,
                                  and the creature throws back what it catches;
  tools/live/fold_slices_live.gd  a town's land is read a slice a frame;
  tools/live/smooth_live.gd       craters as deep as asked, a crowd clock that
                                  starves nobody, a meter that costs nothing;
  tools/live/kernel_live.gd       the C++ land kernel and its GDScript twins give
                                  the same answers (passes where it is not built);
  tools/live/quench_live.gd       fire meets water at its surface: a gout and a
                                  firestorm fizzle, a fireblast goes off there,
                                  a lavaball throws burning boulders and sets as
                                  new floor; and fresh lava churns until it crusts.
  tools/live/names_live.gd        thousands of names, read in the engine; no two
                                  people in a town share one, and a town saved
                                  full of Pips loses its repeats as it loads.

And always, the statements:

  1. A BEAST'S DEATH IS TOLD TO ITS HERD (Animal.die -> Herd.release), and the
     herd never takes a freed handle for "no body": a freed object compares
     equal to null in Godot 4 (Herd._has_body).
  2. THE CROWD CLOCK WALKS NOBODY HELD STILL: a town being raised is switched
     off, and a switched-off body has no physics space.
  3. A TOWN THE WORLD FOUNDS WHERE ONE IS REMEMBERED is raised from its record
     a few pieces a frame (VillageRaise), not founded and overwritten in one.
  4. THE MAP-NAME FIELD LETS GO OF THE KEYS.
  5. THE LAND'S RUGGEDNESS IS BLENDED ACROSS BORDERS (WorldGen._rugged), never
     read off the biome, whose line made a step metres high.
  6. THE BRUSH BURNS: a forage bush is BURNABLE, the fires that sweep trees by
     name light it too, and a burning tree lights it rather than deleting it.
  7. A THROWN ROCK IS A PROP, on a layer the hand's pick sees, until it lies
     down; a thing caught in the air has landed nowhere (Blow); and a body the
     hand is handed is told it was picked up, as a grab tells it.
  8. ONE FOLD AT A TIME, ITS LAND READ IN SLICES (Chessboard._fold_some).
  9. A REMEMBERED TOWN'S LAST STEPS ARE A FRAME EACH, its school found on a
     sliced search, and nothing it could not place is searched for again in
     one frame (VillageRaise._as_placed).
 10. THE LAND'S SCARS ARE READ FROM THE ONE BUCKET A POINT IS IN: a scar is
     filed in every bucket it touches, and reading nine summed it nine ways.
 11. A PUPIL WALKS TO ITS SEAT AS EVERYBODY WALKS, on the drawn ground, with
     no physics query (Edubba.attend).
 12. THE CROWD CLOCK HAS A BUDGET A FRAME, however many physics steps the frame
     runs, and a turn carried past it is booked for the next step, first in line.
 13. THE FRAME METER WALKS THE WORLD A SLICE A FRAME and bills itself.
 14. THE LAND KERNEL IS OPTIONAL AND TWINNED: Kernel never names the native
     class, and every question it answers keeps the GDScript that answers it
     without the library (WorldGen, TerrainScars, Chunk, NavField).
 15. A VILLAGER'S UPKEEP — needs, watchdog, hazards, label — runs twice a second
     of their time, not every turn; on fire, every turn.
 16. FIRE MEETS WATER AT ITS SURFACE (Quench): a fireball asks before anything
     else; a conjured orb reads Quench.AT_THE_SURFACE; lava poured into water
     is sent to Quench.lava_into_water rather than refused; and a burning rock
     goes out in the water, not over it.
 17. FRESH LAVA CHURNS: what MiracleManager.lay_lava pours molten is laid over
     with a LavaSkin, and what set in water is set cold.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIVE = ("kill_live.gd", "typing_live.gd", "crowd_clock_live.gd", "seams_live.gd", "brush_live.gd",
        "catch_live.gd", "fold_slices_live.gd", "smooth_live.gd", "kernel_live.gd",
        "quench_live.gd", "names_live.gd")


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return "\n".join(ln.split("#")[0].rstrip() for ln in
                     (rest[:nxt.start()] if nxt else rest).splitlines()
                     if ln.split("#")[0].strip())


def source(fail):
    animal = (ROOT / "scripts/animals/animal.gd").read_text()
    herd = (ROOT / "scripts/animals/herd.gd").read_text()
    clock = (ROOT / "scripts/crowd_clock.gd").read_text()
    world = (ROOT / "scripts/world/world_gen.gd").read_text()
    menu = (ROOT / "scripts/ui/debug_menu.gd").read_text()
    if ".release(self)" not in body(animal, "die"):
        fail.append("a beast's death is not told to its herd: the dead row stands up again")
    code = "\n".join(ln.split("#")[0] for ln in herd.splitlines())
    if re.search(r'\["agent"\]\s*[!=]=\s*null', code) or "held == null" in body(herd, "_tend_the_promoted"):
        fail.append("the herd asks a row's beast `== null`, and a freed beast is null to that")
    if "can_process()" not in body(clock, "_serve"):
        fail.append("the crowd clock walks villagers of a town held still, with no physics space")
    if "village.from_memory = true" not in body(world, "_maybe_found_village"):
        fail.append("a town the world founds where one is remembered is overwritten in one frame")
    height = body(world, "_seeded_height")
    if "_rugged(" not in height or "biome_at(" in height:
        fail.append("the land's ruggedness is read off the biome again: a cliff at every border")
    if "_soft(" not in body(world, "_rugged"):
        fail.append("the ruggedness changes at a line, not across a band")
    if "release_focus()" not in body(menu, "_input"):
        fail.append("the map-name field never lets go of the keyboard")
    bush = (ROOT / "scripts/world/forage_bush.gd").read_text()
    miracles = (ROOT / "scripts/miracles/miracle_manager.gd").read_text()
    tree = (ROOT / "scripts/world/wild_tree.gd").read_text()
    if "add_to_group(Affords.BURNABLE)" not in body(bush, "_ready") \
            or "ForageBush.light_near(" not in body(miracles, "ignite_trees_near") \
            or "queue_free()" in body(tree, "_spread"):
        fail.append("the brush does not burn: no fire reaches a forage bush, or a burning tree deletes it")
    rock = (ROOT / "scripts/world/rock_deposit.gd").read_text()
    blow = (ROOT / "scripts/world/blow.gd").read_text()
    hand = (ROOT / "scripts/player/divine_hand.gd").read_text()
    if "collision_layer = LOOSE_LAYER" not in body(rock, "_physics_process") \
            or "_lie_down()" not in body(rock, "_physics_process"):
        fail.append("a thrown rock flies on no layer, out of the hand's reach, and rolls on for minutes")
    if "thing.freeze" not in body(blow, "_physics_process"):
        fail.append("a thing caught in the air is struck as if it landed where it was caught")
    if '"pick_up"' not in body(hand, "force_hold"):
        fail.append("a body put in the hand is never told it was picked up")
    board = (ROOT / "scripts/world/board/chessboard.gd").read_text()
    if "_begin_fold(" not in body(board, "_fold_the_far") or re.search(r"(?<![\w])fold\(town", body(board, "_fold_the_far")) \
            or "read_some(" not in body(board, "_fold_some"):
        fail.append("towns fold all at once again, their land read in one frame")
    raise_src = (ROOT / "scripts/world/village_raise.gd").read_text()
    found = body(raise_src, "found")
    if '"the rest of it"' in found or "_as_placed(" not in found or "_search_slowly(school)" not in found:
        fail.append("a remembered town's last steps are one frame again, searches and all")
    scars = (ROOT / "scripts/world/terrain_scars.gd").read_text()
    if "[-1, 0, 1]" in body(scars, "offset_at") or "[-1, 0, 1]" in body(scars, "burn_at"):
        fail.append("the land's scars are read from nine buckets and summed: craters dug twice and four times")
    school = (ROOT / "scripts/world/edubba.gd").read_text()
    if "move_and_slide(" in body(school, "attend") or "VillagerFeet.step_by(" not in body(school, "attend"):
        fail.append("a pupil walks to its seat through the physics engine, a shape cast a turn")
    clock = (ROOT / "scripts/crowd_clock.gd").read_text()
    if "FRAME_BUDGET_USEC - _spent_usec" not in body(clock, "_physics_process") \
            or "_clock_due = now + 1" not in body(clock, "_physics_process"):
        fail.append("the crowd clock serves every booking in one step however long it takes, or "
                    "a turn carried over is booked for no frame at all")
    meter = (ROOT / "scripts/ui/frame_meter.gd").read_text()
    if "find_children(" in body(meter, "_readout") or "find_children(" in body(meter, "_survey_some") \
            or 'Ledger.open(&"FrameMeter")' not in body(meter, "_process"):
        fail.append("the frame meter walks the world in one go, or charges its own work to nobody")
    kernel = (ROOT / "scripts/kernel.gd").read_text()
    chunk = (ROOT / "scripts/world/chunk.gd").read_text()
    nav = (ROOT / "scripts/nav_field.gd").read_text()
    if "LandKernel.new" in kernel or 'ClassDB.instantiate(&"LandKernel")' not in body(kernel, "land") \
            or "_kernel.seeded_height_at(" not in body(world, "seeded_height_at") \
            or "_seeded_height(" not in body(world, "seeded_height_at") \
            or "_offset_here(" not in body(scars, "offset_at") or "_drawn_here(" not in body(chunk, "_drawn_local") \
            or "_steer_here(" not in body(nav, "steer"):
        fail.append("the land kernel is required, or one of its questions has lost its GDScript twin")
    villager = (ROOT / "scripts/villager/villager.gd").read_text()
    turn = body(villager, "take_turn")
    if "_upkeep_owed >= UPKEEP_EVERY or burning" not in turn or "_tick_needs(owed_now)" not in turn:
        fail.append("a villager's upkeep runs on every turn again, a third of the turn")
    fire = (ROOT / "scripts/miracles/fireball.gd").read_text()
    orb = (ROOT / "scripts/miracles/miracle_orb.gd").read_text()
    if "Quench.in_water(self)" not in body(fire, "_physics_process") \
            or "Quench.fizzle(" not in body(fire, "_meet_water") or "_go_off()" not in body(fire, "_meet_water") \
            or "Quench.AT_THE_SURFACE" not in body(orb, "_physics_process") \
            or "Quench.lava_into_water(" not in body(miracles, "_pour_lava") \
            or "water_level_at(" not in body(rock, "_drowned"):
        fail.append("fire goes through the water as if it were not there: a gout sinks to the bed, "
                    "a blast goes off under it, lava is refused")
    lay = body(miracles, "lay_lava")
    if "LavaSkin.pour(" not in lay or "TerrainScars.EMBER_SECONDS" not in lay:
        fail.append("fresh lava lies flat and still, or lava set in water keeps its ember")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    for test in LIVE:
        ran = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script",
                              "tools/live/" + test], capture_output=True, text=True, timeout=600)
        checks = [ln for ln in ran.stdout.splitlines() if ln.rstrip().endswith(("yes", "NO"))]
        print("  %s in Godot: %d checks, %s" % (test, len(checks),
                                                "all pass" if ran.returncode == 0 else "FAILING"))
        if ran.returncode != 0:
            fail.append("%s in Godot:\n" % test + "\n".join(
                ln for ln in checks if ln.rstrip().endswith("NO")))


def main():
    fail = []
    print("THE LIVE CHECKS")
    source(fail)
    live(fail)
    print()
    if fail:
        for f in fail:
            print("FAIL: %s" % f)
        return 1
    print("Success: no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
