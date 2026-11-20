#!/usr/bin/env python3
"""Pose Studio notes, versions, ratings and saves (no Godot needed).

The one writer of pose_studio/: Claude runs it, and the Desktop Pose Studio (Godot) runs it
through OS.execute with --json. With --json every subcommand prints exactly one JSON object
on stdout: {"ok": true, ...} or {"ok": false, "error": "..."} with exit code 1.

  python3 tools/pose_notes.py list [--open] [--key s13]
  python3 tools/pose_notes.py show n12
  python3 tools/pose_notes.py reply n12 --text "..." [--change contact.crouch_amount=0.074:0.3 ...] \\
        --evidence "hip 0.78 -> 0.58 m" --version 4 [--status verified]
  python3 tools/pose_notes.py version s13 -m "lower hips at contact" [--note n12]
  python3 tools/pose_notes.py queue [--all]
  python3 tools/pose_notes.py ratings [s13]
  python3 tools/pose_notes.py save s13 --changes /path/changes.json -m "..." --author user|claude [--note n12]
  python3 tools/pose_notes.py note-add s13 --kind request|rule --text "..." [--stage contact --field f --time 0.5]
  python3 tools/pose_notes.py note-set n12 --status open|addressed|verified|reopened
  python3 tools/pose_notes.py rate s13 --stars 4 [--aspect body=2 ...] [--note n12 ...] [--comment C] \\
        --by user --source studio|phone
  python3 tools/pose_notes.py versions s13 | version-show s13 4 | version-diff s13 3 file
  python3 tools/pose_notes.py restore s13 3 | approve s13 4 [--off]
  python3 tools/pose_notes.py progress | changelog | init

Store folder: $POSE_STUDIO_ROOT if set, else <repo>/pose_studio. Same code for every caller
(tools/pose_studio/store.py: file lock, atomic writes, append-only ratings).
Claude never sets stars: `rate --by claude` is refused.
"""
import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pose_studio"))
import store as store_mod  # noqa: E402


class CliError(Exception):
    pass


class Parser(argparse.ArgumentParser):
    """argparse that raises instead of exiting, so --json can report usage errors as JSON."""

    def error(self, message):
        raise CliError(f"{self.prog}: {message}")


def short(s, n=90):
    s = " ".join(str(s or "").split())
    return s if len(s) <= n else s[:n - 1] + "~"


def parse_change(text):
    """stage.field=from:to -> change dict (from / to are value texts; Vector3 commas are fine)."""
    lhs, sep, rhs = text.partition("=")
    stage, dot, field = lhs.partition(".")
    frm, colon, to = rhs.partition(":")
    if not sep or not dot or not colon:
        raise CliError(f"bad --change {text!r}: use stage.field=from:to")
    return {"stage": stage, "field": field, "from": frm or None, "to": to or None}


def parse_aspect(text):
    k, sep, v = text.partition("=")
    if not sep or not v.strip().lstrip("-").isdigit():
        raise CliError(f"bad --aspect {text!r}: use body=2 (aspects {', '.join(store_mod.ASPECTS)})")
    return k, int(v)


def version_arg(v):
    """Version number or 'file' (the working copy on disk)."""
    return v if v in ("file", "work", "working") else store_mod.check_n(v)


def build_parser():
    ap = Parser(prog="pose_notes.py", description="Pose Studio notes / versions / ratings / saves")
    ap.add_argument("--root", default=os.environ.get("POSE_STUDIO_REPO", ROOT), help=argparse.SUPPRESS)
    ap.add_argument("--json", action="store_true", help="print one JSON object")
    sub = ap.add_subparsers(dest="cmd", required=True, parser_class=Parser)

    def add(name, **kw):
        p = sub.add_parser(name, **kw)
        p.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help="print one JSON object")
        return p

    p = add("list"); p.add_argument("--open", action="store_true"); p.add_argument("--key")
    p = add("show"); p.add_argument("id")
    p = add("reply"); p.add_argument("id"); p.add_argument("--text", required=True)
    p.add_argument("--change", action="append", default=[]); p.add_argument("--evidence", default="")
    p.add_argument("--version", type=int); p.add_argument("--status", choices=store_mod.NOTE_STATUS)
    p = add("version"); p.add_argument("key"); p.add_argument("-m", "--message", required=True)
    p.add_argument("--note", action="append", default=[])
    p = add("queue"); p.add_argument("--all", action="store_true", help="include 5-star poses with no open notes")
    p = add("ratings"); p.add_argument("key", nargs="?")
    p = add("save", help="apply {stage, field, text} changes to the pose file and record a version")
    p.add_argument("key"); p.add_argument("--changes", required=True, help="JSON file: list or {changes: [...]}")
    p.add_argument("-m", "--message", default=""); p.add_argument("--author", required=True)
    p.add_argument("--note", action="append", default=[])
    p = add("note-add"); p.add_argument("key"); p.add_argument("--kind", default="request", choices=store_mod.NOTE_KINDS)
    p.add_argument("--text", required=True); p.add_argument("--stage"); p.add_argument("--field")
    p.add_argument("--time", type=float)
    p.add_argument("--rule-flag"); p.add_argument("--rule-metric")
    p.add_argument("--rule-min", type=float); p.add_argument("--rule-max", type=float)
    p = add("note-set"); p.add_argument("id"); p.add_argument("--status", choices=store_mod.NOTE_STATUS)
    p.add_argument("--text")
    p = add("rate"); p.add_argument("key"); p.add_argument("--stars", type=int, required=True)
    p.add_argument("--aspect", action="append", default=[]); p.add_argument("--note", action="append", default=[])
    p.add_argument("--comment", default=""); p.add_argument("--by", required=True)
    p.add_argument("--source", default="studio")
    p = add("versions"); p.add_argument("key")
    p = add("version-show"); p.add_argument("key"); p.add_argument("n")
    p = add("version-diff"); p.add_argument("key"); p.add_argument("a"); p.add_argument("b", nargs="?", default="file")
    p = add("restore"); p.add_argument("key"); p.add_argument("n"); p.add_argument("--author", default="user")
    p = add("approve"); p.add_argument("key"); p.add_argument("n"); p.add_argument("--off", action="store_true")
    add("progress"); add("changelog"); add("init")
    return ap


def make_store(root):
    return store_mod.Store(root, studio_dir=os.environ.get("POSE_STUDIO_ROOT") or None)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    want_json = "--json" in argv
    try:
        a = build_parser().parse_args(argv)
        st = make_store(a.root)
        res = run(a, st)
    except Exception as e:  # noqa: BLE001  (one JSON object on every failure)
        msg = str(e) or e.__class__.__name__
        if want_json:
            print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
        else:
            print(f"error: {msg}", file=sys.stderr)
        return 1
    if want_json:
        print(json.dumps(dict({"ok": True}, **res["data"]), ensure_ascii=False))
    else:
        for line in res["text"]:
            print(line)
    return 0


def out(data, text):
    return {"data": data, "text": text if isinstance(text, list) else [text]}


def run(a, st):
    cmd = a.cmd
    if cmd == "list":
        notes = st.notes(store_mod.check_key(a.key) if a.key else None)
        if a.open:
            notes = [n for n in notes if n.get("status") in store_mod.OPEN_STATUS]
        lines = []
        for n in notes:
            pin = ".".join(x for x in (n.get("stage"), n.get("field")) if x) or "-"
            lines.append(f"{n['id']:>5} {n['pose']} {n['kind']:7s} {n['status']:9s} {pin:28s} {short(n['text'])}")
        return out({"notes": notes}, lines + [f"{len(notes)} notes"])
    if cmd == "show":
        n = st.find_note(a.id)
        return out({"note": n}, json.dumps(n, indent=1, ensure_ascii=False))
    if cmd == "reply":
        reply = {"author": "claude", "text": a.text, "changes": [parse_change(c) for c in a.change],
                 "evidence": a.evidence, "version": a.version}
        patch = {"reply": reply}
        if a.status:
            patch["status"] = a.status
        n = st.update_note(a.id, patch)
        return out({"note": n}, f"{n['id']} {n['pose']}: reply saved, status {n['status']}")
    if cmd == "version":
        key = store_mod.check_key(a.key)
        rec = st.add_version(key, "claude", a.message, a.note)
        flags = ", ".join(rec["flags"][:6]) + (" ..." if len(rec["flags"]) > 6 else "")
        return out({"record": rec, "version": rec["n"]},
                   f"{key} v{rec['n']:03d} recorded (score {rec['score']}, flags: {flags or 'none'})")
    if cmd == "queue":
        q = st.queue()
        shown, lines = [], []
        for e in q:
            if e["done"] and not a.all:
                continue
            shown.append(e)
            stars = (f"{e['stars']}*" if e["stars"] is not None else
                     f"stale {e['stale_stars']}* (v{e['rated_version']})" if e["group"] == "stale" else "unrated")
            ver = "-" if e["version"] is None else e["version"]
            lines.append(f"{e['key']} {e['group']:7s} {stars:16s} v{ver} score {e['score']}")
            for it in e["items"][:5]:
                tag = it["id"] if it["type"] == "note" else f"flag {it['id']}"
                lines.append(f"    {tag}: {short(it['text'], 80)}")
            if len(e["items"]) > 5:
                lines.append(f"    ... {len(e['items']) - 5} more")
        lines.append(f"{len(shown)} of {len(q)} poses in the queue")
        return out({"queue": shown, "total": len(q)}, lines)
    if cmd == "ratings":
        key = store_mod.check_key(a.key) if a.key else None
        rows = st.ratings(key)
        lines = []
        for r in rows:
            asp = " ".join(f"{k}{v}" for k, v in (r.get("aspects") or {}).items())
            lines.append(f"{r['time']} {r['pose']} v{r['version']} {r['stars']}* {asp} {short(r.get('comment'), 60)}")
        data = {"ratings": rows}
        if key:
            data["state"] = st.rating_state(key)
        else:
            data["progress"] = st.progress()
            for typ, p in data["progress"].items():
                lines.append(f"{typ}: {p['at_5']}/{p['total']} at 5 stars ({p['share_5']:.0%}, target "
                             f"{p['target_share_5']:.0%}), below 4: {p['below_4']}, unrated {p['unrated']}, stale {p['stale']}")
        lines.append(f"{len(rows)} ratings")
        return out(data, lines)
    if cmd == "save":
        key = store_mod.check_key(a.key)
        try:
            with open(a.changes, encoding="utf-8") as f:
                doc = json.load(f)
        except (OSError, ValueError) as e:
            raise CliError(f"cannot read --changes {a.changes!r}: {e}")
        if isinstance(doc, dict):
            if doc.get("key") not in (None, key):
                raise CliError(f"--changes is for {doc.get('key')!r}, not {key}")
            doc = doc.get("changes")
        r = st.save_changes(key, doc, a.author, a.message, a.note)
        if r["saved"]:
            text = f"{r['file']}: {len(r['changes'])} change(s), {r['changed_lines']} line(s), v{r['version']:03d}"
        else:
            text = f"{r['file']}: no change (file untouched)"
        return out(r, text)
    if cmd == "note-add":
        rec = {"kind": a.kind, "text": a.text, "stage": a.stage, "field": a.field, "time": a.time, "author": "user"}
        rule = {k: v for k, v in (("flag", a.rule_flag), ("metric", a.rule_metric),
                                  ("min", a.rule_min), ("max", a.rule_max)) if v is not None}
        if rule:
            if a.kind != "rule":
                raise CliError("--rule-* options need --kind rule")
            rec["rule"] = rule
        n = st.create_note(store_mod.check_key(a.key), rec)
        return out({"note": n}, f"{n['id']} {n['pose']}: {n['kind']} added")
    if cmd == "note-set":
        patch = {k: v for k, v in (("status", a.status), ("text", a.text)) if v is not None}
        if not patch:
            raise CliError("note-set needs --status or --text")
        n = st.update_note(a.id, patch)
        return out({"note": n}, f"{n['id']} {n['pose']}: status {n['status']}")
    if cmd == "rate":
        if a.by != "user":
            raise CliError("stars are given by the user only (Claude never rates)")
        aspects = dict(parse_aspect(x) for x in a.aspect)
        row = st.add_rating({"pose": store_mod.check_key(a.key), "stars": a.stars, "aspects": aspects,
                             "by": "user", "source": a.source, "notes": a.note, "comment": a.comment})
        return out({"rating": row}, f"{row['pose']} v{row['version']}: {row['stars']}* recorded")
    if cmd == "versions":
        key = store_mod.check_key(a.key)
        st.pose_rel(key)                     # the pose file must exist
        vs = st.versions(key)
        cur = st.current_version(key)
        lines = [f"v{r['n']:03d} {r.get('time')} {r.get('author'):6s} {'approved ' if r.get('approved') else ''}"
                 f"{short(r.get('message'), 70)}" for r in vs]
        matches = st.matches_current(key) if cur is not None else None
        lines.append(f"{len(vs)} versions; file {'matches' if matches else 'differs from'} current")
        return out({"key": key, "current": cur, "file_matches_current": matches, "versions": vs}, lines)
    if cmd == "version-show":
        key = store_mod.check_key(a.key)
        rec = st.version_record(key, a.n)
        text = st.version_bytes(key, a.n).decode("utf-8")
        return out({"record": rec, "text": text}, [json.dumps(rec, ensure_ascii=False), text.rstrip("\n")])
    if cmd == "version-diff":
        key = store_mod.check_key(a.key)
        va, vb = version_arg(a.a), version_arg(a.b)
        rows = st.diff_versions(key, va, vb)
        lines = [f"{r['stage']}.{r['field']}: {r['a']} -> {r['b']}" for r in rows] + [f"{len(rows)} differences"]
        return out({"key": key, "a": va, "b": vb, "changes": rows}, lines)
    if cmd == "restore":
        key = store_mod.check_key(a.key)
        rec = st.restore(key, a.n, a.author)
        return out({"record": rec, "version": rec["n"], "file": st.pose_rel(key)},
                   f"{key}: restored v{store_mod.check_n(a.n):03d} as v{rec['n']:03d}")
    if cmd == "approve":
        key = store_mod.check_key(a.key)
        rec = st.approve(key, a.n, not a.off)
        return out({"record": rec}, f"{key} v{rec['n']:03d} approved={rec['approved']}")
    if cmd == "progress":
        p = st.progress()
        lines = [f"{typ}: {x['at_5']}/{x['total']} at 5 stars ({x['share_5']:.0%}), below 4: {x['below_4']},"
                 f" unrated {x['unrated']}, stale {x['stale']}, met {x['met']}" for typ, x in p.items()]
        return out({"progress": p}, lines)
    if cmd == "changelog":
        log = st.write_changelog()
        return out({"file": st._path("changelog.json"), "changelog": log},
                   f"changelog: {len(log['versions'])} versions, {len(log['ratings'])} ratings, {len(log['notes'])} notes")
    if cmd == "init":
        st.ensure_dirs()
        created = st.ensure_all_initial()
        if created:
            st.write_changelog()
        return out({"created": created}, f"versions created for {len(created)} poses")
    raise CliError(f"unknown command {cmd}")


if __name__ == "__main__":
    sys.exit(main())
