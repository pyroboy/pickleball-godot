#!/usr/bin/env python3
"""Data-only pose checker: scores every pose and lists what looks wrong, worst first.
No screenshots, no bench. Plan: docs/POSE_STUDIO_SPEC.md (stage 0).

Usage: python3 tools/pose_check.py [--solve] [--all] [--baseline | --diff] [s00 b11 ...]
  (no flag)   level A: reads data/postures and data/base_poses only (instant)
  --solve     also levels B and C: one headless Godot run (about 10 s for everything) that
              solves each pose with the game's IK and samples the swing once per game tick
  --all       print every pose (default: the 15 worst) and every flag
  --baseline  remember this run; --diff then shows score changes and flags fixed / added
  keys        limit to these poses (s stroke, b body stance, v serve)
Output: a short ranked list here; everything in logs/pose_check/report.txt and latest.json.
Thresholds are judgement calls: edit the constants below.
"""
import glob, json, math, os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "logs", "pose_check")
STAGES = ("windup", "contact", "finish")
BODY = ["stance_width", "front_foot_forward", "back_foot_back", "crouch_amount", "weight_shift", "hip_yaw_deg",
        "torso_yaw_deg", "torso_pitch_deg", "torso_roll_deg", "spine_curve_deg", "body_yaw_deg", "body_pitch_deg",
        "body_roll_deg", "lead_foot", "right_foot_yaw_deg", "left_foot_yaw_deg", "left_hand_offset", "head_pitch_deg"]
TIMING = ["charge_duration", "ft_duration_strike", "ft_duration_sweep", "ft_duration_settle", "ft_duration_hold"]
STORY = ["weight_shift", "hip_yaw_deg", "torso_yaw_deg"]
GAMEPLAY = ["paddle_forehand_mul", "paddle_forward_mul", "paddle_y_offset", "has_zone", "zone_x_min", "zone_x_max",
            "zone_y_min", "zone_y_max", "zone_forward_offset", "paddle_floor_clearance", "speed_strike_start", "speed_strike_end", "speed_strike_points"] + TIMING
HOLDS = {"s08", "s09", "s20"}            # charge and ready poses: held, not swung
OVERHEADS = {"s03", "s04"}
JUMPS = {"b15", "b16"}
FAMILIES = {"forehand": ["s00", "s13", "s05"], "forward": ["s01", "s15", "s06"], "backhand": ["s02", "s14", "s07"],
            "wide forehand": ["s10", "s16", "s18"], "wide backhand": ["s11", "s17", "s19"]}
WEIGHT = {3: 12, 2: 6, 1: 3}             # score cost per flag severity
# ---- thresholds ----
FLIP_DEG = 30.0                  # elbow swivel step per game tick that reads as a flip
FLIP_MOVE_M = 0.12                # ...and the elbow really jumps this far in that tick
FLIP_OFF_M = 0.08                # ...only while the elbow is this far off the shoulder-wrist line (bent arm)
STRAIGHT_LEG = 21.0      # knee bend at or under this: leg fully straight
STRAIGHT_ARM = 15.0      # elbow bend under this: arm locked
WRIST_FLEX = 55.0        # wrist bent across the paddle face beyond this
WRIST_ANGLE = 100.0      # forearm to handle beyond this
FACE_OFF_NET = 25.0      # paddle face away from the net at contact
POP_UP = 0.08            # hips higher at contact than at both other stages (m)
LEAN_FWD, LEAN_SIDE = 35.0, 20.0
MIN_TRANSFER = 0.30      # centre of gravity back -> front gain from wind-up to finish
CORNER, SNAP, ROLL_STEP, WRIST_STEP, ELBOW_JUMP = 30.0, 30.0, 40.0, 30.0, 0.15
CLEARANCE = 0.10         # elbow to torso (m); rough rule, only for captures without "clip"
CLIP_PARTS = {"sleeve": "sleeve", "elbow": "elbow", "fore": "forearm", "paddle": "paddle"}   # timed "clip" (pose_data.gd)
POP = 0.25               # joint travel in one game tick outside the strike (m)


def val(s):
    s = s.strip().rstrip(",")
    m = re.match(r"Vector3\(([^)]*)\)", s)
    if m:
        return tuple(round(float(x), 4) for x in m.group(1).split(","))
    try:
        return round(float(s), 4)
    except ValueError:
        return s


def parse(text):
    """-> (main fields, wind-up keyframe values or None, finish keyframe values or None)"""
    subs = {}
    for m in re.finditer(r'\[sub_resource type="Resource" id="([^"]+)"\]\n(.*?)(?=\n\[)', text, re.S):
        subs[m.group(1)] = {k: val(v) for k, v in re.findall(r'"(\w+)": ([^\n]*)', m.group(2))}
    main = {k: val(v) for k, v in re.findall(r"\n(\w+) = ([^\n]*)", text[text.index("\n[resource]"):])}

    def sub(k):
        m = re.match(r'SubResource\("([^"]+)"\)', str(main.get(k, "")))
        return subs.get(m.group(1)) if m else None
    return main, sub("windup_body"), sub("follow_through_body")


def load_files():
    poses = {}
    for pre, folder in (("s", "data/postures"), ("b", "data/base_poses")):
        for f in sorted(glob.glob(os.path.join(ROOT, folder, "*.tres"))):
            key = pre + os.path.basename(f)[:2]
            main, wind, fin = parse(open(f).read())
            poses[key] = {"file": os.path.relpath(f, ROOT), "name": main.get("display_name", "").strip('"'),
                          "main": main, "windup": wind, "finish": fin}
    return poses


class Report:
    def __init__(self):
        self.flags = {}      # key -> [(severity, id, text)]

    def add(self, key, sev, fid, text):
        self.flags.setdefault(key, []).append((sev, fid, text))

    def score(self, key):
        return max(0, 100 - sum(WEIGHT[s] for s, _, _ in self.flags.get(key, [])))


def stage_val(p, stage, field):
    src = p["main"] if stage == "contact" else p[stage]
    if src is None:
        return None
    return src.get(field, p["main"].get(field))


# ---------------- level A: files only ----------------
def level_a(poses, rep, keys):
    for group in ("s", "b"):
        ks = [k for k in poses if k[0] == group]
        block = {k: tuple(poses[k]["main"].get(f) for f in BODY) for k in ks}
        for k in ks:
            if k not in keys:
                continue
            same = [o for o in ks if o != k and block[o] == block[k]]
            near = [o for o in ks if o != k and o not in same and sum(a != b for a, b in zip(block[o], block[k])) <= 3]
            if same:
                rep.add(k, 3, "A_same_body", "body identical to " + ", ".join(same))
            if near:
                rep.add(k, 1, "A_near_body", f"body nearly the same as {len(near)} other poses ({', '.join(near[:4])})")
    strokes = [k for k in poses if k[0] == "s" and k not in HOLDS]
    timing = {k: tuple(poses[k]["main"].get(f) for f in TIMING) for k in strokes}
    story = {k: tuple(stage_val(poses[k], st, f) for st in STAGES for f in STORY) for k in strokes}
    for k in strokes:
        if k not in keys:
            continue
        share = [o for o in strokes if o != k and timing[o] == timing[k]]
        if len(share) >= 3:
            rep.add(k, 1, "A_timing", f"timing shared with {len(share)} other strokes")
        copy = [o for o in strokes if o != k and story[o] == story[k]]
        if copy:
            rep.add(k, 2, "A_story", "weight shift and turn values copied from " + ", ".join(copy[:4]))
        crouch = [stage_val(poses[k], st, "crouch_amount") for st in STAGES]
        if None not in crouch and max(crouch) - min(crouch) < 0.005:
            rep.add(k, 1, "A_static_legs", f"crouch never changes ({crouch[1]}): no leg drive")


def changed_vs_head(poses, keys):
    lines = []
    for k in sorted(keys):
        if k not in poses:
            continue
        try:
            old = subprocess.run(["git", "show", "HEAD:" + poses[k]["file"]], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        except subprocess.CalledProcessError:
            continue
        om, ow, of = parse(old)
        nm = poses[k]["main"]
        main_diff = sorted(f for f in set(om) | set(nm) if om.get(f) != nm.get(f) and not str(nm.get(f, "")).startswith("SubResource"))
        key_diff = sum(1 for a, b in ((ow, poses[k]["windup"]), (of, poses[k]["finish"])) for f in set(a or {}) | set(b or {}) if (a or {}).get(f) != (b or {}).get(f))
        if main_diff or key_diff:
            game = [f for f in main_diff if f in GAMEPLAY]
            lines.append(f"  {k} {poses[k]['name']}: {len(main_diff) + key_diff} fields" + (f", gameplay: {', '.join(game)}" if game else ""))
    return lines


# ---------------- levels B and C: solved poses ----------------
def find_godot():
    cands = [os.environ.get("GODOT"), shutil.which("godot"), "/Applications/Godot.app/Contents/MacOS/Godot",
             os.path.expanduser("~/Documents/Codex/2026-10-15/task/duos-integration/toolchain/Godot.app/Contents/MacOS/Godot")]
    for c in cands:
        if c and os.access(c, os.X_OK):
            return c
    sys.exit("Godot not found, set GODOT=/path/to/Godot")


def solve(only):
    raw = os.path.join(OUT, "raw")
    shutil.rmtree(raw, ignore_errors=True)
    os.makedirs(raw)
    args = [find_godot(), "--headless", "--path", ROOT, "--fixed-fps", "60", "res://scenes/game.tscn", "--", "--pose-data=" + raw]
    if only:
        args.append("--pose-only=" + ",".join(only))
    if "--elbow-authored" in sys.argv:   # experiment: paddle elbow without the game's wrist correction
        args.append("--pose-elbow-authored")
    with open(os.path.join(OUT, "godot.log"), "w") as log:
        subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, timeout=300)
    errs = [l for l in open(os.path.join(OUT, "godot.log")) if "SCRIPT ERROR" in l or "Parse Error" in l]
    if errs:
        print(f"Godot reported {len(errs)} script errors, first: {errs[0].strip()}")
    return {d["key"]: d for d in (json.load(open(f)) for f in sorted(glob.glob(os.path.join(raw, "*.json"))))}


def level_b(solved, rep):
    for k, d in solved.items():
        st = d["stages"]
        swung = k[0] != "b" and len(st) == 3 and k not in HOLDS
        for name, m in st.items():
            tag = f"{name}: " if len(st) > 1 else ""
            if not m["com_over_base"]:
                rep.add(k, 3, "B_balance_" + name, f"{tag}off balance, centre of gravity {m['com_off_base_m']:.2f} m off the feet")
            if not m["feet_planted"] and k not in JUMPS:
                rep.add(k, 3, "B_feet_" + name, f"{tag}a foot is off the ground")
            if m["trunk_lean_fwd"] > LEAN_FWD:
                rep.add(k, 2, "B_lean_fwd_" + name, f"{tag}bends at the waist {m['trunk_lean_fwd']:.0f} deg")
            if abs(m["trunk_lean_side"]) > LEAN_SIDE:
                rep.add(k, 1, "B_lean_side_" + name, f"{tag}leans sideways {m['trunk_lean_side']:.0f} deg")
            if k[0] == "b" or k in HOLDS:
                continue
            if abs(m["wrist_flex_deg"]) > WRIST_FLEX or m["wrist_angle_deg"] > WRIST_ANGLE:
                rep.add(k, 2, "B_wrist_" + name, f"{tag}wrist bent hard (angle {m['wrist_angle_deg']:.0f}, flex {m['wrist_flex_deg']:.0f} deg)")
            if m["elbow_above_shoulder_m"] > 0.03 and k not in OVERHEADS and k[0] == "s":
                rep.add(k, 2, "B_elbow_up_" + name, f"{tag}elbow {m['elbow_above_shoulder_m']:.2f} m above the shoulder")
        if not swung:
            continue
        c = st["contact"]
        if k[0] == "s" and c["face_to_net_deg"] > FACE_OFF_NET:
            rep.add(k, 2, "B_face", f"paddle face {c['face_to_net_deg']:.0f} deg away from the net at contact")
        hips = [st[s]["hip_height"] for s in STAGES]
        if hips[1] - max(hips[0], hips[2]) > POP_UP and k not in OVERHEADS:   # overheads extend up on purpose
            rep.add(k, 3, "B_pop_up", f"body pops up at contact (hips {hips[0]:.2f} > {hips[1]:.2f} > {hips[2]:.2f} m)")
        elbows = [st[s]["right_elbow_bend"] for s in STAGES]
        if max(elbows) < STRAIGHT_ARM and k not in OVERHEADS:
            rep.add(k, 3, "B_arm_locked", f"arm stays straight through the whole swing (elbow {elbows[0]:.0f}/{elbows[1]:.0f}/{elbows[2]:.0f} deg)")
        elif elbows[1] < STRAIGHT_ARM and k not in OVERHEADS:
            rep.add(k, 2, "B_arm_straight", f"arm locked straight at contact (elbow {elbows[1]:.0f} deg)")
        legs = [s for s in STAGES if min(st[s]["left_knee_bend"], st[s]["right_knee_bend"]) <= STRAIGHT_LEG]
        if legs:
            rep.add(k, 1, "B_leg_straight", "a leg is fully straight at " + ", ".join(legs))
        cog = [st[s]["com_back_to_front"] for s in STAGES]
        if cog[2] - cog[0] < MIN_TRANSFER:
            rep.add(k, 2, "B_transfer", f"little weight transfer (back to front {cog[0]:.2f} > {cog[1]:.2f} > {cog[2]:.2f})")
        elif not cog[0] < cog[1] < cog[2]:
            rep.add(k, 2, "B_transfer_order", f"weight does not move steadily forward ({cog[0]:.2f} > {cog[1]:.2f} > {cog[2]:.2f})")
        if abs(st["windup"]["separation"]) < 10 and k[0] == "s":
            rep.add(k, 1, "B_coil", f"shoulders barely turn past the hips in the wind-up ({st['windup']['separation']:.0f} deg)")
    # Lower contact should mean lower hips inside each family.
    for fam, members in FAMILIES.items():
        got = [(solved[k]["stages"]["contact"]["paddle_head"][1], solved[k]["stages"]["contact"]["hip_height"], k) for k in members if k in solved]
        got.sort(reverse=True)
        for (ph_hi, hip_hi, k_hi), (ph_lo, hip_lo, k_lo) in zip(got, got[1:]):
            if hip_lo > hip_hi + 0.03:
                rep.add(k_lo, 3, "B_family_height", f"contact is lower than {k_hi} (paddle {ph_lo:.2f} vs {ph_hi:.2f} m) but the hips are higher ({hip_lo:.2f} vs {hip_hi:.2f} m)")


def _swivel(sh, wr, pt, outward):
    """Elbow swivel around the shoulder-wrist line, degrees: 0 = elbow down, + = out from the body."""
    sub = lambda a, b: [a[i] - b[i] for i in range(3)]
    dot = lambda a, b: sum(a[i] * b[i] for i in range(3))
    def unit(v):
        l = math.sqrt(dot(v, v)); return [x / l for x in v] if l > 1e-9 else None
    perp = lambda v, ax: sub(v, [x * dot(v, ax) for x in ax])
    ax = unit(sub(wr, sh))
    if ax is None: return None, 0.0
    d = unit(perp([0, -1, 0], ax))
    if d is None: return None, 0.0
    o = perp(outward, ax); o = unit(sub(o, [x * dot(o, d) for x in d]))
    e = perp(sub(pt, sh), ax)
    if o is None: return None, 0.0
    return math.degrees(math.atan2(dot(e, o), dot(e, d))), math.sqrt(dot(e, e))

def elbow_flip(fr):
    """Worst one-tick swivel jump of the paddle elbow while the arm is bent (elbow > FLIP_OFF_M off
    the shoulder-wrist line), with its cause from the captured pole steps (pose_data.gd `pole`):
    the blend of the authored pole, or the game's wrist conditioning (ArmAnatomy.conditioned_pole)."""
    if not fr or "pole" not in fr[0] or "wrist" not in fr[0]["pole"]:
        return None
    wrap = lambda a: (a + 180) % 360 - 180
    rows = []
    for x in fr:
        j, p = x["j"], x["pole"]
        out = [j["r_shoulder"][0] - j["l_shoulder"][0], 0.0, j["r_shoulder"][2] - j["l_shoulder"][2]]
        act, off = _swivel(j["r_shoulder"], p["wrist"], j["r_elbow"], out)
        aut, _ = _swivel(j["r_shoulder"], p["wrist"], p["authored"], out)
        rows.append((act, aut, off, x["t"]))
    worst = None
    for i in range(1, len(rows)):
        (a0, u0, o0, _), (a1, u1, o1, t) = rows[i - 1], rows[i]
        if None in (a0, a1, u0, u1) or min(o0, o1) < FLIP_OFF_M:
            continue
        moved = math.dist(fr[i - 1]["j"]["r_elbow"], fr[i]["j"]["r_elbow"])
        da, du = abs(wrap(a1 - a0)), abs(wrap(u1 - u0))
        # The angle is unreliable where the arm points near straight down / up: also ask for a
        # real elbow jump.
        if da > FLIP_DEG and moved > FLIP_MOVE_M and (worst is None or da > worst["deg"]):
            cause = "the authored pole flips in the blend" if du >= 0.6 * da else "a game step after the pose turns it"
            worst = {"deg": da, "t": t, "cause": cause, "authored_deg": du, "moved_m": moved}
    return worst

def level_c(solved, rep):
    for k, d in solved.items():
        sw, timed = d.get("swing"), d.get("timed")
        if not sw or k in HOLDS:
            continue
        if sw["sharpest_corner_deg"] > CORNER:
            rep.add(k, 2 if sw["sharpest_corner_deg"] > 60 else 1, "C_corner", f"paddle path has a {sw['sharpest_corner_deg']:.0f} deg corner at {sw['corner_at']:.2f}")
        if sw["max_elbow_bend_step_deg"] > SNAP:
            rep.add(k, 2, "C_elbow_snap", f"elbow snaps {sw['max_elbow_bend_step_deg']:.0f} deg in one step at {sw['snap_at']:.2f}")
        if sw["max_elbow_jump_m"] > ELBOW_JUMP:
            rep.add(k, 2, "C_elbow_jump", f"elbow jumps {sw['max_elbow_jump_m']:.2f} m in one step")
        if sw.get("max_forearm_roll_step_deg", 0) > ROLL_STEP:
            rep.add(k, 2, "C_roll", f"forearm rolls {sw['max_forearm_roll_step_deg']:.0f} deg in one step")
        if sw.get("max_wrist_step_deg", 0) > WRIST_STEP:
            rep.add(k, 2, "C_wrist_step", f"wrist flips {sw['max_wrist_step_deg']:.0f} deg in one step")
        has_clip = any("clip" in f for f in (timed or {}).get("frames", []))
        if not has_clip and sw["min_elbow_torso_clearance_m"] < CLEARANCE:
            rep.add(k, 2, "C_clearance", f"elbow passes {sw['min_elbow_torso_clearance_m']:.2f} m from the torso")
        ups = len(sw.get("elbow_up_steps", []))
        if ups and k not in OVERHEADS and k[0] == "s":
            rep.add(k, 2 if ups > 10 else 1, "C_elbow_up", f"elbow points up for {ups} of 41 steps")
        if sw.get("elbow_inward_steps", 0) >= 35:
            rep.add(k, 1, "C_elbow_in", "elbow tucked in toward the torso for the whole swing")
        if not timed or not timed.get("frames"):
            continue
        fr, start, hit = timed["frames"], timed["prefix"], timed["contact_at"]
        speed = lambda j, i: math.dist(fr[i]["j"][j], fr[i - 1]["j"][j]) / timed["tick"]
        prep = max((speed("paddle", i) for i in range(1, len(fr)) if fr[i]["t"] <= start), default=0.0)
        strike = max((speed("paddle", i) for i in range(1, len(fr)) if start < fr[i]["t"] <= hit + timed["tick"]), default=0.0)
        if strike < prep:
            rep.add(k, 2, "C_no_swing", f"paddle moves faster getting ready ({prep:.1f} m/s) than into contact ({strike:.1f} m/s)")
        turn = lambda i: abs((fr[i]["shoulder_yaw"] - fr[i - 1]["shoulder_yaw"] + 180) % 360 - 180)
        peak = max(range(1, len(fr)), key=turn)
        if fr[peak]["t"] > hit + 1.5 * timed["tick"] and turn(peak) > 5:
            rep.add(k, 2, "C_late_turn", f"shoulders turn fastest {fr[peak]['t'] - hit:.2f} s after contact, not into it")
        pops = [(math.dist(fr[i]["j"][j], fr[i - 1]["j"][j]), j, fr[i]["t"]) for i in range(1, len(fr)) for j in fr[i]["j"]
                if j != "paddle" and not (start < fr[i]["t"] <= hit + 2 * timed["tick"])]
        worst = max(pops, default=(0, "", 0))
        if worst[0] > POP:
            rep.add(k, 2, "C_pop", f"{worst[1]} jumps {worst[0]:.2f} m in one tick at {worst[2]:.2f} s")
        for label, span in (("C_clip_ready", lambda t: t <= start), ("C_clip_swing", lambda t: t > start)):
            hits = [(f["t"], part) for f in fr if "clip" in f and span(f["t"])
                    for part in ("sleeve", "elbow", "fore", "paddle")
                    if ((not f["clip"][part]) if part == "sleeve" else f["clip"][part] > 0)]
            if hits:
                parts = sorted({CLIP_PARTS[p] for _, p in hits})
                t0, t1 = min(t for t, _ in hits), max(t for t, _ in hits)
                when = "Ready -> Wind-up" if label == "C_clip_ready" else "the swing"
                rep.add(k, 2, label, f"{', '.join(parts)} through the body {t0:.2f}-{t1:.2f} s ({len({t for t, _ in hits})} ticks, {when})")
        flip = elbow_flip(fr)
        if flip:
            rep.add(k, 2, "C_elbow_flip", f"elbow swings {flip['deg']:.0f} deg around the arm ({flip['moved_m'] * 100:.0f} cm) in one tick at {flip['t']:.2f} s ({flip['cause']})")


def main():
    args = sys.argv[1:]
    flags = {a for a in args if a.startswith("--")}
    only = [a for a in args if not a.startswith("--")]
    os.makedirs(OUT, exist_ok=True)
    poses = load_files()
    keys = set(only) if only else set(poses)
    rep = Report()
    level_a(poses, rep, keys)
    solved = {}
    if "--solve" in flags:
        solved = solve(only)
        level_b(solved, rep)
        level_c(solved, rep)
        keys |= set(solved)
    names = {k: (solved[k]["name"] if k in solved else poses[k]["name"]) for k in keys if k in solved or k in poses}
    ranked = sorted(names, key=lambda k: (rep.score(k), k))
    lines = []
    for k in ranked:
        fl = sorted(rep.flags.get(k, []), key=lambda f: -f[0])
        lines.append((rep.score(k), k, names[k], fl))
    with open(os.path.join(OUT, "report.txt"), "w") as f:
        for score, k, name, fl in lines:
            f.write(f"{score:3d}  {k} {name}\n" + "".join(f"       [{s}] {t}\n" for s, _, t in fl))
    latest = {k: {"score": score, "flags": {fid: t for _, fid, t in fl}} for score, k, _, fl in lines}
    json.dump(latest, open(os.path.join(OUT, "latest.json"), "w"), indent=1)
    base_path = os.path.join(OUT, "baseline.json")
    if "--baseline" in flags:
        shutil.copy(os.path.join(OUT, "latest.json"), base_path)
    level = "files, solved pose, motion" if solved else "files only (add --solve for solved pose and motion)"
    print(f"Pose check ({level}): {len(lines)} poses, {sum(len(l[3]) for l in lines)} flags. Full list: logs/pose_check/report.txt")
    if "--diff" in flags and os.path.exists(base_path):
        base = json.load(open(base_path))
        print("Against baseline:")
        for score, k, name, fl in lines:
            b = base.get(k)
            if not b:
                continue
            fixed = [t for fid, t in b["flags"].items() if fid not in latest[k]["flags"]]
            new = [t for fid, t in latest[k]["flags"].items() if fid not in b["flags"]]
            if fixed or new or b["score"] != score:
                print(f"  {k} {name}: {b['score']} -> {score}" + "".join(f"\n     fixed: {t}" for t in fixed) + "".join(f"\n     NEW:   {t}" for t in new))
        return
    show = lines if "--all" in flags else lines[:15]
    for score, k, name, fl in show:
        top = fl if "--all" in flags else fl[:3]
        more = f" (+{len(fl) - len(top)} more)" if len(fl) > len(top) else ""
        print(f"{score:3d}  {k} {name}: " + ("; ".join(t for _, _, t in top) if top else "clean") + more)
    changed = changed_vs_head(poses, keys)
    if changed:
        print(f"Changed since the last commit ({len(changed)} poses):")
        print("\n".join(changed))


if __name__ == "__main__":
    main()
