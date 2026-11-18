extends SceneTree
const WristReach = preload("res://scripts/paddle_wrist_reach.gd")
const PaddleDimensions = preload("res://scripts/paddle_dimensions.gd")


const Geometry = preload("res://scripts/paddle_clearance.gd")
var game
var hits: Array = []
var bounces: Array = []
var checks: = 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, detail: String):
	checks += 1
	if not ok: failures.append(detail)
func run():
	seed(70819)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.ball.hit_by_paddle.connect(record_hit)
	game.ball.bounced.connect( func(point): bounces.append(point))
	var p = game.practice_launcher
	game.score_left = 4
	game.score_right = 7
	game.serving_team = 0
	var original_difficulty: int = game.player_right.ai_brain.ai_difficulty
	for mode in ["DINK", "HANDS", "WIDE"]:
		for direction in [1, -1]:
			hits.clear()
			bounces.clear()
			p.start_drill("DINK" if mode == "WIDE" else mode, true, direction, "WIDE" if mode == "WIDE" else "STANDARD")
			p.loop_enabled = false
			var origin: Vector3 = game.ball.global_position
			var velocity: Vector3 = game.ball.linear_velocity
			check(game.ball.both_bounces_complete and p.status_text.contains("warm-start"), mode + " warm start not explicit")
			p.repeat_drill()
			check(game.ball.global_position.is_equal_approx(origin) and game.ball.linear_velocity.is_equal_approx(velocity), mode + " repeat feed is not deterministic")
			for frame in range(1500):
				await physics_frame
				if p._attempt_finished or p.exchange_count >= 10: break
			print("KITCHEN RESULT ", mode, " direction=", direction, " hits=", p.exchange_count, " reason=", p.last_failure)
			check(p.exchange_count >= 10, mode + " did not sustain ten real contacts direction " + str(direction))
			check(p.best_exchange_count == p.exchange_count, mode + " best count mismatch")
			for index in hits.size():
				var h: Dictionary = hits[index]
				check(h.team == index % 2, mode + " contact did not alternate between players")
				check(absf(h.surface - 0.0375) <= 0.0051, mode + " hit is detached from or buried inside visible paddle surface")
				check(h.volley == (mode == "HANDS"), mode + " wrong bounce/volley contact")
				check(h.wrist <= 0.7001, mode + " hit beyond anatomical wrist reach")
				if mode == "HANDS": check( not h.foot_fault, "hands player touched kitchen at volley")
			if mode == "HANDS":
				check(bounces.is_empty(), "fast hands acquired a floor bounce")
				check(hits.any( func(h): return absf(h.position.z) < PickleballConstants.NON_VOLLEY_ZONE and not h.foot_fault), "legal volley reaching over kitchen was not exercised")
			else:
				check(bounces.size() >= hits.size(), "dinking lacks a real bounce before every hit")
				for point in bounces:
					check(absf(point.z) <= PickleballConstants.NON_VOLLEY_ZONE and absf(point.x) < 2.45, "dink bounce missed safe shallow target")
			p.stop_practice()
			await physics_frame
			check(game.score_left == 4 and game.score_right == 7 and game.serving_team == 0, "exchange exit changed match state")
			check(game.player_right.ai_brain.ai_difficulty == original_difficulty and not p.demo_enabled, "exchange exit retained demo/difficulty")


	p.start_drill("DINK")
	p.loop_enabled = false
	for frame in range(250):
		await physics_frame
		if p._attempt_finished: break
	check(p._attempt_finished and p.exchange_count == 0 and p.last_failure == "DOUBLE_BOUNCE", "manual missing/late hit not rejected")
	var attempts: int = p.attempt_count
	p.loop_enabled = true
	p._process(p.PRACTICE_LOOP_INTERVAL + 0.01)
	check(p.attempt_count == attempts + 1 and p.exchange_count == 0 and p.last_failure.is_empty(), "repeat retained exchange history/failure")

	p.start_drill("HANDS", true)
	var pause = root.get_node("PauseController")
	pause.open()
	var paused_position: Vector3 = game.ball.global_position
	var paused_hits: int = p.exchange_count
	await create_timer(0.15, true).timeout
	check(game.ball.global_position.is_equal_approx(paused_position) and p.exchange_count == paused_hits, "paused exchange advanced")
	pause.close()
	p.stop_practice()

	p.start_drill("HANDS")
	p.loop_enabled = false
	game.player_left.global_position.z = 1.8
	game.player_left.leg_ik.feet_initialized = false
	game.ball.hit_by_player(0)
	check(p._attempt_finished and p.last_failure == "KITCHEN_VOLLEY" and p.exchange_count == 0, "kitchen volley counted as legal exchange")
	p.repeat_drill()
	game.player_left.leg_ik.feet_initialized = true
	game.player_left.leg_ik._last_body_position = game.player_left.global_position
	game.player_left.leg_ik.right_foot_smooth = Vector3(0.1, PickleballConstants.FLOOR_Y, 2.72)
	game.player_left.leg_ik.left_foot_smooth = Vector3(-0.1, PickleballConstants.FLOOR_Y, 2.72)
	var shoe_box: Dictionary = preload("res://scripts/player_nvz_state.gd").footprints(game.player_left)[0]
	game.player_left.leg_ik.right_foot_smooth.z += PickleballConstants.NON_VOLLEY_ZONE - 0.0002 - shoe_box.min.z
	game.ball.hit_by_player(0)
	check(p._attempt_finished and p.last_failure == "KITCHEN_VOLLEY", "foot on painted kitchen line was legal")
	p.repeat_drill()

	game.player_left.leg_ik.feet_initialized = true
	game.player_left.leg_ik._last_body_position = game.player_left.global_position
	game.player_left.leg_ik.right_foot_smooth = Vector3(0.1, PickleballConstants.FLOOR_Y, 2.72)
	game.player_left.leg_ik.left_foot_smooth = Vector3(-0.1, PickleballConstants.FLOOR_Y, 2.72)
	game.ball.hit_by_player(0)
	game.player_left.leg_ik.right_foot_smooth.z = 1.8
	game.rally_scorer._physics_process(1.0 / 60.0)
	check(p._attempt_finished and p.last_failure == "MOMENTUM", "kitchen momentum fault not preserved")
	p.stop_practice()
	p.stop_practice()
	check(game.score_left == 4 and game.score_right == 7 and game.serving_team == 0, "repeated exit lost match snapshot")
	check( not p.is_exchange_demo() and game.game_state == game.GameState.WAITING, "exit did not return to a clean serve setup")
	game.queue_free()
	await process_frame
	await process_frame
	for failure in failures: push_error(failure)
	print("KITCHEN EXCHANGES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func record_hit(team):
	var player = game.player_left if team == 0 else game.player_right
	var def = player.posture.transition_pose_blend if player.posture.transition_pose_blend else PostureLibrary.instance().get_def(player.paddle_posture)
	var hand_offset: Vector3 = def.left_hand_offset if def.paddle_hand == 1 else def.right_hand_offset
	var grip: Vector3 = player.paddle_node.global_transform * (PaddleDimensions.MAIN_GRIP_OFFSET + hand_offset)
	hits.append({"team": team, "position": game.ball.global_position, "volley": game.ball.was_volley, 
		"surface": Geometry.distance_to_head_shape(player.paddle_node.to_local(game.ball.global_position)), 
		"grip": grip.distance_to(WristReach.live_shoulder(player, def)), "wrist": WristReach.displayed_wrist(player, def).distance_to(WristReach.live_shoulder(player, def)), "foot_fault": game.rally_scorer._ground_contact_in_kitchen(player)})
