extends "res://scripts/tests/test_serve_phase_geometry.gd"
func run():
	export_frames = true
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	for frame in range(5): await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED;game.game_serve.cleanup()
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false);node.set_physics_process(false)
	surface = G.sample_head_surface()
	var p = game.player_left
	p.hitting.serving_visual_active = false;p.hitting.charge_visual_active = false;p.hitting.is_in_follow_through = false;p.current_velocity = Vector3.ZERO;p.posture._committed_incoming_posture = -1
	for style in [0, 4]:
		var plan: Dictionary = Styles.release_plan(p.global_position, false, style)
		for q in [0.0, 1.0]: sample(p, style, q, 0.0, plan)
	var file: = FileAccess.open("/workspace/shared/pickleball-hands/held-cup-frames.json", FileAccess.WRITE);file.store_string(JSON.stringify(records, "\t"));file.close()
	print("HELD CUP FRAMES: ", records.size(), " actual supported poses")
	game.queue_free(); await process_frame;quit()
