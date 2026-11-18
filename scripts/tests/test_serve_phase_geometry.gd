extends SceneTree



const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const C = preload("res://scripts/body_clearance.gd")
const G = preload("res://scripts/paddle_clearance.gd")
const A = preload("res://scripts/arm_anatomy.gd")
var records: Array = []
var failures: Array[String] = []
var failure_count: = 0
var checks: = 0
var surface: Array[Vector3] = []
var focus: = false
var export_frames: = false
func _vector_data(value: Vector3) -> Array: return [value.x, value.y, value.z]
func _basis_data(value: Basis) -> Array: return [_vector_data(value.x), _vector_data(value.y), _vector_data(value.z)]
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failure_count += 1
		if failures.size() < 60: failures.append(label)
func ball_at(plan: Dictionary, elapsed: float) -> Vector3:
	var previous: Vector3 = plan.release_position; var previous_time: = 0.0
	for sample in plan.samples:
		if sample.time >= elapsed: return previous.lerp(sample.pos, clampf((elapsed - previous_time) / maxf(1e-06, sample.time - previous_time), 0, 1))
		previous = sample.pos;previous_time = sample.time
	return plan.contact_position
func adjusted_pose(pose: PostureDefinition, _elapsed: float) -> PostureDefinition: return pose
func sample(p, style: int, charge: float, elapsed: float, plan: Dictionary):
	var pose: PostureDefinition = adjusted_pose(Preview.sample_serve_elapsed(style, elapsed, charge, p.global_position.y), elapsed)
	p.posture.editor_preview_mode = false;p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)


	p.posture.editor_preview_mode = true;p.arm_ik.update_arm_ik(0.0, pose);p.posture.editor_preview_mode = false
	var tag: = "side%d style%d q%.1f t%.4f %s" % [p.player_num, style, charge, elapsed, pose.get_meta("preview_serve_phase")]
	var tx: Transform3D = p.paddle_node.global_transform
	var geometry: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
	var row: = {"tag": tag, "style": style, "charge": charge, "elapsed": elapsed, "phase": pose.get_meta("preview_serve_phase"), "side": p.player_num, "arms": []}
	for side in [0, 1]:
		var arm = p.right_arm_node if side == 0 else p.left_arm_node; var model = arm.articulated_hand
		var s: Vector3 = arm.upper_pivot.global_position; var e: Vector3 = arm.forearm_pivot.global_position; var w: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
		var channels: Dictionary = A.decompose(A.forearm_reference_for_arm(arm, w, side == 1), arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
		var upper: Dictionary = C.mesh_surface_margins(arm.upper_mesh, geometry, s, e, 0.08); var fore: Dictionary = C.mesh_surface_margins(arm.fore_mesh, geometry)
		var margin: = INF
		for region in C.REGIONS: margin = minf(margin, minf(upper[region], fore[region]))
		check(margin >= - 3e-05, tag + " arm%d body %.4f" % [side, margin])
		check(arm.visual_stretch <= 1.001, tag + " arm%d stretch %.4f" % [side, arm.visual_stretch])
		check(channels.within_animation_budget, tag + " arm%d budget %s" % [side, channels])
		row.arms.append({"side": side, "channels": channels, "body_margin": margin, "upper": upper, "fore": fore, "stretch": arm.visual_stretch})
		if export_frames:
			var pole: Vector3 = pose.right_elbow_pole if side == 0 else pose.left_elbow_pole
			var hint: Vector3 = p.global_position + p._get_forehand_axis() * pole.x + Vector3.UP * pole.y + p._get_forward_axis() * pole.z
			hint = p.arm_ik._rotate_shoulder_pole(arm, hint, pose.right_shoulder_rotation_deg if side == 0 else pose.left_shoulder_rotation_deg)
			row.arms[-1].merge({"shoulder": _vector_data(s), "elbow": _vector_data(e), "wrist": _vector_data(w), "authored_pole": _vector_data(hint), "hand_frame": _basis_data(arm.hand_mesh.global_basis * model.anatomical_basis), "hand_mount_basis": _basis_data(arm.hand_mesh.global_basis), "hand_mount_origin": _vector_data(arm.hand_mesh.global_position), "model_basis": _basis_data(model.anatomical_basis), "palm_contact_basis": _basis_data(model.palm_contact_basis), "wrist_socket": _vector_data(model.wrist_socket), "cup_ball_center": _vector_data(model.cup_ball_center), "radial_sign": model.radial_sign})
	if export_frames:
		var cells: Array = []
		for cell in geometry.cells:
			var planes: Array = []
			for plane in cell.planes: planes.append([plane.normal.x, plane.normal.y, plane.normal.z, plane.d])
			cells.append({"region": cell.region, "planes": planes})
		row["body_cells"] = cells;row["ball_center"] = _vector_data(plan.release_position)
	var limb_margin: = INF
	var limb_margins: Dictionary = {}; var limb_index: = 0
	for mesh in [p.right_arm_node.upper_mesh, p.right_arm_node.fore_mesh, p.left_arm_node.upper_mesh, p.left_arm_node.fore_mesh, p.right_leg_node.thigh_mesh, p.right_leg_node.shin_mesh, p.left_leg_node.thigh_mesh, p.left_leg_node.shin_mesh]:
		var local: Transform3D = tx.affine_inverse() * mesh.global_transform
		var minimum: = INF
		for point in C.mesh_surface_points(mesh): minimum = minf(minimum, G.distance_to_paddle_shape(local * point))
		limb_margin = minf(limb_margin, minimum);limb_margins["%d_%s" % [limb_index, mesh.name]] = minimum;limb_index += 1
	check(limb_margin >= - 3e-05, tag + " paddle/limb %.4f" % limb_margin)
	row["limb_margin"] = limb_margin;row["limb_margins"] = limb_margins
	var body: Dictionary = C.sample_paddle(tx, surface, geometry)
	for region in C.REGIONS: check(body[region] >= - 3e-05, tag + " paddle/" + region)
	row["paddle_body"] = body
	var face: float = G.distance_to_paddle_shape(tx.affine_inverse() * p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position) - 0.12
	check(face >= 0.01, tag + " face %.4f" % face);row["face"] = face
	var floor: = INF
	for point in surface: floor = minf(floor, (tx * point).y - p.COURT_FLOOR_Y)
	check(floor >= 0, tag + " floor %.4f" % floor);row["floor"] = floor
	if elapsed < float(plan.contact_time) - 0.001:
		var gap: float = G.distance_to_paddle_shape(tx.affine_inverse() * ball_at(plan, elapsed)) - 0.0375
		check(gap >= - 0.001, tag + " early paddle/ball %.4f" % gap);row["ball_gap"] = gap
	records.append(row)
func run():
	focus = "--focus" in OS.get_cmdline_user_args()
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	surface = G.sample_head_surface()
	for p in ([game.player_left] if focus else [game.player_left, game.player_right]):
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
		for style in ([0, 1, 4, 5] if focus else range(7)):
			var plan: Dictionary = Styles.release_plan(p.global_position, p.player_num == 1, style)
			for charge in [0.0, 0.5, 1.0]:
				var times: Array[float] = [0.0, 0.06, 0.12]
				var contact: float = plan.contact_time; var stroke: float = Styles.stroke_duration(style); var sweep: float = Styles.sweep_duration(style)
				for progress in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]: times.append(contact - stroke + stroke * progress)
				for progress in [0.1, 0.25, 0.5, 0.75, 1.0]: times.append(contact + sweep * progress)


				for frame in range(1, 5): times.append(contact + float(frame) / 60.0)
				for progress in [0.25, 0.5, 0.75, 1.0]: times.append(contact + sweep + Motion.SERVE_HOLD_TIME + Motion.SERVE_RECOVERY_TIME * progress)
				for elapsed in times: sample(p, style, charge, maxf(elapsed, 0), plan)
			print("PHASE GEOMETRY side", p.player_num, " style", style, " complete")
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/serve-phase-geometry-focus.json" if focus else "/workspace/shared/pickleball-hands/serve-phase-geometry.json", FileAccess.WRITE);file.store_string(JSON.stringify({"checks": checks, "failure_count": failure_count, "failures": failures, "records": records}, "\t"));file.close()
	print("SERVE PHASE GEOMETRY: ", checks, " checks, ", failure_count, " failures; ", records.size(), " actual poses")
	for message in failures: push_error(message)
	game.queue_free(); await process_frame;quit(0 if failure_count == 0 else 1)
