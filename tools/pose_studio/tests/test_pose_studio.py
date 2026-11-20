"""Pose Studio backend tests (stdlib unittest, no Godot needed).

  python3 -m unittest discover -s tools/pose_studio/tests -v
Every test works on COPIES of the repo pose files in a temp folder (set TMPDIR to
choose where); the repo's data/ and pose_studio/ are only read, never written.
The CLI tests point tools/pose_notes.py at the temp copy with POSE_STUDIO_REPO (pose files)
and POSE_STUDIO_ROOT (store folder).
"""
import contextlib
import difflib
import glob
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
STUDIO = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(STUDIO))
sys.path.insert(0, STUDIO)
import bench as bench_mod  # noqa: E402
import store as store_mod  # noqa: E402
import tres_edit  # noqa: E402

S13 = "data/postures/13_mid_low_forehand.tres"


def changed_lines(a, b):
    d = [l for l in difflib.unified_diff(a.splitlines(), b.splitlines(), lineterm="", n=0)
         if not l.startswith(("---", "+++", "@@"))]
    return [l for l in d if l.startswith("-")], [l for l in d if l.startswith("+")]


def make_root():
    """Temp repo-like root with copies of every pose file and a pose_check latest.json."""
    root = tempfile.mkdtemp(prefix="pose_studio_test_")
    for folder in ("data/postures", "data/base_poses"):
        os.makedirs(os.path.join(root, folder))
        for p in glob.glob(os.path.join(REPO, folder, "*.tres")):
            shutil.copy2(p, os.path.join(root, folder))
    os.makedirs(os.path.join(root, "logs", "pose_check"))
    latest = {"s17": {"score": 28, "flags": {"B_balance_contact": "off balance"}},
              "s10": {"score": 40, "flags": {"B_transfer": "little transfer"}},
              "s13": {"score": 58, "flags": {"B_pop_up": "hips rise", "C_no_swing": "slow"}},
              "s00": {"score": 90, "flags": {}}}
    with open(os.path.join(root, "logs", "pose_check", "latest.json"), "w") as f:
        json.dump(latest, f)
    return root


def fake_head(root):
    """HEAD reader for the temp root: the copied file with a marker line (so v000 != v001)."""
    def read(rel):
        with open(os.path.join(root, rel), "rb") as f:
            return f.read() + b"; head\n"
    return read


def checker_ran(root):
    """Mark logs/pose_check/latest.json as newer than every pose file (the checker reran)."""
    t = os.stat(os.path.join(root, "logs", "pose_check", "latest.json")).st_mtime + 10
    os.utime(os.path.join(root, "logs", "pose_check", "latest.json"), (t, t))


def read(root, rel):
    with open(os.path.join(root, rel), "rb") as f:
        return f.read()


# ---------------------------------------------------------------- tres_edit
class TresEditTests(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.text = read(self.root, S13).decode("utf-8")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def one_line(self, changes, expect_field):
        new, applied = tres_edit.apply_changes(self.text, changes)
        minus, plus = changed_lines(self.text, new)
        self.assertEqual((len(minus), len(plus)), (1, 1), (minus, plus))
        self.assertIn(expect_field, minus[0])
        self.assertIn(expect_field, plus[0])
        self.assertEqual(len(applied), 1)
        return new, minus[0], plus[0]

    def test_main_field_one_line(self):
        new, m, p = self.one_line([{"stage": "contact", "field": "crouch_amount", "text": "0.3"}], "crouch_amount")
        self.assertEqual(p, "+crouch_amount = 0.3")
        self.assertEqual(m, "-crouch_amount = 0.0744461236357523")

    def test_keyframe_dict_field_one_line(self):
        _, m, p = self.one_line([{"stage": "windup", "field": "body_yaw_deg", "text": "25.0"}], "body_yaw_deg")
        self.assertEqual(p, '+"body_yaw_deg": 25.0,')
        # the finish dict also has body_yaw_deg; it must not move
        new, _ = tres_edit.apply_changes(self.text, [{"stage": "windup", "field": "body_yaw_deg", "text": "25.0"}])
        self.assertEqual(tres_edit.get_value(new, "finish", "body_yaw_deg"), "-20")

    def test_finish_last_entry_keeps_no_comma(self):
        # the last entry of s13's finish dict is the elbow swivel (stage 6c bake)
        _, m, p = self.one_line([{"stage": "finish", "field": "right_elbow_swivel_deg", "text": "-10.0"}],
                                "right_elbow_swivel_deg")
        self.assertEqual(p, '+"right_elbow_swivel_deg": -10.0')

    def test_vector3_field_one_line(self):
        _, m, p = self.one_line([{"stage": "contact", "field": "charge_paddle_offset", "text": "Vector3(0.1, -0.2, -0.45)"}],
                                "charge_paddle_offset")
        self.assertEqual(p, "+charge_paddle_offset = Vector3(0.1, -0.2, -0.45)")

    def test_no_change_byte_identical(self):
        new, applied = tres_edit.apply_changes(self.text, [])
        self.assertEqual(new.encode("utf-8"), read(self.root, S13))
        self.assertEqual(applied, [])

    def test_same_value_text_byte_identical(self):
        same = [{"stage": "contact", "field": "crouch_amount", "text": "0.0744461236357523"},
                {"stage": "windup", "field": "body_yaw_deg", "text": "15.0"},         # file has 15
                {"stage": "finish", "field": "body_position_offset", "text": "Vector3(-0.1, 0, 0.15)"},  # file: no spaces
                {"stage": "contact", "field": "display_name", "text": '"Mid-Low Forehand"'}]
        new, applied = tres_edit.apply_changes(self.text, same)
        self.assertEqual(applied, [])
        self.assertEqual(new.encode("utf-8"), read(self.root, S13))

    def test_new_field_dict_and_main(self):
        new, applied = tres_edit.apply_changes(self.text, [{"stage": "windup", "field": "spine_twist_deg", "text": "4.0"}])
        minus, plus = changed_lines(self.text, new)
        # the previous last entry gains a comma, the new entry is added before "}"
        last = tres_edit.get_value(self.text, "windup", "right_elbow_swivel_deg")
        self.assertEqual(minus, [f'-"right_elbow_swivel_deg": {last}'])
        self.assertEqual(plus, [f'+"right_elbow_swivel_deg": {last},', '+"spine_twist_deg": 4.0'])
        self.assertIsNone(applied[0]["from"])
        new2, _ = tres_edit.apply_changes(self.text, [{"stage": "contact", "field": "ft_new_field", "text": "1.5"}])
        minus, plus = changed_lines(self.text, new2)
        self.assertEqual((minus, plus), ([], ["+ft_new_field = 1.5"]))
        self.assertTrue(new2.endswith("\nft_new_field = 1.5\n"))

    def test_bad_changes_rejected_text_untouched(self):
        bad = [{"stage": "contact", "field": "crouch_amount", "text": "0.3\n[resource]"},
               {"stage": "middle", "field": "crouch_amount", "text": "0.3"},
               {"stage": "contact", "field": "../x", "text": "0.3"},
               {"stage": "contact", "field": "script", "text": "0.3"},
               {"stage": "contact", "field": "crouch_amount", "text": ""},
               {"stage": "contact", "field": "crouch_amount", "text": 0.3}]
        for c in bad:
            with self.assertRaises(tres_edit.TresEditError, msg=str(c)):
                tres_edit.apply_changes(self.text, [{"stage": "contact", "field": "weight_shift", "text": "0.5"}, c])

    def test_diff_values_equals_edits(self):
        changes = [{"stage": "contact", "field": "crouch_amount", "text": "0.3"},
                   {"stage": "windup", "field": "hip_yaw_deg", "text": "12.0"},
                   {"stage": "finish", "field": "left_hand_offset", "text": "Vector3(-0.1, 0, -0.2)"}]
        new, applied = tres_edit.apply_changes(self.text, changes)
        rows = tres_edit.diff_values(self.text, new)
        self.assertEqual(sorted((r["stage"], r["field"], r["b"]) for r in rows),
                         sorted((c["stage"], c["field"], c["text"]) for c in changes))

    def test_all_repo_pose_files_parse(self):
        files = glob.glob(os.path.join(REPO, "data/postures/*.tres")) + glob.glob(os.path.join(REPO, "data/base_poses/*.tres"))
        self.assertEqual(len(files), 43)
        for p in files:
            with open(p) as f:
                v = tres_edit.parse_values(f.read())
            stages = 3 if "/postures/" in p else 1
            self.assertEqual(len(v), stages, p)
            self.assertIn("display_name", v["contact"], p)

    def test_pose_file_guard(self):
        self.assertEqual(tres_edit.pose_file("s13", self.root), S13)
        for k in ("../s13", "s1", "x13", "s13/../..", "s130", None):
            with self.assertRaises(tres_edit.TresEditError):
                tres_edit.pose_file(k, self.root)


# ---------------------------------------------------------------- store
class StoreTests(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.st = store_mod.Store(self.root, head_reader=fake_head(self.root))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def edit(self, key, changes):
        rel = self.st.pose_rel(key)
        text = read(self.root, rel).decode("utf-8")
        new, applied = tres_edit.apply_changes(text, changes)
        self.st.write_bytes(os.path.join(self.root, rel), new.encode("utf-8"))
        return applied

    def test_initial_versions(self):
        orig = read(self.root, S13)
        self.assertTrue(self.st.ensure_initial("s13"))
        self.assertFalse(self.st.ensure_initial("s13"))
        self.assertEqual(self.st.version_bytes("s13", 0), orig + b"; head\n")
        self.assertEqual(self.st.version_bytes("s13", 1), orig)
        self.assertEqual(self.st.current_version("s13"), 1)
        self.assertTrue(self.st.matches_current("s13"))

    def test_real_git_head_reader(self):
        st = store_mod.Store(REPO)
        head = st._git_head("data/postures/00_forehand.tres")
        self.assertTrue(head and head.startswith(b"[gd_resource"))

    def test_restore_byte_identical_and_diff_equals_edits(self):
        orig = read(self.root, S13)
        self.st.ensure_initial("s13")
        changes = [{"stage": "contact", "field": "crouch_amount", "text": "0.3"},
                   {"stage": "finish", "field": "weight_shift", "text": "0.4"}]
        self.edit("s13", changes)
        checker_ran(self.root)
        v2 = self.st.add_version("s13", "user", "lower hips")
        self.assertEqual(v2["n"], 2)
        self.assertEqual(v2["score"], 58)
        self.assertEqual(sorted(v2["flags"]), ["B_pop_up", "C_no_swing"])
        rows = self.st.diff_versions("s13", 1, 2)
        self.assertEqual(sorted((r["stage"], r["field"], r["b"]) for r in rows),
                         sorted((c["stage"], c["field"], c["text"]) for c in changes))
        self.assertEqual(self.st.diff_versions("s13", 2, "file"), [])
        rec = self.st.restore("s13", 1)
        self.assertEqual(rec["n"], 3)
        self.assertEqual(read(self.root, S13), orig)
        self.assertEqual(self.st.version_bytes("s13", 3), orig)
        rec = self.st.restore("s13", 2)
        self.assertEqual(read(self.root, S13), self.st.version_bytes("s13", 2))

    def test_version_schema(self):
        self.st.ensure_initial("s13")
        self.st.add_version("s13", "claude", "msg", ["n1"])
        for p in glob.glob(os.path.join(self.root, "pose_studio/versions/s13/v*.json")):
            with open(p, "rb") as f:
                raw = f.read()
            self.assertTrue(raw.endswith(b"\n"))
            rec = json.loads(raw)
            self.assertEqual(tuple(rec), store_mod.VERSION_KEYS)
            self.assertIsInstance(rec["n"], int)
            self.assertIn(rec["author"], ("user", "claude"))
            self.assertIsInstance(rec["flags"], list)
            self.assertIsInstance(rec["approved"], bool)
            self.assertTrue(re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$", rec["time"]))
        self.assertTrue(self.st.approve("s13", 2)["approved"])
        self.assertTrue(self.st.versions("s13")[2]["approved"])

    def test_note_schema_and_flow(self):
        self.st.ensure_initial("s13")
        n = self.st.create_note("s13", {"kind": "request", "stage": "contact", "field": "crouch_amount",
                                        "time": 0.5, "text": "hips rise at contact"})
        self.assertEqual(tuple(n), store_mod.NOTE_KEYS)
        self.assertEqual((n["id"], n["status"], n["created_version"], n["author"]), ("n1", "open", 1, "user"))
        n2 = self.st.create_note("s10", {"kind": "rule", "text": "no balance flag", "rule": {"flag": "B_balance_contact"}})
        self.assertEqual(n2["id"], "n2")
        r = self.st.update_note("n1", {"reply": {"text": "lowered hips", "evidence": "hip 0.78 -> 0.58 m", "version": 2,
                                                 "changes": [{"stage": "contact", "field": "crouch_amount",
                                                              "from": "0.074", "to": "0.3"}]}})
        self.assertEqual(r["status"], "addressed")
        self.assertEqual(tuple(r["reply"]), store_mod.REPLY_KEYS)
        with open(os.path.join(self.root, "pose_studio/notes/s13.json"), "rb") as f:
            saved = json.loads(f.read())
        self.assertEqual(saved[0], r)
        self.assertEqual(self.st.update_note("n1", {"status": "verified"})["status"], "verified")
        for bad in ({"kind": "wish", "text": "x"}, {"text": ""}, {"text": "x", "stage": "mid"},
                    {"text": "x", "time": 2}, {"text": "x", "field": "../a"}, {"text": "x", "author": "bot"}):
            with self.assertRaises(store_mod.StoreError, msg=str(bad)):
                self.st.create_note("s13", bad)
        with self.assertRaises(store_mod.StoreError):
            self.st.update_note("n1", {"status": "done"})
        with self.assertRaises(store_mod.StoreError):
            self.st.update_note("n1", {"pose": "s00"})

    def test_rating_stale_after_save_and_append_only(self):
        self.st.ensure_initial("s13")
        r = self.st.add_rating({"pose": "s13", "stars": 3, "aspects": {"body": 2, "arm": 4}, "comment": "stiff"})
        self.assertEqual(tuple(r), store_mod.RATING_KEYS)
        self.assertEqual(r["version"], 1)
        self.assertEqual(self.st.rating_state("s13")["stars"], 3)
        path = os.path.join(self.root, "pose_studio/ratings.json")
        before = read(self.root, path)
        self.edit("s13", [{"stage": "contact", "field": "crouch_amount", "text": "0.3"}])
        self.st.add_version("s13", "user", "save")
        s = self.st.rating_state("s13")
        self.assertEqual((s["stars"], s["stale"], s["stale_stars"], s["version"]), (None, True, 3, 2))
        self.st.add_rating({"pose": "s13", "stars": 5})
        after = read(self.root, path)
        self.assertTrue(after.startswith(before.rstrip()[:-1].rstrip()))   # old bytes kept
        self.assertEqual(len(json.loads(after)), 2)
        self.assertEqual(self.st.rating_state("s13")["stars"], 5)
        for bad in ({"pose": "s13", "stars": 6}, {"pose": "s13", "stars": 4, "by": "claude"},
                    {"pose": "s13", "stars": True}, {"pose": "../s13", "stars": 3},
                    {"pose": "s13", "stars": 3, "aspects": {"face": 2}}):
            with self.assertRaises(store_mod.StoreError, msg=str(bad)):
                self.st.add_rating(bad)

    def test_queue_order(self):
        st = self.st
        for k, stars in (("s00", 3), ("s01", 1), ("s02", 5), ("s03", 3), ("b00", 4)):
            st.ensure_initial(k)
            st.add_rating({"pose": k, "stars": stars})
        st.ensure_initial("s04")
        st.add_rating({"pose": "s04", "stars": 2})
        st.add_version("s04", "claude", "improved")          # s04 rating turns stale
        st.ensure_initial("s05")
        st.add_rating({"pose": "s05", "stars": 1})
        st.add_version("s05", "claude", "improved")          # stale with 1 star
        st.create_note("s00", {"text": "arm stiff"})
        n = st.create_note("s00", {"text": "done one"})
        st.update_note(n["id"], {"status": "verified"})
        q = st.queue()
        keys = [e["key"] for e in q]
        self.assertEqual(keys[:5], ["s01", "s00", "s03", "b00", "s02"])   # stars asc, then checker score
        unrated = [e for e in q if e["group"] == "unrated"]
        self.assertEqual([e["key"] for e in unrated[:3]], ["s17", "s10", "s13"])   # worst checker score first
        self.assertEqual(len(unrated), 43 - 7)
        self.assertEqual(keys[-2:], ["s05", "s04"])         # stale last, lowest old stars first
        self.assertEqual([e["group"] for e in q[-2:]], ["stale", "stale"])
        s00 = q[1]
        self.assertEqual([i["type"] for i in s00["items"]], ["note"])
        self.assertTrue(q[4]["done"])
        s13 = next(e for e in q if e["key"] == "s13")
        st.create_note("s13", {"text": "hips"})
        s13 = next(e for e in st.queue() if e["key"] == "s13")
        self.assertEqual([i["type"] for i in s13["items"]], ["note", "flag", "flag"])

    def test_progress(self):
        st = self.st
        for k, s in (("s00", 5), ("s01", 5), ("s02", 3), ("b00", 5)):
            st.add_rating({"pose": k, "stars": s})
        p = st.progress()
        self.assertEqual(p["stroke"]["total"], 21)
        self.assertEqual(p["base"]["total"], 22)
        self.assertEqual(p["stroke"]["counts"], {"1": 0, "2": 0, "3": 1, "4": 0, "5": 2})
        self.assertEqual((p["stroke"]["at_5"], p["stroke"]["below_4"], p["stroke"]["unrated"]), (2, 1, 18))
        self.assertAlmostEqual(p["stroke"]["share_5"], round(2 / 21, 4))
        self.assertFalse(p["stroke"]["met"])
        self.assertEqual([h["at_5"] for h in p["stroke"]["history"]], [1, 2, 2])
        self.assertEqual(p["base"]["history"][-1]["at_5"], 1)

    def test_changelog_rewrites_only_on_change(self):
        st = self.st
        st.ensure_initial("s13")
        self.edit("s13", [{"stage": "contact", "field": "crouch_amount", "text": "0.3"}])
        st.add_version("s13", "claude", "hips")
        path = os.path.join(self.root, "pose_studio/changelog.json")
        log = json.loads(read(self.root, path))
        top = log["versions"][0]
        self.assertEqual((top["pose"], top["n"]), ("s13", 2))
        self.assertEqual([(c["field"], c["b"]) for c in top["changes"]], [("crouch_amount", "0.3")])
        m1 = os.stat(path).st_mtime_ns
        time.sleep(0.02)
        st.write_changelog()
        self.assertEqual(os.stat(path).st_mtime_ns, m1)

    def test_path_guards(self):
        for k in ("../s13", "s13/..", "..", "s1", "S13", "s13.json", "", 13):
            with self.assertRaises(store_mod.StoreError, msg=repr(k)):
                self.st.notes(k)
        for n in ("../1", "-1", "1.5", "abc", True, 10000):
            with self.assertRaises(store_mod.StoreError, msg=repr(n)):
                self.st.version_record("s13", n)
        for nid in ("../n1", "n1/..", "x1", ""):
            with self.assertRaises(store_mod.StoreError, msg=repr(nid)):
                self.st.find_note(nid)


# ---------------------------------------------------------------- tres_edit removal (link diff "removed" rows)
class StoreReviewFixTests(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.st = store_mod.Store(self.root, head_reader=fake_head(self.root))

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_stale_checker_scores_not_recorded(self):
        self.st.ensure_initial("s13")
        self.st.save_changes("s13", [{"stage": "contact", "field": "crouch_amount", "text": "0.3"}], "user", "x")
        rec = self.st.version_record("s13", 2)
        # latest.json predates this write: its score is for the old file
        self.assertEqual((rec["score"], rec["flags"]), (None, []))

    def test_changelog_failure_does_not_fail_save(self):
        self.st.ensure_initial("s13")
        def boom():
            raise OSError("disk full")
        self.st.write_changelog = boom
        r = self.st.save_changes("s13", [{"stage": "contact", "field": "crouch_amount", "text": "0.3"}], "user", "x")
        self.assertTrue(r["saved"])
        self.assertEqual(r["version"], 2)
        self.assertIn("disk full", r["changelog_error"])

    def test_long_packed_array_value_allowed(self):
        long = "PackedVector3Array(" + ", ".join(["0.1, 0.2, 0.3"] * 200) + ")"
        self.assertGreater(len(long), 400)
        self.assertEqual(tres_edit.check_change({"stage": "contact", "field": "right_elbow_path", "text": long})[2], long)
        with self.assertRaises(tres_edit.TresEditError):
            tres_edit.check_change({"stage": "contact", "field": "display_name", "text": '"' + "x" * 500 + '"'})


class TresRemoveTests(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.text = read(self.root, S13).decode("utf-8")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_remove_middle_dict_entry_one_line(self):
        new, applied = tres_edit.apply_changes(self.text, [{"stage": "windup", "field": "crouch_amount", "text": None,
                                                             "removed": True}])
        old = tres_edit.get_value(self.text, "windup", "crouch_amount")
        minus, plus = changed_lines(self.text, new)
        self.assertEqual((minus, plus), ([f'-"crouch_amount": {old},'], []))
        self.assertEqual(applied, [{"stage": "windup", "field": "crouch_amount", "from": old, "to": None}])
        self.assertIsNone(tres_edit.get_value(new, "windup", "crouch_amount"))
        self.assertIsNotNone(tres_edit.get_value(new, "finish", "crouch_amount"))

    def test_remove_last_dict_entry_fixes_comma(self):
        new, _ = tres_edit.apply_changes(self.text, [{"stage": "finish", "field": "right_elbow_swivel_deg",
                                                      "text": None, "removed": True}])
        ws = tres_edit.get_value(self.text, "finish", "elbow_swivel_weight")   # entry before the last one
        bpo = tres_edit.get_value(self.text, "finish", "right_elbow_swivel_deg")
        minus, plus = changed_lines(self.text, new)
        self.assertEqual(minus, [f'-"elbow_swivel_weight": {ws},', f'-"right_elbow_swivel_deg": {bpo}'])
        self.assertEqual(plus, [f'+"elbow_swivel_weight": {ws}'])
        # adding it back gives the original text
        back, _ = tres_edit.apply_changes(new, [{"stage": "finish", "field": "right_elbow_swivel_deg", "text": bpo}])
        self.assertEqual(back, self.text)

    def test_remove_missing_field_no_change(self):
        new, applied = tres_edit.apply_changes(self.text, [{"stage": "windup", "field": "no_such_field",
                                                             "text": None, "removed": True}])
        self.assertEqual((new, applied), (self.text, []))
        with self.assertRaises(tres_edit.TresEditError):   # text null without removed flag
            tres_edit.apply_changes(self.text, [{"stage": "windup", "field": "crouch_amount", "text": None}])


# ---------------------------------------------------------------- store: scratch folder, save, section check
class StoreSaveTests(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.scratch = tempfile.mkdtemp(prefix="pose_studio_store_")
        self.st = store_mod.Store(self.root, head_reader=fake_head(self.root), studio_dir=self.scratch)

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)
        shutil.rmtree(self.scratch, ignore_errors=True)

    def test_scratch_studio_dir(self):
        self.st.ensure_initial("s13")
        self.assertTrue(os.path.exists(os.path.join(self.scratch, "versions", "s13", "v001.tres")))
        self.assertFalse(os.path.exists(os.path.join(self.root, "pose_studio")))
        self.assertEqual(self.st.lock_path, os.path.join(os.path.realpath(self.scratch), ".pose_studio.lock"))

    def test_allowed_fields_cover_every_repo_pose(self):
        for p in glob.glob(os.path.join(REPO, "data/postures/*.tres")) + glob.glob(os.path.join(REPO, "data/base_poses/*.tres")):
            key = ("b" if "/base_poses/" in p else "s") + os.path.basename(p)[:2]
            allowed = store_mod.allowed_fields(key)
            with open(p) as f:
                for stage, vals in tres_edit.parse_values(f.read()).items():
                    self.assertIn(stage, allowed, p)
                    self.assertFalse(set(vals) - allowed[stage], (p, stage))
        self.assertEqual(sorted(store_mod.allowed_fields("b04")), ["contact"])

    def test_save_rejects_disallowed_sections(self):
        orig_s, orig_b = read(self.root, S13), read(self.root, self.st.pose_rel("b04"))
        good = {"stage": "contact", "field": "crouch_amount", "text": "0.3"}
        for key, bad in (("b04", {"stage": "windup", "field": "crouch_amount", "text": "0.3"}),
                         ("s13", {"stage": "windup", "field": "paddle_forehand_mul", "text": "0.3"}),
                         ("s13", {"stage": "contact", "field": "not_a_field", "text": "0.3"}),
                         ("s13", {"stage": "contact", "field": "script", "text": "0.3"}),
                         ("s13", {"stage": "contact", "field": "crouch_amount", "text": "0.3\nx = 1"})):
            with self.assertRaises(store_mod.StoreError, msg=str(bad)):
                self.st.save_changes(key, [good, bad], "user", "x")
        self.assertEqual(read(self.root, S13), orig_s)
        self.assertEqual(read(self.root, self.st.pose_rel("b04")), orig_b)
        for key in ("s1", "x13", "../s13", None):
            with self.assertRaises(store_mod.StoreError):
                self.st.save_changes(key, [good], "user")
        with self.assertRaises(store_mod.StoreError):
            self.st.save_changes("s13", [good], "bot")


# ---------------------------------------------------------------- CLI (--json, new subcommands)
class CliJsonTests(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        self.scratch = tempfile.mkdtemp(prefix="pose_studio_store_")
        self.env = dict(os.environ, POSE_STUDIO_ROOT=self.scratch, POSE_STUDIO_REPO=self.root)
        self.cli = os.path.join(REPO, "tools", "pose_notes.py")

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)
        shutil.rmtree(self.scratch, ignore_errors=True)

    def run_json(self, *args, ok=True):
        r = subprocess.run([sys.executable, self.cli] + list(args) + ["--json"], capture_output=True,
                           text=True, env=self.env, timeout=60)
        lines = r.stdout.splitlines()
        self.assertEqual(len(lines), 1, (args, r.stdout, r.stderr))     # exactly one JSON object
        d = json.loads(lines[0])
        self.assertEqual(d["ok"], ok, (args, d))
        self.assertEqual(r.returncode, 0 if ok else 1, (args, d))
        if not ok:
            self.assertIsInstance(d["error"], str)
        return d

    def changes_file(self, obj):
        p = os.path.join(self.scratch, "changes.json")
        with open(p, "w") as f:
            json.dump(obj, f)
        return p

    def test_save_one_line_then_no_change_then_restore(self):
        orig = read(self.root, S13)
        d = self.run_json("save", "s13", "--changes",
                          self.changes_file([{"stage": "contact", "field": "crouch_amount", "text": "0.3"}]),
                          "-m", "lower hips", "--author", "user")
        self.assertEqual((d["saved"], d["changed_lines"], d["version"], d["file"]), (True, 1, 2, S13))
        minus, plus = changed_lines(orig.decode(), read(self.root, S13).decode())
        self.assertEqual(plus, ["+crouch_amount = 0.3"])
        self.assertEqual(len(minus), 1)
        after = read(self.root, S13)
        # same value again (link diff format with key) -> byte-identical, no new version
        d = self.run_json("save", "s13", "--changes", self.changes_file(
            {"key": "s13", "changes": [{"stage": "contact", "field": "crouch_amount", "text": "0.30"}]}),
            "-m", "again", "--author", "user")
        self.assertEqual((d["saved"], d["changed_lines"], d["version"]), (False, 0, 2))
        self.assertEqual(read(self.root, S13), after)
        d = self.run_json("save", "s13", "--changes", self.changes_file([]), "--author", "claude")
        self.assertFalse(d["saved"])
        self.assertEqual(read(self.root, S13), after)
        self.assertEqual(self.run_json("versions", "s13")["current"], 2)
        # restore v001 -> the original bytes
        d = self.run_json("restore", "s13", "1")
        self.assertEqual((d["version"], d["file"]), (3, S13))
        self.assertEqual(read(self.root, S13), orig)
        vs = self.run_json("versions", "s13")
        self.assertEqual(([v["n"] for v in vs["versions"]], vs["file_matches_current"]), ([0, 1, 2, 3], True))
        self.assertEqual(vs["versions"][2]["message"], "lower hips")

    def test_save_errors(self):
        orig = read(self.root, S13)
        f = self.changes_file([{"stage": "windup", "field": "crouch_amount", "text": "0.3"}])
        self.assertIn("bad pose key", self.run_json("save", "s1", "--changes", f, "--author", "user", ok=False)["error"])
        self.assertIn("not allowed", self.run_json("save", "b04", "--changes", f, "--author", "user", ok=False)["error"])
        self.run_json("save", "s13", "--changes", f, "--author", "robot", ok=False)
        self.run_json("save", "s13", "--changes", os.path.join(self.scratch, "missing.json"), "--author", "user", ok=False)
        self.run_json("save", "s13", "--changes", self.changes_file({"key": "s00", "changes": []}), "--author", "user", ok=False)
        self.run_json("save", "s13", "--author", "user", ok=False)            # usage error is JSON too
        self.assertEqual(read(self.root, S13), orig)

    def test_version_diff_equals_edits(self):
        changes = [{"stage": "contact", "field": "crouch_amount", "text": "0.3"},
                   {"stage": "windup", "field": "hip_yaw_deg", "text": "12.0"},
                   {"stage": "finish", "field": "left_hand_offset", "text": "Vector3(-0.1, 0, -0.2)"}]
        d = self.run_json("save", "s13", "--changes", self.changes_file(changes), "-m", "three", "--author", "claude")
        self.assertEqual((d["changed_lines"], len(d["changes"])), (3, 3))
        rows = self.run_json("version-diff", "s13", "1", "2")["changes"]
        self.assertEqual(sorted((r["stage"], r["field"], r["b"]) for r in rows),
                         sorted((c["stage"], c["field"], c["text"]) for c in changes))
        self.assertEqual(self.run_json("version-diff", "s13", "2", "file")["changes"], [])
        self.assertEqual(self.run_json("version-diff", "s13", "2")["b"], "file")
        shown = self.run_json("version-show", "s13", "2")
        self.assertEqual(shown["text"].encode(), read(self.root, S13))
        self.assertEqual(shown["record"]["author"], "claude")
        self.run_json("version-show", "s13", "9", ok=False)
        self.run_json("version-diff", "s13", "../1", "2", ok=False)
        self.assertTrue(self.run_json("approve", "s13", "2")["record"]["approved"])
        self.assertFalse(self.run_json("approve", "s13", "2", "--off")["record"]["approved"])

    def test_rate_stale_after_save_and_claude_refused(self):
        self.run_json("init")
        r = self.run_json("rate", "s13", "--stars", "3", "--aspect", "body=2", "--aspect", "arm=4",
                          "--comment", "stiff", "--by", "user", "--source", "studio")["rating"]
        self.assertEqual((r["version"], r["stars"], r["aspects"], r["by"], r["source"]),
                         (1, 3, {"body": 2, "arm": 4}, "user", "studio"))
        rpath = os.path.join(self.scratch, "ratings.json")
        before = read(self.root, rpath)
        err = self.run_json("rate", "s13", "--stars", "5", "--by", "claude", ok=False)["error"]
        self.assertIn("user only", err)
        self.run_json("rate", "s13", "--stars", "6", "--by", "user", ok=False)
        self.run_json("rate", "s13", "--stars", "4", "--aspect", "face=2", "--by", "user", ok=False)
        self.run_json("rate", "s13", "--stars", "4", ok=False)                 # --by is required
        self.assertEqual(read(self.root, rpath), before)
        self.run_json("save", "s13", "--changes", self.changes_file(
            [{"stage": "contact", "field": "crouch_amount", "text": "0.3"}]), "--author", "user")
        st = self.run_json("ratings", "s13")["state"]
        self.assertEqual((st["stars"], st["stale"], st["stale_stars"], st["version"]), (None, True, 3, 2))
        q = self.run_json("queue", "--all")
        s13 = next(e for e in q["queue"] if e["key"] == "s13")
        self.assertEqual((s13["group"], s13["stale_stars"]), ("stale", 3))
        self.assertEqual(q["queue"][-1]["key"], "s13")                        # stale poses last
        p = self.run_json("progress")["progress"]
        self.assertEqual((p["stroke"]["stale"], p["stroke"]["target_share_5"], p["stroke"]["target_min_stars"]),
                         (1, 0.8, 4))
        self.assertTrue(read(self.root, rpath).startswith(before.rstrip()[:-1].rstrip()))

    def test_note_add_set_and_lists(self):
        n = self.run_json("note-add", "s13", "--kind", "request", "--text", "hips rise", "--stage", "contact",
                          "--field", "crouch_amount", "--time", "0.5")["note"]
        self.assertEqual((n["id"], n["author"], n["status"], n["stage"], n["field"], n["time"]),
                         ("n1", "user", "open", "contact", "crouch_amount", 0.5))
        self.assertEqual(tuple(n), store_mod.NOTE_KEYS)
        r = self.run_json("note-add", "s10", "--kind", "rule", "--text", "keep balance",
                          "--rule-flag", "B_balance_contact")["note"]
        self.assertEqual((r["id"], r["rule"]), ("n2", {"flag": "B_balance_contact"}))
        self.run_json("note-add", "s13", "--text", "x", "--stage", "middle", ok=False)
        self.run_json("note-add", "s13", "--text", "x", "--rule-flag", "B_x", ok=False)
        self.run_json("note-add", "s13", "--text", "", ok=False)
        self.assertEqual(len(self.run_json("list", "--open")["notes"]), 2)
        self.assertEqual(self.run_json("note-set", "n1", "--status", "addressed")["note"]["status"], "addressed")
        self.assertEqual([x["id"] for x in self.run_json("list", "--open")["notes"]], ["n2"])
        self.assertEqual(self.run_json("note-set", "n1", "--status", "reopened")["note"]["status"], "reopened")
        self.run_json("note-set", "n1", "--status", "done", ok=False)
        self.run_json("note-set", "n9", "--status", "open", ok=False)
        self.run_json("note-set", "n1", ok=False)
        d = self.run_json("reply", "n1", "--text", "lowered", "--change", "contact.crouch_amount=0.07:0.3",
                          "--evidence", "hip 0.78 -> 0.58 m", "--version", "2")
        self.assertEqual(d["note"]["status"], "addressed")
        self.assertEqual(self.run_json("show", "n1")["note"]["reply"]["evidence"], "hip 0.78 -> 0.58 m")
        with open(os.path.join(self.scratch, "notes", "s13.json"), "rb") as f:
            raw = f.read()
        self.assertTrue(raw.endswith(b"\n"))
        self.assertEqual(json.loads(raw)[0]["id"], "n1")

    def test_init_changelog_and_store_location(self):
        d = self.run_json("init")
        self.assertEqual(len(d["created"]), 43)
        self.assertEqual(self.run_json("init")["created"], [])
        self.assertTrue(os.path.exists(os.path.join(self.scratch, ".gdignore")))
        self.assertFalse(os.path.exists(os.path.join(self.root, "pose_studio")))
        v0 = self.run_json("version-show", "s13", "0")
        self.assertEqual(v0["record"]["message"], "HEAD (file not in git; working copy)")
        self.run_json("save", "s13", "--changes", self.changes_file(
            [{"stage": "contact", "field": "crouch_amount", "text": "0.3"}]), "-m", "hips", "--author", "user")
        log = self.run_json("changelog")
        self.assertEqual(log["file"], os.path.join(os.path.realpath(self.scratch), "changelog.json"))
        top = next(v for v in log["changelog"]["versions"] if v["pose"] == "s13" and v["n"] == 2)
        self.assertEqual(top["message"], "hips")      # (times are whole seconds, so order ties with init)
        self.assertEqual([(c["field"], c["b"]) for c in top["changes"]], [("crouch_amount", "0.3")])
        with open(log["file"]) as f:
            self.assertEqual(json.load(f), log["changelog"])
        self.run_json("versions", "s99", ok=False)
        self.run_json("bogus", ok=False)

    def test_text_mode_error_exit_code(self):
        r = subprocess.run([sys.executable, self.cli, "rate", "s13", "--stars", "5", "--by", "claude"],
                           capture_output=True, text=True, env=self.env, timeout=60)
        self.assertEqual((r.returncode, r.stdout), (1, ""))
        self.assertIn("user only", r.stderr)


# ---------------------------------------------------------------- bench (existing logs only)
class BenchTests(unittest.TestCase):
    def test_runs_and_compare_json(self):
        files = glob.glob(os.path.join(REPO, "logs", "bench_*.perf.jsonl"))
        tool = os.path.join(STUDIO, "bench.py")
        r = subprocess.run([sys.executable, tool, "--json"], capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(r.stdout.splitlines()), 1)
        d = json.loads(r.stdout)
        self.assertTrue(d["ok"])
        self.assertEqual(len(d["runs"]), len(files))
        for run in d["runs"]:
            for k in ("points", "shots", "endings", "endings_per_100_shots", "systems", "spikes", "jitter", "pose_trace"):
                self.assertIn(k, run)
        if files:
            self.assertGreater(sum(x["points"] for x in d["runs"]), 0)
        traced = [x["name"] for x in d["runs"] if x["pose_trace"]]
        if traced:
            r = subprocess.run([sys.executable, tool, "--json", "--compare", traced[0], traced[0]],
                               capture_output=True, text=True, timeout=180)
            c = json.loads(r.stdout)
            self.assertEqual((c["ok"], c["pose_diff"]["verdict"]), (True, "IDENTICAL"))
        r = subprocess.run([sys.executable, tool, "--json", "--compare", "../x", "y"], capture_output=True, text=True)
        self.assertEqual((r.returncode, json.loads(r.stdout)["ok"]), (1, False))


# ---------------------------------------------------------------- CLI text mode (unchanged output)
class PoseNotesCliTests(unittest.TestCase):
    def setUp(self):
        self.root = make_root()
        os.environ.pop("POSE_STUDIO_ROOT", None)
        sys.path.insert(0, os.path.join(REPO, "tools"))
        import pose_notes
        self.cli = pose_notes

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def run_cli(self, *args):
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.cli.main(["--root", self.root] + list(args))
        return out.getvalue()

    def test_cli_flow(self):
        st = store_mod.Store(self.root, head_reader=fake_head(self.root))
        st.ensure_initial("s13")
        n = st.create_note("s13", {"text": "hips rise at contact", "stage": "contact"})
        self.assertIn("1 notes", self.run_cli("list", "--open"))
        rel = st.pose_rel("s13")
        text = read(self.root, rel).decode()
        new, _ = tres_edit.apply_changes(text, [{"stage": "contact", "field": "crouch_amount", "text": "0.3"}])
        st.write_bytes(os.path.join(self.root, rel), new.encode())
        checker_ran(self.root)
        out = self.run_cli("version", "s13", "-m", "lower hips", "--note", n["id"])
        self.assertIn("s13 v002 recorded (score 58", out)
        rec = st.version_record("s13", 2)
        self.assertEqual((rec["author"], rec["notes"]), ("claude", ["n1"]))
        self.run_cli("reply", "n1", "--text", "lowered hips", "--change", "contact.crouch_amount=0.0744:0.3",
                     "--evidence", "hip 0.78 -> 0.58 m", "--version", "2")
        note = st.find_note("n1")
        self.assertEqual(note["status"], "addressed")
        self.assertEqual(note["reply"]["changes"], [{"stage": "contact", "field": "crouch_amount", "from": "0.0744", "to": "0.3"}])
        self.assertIn("0 notes", self.run_cli("list", "--open"))
        q = self.run_cli("queue")
        self.assertTrue(q.splitlines()[0].startswith("s17 unrated"), q[:200])
        self.assertIn("0 ratings", self.run_cli("ratings"))


class ServeTuningTests(unittest.TestCase):
    """tools/pose_studio/serve_tuning.py: studio serve edits -> data/serve_tuning.json "set" values."""
    def setUp(self):
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
        import serve_tuning
        self.st = serve_tuning

    def test_set_replaces_add_and_routes_paddle_deltas(self):
        data = {"0": {"windup": {"add": {"weight_shift": -0.2, "body_yaw_deg": 12}}}}
        changed, skipped = self.st.apply(data, 0, [
            {"stage": "windup", "field": "weight_shift", "text": "-0.45"},
            {"stage": "contact", "field": "ft_paddle_offset", "text": "Vector3(0, 0.1, 0.25)"},
            {"stage": "finish", "field": "gone", "text": None, "removed": True}])
        self.assertEqual(data["0"]["windup"], {"add": {"body_yaw_deg": 12}, "set": {"weight_shift": -0.45}})
        self.assertEqual(data["0"]["finish"]["set"], {"ft_paddle_offset": [0.0, 0.1, 0.25]})
        self.assertEqual((len(changed), skipped), (2, ["gone"]))

    def test_godot_text_values(self):
        self.assertIs(self.st.parse_godot("true"), True)
        self.assertEqual(self.st.parse_godot("3"), 3)
        self.assertEqual(self.st.parse_godot("Vector2(1, 2)"), [1.0, 2.0])

if __name__ == "__main__":
    unittest.main()
