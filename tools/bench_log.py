#!/usr/bin/env python3
"""Append one bench run to docs/BENCH_LOG.md (rules: docs/BENCH_RULES.md).

Usage: bench_log.py key=value ... < data summary
Keys: name tool obj seeds secs why ran wall need base stop
"""
import sys, datetime, os

f = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
data = [l.strip() for l in sys.stdin.read().splitlines() if l.strip()]
seeds, ran = f.get("seeds", "").split(), f.get("ran", "").split()
lines = [f"\n## {datetime.datetime.now():%Y-%m-%d %H:%M} · {f.get('name', '?')} · {f.get('tool', 'bench')}",
         f"- Objective: {f.get('obj', '').strip()}"]
s = f"- Seeds: {' '.join(seeds)} × {f.get('secs', '?')} s"
if len(ran) != len(seeds): s += f", ran {' '.join(ran) or 'none'}"
if f.get("why"): s += f" (why: {f['why'].strip()})"
if f.get("wall"): s += f" · wall {f['wall']} s"
lines.append(s)
if f.get("need"): lines.append(f"- Needed data: {f['need']}")
if f.get("base"): lines.append(f"- Base: {f['base']}")
if f.get("stop"): lines.append(f"- Stopped: {f['stop']}")
if data: lines.append("- Data:\n" + "\n".join(f"  - {l}" for l in data))
lines.append("- Verdict: _fill in_")
path = os.path.join(os.path.dirname(__file__), "..", "docs", "BENCH_LOG.md")
with open(path, "a") as out:
    out.write("\n".join(lines) + "\n")
print("logged in docs/BENCH_LOG.md (fill in the Verdict)")
