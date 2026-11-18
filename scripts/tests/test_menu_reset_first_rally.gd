extends SceneTree





const Geometry = preload("res://scripts/paddle_clearance.gd")
class LateFrame extends Node:
	signal finished
	var simulation_time: = 0.0
	func _physics_process(delta: float) -> void :
		simulation_time += delta
	func _process(_delta: float) -> void :
		create_tween().tween_callback( func(): finished.emit())
var game
var metrics
var late
var checks: = 0
var results: Array = []
var issues: Array[String] = []
var serve_count: = 0
var ai_return_count: = 0
var source_hashes: Dictionary = {}
var fast_hands_only: = false
var failed_limbs_only: = false
func asset_hash(path: String) -> String:
	var actual: = path
	if not FileAccess.file_exists(actual):
		if FileAccess.file_exists(path + ".remap"):
			var remap: = ConfigFile.new()
			if remap.load(path + ".remap") == OK: actual = str(remap.get_value("remap", "path", ""))
		elif path.ends_with(".gd"): actual = path.trim_suffix(".gd") + ".gdc"
	return FileAccess.get_sha256(actual) if FileAccess.file_exists(actual) else "missing"

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok and not issues.has(label): issues.append(label)
func tick(): await physics_frame; await late.finished
func press_named(container: Node, text: String) -> bool:
	for child in container.get_children():
		if child is Button and child.text == text:
			child.pressed.emit()
			return true
	return false
func title_match() -> bool:
	Input.action_release("ui_accept")
	if is_instance_valid(game): game.queue_free(); await process_frame
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title);current_scene = title
	await process_frame
	title._play.pressed.emit()
	var deadline: = Time.get_ticks_msec() + 15000
	while current_scene == title and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		await process_frame
	check(current_scene != title and current_scene != null, "Play loads the real game within15seconds")
	if current_scene == title or current_scene == null: return false
	game = current_scene;metrics.game = game
	serve_count = 0;ai_return_count = 0
	game.game_serve.serve_launched.connect( func(_side): serve_count += 1)
	game.ball.hit_by_paddle.connect( func(side): if side == 1: ai_return_count += 1)
	await tick(); await tick()
	seed(77811)
	return true
func open_practice() -> bool:
	var pause = root.get_node("PauseController")
	pause.open(); await process_frame
	var opened: bool = is_instance_valid(pause._menu) and press_named(pause._menu._content, "Practice drills")
	check(opened, "Pause menu exposes Practice drills")
	if not opened: return false
	await process_frame
	check(game.practice_panel._picker_open, "Practice picker opened")
	return game.practice_panel._picker_open
func start_sampling():
	metrics.samples.clear()
	metrics.current = {"issues": [], "hits": [], "opponent_hits": []}
func _pose_id(pose) -> int:
	return pose.posture_id if pose != null else -1
func _owner_state(player) -> Dictionary:
	var human = player.posture.human_contact
	var brain = player.ai_brain
	return {"is_ai": player.is_ai, "paddle_posture": player.paddle_posture, "transition_pose": _pose_id(player.posture.transition_pose_blend), "charge_visual_active": player.hitting.charge_visual_active, "serving_visual_active": player.hitting.serving_visual_active, "follow_through": player.hitting.is_in_follow_through, "swing_tween_present": player.hitting.paddle_swing_tween != null, "human_phase": human.phase if human else -1, "human_elapsed": human.elapsed if human else 0.0, "human_charge": human.charge_ratio if human else 0.0, "human_contact_posture": human.contact.get("posture", -1) if human else -1, "human_visual_pose": _pose_id(human.visual_pose) if human else -1, "human_swing_pose": _pose_id(human.swing_def) if human else -1, "human_swing_flight": human.swing_flight_id if human else -1, "ai_state": brain.ai_state if brain else -1, "ai_charging": player.ai_is_charging, "ai_charge_time": player.ai_charge_time, "ai_desired_pose": brain.ai_desired_posture if brain else -1, "ai_incoming_override": _pose_id(brain.incoming_pose_override) if brain else -1, "ai_charge_pose": brain._charge_posture if brain else -1, "ai_reach_pose": _pose_id(brain.ai_reach_pose) if brain else -1}
func _worst_rotation_pairs() -> Dictionary:
	var pairs: Dictionary = {}
	for index in range(1, metrics.samples.size()):
		var previous: Dictionary = metrics.samples[index - 1]
		var current: Dictionary = metrics.samples[index]
		for actor in ["blue", "red"]:
			var sample: Dictionary = current if actor == "blue" else current.opponent
			for channel in ["hand", "paddle"]:
				var key: String = actor + "_" + channel
				var step: float = sample.orientations[channel + "_step_deg"]
				if not pairs.has(key) or step > pairs[key].step_deg:


					pairs[key] = {"actor": actor, "channel": channel, "step_deg": step, "previous": previous, "current": current}
	return pairs
func record(frame: int):
	var sampled_usec: int = Time.get_ticks_usec()
	metrics.sample_time_seconds = late.simulation_time
	var sample: Dictionary = metrics._measure_body(game.player_left)
	sample.frame = frame;sample.opponent = metrics._measure_body(game.player_right)
	sample.owner_state = _owner_state(game.player_left)
	sample.opponent.owner_state = _owner_state(game.player_right)
	sample.context = {"physics_frame": Engine.get_physics_frames(), "process_frame": Engine.get_process_frames(), "simulation_time": late.simulation_time, "sampled_usec": sampled_usec, "time_scale": Engine.time_scale, "game_state": game.game_state, "serving_team": game.serving_team, "input_charging": game.input_handler.serve_is_charging, "input_charge_time": game.input_handler.serve_charge_time, "flight_id": game.ball.flight_id, "ball_in_play": game.ball.is_in_play, "last_hit_by": game.ball.last_hit_by, "bounces": game.ball.bounces_since_last_hit, "ball_velocity": metrics._v(game.ball.linear_velocity), "practice_mode": game.practice_launcher.drill_mode, "demo_enabled": game.practice_launcher.demo_enabled}
	metrics.samples.append(sample)
func finish_sampling(label: String):
	metrics._assert_live_geometry()
	for problem in metrics.current.issues: check(false, problem)
	var minimum: Dictionary = metrics.current.geometry.minimum_clearances.limb
	var row = {"case": label, "passed": issues.is_empty(), "issues": issues.duplicate(), "samples": metrics.samples.size(), "geometry": metrics.current.geometry, "critical_limb_frame": metrics.samples[int(minimum.frame)] if int(minimum.frame) >= 0 else {}, "critical_rotation_pairs": _worst_rotation_pairs(), "serve_count": serve_count, "ai_return_count": ai_return_count, "loaded_game_sha256": game.get_script().source_code.sha256_text()}
	results.append(row)


	var checkpoint_dir: String = OS.get_environment("MENU_RESET_OUT")
	if checkpoint_dir == "": checkpoint_dir = "user://menu_reset_qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(checkpoint_dir))
	var checkpoint = FileAccess.open(checkpoint_dir.path_join("case_%02d.json" % results.size()), FileAccess.WRITE)
	if checkpoint:
		checkpoint.store_string(JSON.stringify(row, "  "));checkpoint.close()
	else:
		check(false, "Could not save menu case checkpoint")
		row.passed = false;row.issues = issues.duplicate()
	print("MENU RESET FIRST RALLY: ", label, " passed=", row.passed, " issues=", issues, " serves=", serve_count, " ai_returns=", ai_return_count)
func _selected_case(label: String) -> bool:
	if not failed_limbs_only: return true
	return label.contains("return to match") or label.begins_with("Watch wide-dink") or label.begins_with("Watch crosscourt") and label.contains("Repeat")
func observe_practice(label: String):
	var capture: bool = _selected_case(label)
	if capture: start_sampling()
	for frame in range(180):
		await tick()
		if capture:
			record(frame)
			check(game.practice_launcher.is_active, label + " keeps practice active")
	if capture:
		check(game.practice_launcher.best_exchange_count >= 2, label + " produces at least two real exchange contacts")
		finish_sampling(label)
func ordinary_serve(label: String):
	start_sampling()
	var serves_before: = serve_count
	var returns_before: = ai_return_count
	Input.action_press("ui_accept")
	for frame in range(18): await tick();record(frame)
	Input.action_release("ui_accept")
	var observed: = false
	for frame in range(18, 438):
		await tick();record(frame)
		if ai_return_count > returns_before: observed = true;break
		if game.game_state == game.GameState.POINT_SCORED: break
	check(serve_count > serves_before, label + " normal SPACE input launches physical serve")
	check(observed, label + " first AI paddle return arrives")
	finish_sampling(label)
func run():
	fast_hands_only = OS.get_cmdline_user_args().has("--fast-hands-only")
	failed_limbs_only = OS.get_cmdline_user_args().has("--failed-limbs-only")
	if fast_hands_only and failed_limbs_only:
		push_error("Choose one menu diagnostic filter");quit(2);return
	create_timer(180).timeout.connect( func(): push_error("Menu reset first-rally timeout");quit(2))
	for filename in ["game.gd", "practice_launcher.gd", "human_contact_controller.gd", "drive_serve_motion.gd", "incoming_ready_motion.gd", "player_paddle_posture.gd"]:
		source_hashes["res://scripts/" + filename] = asset_hash("res://scripts/" + filename)
	source_hashes["res://scripts/debug/pose_simulation_review.gd"] = asset_hash("res://scripts/debug/pose_simulation_review.gd")
	source_hashes["res://scripts/tests/test_menu_reset_first_rally.gd"] = asset_hash("res://scripts/tests/test_menu_reset_first_rally.gd")
	source_hashes["res://data/postures/05_low_forehand.tres"] = asset_hash("res://data/postures/05_low_forehand.tres")
	late = LateFrame.new();late.process_priority = 20000;late.process_mode = Node.PROCESS_MODE_ALWAYS;root.add_child(late)
	metrics = load("res://scripts/debug/pose_simulation_review.gd").new();metrics.surface = Geometry.sample_head_surface()
	issues = []
	if not fast_hands_only and not failed_limbs_only:
		if not await title_match(): quit(2);return
		await ordinary_serve("Title Play / first ordinary serve and AI return")
	var captions: Array = ["Watch fast-hands demo"] if fast_hands_only else ["Watch crosscourt dink demo", "Watch fast-hands demo", "Watch wide-dink recovery demo"]
	for caption in captions:
		issues = []
		if not await title_match(): quit(2);return
		if not await open_practice(): quit(2);return
		check(press_named(game.practice_panel._content, caption), "named practice demo button exists")
		check( not paused, "Practice starts with normal simulation resumed")
		await observe_practice(caption + " / initial menu start")
		issues = []
		if not await open_practice(): quit(2);return
		check(press_named(game.practice_panel._content, "Repeat current drill"), "Repeat current drill button exists")
		await observe_practice(caption + " / real Repeat button")
		if fast_hands_only: continue
		issues = []
		if not await open_practice(): quit(2);return
		check(press_named(game.practice_panel._content, "Return to match"), "Return to match button exists")
		check( not game.practice_launcher.is_active and game.game_state == game.GameState.WAITING, "Return restores a waiting normal match")
		await ordinary_serve(caption + " / return to match and first AI return")
	var failed: = 0
	for row in results: if not row.passed: failed += 1
	var expected_cases: int = 2 if fast_hands_only else (6 if failed_limbs_only else 10)
	if results.size() != expected_cases: failed += 1;push_error("Incomplete menu reset case coverage")
	var ending: Dictionary = {}
	for path in source_hashes: ending[path] = asset_hash(path)
	if source_hashes != ending: failed += 1;push_error("Source changed during menu reset test")
	var report = {"diagnostic_filter": "fast_hands_initial_repeat" if fast_hands_only else ("failed_limb_routes" if failed_limbs_only else "full"), "expected_cases": expected_cases, "checks": checks, "cases": results.size(), "failed_cases": failed, "source_hashes": source_hashes, "source_hashes_at_end": ending, "fixture": "Real Title Play, Pause Practice, named demo/Repeat/Return button signals; normal Input action serve. No renderer setup, actor teleport, pose/owner/cache writes, ball placement, or direct practice/reset calls. Post-tween geometry from first presented frame.", "results": results}
	var output: = OS.get_environment("MENU_RESET_OUT")
	if output == "": output = "user://menu_reset_qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file = FileAccess.open(output.path_join("menu-reset-first-rally.json"), FileAccess.WRITE)
	if file == null:
		failed += 1
		push_error("Could not save menu reset first-rally report")
	else:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("MENU RESET FIRST RALLY TOTAL: ", checks, " checks; ", results.size(), " cases; ", failed, " failed")
	Input.action_release("ui_accept")
	metrics.free();game.queue_free();late.queue_free(); await process_frame
	await preload("res://scripts/tests/audio_teardown.gd").drain(self)
	quit(0 if failed == 0 else 1)
