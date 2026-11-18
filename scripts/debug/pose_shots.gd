extends Node
## Dev tool behind tools/pose_review.sh. Drives the mobile pose editor preview and, per pose and
## stage (wind-up / contact / finish), saves screenshots (paddle trace, ghosts, contact box) and
## body metrics (feet, centre of gravity, hip/shoulder turn, knees, elbow, paddle path) as JSON.
## Args (after --): --pose-shots=<abs dir> [--pose-only=s00,b11] [--pose-before=<abs dir>]
##   --pose-before: dir holding older copies as postures/<file>.tres and base_poses/<file>.tres;
##   each pose found there is captured twice, tagged "before" and "after" (else tagged "now").
## Output: <dir>/<key>_<tag>_<stage>_<view>.png and <dir>/<key>_<tag>.json, then quits.
## Not loaded unless --pose-shots is passed (see perf_monitor.gd).

const Path = preload("res://scripts/stroke_swing_path.gd")
const VIEWS := ["front", "side"]
const STAGES := ["windup", "contact", "finish"]
const SETTLE_FRAMES := 45
var out_dir := ""
var before_dir := ""
var only: PackedStringArray = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pose-before="): before_dir = a.trim_prefix("--pose-before=")
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
	for mode in ["s", "b"]:
		ed._select_workspace(1 if mode == "b" else 0)
		await _frames(3)
		for i in ed._definitions.size():
			var def: Resource = ed._definitions[i]
			var id: int = def.base_pose_id if mode == "b" else def.posture_id
			var key := "%s%02d" % [mode, id]
			if not only.is_empty() and not only.has(key): continue
			var copy_key := ("base:" if mode == "b" else "stroke:") + str(id)
			var old: Resource = _load_before(def)
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
	if not ed._base and ed._has_motion(): report["path"] = _path_metrics(ed._current)
	var f := FileAccess.open(out_dir.path_join("%s_%s.json" % [key, tag]), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))

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
	var re: Vector3 = _local(p, p.right_arm_node.forearm_pivot.global_position)
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
	return {
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

func _path_metrics(def: Resource) -> Dictionary:
	var ys: Array = []
	var low := INF
	var low_t := 0.0
	for k in 21:
		var s = Path.sample(def, k / 20.0)
		ys.append(_r(s.paddle_y_offset))
		if s.paddle_y_offset < low: low = s.paddle_y_offset; low_t = k / 20.0
	var contact: float = ys[10]
	return {"y_samples": ys, "lowest_y": _r(low), "lowest_at": low_t,
		"drop_below_contact": _r(contact - low), "rise_to_finish": _r(float(ys[20]) - contact)}
