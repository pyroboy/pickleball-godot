"""Minimal text edits to pose .tres files (data/postures, data/base_poses).

Shared by tools/pose_set.py and tools/pose_notes.py (store.py) for the Desktop Pose Studio. Never reformats a file:
only the value text of the edited fields changes; a missing field is appended to
its block. Applying no change (or the same value text) leaves the text identical.

Stages map to file sections:
  contact -> the [resource] block (main pose, incl. charge_* / ft_* deltas)
  windup  -> the windup_body sub-resource `values = {...}` dictionary
  finish  -> the follow_through_body sub-resource dictionary
"""
import glob
import os
import re

STAGES = ("windup", "contact", "finish")
KEY_RE = re.compile(r"^[sba]\d\d$")
FIELD_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_KEYFRAME_PROP = {"windup": "windup_body", "finish": "follow_through_body"}
_NUM_RE = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|(?<![A-Za-z])(?:inf|nan)(?![A-Za-z])")


class TresEditError(ValueError):
    pass


def pose_folder(key):
    return {"b": "data/base_poses", "a": "data/ball_actions"}.get(key[0], "data/postures")


def pose_file(key, root="."):
    """Repo-relative path of the pose file for key (s00..s20, b00..b21, a00..a01 ball actions)."""
    if not isinstance(key, str) or not KEY_RE.match(key):
        raise TresEditError(f"bad pose key: {key!r}")
    folder = pose_folder(key)
    hits = sorted(glob.glob(os.path.join(root, folder, f"{int(key[1:]):02d}_*.tres")))
    if len(hits) != 1:
        raise TresEditError(f"no single pose file for {key}: {hits}")
    return os.path.join(folder, os.path.basename(hits[0]))


def section(text, stage):
    """(start, end, is_dict) of the text block holding this stage's values."""
    if stage == "contact":
        i = text.find("\n[resource]")
        if i < 0:
            raise TresEditError("no [resource] block")
        return i, len(text), False
    if stage not in _KEYFRAME_PROP:
        raise TresEditError(f"bad stage: {stage!r}")
    prop = _KEYFRAME_PROP[stage]
    m = re.search(rf'\n{prop} = SubResource\("([^"]+)"\)', text)
    if not m:
        raise TresEditError(f"{stage}: this pose has no {prop} keyframe")
    i = text.index(f'[sub_resource type="Resource" id="{m.group(1)}"]')
    j = text.find("\n[", i + 1)
    return i, (len(text) if j < 0 else j), True


def _pattern(field, is_dict):
    if is_dict:
        return rf'("{re.escape(field)}": )([^\n]*?)(,?\n)'
    return rf'(\n{re.escape(field)} = )([^\n]*)(\n|$)'


def get_value(text, stage, field):
    """Value text of stage.field, or None when the field is not in the file."""
    i, j, is_dict = section(text, stage)
    m = re.search(_pattern(field, is_dict), text[i:j])
    return m.group(2) if m else None


def set_value(text, stage, field, value):
    """Set stage.field to value text. A trailing .x/.y/.z sets one Vector3 component.
    Returns (new_text, old_value_text or "(unset)")."""
    comp = None
    if field[-2:] in (".x", ".y", ".z"):
        field, comp = field[:-2], "xyz".index(field[-1])
    i, j, is_dict = section(text, stage)
    block = text[i:j]
    m = re.search(_pattern(field, is_dict), block)
    if not m:
        if comp is not None:
            raise TresEditError(f"{stage}.{field} not set in this pose; set the full Vector3 instead")
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
            raise TresEditError(f"{stage}.{field} is not a Vector3: {old}")
        parts = [p.strip() for p in nums.group(1).split(",")]
        parts[comp] = value
        new = f"Vector3({', '.join(parts)})"
    block = block[:m.start(2)] + new + block[m.end(2):]
    return text[:i] + block + text[j:], old


def remove_value(text, stage, field):
    """Delete stage.field from the file (keyframe dictionary entry or main property line).
    Returns (new_text, old_value_text or None when the field was not there)."""
    i, j, is_dict = section(text, stage)
    block = text[i:j]
    m = re.search(_pattern(field, is_dict), block)
    if not m:
        return text, None
    old = m.group(2)
    if is_dict:
        start = block.rfind("\n", 0, m.start()) + 1
        end = m.end(3)
        if "," not in m.group(3):
            # Last entry: drop the comma that ended the previous entry (if there is one).
            prev = start - 1                     # the newline before this line
            if prev > 0 and block[prev - 1] == ",":
                block = block[:prev - 1] + block[prev:start] + block[end:]
                return text[:i] + block + text[j:], old
        block = block[:start] + block[end:]
    else:
        block = block[:m.start()] + block[m.end(2):]
    return text[:i] + block + text[j:], old


def same_value(a, b):
    """True when two value texts mean the same value (e.g. "-20" vs "-20.0",
    "Vector3(0,0,0)" vs "Vector3(0, 0, 0)")."""
    if a == b:
        return True
    if a is None or b is None or '"' in a or '"' in b:
        return False
    sa, sb = _NUM_RE.sub("#", a.replace(" ", "")), _NUM_RE.sub("#", b.replace(" ", ""))
    if sa != sb or "#" not in sa:
        return False
    na, nb = _NUM_RE.findall(a), _NUM_RE.findall(b)
    try:
        return len(na) == len(nb) and all(float(x) == float(y) for x, y in zip(na, nb))
    except ValueError:
        return False


def check_change(c):
    """Validate one {stage, field, text} change; returns (stage, field, text).
    {stage, field, text: null, removed: true} (link diff row for a keyframe key missing
    from the working copy) returns text None = delete the field."""
    if not isinstance(c, dict):
        raise TresEditError(f"change is not an object: {c!r}")
    stage, field, value = c.get("stage"), c.get("field"), c.get("text")
    if stage not in STAGES:
        raise TresEditError(f"bad stage: {stage!r}")
    if not isinstance(field, str) or not FIELD_RE.match(field):
        raise TresEditError(f"bad field: {field!r}")
    if field in ("script", "windup_body", "follow_through_body", "values"):
        raise TresEditError(f"{field} cannot be edited")
    if c.get("removed") is True and value is None:
        return stage, field, None
    # Packed*Array values (elbow paths) are one long line: 64 KB for them, 400 chars otherwise.
    limit = 65536 if isinstance(value, str) and value.startswith("Packed") else 400
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise TresEditError(f"bad value text for {stage}.{field}: {value!r}")
    if any(ch in value for ch in "\n\r\0") or value != value.strip():
        raise TresEditError(f"value text for {stage}.{field} must be one trimmed line")
    return stage, field, value


def apply_changes(text, changes):
    """Apply [{stage, field, text}] to the file text. Unchanged values are skipped.
    Returns (new_text, applied) with applied = [{stage, field, from, to}];
    from is None for a field that was added, to is None for a field that was removed."""
    checked = [check_change(c) for c in changes]   # validate all before editing
    applied = []
    for stage, field, value in checked:
        if value is None:
            text, old = remove_value(text, stage, field)
            if old is not None:
                applied.append({"stage": stage, "field": field, "from": old, "to": None})
            continue
        old = get_value(text, stage, field)
        if old is not None and same_value(old, value):
            continue
        text, _ = set_value(text, stage, field, value)
        applied.append({"stage": stage, "field": field, "from": old, "to": value})
    return text, applied


def parse_values(text):
    """{stage: {field: value_text}} for every single-line value in the pose file."""
    out = {}
    for stage in STAGES:
        try:
            i, j, is_dict = section(text, stage)
        except TresEditError:
            continue
        block = text[i:j]
        if is_dict:
            rx = re.compile(r'^"([A-Za-z_][A-Za-z0-9_]*)": ([^\n]*?),?$', re.M)
        else:
            rx = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*) = ([^\n]*)$", re.M)
        vals = {m.group(1): m.group(2) for m in rx.finditer(block)}
        if not is_dict:
            for k in ("script", "windup_body", "follow_through_body"):
                vals.pop(k, None)
        out[stage] = vals
    return out


def diff_values(text_a, text_b):
    """[{stage, field, a, b}] for every value that differs between two pose texts
    (a / b None when the field is missing on that side)."""
    va, vb = parse_values(text_a), parse_values(text_b)
    rows = []
    for stage in STAGES:
        a, b = va.get(stage, {}), vb.get(stage, {})
        for field in list(a) + [f for f in b if f not in a]:
            x, y = a.get(field), b.get(field)
            if not same_value(x, y):
                rows.append({"stage": stage, "field": field, "a": x, "b": y})
    return rows
