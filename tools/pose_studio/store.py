"""Pose Studio storage: notes, versions, ratings, queue, progress, changelog.

Everything lives in pose_studio/ at the repo root (committed to git; has a .gdignore).
The env var POSE_STUDIO_ROOT (read by tools/pose_notes.py) points the store at another
folder, e.g. a scratch copy for tests; pose files are still read / written under the repo root.
Used by tools/pose_notes.py (the one writer: Claude and the Godot studio call it), so it
works without Godot running. Python standard library only.

Layout (tools/pose_studio/PROTOCOL.md section 3):
  pose_studio/notes/<key>.json          list of note records (spec 4)
  pose_studio/versions/<key>/vNNN.tres  v000 = git show HEAD:<file>, v001 = working copy
  pose_studio/versions/<key>/vNNN.json  at first studio start, then one per save
  pose_studio/ratings.json              append-only rating log (spec 4.1)
  pose_studio/changelog.json            generated
Writes are atomic (temp file + rename) and serialised by logs/.pose_studio.lock.
"""
import contextlib
import datetime
import difflib
import fcntl
import glob
import json
import os
import re
import subprocess
import tempfile
import threading

import tres_edit

KEY_RE = re.compile(r"^[sba]\d\d$")
NOTE_ID_RE = re.compile(r"^n\d{1,6}$")
FIELD_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
STAGES = ("windup", "contact", "finish")
NOTE_KINDS = ("request", "rule")
NOTE_STATUS = ("open", "addressed", "verified", "reopened")
OPEN_STATUS = ("open", "reopened")
ASPECTS = ("body", "arm", "motion", "timing")
AUTHORS = ("user", "claude")
SOURCES = ("studio", "phone")
TARGET_SHARE_5 = 0.8
TARGET_MIN_STARS = 4
POSE_TYPES = {"s": "stroke", "b": "base", "a": "action"}
SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "scripts")
_EXPORT_RE = re.compile(r"^@export\w*(?:\([^)]*\))?\s+var\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)

NOTE_KEYS = ("id", "pose", "kind", "stage", "field", "time", "author", "text", "status",
             "created", "created_version", "reply")
REPLY_KEYS = ("author", "text", "changes", "evidence", "version")
VERSION_KEYS = ("n", "author", "message", "time", "notes", "score", "flags", "approved")
RATING_KEYS = ("pose", "version", "stars", "aspects", "by", "source", "time", "notes", "comment")


class StoreError(ValueError):
    """Bad input (maps to HTTP 400) unless status says otherwise."""

    def __init__(self, msg, status=400):
        super().__init__(msg)
        self.status = status


def now():
    return datetime.datetime.now().replace(microsecond=0).isoformat()


def check_key(key):
    if not isinstance(key, str) or not KEY_RE.match(key):
        raise StoreError(f"bad pose key: {key!r}")
    return key


def check_n(n):
    if isinstance(n, bool):
        raise StoreError(f"bad version number: {n!r}")
    if isinstance(n, str) and re.match(r"^\d{1,4}$", n):
        n = int(n)
    if not isinstance(n, int) or n < 0 or n > 9999:
        raise StoreError(f"bad version number: {n!r}")
    return n


def dump_json(obj):
    return json.dumps(obj, indent=1, sort_keys=False, ensure_ascii=False) + "\n"


_ALLOWED = {}


def allowed_fields(key):
    """{stage: set(field)} a pose file may hold (read from the game scripts):
    stroke contact = PostureDefinition exports, windup / finish = StrokeBodyKeyframe.FIELDS;
    body stance contact = BasePoseDefinition exports (no keyframes)."""
    kind = POSE_TYPES[check_key(key)[0]]
    if kind not in _ALLOWED:
        def exports(name):
            with open(os.path.join(SCRIPTS, name), encoding="utf-8") as f:
                return set(_EXPORT_RE.findall(f.read())) - {"windup_body", "follow_through_body"}
        if kind in ("stroke", "action"):
            with open(os.path.join(SCRIPTS, "stroke_body_keyframe.gd"), encoding="utf-8") as f:
                m = re.search(r"const FIELDS[^=]*=\s*\[(.*?)\]", f.read(), re.S)
            kf = set(re.findall(r'"([A-Za-z_][A-Za-z0-9_]*)"', m.group(1))) if m else set()
            contact = exports("posture_definition.gd") | (exports("ball_action_definition.gd") if kind == "action" else set())
            _ALLOWED[kind] = {"contact": contact, "windup": kf, "finish": kf}
        else:
            _ALLOWED[kind] = {"contact": exports("base_pose_definition.gd")}
    return _ALLOWED[kind]


def check_section(key, changes):
    """Every change must target a section this pose has and a field that section allows."""
    allowed = allowed_fields(key)
    for c in changes:
        stage, field = c.get("stage"), c.get("field")
        if stage not in allowed:
            raise StoreError(f"{key}: stage {stage!r} not allowed (allowed: {sorted(allowed)})", 422)
        if field not in allowed[stage]:
            raise StoreError(f"{key}: field {field!r} not allowed in {stage}", 422)


def changed_line_count(old_text, new_text):
    """Lines changed between two texts (max of removed / added lines in a unified diff)."""
    minus = plus = 0
    for line in difflib.unified_diff(old_text.splitlines(), new_text.splitlines(), lineterm="", n=0):
        if line.startswith(("---", "+++", "@@")):
            continue
        minus += line.startswith("-")
        plus += line.startswith("+")
    return max(minus, plus)


class Store:
    def __init__(self, root, head_reader=None, latest_json=None, studio_dir=None):
        self.root = os.path.realpath(root)
        default_dir = os.path.join(self.root, "pose_studio")
        self.dir = os.path.realpath(studio_dir) if studio_dir else default_dir
        # Lock: logs/.pose_studio.lock (git-ignored) for the repo store; a scratch store keeps its own.
        self.lock_path = (os.path.join(self.root, "logs", ".pose_studio.lock") if self.dir == default_dir
                          else os.path.join(self.dir, ".pose_studio.lock"))
        self.latest_json = latest_json or os.path.join(self.root, "logs", "pose_check", "latest.json")
        self._head_reader = head_reader or self._git_head
        self._tlock = threading.RLock()
        self._depth = 0
        self._lock_fd = None

    # ---------- low level ----------
    @contextlib.contextmanager
    def lock(self):
        """Thread + process lock for every read-modify-write (every CLI process shares it)."""
        with self._tlock:
            if self._depth == 0:
                os.makedirs(os.path.dirname(self.lock_path), exist_ok=True)
                self._lock_fd = open(self.lock_path, "a")
                fcntl.flock(self._lock_fd, fcntl.LOCK_EX)
            self._depth += 1
            try:
                yield
            finally:
                self._depth -= 1
                if self._depth == 0:
                    fcntl.flock(self._lock_fd, fcntl.LOCK_UN)
                    self._lock_fd.close()
                    self._lock_fd = None

    def ensure_dirs(self):
        for d in (self.dir, os.path.join(self.dir, "notes"), os.path.join(self.dir, "versions")):
            os.makedirs(d, exist_ok=True)
        gd = os.path.join(self.dir, ".gdignore")
        if not os.path.exists(gd):
            open(gd, "w").close()

    def _path(self, *parts):
        p = os.path.realpath(os.path.join(self.dir, *parts))
        if not p.startswith(self.dir + os.sep):
            raise StoreError("path outside pose_studio/")
        return p

    @staticmethod
    def write_bytes(path, data):
        """Atomic write: temp file in the same folder, fsync, rename."""
        d = os.path.dirname(path)
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".tmp_", dir=d)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            if os.path.exists(path):
                os.chmod(tmp, os.stat(path).st_mode & 0o777)
            else:
                os.chmod(tmp, 0o644)
            os.replace(tmp, path)
        except BaseException:
            with contextlib.suppress(OSError):
                os.unlink(tmp)
            raise

    def write_json(self, path, obj):
        self.write_bytes(path, dump_json(obj).encode("utf-8"))

    @staticmethod
    def read_json(path, default):
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except FileNotFoundError:
            return default

    # ---------- poses ----------
    def pose_rel(self, key):
        check_key(key)
        try:
            return tres_edit.pose_file(key, self.root)
        except tres_edit.TresEditError as e:
            raise StoreError(str(e), 404)

    def pose_abs(self, key):
        return os.path.join(self.root, self.pose_rel(key))

    def read_pose_bytes(self, key):
        with open(self.pose_abs(key), "rb") as f:
            return f.read()

    def pose_keys(self):
        keys = []
        for prefix, folder in (("s", "data/postures"), ("b", "data/base_poses"), ("a", "data/ball_actions")):
            for p in sorted(glob.glob(os.path.join(self.root, folder, "[0-9][0-9]_*.tres"))):
                keys.append(f"{prefix}{os.path.basename(p)[:2]}")
        return keys

    def pose_info(self, key):
        """{key, name, kind, file, family} read from the file (fallback when Godot is absent)."""
        rel = self.pose_rel(key)
        text = self.read_pose_bytes(key).decode("utf-8")
        vals = tres_edit.parse_values(text).get("contact", {})
        name = vals.get("display_name", '""').strip('"')
        fam = vals.get("family")
        return {"key": key, "name": name, "kind": POSE_TYPES[key[0]], "file": rel,
                "family": int(fam) if fam and fam.lstrip("-").isdigit() else None}

    def checker(self):
        """{key: {score, flags}} from logs/pose_check/latest.json, or {}."""
        try:
            with open(self.latest_json, encoding="utf-8") as f:
                d = json.load(f)
            return d if isinstance(d, dict) else {}
        except (OSError, ValueError):
            return {}

    # ---------- versions ----------
    def _git_head(self, rel):
        r = subprocess.run(["git", "-C", self.root, "show", f"HEAD:{rel}"], capture_output=True, timeout=20)
        return r.stdout if r.returncode == 0 else None

    def _vdir(self, key):
        return self._path("versions", check_key(key))

    def version_numbers(self, key):
        d = self._vdir(key)
        if not os.path.isdir(d):
            return []
        return sorted(int(m.group(1)) for m in (re.match(r"^v(\d{3,4})\.json$", f) for f in os.listdir(d)) if m)

    def current_version(self, key):
        ns = self.version_numbers(key)
        return ns[-1] if ns else None

    def ensure_initial(self, key):
        """v000 = HEAD text, v001 = working copy, only when the pose has no versions yet."""
        with self.lock():
            if self.version_numbers(key):
                return False
            rel = self.pose_rel(key)
            work = self.read_pose_bytes(key)
            head = self._head_reader(rel)
            self.ensure_dirs()
            self._write_version(key, 0, head if head is not None else work, "user",
                                "HEAD" if head is not None else "HEAD (file not in git; working copy)")
            self._write_version(key, 1, work, "user", "working copy at first studio start")
            return True

    def ensure_all_initial(self):
        return [k for k in self.pose_keys() if self.ensure_initial(k)]

    def _write_version(self, key, n, data, author, message, notes=None, score=None, flags=None):
        d = self._vdir(key)
        rec = {"n": n, "author": author, "message": message, "time": now(), "notes": list(notes or []),
               "score": score, "flags": list(flags or []), "approved": False}
        self.write_bytes(os.path.join(d, f"v{n:03d}.tres"), data)
        self.write_json(os.path.join(d, f"v{n:03d}.json"), rec)
        return rec

    def add_version(self, key, author, message="", notes=None, score="auto", flags="auto"):
        """Record the current pose file as a new version. score/flags 'auto' = from latest.json."""
        if author not in AUTHORS:
            raise StoreError(f"bad author: {author!r}")
        if not isinstance(message, str) or len(message) > 2000:
            raise StoreError("bad message")
        notes = self._check_note_ids(notes or [])
        with self.lock():
            self.ensure_initial(key)
            if score == "auto" or flags == "auto":
                # latest.json describes the pose only when the checker ran after the file's
                # last write; otherwise its score belongs to older content: record null.
                c = (self.checker().get(key) or {}) if self._checker_fresh(key) else {}
                if score == "auto":
                    score = c.get("score")
                if flags == "auto":
                    flags = list((c.get("flags") or {}).keys()) if isinstance(c.get("flags"), dict) else list(c.get("flags") or [])
            n = self.current_version(key) + 1
            rec = self._write_version(key, n, self.read_pose_bytes(key), author, message, notes, score, flags)
        try:   # the pose file and version are written: a changelog failure must not fail the save
            self.write_changelog()
        except Exception as e:  # noqa: BLE001
            rec = dict(rec, changelog_error=f"{type(e).__name__}: {e}")
        return rec

    def _checker_fresh(self, key):
        """True when logs/pose_check/latest.json is at least as new as the pose file."""
        try:
            return os.stat(self.latest_json).st_mtime_ns >= os.stat(self.pose_abs(key)).st_mtime_ns
        except (OSError, StoreError):
            return False

    def version_record(self, key, n):
        n = check_n(n)
        p = os.path.join(self._vdir(key), f"v{n:03d}.json")
        rec = self.read_json(p, None)
        if rec is None:
            raise StoreError(f"{key} has no version {n}", 404)
        return rec

    def version_bytes(self, key, n):
        n = check_n(n)
        self.version_record(key, n)
        with open(os.path.join(self._vdir(key), f"v{n:03d}.tres"), "rb") as f:
            return f.read()

    def versions(self, key):
        check_key(key)
        return [self.version_record(key, n) for n in self.version_numbers(key)]

    def matches_current(self, key):
        """True when the pose file equals its latest version byte for byte."""
        n = self.current_version(key)
        return n is not None and self.version_bytes(key, n) == self.read_pose_bytes(key)

    def restore(self, key, n, author="user"):
        """Write version n byte-identically to the pose file, then record a new version."""
        data = self.version_bytes(key, n)
        with self.lock():
            self.ensure_initial(key)
            self.write_bytes(self.pose_abs(key), data)
            rec = self.add_version(key, author, f"restore v{check_n(n):03d}")
        return rec

    def save_changes(self, key, changes, author="user", message="", notes=None):
        """Apply [{stage, field, text}] (link diff rows) to the pose file as minimal text edits
        and record a version. No effective change: file byte-identical, no new version.
        Every change is validated before the file is touched."""
        check_key(key)
        if author not in AUTHORS:
            raise StoreError(f"bad author: {author!r}")
        if not isinstance(message, str) or len(message) > 2000:
            raise StoreError("bad message")
        notes = self._check_note_ids(notes or [])
        if not isinstance(changes, list):
            raise StoreError("changes must be a list of {stage, field, text}")
        try:
            for c in changes:
                tres_edit.check_change(c)
        except tres_edit.TresEditError as e:
            raise StoreError(str(e), 422)
        check_section(key, changes)
        rel = self.pose_rel(key)
        with self.lock():
            self.ensure_initial(key)     # v000 / v001 before the first write
            path = self.pose_abs(key)
            with open(path, "rb") as f:
                old = f.read()
            old_text = old.decode("utf-8")
            try:
                new_text, applied = tres_edit.apply_changes(old_text, changes)
            except tres_edit.TresEditError as e:
                raise StoreError(f"cannot apply changes: {e}", 422)
            if not applied:
                return {"file": rel, "changes": [], "changed_lines": 0,
                        "version": self.current_version(key), "saved": False}
            self.write_bytes(path, new_text.encode("utf-8"))
            rec = self.add_version(key, author, message, notes)
        r = {"file": rel, "changes": applied, "changed_lines": changed_line_count(old_text, new_text),
             "version": rec["n"], "saved": True}
        if rec.get("changelog_error"):
            r["changelog_error"] = rec["changelog_error"]
        return r

    def approve(self, key, n, approved=True):
        with self.lock():
            rec = self.version_record(key, n)
            rec["approved"] = bool(approved)
            self.write_json(os.path.join(self._vdir(key), f"v{rec['n']:03d}.json"), rec)
        self.write_changelog()
        return rec

    def _text_of(self, key, which):
        if which in ("file", "work", "working"):
            return self.read_pose_bytes(key).decode("utf-8")
        return self.version_bytes(key, which).decode("utf-8")

    def diff_versions(self, key, a, b):
        """[{stage, field, a, b}]; a / b are version numbers or 'file' (working copy)."""
        return tres_edit.diff_values(self._text_of(key, a), self._text_of(key, b))

    # ---------- notes ----------
    def _notes_path(self, key):
        return self._path("notes", f"{check_key(key)}.json")

    def notes(self, key=None):
        if key is not None:
            return self.read_json(self._notes_path(key), [])
        out = []
        for p in sorted(glob.glob(os.path.join(self.dir, "notes", "[sb][0-9][0-9].json"))):
            out += self.read_json(p, [])
        return out

    def _next_note_id(self):
        ids = [int(n["id"][1:]) for n in self.notes() if NOTE_ID_RE.match(str(n.get("id", "")))]
        return f"n{max(ids, default=0) + 1}"

    def _check_note_ids(self, ids):
        if not isinstance(ids, list) or not all(isinstance(i, str) and NOTE_ID_RE.match(i) for i in ids):
            raise StoreError(f"bad note id list: {ids!r}")
        return ids

    def find_note(self, note_id):
        if not isinstance(note_id, str) or not NOTE_ID_RE.match(note_id):
            raise StoreError(f"bad note id: {note_id!r}")
        for n in self.notes():
            if n.get("id") == note_id:
                return n
        raise StoreError(f"no note {note_id}", 404)

    @staticmethod
    def _check_pin(rec):
        stage, field, t = rec.get("stage"), rec.get("field"), rec.get("time")
        if stage is not None and stage not in STAGES:
            raise StoreError(f"bad stage: {stage!r}")
        if field is not None and (not isinstance(field, str) or not FIELD_RE.match(field)):
            raise StoreError(f"bad field: {field!r}")
        if t is not None and (isinstance(t, bool) or not isinstance(t, (int, float)) or not 0 <= t <= 1):
            raise StoreError(f"bad time (0..1 or null): {t!r}")

    @staticmethod
    def _check_text(text, what="text", limit=4000):
        if not isinstance(text, str) or not text.strip() or len(text) > limit:
            raise StoreError(f"bad {what}")
        return text

    def create_note(self, key, rec):
        check_key(key)
        if not isinstance(rec, dict):
            raise StoreError("note must be an object")
        if rec.get("pose", key) != key:
            raise StoreError("pose does not match key")
        kind = rec.get("kind", "request")
        if kind not in NOTE_KINDS:
            raise StoreError(f"bad kind: {kind!r}")
        author = rec.get("author", "user")
        if author not in AUTHORS:
            raise StoreError(f"bad author: {author!r}")
        self._check_pin(rec)
        self._check_text(rec.get("text"))
        self.pose_rel(key)
        with self.lock():
            note = {"id": self._next_note_id(), "pose": key, "kind": kind, "stage": rec.get("stage"),
                    "field": rec.get("field"), "time": rec.get("time"), "author": author,
                    "text": rec["text"], "status": "open", "created": now(),
                    "created_version": self.current_version(key), "reply": None}
            if kind == "rule" and isinstance(rec.get("rule"), dict):
                note["rule"] = self._check_rule(rec["rule"])
            lst = self.notes(key)
            lst.append(note)
            self.write_json(self._notes_path(key), lst)
        return note

    @staticmethod
    def _check_rule(rule):
        out = {}
        for k in ("flag", "metric"):
            if rule.get(k) is not None:
                if not isinstance(rule[k], str) or not re.match(r"^[A-Za-z0-9_.]{1,80}$", rule[k]):
                    raise StoreError(f"bad rule {k}")
                out[k] = rule[k]
        for k in ("min", "max"):
            if rule.get(k) is not None:
                if isinstance(rule[k], bool) or not isinstance(rule[k], (int, float)):
                    raise StoreError(f"bad rule {k}")
                out[k] = rule[k]
        return out

    def _check_reply(self, reply):
        if not isinstance(reply, dict):
            raise StoreError("reply must be an object")
        author = reply.get("author", "claude")
        if author not in AUTHORS:
            raise StoreError(f"bad reply author: {author!r}")
        changes = reply.get("changes") or []
        if not isinstance(changes, list):
            raise StoreError("reply changes must be a list")
        clean = []
        for c in changes:
            if not isinstance(c, dict) or c.get("stage") not in STAGES or not isinstance(c.get("field"), str) \
                    or not FIELD_RE.match(c["field"]):
                raise StoreError(f"bad change: {c!r}")
            clean.append({"stage": c["stage"], "field": c["field"],
                          "from": None if c.get("from") is None else str(c["from"]),
                          "to": None if c.get("to") is None else str(c["to"])})
        ver = reply.get("version")
        if ver is not None:
            ver = check_n(ver)
        evidence = reply.get("evidence", "")
        if not isinstance(evidence, str) or len(evidence) > 4000:
            raise StoreError("bad evidence")
        return {"author": author, "text": self._check_text(reply.get("text"), "reply text"),
                "changes": clean, "evidence": evidence, "version": ver}

    def update_note(self, note_id, patch):
        """Partial update: status, reply (sets status 'addressed' unless given), text."""
        if not isinstance(patch, dict):
            raise StoreError("update must be an object")
        bad = set(patch) - {"status", "reply", "text"}
        if bad:
            raise StoreError(f"fields not editable: {sorted(bad)}")
        with self.lock():
            note = self.find_note(note_id)
            key = note["pose"]
            if "reply" in patch:
                note["reply"] = None if patch["reply"] is None else self._check_reply(patch["reply"])
                if note["reply"] is not None and "status" not in patch:
                    note["status"] = "addressed"
            if "status" in patch:
                if patch["status"] not in NOTE_STATUS:
                    raise StoreError(f"bad status: {patch['status']!r}")
                note["status"] = patch["status"]
            if "text" in patch:
                note["text"] = self._check_text(patch["text"])
            lst = [note if n.get("id") == note_id else n for n in self.notes(key)]
            self.write_json(self._notes_path(key), lst)
        return note

    # ---------- ratings ----------
    def _ratings_path(self):
        return self._path("ratings.json")

    def ratings(self, key=None):
        rows = self.read_json(self._ratings_path(), [])
        return [r for r in rows if key is None or r.get("pose") == key]

    def add_rating(self, rec):
        """Append one rating (spec 4.1). Version is always the pose's current version."""
        if not isinstance(rec, dict):
            raise StoreError("rating must be an object")
        key = check_key(rec.get("pose"))
        stars = rec.get("stars")
        if isinstance(stars, bool) or not isinstance(stars, int) or not 1 <= stars <= 5:
            raise StoreError("stars must be an integer 1..5")
        aspects = rec.get("aspects") or {}
        if not isinstance(aspects, dict) or any(k not in ASPECTS for k in aspects) or any(
                isinstance(v, bool) or not isinstance(v, int) or not 1 <= v <= 5 for v in aspects.values()):
            raise StoreError(f"bad aspects (keys {ASPECTS}, values 1..5)")
        if rec.get("by", "user") != "user":
            raise StoreError("stars are given by the user only")
        source = rec.get("source", "studio")
        if source not in SOURCES:
            raise StoreError(f"bad source: {source!r}")
        comment = rec.get("comment", "")
        if not isinstance(comment, str) or len(comment) > 4000:
            raise StoreError("bad comment")
        notes = self._check_note_ids(rec.get("notes") or [])
        self.pose_rel(key)
        with self.lock():
            self.ensure_initial(key)
            row = {"pose": key, "version": self.current_version(key), "stars": stars,
                   "aspects": {k: aspects[k] for k in ASPECTS if k in aspects}, "by": "user",
                   "source": source, "time": now(), "notes": notes, "comment": comment}
            self._append_rating(row)
        return row

    def _append_rating(self, row):
        path = self._ratings_path()
        try:
            with open(path, "rb") as f:
                old = f.read().decode("utf-8")
        except FileNotFoundError:
            old = ""
        rows = json.loads(old) if old.strip() else []
        if not isinstance(rows, list):
            raise StoreError("ratings.json is not a list", 500)
        new = dump_json(rows + [row])
        # Append-only: every existing entry keeps its exact bytes.
        if rows and not new.startswith(old.rstrip()[:-1].rstrip()):
            raise StoreError("ratings.json was reformatted by hand; refusing to rewrite it", 500)
        self.write_bytes(path, new.encode("utf-8"))

    def rating_state(self, key, ratings=None):
        """{stars, stale, stale_stars, version, rated_version, aspects} for a pose."""
        cur = self.current_version(key)
        rows = [r for r in (ratings if ratings is not None else self.ratings()) if r.get("pose") == key]
        last = rows[-1] if rows else None
        on_cur = [r for r in rows if r.get("version") == cur]
        if on_cur:
            r = on_cur[-1]
            return {"stars": r["stars"], "stale": False, "stale_stars": None, "version": cur,
                    "rated_version": cur, "aspects": r.get("aspects") or {}}
        return {"stars": None, "stale": last is not None, "stale_stars": last["stars"] if last else None,
                "version": cur, "rated_version": last["version"] if last else None,
                "aspects": (last.get("aspects") or {}) if last else {}}

    # ---------- queue ----------
    def queue(self):
        """Spec 4.1: poses by current stars (lowest first), then unrated, then stale;
        inside a pose: open notes first, then checker flags."""
        ratings, checker, notes = self.ratings(), self.checker(), self.notes()
        groups = {"rated": [], "unrated": [], "stale": []}
        for key in self.pose_keys():
            st = self.rating_state(key, ratings)
            c = checker.get(key) or {}
            flags = c.get("flags") or {}
            if isinstance(flags, list):
                flags = {f: "" for f in flags}
            open_notes = [n for n in notes if n.get("pose") == key and n.get("status") in OPEN_STATUS]
            items = [{"type": "note", "id": n["id"], "kind": n.get("kind"), "stage": n.get("stage"),
                      "field": n.get("field"), "text": n.get("text"), "status": n.get("status")} for n in open_notes]
            items += [{"type": "flag", "id": f, "text": t} for f, t in flags.items()]
            group = "rated" if st["stars"] is not None else ("stale" if st["stale"] else "unrated")
            groups[group].append({"key": key, "kind": POSE_TYPES[key[0]], "group": group, "stars": st["stars"],
                                  "stale_stars": st["stale_stars"], "version": st["version"],
                                  "rated_version": st["rated_version"], "score": c.get("score"),
                                  "done": st["stars"] == 5 and not open_notes, "items": items})
        score = lambda e: e["score"] if isinstance(e["score"], (int, float)) else 1e9
        groups["rated"].sort(key=lambda e: (e["stars"], score(e), e["key"]))
        groups["unrated"].sort(key=lambda e: (score(e), e["key"]))
        groups["stale"].sort(key=lambda e: (e["stale_stars"], score(e), e["key"]))
        return groups["rated"] + groups["unrated"] + groups["stale"]

    # ---------- progress ----------
    def _version_times(self):
        """{key: [(time, n), ...]} sorted, from version records."""
        out = {}
        for key in self.pose_keys():
            out[key] = sorted((r.get("time") or "", r["n"]) for r in self.versions(key))
        return out

    def progress(self):
        ratings = self.ratings()
        keys = self.pose_keys()
        out = {}
        for prefix, typ in POSE_TYPES.items():
            tk = [k for k in keys if k[0] == prefix]
            counts = {str(s): 0 for s in range(1, 6)}
            unrated = stale = 0
            for k in tk:
                st = self.rating_state(k, ratings)
                if st["stars"] is not None:
                    counts[str(st["stars"])] += 1
                elif st["stale"]:
                    stale += 1
                else:
                    unrated += 1
            total = len(tk)
            at5 = counts["5"]
            below = sum(counts[str(s)] for s in range(1, TARGET_MIN_STARS))
            share = at5 / total if total else 0.0
            out[typ] = {"total": total, "counts": counts, "unrated": unrated, "stale": stale,
                        "at_5": at5, "share_5": round(share, 4), "below_4": below,
                        "target_share_5": TARGET_SHARE_5, "target_min_stars": TARGET_MIN_STARS,
                        "met": total > 0 and share >= TARGET_SHARE_5 and below == 0 and unrated == 0 and stale == 0,
                        "history": []}
        # History: after each rating, share at 5 on the version that was current then.
        vt = self._version_times()
        latest = {}
        for r in ratings:
            k, t = r.get("pose"), r.get("time") or ""
            if k not in vt:
                continue
            latest[k] = r
            typ = POSE_TYPES[k[0]]
            at5 = 0
            for kk, rr in latest.items():
                if POSE_TYPES[kk[0]] != typ:
                    continue
                cur = max((n for tt, n in vt[kk] if tt <= t), default=None)
                if rr["stars"] == 5 and rr.get("version") == cur:
                    at5 += 1
            total = out[typ]["total"]
            out[typ]["history"].append({"time": t, "pose": k, "stars": r["stars"], "at_5": at5,
                                        "share_5": round(at5 / total, 4) if total else 0.0})
        return out

    # ---------- changelog ----------
    def changelog(self):
        entries = []
        for key in self.pose_keys():
            vs = self.versions(key)
            for prev, rec in zip([None] + vs[:-1], vs):
                changes = []
                if prev is not None:
                    changes = self.diff_versions(key, prev["n"], rec["n"])
                entries.append({"pose": key, "n": rec["n"], "time": rec.get("time"), "author": rec.get("author"),
                                "message": rec.get("message"), "approved": rec.get("approved", False),
                                "notes": rec.get("notes", []), "score": rec.get("score"),
                                "flags": rec.get("flags", []), "changes": changes})
        entries.sort(key=lambda e: (e["time"] or "", e["pose"], e["n"]), reverse=True)
        return {"versions": entries,
                "ratings": self.ratings(),
                "notes": [{k: n.get(k) for k in ("id", "pose", "kind", "status", "text", "created")} for n in self.notes()]}

    def write_changelog(self):
        """Regenerate pose_studio/changelog.json; rewrites only when the content changed."""
        with self.lock():
            log = self.changelog()
            path = self._path("changelog.json")
            data = dump_json(log).encode("utf-8")
            try:
                with open(path, "rb") as f:
                    if f.read() == data:
                        return log
            except FileNotFoundError:
                pass
            self.write_bytes(path, data)
        return log
