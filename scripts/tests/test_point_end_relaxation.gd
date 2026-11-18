extends SceneTree
const Path = preload("res://scripts/stroke_swing_path.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Styles = preload("res://scripts/serve_style.gd")
const Geometry = preload("res://scripts/paddle_clearance.gd")
var failures: Array[String] = []
var checks: = 0
var max_step: = 0.0
var min_clearance: = INF
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and failures.size() < 20: failures.append(label)
func run():
	create_timer(120).timeout.connect( func(): push_error("Point-end relaxation timeout");quit(2))
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame; await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.game_serve.cleanup()
	var metrics = load("res://scripts/debug/pose_simulation_review.gd").new()
	metrics.surface = Geometry.sample_head_surface()
	var controller = game.between_point_controller
	var ready = PostureLibrary.instance().get_def(20)
	var cases: Array = []
	for yaw in [-95.0, -72.0, 0.0, 72.0, 95.0]:
		cases.append({"pose": Path.rotate_guard(ready, yaw), "serve": false, "tag": "guard%.0f" % yaw})
	for style in range(7):
		for charge in [0.0, 0.5, 1.0]:
			var hold: PostureDefinition = Motion.serve_style_preparation(style, charge, Styles.hold_offset(style))
			var poses: Array = [hold, Motion.serve_style_wait(hold, 0.5, style), Motion.serve_style_strike(hold, 0.5, style), Motion.serve_style_contact(style), Motion.serve_style_follow_through(style, charge, 0.5), Motion.serve_style_follow_through(style, charge, 1.0)]
			for phase in range(poses.size()):
				cases.append({"pose": poses[phase], "serve": true, "tag": "serve%d charge%.1f phase%d" % [style, charge, phase]})
	for item in cases:
		if not OS.get_environment("POINT_END_CASE").is_empty() and not item.tag.contains(OS.get_environment("POINT_END_CASE")): continue
		for fps in [30, 60, 120]:
			controller.cancel();game.game_state = game.GameState.POINT_SCORED;game.match_over = false
			var previous: Array[Quaternion] = []
			for p in [game.player_left, game.player_right]:
				p.hitting.serving_visual_active = item.serve;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
				p.current_velocity = Vector3.ZERO;p.posture.editor_preview_mode = false
				var pose = item.pose
				p.posture.transition_pose_blend = pose;p.posture.force_posture_update(pose)
				previous.append(p.paddle_node.global_basis.get_rotation_quaternion())
			check(controller.begin(), "point-end settle begins")
			for team in [0, 1]:
				check(Path.paddle_basis([game.player_left, game.player_right][team], controller.pose_for(team)).get_rotation_quaternion().angle_to(previous[team]) < 0.001, "ownership entry preserves displayed orientation")
			for frame in range(int(ceil(0.35 * fps))):
				controller._physics_process(1.0 / fps)
				for team in [0, 1]:
					var p = [game.player_left, game.player_right][team];p._process(1.0 / fps)
					var rotation: Quaternion = p.paddle_node.global_basis.get_rotation_quaternion()
					var angle: float = rad_to_deg(previous[team].angle_to(rotation));max_step = maxf(max_step, angle)
					check(angle <= 900.0 / fps + 0.05, "bounded point-end rotation %s fps%d frame%d" % [item.tag, fps, frame]);previous[team] = rotation
					for arm in [p.right_arm_node, p.left_arm_node]: check(arm.upper_pivot.global_position.distance_to(arm.hand_pivot.global_position) <= 0.705, "point-end arm reach %s fps%d frame%d" % [item.tag, fps, frame])
					var clearances: Dictionary = metrics._limb_clearances(p, p.paddle_node.global_transform)
					for key in clearances:
						var value: float = clearances[key];min_clearance = minf(min_clearance, value);check(value >= - 0.002, "point-end paddle/limb clearance %s fps%d frame%d %s gap%.4f" % [item.tag, fps, frame, key, value])
					var head: Vector3 = p.body_pivot.get_node("TorsoMesh/HeadMesh").global_position
					check(Geometry.distance_to_paddle_shape(p.paddle_node.to_local(head)) - 0.12 >= 0, "point-end face clearance %s fps%d frame%d" % [item.tag, fps, frame])
	controller.cancel();metrics.free();game.queue_free(); await process_frame
	print("POINT END RELAXATION: ", checks, " checks; maxstep=", max_step, " minlimb=", min_clearance, "; failures=", failures)
	quit(0 if failures.is_empty() else 1)
