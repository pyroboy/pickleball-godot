#!/usr/bin/env python3
"""Phone Pose Studio -> repo. Pulls the iPhone app's save queue, applies it, pushes back status.

The phone (scripts/studio/phone_sync_queue.gd) writes one JSON file per save, note and star
rating in the app's Documents/pose_studio_queue. This tool:
  1. pulls that folder with `xcrun devicectl` (cable or Wi-Fi pairing), or reads --local DIR,
  2. applies the entries oldest first with tools/pose_notes.py, exactly as the desktop studio's
     Save / Add note / Rate do (pose files via tres_edit, versions, notes, the ratings log);
     serves go to data/serve_tuning.json via serve_tuning.py,
  3. pushes back Documents/pose_studio_queue/synced.json (the applied ids: the phone deletes those
     entries) and Documents/pose_studio_sync/{notes,ratings,versions}.json (the repo's state, which
     the phone shows: Claude's replies, stars, version history).
Entries already applied (pose_studio/phone_applied.json) are never applied twice.

Usage: python3 tools/pose_studio/phone_sync.py [--device UDID] [--bundle ID] [--local DIR] [--dry-run] [--auto]
--auto (the background poll, tools/phone_sync_auto.sh): silent when the phone is unreachable or
nothing changed; pushes back only when there is something new for the phone.
Nothing is committed: review `git status` / `git diff` afterwards.
"""
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import store as store_mod  # noqa: E402

DEVICE = "00008130-001675341460001C"
BUNDLE = "com.arjomagno.arjostylepickleball.ios"
APPLIED = os.path.join(ROOT, "pose_studio", "phone_applied.json")
PUSHED = os.path.join(ROOT, "logs", "phone_sync_pushed.sha1")   # --auto: what the phone last got


def devicectl(*args):
    r = subprocess.run(["xcrun", "devicectl", "device", "copy"] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit("devicectl failed: " + (r.stderr or r.stdout).strip()[-400:])


def pull(device, bundle, dest):
    devicectl("from", "--device", device, "--domain-type", "appDataContainer", "--domain-identifier", bundle,
              "--source", "Documents/pose_studio_queue", "--destination", dest)


def push(device, bundle, src, remote):
    devicectl("to", "--device", device, "--domain-type", "appDataContainer", "--domain-identifier", bundle,
              "--source", src, "--destination", remote)


def cli(args, tool="tools/pose_notes.py"):
    r = subprocess.run([sys.executable, os.path.join(ROOT, tool)] + args + ["--json"], capture_output=True, text=True, cwd=ROOT)
    out = r.stdout.strip().splitlines()
    try:
        res = json.loads(out[-1]) if out else {}
    except ValueError:
        res = {}
    if not isinstance(res, dict): res = {}
    res.setdefault("ok", r.returncode == 0)
    if not res["ok"]: res.setdefault("error", (r.stderr or r.stdout).strip()[-300:])
    return res


def apply(entry, tmp):
    kind, key = entry.get("kind"), entry.get("key", "")
    if kind == "save":
        path = os.path.join(tmp, "changes_%s.json" % entry["id"])
        with open(path, "w") as f: json.dump({"key": key, "changes": entry.get("changes", [])}, f)
        if key.startswith("v"):
            return cli(["apply", "--style", str(int(key[1:])), "--changes", path], "tools/pose_studio/serve_tuning.py")
        return cli(["save", key, "--changes", path, "-m", "phone: " + entry.get("message", ""), "--author", "user"])
    if kind == "note":
        args = ["note-add", key, "--text", entry.get("text", "")]
        if entry.get("stage"): args += ["--stage", entry["stage"]]
        if entry.get("time_on_timeline") is not None: args += ["--time", str(float(entry["time_on_timeline"]))]
        return cli(args)
    if kind == "rate":
        return cli(["rate", key, "--stars", str(int(entry["stars"])), "--by", "user", "--source", "phone"])
    return {"ok": False, "error": "unknown kind %r" % kind}


def state_for_phone(store):
    keys = store.pose_keys() + ["v%02d" % i for i in range(7)]
    notes, ratings, versions = {}, {}, {}
    for n in store.notes():
        notes.setdefault(n.get("pose", ""), []).append(
            {k: n.get(k) for k in ("id", "text", "stage", "time", "status", "author", "reply", "created")})
    log = store.ratings()
    for k in keys:
        try:
            st = store.rating_state(k, log)
            if st and st.get("stars"): ratings[k] = {"stars": st["stars"], "version": st.get("version"), "stale": bool(st.get("stale"))}
        except Exception:
            pass
        try:
            versions[k] = [{x: r.get(x) for x in ("n", "author", "message", "time", "approved")} for r in store.versions(k)]
        except Exception:
            pass
    return notes, ratings, versions


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--device", default=DEVICE)
    ap.add_argument("--bundle", default=BUNDLE)
    ap.add_argument("--local", help="a queue folder on this Mac instead of the phone (tests)")
    ap.add_argument("--dry-run", action="store_true", help="list what would be applied")
    ap.add_argument("--auto", action="store_true", help="background poll: quiet, push only on changes")
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="phone_sync_")
    try:
        qdir = a.local or os.path.join(tmp, "queue")
        if not a.local:
            try: pull(a.device, a.bundle, qdir)
            except SystemExit:
                if a.auto: return   # phone asleep / out of reach: try again next poll
                raise
        names = sorted(n for n in os.listdir(qdir) if n.endswith(".json") and n != "synced.json") if os.path.isdir(qdir) else []
        applied = set(json.load(open(APPLIED)).get("ids", [])) if os.path.exists(APPLIED) else set()
        entries = []
        for n in names:
            try: e = json.load(open(os.path.join(qdir, n)))
            except ValueError: print("skip unreadable", n); continue
            if isinstance(e, dict) and e.get("id"): entries.append(e)
        done, failed, new, before = [], [], 0, 0
        for e in entries:
            if e["id"] in applied:
                done.append(e["id"]); before += 1; continue
            desc = "%s %s %s" % (e["kind"], e.get("key"), {"save": "%d change(s)" % len(e.get("changes", [])), "note": repr(e.get("text", ""))[:50],
                                                       "rate": "%s stars" % e.get("stars")}.get(e["kind"], ""))
            if a.dry_run: print("would apply:", desc); continue
            r = apply(e, tmp)
            if r.get("ok"):
                print("applied:", desc, ("v%03d" % r["version"]) if isinstance(r.get("version"), int) else "")
                done.append(e["id"]); applied.add(e["id"]); new += 1
            else:
                print("FAILED:", desc, "-", r.get("error")); failed.append(e["id"])
                break   # keep the order: later saves build on this one
        if a.dry_run: return
        os.makedirs(os.path.dirname(APPLIED), exist_ok=True)
        with open(APPLIED, "w") as f: json.dump({"ids": sorted(applied)[-2000:]}, f, indent=1)
        # Push back: applied ids, and the repo's notes / ratings / versions for the phone to show.
        store = store_mod.Store(ROOT)
        notes, ratings, versions = state_for_phone(store)
        out = os.path.join(tmp, "out"); os.makedirs(os.path.join(out, "sync"), exist_ok=True)
        with open(os.path.join(out, "synced.json"), "w") as f: json.dump({"ids": done}, f)
        for name, obj in (("notes", notes), ("ratings", ratings), ("versions", versions)):
            with open(os.path.join(out, "sync", name + ".json"), "w") as f: json.dump(obj, f)
        digest = hashlib.sha1(json.dumps([done, notes, ratings, versions], sort_keys=True).encode()).hexdigest()
        if a.auto and not failed and new == 0 and os.path.exists(PUSHED) and open(PUSHED).read().strip() == digest:
            return   # nothing new either way
        if a.local:
            shutil.copy(os.path.join(out, "synced.json"), os.path.join(qdir, "synced.json"))
            sync_dir = os.path.join(os.path.dirname(qdir.rstrip("/")), "pose_studio_sync")
            os.makedirs(sync_dir, exist_ok=True)
            for name in ("notes", "ratings", "versions"): shutil.copy(os.path.join(out, "sync", name + ".json"), sync_dir)
        else:
            push(a.device, a.bundle, os.path.join(out, "synced.json"), "Documents/pose_studio_queue/synced.json")
            for name in ("notes", "ratings", "versions"):
                push(a.device, a.bundle, os.path.join(out, "sync", name + ".json"), "Documents/pose_studio_sync/%s.json" % name)
        if a.auto:
            os.makedirs(os.path.dirname(PUSHED), exist_ok=True)
            with open(PUSHED, "w") as f: f.write(digest)
        if not a.auto or new or failed:
            print("%d applied, %d already applied before, %d failed. Nothing committed: review with git status / git diff" % (new, before, len(failed)))
        if failed: sys.exit(1)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
