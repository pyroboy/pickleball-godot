extends Node
## Dev tool behind tools/pose_review.sh. Drives the mobile pose editor preview and, per pose and
## stage (wind-up / contact / finish), saves screenshots (paddle trace, ghosts, contact box) and
## body metrics (feet, centre of gravity, hip/shoulder turn, knees, elbow, paddle path) as JSON.
## Args (after --): --pose-shots=<abs dir> [--pose-only=s00,b11,v00]  (s stroke, b body, v serve) [--pose-before=<abs dir>]
##   --pose-before: dir holding older copies as postures/<file>.tres and base_poses/<file>.tres;
##   each pose found there is captured twice, tagged "before" and "after" (else tagged "now").
## Output: <dir>/<key>_<tag>_<stage>_<view>.png and <dir>/<key>_<tag>.json, then quits.
## Not loaded unless --pose-shots is passed (see perf_monitor.gd).

const Path = preload("res://scripts/stroke_swing_path.gd")
const ServeStore = preload("res://scripts/mobile_serve_pose_store.gd")
const RuntimePreview = preload("res://scripts/runtime_motion_preview.gd")
const Styles = preload("res://scripts/serve_style.gd")
const VIEWS := ["front", "side"]
const STAGES := ["windup", "contact", "finish"]
const SETTLE_FRAMES := 45
var out_dir := ""
var before_dir := ""
var only: PackedStringArray = []
var from_rest := false  # --pose-from-rest: trace serves from the held pose, not just the strike
var strip := false  # --pose-strip: save a frame every 4 swing-trace steps

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pose-before="): before_dir = a.trim_prefix("--pose-before=")
		if a == "--pose-strip": strip = true
		if a == "--pose-from-rest": from_rest = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var game: Node = null
	for i in 600:
		await _frames(1)
		game = get_tree().current_scene
		if game and game.has_method("open_mobile_pose_editor") and game.get("player_left"): break
	await _frames(30)
	game.open_mobile_pose_editor()
	await _frames(20)
	var ed = game.mobile_pose_editor
	for z in 3: ed._preview.zoom(0.3)  # zoom out so both feet stay in frame
	ed._preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for mode in ["s", "b", "v"]:  # strokes, body stances, serves
		ed._select_workspace({"s": 0, "b": 1, "v": 2}[mode])
		await _frames(3)
		for i in ed._definitions.size():
			var def: Resource = ed._definitions[i]
			var id: int = def.base_pose_id if mode == "b" else ServeStore.style_id(def) if mode == "v" else def.posture_id
			var key := "%s%02d" % [mode, id]
			if not only.is_empty() and not only.has(key): continue
			var copy_key: String = {"s": "stroke:", "b": "base:", "v": "serve:"}[mode] + str(id)
			var old: Resource = null if mode == "v" else _load_before(def)
			if old != null:
				ed._definitions[i] = old
				ed._copies.erase(copy_key)
				await _capture(ed, i, key, "before")
				ed._definitions[i] = def
				ed._copies.erase(copy_key)
			await _capture(ed, i, key, "after" if old != null else "now")
	get_tree().quit()

func _load_before(def: Resource) -> Resource:
	if before_dir == "": return null
	var sub := "base_poses" if def is BasePoseDefinition else "postures"
	var path := before_dir.path_join(sub).path_join(def.resource_path.get_file())
	if not FileAccess.file_exists(path): return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)

func _capture(ed, index: int, key: String, tag: String) -> void:
	ed._select_pose(index)
	await _frames(3)
	var report := {"key": key, "tag": tag, "name": String(ed._current.display_name), "stages": {}}
	var stages: Array = [1] if ed._base or not ed._has_motion() else [0, 1, 2]
	for st in stages:
		ed._select_stage(st)
		for view in VIEWS:
			ed._preview.view(view)
			var yaw: float = ed._preview.yaw
			var pitch: float = ed._preview.pitch
			for k in SETTLE_FRAMES:
				# Stage/pose changes can re-fit or re-orbit the camera; hold the requested angle.
				ed._preview.yaw = yaw; ed._preview.pitch = pitch; ed._preview.update_camera()
				await _frames(1)
			var rect := Rect2i(ed._preview.get_global_rect())
			var img := get_viewport().get_texture().get_image()
			rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			img.get_region(rect).save_png(out_dir.path_join("%s_%s_%s_%s.png" % [key, tag, STAGES[st], view]))
		report.stages[STAGES[st]] = _body_metrics(ed._preview.player)
	if not ed._base and ed._has_motion():
		report["path"] = _path_metrics(ed._current, ed._serve)
		report["swing"] = await _swing_trace(ed)
	var f := FileAccess.open(out_dir.path_join("%s_%s.json" % [key, tag]), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))

const TRACE_STEPS := 40

# Solved swing, sampled through the editor preview: paddle head and right-arm joints per step.
# Reports the sharpest path corner, elbow snaps (frame-to-frame jumps) and elbow-to-torso clearance.
func _swing_trace(ed) -> Dictionary:
	var p = ed._preview.player
	var heads: Array = []
	var elbows: Array = []
	var bends: Array = []
	var rolls: Array = []
	var fields: Array = []
	var clear := INF
	var inward := 0
	var up_steps: Array = []
	var wrists: Array = []  # per step: _wrist_metrics()
	var elbow_up: Array = []  # per step: [elbow height above shoulder m, upward share of the elbow bulge]
	# Serves spend most of the first half waiting for the ball; trace only the real swing
	# (strike + follow-through) so per-step changes are comparable to strokes.
	var from := 0.0
	if ed._serve:
		var style: int = ServeStore.style_id(ed._current)
		var ct: float = float(RuntimePreview.serve_plan(style).contact_time)
		if ct > 0.0 and not from_rest: from = clampf(0.5 * (1.0 - Styles.stroke_duration(style) / ct), 0.0, 0.5)
	for k in TRACE_STEPS + 1:
		ed._progress = lerpf(from, 1.0, float(k) / TRACE_STEPS)
		ed._refresh_preview()
		await _frames(2)
		if strip and k % 4 == 0:
			await _frames(2)
			var img := get_viewport().get_texture().get_image()
			var rect := Rect2i(ed._preview.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			img.get_region(rect).save_png(out_dir.path_join("strip_%s_%02d.png" % [ServeStore.style_id(ed._current) if ed._serve else ed._current.posture_id, k]))
		var arm = p.right_arm_node
		var pz = ed._preview.pose
		fields.append([_r(pz.main_grip_rotation_deg), _r(pz.paddle_in_hand_rotation_deg), _r(pz.paddle_pitch_base_deg), _r(pz.paddle_yaw_base_deg), _r(pz.paddle_roll_base_deg), _rv(pz.right_elbow_pole)])
		heads.append(_local(p, p.paddle_node.get_node("Head").global_position))
		var sh: Vector3 = _local(p, arm.upper_pivot.global_position)
		var e: Vector3 = _local(p, preload("res://scripts/elbow_swivel.gd").visual_elbow_now(arm))
		var w: Vector3 = _local(p, arm.hand_pivot.global_position)
		elbows.append(e)
		bends.append(_bend(sh, e, w))
		wrists.append(_wrist_metrics(p, e, w))
		var torso: Vector3 = _local(p, p.body_pivot.get_node("TorsoMesh").global_position)
		clear = minf(clear, Vector2(e.x - torso.x, e.z - torso.z).length())
		# Elbow pointing in toward the torso (relative to the shoulder-wrist line) reads as a twisted arm.
		var mid: Vector3 = (sh + w) * 0.5
		var to_torso: Vector3 = Vector3(torso.x - mid.x, 0, torso.z - mid.z).normalized()
		if (e - mid).dot(to_torso) > 0.04: inward += 1
		# Elbow pointing up: the elbow bulges upward from the shoulder-wrist line, or sits above the shoulder.
		var bulge: Vector3 = e - mid
		elbow_up.append([_r(e.y - sh.y), _r(bulge.normalized().y if bulge.length() > 0.001 else 0.0)])
		if (bulge.length() > 0.03 and bulge.normalized().y > 0.6) or e.y > sh.y + 0.03: up_steps.append(k)
		# Forearm roll: the hand's x axis around the forearm, measured from the elbow-plane normal.
		var fore: Vector3 = (w - e).normalized()
		var plane_n: Vector3 = (sh - e).cross(w - e)
		var hand_x: Vector3 = arm.hand_pivot.global_basis.x
		hand_x = Vector3(hand_x.dot(p._get_forehand_axis()), hand_x.y, hand_x.dot(p._get_forward_axis()))
		hand_x -= fore * hand_x.dot(fore)
		rolls.append(rad_to_deg(plane_n.normalized().signed_angle_to(hand_x.normalized(), fore)) if plane_n.length() > 0.0001 and hand_x.length() > 0.0001 else 0.0)
	var corner := 0.0
	var corner_at := 0.0
	for k in range(1, TRACE_STEPS):
		var a: Vector3 = heads[k] - heads[k - 1]
		var b: Vector3 = heads[k + 1] - heads[k]
		if a.length() < 0.005 or b.length() < 0.005: continue
		var turn: float = rad_to_deg(a.angle_to(b))
		if turn > corner: corner = turn; corner_at = float(k) / TRACE_STEPS
	var snap := 0.0
	var snap_at := 0.0
	var jump := 0.0
	for k in range(1, TRACE_STEPS + 1):
		var d: float = absf(bends[k] - bends[k - 1])
		if d > snap: snap = d; snap_at = float(k) / TRACE_STEPS
		jump = maxf(jump, (elbows[k] - elbows[k - 1]).length())
	var roll_step := 0.0
	var roll_min := INF
	var roll_max := -INF
	for k in rolls.size():
		roll_min = minf(roll_min, rolls[k]); roll_max = maxf(roll_max, rolls[k])
		# Roll is measured against the elbow plane, which is undefined for a near-straight arm.
		if k > 0 and bends[k] > 25.0 and bends[k - 1] > 25.0:
			roll_step = maxf(roll_step, absf(wrapf(rolls[k] - rolls[k - 1], -180.0, 180.0)))
	var path: Array = []
	for h in heads: path.append(_rv(h))
	return {"head_path": path, "sharpest_corner_deg": _r(corner), "corner_at": corner_at,
		"max_elbow_bend_step_deg": _r(snap), "snap_at": snap_at, "max_elbow_jump_m": _r(jump),
		"min_elbow_torso_clearance_m": _r(clear), "elbow_inward_steps": inward,
		"forearm_roll_range_deg": [_r(roll_min), _r(roll_max)], "max_forearm_roll_step_deg": _r(roll_step),
		"max_wrist_angle_deg": _r(wrists.map(func(v): return v.angle).max()),
		"max_abs_wrist_flex_deg": _r(wrists.map(func(v): return absf(v.flex)).max()),
		"max_wrist_step_deg": _r(_max_step(wrists.map(func(v): return v.angle))),
		"wrist_angles": wrists.map(func(v): return v.angle), "wrist_flex": wrists.map(func(v): return v.flex),
		"max_elbow_above_shoulder_m": _r(elbow_up.map(func(v): return v[0]).max()),
		"traced_from": _r(from), "elbow_up_steps": up_steps, "elbow_up": elbow_up, "rolls": rolls.map(func(v): return _r(v)), "bends": bends.map(func(v): return _r(v)), "grip_inhand_pitch_yaw_roll": fields}

# Player-local frame: x = forehand side, y = height above the court floor, z = toward the net.
# Metres and degrees.
func _local(p: Node3D, v: Vector3) -> Vector3:
	var d := v - p.global_position
	return Vector3(d.dot(p._get_forehand_axis()), v.y - p.COURT_FLOOR_Y, d.dot(p._get_forward_axis()))

func _yaw(a: Vector3, b: Vector3) -> float:
	# Turn of the line a->b (left joint -> right joint) away from square (parallel to the net).
	return rad_to_deg(atan2(b.z - a.z, b.x - a.x))

func _bend(a: Vector3, mid: Vector3, b: Vector3) -> float:
	return 180.0 - rad_to_deg((a - mid).angle_to(b - mid))

func _max_step(a: Array) -> float:
	var m := 0.0
	for k in range(1, a.size()): m = maxf(m, absf(a[k] - a[k - 1]))
	return m

func _r(v: float) -> float: return snappedf(v, 0.01)
func _rv(v: Vector3) -> Array: return [_r(v.x), _r(v.y), _r(v.z)]

func _body_metrics(p) -> Dictionary:
	var L = p.left_leg_node
	var R = p.right_leg_node
	var hips: Vector3 = _local(p, p.body_pivot.get_node("HipsMesh").global_position)
	var torso: Vector3 = _local(p, p.body_pivot.get_node("TorsoMesh").global_position)
	var head: Vector3 = _local(p, p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position)
	var lh: Vector3 = _local(p, L.thigh_pivot.global_position)
	var rh: Vector3 = _local(p, R.thigh_pivot.global_position)
	var lk: Vector3 = _local(p, L.shin_pivot.global_position)
	var rk: Vector3 = _local(p, R.shin_pivot.global_position)
	var la: Vector3 = _local(p, L.foot_pivot.global_position)
	var ra: Vector3 = _local(p, R.foot_pivot.global_position)
	var ls: Vector3 = _local(p, p.left_arm_node.upper_pivot.global_position)
	var rs: Vector3 = _local(p, p.right_arm_node.upper_pivot.global_position)
	var re: Vector3 = _local(p, preload("res://scripts/elbow_swivel.gd").visual_elbow_now(p.right_arm_node))
	var rw: Vector3 = _local(p, p.right_arm_node.hand_pivot.global_position)
	var paddle: Vector3 = _local(p, p.paddle_node.get_node("Head").global_position)
	# Segment-weighted centre of gravity (arms left out; they are light and move a lot).
	var com: Vector3 = hips * 0.40 + torso * 0.30 + head * 0.08 \
		+ ((lh + lk) * 0.5 + (rh + rk) * 0.5) * 0.08 + ((lk + la) * 0.5 + (rk + ra) * 0.5) * 0.03
	var front: Vector3 = la if la.z >= ra.z else ra
	var back: Vector3 = ra if la.z >= ra.z else la
	var base := Vector2(front.x - back.x, front.z - back.z)
	var c := Vector2(com.x - back.x, com.z - back.z)
	var t: float = clampf(c.dot(base) / maxf(base.length_squared(), 0.0001), -1.0, 2.0)
	var off: float = (c - base * clampf(t, 0.0, 1.0)).length()
	var spine := torso - hips
	# Hitting upper arm relative to the trunk: elevation (0 = hanging, 90 = level with the shoulder,
	# >90 = above) and flare: angle of the upper arm out of the trunk's front-back plane
	# (+ = elbow out to the hitting side, - = across the chest; elbow in front of the body is 0).
	var down: Vector3 = -spine.normalized()
	var across: Vector3 = (rs - ls)
	across = (across - spine.normalized() * across.dot(spine.normalized())).normalized()
	var upper: Vector3 = (re - rs).normalized()
	var wrist: Dictionary = _wrist_metrics(p, re, rw)
	return {
		"wrist_angle_deg": wrist.angle, "wrist_flex_deg": wrist.flex, "wrist_deviation_deg": wrist.deviation,
		"paddle_tip_pitch_deg": wrist.tip_pitch, "face_to_net_deg": wrist.face_to_net,
		"elbow_above_shoulder_m": _r(re.y - rs.y),
		"upper_arm_elevation_deg": _r(rad_to_deg(upper.angle_to(down))),
		"elbow_flare_deg": _r(rad_to_deg(asin(clampf(upper.dot(across), -1.0, 1.0)))),
		"left_ankle": _rv(la), "right_ankle": _rv(ra),
		"feet_planted": la.y < 0.10 and ra.y < 0.10,  # planted ankle sits ~0.04 m up
		"stance_width": _r(absf(la.x - ra.x)), "stance_depth": _r(absf(la.z - ra.z)),
		"front_foot": "left" if la.z >= ra.z else "right",
		"com": _rv(com),
		"com_back_to_front": _r(t), "com_off_base_m": _r(off), "com_over_base": t >= -0.05 and t <= 1.05 and off <= 0.15,
		"hip_yaw": _r(_yaw(lh, rh)), "shoulder_yaw": _r(_yaw(ls, rs)),
		"separation": _r(_yaw(ls, rs) - _yaw(lh, rh)),
		"trunk_lean_fwd": _r(rad_to_deg(atan2(spine.z, spine.y))), "trunk_lean_side": _r(rad_to_deg(atan2(spine.x, spine.y))),
		"hip_height": _r(hips.y),
		"left_knee_bend": _r(_bend(lh, lk, la)), "right_knee_bend": _r(_bend(rh, rk, ra)),
		"right_elbow_bend": _r(_bend(rs, re, rw)),
		"paddle_head": _rv(paddle), "paddle_from_shoulder": _r(paddle.distance_to(rs)),
	}

# Direction in the player-local frame (x forehand side, y up, z toward the net).
func _ldir(p, v: Vector3) -> Vector3:
	return Vector3(v.dot(p._get_forehand_axis()), v.y, v.dot(p._get_forward_axis())).normalized()

# How the paddle sits in the hand. Paddle local y = handle -> head, z = face normal.
# angle: forearm (elbow -> wrist) vs handle, 0 = paddle in line with the forearm.
# flex: forearm out of the paddle face plane (wrist bent back/forward across the face).
# deviation: angle inside the face plane (wrist cocked up/down along the paddle edge).
# tip_pitch: paddle tip above (+) / below (-) horizontal. face_to_net: face normal vs the net
# direction (0 = square to the net, 90 = face pointing sideways or up/down).
func _wrist_metrics(p, e: Vector3, w: Vector3) -> Dictionary:
	var b: Basis = p.paddle_node.global_basis
	var axis: Vector3 = _ldir(p, b.y)
	var face_x: Vector3 = _ldir(p, b.x)
	var face_n: Vector3 = _ldir(p, b.z)
	var fore: Vector3 = (w - e).normalized()
	var flex: float = rad_to_deg(asin(clampf(fore.dot(face_n), -1.0, 1.0)))
	var dev: float = rad_to_deg(atan2(fore.dot(face_x), fore.dot(axis)))
	return {"angle": _r(rad_to_deg(fore.angle_to(axis))), "flex": _r(flex), "deviation": _r(dev),
		"tip_pitch": _r(rad_to_deg(asin(clampf(axis.y, -1.0, 1.0)))),
		"face_to_net": _r(rad_to_deg(acos(clampf(absf(face_n.z), 0.0, 1.0))))}

func _path_metrics(def: Resource, serve := false) -> Dictionary:
	var ys: Array = []
	var low := INF
	var low_t := 0.0
	for k in 21:
		var s = ServeStore.sample(def, k / 20.0) if serve else Path.sample(def, k / 20.0)
		ys.append(_r(s.paddle_y_offset))
		if s.paddle_y_offset < low: low = s.paddle_y_offset; low_t = k / 20.0
	var contact: float = ys[10]
	return {"y_samples": ys, "lowest_y": _r(low), "lowest_at": low_t,
		"drop_below_contact": _r(contact - low), "rise_to_finish": _r(float(ys[20]) - contact)}
