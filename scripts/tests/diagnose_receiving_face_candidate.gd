extends SceneTree



const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const A = preload("res://scripts/arm_anatomy.gd")
const C = preload("res://scripts/body_clearance.gd")
const P = preload("res://scripts/paddle_clearance.gd")
const O = preload("res://scripts/stroke_preparation_orientation.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var input_path: = "/workspace/shared/pickleball-hands/fh-face-selected-candidates.json"
var source_path: = "/workspace/shared/pickleball-hands/live-receiving-current-all18/contact-geometry.json"
var output_path: = "/workspace/shared/pickleball-hands/fh-face-actual-rig-candidates.json"
var errors: Array[String] = []
var records: Array = []
func _initialize(): call_deferred("run")
func v(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2])
func vd(a: Vector3) -> Array: return [a.x, a.y, a.z]
func bd(b: Basis) -> Array: return [vd(b.x), vd(b.y), vd(b.z)]
func bt(a: Array) -> Basis: return Basis(v(a[0]), v(a[1]), v(a[2]))
func tt(a: Array) -> Transform3D: return Transform3D(bt(a), v(a[3]))
func check(ok: bool, label: String):
	if not ok: errors.append(label)
func apply_fields(pose: PostureDefinition, data: Dictionary):
	for key in data:
		var value = data[key]
		pose.set(key, v(value) if value is Array and value.size() == 3 else value)
func measured(p, pose: PostureDefinition) -> Dictionary:
	var arm = p.right_arm_node; var model = arm.articulated_hand
	var s: Vector3 = arm.upper_pivot.global_position; var e: Vector3 = arm.forearm_pivot.global_position
	var w: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
	var body: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
	var upper: Dictionary = C.mesh_surface_margins(arm.upper_mesh, body, s, e, 0.08)
	var fore: Dictionary = C.mesh_surface_margins(arm.fore_mesh, body)
	var body_margin: = INF; var limb_margin: = INF
	for region in C.REGIONS: body_margin = minf(body_margin, minf(upper[region], fore[region]))
	var inverse: Transform3D = p.paddle_node.global_transform.affine_inverse()
	for mesh in [arm.upper_mesh, arm.fore_mesh]:
		for point in C.mesh_surface_points(mesh): limb_margin = minf(limb_margin, P.distance_to_paddle_shape(inverse * (mesh.global_transform * point)))
	return {"shoulder": vd(s), "elbow": vd(e), "wrist": vd(w), "hand_basis": bd(arm.hand_mesh.global_basis), 
		"elbow_below_shoulder_m": s.y - e.y, "body_margin_m": body_margin, "paddle_limb_margin_m": limb_margin, 
		"upper_regions": upper, "fore_regions": fore, "stretch": arm.visual_stretch, 
		"channels": A.decompose(A.forearm_reference(s, e, w, Vector3.UP, false), arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)}
func canonical_pole(p, pose: PostureDefinition, world: Vector3) -> Vector3:
	var stance: = Basis(p._get_forehand_axis(), Vector3.UP, - p._get_forward_axis())
	var turn: Basis = stance * Basis.from_euler(pose.right_shoulder_rotation_deg * (PI / 180.0)) * stance.inverse()
	var shoulder: Vector3 = p.right_arm_node.upper_pivot.global_position
	var relative: Vector3 = shoulder + turn.inverse() * (world - shoulder) - p.global_position
	return Vector3(relative.dot(p._get_forehand_axis()), relative.y, relative.dot(p._get_forward_axis()))
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--candidates="): input_path = arg.trim_prefix("--candidates=")
		if arg.begins_with("--source="): source_path = arg.trim_prefix("--source=")
		if arg.begins_with("--output="): output_path = arg.trim_prefix("--output=")
	if not FileAccess.file_exists(input_path): push_error("Candidate input is missing: " + input_path);quit(2);return
	var candidates = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	var exported = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var snapshots: Dictionary = {}
	for row in exported.snapshots: snapshots[row.case] = row
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO
	p.posture.editor_preview_mode = true
	for candidate in candidates:
		var row: Dictionary = snapshots[candidate.case]
		var pose: PostureDefinition = PostureLibrary.instance().get_def(int(row.pose_fields.posture_id)).duplicate(true)


		apply_fields(pose, row.pose_fields);apply_fields(pose, row.review_pose_fields)
		pose.set_meta("visual_wrist_lag_deg", float(row.visual_wrist_lag_deg))
		p.global_position = v(row.player_origin);p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
		p.body_pivot.global_transform = tt(row.body_transform);p.paddle_node.global_transform = tt(row.paddle_transform)
		p.arm_ik.update_arm_ik(0.0, pose)
		var baseline: Dictionary = measured(p, pose)
		for key in ["shoulder", "elbow", "wrist"]: check(v(baseline[key]).distance_to(v(row[key])) < 0.0001, candidate.case + " baseline reconstruction " + key)
		check(bt(baseline.hand_basis).is_equal_approx(tt(row.hand_transform).basis), candidate.case + " baseline hand frame")
		if candidate.has("shoulder_protraction_m"):
			pose.shoulder_protraction_m = float(candidate.shoulder_protraction_m)
			Body.apply(p, pose)
			p.body_pivot.global_transform = tt(row.body_transform)
		var paddle: = Transform3D(bt(candidate.paddle_basis), v(candidate.paddle_origin))
		var original: Transform3D = tt(row.paddle_transform)
		var head: Vector3 = paddle * PaddleSize.HEAD_OFFSET
		check(head.distance_to(original * PaddleSize.HEAD_OFFSET) < 1e-05, candidate.case + " exact head")
		check(absf(paddle.basis.z.dot(original.basis.z)) > 0.99999, candidate.case + " exact physical face plane")
		var stance: = Basis(p._get_forehand_axis(), Vector3.UP, - p._get_forward_axis())
		O.set_canonical_basis(pose, stance.inverse() * paddle.basis)
		var offset: Vector3 = head - p.global_position
		pose.paddle_forehand_mul = offset.dot(p._get_forehand_axis());pose.paddle_y_offset = offset.y;pose.paddle_forward_mul = offset.dot(p._get_forward_axis())
		check((Path.world_transform(p, pose) * PaddleSize.HEAD_OFFSET).distance_to(head) < 1e-05, candidate.case + " shared reach query retains exact head")
		pose.right_elbow_pole = canonical_pole(p, pose, v(candidate.elbow))
		p.paddle_node.global_transform = paddle;p.arm_ik.update_arm_ik(0.0, pose)
		var result: Dictionary = measured(p, pose)
		var ball: Vector3 = v(row.ball_position)
		var face_side: Vector3 = paddle.basis.z * signf((ball - head).dot(paddle.basis.z))
		var dorsal: Vector3 = p.right_arm_node.hand_mesh.global_basis * p.right_arm_node.articulated_hand.anatomical_basis.z
		result["dorsal_dot_ball_side"] = dorsal.dot(face_side)
		result["ball_surface_gap_m"] = P.distance_to_head_shape(paddle.affine_inverse() * ball) - 0.0375
		result.merge({"case": candidate.case, "inplane_deg": candidate.inplane_deg, "baseline": baseline, "canonical_pole": vd(pose.right_elbow_pole), "elbow_target_error_m": v(result.elbow).distance_to(v(candidate.elbow)), "wrist_target_error_m": v(result.wrist).distance_to(v(candidate.wrist))})
		check(result.channels.within_animation_budget, candidate.case + " candidate wrist budget")
		check(result.dorsal_dot_ball_side < - 0.5, candidate.case + " forehand presents the palmar side")
		check(absf(result.ball_surface_gap_m) < 0.0001, candidate.case + " unchanged finite ball contact")
		check(result.stretch <= 1.001, candidate.case + " exact arm reach")
		check(result.body_margin_m >= - 3e-05, candidate.case + " actual arm body clearance")
		check(result.paddle_limb_margin_m >= - 3e-05, candidate.case + " actual paddle arm clearance")
		records.append(result)
	var report: = FileAccess.open(output_path, FileAccess.WRITE)
	if report: report.store_string(JSON.stringify({"records": records, "errors": errors, "source": "Finite test-only endpoint replay, exported real fitted body, production conditioner; no gameplay mutation"}, "\t"));report.close()
	for error in errors: push_error(error)
	print("RECEIVING FACE CANDIDATES: ", records.size(), " records, ", errors.size(), " failures")
	game.queue_free(); await process_frame;quit(0 if errors.is_empty() else 1)
