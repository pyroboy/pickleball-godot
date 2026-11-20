extends "res://scripts/debug/pose_shots.gd"
## Data-only pose capture behind tools/pose_check.py: the pose_shots metrics without any
## screenshots, so it runs headless. Adds joint positions and "timed": the swing sampled on
## the editor's elapsed-time timeline (runtime motion, full charge) once per game tick.
## Args (after --): --pose-data=<abs dir> [--pose-only=s00,b11,v00] [--pose-settle=N]
## Output: <dir>/<key>_now.json per pose, then quits. Loaded by perf_monitor.gd.

const TICK := 1.0 / 30.0
const TIMED_KEYS := ["com_back_to_front", "com_over_base", "com_off_base_m", "feet_planted", "hip_yaw",
	"shoulder_yaw", "separation", "hip_height", "left_knee_bend", "right_knee_bend", "right_elbow_bend",
	"trunk_lean_fwd", "trunk_lean_side", "wrist_angle_deg", "wrist_flex_deg", "elbow_above_shoulder_m"]
var settle := 12

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pose-only="): only = a.trim_prefix("--pose-only=").split(",")
		if a.begins_with("--pose-settle="): settle = int(a.trim_prefix("--pose-settle="))
		if a == "--pose-elbow-authored": load("res://scripts/player_arm_ik.gd").paddle_elbow_wrist_correction = false
	super._ready()

func _capture(ed, index: int, key: String, tag: String) -> void:
	ed._select_pose(index)
	await _frames(3)
	var report := {"key": key, "tag": tag, "name": String(ed._current.display_name), "stages": {}}
	var moving: bool = not ed._base and ed._has_motion()
	var stages: Array = [0, 1, 2] if moving else [1]
	for st in stages:
		ed._select_stage(st)
		await _frames(settle)
		var m: Dictionary = _body_metrics(ed._preview.player)
		m["joints"] = _joints(ed._preview.player)
		report.stages[STAGES[st]] = m
	if moving:
		report["path"] = _path_metrics(ed._current, ed._serve)
		report["swing"] = await _swing_trace(ed)
		report["timed"] = await _timed_trace(ed)
	var f := FileAccess.open(out_dir.path_join("%s_%s.json" % [key, tag]), FileAccess.WRITE)
	f.store_string(JSON.stringify(report))

func _r3(v: float) -> float: return snappedf(v, 0.001)

# Joint positions in the player-local frame (x forehand side, y up from the floor, z to the net), metres.
func _joints(p) -> Dictionary:
	var ll = p.left_leg_node
	var rl = p.right_leg_node
	var la = p.left_arm_node
	var ra = p.right_arm_node
	var nodes := {"hips": p.body_pivot.get_node("HipsMesh"), "torso": p.body_pivot.get_node("TorsoMesh"),
		"head": p.body_pivot.get_node("TorsoMesh/HeadMesh"),
		"l_hip": ll.thigh_pivot, "r_hip": rl.thigh_pivot, "l_knee": ll.shin_pivot, "r_knee": rl.shin_pivot,
		"l_ankle": ll.foot_pivot, "r_ankle": rl.foot_pivot,
		"l_shoulder": la.upper_pivot, "r_shoulder": ra.upper_pivot, "l_elbow": la.forearm_pivot,
		"r_elbow": ra.forearm_pivot, "l_wrist": la.hand_pivot, "r_wrist": ra.hand_pivot,
		"paddle": p.paddle_node.get_node("Head")}
	var out := {}
	for name in nodes:
		var g: Vector3 = nodes[name].global_position
		if name == "r_elbow" or name == "l_elbow": g = preload("res://scripts/elbow_swivel.gd").visual_elbow_now(ra if name == "r_elbow" else la)   # drawn elbow
		var v: Vector3 = _local(p, g)
		out[name] = [_r3(v.x), _r3(v.y), _r3(v.z)]
	return out

# The swing in real time: Charge -> release with runtime motion, one sample per game tick.
func _timed_trace(ed) -> Dictionary:
	var tl = ed._timeline
	tl._seek(0.0)
	await _frames(2)
	if not tl.active: return {}
	var seq = tl.sequence
	var total: float = seq.duration
	var frames: Array = []
	for k in int(ceil(total / TICK)) + 1:
		var t: float = minf(k * TICK, total)
		tl._seek(t / maxf(total, 0.001))
		await _frames(2)
		var m: Dictionary = _body_metrics(ed._preview.player)
		var row := {"t": _r3(t), "progress": _r3(ed._progress), "phase": String(tl.sample.get("phase", "")),
			"j": _joints(ed._preview.player)}
		for key in TIMED_KEYS: row[key] = m[key]
		var pole = _authored_pole(ed._preview.player, ed._preview.pose)
		if pole != null: row["pole"] = pole
		frames.append(row)
	var out := {"tick": TICK, "duration": _r3(total), "prefix": _r3(seq.prefix_seconds),
		"contact_at": _r3(seq.prefix_seconds + seq.release_seconds),
		"finish_at": _r3(seq.prefix_seconds + seq.stroke_seconds), "frames": frames}
	tl.invalidate()
	ed._stop()
	return out

## The paddle arm's authored elbow pole in the player's frame (as `j`), before the game's
## stabilize / wrist conditioning (player_arm_ik.gd): the elbow swivel the pose asks for.
func _authored_pole(p, shown = null):
	if p == null or p.arm_ik == null: return null
	var def = shown if shown != null else p.get_runtime_posture_def()   # the preview solves its shown pose
	if def == null: return null
	var left: bool = def.paddle_hand == 1
	var arm = p.left_arm_node if left else p.right_arm_node
	if arm == null: return null
	var fh: Vector3 = p._get_forehand_axis()
	var fw: Vector3 = p._get_forward_axis()
	var side: float = -1.0 if left else 1.0
	var pole: Vector3 = def.left_elbow_pole if left else def.right_elbow_pole
	var w: Vector3 = p.global_position + fh * 0.5 * side + Vector3.DOWN + fw * -0.5
	if pole.length_squared() > 1e-10: w = p.global_position + fh * pole.x + Vector3.UP * pole.y + fw * pole.z
	w = p.arm_ik._rotate_shoulder_pole(arm, w, def.left_shoulder_rotation_deg if left else def.right_shoulder_rotation_deg)
	var out := {"authored": _lv(p, w)}
	# The game's two corrections, replayed as player_arm_ik.gd does them (read-only).
	var hands = p.arm_ik._hands
	if hands != null and p.paddle_node != null:
		const Anatomy = preload("res://scripts/arm_anatomy.gd")
		const Hand = preload("res://scripts/player_hand_presentation.gd")
		const Size = preload("res://scripts/paddle_dimensions.gd")
		var offset: Vector3 = def.left_hand_offset if left else def.right_hand_offset
		var target: Vector3 = p.paddle_node.to_global(Size.MAIN_GRIP_OFFSET + offset)
		var mount: Transform3D = hands.main_mount(arm, target, p.paddle_node.global_basis, def)
		var wrist: Vector3 = Hand.wrist_for(arm, mount)
		var distal: Vector3 = mount.basis * arm.articulated_hand.anatomical_basis.x
		var sh: Vector3 = arm.upper_pivot.global_position
		var ref: Vector3 = fh
		var between = p._between_point_owner() if p.has_method("_between_point_owner") else null
		if between != null: ref = fh.rotated(Vector3.UP, -deg_to_rad(def.body_yaw_deg))
		var ik_script = load("res://scripts/player_arm_ik.gd")
		var st: Vector3 = Anatomy.stabilized_pole(sh, wrist, w, -ref * side)
		var co: Vector3 = Anatomy.conditioned_pole(sh, wrist, st, distal, arm.upper_arm_length, arm.forearm_length) if ik_script.paddle_elbow_wrist_correction else st
		out["stabilized"] = _lv(p, st); out["conditioned"] = _lv(p, co); out["wrist"] = _lv(p, wrist)
		var sw: float = clampf(float(def.elbow_swivel_weight), 0.0, 1.0) if "elbow_swivel_weight" in def else 0.0
		if sw > 0.0:   # the pose's swivel replaces the guide point: that is what the pose asks for
			const Swivel = preload("res://scripts/elbow_swivel.gd")
			var fr: Array = Swivel.frame(def, fh, fw, left)
			var sp: Vector3 = Swivel.mix(sh, wrist, co, fr[0], fr[1], def.left_elbow_swivel_deg if left else def.right_elbow_swivel_deg, left, sw)
			out["authored"] = _lv(p, sp); out["conditioned"] = _lv(p, sp); out["swivel_weight"] = sw
			var rest: Vector3 = (fr[1] + fr[0] * Swivel.REST_OUT).normalized()
			out["rest_dot"] = snappedf(rest.dot((wrist - sh).normalized()), 0.001)
			out["swivel_deg"] = snappedf(def.left_elbow_swivel_deg if left else def.right_elbow_swivel_deg, 0.1)
			out["legacy_deg"] = snappedf(Swivel.angle(sh, wrist, co, fr[0], fr[1], left), 0.1)
	return out

func _lv(p, w: Vector3) -> Array:
	var v: Vector3 = _local(p, w)
	return [_r3(v.x), _r3(v.y), _r3(v.z)]
