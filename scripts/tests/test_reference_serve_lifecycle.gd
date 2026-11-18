extends SceneTree


const Geometry = preload("res://scripts/paddle_clearance.gd")
var checks: = 0
var contacts: = 0
var failures: Array[String] = []
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func run() -> void :
	create_timer(90).timeout.connect( func(): quit(2))
	for side in [0, 1]:
		for style in range(7):
			var game = load("res://scenes/game.tscn").instantiate()
			root.add_child(game); await physics_frame
			game.input_handler.set_process(false)
			game.serving_team = side;game._reset_ball()
			var serve = game.game_serve
			serve.select_serve_style(style)
			for i in range(24): await physics_frame
			var player = game.player_left if side == 0 else game.player_right
			var tag: = "side%d style%d" % [side, style]
			serve.start_charge();serve.tick_charge(0.25 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
			serve.cleanup()
			check( not serve.is_charging() and not serve.is_release_pending(), tag + " cancels partial hold")
			game._reset_ball()
			for i in range(2): await physics_frame
			check(player.paddle_node.global_basis.y.y > 0.45, tag + " returns to raised resting blade")
			serve.start_charge();serve.tick_charge(0.25 * PickleballConstants.MAX_SERVE_CHARGE_TIME)
			var hits: Array[float] = []
			serve.serve_launched.connect( func(_team: int):
				hits.append(Geometry.distance_to_head_shape(player.paddle_node.to_local(game.ball.global_position)) - Ball.BALL_RADIUS))
			serve.release(0.25)
			for i in range(120):
				if not hits.is_empty(): break
				await physics_frame
			check(hits.size() == 1, tag + " one physical quarter-charge contact")
			if not hits.is_empty():
				contacts += 1
				check(absf(hits[0]) < 0.003, tag + " exact surface contact")
				check(is_equal_approx(game.ball.get_meta("shot_profile").charge, 0.25), tag + " quarter charge preserved")
			game.ball.freeze = true
			game.ball.is_in_play = false
			game.set_physics_process(false)
			game.player_right.set_ai_movement_enabled(false)
			for i in range(52): await physics_frame
			check( not player.hitting.serving_visual_active and not player.hitting.is_in_follow_through, tag + " releases animation ownership")
			game.serving_team = side;game._reset_ball()
			for i in range(2): await physics_frame
			check(player.paddle_node.global_basis.y.y > 0.45, tag + " fresh serve restores reference hold")
			check( not serve.is_release_pending() and not game.ball.is_in_play, tag + " fresh serve has no stale shot")
			game.queue_free(); await process_frame
	for failure in failures: push_error(failure)
	print("REFERENCE SERVE LIFECYCLE: %d checks, %d failures; %d/14 quarter-charge contacts" % [checks, failures.size(), contacts])
	quit(0 if failures.is_empty() else 1)
