#!/usr/bin/env python3
"""Compare two pose traces (from --pose-trace) tick by tick.

Usage: python3 tools/pose_diff.py baseline.jsonl new.jsonl [tolerance_mm=1.0]
Prints the first tick where any joint moved more than the tolerance, and the
max / p99 deviation per joint up to that point. Exit code 1 if it diverged.
"""
import json, sys, math, gzip
from collections import defaultdict

a_path, b_path = sys.argv[1], sys.argv[2]
tol = float(sys.argv[3]) / 1000.0 if len(sys.argv) > 3 else 0.001
opn = lambda p: gzip.open(p, "rt") if p.endswith(".gz") else open(p)
resolve = lambda p: p if p.endswith(".gz") or not __import__("os").path.exists(p + ".gz") else p + ".gz"
A = [json.loads(l) for l in opn(resolve(a_path))]
B = [json.loads(l) for l in opn(resolve(b_path))]
n = min(len(A), len(B))
dev = defaultdict(list)
first = None
for i in range(n):
    a, b = A[i], B[i]
    for key in a:
        if key == "tick" or key not in b or not isinstance(a[key], (dict, list)) or (isinstance(a[key], list) and key != "ball"): continue
        if key == "ball":
            pairs = {"ball": (a[key], b[key])}
        else:
            pairs = {f"{key}.{j}": (a[key][j], b[key].get(j)) for j in a[key] if b[key].get(j) is not None}
        for name, (p, q) in pairs.items():
            d = math.dist(p, q)
            dev[name].append(d)
            if d > tol and first is None:
                first = (i, name, d)
    if first: break
print(f"compared {i + 1} of {n} ticks (baseline {len(A)}, new {len(B)})")
worst = sorted(((max(v), sorted(v)[int(len(v) * 0.99)], k) for k, v in dev.items()), reverse=True)[:6]
for mx, p99, k in worst:
    print(f"  {k:28s} max {mx * 1000:8.3f} mm   p99 {p99 * 1000:8.3f} mm")
if first:
    print(f"DIVERGED at tick index {first[0]}: {first[1]} moved {first[2] * 1000:.2f} mm (tol {tol * 1000:.2f} mm)")
    sys.exit(1)
print(f"IDENTICAL within {tol * 1000:.2f} mm")
