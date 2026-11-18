extends SceneTree
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")



func _initialize() -> void :
	call_deferred("run")

func run() -> void :
	seed(42091)
	var failures: Array[String] = []
	var returns: int = 0
	var max_shoulder_distance: float = 0.0
	var max_head_correction: float = 0.0
	for difficulty in range(3):
		for lane_x in [-1.5, 0.0, 1.5]:
			for arc_y in [2.5, 4.0, 5.5]:
				var game: Node = load("res://scenes/game.tscn").instantiate()
				root.add_child(game)
				await physics_frame
				await physics_frame
				game.player_right.global_position = Vector3(0.0, game.player_right.ground_y, -3.0)
				game.ai_difficulty = difficulty
				game.player_right.ai_brain.ai_difficulty = difficulty
				game._set_game_state(game.GameState.PLAYING)
				game.rally_scorer._serve_was_hit = true
				var ball: Ball = game.ball
				ball.reset_rally_state()
				ball.both_bounces_complete = true
				ball.global_position = Vector3(lane_x, 1.2, 3.5)
				ball.linear_velocity = Vector3(0.0, arc_y, -10.0)
				ball.angular_velocity = Vector3.ZERO
				ball.last_hit_by = 0
				ball.is_in_play = true
				ball.flight_id += 1
				var hit_measurement: = [INF, INF, INF]
				ball.hit_by_paddle.connect( func(player_num: int) -> void :
					if player_num == 1:
						hit_measurement[0] = PaddleReach.shoulder_world(game.player_right).distance_to(ball.global_position)
						hit_measurement[1] = preload("res://scripts/paddle_clearance.gd").distance_to_head_shape(game.player_right.paddle_node.to_local(ball.global_position))
						var def: PostureDefinition = game.player_right.posture.transition_pose_blend
						if def == null: def = PostureLibrary.instance().get_def(game.player_right.ai_desired_posture)
						var hand_offset: Vector3 = def.left_hand_offset if def.paddle_hand == 1 else def.right_hand_offset
						hit_measurement[2] = WristReach.displayed_wrist(game.player_right, def).distance_to(WristReach.live_shoulder(game.player_right, def)))
				var returned: bool = false
				for frame in range(160):
					await physics_frame
					if ball.last_hit_by == 1:
						returned = true
						break
					if game.game_state != game.GameState.PLAYING:
						break
				if returned:
					returns += 1
					max_shoulder_distance = maxf(max_shoulder_distance, hit_measurement[0])
					max_head_correction = maxf(max_head_correction, game.player_right.ai_brain.last_ai_contact_correction)
					if hit_measurement[0] > PaddleReach.MAX_HEAD_DISTANCE + 0.05:
						failures.append("d%d x%.1f arc%.1f hit beyond arm reach (%.2f m)" % [difficulty, lane_x, arc_y, hit_measurement[0]])
					if absf(hit_measurement[1] - 0.0375) > 0.0051:
						failures.append("d%d x%.1f arc%.1f hit detached/buried at visible surface (%.3f m)" % [difficulty, lane_x, arc_y, hit_measurement[1]])
					if hit_measurement[2] > 0.7001:
						failures.append("d%d x%.1f arc%.1f wrist exceeded connected arm (%.3f m)" % [difficulty, lane_x, arc_y, hit_measurement[2]])
					if game.player_right.ai_brain.last_ai_contact_correction > 0.001:
						failures.append("d%d x%.1f arc%.1f paddle jumped %.2f m at contact" % [difficulty, lane_x, arc_y, game.player_right.ai_brain.last_ai_contact_correction])
				else:
					failures.append("d%d x%.1f arc%.1f missed a reachable shot" % [difficulty, lane_x, arc_y])
				game.queue_free()
				await physics_frame
	print("AI RETURN SWEEP: %d/27 returns, maximum shoulder distance %.3f m, correction %.3f m" % [returns, max_shoulder_distance, max_head_correction])
	var varied_shots: Array[Dictionary] = [
		{"name": "topspin", "pos": Vector3(0, 1.3, 3.5), "vel": Vector3(0, 4, -10), "spin": Vector3(-35, 0, 0)}, 
		{"name": "backspin", "pos": Vector3(0, 1.3, 3.5), "vel": Vector3(0, 4, -10), "spin": Vector3(35, 0, 0)}, 
		{"name": "sidespin", "pos": Vector3(0, 1.3, 3.5), "vel": Vector3(0, 4, -10), "spin": Vector3(0, 35, 0)}, 
		{"name": "fast", "pos": Vector3(0, 1.3, 4.5), "vel": Vector3(0, 4, -15), "spin": Vector3(-25, 0, 0)}, 
		{"name": "soft", "pos": Vector3(0, 1.0, 2.5), "vel": Vector3(0, 3, -6), "spin": Vector3(-10, 0, 0)}, 
	]
	var varied_returns: int = 0
	for shot in varied_shots:
		var game: Node = load("res://scenes/game.tscn").instantiate()
		root.add_child(game)
		await physics_frame
		await physics_frame
		game.player_right.global_position = Vector3(0.0, game.player_right.ground_y, -3.0)
		game.ai_difficulty = 2
		game.player_right.ai_brain.ai_difficulty = 2
		game._set_game_state(game.GameState.PLAYING)
		game.rally_scorer._serve_was_hit = true
		var ball: Ball = game.ball
		ball.reset_rally_state()
		ball.both_bounces_complete = true
		ball.global_position = shot.pos
		ball.linear_velocity = shot.vel
		ball.angular_velocity = shot.spin
		ball.last_hit_by = 0
		ball.is_in_play = true
		ball.flight_id += 1
		var returned: bool = false
		for frame in range(160):
			await physics_frame
			if ball.last_hit_by == 1:
				returned = true
				break
			if game.game_state != game.GameState.PLAYING:
				break
		if returned:
			varied_returns += 1

		else:
			failures.append("%s shot was not returned" % shot.name)
		game.queue_free()
		await physics_frame
	print("AI VARIED RETURNS: %d/5" % varied_returns)
	if failures.is_empty():
		print("AI RETURN SWEEP PASS")
	else:
		for failure in failures:
			push_error(failure)
		print("AI RETURN SWEEP FAIL: ", failures)
	quit(0 if failures.is_empty() else 1)
