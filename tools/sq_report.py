#!/usr/bin/env python3
"""Shot-quality report (docs/SHOT_QUALITY_PLAN.md) from a perf log.
Usage: python3 tools/sq_report.py logs/bench_<name>.perf.jsonl [...]
Mishits: score spread, large mishits per contact and by cause, which part caused them.
Flights: grade and net clearance per shot type. Endings: the stamp lines of each point."""
import json, sys, collections, statistics as st

def med(v): return round(st.median(v), 2) if v else None

for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path) if '"kind":"note"' in l]
    ex = [r["data"] for r in rows if r["note"] == "execution" and not r["data"].get("serve")]
    fl = [r["data"] for r in rows if r["note"] == "flight" and not r["data"].get("serve")]
    print(f"== {path}")
    for who, sel in (("AI", [e for e in ex if e["ai"]]), ("human", [e for e in ex if not e["ai"]])):
        if not sel: continue
        big = [e for e in sel if e.get("large_miss")]
        sc = sorted(e.get("mishit", 0.0) for e in sel)
        words = collections.Counter(e.get("timing_word", "") for e in sel)
        print(f"  {who}: {len(sel)} contacts | large mishits {len(big)} ({100 * len(big) / len(sel):.1f}%) by cause {dict(collections.Counter(e.get('miss_cause', '') for e in big))}")
        print(f"    score median {med(sc)}, p90 {sc[int(len(sc) * 0.9)]:.2f} | timing words {dict(words)}")
        parts = [e.get("parts") or [0, 0, 0, 0] for e in sel]
        print("    part over 0.2 on: timing %d, not set %d, risk %d, stamina %d | balance median %s, p90 %.2f" % (
            sum(p[0] > 0.2 for p in parts), sum(p[1] > 0.2 for p in parts), sum(p[2] > 0.2 for p in parts), sum(p[3] > 0.2 for p in parts),
            med([e.get("balance", 0.0) for e in sel]), sorted(e.get("balance", 0.0) for e in sel)[int(len(sel) * 0.9)]))
    by = collections.defaultdict(list)
    for d in fl: by[d["tactic"]].append(d)
    for t, v in sorted(by.items(), key=lambda kv: -len(kv[1])):
        g = collections.Counter(x["grade"] for x in v)
        print(f"  {t:<9} {len(v):>4} | LOW {g['LOW']:>3} LOOSE {g['LOOSE']:>3} HIGH {g['HIGH']:>3} LOB {g['LOB']:>3} NET {g['NET']:>3} | clearance median {med([x['clearance'] for x in v])} m, apex past net {med([x['apex_past'] for x in v])} m")
    ends = [r["data"] for r in rows if r["note"] == "point_ending"]
    print("  endings:", dict(collections.Counter((e.get("where", ""), e.get("why", "")) for e in ends)))
