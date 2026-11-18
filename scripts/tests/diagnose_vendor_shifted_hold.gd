extends "res://scripts/tests/test_serve_phase_geometry.gd"

const Candidate = preload("res://scripts/tests/photo_takeback_candidate.gd")
const Grasp = preload("res://scripts/serve_ball_grasp_profile.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const COLUMN: = Vector2(0.417110649305134, 0.620205599438965)
const HOLD_WORLD_Y: = 1.25
const FK_CONTACT_WORLD_Y: = 0.724804794324833
var report_path: = "/workspace/shared/pickleball-hands/vendor-shifted-hold-check.json"
var active_charge: = 0.0
var active_hold: = Vector3.ZERO
const VisibleBody = preload("res://scripts/stroke_body_pose.gd")
func adjusted_pose(pose: PostureDefinition, _elapsed: float) -> PostureDefinition:
	pose = Candidate.apply(pose, active_charge)
	pose.weight_shift += 0.5 * (1.0 - smoothstep(0.0, 1.0, active_charge))
	pose.left_elbow_pole = Grasp.pole(active_charge, active_hold.y)
	pose.set_meta("preview_serve_held_offset", active_hold)
	pose.set_meta("serve_phase_held_offset", active_hold)
	return pose
func flight_summary(p, release: Vector3, style: int) -> Dictionary:
	var plan: Dictionary = Styles.release_plan(p.global_position, p.player_num == 1, style, release)
	var traced: Dictionary = Flight.trace(release, Vector3.ZERO, Vector3.ZERO, 2.0, 2, false)
	var apex: float = Flight.FLOOR_REST_Y
	var fk_crossings: Array = []
	var samples: Array = []
	var previous: Dictionary = {"time": 0.0, "pos": release, "vel": Vector3.ZERO, "bounces": 0}
	for sample in traced.samples:
		if int(sample.bounces) == 1: apex = maxf(apex, sample.pos.y)
		if int(previous.bounces) == int(sample.bounces) and (previous.pos.y - FK_CONTACT_WORLD_Y) * (sample.pos.y - FK_CONTACT_WORLD_Y) <= 0.0 and not is_equal_approx(previous.pos.y, sample.pos.y):
			var alpha: float = (FK_CONTACT_WORLD_Y - previous.pos.y) / (sample.pos.y - previous.pos.y)
			fk_crossings.append({"time": lerpf(previous.time, sample.time, alpha), "position": _vector_data(previous.pos.lerp(sample.pos, alpha)), "bounces": sample.bounces, "vertical_velocity": lerpf(previous.vel.y, sample.vel.y, alpha)})
		samples.append({"time": sample.time, "position": _vector_data(sample.pos), "velocity": _vector_data(sample.vel), "bounces": sample.bounces})
		previous = sample
	return {"side": p.player_num, "style": style, "release_position": _vector_data(release), "initial_velocity": [0, 0, 0], "initial_spin": [0, 0, 0], "legacy_selection_contact_position": _vector_data(plan.contact_position), "legacy_selection_contact_time": plan.contact_time, "first_bounce_time": traced.first_bounce_time, "first_bounce": _vector_data(traced.first_bounce), "first_bounce_apex_y": apex, "fk_contact_height_y": FK_CONTACT_WORLD_Y, "fk_height_crossings": fk_crossings, "samples": samples}

func author_support_direction(p, pose: PostureDefinition) -> void :
	var arm = p.left_arm_node
	var mount: Transform3D = arm.hand_mesh.global_transform
	var wrist: Vector3 = mount * arm.articulated_hand.wrist_socket
	var distal: Vector3 = mount.basis * arm.articulated_hand.anatomical_basis.x


	var desired_elbow: Vector3 = wrist - distal * arm.forearm_length
	var stance: = Basis(p._get_forehand_axis(), Vector3.UP, - p._get_forward_axis())
	var rotation: Basis = stance * Basis.from_euler(pose.left_shoulder_rotation_deg * (PI / 180.0)) * stance.inverse()
	var shoulder: Vector3 = arm.upper_pivot.global_position
	var unrotated: Vector3 = shoulder + rotation.inverse() * (desired_elbow - shoulder) - p.global_position
	pose.left_elbow_pole = Vector3(unrotated.dot(p._get_forehand_axis()), unrotated.y, unrotated.dot(p._get_forward_axis()))
	p.posture.editor_preview_mode = true;p.arm_ik.update_arm_ik(0.0, pose);p.posture.editor_preview_mode = false

func sample(p, style: int, charge: float, elapsed: float, plan: Dictionary):
	var pose: PostureDefinition = adjusted_pose(Preview.sample_serve_elapsed(style, elapsed, charge, p.global_position.y), elapsed)
	p.posture.editor_preview_mode = false;p.leg_ik.feet_initialized = false;p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)


	p.posture.editor_preview_mode = true;p.arm_ik.update_arm_ik(0.0, pose);p.posture.editor_preview_mode = false
	author_support_direction(p, pose)
	var tag: = "side%d style%d q%.1f t%.4f %s" % [p.player_num, style, charge, elapsed, pose.get_meta("preview_serve_phase")]
	var tx: Transform3D = p.paddle_node.global_transform
	var geometry: Dictionary = C.volumes(p, pose, p.body_pivot.global_transform)
	var row: = {"tag": tag, "style": style, "charge": charge, "elapsed": elapsed, "phase": pose.get_meta("preview_serve_phase"), "side": p.player_num, "arms": []}
	for side in [0, 1]:
		var arm = p.right_arm_node if side == 0 else p.left_arm_node; var model = arm.articulated_hand
		var s: Vector3 = arm.upper_pivot.global_position; var e: Vector3 = arm.forearm_pivot.global_position; var w: Vector3 = arm.hand_mesh.global_transform * model.wrist_socket
		var channels: Dictionary = A.decompose(A.forearm_reference(s, e, w, Vector3.UP, side == 1), arm.hand_mesh.global_basis * model.anatomical_basis, model.radial_sign)
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
	surface = G.sample_head_surface()
	var flights: Array = []
	for p in [game.player_left, game.player_right]:
		p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
		p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
		for style in [0, 4]:
			active_hold = Vector3(COLUMN.x, (1.45 if style == 4 else HOLD_WORLD_Y) - p.global_position.y, COLUMN.y)
			var release: Vector3 = p.global_position + p._get_forehand_axis() * active_hold.x + Vector3.UP * active_hold.y + p._get_forward_axis() * active_hold.z
			var plan: Dictionary = Styles.release_plan(p.global_position, p.player_num == 1, style, release)
			flights.append(flight_summary(p, release, style))
			for step in range(21):
				active_charge = step / 20.0;export_frames = step in [0, 10, 20]
				var original: PostureDefinition = Candidate.apply(Motion.serve_style_preparation(0, active_charge, Styles.hold_offset(0)), active_charge)
				var main_target: Transform3D = Path.world_transform(p, original)
				sample(p, style, active_charge, 0.0, plan)
				var support = p.left_arm_node; var model = support.articulated_hand
				var mount: Transform3D = support.hand_mesh.global_transform
				var wrist: Vector3 = mount * model.wrist_socket
				var row: Dictionary = records[-1]
				row["held_seat_error_m"] = (mount * model.cup_ball_center).distance_to(release)
				row["support_wrist_reach_m"] = support.upper_pivot.global_position.distance_to(wrist)
				row["support_exact_upper_m"] = support.upper_pivot.global_position.distance_to(support.forearm_pivot.global_position)
				row["support_exact_forearm_m"] = support.forearm_pivot.global_position.distance_to(wrist)
				row["main_paddle_unchanged"] = p.paddle_node.global_transform.is_equal_approx(main_target)
				var tag: = "side%d q%.2f" % [p.player_num, active_charge]
				check(row.held_seat_error_m < 1e-05, tag + " calibrated held sphere seat")
				check(absf(row.support_exact_upper_m - 0.35) < 1e-05 and absf(row.support_exact_forearm_m - 0.35) < 1e-05, tag + " actual support links")
				check(row.main_paddle_unchanged, tag + " unchanged main takeback path")
	var file: = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failure_count": failure_count, "failures": failures, "records": records, "flight_traces": flights, "scope": "Isolated1.25/1.45m holds;50mm forward prep translation and hand-distal radial pole; no adoption"}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("VENDOR SHIFTED HOLD ", checks, " checks; ", failure_count, " failures; ", records.size(), " actual poses; ", flights.size(), " real Flight traces")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failure_count == 0 else 1)
