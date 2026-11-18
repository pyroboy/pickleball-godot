extends "res://scripts/tests/author_serve_neutral_endpoints.gd"


func run():
	output = "/workspace/shared/pickleball-hands/neutral-prep-leg-clearance.json"
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left;p.posture.editor_preview_mode = false
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	surface = Paddle.sample_head_surface()
	for forward in [0.1, 0.25]:
		var config: = {"wrist_x": 0.42, "wrist_y": - 0.12, "wrist_forward0": forward, "load_backshift": 0.1, "axial": 0.0, "pole_x": 0.42, "pole_y": 0.04, "pole_forward": - 0.05}
		for style in [0, 2, 3, 4]:
			for charge in [0.0, 0.5, 1.0]: sample(p, config, style, charge, 0.0)
	var occluded: = {"wrist_x": 0.42, "wrist_y": - 0.12, "wrist_forward0": 0.1, "load_backshift": 0.1, "axial": -30.0, "pole_x": 0.42, "pole_y": 0.04, "pole_forward": - 0.05}
	sample(p, occluded, 0, 1.0, 0.0)
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("NEUTRAL PREP LEG CLEARANCE ", rows.size(), " -> ", output)
	game.queue_free(); await process_frame;quit()
