#!/usr/bin/env python3
"""Summarise logs/perf.jsonl from a play session in ~20 lines.

Usage: python3 tools/perf_report.py [--short | --budget | --row] [path/to/perf.jsonl]
  --short:  ~6 lines (used by tools/bench.sh) to keep output small.
  --budget: only the budget lines of docs/PERFORMANCE_PLAN.md (bench summary, phone check).
  --row:    one row for the plan's Log table (tools/phone_perf.sh; STEP=, BUILD= env fill it in).
"""
import json, sys, os, statistics
from collections import defaultdict

FLAGS = {"--short", "--budget", "--row"}
SHORT = "--short" in sys.argv
BUDGET_ONLY = "--budget" in sys.argv
ROW = "--row" in sys.argv
args = [a for a in sys.argv[1:] if a not in FLAGS]
path = args[0] if args else os.path.join(os.path.dirname(__file__), "..", "logs", "perf.jsonl")
rows, bad = [], 0
for l in open(path, errors="replace"):
    if not l.strip(): continue
    try: rows.append(json.loads(l))
    except ValueError: bad += 1   # a cut-off last line (app killed mid-write): skip it
if bad: print(f"(skipped {bad} unreadable line{'s' if bad > 1 else ''})", file=sys.stderr)
meta = next((r for r in rows if r["kind"] == "meta"), {})
secs = [r for r in rows if r["kind"] == "sec"]
spikes = [r for r in rows if r["kind"] == "spike"]
if not secs:
    sys.exit("no data yet")

def pct(vals, p):
    vals = sorted(vals)
    return vals[min(len(vals) - 1, int(len(vals) * p))]

fps = [r["fps"] for r in secs]

# ---- budgets (docs/PERFORMANCE_PLAN.md "Frame budget"): phone, rallies, after minute 3 ----
BUDGET_TICK, BUDGET_PROC, HITCH_MS, SLOW_MS = 6.0, 7.0, 50.0, 21.0
OUTER = lambda k: k.endswith(".physics") or k.startswith("proc.") or k == "contact.authority"

def mean(v): return sum(v) / len(v) if v else 0.0

def uncapped(r, caps):
    """True when this second ran uncapped (60 fps wanted), so slow frames mean missed slots."""
    if "max_fps" in r: return r["max_fps"] == 0
    cap = 60   # older logs: follow Adaptive's notes
    for t, c in caps:
        if t <= r["t"]: cap = c
    return cap == 60

def tick_ms(r):
    """Scoped ms per physics tick this second (the serial tick cost)."""
    sc = r["scopes"]
    ticks = sc.get("game.physics", [0, 0, 0])
    n = ticks[2] * r["fps"] if len(ticks) > 2 else 0
    if n <= 0: return None
    return sum(v[0] for k, v in sc.items() if k.endswith(".physics")) * r["fps"] / n

def budget_lines():
    out = []
    caps = [(r["t"], r["data"].get("fps", 60)) for r in rows if r["kind"] == "note" and r.get("note") == "adaptive_fps"]
    play = [r for r in secs if r["state"] == "PLAYING"]
    tag = "rallies"
    if not play: play, tag = secs, "all seconds, no rallies"
    hot = [r for r in play if r["t"] >= 180] or play
    if len(hot) < len(play): tag += " after minute 3"
    ph = [r["phys_ms"] for r in hot]; pc = [r["cpu_ms"] for r in hot]
    ok = lambda v, b: "OK" if v <= b else "OVER"
    out.append(f"Worst tick each second ({tag}): mean {mean(ph):.1f} / p90 {pct(ph, .9):.1f} ms vs budget {BUDGET_TICK:.0f} ms  {ok(mean(ph), BUDGET_TICK)}")
    out.append(f"Worst process+draw each second ({tag}): mean {mean(pc):.1f} / p90 {pct(pc, .9):.1f} ms vs budget {BUDGET_PROC:.0f} ms  {ok(mean(pc), BUDGET_PROC)}")
    tk = [t for t in (tick_ms(r) for r in play) if t is not None]
    if tk: out.append(f"Scoped tick cost ({tag.split(' after')[0]}): avg {mean(tk):.2f} ms per tick (budget average 3 ms)  {ok(mean(tk), 3.0)}")
    un = [r for r in secs if uncapped(r, caps)]
    frames = sum(r["fps"] for r in un)
    if any("slow" in r for r in un):
        slow = sum(r.get("slow", 0) for r in un); est = ""
    else:   # older logs: missed 60 fps slots from the frame count
        slow = sum(max(0, 60 - r["fps"]) for r in un); est = " (estimated from fps)"
    capped = len(secs) - len(un)
    out.append(f"Slow frames (>= {SLOW_MS:.0f} ms at 60): {100 * slow / max(frames, 1):.1f}%{est} | capped at 30 for {capped} of {len(secs)} s"
               + ("  OK" if frames and slow / frames < 0.02 and capped == 0 else ""))
    rally_hitches = [s for s in spikes if s["state"] == "PLAYING" and s["ms"] > HITCH_MS]
    mins = max(len(play), 1) / 60.0
    out.append(f"Hitches > {HITCH_MS:.0f} ms in rallies: {len(rally_hitches)} ({len(rally_hitches) / mins * 3:.0f} per 3 min of rally)"
               + (f", worst {max(s['ms'] for s in rally_hitches):.0f} ms" if rally_hitches else "  OK"))
    # Frames that carried a physics tick against the frames in between (uncapped rally seconds).
    tf = [r for r in secs if r["state"] == "PLAYING" and "tick_f" in r and r.get("max_fps", 0) == 0]
    if tf:
        tn = sum(r["tick_f"][0] for r in tf); fn = sum(r["free_f"][0] for r in tf)
        tm = sum(r["tick_f"][1] * r["tick_f"][0] for r in tf) / max(tn, 1); fm = sum(r["free_f"][1] * r["free_f"][0] for r in tf) / max(fn, 1)
        to = sum(r["tick_f"][3] for r in tf); fo = sum(r["free_f"][3] for r in tf)
        out.append(f"Frames with a physics tick (rallies at 60): mean {tm:.1f} ms, {100 * to / max(tn, 1):.0f}% over 17.5 ms | frames between: mean {fm:.1f} ms, {100 * fo / max(fn, 1):.0f}% over"
                   f" | engine: physics step {statistics.mean(r['eng_phys_avg'] for r in tf):.1f} ms, process {statistics.mean(r['eng_proc_avg'] for r in tf):.1f} ms")
    can = [(r["t"], r["canary_ms"]) for r in secs if "canary_ms" in r]
    if len(can) >= 10:
        first = [c for t, c in can if t < can[0][0] + 60]; last = [c for t, c in can if t > can[-1][0] - 60]
        a, b = statistics.median(first), statistics.median(last)
        out.append(f"Canary (fixed work): minute 1 {a:.3f} ms, last minute {b:.3f} ms ({100 * (b / a - 1):+.0f}%; budget +15%)  {ok(b / a, 1.15)}")
    else:
        out.append("Canary: not in this log")
    tg = [r for r in rows if r["kind"] == "toggles"]
    if tg:
        for r in tg:
            off = [k for k, v in r["toggles"].items() if not v]
            out.append(f"Toggles at {r['t']}s: " + ("all on" if not off else "off: " + ", ".join(off))
                       + f" | physics steps {r.get('max_physics_steps', '?')}, max_fps {r.get('max_fps', '?')}")
    else:
        out.append("Toggles: not in this log (older build)")
    return out

def script_ms_per_s(state="PLAYING"):
    rs = [r for r in secs if r["state"] == state] or secs
    return mean([sum(v[0] for k, v in r["scopes"].items() if OUTER(k)) * r["fps"] for r in rs])

if BUDGET_ONLY:
    print("\n".join(budget_lines())); sys.exit(0)
if ROW:
    import datetime
    caps = [(r["t"], r["data"].get("fps", 60)) for r in rows if r["kind"] == "note" and r.get("note") == "adaptive_fps"]
    un = [r for r in secs if uncapped(r, caps)]; frames = sum(r["fps"] for r in un)
    slow = sum(r.get("slow", max(0, 60 - r["fps"])) for r in un)
    play = [r for r in secs if r["state"] == "PLAYING"]
    hitches = [s for s in spikes if s["state"] == "PLAYING" and s["ms"] > HITCH_MS]
    per3 = len(hitches) / max(len(play), 1) * 180
    notes = [f"{len(secs) / 60:.1f} min", f"30 fps cap {len(secs) - len(un)} s"]
    can = [r["canary_ms"] for r in secs if "canary_ms" in r]
    if len(can) >= 120: notes.append(f"canary {statistics.median(can[:60]):.3f}->{statistics.median(can[-60:]):.3f} ms")
    tg = [r for r in rows if r["kind"] == "toggles"]
    if tg:
        off = [k for k, v in tg[-1]["toggles"].items() if not v]
        notes.append("toggles all on" if not off else "off: " + ", ".join(off))
    print(f"| {datetime.date.today()} | {os.environ.get('STEP', '?')} | {os.environ.get('BUILD', '?')} | "
          f"{100 * slow / max(frames, 1):.0f}% at 60 | {per3:.0f} | {script_ms_per_s():.0f} | {'; '.join(notes)} |")
    sys.exit(0)
def gameplay_line():
    ev = [r for r in rows if r["kind"] == "event"]
    ends = [r["data"] for r in ev if r["event"] == "rally_end"]
    # A serve that goes straight from SERVING to POINT_SCORED faulted at the hit: it has no
    # rally_end, so the points count alone hides it (2026-11-25: 11 of 17 serves, unnoticed).
    serves = [r["data"]["to"] for r in ev if r["event"] == "state" and r["data"]["from"] == "SERVING"]
    serve_faults = sum(1 for to in serves if to == "POINT_SCORED")
    if not ends and not serve_faults: return None
    span = defaultdict(list); last = None
    for r in ev:
        if r["event"] != "state": continue
        t = r["data"]["tick"] / float(meta.get("physics_hz", 30))   # game time, not wall time
        if last: span[last[0]].append(t - last[1])
        last = (r["data"]["to"], t)
    reasons = defaultdict(int)
    for e in ends: reasons[e["reason"]] += 1
    avg = lambda k: sum(span[k]) / len(span[k]) if span[k] else 0
    return (f"Points {len(ends)} (" + ", ".join(f"{k.lower()} {n}" for k, n in sorted(reasons.items(), key=lambda kv: -kv[1])) +
            f") | rally {avg('PLAYING'):.1f}s, between {avg('POINT_SCORED'):.1f}s, serve wait {avg('WAITING'):.1f}s"
            f" | serves {len(serves)}, faulted at the hit {serve_faults}")

if SHORT:
    g = gameplay_line()
    if g: print(g)
    tot = defaultdict(float)
    for r in secs:
        for k, v in r["scopes"].items(): tot[k] += v[0]
    # Top-level = one node's whole _process/_physics_process; everything else is
    # nested inside one of them, so the two lists must not be added together.
    outer = lambda k: k.endswith(".physics") or k.startswith("proc.") or k == "contact.authority"
    by = lambda keep: sorted((k for k in tot if keep(k) and not k.startswith("render.")), key=tot.get, reverse=True)
    print("Systems ms/frame: " + ", ".join(f"{k} {tot[k]/len(secs):.2f}" for k in by(outer)[:4]) +
          " | inside them: " + ", ".join(f"{k} {tot[k]/len(secs):.2f}" for k in by(lambda k: not outer(k))[:3]))
    cause = defaultdict(int)
    for sp in spikes:   # deepest-named non-container scope that took the most time
        inner = {k: v for k, v in sp["top"].items() if not (k.endswith(".physics") or k.startswith("proc."))} or sp["top"]
        cause[(sp["state"], max(inner, key=lambda k: inner[k][0]) if inner else "?")] += 1
    print(f"Spikes >= {meta.get('spike_ms')}ms: {len(spikes)}" + (f", worst {max(s['ms'] for s in spikes)}ms; mostly " +
          ", ".join(f"{k} in {st} x{n}" for (st, k), n in sorted(cause.items(), key=lambda kv: -kv[1])[:2]) if spikes else ""))
    jit = defaultdict(int); frames = defaultdict(int)
    for r in secs:
        for st, n in r.get("state_frames", {r["state"]: r["fps"]}).items(): frames[st] += n
        for k, n in r.get("jitter", {}).items():
            parts = k.split(":"); st = parts[3] if len(parts) > 3 else r["state"]
            jit[(st, ":".join(parts[:3]))] += n
    worst = sorted(jit.items(), key=lambda kv: -kv[1] / max(frames[kv[0][0]], 1))[:3]
    if worst: print("Jitter /1k frames: " + ", ".join(f"{k} {st} {1000*n/max(frames[st],1):.0f}" for (st, k), n in worst))
    sys.exit(0)
print(f"{meta.get('os')} {meta.get('model')} | {meta.get('renderer')} | {len(secs)}s played")
print(f"FPS   median {pct(fps,.5)}  worst-5% {pct(fps,.05)}  min {min(fps)}")
g = gameplay_line()
if g: print(g)
print(f"Frame p95 {pct([r['p95_ms'] for r in secs],.5):.1f}ms typical, worst frame {max(r['max_ms'] for r in secs):.1f}ms")
print(f"Scene draws {pct([r['draws'] for r in secs],.5)}  nodes {max(r['nodes'] for r in secs)}")
by_state_ms = defaultdict(list)
for r in secs: by_state_ms[r["state"]].append(r["avg_ms"])
print("Avg frame ms by state:", ", ".join(f"{s} {pct(v,.5)}" for s, v in sorted(by_state_ms.items())))

# FPS by game state
by_state = defaultdict(list)
for r in secs: by_state[r["state"]].append(r)
print("By state (median fps / spikes):", ", ".join(
    f"{s} {pct([r['fps'] for r in rs],.5)}/{sum(r['spikes'] for r in rs)}" for s, rs in sorted(by_state.items())))

# Systems: avg ms per frame across the session, worst single frame
tot, worst, calls, n = defaultdict(float), defaultdict(float), defaultdict(float), len(secs)
for r in secs:
    for k, v in r["scopes"].items():
        tot[k] += v[0]; worst[k] = max(worst[k], v[1])
        if len(v) > 2: calls[k] += v[2]
print("Systems            avg ms/frame  worst ms  calls/frame")
for k in sorted(tot, key=tot.get, reverse=True)[:12]:
    print(f"  {k:22s} {tot[k]/n:6.2f}  {worst[k]:8.1f}  {calls[k]/n:6.1f}")

# Spikes: count and who was biggest in each
print(f"Spikes >= {meta.get('spike_ms')}ms: {len(spikes)}")
blame = defaultdict(int)
for s in spikes:
    top = {k: v for k, v in s["top"].items() if k != "player.physics"}  # container scope
    if top: blame[max(top, key=lambda k: top[k][0])] += 1
    else: blame["(untimed: render/GC/engine)"] += 1
for k, c in sorted(blame.items(), key=lambda kv: -kv[1])[:5]:
    print(f"  {c:4d}x  biggest = {k}")
for s in sorted(spikes, key=lambda s: -s["ms"])[:3]:
    print(f"  worst: t={s['t']}s {s['ms']}ms {s['state']} {s['top']}")

# ---- motion jitter (sec rows "jitter": {"obj:kind:zone": count}) ----
jit = defaultdict(int); state_frames = defaultdict(int)
for r in secs:
    for st, n in r.get("state_frames", {r["state"]: r["fps"]}).items(): state_frames[st] += n
    for k, n in r.get("jitter", {}).items():
        parts = k.split(":"); st = parts[3] if len(parts) > 3 else r["state"]
        jit[(st,) + tuple(parts[:3])] += n
bursts = [r for r in rows if r["kind"] == "jitter_burst"]
if jit or bursts:
    print("Motion jitter (per 1000 frames of that state; obj kind zone):")
    for (st, obj, kind, zone), n in sorted(jit.items(), key=lambda kv: -kv[1] / max(state_frames[kv[0][0]], 1))[:12]:
        print(f"  {1000 * n / max(state_frames[st], 1):6.1f}/1k  {n:5d}  {obj:5s} {kind:7s} {zone:7s} {st}")
    print(f"  bursts (3+ in 0.5 s, snapshot in log): {len(bursts)}" +
          "".join(f"\n    t={b['t']}s {b['obj']} {b['last_kind']} {b['zone']} {b['state']}" for b in bursts[:8]))

print("Budgets (docs/PERFORMANCE_PLAN.md):")
for l in budget_lines(): print("  " + l)
