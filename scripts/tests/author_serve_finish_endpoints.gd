extends "res://scripts/tests/author_serve_neutral_endpoints.gd"

func run():
	source_phase = "FINISH"
	output = "/workspace/shared/pickleball-hands/neutral-serve-finish-rig.json"
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	var p = game.player_left;p.posture.editor_preview_mode = false
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false
	p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	surface = Paddle.sample_head_surface()
	for x in [ - 0.12, 0.0, 0.12]:
		for y in [0.05, 0.15, 0.25]:
			for forward in [0.4, 0.5]:
				for hint in [Vector3(0.3, 0.0, 0.25), Vector3(0.4, 0.1, 0.35)]:
					for axial in [0.0]:
						var config: = {"wrist_x": x, "wrist_y": y, "wrist_forward0": forward, "load_backshift": 0.0, "axial": axial, "pole_x": hint.x, "pole_y": hint.y, "pole_forward": hint.z}
						sample(p, config, 0, 1.0, 0.0)
	var file: = FileAccess.open(output, FileAccess.WRITE);file.store_string(JSON.stringify(rows, "\t"));file.close()
	print("NEUTRAL SERVE FINISH RIG ", rows.size(), " -> ", output)
	game.queue_free(); await process_frame;quit()
