extends "res://scripts/tests/cloud_temporal_aiming_audit.gd"
## Run the proposed focus patch as a separate scene instance; production file is untouched.
const Arc = preload("res://scripts/ui/aim_arc_style.gd")
var use_production := false

func _initialize() -> void:
	output = "/tmp/cloud_arc_style_integration.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="): rate = int(arg.trim_prefix("--rate="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=" )
		if arg == "--use-production": use_production = true
	Engine.physics_ticks_per_second = rate
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(720,1280)
	var pause = root.get_node("PauseController")
	if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
	if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	game = load("res://scenes/game.tscn").instantiate(); root.add_child(game); current_scene = game
	for i in 12: await process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	if not use_production:
		var original = game.aim_focus
		original.cancel(); original.set_process(false)
		game.remove_child(original); original.queue_free()
		var candidate = load("res://tools/cloud_qa/arc_style_focus_candidate.gd").new()
		game.add_child(candidate); candidate.setup(game); game.aim_focus = candidate
	focus = game.aim_focus; focus.set_process(false)
	check(focus.get_script().get_script_constant_map().has("ArcStyle"), "testing the intended arc-style integration")
	camera = root.get_camera_3d(); camera_initial = camera.global_transform
	var rows: Array = []
	for mode in ["static", "smooth_aim", "smooth_camera", "smooth_player"]:
		prepare_rally(); game.ball.freeze = true
		var target: Vector3 = game.aim_controller.get_target()
		var contact: Vector3 = game.player_left.posture.human_contact.contact.point
		var prior_lines := PackedVector2Array()
		var static_changes := 0
		var max_target_error := 0.0
		var solves_before: int = focus.preview_solves
		for frame in range(3 * rate + 1):
			var t := float(frame) / float(rate)
			var now := clock_usec + roundi(t * 1000000.0)
			match mode:
				"smooth_aim": game.aim_controller.target = target + Vector3(0.7 * sin(t * TAU / 3.0), 0, 0)
				"smooth_camera": camera.global_position = camera_initial.origin + camera.global_basis.x * 0.25 * sin(t * TAU / 3.0)
				"smooth_player": game.player_left.posture.human_contact.contact.point = contact + Vector3(0.3 * sin(t * TAU / 3.0), 0, 0)
			focus._update_presentation(now)
			var raw_copy: PackedVector3Array = focus._last_estimate.points.duplicate()
			check(focus._world_path == raw_copy, mode + " raw estimator points remain authoritative and unmodified")
			var expected_target: Vector2 = camera.unproject_position(game.aim_controller.get_target())
			max_target_error = maxf(max_target_error, focus._target_screen.distance_to(expected_target))
			var strokes: Dictionary = Arc.geometry(focus._screen_path, root.get_visible_rect())
			check(not strokes.overflow and not strokes.lines.is_empty(), mode + " actual estimate has drawable bounded strokes")
			if mode == "static" and frame > 0 and strokes.lines != prior_lines: static_changes += 1
			prior_lines = strokes.lines
		check(max_target_error == 0.0, mode + " actual target remains immediate")
		check(static_changes == 0, mode + " no clock-driven static drawing changes")
		rows.append({"scenario":mode,"frames":3*rate+1,"static_geometry_changes":static_changes if mode == "static" else null,"max_immediate_target_error_px":max_target_error,"solver_refreshes":focus.preview_solves-solves_before})
	prepare_rally()
	var target: Vector3 = game.aim_controller.get_target()
	var depth: float = -(camera.global_transform.affine_inverse() * target).z
	camera.near = depth + 1.0
	focus._update_presentation(clock_usec + 100000)
	check(not focus._presentation and not focus._drawing.visible, "near-plane-invalid target hides presentation immediately")
	camera.near = 0.05
	focus.cancel()
	check(not focus._presentation and not focus._drawing.visible, "cancel leaves no retained arc")
	var result := {"scope":"Actual game scene and estimator; separate proposed focus script instance unless --use-production. Frozen physics, synthetic times, no native raster/device claim.","rate":rate,"use_production":use_production,"checks":checks,"failures":failures,"records":rows}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ARC STYLE INTEGRATION: %d Hz, %d checks, %d failures" % [rate, checks, failures.size()])
	Input.action_release("ui_accept"); game.queue_free()
	for i in 3: await process_frame
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failures.is_empty() else 1)
