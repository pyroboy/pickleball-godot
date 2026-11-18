extends "res://scripts/tests/test_split_step_runtime.gd"
## Deterministic presentation capture using production observer + full rig.
## Run by release owner in a rendered session. No asset/resource writes.
func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Split capture needs a rendered session"); quit(2); return
	var folder := "/tmp/split-step-capture"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): folder = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(960, 900); root.content_scale_size = Vector2i(960, 900)
	DisplayServer.window_set_size(Vector2i(960, 900))
	var pause = root.get_node_or_null("PauseController")
	if pause:
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
		pause.close()
	paused = false
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	for frame in 5: await process_frame
	game.game_serve.cleanup(); game.process_mode = Node.PROCESS_MODE_DISABLED
	for tween in get_processed_tweens(): tween.kill()
	for node in game.find_children("*", "Node", true, false): node.set_process(false); node.set_physics_process(false)
	for child in game.get_children():
		if child is CanvasLayer: child.visible = false
	var camera := Camera3D.new(); game.add_child(camera); camera.make_current(); camera.fov = 39; camera.near = .01
	var layer := CanvasLayer.new(); root.add_child(layer)
	var caption := Label.new(); caption.position = Vector2(20, 18); caption.add_theme_font_size_override("font_size", 22); layer.add_child(caption)
	for p in [game.player_left, game.player_right]:
		for lead in [.08, .20, .03]:
			var ready := fixture(p)
			var opponent = game.player_right if p.player_num == 0 else game.player_left
			var original = opponent.posture.human_contact
			if original == null: opponent.posture.human_contact = Human.new(opponent, opponent.posture)
			var human = opponent.posture.human_contact
			var label := "quick_low" if lead < .1 else "more_preparation"
			if lead < .06: label = "late_grounded"
			var destination: String = folder.path_join("side%d_%s" % [p.player_num, label]); DirAccess.make_dir_recursive_absolute(destination)
			var focus: Vector3 = p.global_position + Vector3(0, -.12, 0)
			camera.global_position = focus + p._get_forward_axis() * 2.75 + p._get_forehand_axis() * 1.15 + Vector3.UP * .10
			camera.look_at(focus, Vector3.UP)
			var struck := false
			for frame in 72:
				var elapsed: float = frame / 60.0
				if elapsed >= .10 and not struck:
					human.phase = 1; human.hit = false; human.strike_time = lead; human.elapsed = elapsed - .10
				if elapsed >= .10 + lead and not struck:
					game.ball.hit_by_player(opponent.player_num); human.hit = true; human.phase = -1; struck = true
				p.ai_brain._observed_flight_id = game.ball.flight_id; p.ai_brain._perception_ready = elapsed > .50; p.ai_brain.ai_selected_contact_reachable = false
				var motion: Vector3 = p._get_forehand_axis() * .85 if elapsed > .58 and elapsed < .93 else Vector3.ZERO
				p.current_velocity = motion
				p.pose_controller.update_runtime_pose_state(1.0 / 60)
				tick(p, ready, motion, 1.0 / 60)
				var sample: Dictionary = p.pose_controller.split_step.sample()
				caption.text = "P%d | %s | %s\nLift %.1f mm | applied R/L toe-down %.1f° / %.1f°\nObserved cue %d ms" % [p.player_num, label, sample.phase, sample.foot_lift * 1000, p.leg_ik.applied_foot_pitch_deg[0], p.leg_ik.applied_foot_pitch_deg[1], roundi(lead * 1000)]
				await process_frame; await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(destination.path_join("frame%04d.png" % frame))
				records.append({"side": p.player_num, "case": label, "frame": frame, "sample": sample, "applied_pitch": p.leg_ik.applied_foot_pitch_deg.duplicate(), "right_sole": sole_y(p.right_leg_node.foot_mesh), "left_sole": sole_y(p.left_leg_node.foot_mesh)})
			opponent.posture.human_contact = original
	var file := FileAccess.open(folder.path_join("frames.json"), FileAccess.WRITE); file.store_string(JSON.stringify(records, "\t")); file.close()
	print("SPLIT MOTION CAPTURE ", folder, " frames=", records.size())
	game.queue_free(); await process_frame; quit()
