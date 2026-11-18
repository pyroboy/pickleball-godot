extends "res://scripts/tests/test_serve_phase_geometry.gd"

const Candidate = preload("res://scripts/tests/photo_takeback_candidate.gd")
const Grasp = preload("res://scripts/serve_ball_grasp_profile.gd")
const Flight = preload("res://scripts/ball_flight_predictor.gd")
const COLUMN: = Vector2(0.417110649305134, 0.620205599438965)
const HOLD_WORLD_Y: = 1.25
const FK_CONTACT_WORLD_Y: = 0.724804794324833
var active_charge: = 0.0
var active_hold: = Vector3.ZERO
func adjusted_pose(pose: PostureDefinition, _elapsed: float) -> PostureDefinition:
	pose = Candidate.apply(pose, active_charge)
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
		active_hold = Vector3(COLUMN.x, HOLD_WORLD_Y - p.global_position.y, COLUMN.y)
		var release: Vector3 = p.global_position + p._get_forehand_axis() * active_hold.x + Vector3.UP * active_hold.y + p._get_forward_axis() * active_hold.z
		var plan: Dictionary = Styles.release_plan(p.global_position, p.player_num == 1, 0, release)
		for style in [0, 4]: flights.append(flight_summary(p, release, style))
		for step in range(21):
			active_charge = step / 20.0;export_frames = step in [0, 10, 20]
			var original: PostureDefinition = Candidate.apply(Motion.serve_style_preparation(0, active_charge, Styles.hold_offset(0)), active_charge)
			var main_target: Transform3D = Path.world_transform(p, original)
			sample(p, 0, active_charge, 0.0, plan)
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
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/vendor-raised-hold-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failure_count": failure_count, "failures": failures, "records": records, "flight_traces": flights, "scope": "One isolated1.25m hold; no production plan adoption"}, "\t"));file.close()
	for failure in failures: push_error(failure)
	print("VENDOR RAISED HOLD ", checks, " checks; ", failure_count, " failures; ", records.size(), " actual poses; ", flights.size(), " real Flight traces")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failure_count == 0 else 1)
