extends SceneTree

class LateFrame extends Node:
	signal presented
	func _process(_delta: float) -> void : create_tween().tween_callback( func(): presented.emit())
const AudioTeardown = preload("res://scripts/tests/audio_teardown.gd")
var checks: = 0
var failures: Array[String] = []
var rows: Array = []
var captures: Array = []
var capture_dir: = ""
var close_view: SubViewport
var close_camera: Camera3D
func _initialize() -> void : call_deferred("run")
func check(ok: bool, message: String) -> void :
	checks += 1
	if not ok: failures.append(message)
func run() -> void :
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty():
		if DisplayServer.get_name() == "headless": push_error("Graphical capture requires renderer");quit(2);return
		DirAccess.make_dir_recursive_absolute(capture_dir)
		root.size = Vector2i(720, 1280);root.content_scale_size = Vector2i(720, 1280)
		var pause = root.get_node("PauseController")
		if root.focus_exited.is_connected(pause._on_window_focus_exited): root.focus_exited.disconnect(pause._on_window_focus_exited)
		if root.focus_entered.is_connected(pause._on_window_focus_entered): root.focus_entered.disconnect(pause._on_window_focus_entered)
	var game = load("res://scenes/game.tscn").instantiate();root.add_child(game);current_scene = game
	await process_frame; await physics_frame
	if not capture_dir.is_empty():
		close_view = SubViewport.new();close_view.size = Vector2i(512, 512);close_view.world_3d = game.get_world_3d();close_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS;root.add_child(close_view)
		close_camera = Camera3D.new();close_camera.projection = Camera3D.PROJECTION_ORTHOGONAL;close_camera.size = 2.4;close_view.add_child(close_camera);close_camera.current = true
	var late: = LateFrame.new();late.process_priority = 10000;root.add_child(late)
	for team in [0, 1]:
		for far in [true, false]:
			var tag: = "%s_%s" % [team, "far" if far else "near"]
			game.serving_team = team;game.score_left = 0;game.score_right = 0;game.match_over = false;game._reset_ball()
			var player = game.player_left if team == 0 else game.player_right
			player.global_position = Vector3(0, player.ground_y, (6.1 if far else 3.4) * (1 if team == 0 else -1))
			player.leg_ik.feet_initialized = false;player._process(0.0)
			var ball_pos: = Vector3(0.2, Ball.FLOOR_Y + Ball.BALL_RADIUS, (1.0 if far else 3.0) * (1 if team == 0 else -1))
			game.ball.global_position = ball_pos;game.ball.linear_velocity = Vector3.ZERO
			game._on_point_scored(team)
			var controller = game.between_point_controller
			var max_speed: = 0.0; var max_near_speed: = 0.0; var max_acceleration: = 0.0; var max_root_step: = 0.0
			var saw_bend: = false; var planted_at_bend: = false; var saw_run: = false; var saw_walk: = false
			var prior_speed: = 0.0; var previous: Vector3 = player.global_position; var prior_phase: = ""
			var seen: Dictionary = {}; var max_foot_drift: = 0.0
			var foot_positions: Array[Vector3] = [player.leg_ik.right_foot_smooth, player.leg_ik.left_foot_smooth]
			var foot_serials: Array[int] = [player.leg_ik.right_contact_serial, player.leg_ik.left_contact_serial]
			for frame in range(1050):
				await physics_frame; await late.presented
				if not controller.is_active(): break
				var speed: float = Vector2(player.current_velocity.x, player.current_velocity.z).length()
				max_root_step = maxf(max_root_step, previous.distance_to(player.global_position));previous = player.global_position
				if controller.phase == "APPROACH" and controller.retriever == team:
					var distance: float = player.global_position.distance_to(controller._targets[team])
					max_speed = maxf(max_speed, speed)
					if distance < 0.8: max_near_speed = maxf(max_near_speed, speed)
					if prior_phase == "APPROACH": max_acceleration = maxf(max_acceleration, (speed - prior_speed) * 60)
					if player.leg_ik._run_active and speed > 3.2: saw_run = true
					if distance < 0.8 and speed > 0.12 and speed < 1.35 and not player.leg_ik._run_active: saw_walk = true
				if controller.phase == "BEND" and not saw_bend:
					saw_bend = true
					planted_at_bend = speed < 0.06 and player.leg_ik.right_foot_locked and player.leg_ik.left_foot_locked and not player.leg_ik._run_active
				var leg = player.leg_ik
				var now: Array[Vector3] = [leg.right_foot_smooth, leg.left_foot_smooth]
				var serials: Array[int] = [leg.right_contact_serial, leg.left_contact_serial]
				var locked: Array[bool] = [leg.right_foot_locked, leg.left_foot_locked]
				for side in [0, 1]:
					if locked[side] and serials[side] == foot_serials[side]: max_foot_drift = maxf(max_foot_drift, now[side].distance_to(foot_positions[side]))
				foot_positions = now;foot_serials = serials
				var marker: String = controller.phase
				if marker == "APPROACH":
					var distance: float = player.global_position.distance_to(controller._targets[team])
					marker = "run" if speed > 3.6 else ("walking_approach" if distance < 0.8 and speed < 1.35 and speed > 0.12 else ("decelerating" if distance < 2.0 and speed > 1.4 else "accelerating"))
				if not capture_dir.is_empty() and not seen.has(marker):
					seen[marker] = true
					await capture_marker(game, player, tag, marker)
				prior_speed = speed;prior_phase = controller.phase
			check( not controller.is_active() and game.game_state == game.GameState.WAITING, tag + " did not finish to service")
			check( not controller.used_offscreen_helper and controller.last_result != "TIMEOUT", tag + " escaped through helper/timeout")
			check(saw_bend and planted_at_bend, tag + " bend began before planted stop")
			check(max_near_speed <= 1.4, tag + " did not ease to walk near ball")
			check(max_acceleration <= 7.2, tag + " abrupt acceleration")
			check(max_root_step <= 0.085, tag + " root teleported/oversped")
			if far: check(max_speed > 3.6 and saw_run, tag + " never ran with actual gait")
			else: check(max_speed < 1.4, tag + " nearby pickup unnecessarily ran")
			check(saw_walk, tag + " no low-speed walking approach")
			check(max_foot_drift < 1e-05, tag + " planted foot dragged in world space")
			rows.append({"case": tag, "max_speed": max_speed, "max_near_speed": max_near_speed, "max_acceleration": max_acceleration, "max_root_step": max_root_step, "planted_at_bend": planted_at_bend, "saw_run": saw_run, "saw_walk": saw_walk, "result": controller.last_result, "pickup_gap": controller.pickup_contact_gap, "max_planted_foot_drift": max_foot_drift})
	game.queue_free(); await process_frame; await process_frame
	await AudioTeardown.drain(self)
	var f = FileAccess.open("/tmp/running-retrieval.json", FileAccess.WRITE);f.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": rows, "captures": captures}, "\t"));f.close()
	for failure in failures: push_error(failure)
	print("RUNNING RETRIEVAL: %d checks, %d failures" % [checks, failures.size()]);quit(0 if failures.is_empty() else 1)

func capture_marker(game, player, tag: String, marker: String) -> void :
	close_camera.global_position = player.global_position + player._get_forehand_axis() * 2.8 + player._get_forward_axis() * 2.0 + Vector3.UP * 0.55
	close_camera.look_at(player.global_position + Vector3.UP * 0.05)
	await RenderingServer.frame_post_draw
	var stem: = tag + "-" + marker.to_lower()
	root.get_texture().get_image().save_png(capture_dir.path_join(stem + ".png"))
	close_view.get_texture().get_image().save_png(capture_dir.path_join(stem + "-rig.png"))
	captures.append({"case": tag, "phase": marker, "time": game.between_point_controller.elapsed, "speed": player.current_velocity.length(), "root": player.global_position, "right_foot": player.leg_ik.right_foot_smooth, "left_foot": player.leg_ik.left_foot_smooth, "right_locked": player.leg_ik.right_foot_locked, "left_locked": player.leg_ik.left_foot_locked, "file": stem + ".png", "rig": stem + "-rig.png"})
