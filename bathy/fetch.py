#!/usr/bin/env python3
"""GETTING THE GRID, AND PICKING THE RIGHT PIECES OF IT.

GEBCO_2026 is published as one global netCDF of 7.5 GB and, more usefully, as a
set of EIGHT GeoTIFFs of 90 by 90 degrees. North America needs two of them, so
the whole continent costs about a quarter of the global download -- and the
subset application at https://download.gebco.net/ will cut an arbitrary box for
you, which is smaller again and is the quickest route to a first result.

WHY THIS DOES NOT HARD-CODE THE FILENAMES. GEBCO's tile names have changed shape
between releases, and a script that guesses one and gets it wrong does not fail
loudly -- it quietly fetches one tile instead of two and leaves you with half a
continent and no error. So nothing here is named: it unpacks whatever is in the
archive, reads each file's OWN georeference, and reports which ones actually
overlap the box you asked for. If that list is shorter than you expected, you
find out here rather than three hours into a tiling run.

THE DOWNLOAD ITSELF IS RESUMABLE, because four gigabytes over a domestic
connection does not always arrive on the first attempt, and starting again from
zero is how people give up on a dataset.

    python3 bathy/fetch.py --dest gebco                    # fetch and unpack
    python3 bathy/fetch.py --dest gebco --pick 5 -170 85 -50   # which files matter

TERMS. The GEBCO Grid is public domain and may be copied, adapted, redistributed
and commercially used, on three conditions: acknowledge the source, do not imply
official status or endorsement, and do not misrepresent the data. The required
attribution is:

    GEBCO Bathymetric Compilation Group 2026 (2026). The GEBCO_2026 Grid - a
    continuous terrain model for oceans and land at 15 arc-second intervals.
    doi:10.5285/4f68d5c7-45eb-f999-e063-7086abc036fa

AND GEBCO'S OWN DISCLAIMER, which is a condition of use and not a footnote:
"The GEBCO Grid should NOT be used for navigation or for any other purpose
involving safety at sea."
"""
import argparse
import pathlib
import subprocess
import sys
import zipfile

## WHERE IT ACTUALLY LIVES. CEDA hosts the archives for BODC; the ?download=1 is
## part of the URL and not decoration -- without it you get a landing page.
GRID_ZIP = ("https://dap.ceda.ac.uk/bodc/gebco/global/gebco_2026/"
            "ice_surface_elevation/geotiff/gebco_2026_geotiff.zip?download=1")
## THE TYPE IDENTIFIER GRID: one byte a cell saying where that cell's value came
## from -- a real survey, or an interpolation. 92 MB compressed, and the only
## thing in this whole pipeline that can tell a measured depth from a guessed
## one. Worth having on the screen; see bathy/README.md.
TID_ZIP = ("https://dap.ceda.ac.uk/bodc/gebco/global/gebco_2026/"
           "type_identifier_grid/geotiff/gebco_2026_tid_geotiff.zip?download=1")
BROWSE = "https://data.ceda.ac.uk/bodc/gebco/global/gebco_2026"
SUBSET_APP = "https://download.gebco.net/"


def download(url, into):
    """curl with --continue-at, so a broken transfer resumes instead of restarting."""
    into.parent.mkdir(parents=True, exist_ok=True)
    print("FETCHING %s\n      -> %s" % (url.split("?")[0], into))
    done = subprocess.run(
        ["curl", "-L", "--fail", "--continue-at", "-", "--retry", "5",
         "--retry-delay", "4", "--retry-all-errors", "-o", str(into), url])
    if done.returncode != 0:
        sys.exit("FETCH FAILED (curl exit %d). The archive is also browsable at "
                 "%s, and %s will cut a smaller box for you."
                 % (done.returncode, BROWSE, SUBSET_APP))
    print("   %.2f GB on disk." % (into.stat().st_size / 1e9))


def unpack(archive, into):
    into.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as zf:
        members = [m for m in zf.namelist() if not m.endswith("/")]
        print("UNPACKING %d member(s) from %s" % (len(members), archive.name))
        zf.extractall(into)
    rasters = sorted(p for p in into.rglob("*")
                     if p.suffix.lower() in (".tif", ".tiff", ".nc"))
    print("   %d raster(s): %s" % (len(rasters),
                                   ", ".join(p.name for p in rasters[:4])
                                   + (" ..." if len(rasters) > 4 else "")))
    return rasters


def overlapping(rasters, box):
    """Which of these files actually touch the box, by their OWN georeference.

    south, west, north, east -- and the comparison is strict on the far edges so
    a file that merely abuts the box is not counted as covering it."""
    import rasterio
    south, west, north, east = box
    keep = []
    for path in rasters:
        name = ('netCDF:"%s":elevation' % path) if path.suffix == ".nc" else str(path)
        try:
            with rasterio.open(name) as src:
                left, bottom, right, top = src.bounds
        except Exception as why:                       # noqa: BLE001
            print("   UNREADABLE %s (%s)" % (path.name, why))
            continue
        if left < east and right > west and bottom < north and top > south:
            keep.append(path)
            print("   USE  %-52s  %.1f..%.1f N  %.1f..%.1f E"
                  % (path.name, bottom, top, left, right))
        else:
            print("   skip %-52s  %.1f..%.1f N  %.1f..%.1f E"
                  % (path.name, bottom, top, left, right))
    return keep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default="gebco")
    ap.add_argument("--tid", action="store_true", help="also fetch the TID grid")
    ap.add_argument("--pick", nargs=4, type=float, default=None,
                    metavar=("SOUTH", "WEST", "NORTH", "EAST"),
                    help="report which unpacked files overlap this box")
    ap.add_argument("--no-download", action="store_true",
                    help="do not fetch anything; unpack an archive already on "
                         "disk if the rasters are not out yet, and otherwise use "
                         "what is there. A four-gigabyte archive sitting beside "
                         "an empty directory is the ordinary state of things "
                         "after an interrupted run, and it should not need "
                         "re-downloading to get past.")
    args = ap.parse_args()
    dest = pathlib.Path(args.dest)

    zip_at = dest / "gebco_2026_geotiff.zip"
    if args.no_download:
        # Nothing to fetch, but an archive already here still needs opening.
        out = dest / "grid"
        already = any(p.suffix.lower() in (".tif", ".tiff", ".nc")
                      for p in out.rglob("*")) if out.is_dir() else False
        if not already and zip_at.exists():
            unpack(zip_at, out)
    else:
        if zip_at.exists():
            print("ALREADY HAVE %s (%.2f GB) — delete it to fetch again."
                  % (zip_at, zip_at.stat().st_size / 1e9))
        else:
            download(GRID_ZIP, zip_at)
        unpack(zip_at, dest / "grid")
        if args.tid:
            tid_at = dest / "gebco_2026_tid_geotiff.zip"
            if not tid_at.exists():
                download(TID_ZIP, tid_at)
            unpack(tid_at, dest / "tid")

    rasters = sorted(p for p in (dest / "grid").rglob("*")
                     if p.suffix.lower() in (".tif", ".tiff", ".nc"))
    if not rasters:
        sys.exit("NOTHING UNPACKED under %s/grid. Fetch first, or point --dest at "
                 "where the archive was expanded." % dest)
    if args.pick:
        print("\nWHICH FILES COVER %s:" % (tuple(args.pick),))
        keep = overlapping(rasters, args.pick)
        if not keep:
            sys.exit("NO FILE OVERLAPS THAT BOX. Either the box is wrong or this "
                     "is not the grid you think it is — nothing downstream can "
                     "recover from tiling an empty region.")
        print("\nNext:\n  python3 bathy/build.py --source %s \\\n"
              "      --out tiles/north_america --bounds %g %g %g %g"
              % (" ".join(str(p) for p in keep), *args.pick))
    return 0


if __name__ == "__main__":
    sys.exit(main())
