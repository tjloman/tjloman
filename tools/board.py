#!/usr/bin/env python3
"""THE CHESSBOARD: towns out of sight, as numbers, held to the three rules.

    "they don't do the 3 things most common in rushed designs: go extinct,
     balloon in growth, or endlessly crash."

What holds it there, in the source:

  1. THE FLOOR: the board never takes a town below TownRules.VESTIGE, and the
     vestige stays grown people; only the hand ends a town.
  2. ROOM: births need beds (plus the few a town crowds in, more for a ruin),
     never past MOST_SOULS, AND what the land feeds year in, year out
     (TownRules.land_feeds) -- the foresight that stops a town growing on a full
     larder and starving on the one it has left.
  3. THE LARDERS ARE KEPT: wild food is never taken below KEEP_STOCK.
  4. THE GRANARY: two years put by, the work falling away sharply past it, and
     nothing kept past five (RESERVE_CAP_YEARS).
  5. THE BEASTS CAN BE KEPT IN CHECK: a town's guard culls them.
  6. ONE SOURCE FOR THE LAND: a chunk scatters bushes and beasts from the very
     tables TownLand reckons a town's land from (Chunk.BUSHES, BEASTS, STAND).
  7. A TOWN OUT OF SIGHT IS FOLDED INTO ITS RECORD and remembered with every
     other (SaveGame.village_memory); taken back, it is first CAUGHT UP
     (SaveGame.recall -> Chessboard.bring_up_to_date), its people reconciled
     BY NAME, the dead chosen from those past their span, and everyone set to
     the state the town is in -- nobody comes back starving to a full granary.
  8. A PERSON'S SPAN IS SAVED and a restored one always has years left.
  9. THE TOTEM CAN BE HELD: a hoverable body in the totem group, which the hand
     reads like the nest wall, opening TownReading in the stone panel.
 10. A DEAD TREE STAYS DEAD: a tree of a chunk's stand that is felled, burned
     or uprooted is written down (WorldGen._felled) and saved, and the seed
     never stands it again (Chunk._after_felling). A wood comes back only from
     what is planted -- a grown tree's seed, the god's grove -- and a planted
     tree is remembered while it lives (WorldGen._sown) and forgotten when it
     dies. A town out of sight fells any tree in reach and its woods never grow
     back; what it cut is written back to the woods when it returns.
 11. A BARN'S STOCK GOES WITH ITS TOWN: written into the record by kind, fed
     out of sight from the granary at the live barn's trough (Drove.trough) and
     dying off unfed, and put back into the barn when the town is raised again.
 12. THE ROAD BETWEEN TOWNS: the board keeps time -- every folded town is
     stepped as its steps fall due, not frozen until seen. Those it sends away
     leave by name (TownFold._set_out), not told as dead; they wait for company
     and walk as a band to the town they know of with room and food, at a
     family's pace. Towns trade what they have spare for what they lack, the
     traders walking there and back. Ruins neither send nor receive. In loaded
     land a band is villagers walking (Migrant), off every town's roll.
 13. And with GODOT set, tools/live/century_live.gd runs the rules over 320
     towns for 180 game years and judges every one, fold_live.gd folds a
     believing town, lets twenty years pass, and brings it back, and
     woods_live.gd fells, plants, saves and sheds a wood, and barn_live.gd
     stocks a barn, writes it down and fills its trough.
"""
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RULES = (ROOT / "scripts/world/board/town_rules.gd").read_text()
LAND = (ROOT / "scripts/world/board/town_land.gd").read_text()
CHUNK = (ROOT / "scripts/world/chunk.gd").read_text()
BOARD = (ROOT / "scripts/world/board/chessboard.gd").read_text()
FOLD = (ROOT / "scripts/world/board/town_fold.gd").read_text()
SAVE = (ROOT / "scripts/save_game.gd").read_text()
VILLAGE = (ROOT / "scripts/world/village.gd").read_text()
HAND = (ROOT / "scripts/player/divine_hand.gd").read_text()
HUD = (ROOT / "scripts/ui/hud.gd").read_text()
TREE = (ROOT / "scripts/world/wild_tree.gd").read_text()


def body(text, name):
    m = re.search(r"^(static )?func %s\(" % re.escape(name), text, re.M)
    if not m:
        sys.exit("no func %s" % name)
    rest = text[m.end():]
    nxt = re.search(r"^(static )?func ", rest, re.M)
    return "\n".join(ln.split("#")[0].rstrip() for ln in
                     (rest[:nxt.start()] if nxt else rest).splitlines()
                     if ln.split("#")[0].strip())


def const(name):
    m = re.search(r"^const %s := ([0-9.]+)" % name, RULES, re.M)
    return float(m.group(1)) if m else None


def source(fail):
    lives = body(RULES, "_lives")
    if "pop - died < floor_at" not in lives or "minf(VESTIGE, pop)" not in lives:
        fail.append("the board can take a town below the vestige")
    if "grow_old = 0.0" not in lives:
        fail.append("a vestige ages into elders who can have no children")
    if "land_feeds(book, land)" not in lives or "book.beds()" not in lives:
        fail.append("births do not listen to the beds and to what the land feeds")
    if "KEEP_STOCK" not in body(RULES, "_spare"):
        fail.append("the wild larders can be stripped")
    reserve, cap = const("RESERVE_YEARS"), const("RESERVE_CAP_YEARS")
    print("  granary: %s years put by, nothing kept past %s" % (reserve, cap))
    if reserve != 2.0 or cap != 5.0:
        fail.append("the granary is not two years kept and five at most")
    if "RESERVE_CAP_YEARS" not in body(RULES, "step") or "food_wanted(" not in body(RULES, "step"):
        fail.append("the granary has no ceiling, or the work does not ease off as it fills")
    if "cull" not in body(RULES, "step") or "_guard(book)" not in body(RULES, "step"):
        fail.append("the beasts cannot be kept in check")
    scatter = "\n".join(ln.split("#")[0] for ln in CHUNK.splitlines())
    if re.search(r"_scatter_animals\(rng, \{", scatter) or "BEASTS[biome]" not in scatter \
            or "_bushes(rng, biome)" not in scatter:
        fail.append("a chunk scatters from literals again, not the tables a town reads its land from")
    for table in ("Chunk.STAND", "Chunk.BUSHES", "Chunk.BEASTS", "herds_remembered"):
        if table not in LAND:
            fail.append("TownLand does not read %s" % table)
    LIVE_TEST = ("slope_at", "<= 0.9", "footprint_dry(", "2.2", "line_dry(")
    land_test = body(LAND, "_buildable") + "\n" + "\n".join(
        ln for ln in LAND.splitlines() if ln.startswith(("const BUILD_SLOPE", "const FOOTPRINT")))
    live_test = body(VILLAGE, "_ground_for_building")
    for part in ("slope_at", "footprint_dry(", "line_dry("):
        if part not in land_test or part not in live_test:
            fail.append("the room a town's numbers read is not asked the live builder's way (%s)" % part)
    if "<= 0.9" not in live_test or "2.2" not in live_test or "BUILD_SLOPE := 0.9" not in land_test \
            or "FOOTPRINT := 2.2" not in land_test:
        fail.append("the room a town's numbers read uses a different slope or footprint from the live builder")
    if "land.near(build_reach(pop))" not in body(RULES, "step") \
            or "free >= house_room(size)" not in body(RULES, "_build"):
        fail.append("a town's numbers build past the room their reach gives them")
    fold = body(BOARD, "fold")
    if "town.to_dict()" not in fold or "SaveGame.village_memory.append(record)" not in fold:
        fail.append("a folded town is not remembered as its own record")
    if "Chessboard.bring_up_to_date(" not in body(SAVE, "recall"):
        fail.append("a town is taken back without its years away")
    rec = body(FOLD, "_reconcile")
    if "_due(" not in rec or "_condition(one, book, rng)" not in rec:
        fail.append("the alibi does not take the dead from those past their span, or does not "
                    "set the living to the state of their town")
    if '"lifespan": v.lifespan' not in body(VILLAGE, "to_dict") \
            or 'entry.get("lifespan"' not in body(VILLAGE, "_restore_villager"):
        fail.append("a person's span is not saved, or a restored one can die on the first morning")
    totem = body(VILLAGE, "_build_totem")
    if "add_to_group(TOTEMS)" not in totem or "collision_layer = 4" not in totem:
        fail.append("the totem is not something the hand can hold")
    if "return _after_felling(out)" not in body(CHUNK, "_tree_stand"):
        fail.append("a chunk's seed stands its trees again however many were felled")
    for fn in ("fell", "pick_up", "_burn"):
        if "_gone_from_spot()" not in body(TREE, fn):
            fail.append("a tree gone by %s is not remembered as down" % fn)
    if '"woods": world.woods_to_save()' not in body(SAVE, "snapshot") \
            or 'world.woods_from_save(pending_world.get("woods", {}))' not in body(SAVE, "apply_pending"):
        fail.append("a save forgets which trees are down")
    if "_after_felling" not in body(CHUNK, "_tree_stand") or "REGROW" in CHUNK \
            or '"at"' in body(TREE, "_gone_from_spot"):
        fail.append("a felled tree of the stand grows back from the seed: a dead tree stays dead")
    if "wood_stock = _regrow" in RULES or "book.wood_stock = clampf(book.wood_stock +" in RULES:
        fail.append("out of sight, a felled wood grows back")
    if "forget_sown(" not in body(TREE, "_gone_from_spot") or "world.sow(" not in body(TREE, "_try_replant") \
            or "world.sow(" not in body((ROOT / "scripts/miracles/miracle_manager.gd").read_text(), "_cast_forest_seed") \
            or '"sown":' not in body((ROOT / "scripts/world/world_gen.gd").read_text(), "woods_to_save"):
        fail.append("a planted tree is not remembered while it lives, or not forgotten when it dies")
    if "TownLand.write_back_woods(" not in body(BOARD, "bring_up_to_date"):
        fail.append("a town's felling out of sight is not written back to the woods")
    # FISHING IS A LIVELIHOOD: a cast brings home a string, the board's rate is
    # the one measured in a cove town, and the fishers grow with the town.
    road = (ROOT / "scripts/world/board/migration.gd").read_text()
    villager_src = (ROOT / "scripts/villager/villager.gd").read_text()
    if "_step_the_folded(world)" not in body(BOARD, "_process") \
            or "TownFold.catch_up(" not in body(BOARD, "_step_the_folded"):
        fail.append("a folded town is frozen until it is seen again: nothing out of sight moves")
    if "_set_out(record, folk," not in body(FOLD, "_reconcile") or "going" not in body(FOLD, "catch_up") \
            or "book.leaving_young += kids" not in body(RULES, "_leave"):
        fail.append("those a town sends away vanish, or are told as dead, rather than leaving by name")
    if 'town["ruined"]' not in body(road, "go_round") or 'town["ruined"]' not in body(road, "choose") \
            or "KNOWS_OF" not in body(road, "choose"):
        fail.append("a ruin sends or receives people, or a band goes where nobody has heard of")
    if "PACE * seconds" not in body(road, "advance") or "Migration.advance(band, delta)" not in body(BOARD, "_walk_the_road"):
        fail.append("a band arrives without walking the road")
    if "_swap(band, here)" not in body(road, "arrive") or "_trade_from(town, towns, now)" not in body(road, "go_round"):
        fail.append("towns do not trade, or the traders do not go there and back")
    if "journey.is_empty()" not in body(VILLAGE, "_refresh_roster") or "Migrant.walk(self, delta)" not in villager_src:
        fail.append("a villager on the road is still on a town's roll, or does not walk with the band")
    if '"bands": Migration.to_save()' not in body(SAVE, "snapshot"):
        fail.append("a save forgets the bands on the road")
    if "##     static func _raid(" not in road:
        fail.append("the raid is meant to be there, commented, for when there is another god")
    jobs = (ROOT / "scripts/world/village_jobs.gd").read_text()
    villager = (ROOT / "scripts/villager/villager.gd").read_text()
    catch = re.search(r"^const SHORE_CATCH := (\d+)", jobs, re.M)
    per_hand = const("FISH_PER_HAND")
    print("  fishing: %s fish a cast, %s meals a hand-year out of sight"
          % (catch.group(1) if catch else "?", per_hand))
    if not catch or int(catch.group(1)) < 5 or '_begin_haul("meat", VillageJobs.SHORE_CATCH, "fish")' not in villager:
        fail.append("a fisher brings home a fish a cast again: nobody can live by the water")
    if per_hand is None or per_hand < 15.0:
        fail.append("out of sight, a fisher brings in a fraction of what the live one does")
    if "SOULS_PER_FISHER" not in body(jobs, "room_for"):
        fail.append("three fishers, however big the harbour town grows")
    step = body(RULES, "step")
    if "_keep_stock(book, herd_eats, dt)" not in step or "Drove.trough(" not in step \
            or "need + herd_eats" not in step:
        fail.append("a folded town's stock eats nothing, or its town grows no food for it")
    if '"kept": _kept_stock()' not in body(VILLAGE, "to_dict") \
            or ".stock_up(kind" not in body(VILLAGE, "_rebuild") \
            or 'record.get("kept"' not in body(FOLD, "book_of") \
            or 'record["kept"] = kept' not in body(FOLD, "catch_up"):
        fail.append("a barn's stock is lost when its town is folded, saved or raised again")
    if "Village.TOTEMS" not in body(HAND, "_readable") or "TownReading.of(" not in body(HUD, "_on_stone_read"):
        fail.append("holding a totem does not read the town")


def live(fail):
    godot = os.environ.get("GODOT", "")
    if not godot or not pathlib.Path(godot).exists():
        print("  GODOT not set: not run in an engine here")
        return
    for test in ("century_live.gd", "fold_live.gd", "woods_live.gd", "barn_live.gd", "road_live.gd"):
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
    print("THE CHESSBOARD")
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
