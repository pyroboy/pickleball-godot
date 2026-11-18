#!/usr/bin/env python3
"""Build before/after sheets and a metrics table from tools/pose_review.sh output.
Usage: python3 tools/pose_review.py logs/pose_review"""
import glob, json, os, sys

STAGES = ["windup", "contact", "finish"]
# metric, label, format
ROWS = [
    ("feet_planted", "feet planted", "{}"),
    ("com_over_base", "CoG over base", "{}"),
    ("com_back_to_front", "CoG back->front (0..1)", "{:.2f}"),
    ("com_off_base_m", "CoG off base line m", "{:.2f}"),
    ("stance_width", "stance width m", "{:.2f}"),
    ("stance_depth", "stance depth m", "{:.2f}"),
    ("front_foot", "front foot", "{}"),
    ("hip_height", "hip height m", "{:.2f}"),
    ("hip_yaw", "hip turn deg", "{:.0f}"),
    ("shoulder_yaw", "shoulder turn deg", "{:.0f}"),
    ("separation", "shoulder-hip sep deg", "{:.0f}"),
    ("trunk_lean_fwd", "trunk lean fwd deg", "{:.0f}"),
    ("trunk_lean_side", "trunk lean side deg", "{:.0f}"),
    ("left_knee_bend", "L knee bend deg", "{:.0f}"),
    ("right_knee_bend", "R knee bend deg", "{:.0f}"),
    ("right_elbow_bend", "R elbow bend deg", "{:.0f}"),
    ("paddle_from_shoulder", "paddle from shoulder m", "{:.2f}"),
]


def load(out):
    poses = {}
    for f in sorted(glob.glob(os.path.join(out, "raw", "*.json"))):
        d = json.load(open(f))
        poses.setdefault(d["key"], {})[d["tag"]] = d
    return poses


def sheet(out, key, tags, view):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return None
    cells = []
    for st in STAGES:
        row = [os.path.join(out, "raw", f"{key}_{t}_{st}_{view}.png") for t in tags]
        if all(os.path.exists(p) for p in row):
            cells.append((st, row))
    if not cells:
        return None
    w, h = Image.open(cells[0][1][0]).size
    img = Image.new("RGB", (w * len(tags), h * len(cells)), (15, 15, 20))
    dr = ImageDraw.Draw(img)
    for r, (st, row) in enumerate(cells):
        for c, p in enumerate(row):
            img.paste(Image.open(p).convert("RGB"), (c * w, r * h))
            dr.text((c * w + 8, r * h + 8), f"{tags[c].upper()} {st}", fill=(255, 255, 0))
    path = os.path.join(out, f"{key}_{view}.png")
    img.save(path)
    return path


def fmt(v, f):
    return "-" if v is None else f.format(v)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "logs/pose_review"
    for key, by_tag in load(out).items():
        tags = [t for t in ("before", "after", "now") if t in by_tag]
        name = by_tag[tags[-1]]["name"]
        print(f"\n=== {key} {name} ({' vs '.join(tags)}) ===")
        for view in ("front", "side"):
            p = sheet(out, key, tags, view)
            if p:
                print(f"sheet: {p}")
        stages = [s for s in STAGES if s in by_tag[tags[-1]]["stages"]] or list(by_tag[tags[-1]]["stages"])
        head = f"{'':24}" + "".join(f"{s[:7] + ' ' + t[:3]:>13}" for s in stages for t in tags)
        print(head)
        for m, label, f in ROWS:
            vals = []
            for s in stages:
                for t in tags:
                    vals.append(fmt(by_tag[t]["stages"].get(s, {}).get(m), f))
            print(f"{label:24}" + "".join(f"{v:>13}" for v in vals))
        for t in tags:
            sw = by_tag[t].get("swing")
            if sw:
                print(f"swing [{t}]: sharpest corner {sw['sharpest_corner_deg']:.0f} deg at t={sw['corner_at']:.2f}, "
                      f"elbow snap {sw['max_elbow_bend_step_deg']:.0f} deg/step at t={sw['snap_at']:.2f}, "
                      f"elbow jump {sw['max_elbow_jump_m']:.2f} m, elbow-torso clearance {sw['min_elbow_torso_clearance_m']:.2f} m, "
                      f"elbow inward {sw.get('elbow_inward_steps', 0)}/41 steps, forearm roll step {sw.get('max_forearm_roll_step_deg', 0):.0f} deg, "
                      f"elbow UP at steps {sw.get('elbow_up_steps', [])} (traced from t={sw.get('traced_from', 0)})")
            path = by_tag[t].get("path")
            if path:
                print(f"paddle path [{t}]: drop below contact {path['drop_below_contact']:.2f} m "
                      f"(lowest at t={path['lowest_at']:.2f}), rise to finish {path['rise_to_finish']:.2f} m")


if __name__ == "__main__":
    main()
