#!/usr/bin/env python3
"""A SMALL PIECE OF FAKE SEAFLOOR, SHAPED EXACTLY LIKE THE REAL THING.

The real grid is a 4 GB download and the machine this was written on could not
reach gebco.net at all. That is a bad reason to ship an untested tiler, so this
makes a raster that is GEBCO in every respect that the builder can actually
observe: EPSG:4326, 15 arc-seconds, Int16 metres, positive up, pixel-is-area,
and its west and north edges a whole number of cells from -180/+90.

It is NOT a model of the seafloor and is not trying to be. It exists so that
every code path in build.py and tools/soundings.py runs on something with a
coastline, a deep basin, a shoal and a piece of dry land in it -- and, most of
all, so that a PINNACLE can be planted in a single cell and then looked for at
the top of the pyramid. A shoalest-wins overview either carries that one cell
all the way up or it does not, and that is the one thing about this pipeline
that nobody would notice was broken.

    python3 bathy/probe.py --out probe/gebco_probe.tif --bounds 40 -75 44 -69
"""
import argparse

import numpy as np
import rasterio
from rasterio.transform import from_origin

PER_DEGREE = 240
CELL = 1.0 / PER_DEGREE

## WHERE THE PINNACLE GOES, and how high it comes. One cell, in open water, put
## somewhere no rounding is likely to land on it by accident. tools/soundings.py
## is told the same two numbers and goes looking for it.
PINNACLE_AT = (0.37, 0.61)      # as a fraction of the raster, row then column
PINNACLE_TO = -3                # metres: a rock three metres under the surface


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--bounds", nargs=4, type=float, required=True,
                    metavar=("SOUTH", "WEST", "NORTH", "EAST"))
    args = ap.parse_args()
    south, west, north, east = args.bounds

    # Snap the corners onto the global lattice, because that is the one thing
    # build.py refuses a source for, and a probe that could not be refused for
    # it would not be testing the refusal.
    west = WEST_SNAP = round((west + 180.0) * PER_DEGREE) / PER_DEGREE - 180.0
    north = round((90.0 - north) * PER_DEGREE)
    north = 90.0 - north / PER_DEGREE
    rows = int(round((north - south) * PER_DEGREE))
    cols = int(round((east - WEST_SNAP) * PER_DEGREE))

    yy, xx = np.mgrid[0:rows, 0:cols]
    fy, fx = yy / rows, xx / cols

    # A shelf falling away to a basin, west to east, with land in the top-left.
    depth = -20.0 - 4200.0 * np.clip((fx - 0.28) / 0.6, 0.0, 1.0) ** 1.7
    # A bay cut into the coast, so there is a real coastline to not interpolate
    # across rather than a straight edge.
    land = (fx < 0.22 + 0.10 * np.sin(fy * 9.0)) & (fy < 0.78)
    height = 4.0 + 900.0 * np.clip((0.24 - fx) / 0.24, 0.0, 1.0) ** 1.4
    grid = np.where(land, height, depth)
    # A shoal bank: the sort of thing that must survive being zoomed out.
    bank = np.exp(-(((fy - 0.55) / 0.06) ** 2 + ((fx - 0.44) / 0.09) ** 2))
    grid += bank * 260.0
    grid = np.clip(grid, -11000, 8800).astype(np.int16)

    # AND THE ONE CELL THAT MATTERS.
    pr = int(rows * PINNACLE_AT[0])
    pc = int(cols * PINNACLE_AT[1])
    grid[pr, pc] = PINNACLE_TO

    with rasterio.open(
            args.out, "w", driver="GTiff", height=rows, width=cols, count=1,
            dtype="int16", crs="EPSG:4326",
            transform=from_origin(WEST_SNAP, north, CELL, CELL),
            tiled=True, blockxsize=256, blockysize=256, compress="deflate") as dst:
        dst.write(grid, 1)

    print("PROBE %s: %d x %d cells, %.4f..%.4f N, %.4f..%.4f E"
          % (args.out, rows, cols, south, north, WEST_SNAP, east))
    print("   deepest %d m, highest %d m, %.1f%% of it dry land."
          % (grid.min(), grid.max(), land.mean() * 100))
    print("   PINNACLE of %d m planted at row %d col %d — a single cell, in "
          "open water, %.4f N %.4f E."
          % (PINNACLE_TO, pr, pc, north - (pr + 0.5) * CELL,
             WEST_SNAP + (pc + 0.5) * CELL))


if __name__ == "__main__":
    main()
