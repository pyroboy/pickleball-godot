extends "res://scripts/tests/test_human_incoming_contact.gd"

func run() -> void :
	create_timer(65).timeout.connect( func(): quit(2))
	var expected_returns: int = 0
	for def in PostureLibrary.instance().all_definitions():
		if not def.has_zone: continue
		for power in [0.3, 0.65, 1.0]:
			expected_returns += 1
			var game = await setup_game()
			var player = game.player_left
			incoming(game, def.paddle_forehand_mul, 1.0 + def.paddle_y_offset, 4.0)
			game.ball.global_position.z = player.global_position.z - def.zone_forward_offset - 0.65
			game.ball.linear_velocity.y = 1.1
			await physics_frame
			await physics_frame
			var human = player.posture.human_contact
			var tag: String = "%s %.0f%%" % [def.display_name, power * 100]
			check( not human.contact.is_empty(), tag + " cannot receive its authored contact")
			if human.contact.is_empty():
				game.queue_free()
				await process_frame
				continue
			check(human.contact.posture == def.posture_id, tag + " selects wrong posture %d" % human.contact.posture)
			var expected_contact: Vector3 = human.contact.point
			var distances: Array[float] = []
			var impacts: Array[Vector3] = []
			game.ball.hit_by_paddle.connect( func(id):
				if id == 0:
					distances.append(PaddleReach.head_world(player).distance_to(game.ball.global_position))
					impacts.append(game.ball.global_position)
			)
			Input.action_press("ui_accept")
			game.input_handler._handle_swing_charge(power * PickleballConstants.MAX_SERVE_CHARGE_TIME)
			check(player.posture.transition_pose_blend.paddle_hand == def.paddle_hand, tag + " charge uses wrong hand")
			Input.action_release("ui_accept")
			game.input_handler._handle_swing_charge(0)
			check(game.ball.last_hit_by == 1, tag + " hits before contact")
			for frame in range(55):
				await physics_frame
				if game.ball.last_hit_by == 0 or game.game_state != game.GameState.PLAYING: break
			check(distances.size() == 1, tag + " must return exactly once")
			if distances.size() == 1:
				returns += 1
				maximum_error = maxf(maximum_error, distances[0])
				check(distances[0] <= Planner.IMPACT_DISTANCE, tag + " misses actual paddle")
				check(impacts[0].distance_to(expected_contact) < 0.25, tag + " misses predicted impact")
			game.queue_free()
			await process_frame
	for failure in failures: push_error(failure)
	print("ALL STROKE CONTACTS: %d checks, %d failures; %d/%d returns; max impact error %.3f m" % [checks, failures.size(), returns, expected_returns, maximum_error])
	quit(0 if failures.is_empty() else 1)
