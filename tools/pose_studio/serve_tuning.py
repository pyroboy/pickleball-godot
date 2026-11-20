#!/usr/bin/env python3
"""Write Pose Studio serve edits into data/serve_tuning.json (the packaged serve tuning that
MobileServePoseStore._apply_tuning lays over the code-built serve keys).

Usage: python3 tools/pose_studio/serve_tuning.py apply --style N --changes FILE [--json]
FILE: {"key": "v00", "changes": [{"stage": "windup"|"contact"|"finish", "field": f, "text": godot_text}]}
(the studio's diff rows: text is the Godot value text, e.g. "0.3", "Vector3(0.1, 0, -0.2)").

Each changed field becomes a "set" value in its stage (and leaves "add" for that field, which
would otherwise be added on top). charge_* fields go to "windup", ft_* to "finish" (the store
puts them on the contact definition either way). Rows marked "removed" are skipped (the tuning
cannot remove a code-built key). One JSON object is printed with --json.
"""
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TUNING = os.path.join(ROOT, "data", "serve_tuning.json")
STYLES = 7

def parse_godot(text):
    """Godot var_to_str text -> JSON value (Vector3 / Vector2 -> list)."""
    t = text.strip()
    m = re.fullmatch(r"Vector([23])\((.*)\)", t)
    if m:
        return [float(x) for x in m.group(2).split(",")]
    if t in ("true", "false"):
        return t == "true"
    if len(t) >= 2 and t[0] == '"' and t[-1] == '"':
        return t[1:-1]
    try:
        return int(t)
    except ValueError:
        return float(t)

def stage_for(row):
    f = row["field"]
    if f.startswith("charge_"):
        return "windup"
    if f.startswith("ft_"):
        return "finish"
    return row["stage"]

def apply(data, style, rows):
    entry = data.setdefault(str(style), {})
    changed, skipped = [], []
    for row in rows:
        if row.get("removed") or row.get("text") is None:
            skipped.append(row["field"])
            continue
        stage = stage_for(row)
        if stage not in ("windup", "contact", "finish"):
            skipped.append(row["field"])
            continue
        value = parse_godot(row["text"])
        st = entry.setdefault(stage, {})
        st.setdefault("set", {})[row["field"]] = value
        add = st.get("add")
        if isinstance(add, dict) and row["field"] in add:
            del add[row["field"]]
            if not add:
                del st["add"]
        changed.append({"stage": stage, "field": row["field"], "value": value})
    return changed, skipped

def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    def out(obj, code=0):
        print(json.dumps(obj) if as_json else obj)
        return code
    if len(args) < 1 or args[0] != "apply" or "--style" not in args or "--changes" not in args:
        return out({"ok": False, "error": __doc__.strip().splitlines()[2]}, 2)
    style = int(args[args.index("--style") + 1])
    if not 0 <= style < STYLES:
        return out({"ok": False, "error": "style must be 0..%d" % (STYLES - 1)}, 2)
    with open(args[args.index("--changes") + 1]) as f:
        rows = json.load(f).get("changes", [])
    with open(TUNING) as f:
        data = json.load(f)
    changed, skipped = apply(data, style, rows)
    if changed:
        tmp = TUNING + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=1)
            f.write("\n")
        os.replace(tmp, TUNING)
    return out({"ok": True, "style": style, "changed": len(changed), "fields": changed, "skipped": skipped,
                "file": os.path.relpath(TUNING, ROOT)})

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
