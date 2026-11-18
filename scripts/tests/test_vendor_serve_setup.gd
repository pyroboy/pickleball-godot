extends "res://scripts/tests/test_vendor_serve_live.gd"
func run():
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	game.input_handler.set_process(false)
	late = LateFrame.new();late.process_priority = 10000;root.add_child(late)
	game.player_right.set_ai_movement_enabled(false)
	for side in [0, 1]:
		game.serving_team = side;game._reset_ball()
		var player = game.player_left if side == 0 else game.player_right
		for frame in range(8): await tick(player, "idle settle")
	print("VENDOR SERVE SETUP ", checks, " checks; ", failures.size(), " failures; wrist gap ", maximum_wrist_gap)
	for failure in failures: push_error(failure)
	await preload("res://scripts/tests/hand_scene_teardown.gd").finish(self, game, late)
	quit(0 if failures.is_empty() else 1)
