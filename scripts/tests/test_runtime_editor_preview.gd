extends SceneTree
const Preview = preload("res://scripts/posture_editor_v2/runtime_motion_preview.gd")
const Motion = preload("res://scripts/drive_serve_motion.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
var failures: Array[String] = []
var checks: = 0
func _initialize(): call_deferred("run")
func check(ok: bool, text: String):
	checks += 1
	if not ok: failures.append(text)
func run():
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	create_timer(35).timeout.connect( func(): quit(2))
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await process_frame
	game._toggle_posture_editor_v2()
	var editor = game.posture_editor_v2
	editor._on_posture_selected(0)
	var source: PostureDefinition = editor._current_def
	var before: PostureDefinition = source.duplicate(true)
	for technique in range(7):
		editor._technique_picker.select(technique)
		for mode in range(3):
			editor._preview_spin.select(mode)
			for charge in [0.25, 1.0]:
				editor._preview_charge.set_value_no_signal(charge)
				editor._on_runtime_preview_changed()
				for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
					editor._on_swing_scrubbed(t)
					await process_frame
					var expected = Preview.sample(source, t, technique, charge, mode)
					check(game.player_left.paddle_node.global_transform.is_equal_approx(Path.world_transform(game.player_left, expected)), "visible runtime preview disagrees technique%d spin%d power%.2f t%.2f" % [technique, mode, charge, t])
					check(game.player_left.posture.transition_pose_blend.crouch_amount == expected.crouch_amount, "preview body sampler parity")

		editor._on_preview_swing()
		var tp = editor._transition_player
		tp.pause()
		for phase in [TransitionPlayer.Phase.CONTACT, TransitionPlayer.Phase.FOLLOW_THROUGH]:
			tp._current_phase = phase
			tp._phase_time = tp.phase_durations[phase] * 0.42
			tp._apply_phase_pose()
			var progress = tp.path_progress(0 if phase == TransitionPlayer.Phase.CONTACT else 1, 0.42)
			check(game.player_left.paddle_node.global_transform.is_equal_approx(Path.world_transform(game.player_left, Preview.sample(source, progress, technique, 1.0, 2))), "play and scrub path disagree")
	check(editor._dirty_defs.is_empty(), "runtime preview dirties authored data")
	for prop in source.get_property_list():
		if (prop.usage & PROPERTY_USAGE_STORAGE) != 0 and source.get(prop.name) is float:
			check(is_equal_approx(source.get(prop.name), before.get(prop.name)), "preview modifies saved field " + prop.name)
	editor._technique_picker.select(0)
	editor._select_keyframe(1)
	await process_frame
	check(game.player_left.paddle_node.global_transform.is_equal_approx(Path.world_transform(game.player_left, source)), "return to authored contact failed")
	editor.close()
	game.queue_free()
	await process_frame
	await process_frame
	print("RUNTIME EDITOR PREVIEW: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
