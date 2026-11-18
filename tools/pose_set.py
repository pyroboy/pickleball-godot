#!/usr/bin/env python3
"""Set pose values in data/postures or data/base_poses .tres files without the editor.
Usage: python3 tools/pose_set.py s00 windup.body_yaw_deg=32 contact.crouch_amount=0.2 \
           finish.weight_shift=0.85 contact.charge_paddle_offset.y=-0.45
  key:   s<id> stroke posture, b<id> body pose
  stage: windup (windup_body keyframe), finish (follow_through_body keyframe), contact (main pose)
  A trailing .x/.y/.z sets one component of a Vector3. Without = prints current values for stage(s)."""
import glob, re, sys


def pose_file(key):
    folder = "data/base_poses" if key[0] == "b" else "data/postures"
    hits = glob.glob(f"{folder}/{int(key[1:]):02d}_*.tres")
    if len(hits) != 1:
        sys.exit(f"no single pose file for {key}: {hits}")
    return hits[0]


def section(text, stage):
    """(start, end, is_dict) of the text block holding this stage's values."""
    if stage == "contact":
        i = text.index("\n[resource]")
        return i, len(text), False
    prop = {"windup": "windup_body", "finish": "follow_through_body"}[stage]
    m = re.search(rf'\n{prop} = SubResource\("([^"]+)"\)', text)
    if not m:
        sys.exit(f"{stage}: this pose has no {prop} keyframe")
    i = text.index(f'[sub_resource type="Resource" id="{m.group(1)}"]')
    j = text.find("\n[", i + 1)
    return i, (len(text) if j < 0 else j), True


def set_value(text, stage, field, value):
    comp = None
    if field[-2:] in (".x", ".y", ".z"):
        field, comp = field[:-2], "xyz".index(field[-1])
    i, j, is_dict = section(text, stage)
    block = text[i:j]
    pat = rf'("{re.escape(field)}": )([^\n]*?)(,?\n)' if is_dict else rf'(\n{re.escape(field)} = )([^\n]*)(\n|$)'
    m = re.search(pat, block)
    if not m:
        if comp is not None:
            sys.exit(f"{stage}.{field} not set in this pose; set the full Vector3 instead")
        # Add a missing field: dict entries before the closing brace, properties at the end.
        if is_dict:
            k = block.rindex("\n}")
            block = block[:k] + f',\n"{field}": {value}' + block[k:]
        else:
            block = block.rstrip("\n") + f"\n{field} = {value}\n"
        return text[:i] + block + text[j:], "(unset)"
    old = m.group(2)
    new = value
    if comp is not None:
        nums = re.match(r"Vector3\(([^)]*)\)", old)
        if not nums:
            sys.exit(f"{stage}.{field} is not a Vector3: {old}")
        parts = [p.strip() for p in nums.group(1).split(",")]
        parts[comp] = value
        new = f"Vector3({', '.join(parts)})"
    block = block[:m.start(2)] + new + block[m.end(2):]
    return text[:i] + block + text[j:], old


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
        for st in ("windup", "contact", "finish"):
            try:
                show(text, st)
            except SystemExit:
                pass
        return
    for e in edits:
        lhs, value = e.split("=", 1)
        stage, field = lhs.split(".", 1)
        text, old = set_value(text, stage, field, value)
        print(f"{path}: {stage}.{field} {old} -> {value}")
    open(path, "w").write(text)


if __name__ == "__main__":
    main()
