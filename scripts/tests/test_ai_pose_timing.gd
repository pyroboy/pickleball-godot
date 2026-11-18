extends SceneTree

const Path = preload("res://scripts/stroke_swing_path.gd")
var failures: Array[String] = []
var checks: = 0
func _initialize() -> void : call_deferred("run")
func check(ok: bool, label: String) -> void :
	checks += 1
	if not ok: failures.append(label)
func run() -> void :
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	var player = game.player_right
	var brain = player.ai_brain
	player.set_physics_process(false)
	game.rally_scorer.end_rally()
	game.game_state = game.GameState.PLAYING
	game.ball.freeze = true
	game.ball.is_in_play = true
	game.ball.last_hit_by = 0
	player.global_position = Vector3(0, player.ground_y, -3.0)
	brain.ai_desired_posture = player.PaddlePosture.LOW_FOREHAND
	var base: PostureDefinition = PostureLibrary.instance().get_def(brain.ai_desired_posture)
	brain.incoming_pose_override = PostureLibrary.instance().get_def(player.PaddlePosture.READY)
	game.ball.global_position = player.global_position + base.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis())
	brain.ai_predicted_contact_position = game.ball.global_position
	brain.ai_selected_contact_reachable = true
	brain.ai_selected_contact_time = 0.2
	var before: Quaternion = Path.paddle_basis(player, brain.incoming_pose_override).get_rotation_quaternion()
	brain.align_paddle_to_contact(1.0 / 60.0)
	var once: Quaternion = Path.paddle_basis(player, brain.incoming_pose_override).get_rotation_quaternion()
	var crouch: float = brain.incoming_pose_override.crouch_amount
	brain.align_paddle_to_contact(1.0 / 60.0)
	var twice: Quaternion = Path.paddle_basis(player, brain.incoming_pose_override).get_rotation_quaternion()
	check(rad_to_deg(before.angle_to(once)) <= 12.01, "AI prep keeps 720deg/s bound")
	check(rad_to_deg(once.angle_to(twice)) < 0.05, "second same-tick contact alignment adds no rotation")
	check(is_equal_approx(crouch, brain.incoming_pose_override.crouch_amount), "second same-tick alignment adds no body blend")
	await physics_frame
	brain.align_paddle_to_contact(1.0 / 60.0)
	var next: Quaternion = Path.paddle_basis(player, brain.incoming_pose_override).get_rotation_quaternion()
	check(rad_to_deg(twice.angle_to(next)) <= 12.01 and rad_to_deg(twice.angle_to(next)) > 0.1, "next physics tick continues bounded prep")
	print("AI POSE TIMING: %d checks, %d failures: %s" % [checks, failures.size(), failures])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
