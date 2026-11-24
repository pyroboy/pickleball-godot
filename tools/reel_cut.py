"""Cut the cinematic reel from tools/cine.gd's shot log (docs/REEL_TOOLS.md).
Usage: python3 tools/reel_cut.py <dir with match.avi + shots.jsonl> <frame offset> <out.mp4> [total frames]
Offset: movie frame index of cine.gd frame 0 (0 when the movie has one more frame than the last logged one).
Env: TRIM=shot=frames,... drops frames from a shot's end."""
import json, subprocess, sys, os
from itertools import groupby
d, off, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
TOTAL = int(sys.argv[4]) if len(sys.argv) > 4 else 450
L = [r for r in (json.loads(l) for l in open(os.path.join(d, "shots.jsonl"))) if "shot" in r]
order = ["A_establish", "C1_dink_dolly", "C2_dink_ots", "DE_lob_orbit", "F_bullet", "F_release", "G_chase", "H_counter", "I_crowd"]
runs = {}
for k, g in groupby(L, key=lambda r: r["shot"]):
    g = list(g)
    if k in order and k not in runs: runs[k] = (g[0]["f"], len(g))
trim = dict(x.split("=") for x in os.environ.get("TRIM", "").split(",") if x)  # name=frames to drop from the end
segs = []
for k in order:
    a, n = runs[k]
    n -= int(trim.get(k, 0))
    segs.append((k, a + off, n))
extra = sum(s[2] for s in segs) - TOTAL
if extra > 0:  # take it off the counter shot's tail
    i = [s[0] for s in segs].index("H_counter")
    segs[i] = (segs[i][0], segs[i][1], segs[i][2] - extra)
FPS = 30
parts, labels = [], []
for i, (name, a, n) in enumerate(segs):
    parts.append(f"[0:v]trim=start_frame={a}:end_frame={a+n},setpts=PTS-STARTPTS[v{i}]")
    parts.append(f"[0:a]atrim=start={a/FPS:.4f}:duration={n/FPS:.4f},asetpts=PTS-STARTPTS[a{i}]")
    labels.append(f"[v{i}][a{i}]")
    print(f"{name:14s} movie frames {a}..{a+n} ({n})")
total = sum(s[2] for s in segs)
title_in = (total - segs[-1][2] + 14) / FPS
parts.append("".join(labels) + f"concat=n={len(segs)}:v=1:a=1[vc][ac]")
parts.append("[vc]fade=in:st=0:d=0.13[vf]")
parts.append(f"[1:v]scale=930:-1:flags=neighbor,format=rgba,fade=in:st=0:d=0.25:alpha=1,setpts=PTS+{title_in:.3f}/TB[logo]")
parts.append(f"[vf][logo]overlay=x=(W-w)/2:y=330:enable='gte(t,{title_in:.3f})'[vo]")
parts.append(f"[ac]afade=in:st=0:d=0.4,afade=out:st={total/FPS-0.6:.3f}:d=0.6[ao]")
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # project root
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(d, "match.avi"),
    "-loop", "1", "-i", os.path.join(here, "assets/branding/title-logo.png"),
    "-filter_complex", ";".join(parts), "-map", "[vo]", "-map", "[ao]", "-t", f"{total/FPS:.3f}",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", "-preset", "slow", "-r", str(FPS),
    "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out], check=True)
print("->", out, total, "frames", total / FPS, "s")
