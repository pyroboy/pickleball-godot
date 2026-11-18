extends SceneTree







const Geometry = preload("res://scripts/paddle_clearance.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Styles = preload("res://scripts/serve_style.gd")
class LateFrame extends Node:
	signal finished
	var simulation_time: = 0.0
	func _physics_process(delta: float) -> void : simulation_time += delta
	func _process(_delta: float) -> void :
		create_tween().tween_callback( func(): finished.emit())
var game
var metrics
var late
var checks: = 0
var results: Array = []
var issues: Array[String] = []
var case_name: = ""
var controller
var start_hash: = ""
var entry_details: Array = []
var source_hashes: = {}
func script_hash(filename: String) -> String:
	var path: = "res://scripts/" + filename
	if not FileAccess.file_exists(path): path = path.trim_suffix(".gd") + ".gdc"
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"

func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok and not issues.has(message): issues.append(message)
func tick() -> void :
	await physics_frame
	await late.finished
func reset(team: int, style: int = 0) -> void :
	if is_instance_valid(game): game.queue_free(); await process_frame
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame; await late.finished
	metrics.game = game
	controller = game.between_point_controller
	for key in ["ui_accept", "move_left", "move_right", "move_up", "move_down"]: Input.action_release(key)
	game.set_physics_process(false)
	game.game_serve.set_process(false)
	game.input_handler.set_process(false)
	game._reset_match()
	game.serving_team = team
	game.game_serve.selected_serve_style = style
	game._reset_ball()
	for p in [game.player_left, game.player_right]:
		p.hitting.clear_charge_visual()
		p._between_pose_active = false
		p._between_last_pose = null
		p.posture.transition_pose_blend = null
		p.leg_ik.feet_initialized = false
		p.current_velocity = Vector3.ZERO
		p.velocity = Vector3.ZERO
	game.player_right.set_ai_movement_enabled(false)
	game.game_serve.cleanup()
	game.game_serve._prepare_server(0.0)
	await tick()
func snapshot() -> Array:
	var values: Array = []
	for p in [game.player_left, game.player_right]:
		values.append({"paddle": p.paddle_node.global_transform, "wrist": p.left_arm_node.hand_mesh.global_transform * p.left_arm_node.articulated_hand.wrist_socket, "pose": p.posture.transition_pose_blend, "serving": p.hitting.serving_visual_active, "follow": p.hitting.is_in_follow_through, "charge": p.hitting.charge_visual_active})
	return values
func sample(frame: int) -> void :
	metrics.sample_time_seconds = late.simulation_time
	var row: Dictionary = metrics._measure_body(game.player_left)
	row.frame = frame
	row.opponent = metrics._measure_body(game.player_right)
	metrics.samples.append(row)
func finish_case() -> void :
	metrics._assert_live_geometry()
	for issue in metrics.current.issues: check(false, issue)
	var max_step: = 0.0
	var max_wrist_step: = 0.0
	for index in range(1, metrics.samples.size()):
		var previous = metrics.samples[index - 1]
		var current = metrics.samples[index]
		for team in [0, 1]:
			var a = previous if team == 0 else previous.opponent
			var b = current if team == 0 else current.opponent
			max_step = maxf(max_step, b.orientations.paddle_step_deg)
			var aw = Vector3(a.arms[1].visible_wrist[0], a.arms[1].visible_wrist[1], a.arms[1].visible_wrist[2])
			var bw = Vector3(b.arms[1].visible_wrist[0], b.arms[1].visible_wrist[1], b.arms[1].visible_wrist[2])
			max_wrist_step = maxf(max_wrist_step, aw.distance_to(bw))
	check(max_step <= 900.0 / Engine.physics_ticks_per_second + 0.05, "paddle frame step %.3f exceeds 900deg/s bound" % max_step)
	var row: = {"case": case_name, "passed": issues.is_empty(), "issues": issues.duplicate(), "geometry": metrics.current.geometry, "max_paddle_step_deg": max_step, "max_support_wrist_step_m": max_wrist_step, "frames": metrics.samples.size(), "entry_owners": entry_details.duplicate(true)}
	results.append(row)
	print("[HANDOFF] ", case_name, " passed=", row.passed, " issues=", issues)
func handoff(winner: int, fault_mode: String = "") -> void :
	metrics.samples.clear()
	metrics.current = {"issues": [], "hits": [], "opponent_hits": []}
	var before: Array = snapshot()
	entry_details = []
	for p in [game.player_left, game.player_right]:
		var pose: PostureDefinition = p.posture.transition_pose_blend
		var entry: = {"team": p.player_num, "pose_name": pose.display_name if pose else "NULL", "pose_id": pose.posture_id if pose else -1, "serving": p.hitting.serving_visual_active, "charge": p.hitting.charge_visual_active, "follow": p.hitting.is_in_follow_through, "ai_guard": p._ai_guard_active, "ai_incoming": p._ai_incoming_active, "ai_charge": p.ai_is_charging, "ai_override": p.ai_brain.incoming_pose_override != null, "runtime_name": p.get_runtime_posture_def().display_name, "runtime_basis_error_deg": rad_to_deg(Path.paddle_basis(p, p.get_runtime_posture_def()).get_rotation_quaternion().angle_to(p.paddle_node.global_basis.get_rotation_quaternion())), "paddle_euler": str(p.paddle_node.global_basis.get_euler() * 180 / PI), "pose_basis_error_deg": rad_to_deg(Path.paddle_basis(p, pose).get_rotation_quaternion().angle_to(p.paddle_node.global_basis.get_rotation_quaternion())) if pose else -1}
		entry_details.append(entry)
	if case_name == "rally_team0_ready": print("[ENTRY OWNER] ", entry_details)
	sample(-1)
	var before_score: Array = [game.score_left, game.score_right]
	if fault_mode == "SERVICE_ZONE": game.game_serve.perform_serve(0.5)
	elif fault_mode == "SERVICE_CONTACT": game.game_serve._launch_pending_serve()
	else: game._on_point_scored(winner)
	check(controller.is_active(), "point-score enters retrieval")
	for team in [0, 1]:
		var p = [game.player_left, game.player_right][team]
		check(p.paddle_node.global_transform.is_equal_approx(before[team].paddle), "P%d synchronous cleanup changed displayed paddle" % team)
		check(controller.support_hand_target_for(team).distance_to(before[team].wrist) < 0.0001, "P%d support snapshot differs from displayed wrist" % team)
		var entry: PostureDefinition = controller.pose_for(team)
		check(entry != null, "P%d missing entry pose" % team)
		if entry != null:
			var q: Quaternion = Path.paddle_basis(p, entry).get_rotation_quaternion()
			check(q.angle_to(before[team].paddle.basis.get_rotation_quaternion()) < 0.002, "P%d entry pose orientation differs from displayed paddle" % team)
	var settled_score: Array = [game.score_left, game.score_right]
	var generation: int = game._point_reset_generation
	game.set_physics_process(true)
	game.game_serve.set_process(true)
	for frame in range(int(ceil(0.5 * Engine.physics_ticks_per_second))):
		await tick()
		sample(frame)
		check([game.score_left, game.score_right] == settled_score, "extra score during handoff")
		check(game._point_reset_generation == generation, "unexpected reset during handoff")
		check( not game.ball.is_in_play, "live ball during handoff")
	check(controller.phase != "SETTLE", "SETTLE completes at original duration")
	finish_case()
func held_cases() -> void :
	for team in [0, 1]:
		for style in range(7):
			for charge in [0.0, 0.5, 1.0]:
				for sideout in [false, true]:
					case_name = "held_team%d_style%d_charge%.1f_sideout%s" % [team, style, charge, sideout]
					issues = []
					await reset(team, style)
					game.game_serve._prepare_server(charge)
					await tick()
					await handoff(1 - team if sideout else team)
func release_cases() -> void :
	for team in [0, 1]:
		for style in range(7):
			var phases: Array = ["RELEASE", "SWING", "FOLLOW"]
			if Styles.is_drop(style): phases.append("BOUNCE")
			for phase in phases:
				case_name = "delivery_team%d_style%d_%s" % [team, style, phase]
				issues = []
				await reset(team, style)
				game.game_serve.perform_serve(0.6)
				var observed: = false
				for frame in range(150):
					await tick()
					var pending: Dictionary = game.game_serve._pending_release
					if phase == "FOLLOW" and not game.game_serve._follow_through.is_empty(): observed = true;break
					if not pending.is_empty() and (pending.phase == phase or (phase == "RELEASE" and pending.phase == "DROP")): observed = true;break
				check(observed, "requested delivery phase never presented")
				if observed: await handoff(1 - team)
				else: metrics.samples.clear();metrics.current = {"issues": [], "hits": [], "opponent_hits": []};sample(-1);finish_case()
func rally_cases() -> void :
	for team in [0, 1]:
		for mode in ["incoming", "charge", "cancel", "miss", "ready"]:
			case_name = "rally_team%d_%s" % [team, mode]
			if OS.get_environment("HANDOFF_CASE") != "" and OS.get_environment("HANDOFF_CASE") != case_name: continue
			issues = []
			await reset(0)
			game.game_serve.cleanup()
			for p in [game.player_left, game.player_right]:
				p.hitting.clear_charge_visual()
				p.global_position = Vector3(0, p.ground_y, 3.2 if p.player_num == 0 else -3.2)
				p.leg_ik.feet_initialized = false
			game._set_game_state(game.GameState.PLAYING)
			var p = game.player_left if team == 0 else game.player_right
			var b = game.ball
			b.reset_rally_state();b.both_bounces_complete = true;b.serving_side_bounced = true;b.receiving_side_bounced = true
			b.global_position = p.global_position + p._get_forward_axis() * 1.7 + p._get_forehand_axis() * 0.42 + Vector3.UP * 0.3
			b.linear_velocity = - p._get_forward_axis() * 4.0 + Vector3.UP * 1.5
			b.freeze = false;b.last_hit_by = 1 - team;b.is_in_play = true;b.flight_id += 1
			await tick(); await tick()
			if mode in ["charge", "cancel"]:
				p.hitting.set_serve_charge_visual(0.6)
				await tick()
				if mode == "cancel": p.hitting.clear_charge_visual(); await tick()
			elif mode == "miss":
				for frame in range(18): await tick()
			elif mode == "ready":
				b.last_hit_by = team;b.linear_velocity = p._get_forward_axis() * 4
				for frame in range(12): await tick()
			await handoff(1 - team)
func fault_cases() -> void :
	for team in [0, 1]:
		case_name = "actual_service_zone_fault_team%d" % team
		issues = []
		await reset(team, 2)
		var p = game.player_left if team == 0 else game.player_right
		p.global_position.x *= -1
		game.game_serve.cleanup()
		game.game_serve._prepare_server(0.5)
		await tick()
		await handoff(1 - team, "SERVICE_ZONE")
		case_name = "actual_service_contact_foot_fault_team%d" % team
		issues = []
		await reset(team, 0)
		game.game_serve.perform_serve(0.6)
		var reached: = false
		for frame in range(100):
			await tick()
			if not game.game_serve._pending_release.is_empty() and game.game_serve._pending_release.phase == "SWING": reached = true;break
		check(reached, "contact foot-fault fixture reached swing")
		if reached:
			p = game.player_left if team == 0 else game.player_right

			for leg in [p.right_leg_node, p.left_leg_node]: leg.foot_mesh.global_position.z += -0.5 if team == 0 else 0.5
			check( not game.game_serve._legal_service_feet(p, team), "contact foot-fault fixture has illegal actual shoe")
			await handoff(1 - team, "SERVICE_CONTACT")
		else: metrics.samples.clear();metrics.current = {"issues": [], "hits": [], "opponent_hits": []};sample(-1);finish_case()
func run() -> void :
	var requested_group: String = OS.get_environment("HANDOFF_GROUP")
	if requested_group not in ["", "held", "delivery", "rally", "fault"] or (OS.get_environment("HANDOFF_CASE") != "" and requested_group != "rally"):
		push_error("Invalid HANDOFF_GROUP, or HANDOFF_CASE used outside the rally group")
		quit(2)
		return
	create_timer(180).timeout.connect( func(): push_error("Handoff regression timeout");quit(2))
	start_hash = script_hash("between_point_controller.gd")
	for file in ["between_point_controller.gd", "game_serve.gd", "game.gd", "player.gd", "player_paddle_posture.gd", "posture_definition.gd", "base_pose_definition.gd", "drive_serve_motion.gd"]: source_hashes[file] = script_hash(file)
	seed(77811)
	game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame; await process_frame
	late = LateFrame.new();late.process_priority = 20000;root.add_child(late)
	metrics = load("res://scripts/debug/pose_simulation_review.gd").new();metrics.game = game;metrics.surface = Geometry.sample_head_surface()
	controller = game.between_point_controller
	var group: String = OS.get_environment("HANDOFF_GROUP")
	var expected: = 0
	if group in ["", "held"]: await held_cases();expected += 84
	if group in ["", "delivery"]: await release_cases();expected += 50
	if group in ["", "rally"]: await rally_cases();expected += 10
	if group in ["", "fault"]: await fault_cases();expected += 4
	if OS.get_environment("HANDOFF_CASE") != "": expected = 1
	var failed: = 0
	if results.size() != expected: failed += 1;push_error("Incomplete handoff case coverage")
	for result in results: if not result.passed: failed += 1
	var end_hashes: = {}
	for file in source_hashes: end_hashes[file] = script_hash(file)
	if source_hashes != end_hashes: failed += 1;push_error("Source changed during final handoff audit")
	var report = {"source_hashes_at_end": end_hashes, "source_hashes": source_hashes, "source_hash": start_hash, "source_hash_at_end": script_hash("between_point_controller.gd"), "checks": checks, "cases": results.size(), "failed_cases": failed, "physics_hz": Engine.physics_ticks_per_second, "rendered": false, "fixture_note": "Production pose/preparation methods with top-level charge/auto-serve timers stopped during setup; production _on_point_scored and entire live SceneTree during handoff, final post-tween geometry sampled through0.50s. No player touchscreen claim.", "results": results}
	var output: = OS.get_environment("HANDOFF_OUT")
	if output == "": output = "user://point_end_handoff"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var filename: = "real-point-end-handoff" + ("-" + group if group != "" else "") + ".json"
	var file = FileAccess.open(output.path_join(filename), FileAccess.WRITE)
	if file == null:
		failed += 1
		push_error("Could not save real point-end handoff report")
	else:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("REAL POINT END HANDOFF: ", checks, " checks; ", results.size(), " cases; ", failed, " failed cases")
	metrics.free();game.queue_free();late.queue_free(); await process_frame
	quit(0 if failed == 0 else 1)
