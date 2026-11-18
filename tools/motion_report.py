#!/usr/bin/env python3
"""Find jitter and slow movement in a frame log, and draw it as a graph.

Usage: python3 tools/motion_report.py logs/bench_<name>.frames.jsonl [out.html]
  (frame log: FRAME_LOG=1 tools/bench.sh <name>, or --frame-log=path on any run)

Reads the "drawn" positions (interpolated, what is on screen) per frame:
  jitter  - a moving object that stalls for a frame (30 Hz stepping), jumps
            (pop), or flips direction and back.
  slow    - a player who should be moving (intended speed > 0.5 m/s) but is
            drawn at under half that speed, or creeps (0.05-0.6 m/s) for 0.4 s+.
Writes a text summary and an HTML graph (default: next to the log).
"""
import json, math, sys, html
from collections import Counter, defaultdict

path = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else path.rsplit(".", 1)[0] + ".motion.html"
rows = [r for r in (json.loads(l) for l in open(path)) if "drawn" in r]
if not rows: sys.exit("no 'drawn' data: re-run with the current perf_monitor.gd")

# Bench runs use --fixed-fps 60: game time advances 1/60 s per frame whatever
# the wall clock says. Phone/desktop logs use the real frame time.
med_ms = sorted(r["ms"] for r in rows)[len(rows) // 2]
fixed = med_ms < 8.0
dts = [1 / 60 if fixed else max(r["ms"], 1.0) / 1000 for r in rows]
objs = sorted({k for r in rows for k in r["drawn"] if not k.startswith("v")})

MOVING = 0.3      # m/s: below this an object counts as standing
STALL = 0.25      # a frame moving < 25% of its neighbours' average
POP = 3.0         # a frame moving > 3x its neighbours' average
speed = {o: [0.0] * len(rows) for o in objs}
step = {o: [None] * len(rows) for o in objs}
for o in objs:
    for i in range(1, len(rows)):
        a, b = rows[i - 1]["drawn"].get(o), rows[i]["drawn"].get(o)
        if a and b:
            step[o][i] = [b[k] - a[k] for k in range(3)]
            speed[o][i] = math.dist(a, b) / dts[i]

events = []   # (frame index, object, kind)
for o in objs:
    s, d = speed[o], step[o]
    for i in range(2, len(rows) - 1):
        if d[i] is None or d[i - 1] is None or d[i + 1] is None: continue
        around = (s[i - 1] + s[i + 1]) / 2
        if around < MOVING: continue
        if s[i] < STALL * around: events.append((i, o, "stall"))
        elif s[i] > POP * around and s[i] > 1.0: events.append((i, o, "pop"))
        else:
            dot_prev = sum(d[i][k] * d[i - 1][k] for k in range(3))
            dot_next = sum(d[i][k] * d[i + 1][k] for k in range(3))
            if dot_prev < 0 and dot_next < 0: events.append((i, o, "reverse"))

slow = []     # (start, end, object, kind)
for o in [o for o in objs if o.startswith("p")]:
    want = [r["drawn"].get("v" + o[1:], 0.0) for r in rows]
    for kind, test in (("lag", lambda i: want[i] > 0.5 and speed[o][i] < 0.5 * want[i]),
                       ("creep", lambda i: 0.05 < speed[o][i] < 0.6)):
        i = 0
        while i < len(rows):
            if not test(i): i += 1; continue
            j = i
            while j < len(rows) and test(j): j += 1
            if sum(dts[i:j]) >= (0.4 if kind == "creep" else 0.2): slow.append((i, j, o, kind))
            i = j

t = [0.0]
for dt in dts[1:]: t.append(t[-1] + dt)
state_at = [r["state"] for r in rows]

# ---- text summary ----
print(f"{path}: {len(rows)} frames, {t[-1]:.0f} s {'(fixed 60 fps)' if fixed else ''}")
print("Jitter events by object / kind / state:")
for (o, k, st), n in Counter((o, k, state_at[i]) for i, o, k in events).most_common(12):
    print(f"  {n:5d}  {o:5s} {k:8s} {st}")
print("Slow segments:")
for (o, k, st), n in Counter((o, k, state_at[s0]) for s0, s1, o, k in slow).most_common(12):
    secs = sum(t[s1 - 1] - t[s0] for s0, s1, oo, kk in slow if (oo, kk, state_at[s0]) == (o, k, st))
    print(f"  {n:5d}  {o:5s} {k:6s} {st:13s} {secs:6.1f} s total")
if not events and not slow: print("  none")

# ---- HTML graph: one speed lane per object, events marked ----
STATE_COL = {"WAITING": "#e8eef7", "SERVING": "#f4ecd8", "PLAYING": "#e6f2e6", "POINT_SCORED": "#f3e3e8"}
KIND_COL = {"stall": "#d33", "pop": "#a0f", "reverse": "#f80", "lag": "#c60", "creep": "#06c"}
W, LANE, PAD = 1400, 90, 60
H = PAD + LANE * len(objs) + 30
X = lambda tt: PAD + (W - PAD - 10) * tt / max(t[-1], 1e-6)
svg = [f'<svg viewBox="0 0 {W} {H}" width="100%" font-family="system-ui" font-size="11">']
i = 0
while i < len(rows):      # state bands
    j = i
    while j < len(rows) and state_at[j] == state_at[i]: j += 1
    svg.append(f'<rect x="{X(t[i]):.1f}" y="20" width="{max(X(t[j-1]) - X(t[i]), 1):.1f}" height="{H-50}" fill="{STATE_COL.get(state_at[i], "#eee")}"/>')
    i = j
for lane, o in enumerate(objs):
    y0 = PAD + lane * LANE
    top = max(max(speed[o]), 1.0)
    cap = min(top, 25.0)
    Y = lambda v: y0 + LANE - 12 - (LANE - 24) * min(v, cap) / cap
    svg.append(f'<text x="4" y="{y0 + LANE/2:.0f}" font-weight="600">{o}</text>')
    svg.append(f'<text x="4" y="{y0 + LANE/2 + 13:.0f}" fill="#666">{cap:.0f} m/s</text>')
    svg.append(f'<line x1="{PAD}" x2="{W-10}" y1="{Y(0):.1f}" y2="{Y(0):.1f}" stroke="#bbb"/>')
    every = max(1, len(rows) // 4000)
    pts = " ".join(f"{X(t[k]):.1f},{Y(speed[o][k]):.1f}" for k in range(0, len(rows), every))
    svg.append(f'<polyline points="{pts}" fill="none" stroke="#333" stroke-width="0.7"/>')
    for s0, s1, oo, k in slow:
        if oo == o:
            svg.append(f'<rect x="{X(t[s0]):.1f}" y="{y0+4}" width="{max(X(t[s1-1]) - X(t[s0]), 2):.1f}" height="6" fill="{KIND_COL[k]}"><title>{k} {t[s1-1]-t[s0]:.2f}s at {t[s0]:.1f}s ({state_at[s0]})</title></rect>')
    for k_i, oo, k in events:
        if oo == o:
            svg.append(f'<circle cx="{X(t[k_i]):.1f}" cy="{Y(speed[o][k_i]):.1f}" r="2.5" fill="{KIND_COL[k]}"><title>{k} at {t[k_i]:.2f}s ({state_at[k_i]})</title></circle>')
for s in range(0, int(t[-1]) + 1, max(5, int(t[-1] // 20) // 5 * 5 or 5)):
    svg.append(f'<text x="{X(s):.1f}" y="{H-12}" text-anchor="middle" fill="#666">{s}s</text>')
svg.append("</svg>")
legend = " ".join(f'<span style="color:{c}">&#9679; {k}</span>' for k, c in KIND_COL.items())
legend += " &nbsp;|&nbsp; " + " ".join(f'<span style="background:{c};padding:0 6px">{k}</span>' for k, c in STATE_COL.items())
counts = Counter(k for _, _, k in events) + Counter(k for *_, k in slow)
summary = ", ".join(f"{k}: {n}" for k, n in counts.most_common()) or "nothing flagged"
open(out, "w").write(f"""<!doctype html><meta charset="utf-8"><title>Motion report</title>
<body style="margin:16px;font-family:system-ui;background:#fff;color:#222">
<h2 style="margin:0 0 4px">Motion: {html.escape(path.rsplit('/',1)[-1])}</h2>
<p style="margin:0 0 8px;color:#555">{len(rows)} frames, {t[-1]:.0f} s. Drawn speed per object (line).
Dots = jitter frames, bars = slow segments; hover for details. {summary}.</p>
<p style="margin:0 0 8px">{legend}</p>{''.join(svg)}</body>""")
print("graph:", out)
