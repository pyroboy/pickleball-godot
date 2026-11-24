#!/usr/bin/env python3
"""Set pose values in data/postures or data/base_poses .tres files without the editor.
Usage: python3 tools/pose_set.py s00 windup.body_yaw_deg=32 contact.crouch_amount=0.2 \
           finish.weight_shift=0.85 contact.charge_paddle_offset.y=-0.45
  key:   s<id> stroke posture, b<id> body pose
  stage: windup (windup_body keyframe), finish (follow_through_body keyframe), contact (main pose),
         drop (drop_body keyframe, only on strokes that have one; its paddle is contact.drop_paddle_offset
         and contact.drop_paddle_rotation_deg, its time contact.drop_time)
  A trailing .x/.y/.z sets one component of a Vector3. Without = prints current values for stage(s)."""
import glob, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "pose_studio"))
import tres_edit  # noqa: E402  (shared .tres text edits; also used by the Pose Studio server)


def pose_file(key):
    folder = "data/base_poses" if key[0] == "b" else "data/postures"
    hits = glob.glob(f"{folder}/{int(key[1:]):02d}_*.tres")
    if len(hits) != 1:
        sys.exit(f"no single pose file for {key}: {hits}")
    return hits[0]


def section(text, stage):
    """(start, end, is_dict) of the text block holding this stage's values."""
    try:
        return tres_edit.section(text, stage)
    except tres_edit.TresEditError as e:
        sys.exit(str(e))


def set_value(text, stage, field, value):
    try:
        return tres_edit.set_value(text, stage, field, value)
    except tres_edit.TresEditError as e:
        sys.exit(str(e))


def show(text, stage):
    i, j, _ = section(text, stage)
    print(f"--- {stage}")
    print(text[i:j].strip())


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = pose_file(sys.argv[1])
    text = open(path).read()
    edits = sys.argv[2:]
    if not edits:
        for st in ("windup", "drop", "contact", "finish"):
            try:
                show(text, st)
            except SystemExit:
                pass
        return
    for e in edits:
        lhs, value = e.split("=", 1)
        if "=" in value or (" " in value and not value.startswith("Vector3(")):
            sys.exit(f"bad value for {lhs!r}: {value!r} (one field=value per argument)")
        stage, field = lhs.split(".", 1)
        text, old = set_value(text, stage, field, value)
        print(f"{path}: {stage}.{field} {old} -> {value}")
    open(path, "w").write(text)


if __name__ == "__main__":
    main()
