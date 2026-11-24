#!/usr/bin/env python3
"""Bench pre-check (docs/BENCH_RULES.md): are the datapoints recorded, and how many seeds?

Usage: python3 tools/bench_plan.py <note> [<note> ...] [--rate P --detect D] [--secs 120]
  <note>          perf note the objective needs (ai_launch, team_claim, point_ending ...)
  --rate P        today's rate of the thing measured, per event of the FIRST note (0..1)
  --detect D      smallest change in that rate that would alter the decision (0..1)
For each note: is it recorded by a script, and how many per seed in past runs (logs/).
With --rate/--detect: events needed per side (16 p (1-p) / d^2), as seeds and wall time.
Exit code 2 when a note is recorded nowhere: add it before benching.
"""
import argparse, glob, math, os, subprocess, statistics

ap = argparse.ArgumentParser()
ap.add_argument("notes", nargs="+"); ap.add_argument("--rate", type=float); ap.add_argument("--detect", type=float)
ap.add_argument("--secs", type=int, default=120)
a = ap.parse_args()
os.chdir(os.path.join(os.path.dirname(__file__), ".."))
runs = sorted(glob.glob("logs/bench_*_s*.perf.jsonl"), key=os.path.getmtime)[-8:]
missing = False; per_seed = {}
for n in a.notes:
    key = f'"{n}"'
    hit = subprocess.run(["grep", "-rlF", key, "scripts"], capture_output=True, text=True).stdout.split()
    counts = [c for c in (sum(1 for l in open(r) if key in l) for r in runs)]
    if not hit:
        missing = True; print(f"MISSING  {n}: no script records it. Add the note before benching."); continue
    if counts and max(counts) > 0:
        per_seed[n] = statistics.median(counts)
        print(f"ok       {n}: {min(counts)}-{max(counts)} per seed, median {per_seed[n]:.0f} (last {len(counts)} seed runs; lengths may differ) | {hit[0]}")
    else:
        print(f"ok       {n}: recorded by {hit[0]}, but 0 in the last {len(counts)} seed runs (new, or rare: check with one 20 s run)")
if a.rate is not None and a.detect:
    need = math.ceil(16 * a.rate * (1 - a.rate) / a.detect ** 2)
    n0 = a.notes[0]; ev = per_seed.get(n0)
    print(f"rate {a.rate:.2f}, detect ±{a.detect:.2f}: about {need} '{n0}' events per side")
    if ev:
        seeds = math.ceil(need / ev)
        print(f"  = {seeds} seed(s) per side at ~{ev:.0f} per seed, ~{seeds * a.secs / 4 / 60:.1f} min per side"
              + ("  -> too many: denser datapoint, forced situation, or larger --detect" if seeds > 6 else ""))
raise SystemExit(2 if missing else 0)
