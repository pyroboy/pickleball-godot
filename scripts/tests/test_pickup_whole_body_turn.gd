extends SceneTree

# Real scored-point pickup, carry and service handoff on both court halves.
# Checks the rendered rig and world-space foot contacts, not just pose fields.
class LateFrame extends Node:
	signal presented
	func _process(_delta: float) -> void:
		create_tween().tween_callback(func(): presented.emit())

const Path = preload("res://scripts/stroke_swing_path.gd")
var checks := 0
var failures: Array[String] = []
var cases: Array = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func heading(node: Node3D, forward: Vector3) -> float:
	var direction: Vector3 = node.global_basis * forward
	direction.y = 0.0
	return forward.signed_angle_to(direction.normalized(), Vector3.UP)

func run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	var late := LateFrame.new(); late.process_priority = 10000; root.add_child(late)
	for team in [0, 1]:
		for approach in [Vector2(0, -1.8), Vector2(0, 1.8), Vector2(-2.0, 0), Vector2(2.0, 0)]:
			game.serving_team = team; game.score_left = 0; game.score_right = 0; game.match_over = false; game._reset_ball()
			var player = game.player_left if team == 0 else game.player_right
			var controller = game.between_point_controller
			var forward: Vector3 = player._get_forward_axis()
			var ball_position := Vector3(0.2, Ball.FLOOR_Y + Ball.BALL_RADIUS, 3.5 * (1 if team == 0 else -1))
			player.global_position = controller._pickup_root(ball_position, player) + player._get_forehand_axis() * approach.x + forward * approach.y
			player.leg_ik.feet_initialized = false; player._process(0.0)
			game.ball.global_position = ball_position; game.ball.linear_velocity = Vector3.ZERO
			game._on_point_scored(team)
			var tag := "team%d approach%s" % [team, approach]
			var root_before: Vector3 = player.global_position
			var prior_heading := heading(player.body_pivot, forward)
			var prior_phase := ""
			var prior_tick: int = Engine.get_physics_frames()
			var max_turn_rate := 0.0; var heading_in_sync := true
			var foot_positions: Array[Vector3] = [player.leg_ik.right_foot_smooth, player.leg_ik.left_foot_smooth]
			var foot_yaw: Array[float] = [player.leg_ik._right_yaw, player.leg_ik._left_yaw]
			var serials: Array[int] = [player.leg_ik.right_contact_serial, player.leg_ik.left_contact_serial]
			var max_heading_error := 0.0; var max_rig_error := 0.0; var max_paddle_error := 0.0
			var max_turn_step := 0.0; var max_root_step := 0.0; var max_root_speed := 0.0; var max_locked_drift := 0.0; var max_locked_turn := 0.0
			var max_held_gap := 0.0; var max_heading := 0.0; var saw_bend := false; var saw_lift := false; var serve_planted := false
			for frame in range(1050):
				await physics_frame; await late.presented
				if not controller.is_active(): break
				var leg = player.leg_ik
				var body_heading := heading(player.body_pivot, forward)
				var elapsed: float = float(Engine.get_physics_frames() - prior_tick) / Engine.physics_ticks_per_second
				var root_step: float = root_before.distance_to(player.global_position)
				max_root_step = maxf(max_root_step, root_step)
				max_root_speed = maxf(max_root_speed, root_step / maxf(elapsed, 1.0 / Engine.physics_ticks_per_second))
				root_before = player.global_position
				if controller.phase in ["APPROACH", "CARRY"]:
					max_heading = maxf(max_heading, absf(leg._heading_angle))
					var heading_error: float = absf(angle_difference(body_heading, leg._heading_angle))
					max_heading_error = maxf(max_heading_error, heading_error)
					var turn_budget: float = deg_to_rad(leg.TURN_RATE * maxf(elapsed, 1.0 / Engine.physics_ticks_per_second) + 0.05)
					heading_in_sync = heading_in_sync and heading_error <= turn_budget
					if prior_phase == controller.phase:
						var turn: float = absf(angle_difference(prior_heading, body_heading))
						max_turn_step = maxf(max_turn_step, turn)
						max_turn_rate = maxf(max_turn_rate, turn / maxf(elapsed, 1.0 / Engine.physics_ticks_per_second))
					for part in [player.body_pivot.get_node("HipsMesh"), player.body_pivot.get_node("TorsoMesh")]:
						max_rig_error = maxf(max_rig_error, absf(angle_difference(body_heading, heading(part, forward))))
					var pose: PostureDefinition = player.posture.transition_pose_blend
					max_paddle_error = maxf(max_paddle_error, Path.paddle_basis(player, pose).get_rotation_quaternion().angle_to(player.paddle_node.global_basis.get_rotation_quaternion()))
					check(is_equal_approx(pose.right_foot_yaw_deg, 5.0) and is_equal_approx(pose.left_foot_yaw_deg, 5.0), tag + " foot heading applied twice")
				if controller.phase == "BEND" and not saw_bend:
					saw_bend = true
					check(player.current_velocity.length() < 0.06 and leg.right_foot_locked and leg.left_foot_locked, tag + " bent before planted stop")
				if controller.phase == "LIFT": saw_lift = true
				if controller.phase == "SET_SERVE" and prior_phase != "SET_SERVE":
					serve_planted = leg.is_support_ready(0) and leg.is_support_ready(1) and absf(body_heading) < deg_to_rad(1)
				if controller._carry_team == team:
					max_held_gap = maxf(max_held_gap, game.ball.global_position.distance_to(controller._hand_ball_position(team, controller._carry_direction)))
				var now: Array[Vector3] = [leg.right_foot_smooth, leg.left_foot_smooth]
				var turns: Array[float] = [leg._right_yaw, leg._left_yaw]
				var contacts: Array[int] = [leg.right_contact_serial, leg.left_contact_serial]
				for side in [0, 1]:
					if (leg.right_foot_locked if side == 0 else leg.left_foot_locked) and contacts[side] == serials[side]:
						max_locked_drift = maxf(max_locked_drift, now[side].distance_to(foot_positions[side]))
						max_locked_turn = maxf(max_locked_turn, absf(angle_difference(foot_yaw[side], turns[side])))
				foot_positions = now; foot_yaw = turns; serials = contacts
				prior_heading = body_heading; prior_phase = controller.phase; prior_tick = Engine.get_physics_frames()
			check(controller.last_result == "READY" and not controller.is_active() and not controller.used_offscreen_helper, tag + " pickup did not complete naturally")
			check(saw_bend and saw_lift and absf(controller.pickup_contact_gap) < 0.012, tag + " actual ball pickup missing")
			check(max_heading > deg_to_rad(90), tag + " did not exercise a large carry turn")
			# Physics authors the pose before the render support update: at most one
			# render turn step is expected, rather than a frozen or doubled heading.
			check(heading_in_sync, tag + " body did not follow travel heading")
			check(max_rig_error < 0.00001 and max_paddle_error < deg_to_rad(0.1), tag + " torso/hips/paddle did not share body turn")
			check(max_turn_rate <= deg_to_rad(player.leg_ik.TURN_RATE + 0.1), tag + " whole body snapped while turning")
			check(max_root_speed <= controller.RUN_SPEED + 0.05, tag + " root teleported")
			check(max_locked_drift < 0.00001 and max_locked_turn < 0.00001, tag + " planted feet slid or spun")
			check(max_held_gap < 0.00001, tag + " held ball detached during whole-body turn")
			check(serve_planted and game.game_state == game.GameState.WAITING and game.game_serve._legal_service_feet(player, team), tag + " service handoff happened before court-facing replant")
			cases.append({"case": tag, "result": controller.last_result, "max_body_heading_error_deg": rad_to_deg(max_heading_error), "max_turn_step_deg": rad_to_deg(max_turn_step), "max_turn_rate_deg_s": rad_to_deg(max_turn_rate), "max_rig_error_deg": rad_to_deg(max_rig_error), "max_paddle_error_deg": rad_to_deg(max_paddle_error), "max_root_step_m": max_root_step, "max_root_speed_m_s": max_root_speed, "max_planted_drift_m": max_locked_drift, "max_held_ball_gap_m": max_held_gap, "serve_planted": serve_planted})
	for failure in failures: push_error(failure)
	print("PICKUP WHOLE BODY: ", checks, " checks, ", failures.size(), " failures; ", JSON.stringify(cases))
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game, late)
	quit(0 if failures.is_empty() else 1)
