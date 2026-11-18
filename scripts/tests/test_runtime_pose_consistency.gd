extends SceneTree

const PaddleSize = preload("res://scripts/paddle_dimensions.gd")
const Path = preload("res://scripts/stroke_swing_path.gd")
const Body = preload("res://scripts/stroke_body_pose.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void : call_deferred("run")
func check(value: bool, message: String) -> void :
	checks += 1
	if not value: failures.append(message)

func run() -> void :
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	create_timer(30).timeout.connect( func(): quit(2))
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await physics_frame
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.input_handler.set_process(false)
	game.ball.set_physics_process(false)
	for player in [game.player_left, game.player_right]:
		player.set_process(false)
		player.set_physics_process(false)
		player.hitting.set_process(false)
		player.hitting.clear_charge_visual()
		player.current_velocity = Vector3.ZERO
		player.is_ai = true
		player.posture.human_contact = null
		player.posture.transition_pose_blend = null
		player.ai_state = player.AIState.INTERCEPT_POSITION
		var head = player.body_pivot.get_node("TorsoMesh/HeadMesh")
		for eye in head.get_children():
			check(eye.position.dot(player._get_forward_axis()) > 0.1, "eyes must be on front of head side%d" % player.player_num)
		for def in PostureLibrary.instance().all_definitions():
			var tag: String = "%s side%d" % [def.display_name, player.player_num]
			player.posture.force_posture_update(def)
			player.ai_desired_posture = def.posture_id
			game.ball.global_position = player.global_position + def.resolve_paddle_offset(player._get_forehand_axis(), player._get_forward_axis()) + player._get_forward_axis() * 2.0
			game.ball.last_hit_by = 1 - player.player_num
			game.ball.is_in_play = true
			player.posture.update_paddle_tracking(true)
			var expected: Transform3D = Path.world_transform(player, def)
			var actual: Transform3D = player.paddle_node.global_transform
			check(actual.is_equal_approx(expected), tag + " tracking differs from authored world transform")
			var before_head: Vector3 = PaddleReach.head_world(player)
			var before_basis: Basis = actual.basis

			player._process(1.0 / 60.0)
			check(player.paddle_node.global_transform.basis.is_equal_approx(before_basis), tag + " body update changes paddle orientation")
			check(PaddleReach.head_world(player).distance_to(before_head) < 0.04, tag + " body update displaces contact center")
			player.posture.force_posture_update(def)
			player.arm_ik.update_arm_ik(1.0 / 60.0, def)
			var grip: Vector3 = player.paddle_node.to_global(PaddleSize.MAIN_GRIP_OFFSET)
			check(player.right_arm_node.hand_pivot.global_position.distance_to(grip) < 0.025, tag + " dominant hand loses grip")
			var ghost = player.posture.posture_ghosts.get(def.posture_id)
			if ghost:
				player.posture._place_ghost_pose(ghost, def)
				check((ghost.global_transform * PaddleSize.HEAD_OFFSET).distance_to(expected * PaddleSize.HEAD_OFFSET) < 0.001, tag + " ghost head differs from paddle head")
				check(ghost.global_transform.basis.orthonormalized().is_equal_approx(expected.basis), tag + " ghost orientation differs from editor")
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("RUNTIME POSE CONSISTENCY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
