extends SceneTree
const Store = preload("res://scripts/mobile_serve_pose_store.gd")
const Feet = preload("res://scripts/player_nvz_state.gd")
var checks := 0
var failures: Array[String] = []
var game
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	Store.set_test_path("user://pose_store_tests/flat_setup_%d/serves.json" % OS.get_process_id())
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	for side in [0, 1]:
		for parity in [0, 1]:
			game.score_left = parity; game.score_right = parity; game.serving_team = side
			game.game_serve.select_serve_style(0); game._reset_ball(); game.game_serve._prepare_server(0)
			var player = game.player_left if side == 0 else game.player_right
			var pose: PostureDefinition = player.posture.transition_pose_blend
			check(is_equal_approx(pose.front_foot_forward, .04) and is_equal_approx(pose.back_foot_back, -.5), "exact approved Flat forward/back plant survives automatic setup")
			check(game.game_serve._legal_service_feet(player, side), "new automatic setup clears actual full shoes on both courts/parities")
			check(game.rally_scorer.check_server_position(player.global_position, side, parity + 1).valid, "automatic root remains legal service side")
			var chosen: Vector3 = game.between_point_controller._serve_position(side)
			check(is_equal_approx(absf(chosen.z), game.SERVE_RESET_DEPTH), "between-point carry chooses the same legal depth")
			var clearance := INF
			for foot in Feet.footprints(player):
				clearance = minf(clearance, foot.min.z - PickleballConstants.BASELINE_Z if side == 0 else -PickleballConstants.BASELINE_Z - foot.max.z)
			check(clearance > .02, "automatic stance includes positive shoe clearance")
			print("FLAT SETUP side", side, " parity", parity, " shoe baseline clearance=", clearance)
			player.global_position.z = 6.8 if side == 0 else -6.8
			player.posture.force_posture_update(pose); player.leg_ik.initialize_serve_stance(pose)
			check(not game.game_serve._legal_service_feet(player, side), "old 6.8m setup genuinely crosses baseline with approved footprint")
			check(game.game_serve._check_service_feet(player, side).boundary == "baseline", "old setup fails actual shoe boundary, not a synthetic root rule")
	# Reset all seven styles to the legal root without modifying their pose data.
	for style in range(7):
		game.serving_team = 0; game.game_serve.select_serve_style(style); game._reset_ball(); game.game_serve._prepare_server(0)
		check(game.game_serve._legal_service_feet(game.player_left, 0), "automatic setup supports style%d" % style)
	print("FLAT SERVE SETUP: %d checks, %d failures" % [checks, failures.size()])
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game)
	quit(0 if failures.is_empty() else 1)
