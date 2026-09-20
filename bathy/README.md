# Soundings — the seafloor of North America, tiled

Turns the published GEBCO grid into a pyramid of raw `Int16` tiles a tablet can
stream, and then proves the pyramid did not lose anything on the way up.

```bash
pip install rasterio                       # brings its own GDAL; no apt needed

python3 bathy/fetch.py --dest gebco        # 4 GB, resumable
python3 bathy/fetch.py --dest gebco --no-download --pick 5 -170 85 -50
python3 bathy/build.py --source gebco/grid/<the files it named> \
        --out tiles/north_america --bounds 5 -170 85 -50
python3 tools/soundings.py tiles/north_america --require \
        --source gebco/grid/<the same files>
```

North America at 15 arc-seconds is **19 200 × 28 800 cells, 1.11 GB at level 0
and 1.47 GB for the whole seven-level pyramid**, in 2 166 base tiles. The
download is the slow part; the tiling is minutes.

Faster first result: <https://download.gebco.net/> cuts an arbitrary box, so you
can tile one coast before committing to the continent.

## The one decision worth understanding

**Overviews take the shoalest cell, never the average.**

Average four cells of −40, −38, −41 and −2 and you get −30. The rock is gone,
the water is drawn open, and every zoom level agrees with every other, so
nothing looks wrong anywhere on the chart. `gdaladdo` averages by default.

So a parent cell is the **maximum** of its four children — the closest to the
surface. Zooming out can therefore only ever make the water look *shallower*
than it is, never deeper. That is the direction an error is allowed to point,
and `tools/soundings.py` finds the shoalest submerged cell in the whole data set
and follows it to the top of the pyramid to prove it survived.

## What this is not

GEBCO's Terms of Use say it plainly, and accepting them is a condition of having
the data:

> The GEBCO Grid should NOT be used for navigation or for any other purpose
> involving safety at sea.

It is a 15-arc-second **interpolated compilation** — about 450 m a cell, and
elevation relative to approximate mean sea level, positive up. A nautical chart
sounding is depth below **chart datum** (roughly MLLW in the US), positive down,
and deliberately pessimistic. The two differ by one to three metres in tidal
water and are not interchangeable. The manifest records the datum and the sign
convention by name so that the day a real survey is mosaicked in, the mismatch
is a loud failure rather than a quiet couple of metres.

Put the disclaimer on the screen, not in this file.

## Next, and in this order

1. **The TID grid** — `fetch.py --tid`, 92 MB compressed. One byte a cell saying
   whether that value came from a real survey or from interpolation. This is the
   single most valuable addition here: it lets the display *show* which depths
   are measured and which are guessed, which turns the disclaimer above from
   small print into a visible property of the chart. Not implemented, because
   its code table should be read rather than guessed at.
2. **Inland and harbour water.** GEBCO is an ocean product. "Every navigable
   body of water in North America" also means:
   - **USACE eHydro** — the US Army Corps' surveys of the navigable channels
     themselves, which is the most literal reading of "navigable" there is.
   - **NOAA ENC / BlueTopo** — US coastal and harbour scale, weekly updates.
   - **NOAA Great Lakes bathymetry.**
   - **CHS NONNA-10 / NONNA-100** — Canada's open bathymetry.
   - **USGS 3DEP** for land elevation at 1/3 arc-second.
   Each arrives on a different lattice with a different vertical datum, which is
   why they are a second pass and not a Tuesday: mixing datums without handling
   them gives depths that are wrong by metres with nothing on screen to say so.
   `build.py` refuses any source off the 1/240 lattice for exactly this reason.
3. **GEBCO's multi-resolution product**, which carries higher resolution where
   it exists and is available through the same download application.

## Files

| | |
|---|---|
| `bathy/fetch.py` | Fetches and unpacks the grid; names which files overlap your box, by reading their own georeference rather than guessing filenames. |
| `bathy/build.py` | Cuts the pyramid. Refuses any source not on GEBCO's lattice. |
| `bathy/probe.py` | Makes a small GEBCO-shaped raster with a one-cell pinnacle in it, so the pipeline can be tested without the 4 GB download. |
| `tools/soundings.py` | The checks. Run it with `--require` after a build, so a build that refused its source cannot read as a clean run. |

## Attribution, which is required

> GEBCO Bathymetric Compilation Group 2026 (2026). The GEBCO_2026 Grid — a
> continuous terrain model for oceans and land at 15 arc-second intervals.
> doi:10.5285/4f68d5c7-45eb-f999-e063-7086abc036fa

Public domain: free to copy, adapt, redistribute and use commercially, provided
the source is acknowledged, no official status or endorsement is implied, and
the data is not misrepresented.
