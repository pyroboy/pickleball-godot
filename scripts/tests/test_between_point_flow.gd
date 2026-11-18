extends SceneTree
class LateFrame extends Node:
	signal presented
	func _process(_delta: float) -> void : create_tween().tween_callback( func(): presented.emit())
const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
var failures: Array[String] = []
var checks: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: ", message)
func run() -> void :
	create_timer(180.0).timeout.connect( func(): quit(2))
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var late: = LateFrame.new()
	late.process_priority = 10000
	root.add_child(late)
	var controller = game.between_point_controller
	controller.phase_changed.connect( func(phase): print("[RETRIEVAL] ", phase, " t=", controller.elapsed))
	var cases: Array[Dictionary] = []
	for team in [0, 1]:
		for ball_team in [0, 1]:
			for lane in [-0.7, 0.7]:
				for parity in [0, 1]: cases.append({"team": team, "ball_team": ball_team, "lane": lane, "parity": parity})
	if OS.has_environment("RETRIEVAL_DIAG_FIRST"): cases = cases.slice(0, 1)
	if OS.has_environment("RETRIEVAL_DIAG_CASE"):
		var selected: int = int(OS.get_environment("RETRIEVAL_DIAG_CASE"));cases = cases.slice(selected, selected + 1)
	for case in cases:
		var team: int = case.team
		var ball_team: int = case.ball_team
		game.score_left = case.parity + 2
		game.score_right = case.parity + 3
		game.serving_team = team
		game._reset_ball()
		for player in [game.player_left, game.player_right]:
			var main_reach: float = player.right_arm_node.upper_pivot.global_position.distance_to(_wrist(player.right_arm_node))
			var support_reach: float = player.left_arm_node.upper_pivot.global_position.distance_to(_wrist(player.left_arm_node))
			check(main_reach <= 0.705 and support_reach <= 0.705, "reset synchronously presents reachable arms before another score")
		var ball_pos: = Vector3(case.lane, Ball.FLOOR_Y + Ball.BALL_RADIUS, 3.6 if ball_team == 0 else -3.6)
		game.ball.global_position = ball_pos
		game.ball.linear_velocity = Vector3.ZERO
		game._on_point_scored(team)
		check(controller.is_active(), "retrieval starts")
		check( not controller.is_ready_for_serve(), "serve waits for retrieval")
		var worst_grip: = 0.0
		var worst_support: = 0.0
		var worst_link_error: = 0.0
		var worst_stretch: = 1.0
		var worst_main_info: Dictionary = {}
		var prior_hand: Array = []
		var worst_turn: = 0.0
		var turn_info: Dictionary = {}
		var score: Array = [game.score_left, game.score_right]
		for frame in range(950):
			await physics_frame
			await late.presented
			if not controller.is_active(): break
			var hands: Array = []
			for hand_player in [game.player_left, game.player_right]:
				var q: Quaternion = hand_player.left_arm_node.hand_mesh.global_basis.get_rotation_quaternion()
				if prior_hand.size() == 2:
					var change: float = rad_to_deg(prior_hand[hand_player.player_num].angle_to(q))
					if change > worst_turn:
						worst_turn = change;turn_info = {"phase": controller.phase, "elapsed": controller.phase_elapsed, "team": hand_player.player_num, "mode": hand_player.arm_ik._hands.mode}
				hands.append(q)
			prior_hand = hands
			for player in [game.player_left, game.player_right]:


				var main_distance: float = player.right_arm_node.upper_pivot.global_position.distance_to(_wrist(player.right_arm_node))
				if main_distance > worst_grip:
					worst_grip = main_distance
					var pose: PostureDefinition = player.posture.transition_pose_blend
					worst_main_info = {"phase": controller.phase, "phase_time": controller.phase_elapsed, "team": player.player_num, "shoulder": player.right_arm_node.upper_pivot.global_position, "authored_shoulder": preload("res://scripts/stroke_body_pose.gd").shoulder_world(player, pose) if pose != null else Vector3.INF, "anchor": player.right_arm_node.hand_pivot.global_position, "paddle_grip": player.paddle_node.to_global(PaddleSize.MAIN_GRIP_OFFSET), "scale": player.right_arm_node.visual_stretch, "crouch": pose.crouch_amount if pose != null else -1}

				worst_support = maxf(worst_support, player.left_arm_node.upper_pivot.global_position.distance_to(_wrist(player.left_arm_node)))
				for arm in [player.right_arm_node, player.left_arm_node]:
					worst_stretch = maxf(worst_stretch, arm.visual_stretch)
					worst_link_error = maxf(worst_link_error, absf(arm.upper_pivot.global_position.distance_to(arm.forearm_pivot.global_position) - arm.upper_arm_length))
					worst_link_error = maxf(worst_link_error, absf(arm.forearm_pivot.global_position.distance_to(_wrist(arm)) - arm.forearm_length))
				if player.left_arm_node.upper_pivot.global_position.distance_to(_wrist(player.left_arm_node)) > 0.705:
					print("[ARM DIAG] phase=", controller.phase, " team=", player.player_num, " t=", controller.phase_elapsed, " shoulder=", player.left_arm_node.upper_pivot.global_position, " wrist=", player.left_arm_node.hand_pivot.global_position, " target=", controller.support_hand_target_for(player.player_num))
		print("[RETRIEVAL] max arms main=", worst_grip, " support=", worst_support, " detail=", worst_main_info)
		print("[HAND TURN] maximum=", worst_turn, " info=", turn_info)
		check(worst_turn <= 30.0, "retrieval hand orientation is continuous at fixed60fps")
		check(worst_grip <= 0.706 and worst_support <= 0.706, "both arms keep anatomical reach")
		check(worst_stretch <= 1.001 and worst_link_error < 0.0001, "both actual arm links keep their exact lengths through retrieval")
		check(game.game_serve._legal_service_feet(game.player_left if team == 0 else game.player_right, team), "actual server soles establish legal baseline stance")
		check(controller.last_result == "READY", "natural finish team=%d court=%d result=%s" % [team, ball_team, controller.last_result])
		check(game.game_state == game.GameState.WAITING and not game.ball.is_in_play, "ready is dead-ball WAITING")
		check([game.score_left, game.score_right] == score, "retrieval changes no score")
		check(game.serving_team == team, "retrieval retains server")
		if team != ball_team:
			check(controller.observed_bounces > 0 and controller.catch_after_bounce, "transfer visibly bounces before catch")
		else:
			check( not controller.used_offscreen_helper, "reachable own ball picked up")
		check(game.rally_scorer.check_server_position((game.player_left if team == 0 else game.player_right).global_position, team, int(game.get_server_score() % 2 == 0)).valid, "correct serve parity spot")
	game.serving_team = 0
	game._reset_ball()
	game.ball.global_position = Vector3(20, 0.1, 12)
	game._on_point_scored(0)
	for frame in range(950):
		await physics_frame
		if not controller.is_active(): break
	check(controller.used_offscreen_helper and controller.catch_after_bounce and controller.last_result == "READY", "offscreen feeder bounces then catches safely")
	game.ball.global_position = Vector3(20, 0.1, 12)
	game._on_point_scored(0)
	for frame in range(240):
		await physics_frame
		if controller.phase == "PASS": break
	check(controller.phase == "PASS", "physical transfer starts before pause fixture")
	var pass_position: Vector3 = game.ball.global_position
	var pass_elapsed: float = controller.elapsed
	paused = true
	await create_timer(0.25, true).timeout
	controller.skip()
	check(controller.is_active() and game.ball.global_position == pass_position and controller.elapsed == pass_elapsed, "pause freezes pass and ignores skip until resumed")
	check( not game.ball.can_process() and not game.ball.audio_synth.can_process(), "pause suspends ball and its audio synthesis")
	paused = false
	controller.skip()
	controller.skip()
	check( not controller.is_active() and game.ball.collision_mask == 7, "mid-transfer repeated skip restores collision ownership")
	game._on_point_scored(0)
	controller.skip()
	check( not controller.is_active() and game.game_state == game.GameState.WAITING, "skip reaches safe ready")
	game._on_point_scored(0)
	var position: Vector3 = game.player_left.global_position
	var phase_time: float = controller.elapsed
	paused = true
	await create_timer(0.25, true).timeout
	check(game.player_left.global_position == position and controller.elapsed == phase_time, "pause freezes retrieval movement/time")
	paused = false
	game.practice_launcher.start_drill("DRIVE")
	check( not controller.is_active() and game.game_state == game.GameState.PLAYING, "practice cancels retrieval")
	game.practice_launcher.stop_practice()
	game._on_point_scored(0)
	game._suspend_tool_gameplay()
	check( not controller.is_active(), "tool opening cancels retrieval")
	game._resume_tool_gameplay()
	game._on_point_scored(0)
	controller.elapsed = controller.TIMEOUT + 0.1
	await physics_frame
	await late.presented
	check( not controller.is_active() and controller.last_result == "TIMEOUT" and game.ball.collision_mask == 7, "timeout restores safe collision/ready state")
	game.ball.global_position = Vector3(20, 0.1, 12)
	game._on_point_scored(0)
	for frame in range(24): await physics_frame
	game.practice_launcher.start_drill("DINK", true)
	var practice_flight: int = game.ball.flight_id
	for frame in range(15): await physics_frame
	check( not controller.is_active() and game.practice_launcher.is_active and game.ball.flight_id == practice_flight, "stale helper cannot launch into replacement drill")
	game.practice_launcher.stop_practice()
	game._set_game_state(game.GameState.PLAYING)
	game.ball.is_in_play = true
	check( not controller.begin() and not controller.is_active(), "controller cannot start during live rally")
	game.ball.is_in_play = false
	game._set_game_state(game.GameState.WAITING)
	game.score_left = 10
	game.score_right = 8
	game.serving_team = 0
	game._reset_ball()
	game._on_point_scored(0)
	check(game.match_over and not controller.is_active(), "match win has no next-serve retrieval")
	game.request_rematch()
	check( not controller.is_active() and game.game_state == game.GameState.WAITING and game.score_left == 0, "rematch resets safely")
	print("BETWEEN POINTS: ", checks, " checks, ", failures.size(), " failures")
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game, late)
	quit(0 if failures.is_empty() else 1)

func _wrist(arm) -> Vector3:
	return arm.hand_mesh.global_transform * arm.articulated_hand.wrist_socket
