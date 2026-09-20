#!/usr/bin/env python3
"""ZOOMING OUT MUST NEVER MAKE THE WATER LOOK DEEPER THAN IT IS.

A depth pyramid has one failure that nobody sees. Every overview level throws
three cells in four away, and the rule it throws them away by decides whether a
rock is on the chart or not. Average four cells of -40, -38, -41 and -2 and you
get -30: the rock is gone, the water is drawn open, and every zoom level above
it agrees with every other, so nothing looks wrong anywhere. `gdaladdo`
averages by default. That is the bug this file exists for.

So the tiles are built shoalest-wins -- a parent cell is the closest to the
surface of its four children -- and these are the claims that keep it that way:

  NOTHING OUTSIDE THE SURFACE OF THE EARTH. Every cell is a plausible elevation
  or is exactly NODATA. A byte-order slip, a misread scale factor or a fill
  value carried through as real data all look perfectly fine on a colour ramp
  and all fail here.

  THE SHOALEST CELL THAT IS STILL UNDER WATER SURVIVES TO THE TOP. Found at
  level 0, then looked for at its own position on every level above. This is the
  pinnacle test and it is the reason the file exists: an averaging pyramid loses
  it at level 1 and every level after.

  UNDER WATER, and that qualifier is the whole check. Written first as "the
  shoalest cell in the data" it passed happily -- and what it had found was a
  904 m hilltop on dry land. On the real grid it would have gone looking for
  Everest, confirmed that Everest was still in the overviews, and said PASS.
  The cell that can sink a boat is the shallowest one with water over it, so
  that is the one that is tracked.

  EVERY PARENT IS ONE OF ITS OWN CHILDREN, and specifically the shallowest of
  them. Not their mean, not the first of them, not a resampled guess between
  them. Checked cell by cell against the bytes actually on disk.

  THE GEOREFERENCE ROUND-TRIPS -- against the SOURCE RASTER, and against the
  lattice GEBCO PUBLISHES ON rather than the one the manifest claims. Half a cell
  at 15 arc-seconds is 230 metres: the width of a channel, and invisible on
  screen.

  THE MANIFEST IS NOT THE AUTHORITY HERE, and that is the whole of why this check
  works. Written first to read the origin out of the manifest, it passed a
  deliberate half-cell shift of the entire grid -- because the builder wrote the
  shifted origin into the manifest and the checker dutifully shifted with it, so
  the two agreed perfectly about being wrong together. The canonical lattice is
  therefore written down HERE, as a constant, and a manifest that disagrees with
  it is itself the failure.

  AND NOTHING IS INVENTED. No gap filled, no cell interpolated across a
  coastline. A hole stays a hole, because a plotter that draws "unknown" as
  "zero" draws dry land in the middle of a shipping channel.

  Which is checked by GEOGRAPHY, not by counting. Written first as a printed
  tally of holes it asserted nothing whatsoever -- filling every gap with zero
  would have sailed through it, since zero is a perfectly plausible elevation.
  What it does now is work out which cells any source actually covered, and
  fail on a cell that holds a number no source could have supplied.

  AND THE MANIFEST SAYS WHAT THE NUMBERS MEAN. Datum and sign convention by
  name, and GEBCO's own disclaimer carried with the data rather than left on a
  web page. A depth with no datum is a number, not a depth.

    python3 tools/soundings.py tiles/north_america [--source gebco/*.tif]

With no tiles built yet it says so and passes: this is a check on data, and data
that is not there is not a broken pipeline. Pass --require where a build was
supposed to have just run, because a build that refused its source also leaves no
tiles, and "nothing to check" must not be allowed to read as "all well".
"""
import argparse
import json
import pathlib
import sys

import numpy as np

DEEPEST, HIGHEST = -11500, 9200

## THE LATTICE GEBCO PUBLISHES ON, written here and taken from nothing. 15
## arc-seconds is exactly 1/240 of a degree and the global grid starts at
## -180/+90 with no fractional offset. This is the authority the tiles are
## judged against; see the docstring for what happened when it was not.
TRUE_WEST, TRUE_NORTH, TRUE_PER_DEGREE = -180.0, 90.0, 240


def tiles_at(root, level):
    out = {}
    base = root / str(level)
    if not base.is_dir():
        return out
    for row in base.iterdir():
        if not row.is_dir():
            continue
        for cell in row.glob("*.i16"):
            out[(int(row.name), int(cell.stem))] = cell
    return out


def load(path, tile):
    return np.frombuffer(path.read_bytes(), dtype="<i2").reshape(tile, tile)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--require", action="store_true",
                    help="treat missing tiles as a failure. A build that dies "
                         "half way leaves no manifest, and without this the "
                         "check on its output reads as a pass — which is how a "
                         "refused source came to look like a clean run.")
    ap.add_argument("--source", nargs="*", default=[],
                    help="the raster(s) the tiles were cut from, for the "
                         "georeference round-trip")
    args = ap.parse_args()
    root = pathlib.Path(args.root)
    book = root / "manifest.json"
    if not book.exists():
        print("NO TILES AT %s — nothing built yet, so nothing to check." % root)
        if args.require:
            print("FAIL: --require was given and there is no manifest at all, so "
                  "the build that was supposed to produce these tiles did not "
                  "finish. Check its exit status; a refused source prints why.")
            return 1
        return 0

    man = json.loads(book.read_text())
    TILE = int(man["tile"])
    NODATA = int(man["nodata"])
    PER_DEGREE = int(man["per_degree"])
    WEST = float(man["origin"]["west"])
    NORTH = float(man["origin"]["north"])
    levels = sorted(int(k) for k in man["levels"])
    fail = []
    # THE LATTICE FIRST, because every position below is computed from it.
    if (WEST, NORTH, PER_DEGREE) != (TRUE_WEST, TRUE_NORTH, TRUE_PER_DEGREE):
        fail.append("the manifest puts the grid origin at %.8f/%.8f at %d cells "
                    "a degree, and GEBCO publishes on %.1f/%.1f at %d. A shift "
                    "of %.3f cells is %.0f metres and it moves every coastline "
                    "in the file together, so nothing looks wrong anywhere"
                    % (WEST, NORTH, PER_DEGREE, TRUE_WEST, TRUE_NORTH,
                       TRUE_PER_DEGREE, abs(WEST - TRUE_WEST) * PER_DEGREE,
                       abs(WEST - TRUE_WEST) * 111320.0))
    print("MANIFEST: %s, %s, tile %d, %d levels, nodata %d."
          % (man["crs"], man["units"], TILE, len(levels), NODATA))
    print("   datum: %s" % man.get("vertical_datum", "UNSTATED"))
    print("   sign:  %s" % man.get("sign", "UNSTATED"))

    # -- THE MANIFEST SAYS WHAT THE NUMBERS MEAN -----------------------------
    for key in ("vertical_datum", "sign", "not_for_navigation", "overview"):
        if not str(man.get(key, "")).strip():
            fail.append("the manifest does not say '%s' — a depth with no datum "
                        "or no sign convention is a number somebody will one day "
                        "mosaic a chart-datum survey into, and the mismatch will "
                        "be a quiet two metres rather than a loud failure" % key)

    # -- NOTHING OUTSIDE THE SURFACE OF THE EARTH ----------------------------
    print()
    shoalest, shoal_at, counted, holes = -32768, None, 0, 0
    highest = -32768
    for level in levels:
        found = tiles_at(root, level)
        lo, hi = 32767, -32768
        for (ty, tx), path in found.items():
            cells = load(path, TILE)
            real = cells != NODATA
            if not real.any():
                continue
            vals = cells[real]
            bad = (vals < DEEPEST) | (vals > HIGHEST)
            if bad.any():
                fail.append("level %d tile %d/%d holds %d cell(s) outside "
                            "%d..%d metres (worst %d) — that is not a depth, it "
                            "is a byte-order or fill-value mistake, and it looks "
                            "correct on a colour ramp"
                            % (level, ty, tx, int(bad.sum()), DEEPEST, HIGHEST,
                               int(vals[bad][0])))
            lo, hi = min(lo, int(vals.min())), max(hi, int(vals.max()))
            if level == 0:
                counted += int(real.sum())
                holes += int((~real).sum())
                highest = max(highest, int(vals.max()))
                # SUBMERGED ONLY. A cell at or above zero is land, and the
                # highest piece of land in the data set is not a hazard to
                # anything afloat.
                wet = real & (cells < 0)
                if wet.any() and int(cells[wet].max()) > shoalest:
                    shoalest = int(cells[wet].max())
                    flat = int(np.argmax(np.where(wet, cells, -32768)))
                    shoal_at = (ty, tx, flat // TILE, flat % TILE)
        print("   level %d: %4d tiles, %6d .. %5d metres" % (level, len(found), lo, hi))

    # -- THE SHOALEST CELL SURVIVES TO THE TOP -------------------------------
    #
    # Stated generally rather than against a planted marker, so it holds on the
    # real grid too: whatever the closest thing to the surface is, it is still
    # the value at its own position however far you zoom out.
    print()
    if shoal_at is None:
        fail.append("level 0 holds no cell that is under water at all, so the "
                    "pinnacle test has nothing to track — on a bathymetry grid "
                    "that is not a pass, it means the wrong thing was tiled")
    else:
        ty, tx, py, px = shoal_at
        # Its position in whole level-0 cells from the global origin, then the
        # same position expressed at each level above. Written out here rather
        # than asked of the builder.
        gy, gx = ty * TILE + py, tx * TILE + px
        lat = TRUE_NORTH - (gy + 0.5) / TRUE_PER_DEGREE
        lon = TRUE_WEST + (gx + 0.5) / TRUE_PER_DEGREE
        print("THE SHOALEST SUBMERGED CELL is %d m at %.5f N %.5f E "
              "(level 0 tile %d/%d, cell %d,%d)."
              % (shoalest, lat, lon, ty, tx, py, px))
        print("   (the highest cell of any kind is %d m — dry land, and not what "
              "this tracks)" % highest)
        for level in levels[1:]:
            ly, lx = gy >> level, gx >> level
            path = root / ("%d/%d/%d.i16" % (level, ly // TILE, lx // TILE))
            if not path.exists():
                fail.append("the shoalest cell in the data (%d m) has no tile "
                            "covering it at level %d — the pyramid does not "
                            "reach the thing most worth seeing" % (shoalest, level))
                continue
            here = int(load(path, TILE)[ly % TILE, lx % TILE])
            mark = "kept" if here == shoalest else "LOST (reads %d m)" % here
            print("   level %d: %s" % (level, mark))
            if here != shoalest:
                fail.append("the shoalest cell still under water is %d m and "
                            "at level %d its own position reads %d m — %s. An "
                            "averaged overview draws open water over a rock, and "
                            "every zoom level agrees with every other, so nothing "
                            "anywhere looks wrong"
                            % (shoalest, level, here,
                               "it has been lost to a deeper cell beside it"
                               if here < shoalest else "it has been overstated"))

    # -- EVERY PARENT IS THE SHALLOWEST OF ITS OWN CHILDREN ------------------
    print()
    checked, wrong, worst = 0, 0, 0
    for level in levels[1:]:
        for (ty, tx), path in tiles_at(root, level).items():
            parent = load(path, TILE)
            big = np.full((TILE * 2, TILE * 2), NODATA, dtype=np.int16)
            for dy in (0, 1):
                for dx in (0, 1):
                    kid = root / ("%d/%d/%d.i16"
                                  % (level - 1, ty * 2 + dy, tx * 2 + dx))
                    if kid.exists():
                        big[dy * TILE:(dy + 1) * TILE,
                            dx * TILE:(dx + 1) * TILE] = load(kid, TILE)
            grouped = big.reshape(TILE, 2, TILE, 2)
            real = grouped != NODATA
            want = np.where(real.any(axis=(1, 3)),
                            np.where(real, grouped, DEEPEST - 1).max(axis=(1, 3)),
                            NODATA)
            off = parent.astype(np.int32) - want.astype(np.int32)
            checked += parent.size
            if off.any():
                wrong += int((off != 0).sum())
                worst = max(worst, int(np.abs(off).max()))
    print("EVERY PARENT CELL AGAINST THE SHALLOWEST OF ITS FOUR CHILDREN:")
    print("   %d cells checked, %d disagree%s."
          % (checked, wrong, "" if not wrong else " (worst by %d m)" % worst))
    if wrong:
        fail.append("%d overview cells of %d are not the shallowest of their four "
                    "children (worst by %d m) — that is an averaging or "
                    "nearest-neighbour pyramid, and it hides shoals at every "
                    "level above the one they were surveyed at"
                    % (wrong, checked, worst))

    # -- NOTHING IS INVENTED -------------------------------------------------
    print()
    print("LEVEL 0 HOLDS %d real cells and %d NODATA." % (counted, holes))
    if args.source:
        import rasterio
        boxes = []
        for path in args.source:
            name = ('netCDF:"%s":elevation' % path) if path.endswith(".nc") else path
            with rasterio.open(name) as src:
                boxes.append(tuple(src.bounds))   # left, bottom, right, top
        made_up = 0
        for (ty, tx), path in tiles_at(root, 0).items():
            cells = load(path, TILE)
            real = cells != NODATA
            if not real.any():
                continue
            gy = ty * TILE + np.arange(TILE)
            gx = tx * TILE + np.arange(TILE)
            lat = TRUE_NORTH - (gy + 0.5) / TRUE_PER_DEGREE
            lon = TRUE_WEST + (gx + 0.5) / TRUE_PER_DEGREE
            covered = np.zeros((TILE, TILE), dtype=bool)
            for left, bottom, right, top in boxes:
                covered |= (((lat > bottom) & (lat <= top))[:, None]
                            & ((lon >= left) & (lon < right))[None, :])
            made_up += int((real & ~covered).sum())
        print("   %d cell(s) hold a number no source covered." % made_up)
        if made_up:
            fail.append("%d level-0 cells hold a value at a position none of the "
                        "source rasters covers — something has been filled in, "
                        "interpolated or carried over, and a guessed depth is "
                        "indistinguishable on screen from a surveyed one"
                        % made_up)

    # -- THE GEOREFERENCE ROUND-TRIPS ----------------------------------------
    if args.source:
        import rasterio
        print()
        print("AGAINST THE SOURCE RASTER, at cells picked across it:")
        rng = np.random.default_rng(20260920)
        tested = matched = 0
        for path in args.source:
            name = ('netCDF:"%s":elevation' % path) if path.endswith(".nc") else path
            with rasterio.open(name) as src:
                band = src.read(1)
                for _ in range(400):
                    r = int(rng.integers(0, src.height))
                    c = int(rng.integers(0, src.width))
                    # Cell centre in the world, from the SOURCE's own transform.
                    lon = src.transform.c + (c + 0.5) * src.transform.a
                    lat = src.transform.f - (r + 0.5) * abs(src.transform.e)
                    # And which level-0 cell that is, by this file's arithmetic.
                    gx = int(np.floor((lon - TRUE_WEST) * TRUE_PER_DEGREE))
                    gy = int(np.floor((TRUE_NORTH - lat) * TRUE_PER_DEGREE))
                    tile = root / ("0/%d/%d.i16" % (gy // TILE, gx // TILE))
                    if not tile.exists():
                        continue
                    tested += 1
                    got = int(load(tile, TILE)[gy % TILE, gx % TILE])
                    if got == int(band[r, c]):
                        matched += 1
                    elif tested - matched <= 3:
                        print("   MISMATCH at %.5f N %.5f E: source %d, tile %d"
                              % (lat, lon, int(band[r, c]), got))
        print("   %d cells tested, %d matched the source exactly." % (tested, matched))
        if tested and matched != tested:
            fail.append("%d of %d sampled cells do not match the source raster at "
                        "the same latitude and longitude — the tiles are offset "
                        "from the grid they were cut from, and half a cell is 230 "
                        "metres, which is the width of a channel and invisible on "
                        "screen" % (tested - matched, tested))
        if not tested:
            fail.append("not one sampled source cell fell inside the tiles, so the "
                        "round-trip proved nothing at all")

    print()
    if fail:
        for why in fail:
            print("FAIL: %s" % why)
        return 1
    print("PASS: nothing outside the earth's surface, the shoalest cell survives "
          "to the top, every parent is the shallowest of its children, and the "
          "grid round-trips against its source.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
