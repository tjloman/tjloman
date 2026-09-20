#!/usr/bin/env python3
"""EVERY NAVIGABLE METRE OF NORTH AMERICA, CUT INTO SOMETHING A TABLET CAN STREAM.

GEBCO_2026 hands you the world's seafloor as a 15-arc-second grid of 2-byte
signed integers: metres, positive up, land and sea in one seamless surface. That
is already the right numbers in the right units. What it is not is something a
plotter can draw -- you cannot hold 86400x43200 cells on a tablet and you cannot
seek into a netCDF per frame.

So this cuts it into a pyramid of fixed-size Int16 tiles, and the whole file is
built around four decisions that are easy to get wrong and invisible afterwards.

  NO REPROJECTION. The tiles stay in EPSG:4326, the grid's own CRS, on the
  grid's own lattice. Every reprojection resamples, and resampling a depth grid
  invents depths between the ones that were measured. The plotter converts
  lat/lon to screen; that is a per-frame job and it is cheap. Warping the data
  once to make the drawing easier would bake an error into the file forever.

  INT16 METRES, WHICH IS WHAT GEBCO ALREADY IS. No float conversion, no scale
  factor, no unit change. A tile is a byte-for-byte carry of the source cells,
  so there is no lossy step anywhere between the hydrographic office and the
  screen, and a tile can be memory-mapped and read as-is.

  THE OVERVIEWS TAKE THE SHALLOWEST, NEVER THE AVERAGE. This is the one that
  matters and it is the one every default gets wrong. `gdaladdo` averages by
  default; averaging four cells of -40, -38, -41 and -2 gives you -30 and hides
  the rock. Zoomed out, an averaged pyramid draws open water over a pinnacle
  that is two metres under your keel. So a parent cell is the MAXIMUM of its
  four children -- the closest to the surface, the shoalest -- and zooming out
  can therefore only ever make the water look shallower than it is, never
  deeper. That is the direction an error is allowed to point.

  AND EVERY LEVEL IS BUILT FROM THE ONE BELOW IT. Not re-read from source. That
  makes the pyramid self-consistent by construction rather than by luck, and it
  means the shoalest cell at level 0 propagates all the way to the top instead
  of being re-averaged out of existence at each step.

WHAT IT REFUSES TO DO. It does not fill a gap, interpolate across a coastline,
or guess at a cell no source covered. A hole stays a hole and is written as
NODATA, because a plotter that draws "unknown" as "zero" draws dry land in the
middle of a shipping channel. See tools/soundings.py, which fails if a value
outside the plausible range of the earth's surface ever reaches a tile.

VERTICAL DATUM, AND WHY THESE ARE NOT CHART DEPTHS. GEBCO is elevation relative
to mean sea level, positive up. A nautical chart sounding is depth below CHART
DATUM -- roughly MLLW in the US -- positive down, and deliberately pessimistic,
because the whole point of chart datum is that the water is almost always
deeper than the chart says. The two differ by one to three metres in tidal
water. They are not interchangeable and nothing here pretends they are: the
manifest records the datum and the sign convention by name, so that the day a
real survey layer is mosaicked in, the mismatch is a loud failure instead of a
quiet couple of metres.

    python3 bathy/build.py --source gebco/*.tif --out tiles/north_america \
        --bounds 5 -170 85 -50
"""
import argparse
import json
import pathlib
import sys
import time

import numpy as np
import rasterio
from rasterio.windows import Window

# THE LATTICE. GEBCO_2026 is 15 arc-seconds, which is exactly 1/240 of a degree,
# and the global grid runs from -180/+90 with no fractional offset. Tiles are cut
# on that same lattice from that same origin at every level, so a cell boundary
# here is a cell boundary in the source -- and so a higher-resolution survey
# added later lands on these cell edges instead of half a cell off them.
PER_DEGREE = 240
CELL0 = 1.0 / PER_DEGREE
WEST, NORTH = -180.0, 90.0

## Int16's floor, which is not a depth anywhere on earth and so can stand for
## "nothing covered this". GEBCO itself has no gaps -- it is a complete surface --
## so a NODATA cell in the output always means "outside what was asked for", never
## "the ocean is unknown here".
NODATA = -32768

## THE DEEPEST AND HIGHEST THE SURFACE OF THIS PLANET GETS, with room either side.
## Challenger Deep is about -10935 and Everest about +8849. A cell outside this is
## not a bathymetric value, it is a byte-order mistake, a misread scale factor or a
## fill value being carried through as real data -- all three of which have shipped
## in grids before and none of which look wrong on a colour ramp.
DEEPEST, HIGHEST = -11500, 9200

TILE = 512


def cell_at(level):
    """Degrees per cell at a pyramid level. Level 0 is the source resolution."""
    return CELL0 * (2 ** level)


def open_sources(paths):
    """Open every source and REFUSE anything that is not on the grid this
    expects. A source at a different resolution, or in a different CRS, or
    half a cell off the lattice, would tile without complaint and be wrong by
    a couple of hundred metres everywhere -- which on a chart is the width of
    the channel you were trying to stay inside."""
    out = []
    for path in paths:
        name = str(path)
        # netCDF needs the variable naming its subdataset; GeoTIFF opens as-is.
        if name.endswith(".nc"):
            name = 'netCDF:"%s":elevation' % path
        src = rasterio.open(name)
        crs_ok = src.crs is not None and src.crs.to_epsg() == 4326
        res_ok = abs(src.transform.a - CELL0) < 1e-12 \
            and abs(abs(src.transform.e) - CELL0) < 1e-12
        # On the lattice: the source's own west edge must be a whole number of
        # cells from the global origin.
        off = (src.transform.c - WEST) * PER_DEGREE
        lat_off = (NORTH - src.transform.f) * PER_DEGREE
        grid_ok = abs(off - round(off)) < 1e-6 and abs(lat_off - round(lat_off)) < 1e-6
        if not crs_ok:
            sys.exit("REFUSED %s: CRS is %s, not EPSG:4326. Reprojecting a depth "
                     "grid invents depths; convert it deliberately, not here."
                     % (path, src.crs))
        if not res_ok:
            sys.exit("REFUSED %s: cell is %.9f x %.9f degrees, not 1/240. This "
                     "builder carries cells across byte for byte and cannot do "
                     "that from a different grid." % (path, src.transform.a,
                                                      abs(src.transform.e)))
        if not grid_ok:
            sys.exit("REFUSED %s: its west/north edge is %.4f/%.4f cells off the "
                     "global lattice. Half a cell is 230 metres and looks like "
                     "nothing on screen." % (path, off - round(off),
                                             lat_off - round(lat_off)))
        out.append(src)
    return out


def sample(sources, level, west, north, width, height):
    """The cells for one output tile, gathered from whatever sources cover it.

    Read boundless so a tile straddling the edge of a source comes back padded
    with NODATA rather than short -- a short read silently shifts every cell
    after it, which is the kind of failure that shows up as a coastline offset
    a thousand miles away from the file that caused it."""
    cell = cell_at(level)
    got = np.full((height, width), NODATA, dtype=np.int16)
    for src in sources:
        # Where this tile's top-left sits in THIS source's pixel space.
        col = (west - src.transform.c) / src.transform.a
        row = (src.transform.f - north) / abs(src.transform.e)
        step = int(round(cell / src.transform.a))
        win = Window(col_off=int(round(col)), row_off=int(round(row)),
                     width=width * step, height=height * step)
        block = src.read(1, window=win, boundless=True, fill_value=NODATA,
                         out_shape=(height * step, width * step))
        if step > 1:
            # Reading at a coarser level than the source still takes the
            # shoalest, for the same reason the overviews do.
            block = shoalest(block, step)
        here = got == NODATA
        got[here] = block[here]
    return got


def shoalest(block, factor):
    """Shrink by `factor`, keeping the CLOSEST-TO-SURFACE cell of each group.

    Written with an explicit mask rather than a plain `max`. A plain max happens
    to do the right thing only because NODATA is Int16's floor and so loses to
    every real value -- which is true today and stops being true the moment
    somebody picks a different sentinel. The mask says what is meant."""
    h, w = block.shape
    h -= h % factor
    w -= w % factor
    grouped = block[:h, :w].reshape(h // factor, factor, w // factor, factor)
    real = grouped != NODATA
    # Where nothing real is in the group the answer is NODATA; elsewhere it is
    # the largest real value, which for elevation-positive-up is the shallowest.
    masked = np.where(real, grouped, DEEPEST - 1)
    best = masked.max(axis=(1, 3)).astype(np.int16)
    any_real = real.any(axis=(1, 3))
    return np.where(any_real, best, NODATA).astype(np.int16)


def tile_span(level, bounds):
    """Which tile indices cover the requested box at this level."""
    south, west, north, east = bounds
    cell = cell_at(level)
    span = TILE * cell
    tx0 = int(np.floor((west - WEST) / span))
    tx1 = int(np.ceil((east - WEST) / span))
    ty0 = int(np.floor((NORTH - north) / span))
    ty1 = int(np.ceil((NORTH - south) / span))
    return ty0, ty1, tx0, tx1


def write_tile(root, level, ty, tx, cells):
    path = root / ("%d/%d" % (level, ty))
    path.mkdir(parents=True, exist_ok=True)
    # Raw little-endian Int16, no header. The manifest says what it is; a header
    # per tile would be a second place for the same truth to be written.
    (path / ("%d.i16" % tx)).write_bytes(cells.astype("<i2").tobytes())


def read_tile(root, level, ty, tx):
    path = root / ("%d/%d/%d.i16" % (level, ty, tx))
    if not path.exists():
        return None
    return np.frombuffer(path.read_bytes(), dtype="<i2").reshape(TILE, TILE)


def build_level0(sources, root, bounds):
    ty0, ty1, tx0, tx1 = tile_span(0, bounds)
    cell = cell_at(0)
    span = TILE * cell
    written, empty = 0, 0
    began = time.time()
    total = (ty1 - ty0) * (tx1 - tx0)
    for ty in range(ty0, ty1):
        for tx in range(tx0, tx1):
            cells = sample(sources, 0, WEST + tx * span, NORTH - ty * span,
                           TILE, TILE)
            if (cells == NODATA).all():
                empty += 1
                continue
            write_tile(root, 0, ty, tx, cells)
            written += 1
        done = (ty - ty0 + 1) * (tx1 - tx0)
        print("   level 0: %5d/%d tiles, %d written, %d empty  (%.0fs)"
              % (done, total, written, empty, time.time() - began), flush=True)
    return {"y0": ty0, "y1": ty1, "x0": tx0, "x1": tx1, "tiles": written}


def build_overviews(root, level0, levels):
    """Each level from the one below, four children to a parent, shoalest wins."""
    spans = {0: level0}
    for level in range(1, levels):
        below = spans[level - 1]
        ty0, ty1 = below["y0"] // 2, (below["y1"] + 1) // 2
        tx0, tx1 = below["x0"] // 2, (below["x1"] + 1) // 2
        written = 0
        for ty in range(ty0, ty1):
            for tx in range(tx0, tx1):
                # A parent tile is 2x2 child tiles, each halved.
                big = np.full((TILE * 2, TILE * 2), NODATA, dtype=np.int16)
                found = False
                for dy in (0, 1):
                    for dx in (0, 1):
                        kid = read_tile(root, level - 1, ty * 2 + dy, tx * 2 + dx)
                        if kid is None:
                            continue
                        found = True
                        big[dy * TILE:(dy + 1) * TILE,
                            dx * TILE:(dx + 1) * TILE] = kid
                if not found:
                    continue
                write_tile(root, level, ty, tx, shoalest(big, 2))
                written += 1
        spans[level] = {"y0": ty0, "y1": ty1, "x0": tx0, "x1": tx1,
                        "tiles": written}
        print("   level %d: %d tiles" % (level, written), flush=True)
    return spans


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", nargs="+", required=True,
                    help="GEBCO GeoTIFF or netCDF tiles covering the box")
    ap.add_argument("--out", required=True, help="where the pyramid goes")
    ap.add_argument("--bounds", nargs=4, type=float, required=True,
                    metavar=("SOUTH", "WEST", "NORTH", "EAST"))
    ap.add_argument("--levels", type=int, default=7)
    args = ap.parse_args()

    root = pathlib.Path(args.out)
    root.mkdir(parents=True, exist_ok=True)
    sources = open_sources(args.source)
    print("SOURCES accepted: %d, all EPSG:4326 on the 1/240 lattice."
          % len(sources))
    print("CUTTING %s at 15 arc-seconds, shoalest-wins overviews."
          % (tuple(args.bounds),))

    level0 = build_level0(sources, root, args.bounds)
    spans = build_overviews(root, level0, args.levels)

    (root / "manifest.json").write_text(json.dumps({
        "crs": "EPSG:4326",
        "units": "metres",
        # SPELLED OUT, because the day a chart-datum source is mosaicked in, the
        # difference between these two strings is the difference between a rock
        # drawn as a rock and a rock drawn as open water.
        "vertical_datum": "approximate mean sea level (GEBCO_2026 as published)",
        "sign": "positive up: land is positive, sea floor is negative",
        "not_for_navigation": (
            "Compiled bathymetry at 15 arc-seconds (about 450 m). Not chart "
            "datum, not surveyed soundings, not corrected. Planning and display "
            "only."),
        "dtype": "int16 little-endian, raw, no header",
        "nodata": NODATA,
        "tile": TILE,
        "per_degree": PER_DEGREE,
        "origin": {"west": WEST, "north": NORTH},
        "overview": "shoalest of four children (max elevation), never the mean",
        "bounds": {"south": args.bounds[0], "west": args.bounds[1],
                   "north": args.bounds[2], "east": args.bounds[3]},
        "levels": {str(k): v for k, v in spans.items()},
        "source_files": [str(p) for p in args.source],
        "built": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }, indent=2) + "\n")
    print("MANIFEST written. %d levels, %d tiles at level 0."
          % (len(spans), level0["tiles"]))
    print("Now run: python3 tools/soundings.py %s" % args.out)


if __name__ == "__main__":
    main()
