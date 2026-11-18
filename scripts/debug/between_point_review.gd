extends "res://scripts/debug/pose_simulation_review.gd"

func _build_scenarios() -> void :
	scenarios = [
		{"id": "pickup_blue", "name": "Server picks up and carries", "server": 0, "court": 0, "drill_mode": "BETWEEN", "expected_hits": 0, "expected_opponent_hits": 0}, 
		{"id": "handover_red", "name": "Blue pickup / lob / Red bounce-catch", "server": 1, "court": 0, "camera_player": 1, "drill_mode": "BETWEEN", "expected_hits": 0, "expected_opponent_hits": 0}, 
		{"id": "handover_blue", "name": "Red pickup / lob / Blue bounce-catch", "server": 0, "court": 1, "drill_mode": "BETWEEN", "expected_hits": 0, "expected_opponent_hits": 0}, 
		{"id": "handover_red_pickup", "name": "Blue retrieves and passes / collector view", "server": 1, "court": 0, "camera_player": 0, "drill_mode": "BETWEEN", "expected_hits": 0, "expected_opponent_hits": 0}, 
		{"id": "handover_blue_pickup", "name": "Red retrieves and passes / collector view", "server": 0, "court": 1, "camera_player": 1, "drill_mode": "BETWEEN", "expected_hits": 0, "expected_opponent_hits": 0}, 
		{"id": "offscreen_return", "name": "Offscreen helper / bounce / catch", "server": 0, "court": -1, "drill_mode": "BETWEEN", "expected_hits": 0, "expected_opponent_hits": 0}, 
	]

func _run_case(item: Dictionary) -> void :
	playing = true
	current = item.duplicate(true)
	samples = []
	frame_number = 0
	sim_time = 0.0
	hit_frame = -1
	stage = "READY"
	current.hits = []
	current.opponent_hits = []
	current.serve_drop_bounces = 0
	feet_established = [false, false]
	volley_follow_active = [false, false]
	current.events = []
	last_bounce_frame = -1
	observed_bounces = [0, 0]
	current.issues = []
	current.stages = {}
	last_captured_stage = ""
	await _setup_game()
	game.player_right.set_process(true)
	game.player_right.set_physics_process(true)
	game.player_right.show()
	game.serving_team = item.server
	game.score_left = 2
	game.score_right = 3
	game._reset_ball()
	await get_tree().physics_frame
	game.ball.show()
	game.ball.global_position = Vector3(-0.7, Flight.FLOOR_REST_Y, 3.6 if item.court == 0 else -3.6) if item.court >= 0 else Vector3(20, 0.1, 12)
	game.ball.linear_velocity = Vector3.ZERO
	game.ball.hit_by_paddle.connect(_on_hit)
	game.game_serve.serve_launched.connect(_on_serve_hit)
	var controller = game.between_point_controller
	controller.phase_changed.connect( func(value: String):
		stage = value
		_event(value))
	game._on_point_scored(item.server)
	while controller.is_active() and sim_time < 16.0:
		await _tick()
	current.pickup_contact_gap = controller.pickup_contact_gap
	current.catch_contact_gap = controller.catch_contact_gap
	current.retrieval_result = controller.last_result
	current.transfer_bounces = controller.observed_bounces
	current.catch_after_bounce = controller.catch_after_bounce
	current.used_offscreen_helper = controller.used_offscreen_helper
	if item.court >= 0 and controller.used_offscreen_helper: current.issues.append("Reachable pickup incorrectly used helper")
	if controller.last_result != "READY": current.issues.append("Natural retrieval did not finish: " + controller.last_result)
	if item.court != item.server and not controller.catch_after_bounce: current.issues.append("Server did not catch after actual floor bounce")
	_finish_case(item)

func _measure_body(player_override = null) -> Dictionary:
	var result: Dictionary = super._measure_body(player_override)
	var player = player_override if player_override != null else game.player_left
	var controller = game.between_point_controller
	result.retrieval_hand_gap = controller._hand_surface_gap(player.player_num, game.ball.global_position) if controller.is_active() and controller._carry_team == player.player_num else null
	return result

func _assert_live_geometry() -> void :
	super._assert_live_geometry()
	for sample in samples:
		for body in [sample, sample.opponent]:
			if body.retrieval_hand_gap != null and absf(body.retrieval_hand_gap) > 0.003:
				current.issues.append("Held ball/hand gap %.4fm at frame%d" % [body.retrieval_hand_gap, sample.frame])
				return

func _source_hashes() -> Dictionary:
	var hashes: Dictionary = super._source_hashes()
	for file in ["debug/between_point_review.gd", "camera/camera_rig.gd", "camera/between_point_camera.gd"]:
		hashes[file] = FileAccess.get_sha256("res://scripts/" + file)
	return hashes
