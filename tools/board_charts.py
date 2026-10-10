#!/usr/bin/env python3
"""THE CHESSBOARD'S CLOCKWORK, DRAWN: charts of a century of towns out of sight.

    godot --headless --path . --script tools/live/century_live.gd -- century.csv
    python3 tools/board_charts.py century.csv chessboard.html

Reads the CSV the century harness writes (every town, every year) and draws a
page: how each kind of land's towns grew and settled, what stage they ended at,
what took their people, how many children they lost and how much they kept in
store. Plain SVG, no libraries -- the charts are the same numbers the harness
judges, so a page that looks wrong is a model that is wrong.
"""
import csv
import html
import json
import statistics
import sys

KINDS = ["plains", "forest", "fishing", "cramped", "wolves", "tundra", "desert", "ruin"]
LABEL = {"plains": "Open plains", "forest": "Forest", "fishing": "Fishing cove",
         "wolves": "Wolf country", "tundra": "Tundra", "desert": "Desert",
         "cramped": "Rich but cramped",
         "ruin": "Ruins, on any land"}
STAGES = ["camp", "hamlet", "village", "town", "city"]
EAT = {"children": 0.35, "adults": 0.85, "elders": 0.7}


def load(path):
    rows = list(csv.DictReader(open(path)))
    towns = {}
    for r in rows:
        towns.setdefault(r["town"], []).append(r)
    return towns


def pct(values, q):
    s = sorted(values)
    if not s:
        return 0.0
    i = (len(s) - 1) * q
    lo, hi = int(i), min(int(i) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (i - lo)


def pop(r):
    return float(r["children"]) + float(r["adults"]) + float(r["elders"])


def summarise(towns):
    out = {}
    for kind in KINDS:
        mine = [t for name, t in towns.items() if t[0]["kind"] == kind]
        if not mine:
            continue
        years = min(len(t) for t in mine)
        series = []
        for y in range(years):
            vals = [pop(t[y]) for t in mine]
            series.append([round(float(mine[0][y]["year"])), round(pct(vals, 0.1), 1),
                           round(statistics.median(vals), 1), round(pct(vals, 0.9), 1)])
        ends = [t[-1] for t in mine]
        stages = [0] * 5
        for e in ends:
            stages[int(e["stage"])] += 1
        deaths = {"old age": sum(float(e["aged_out"]) for e in ends),
                  "hunger": sum(float(e["starved"]) for e in ends),
                  "beasts": sum(float(e["taken"]) for e in ends)}
        born = sum(float(e["born"]) for e in ends)
        lost = sum(float(e["lost_young"]) for e in ends)
        granary = []
        for e in ends:
            need = sum(float(e[k]) * v for k, v in EAT.items())
            if need > 0:
                granary.append(float(e["food"]) / need)
        end_pops = [pop(e) for e in ends]
        out[kind] = {
            "label": LABEL[kind], "series": series, "stages": stages, "deaths": deaths,
            "young_lost": 100.0 * lost / born if born > 0 else 0.0,
            "granary": statistics.median(granary) if granary else 0.0,
            "end": [min(end_pops), statistics.median(end_pops), max(end_pops)],
            "towns": len(mine),
        }
    return out


def nice_max(v):
    for step in (5, 10, 20, 25, 50, 100, 200, 250, 500):
        if v <= step * 4:
            return step * (int(v / step) + 1), step
    return v, v / 4


def multiples(data):
    """One small panel per kind of land: the middle town, and the 10-90 band."""
    w, h, left, bottom, top = 300, 170, 40, 26, 14
    cards = []
    for kind, d in data.items():
        s = d["series"]
        x_max = s[-1][0]
        y_max, step = nice_max(max(p[3] for p in s))
        px = lambda yr: left + (w - left - 10) * yr / x_max
        py = lambda v: top + (h - top - bottom) * (1 - v / y_max)
        band = " ".join(f"{px(p[0]):.1f},{py(p[3]):.1f}" for p in s) + " " + \
            " ".join(f"{px(p[0]):.1f},{py(p[1]):.1f}" for p in reversed(s))
        line = " ".join(f"{px(p[0]):.1f},{py(p[2]):.1f}" for p in s)
        grid = []
        v = 0
        while v <= y_max + 0.01:
            grid.append(f'<line x1="{left}" x2="{w - 10}" y1="{py(v):.1f}" y2="{py(v):.1f}" class="grid"/>'
                        f'<text x="{left - 6}" y="{py(v) + 4:.1f}" class="tick" text-anchor="end">{int(v)}</text>')
            v += step
        for yr in (0, 60, 120, 180):
            if yr <= x_max:
                grid.append(f'<text x="{px(yr):.1f}" y="{h - 8}" class="tick" text-anchor="middle">{yr}</text>')
        last = s[-1]
        cards.append(f'''
<figure class="panel" data-kind="{kind}">
  <figcaption><span class="pname">{html.escape(d["label"])}</span>
    <span class="pval">ends at {last[2]:.0f} <span class="muted">({last[1]:.0f}&ndash;{last[3]:.0f})</span></span></figcaption>
  <svg viewBox="0 0 {w} {h}" role="img" aria-label="{html.escape(d['label'])}: population over {x_max} years">
    {''.join(grid)}
    <polygon points="{band}" class="band"/>
    <polyline points="{line}" class="line"/>
    <circle cx="{px(last[0]):.1f}" cy="{py(last[2]):.1f}" r="4" class="enddot"/>
    <line class="cross" x1="0" x2="0" y1="{top}" y2="{h - bottom}" visibility="hidden"/>
    <rect class="hit" x="{left}" y="{top}" width="{w - left - 10}" height="{h - top - bottom}"
      data-x0="{left}" data-xw="{w - left - 10}" data-xmax="{x_max}"/>
  </svg>
</figure>''')
    return "\n".join(cards)


def stacked(data, field, names, cls, fmt, title_note):
    rows = []
    for kind, d in data.items():
        vals = [float(v) for v in (d[field] if isinstance(d[field], list) else d[field].values())]
        total = sum(vals) or 1.0
        segs = []
        for i, v in enumerate(vals):
            if v <= 0:
                continue
            share = 100.0 * v / total
            tip = f"{d['label']}: {names[i]} {fmt(v, share)}"
            segs.append(f'<span class="seg {cls}{i}" style="flex-grow:{share:.3f}" '
                        f'data-tip="{html.escape(tip)}"></span>')
        rows.append(f'<div class="srow"><span class="slabel">{html.escape(d["label"])}</span>'
                    f'<span class="sbar">{"".join(segs)}</span></div>')
    legend = "".join(f'<span class="key"><span class="sw {cls}{i}"></span>{n}</span>'
                     for i, n in enumerate(names))
    return f'<div class="legend">{legend}</div><div class="stack" aria-label="{title_note}">{"".join(rows)}</div>'


def bars(data, value, unit, digits=0):
    top = max(value(d) for d in data.values()) or 1.0
    rows = []
    for kind, d in data.items():
        v = value(d)
        rows.append(f'<div class="brow" data-tip="{html.escape(d["label"])}: {v:.{digits}f}{unit}">'
                    f'<span class="slabel">{html.escape(d["label"])}</span>'
                    f'<span class="btrack"><span class="bfill" style="width:{100.0 * v / top:.1f}%"></span>'
                    f'<span class="bval">{v:.{digits}f}{unit}</span></span></div>')
    return "".join(rows)


def table(data):
    head = ("<tr><th>Land</th><th>Towns</th><th>Low</th><th>Middle</th><th>High</th>"
            + "".join(f"<th>{s}</th>" for s in STAGES)
            + "<th>Young lost</th><th>Granary</th></tr>")
    body = []
    for d in data.values():
        e = d["end"]
        body.append(f"<tr><td>{html.escape(d['label'])}</td><td>{d['towns']}</td>"
                    f"<td>{e[0]:.0f}</td><td>{e[1]:.0f}</td><td>{e[2]:.0f}</td>"
                    + "".join(f"<td>{n}</td>" for n in d["stages"])
                    + f"<td>{d['young_lost']:.0f}%</td><td>{d['granary']:.1f} y</td></tr>")
    return f"<table><thead>{head}</thead><tbody>{''.join(body)}</tbody></table>"


PAGE = """<title>Chessboard Century</title>
<style>
:root {
  --surface: #fcfcfb; --card: #f4f3ef; --ink: #0b0b0b; --ink-2: #52514e; --muted: #7a7974;
  --grid: #e4e3dd; --s1: #2a78d6; --s2: #eb6834; --s3: #1baf7a;
  --st0: #86b6ef; --st1: #5598e7; --st2: #2a78d6; --st3: #1c5cab; --st4: #104281;
  --band: rgba(42, 120, 214, 0.12);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --surface: #1a1a19; --card: #232321; --ink: #f0efec; --ink-2: #c3c2b7; --muted: #95948c;
    --grid: #33332f; --s1: #3987e5; --s2: #d95926; --s3: #199e70;
    --st0: #184f95; --st1: #256abf; --st2: #3987e5; --st3: #6da7ec; --st4: #b7d3f6;
    --band: rgba(57, 135, 229, 0.16);
  }
}
:root[data-theme="dark"] {
  --surface: #1a1a19; --card: #232321; --ink: #f0efec; --ink-2: #c3c2b7; --muted: #95948c;
  --grid: #33332f; --s1: #3987e5; --s2: #d95926; --s3: #199e70;
  --st0: #184f95; --st1: #256abf; --st2: #3987e5; --st3: #6da7ec; --st4: #b7d3f6;
  --band: rgba(57, 135, 229, 0.16);
}
body { background: var(--surface); color: var(--ink); padding-inline: 16px; padding-block: 28px 48px;
  font: 15px/1.5 "Source Sans 3", "Segoe UI", system-ui, sans-serif; }
main { max-width: 1040px; margin: 0 auto; display: grid; gap: 34px; }
main > *, .two > * { min-width: 0; }
h1 { font: 600 30px/1.15 "Source Serif 4", Georgia, serif; margin: 0; text-wrap: balance; }
h2 { font: 600 19px/1.3 "Source Serif 4", Georgia, serif; margin: 0 0 4px; }
.lede { color: var(--ink-2); max-width: 66ch; margin: 8px 0 0; }
.note { color: var(--muted); font-size: 13px; margin: 0 0 12px; max-width: 70ch; }
.verdict { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px; }
.chip { font-size: 13px; padding: 3px 10px; border-radius: 999px; background: var(--card); color: var(--ink-2); }
.chip b { color: var(--ink); font-weight: 600; }
.grid3 { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 14px; }
.panel { margin: 0; background: var(--card); border-radius: 10px; padding: 10px 10px 4px; }
figcaption { display: flex; justify-content: space-between; align-items: baseline; gap: 8px;
  font-size: 14px; padding: 0 4px 2px; }
.pname { font-weight: 600; } .pval { color: var(--ink-2); font-variant-numeric: tabular-nums; font-size: 13px; }
.muted { color: var(--muted); }
svg { width: 100%; height: auto; display: block; overflow: visible; }
.grid { stroke: var(--grid); stroke-width: 1; }
.tick { fill: var(--muted); font-size: 10px; font-variant-numeric: tabular-nums; }
.band { fill: var(--band); }
.line { fill: none; stroke: var(--s1); stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
.enddot { fill: var(--s1); stroke: var(--card); stroke-width: 2; }
.cross { stroke: var(--ink-2); stroke-width: 1; }
.hit { fill: transparent; cursor: crosshair; }
.legend { display: flex; flex-wrap: wrap; gap: 14px; margin: 0 0 10px; font-size: 13px; color: var(--ink-2); }
.key { display: inline-flex; align-items: center; gap: 6px; }
.sw { width: 12px; height: 12px; border-radius: 3px; display: inline-block; }
.stack, .bars { display: grid; gap: 8px; }
.srow, .brow { display: grid; grid-template-columns: 150px 1fr; align-items: center; gap: 12px; }
.slabel { font-size: 14px; color: var(--ink-2); }
.sbar { display: flex; gap: 2px; height: 20px; }
.seg { min-width: 2px; height: 100%; }
.seg:first-child { border-radius: 4px 0 0 4px; } .seg:last-child { border-radius: 0 4px 4px 0; }
.seg:only-child { border-radius: 4px; }
.d0 { background: var(--s1); } .d1 { background: var(--s2); } .d2 { background: var(--s3); }
.g0 { background: var(--st0); } .g1 { background: var(--st1); } .g2 { background: var(--st2); }
.g3 { background: var(--st3); } .g4 { background: var(--st4); }
.btrack { display: flex; align-items: center; gap: 8px; height: 20px; }
.bfill { height: 20px; max-height: 20px; background: var(--s1); border-radius: 0 4px 4px 0; min-width: 2px; }
.bval { font-size: 13px; color: var(--ink-2); font-variant-numeric: tabular-nums; white-space: nowrap; }
.two { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 34px; }
.tablewrap { overflow-x: auto; }
table { border-collapse: collapse; font-size: 13px; font-variant-numeric: tabular-nums; width: 100%; }
th, td { padding: 6px 8px; text-align: right; border-bottom: 1px solid var(--grid); white-space: nowrap; }
th:first-child, td:first-child { text-align: left; }
th { color: var(--ink-2); font-weight: 600; }
#tip { position: fixed; pointer-events: none; background: var(--ink); color: var(--surface);
  font-size: 12px; padding: 5px 8px; border-radius: 6px; font-variant-numeric: tabular-nums; z-index: 10; }
@media (max-width: 520px) { .srow, .brow { grid-template-columns: 96px 1fr; } }
</style>
<main>
  <header>
    <h1>The chessboard, a century and a half on</h1>
    <p class="lede">Every town here is a town out of sight: no people on the ground, only the numbers
    the game steps a quarter-day at a time. Forty towns on each of eight kinds of land, every figure of the land
    jittered, run for 180 game years &mdash; about 100 game days, or nine hours of play.</p>
    <div class="verdict">__CHIPS__</div>
  </header>
  <section>
    <h2>How they grew, and where they settled</h2>
    <p class="note">The line is the middle town of the forty; the wash is the 10th to 90th percentile.
    Each panel has its own scale &mdash; a desert camp and a plains city do not share one.</p>
    <div class="grid3">__MULTIPLES__</div>
  </section>
  <section>
    <h2>What they became</h2>
    <p class="note">The stage each town had reached by the end. Stages move only after the case has
    held for years, so a town does not flicker between them.</p>
    __STAGES__
  </section>
  <div class="two">
    <section>
      <h2>What took their people</h2>
      <p class="note">Every death over the whole run, by cause.</p>
      __DEATHS__
    </section>
    <section>
      <h2>Children lost, per hundred born</h2>
      <p class="note">To hunger, to beasts, and to the bad luck of a poor place. A ruin's and a desert's
      founding children count here too.</p>
      <div class="bars">__YOUNG__</div>
    </section>
  </div>
  <section>
    <h2>Years of food in store at the end</h2>
    <p class="note">Towns work to keep two years put by, ease off sharply past it, and throw out what
    sours past five.</p>
    <div class="bars">__GRANARY__</div>
  </section>
  <section>
    <h2>The numbers</h2>
    <div class="tablewrap">__TABLE__</div>
  </section>
</main>
<div id="tip" hidden></div>
<script>
const DATA = __DATA__;
const tip = document.getElementById('tip');
function show(e, text) { tip.textContent = text; tip.hidden = false;
  const x = Math.min(e.clientX + 14, window.innerWidth - tip.offsetWidth - 8);
  tip.style.left = x + 'px'; tip.style.top = (e.clientY + 14) + 'px'; }
function hide() { tip.hidden = true; }
document.querySelectorAll('.panel').forEach(fig => {
  const d = DATA[fig.dataset.kind], hit = fig.querySelector('.hit'), cross = fig.querySelector('.cross');
  const svg = fig.querySelector('svg');
  hit.addEventListener('pointermove', e => {
    const pt = svg.createSVGPoint(); pt.x = e.clientX; pt.y = e.clientY;
    const p = pt.matrixTransform(svg.getScreenCTM().inverse());
    const x0 = +hit.dataset.x0, xw = +hit.dataset.xw, xmax = +hit.dataset.xmax;
    const yr = Math.max(0, Math.min(xmax, (p.x - x0) / xw * xmax));
    const row = d.series.reduce((a, b) => Math.abs(b[0] - yr) < Math.abs(a[0] - yr) ? b : a);
    const cx = x0 + xw * row[0] / xmax;
    cross.setAttribute('x1', cx); cross.setAttribute('x2', cx); cross.setAttribute('visibility', 'visible');
    show(e, `${d.label}, year ${row[0]}: ${Math.round(row[2])} people (${Math.round(row[1])}–${Math.round(row[3])})`);
  });
  hit.addEventListener('pointerleave', () => { cross.setAttribute('visibility', 'hidden'); hide(); });
});
document.querySelectorAll('[data-tip]').forEach(el => {
  el.addEventListener('pointermove', e => show(e, el.dataset.tip));
  el.addEventListener('pointerleave', hide);
});
</script>
"""


def verdicts(towns):
    """The harness's three judgements, recounted from the CSV."""
    died = over = crashed = 0
    for rows in towns.values():
        trace = [pop(r) for r in rows]
        # The CSV rounds each of three ages to hundredths: a town on the floor
        # can read 2.99 without having gone below it.
        if any(p < min(3.0, trace[0]) - 0.02 for p in trace):
            died += 1
        if any(pop(r) > min(400.0, float(r["beds"]) + (14.0 if r.get("ruined") == "1" else 8.0))
               * 1.1 + 2.0 for r in rows):
            over += 1
        drops, y = 0, 30
        while y + 10 < len(trace):
            if trace[y + 10] < trace[y] * 0.67 and trace[y] > 10.0:
                drops += 1
                y += 10
            else:
                y += 1
        if drops > 1:
            crashed += 1
    return len(towns), died, over, crashed


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "century.csv"
    dst = sys.argv[2] if len(sys.argv) > 2 else "chessboard.html"
    towns = load(src)
    data = summarise(towns)
    n, died, over, crashed = verdicts(towns)
    chips = [f'<span class="chip"><b>{n}</b> towns</span>',
             f'<span class="chip"><b>{died}</b> died out</span>',
             f'<span class="chip"><b>{over}</b> overfilled</span>',
             f'<span class="chip"><b>{crashed}</b> crashed twice</span>']
    page = (PAGE.replace("__CHIPS__", "".join(chips))
            .replace("__MULTIPLES__", multiples(data))
            .replace("__STAGES__", stacked(data, "stages", STAGES, "g",
                                           lambda v, s: f"{v:.0f} towns", "stage at the end"))
            .replace("__DEATHS__", stacked(data, "deaths", ["old age", "hunger", "beasts"], "d",
                                           lambda v, s: f"{s:.0f}%", "deaths by cause"))
            .replace("__YOUNG__", bars(data, lambda d: d["young_lost"], "%"))
            .replace("__GRANARY__", bars(data, lambda d: d["granary"], " years", 1))
            .replace("__TABLE__", table(data))
            .replace("__DATA__", json.dumps({k: {"label": v["label"], "series": v["series"]}
                                             for k, v in data.items()})))
    open(dst, "w").write(page)
    print("wrote %s" % dst)


if __name__ == "__main__":
    main()
