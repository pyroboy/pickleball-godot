"""Bench tab data: reads existing logs/bench_*.perf.jsonl and .pose.jsonl.gz only.
Never starts a bench.

  python3 tools/pose_studio/bench.py [--json]                 every run
  python3 tools/pose_studio/bench.py [--json] --compare a b   two runs + pose_diff verdict
With --json: exactly one JSON object on stdout ({"ok": true, "runs": [...]} or
{"ok": true, "a", "b", "pose_diff"}; failures {"ok": false, "error"} with exit code 1).
 Reuses tools/perf_report.py (pct, scope grouping),
tools/shot_report.py (_cause) and tools/pose_diff.py (verdict).

Those tools are scripts with top-level code, so their functions are loaded by
compiling only their def statements (no script body runs), and pose_diff.py runs
as a subprocess on the two saved traces.
"""
import argparse
import ast
import os
import re
import subprocess
import sys
import threading
from collections import Counter, defaultdict
import json

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME_RE = re.compile(r"^[A-Za-z0-9_.-]{1,80}$")


def load_defs(path, names):
    """Function definitions from a script without running its top-level code."""
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), path)
    keep = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))
            or (isinstance(n, ast.FunctionDef) and n.name in names)]
    ns = {"__name__": "bench_defs"}
    exec(compile(ast.Module(body=keep, type_ignores=[]), path, "exec"), ns)
    missing = [n for n in names if n not in ns]
    if missing:
        raise ImportError(f"{path}: missing {missing}")
    return ns


_perf = load_defs(os.path.join(TOOLS, "perf_report.py"), ["pct"])
_shot = load_defs(os.path.join(TOOLS, "shot_report.py"), ["_cause"])
pct, cause_of = _perf["pct"], _shot["_cause"]


def _outer(k):   # same rule as perf_report.py --short: top-level scopes
    return k.endswith(".physics") or k.startswith("proc.") or k == "contact.authority"


class Bench:
    def __init__(self, root):
        self.logs = os.path.join(os.path.realpath(root), "logs")
        self._cache = {}
        self._lock = threading.Lock()

    def names(self):
        try:
            files = os.listdir(self.logs)
        except OSError:
            return []
        return sorted(f[len("bench_"):-len(".perf.jsonl")] for f in files
                      if f.startswith("bench_") and f.endswith(".perf.jsonl") and NAME_RE.match(f[6:-11]))

    def _path(self, name, ext):
        if not isinstance(name, str) or not NAME_RE.match(name) or name not in self.names():
            raise KeyError(f"no bench run {name!r}")
        return os.path.join(self.logs, f"bench_{name}{ext}")

    def summary(self, name):
        path = self._path(name, ".perf.jsonl")
        mt = os.stat(path).st_mtime_ns
        with self._lock:
            hit = self._cache.get(name)
            if hit and hit[0] == mt:
                return hit[1]
        s = summarize(path, name)
        s["pose_trace"] = os.path.exists(os.path.join(self.logs, f"bench_{name}.pose.jsonl.gz"))
        with self._lock:
            self._cache[name] = (mt, s)
        return s

    def runs(self):
        return [self.summary(n) for n in self.names()]

    def compare(self, a, b):
        sa, sb = self.summary(a), self.summary(b)
        verdict = {"verdict": "no pose traces", "text": ""}
        pa, pb = self._path(a, ".pose.jsonl.gz"), self._path(b, ".pose.jsonl.gz")
        if os.path.exists(pa) and os.path.exists(pb):
            r = subprocess.run([sys.executable, os.path.join(TOOLS, "pose_diff.py"), pa, pb],
                               capture_output=True, text=True, timeout=120)
            out = (r.stdout + r.stderr).strip()
            v = "IDENTICAL" if "IDENTICAL" in out else ("DIVERGED" if "DIVERGED" in out else "error")
            verdict = {"verdict": v, "text": out[-3000:]}
        return {"a": sa, "b": sb, "pose_diff": verdict}


def summarize(path, name):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    continue
    meta = next((r for r in rows if r.get("kind") == "meta"), {})
    secs = [r for r in rows if r.get("kind") == "sec"]
    spikes = [r for r in rows if r.get("kind") == "spike"]
    # Endings per 100 shots (shot_report.py logic)
    causes, shots, points, hit = Counter(), 0, 0, None
    reasons = Counter()
    for r in rows:
        if r.get("kind") != "event":
            continue
        if r.get("event") == "hit":
            hit = r["data"]
            shots += 1
        elif r.get("event") == "rally_end":
            causes[cause_of(r["data"]["reason"], hit)] += 1
            reasons[r["data"]["reason"]] += 1
            points += 1
            hit = None
    endings = [{"cause": c, "n": n, "per_100_shots": round(100.0 * n / max(shots, 1), 2)}
               for c, n in causes.most_common()]
    # Systems (perf_report.py --short grouping)
    tot = defaultdict(float)
    for r in secs:
        for k, v in (r.get("scopes") or {}).items():
            tot[k] += v[0]
    n = max(len(secs), 1)
    by = lambda keep: sorted((k for k in tot if keep(k) and not k.startswith("render.")), key=tot.get, reverse=True)
    systems = [{"name": k, "ms_per_frame": round(tot[k] / n, 3)} for k in by(_outer)[:6]]
    inner = [{"name": k, "ms_per_frame": round(tot[k] / n, 3)} for k in by(lambda k: not _outer(k))[:6]]
    # Spikes
    blame = Counter()
    for sp in spikes:
        top = sp.get("top") or {}
        inn = {k: v for k, v in top.items() if not (k.endswith(".physics") or k.startswith("proc."))} or top
        blame[(sp.get("state"), max(inn, key=lambda k: inn[k][0]) if inn else "?")] += 1
    # Jitter per 1000 frames of the state
    jit, frames = defaultdict(int), defaultdict(int)
    for r in secs:
        for st, c in (r.get("state_frames") or {r.get("state"): r.get("fps", 0)}).items():
            frames[st] += c
        for k, c in (r.get("jitter") or {}).items():
            parts = k.split(":")
            st = parts[3] if len(parts) > 3 else r.get("state")
            jit[(st, ":".join(parts[:3]))] += c
    jitter = [{"state": st, "what": k, "count": c, "per_1k_frames": round(1000.0 * c / max(frames[st], 1), 1)}
              for (st, k), c in sorted(jit.items(), key=lambda kv: -kv[1] / max(frames[kv[0][0]], 1))[:6]]
    fps = [r.get("fps", 0) for r in secs]
    return {
        "name": name, "file": os.path.relpath(path, os.path.dirname(os.path.dirname(path))),
        "mtime": int(os.stat(path).st_mtime),
        "seconds": len(secs), "renderer": meta.get("renderer"), "physics_hz": meta.get("physics_hz"),
        "fps_median": pct(fps, .5) if fps else None, "fps_worst_5": pct(fps, .05) if fps else None,
        "points": points, "shots": shots, "shots_per_point": round(shots / points, 2) if points else None,
        "reasons": dict(reasons.most_common()),
        "endings": endings, "endings_per_100_shots": round(100.0 * points / max(shots, 1), 2),
        "systems": systems, "inner_systems": inner,
        "spikes": {"count": len(spikes), "threshold_ms": meta.get("spike_ms"),
                   "worst_ms": max((s.get("ms", 0) for s in spikes), default=None),
                   "mostly": [{"state": st, "scope": k, "n": c} for (st, k), c in blame.most_common(3)]},
        "jitter": jitter,
    }


def _text_run(r):
    ends = ", ".join(f"{e['cause']} {e['per_100_shots']}" for e in r["endings"][:4])
    return (f"{r['name']:16s} {r['seconds']:5d}s fps {r['fps_median']} (worst5 {r['fps_worst_5']}) "
            f"points {r['points']} shots {r['shots']} ends/100 {r['endings_per_100_shots']} [{ends}]"
            f" spikes {r['spikes']['count']}{' trace' if r['pose_trace'] else ''}")


def main(argv=None):
    root = os.path.dirname(TOOLS)
    ap = argparse.ArgumentParser(description="Bench runs from existing logs (never starts a bench)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--compare", nargs=2, metavar=("A", "B"))
    ap.add_argument("--root", default=root, help=argparse.SUPPRESS)
    argv = list(sys.argv[1:] if argv is None else argv)
    want_json = "--json" in argv
    try:
        a = ap.parse_args(argv)
        b = Bench(a.root)
        if a.compare:
            data = b.compare(*a.compare)
            text = [_text_run(data["a"]), _text_run(data["b"]), f"pose_diff: {data['pose_diff']['verdict']}"]
        else:
            runs = b.runs()
            data = {"runs": runs}
            text = [_text_run(r) for r in runs] + [f"{len(runs)} runs"]
    except SystemExit as e:
        if not want_json or e.code in (0, None):
            raise
        print(json.dumps({"ok": False, "error": "bad arguments"}))
        return 1
    except Exception as e:  # noqa: BLE001
        msg = str(e.args[0]) if isinstance(e, KeyError) and e.args else (str(e) or e.__class__.__name__)
        if want_json:
            print(json.dumps({"ok": False, "error": msg}))
        else:
            print(f"error: {msg}", file=sys.stderr)
        return 1
    if want_json:
        print(json.dumps(dict({"ok": True}, **data), ensure_ascii=False))
    else:
        print("\n".join(text))
    return 0


if __name__ == "__main__":
    sys.exit(main())
